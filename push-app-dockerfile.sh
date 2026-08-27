#!/usr/bin/env bash
# push-app-dockerfile.sh
# Crea Dockerfile para el servicio app (Node.js) en la raíz del repo
# y crea el .env desde .env.example

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RED='\033[0;31m'
RESET='\033[0m'

echo -e "${CYAN}=== App Dockerfile + .env ===${RESET}\n"

if [ ! -d ".git" ]; then
  echo "❌ Ejecuta desde la raíz del repo ServerSideTracking"
  exit 1
fi

git checkout main && git pull origin main --quiet
echo -e "✅ main actualizado\n"

# =============================================================
# COMMIT 1 — package.json en la raíz
# =============================================================
echo -e "${YELLOW}[1/3] package.json${RESET}"

cat > package.json << 'PKG_EOF'
{
  "name": "sst-pro-collector",
  "version": "1.0.0",
  "description": "Santamaría Collection — SST Pro Collector",
  "main": "server.js",
  "scripts": {
    "start": "node server.js",
    "dev": "nodemon server.js"
  },
  "dependencies": {
    "cookie-parser": "^1.4.6",
    "express": "^4.18.2",
    "uuid": "^9.0.0"
  }
}
PKG_EOF

git add package.json
git commit -m "feat(app): añadir package.json — dependencias Node.js del collector

- express 4.18.2
- uuid 9.0.0
- cookie-parser 1.4.6 (para leer _fbp y _fbc)"

echo -e "${GREEN}✅ Commit 1/3 OK${RESET}\n"

# =============================================================
# COMMIT 2 — server.js (entry point) + Dockerfile app
# =============================================================
echo -e "${YELLOW}[2/3] server.js + Dockerfile (app)${RESET}"

cat > server.js << 'SERVER_EOF'
/**
 * server.js
 * Santamaría Collection — SST Pro
 * Entry point del collector Node.js
 */

const express      = require('express');
const cookieParser = require('cookie-parser');
const collector    = require('./codigo/collector-endpoint');
const webhook      = require('./codigo/meta-leadform-webhook');

const app  = express();
const PORT = process.env.PORT || 3000;

// Middlewares
app.use(express.json({
  verify: (req, res, buf) => { req.rawBody = buf; } // para verificación firma Meta
}));
app.use(cookieParser());

// Rutas
app.use('/api', collector);
app.use('/webhook', webhook);

// Health global
app.get('/health', (req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

app.listen(PORT, () => {
  console.log(`[Server] SST Pro collector corriendo en puerto ${PORT}`);
});
SERVER_EOF

cat > Dockerfile << 'DOCKER_APP_EOF'
FROM node:20-slim

WORKDIR /app

# Instalar dependencias primero (aprovecha cache de Docker)
COPY package.json .
RUN npm install --omit=dev

# Copiar código
COPY server.js .
COPY codigo/ ./codigo/

EXPOSE 3000

CMD ["node", "server.js"]
DOCKER_APP_EOF

git add server.js Dockerfile
git commit -m "feat(app): añadir server.js y Dockerfile para servicio app Node.js

- server.js: entry point con express, cookie-parser, rutas /api y /webhook
- req.rawBody preservado para verificación de firma HMAC del webhook Meta
- Dockerfile: node:20-slim, npm install --omit=dev, expone puerto 3000"

echo -e "${GREEN}✅ Commit 2/3 OK${RESET}\n"

# =============================================================
# PASO 3 — Crear .env local (NO se commitea — está en .gitignore)
# =============================================================
echo -e "${YELLOW}[3/3] Crear .env local${RESET}"

# Verificar que .env no existe ya
if [ -f "configuracion/.env" ]; then
  echo -e "${RED}⚠️  configuracion/.env ya existe — no se sobreescribe${RESET}"
else
  cp configuracion/.env.example configuracion/.env
  echo -e "${GREEN}✅ configuracion/.env creado desde .env.example${RESET}"
fi

# Asegurar que .env está en .gitignore
if ! grep -q "\.env$" .gitignore 2>/dev/null; then
  echo ".env" >> .gitignore
  git add .gitignore
  git commit -m "chore: asegurar .env en .gitignore" || true
fi

# =============================================================
# PUSH
# =============================================================
echo -e "\n${CYAN}Haciendo push...${RESET}"
git push origin main

echo -e "\n${GREEN}=== ✅ Push completado ===${RESET}"
git log --oneline -3

echo -e "\n${CYAN}─── Siguiente: rellenar el .env ───${RESET}"
echo ""
echo "Edita configuracion/.env con tus credenciales reales:"
echo "  nano configuracion/.env"
echo ""
echo "Variables críticas a rellenar:"
echo "  META_PIXEL_ID              → Events Manager → tu Pixel → ID"
echo "  META_ACCESS_TOKEN          → Events Manager → tu Pixel → Configuración → API Token"
echo "  META_WEBHOOK_VERIFY_TOKEN  → cualquier string seguro (ej: openssl rand -hex 20)"
echo "  META_APP_SECRET            → Meta for Developers → tu App → Configuración básica"
echo "  META_PAGE_ACCESS_TOKEN     → Meta for Developers → tu App → Herramientas → Token"
echo "  META_TEST_EVENT_CODE       → Events Manager → Test Events → código TEST..."
echo ""
echo "Luego levanta todo con:"
echo "  cd configuracion && docker-compose --env-file .env up --build"
