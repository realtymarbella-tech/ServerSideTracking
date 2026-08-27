#!/usr/bin/env bash
# push-scorer-dockerfile.sh
# Añade Dockerfile y requirements.txt al directorio scoring/ y hace push

set -e

GREEN='\033[0;32m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}=== Scorer Dockerfile — commit y push ===${RESET}\n"

# Verificar repo
if [ ! -d ".git" ]; then
  echo "❌ Ejecuta desde la raíz del repo ServerSideTracking"
  exit 1
fi

git checkout main && git pull origin main --quiet
echo -e "✅ main actualizado\n"

# ─── Dockerfile ───────────────────────────────────────────────
cat > scoring/Dockerfile << 'DOCKERFILE_EOF'
FROM python:3.11-slim

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY scoring-model.py .
COPY scoring-api.py .

RUN useradd -m scorer
USER scorer

EXPOSE 8001

CMD ["uvicorn", "scoring-api:app", "--host", "0.0.0.0", "--port", "8001", "--workers", "2"]
DOCKERFILE_EOF

git add scoring/Dockerfile
git commit -m "feat(infra): añadir Dockerfile para microservicio scorer Python

- Base python:3.11-slim
- curl instalado para healthcheck de docker-compose
- Usuario no-root scorer por seguridad
- 2 workers uvicorn en puerto 8001"

echo -e "${GREEN}✅ Commit 1/2 — Dockerfile OK${RESET}\n"

# ─── requirements.txt ─────────────────────────────────────────
cat > scoring/requirements.txt << 'REQ_EOF'
fastapi==0.111.0
uvicorn[standard]==0.29.0
pydantic==2.7.1
REQ_EOF

git add scoring/requirements.txt
git commit -m "feat(infra): añadir requirements.txt para scorer

- fastapi 0.111.0
- uvicorn 0.29.0 con extras standard (websockets, httptools)
- pydantic 2.7.1"

echo -e "${GREEN}✅ Commit 2/2 — requirements.txt OK${RESET}\n"

# ─── Push ─────────────────────────────────────────────────────
echo -e "${CYAN}Haciendo push...${RESET}"
git push origin main

echo -e "\n${GREEN}=== ✅ Push completado ===${RESET}"
git log --oneline -2

echo -e "\n${CYAN}Ahora puedes levantar todo con:${RESET}"
echo "  cd configuracion && docker-compose up --build"
