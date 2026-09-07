#!/bin/bash
# safe-env-loader.sh
# Reemplaza dotenv por un loader manual seguro, sin dependencias externas

set -e
FILE="server.js"

# Revertir el require('dotenv').config() que agregamos antes
python3 << 'PYEOF'
with open('server.js', 'r') as f:
    content = f.read()

# Quitar la línea de dotenv si existe
content = content.replace("require('dotenv').config();\n", "")

# Loader manual seguro: lee .env línea por línea, sin ejecutar código, sin red
safe_loader = '''// --- Carga manual y segura de .env (sin dependencias externas) ---
const fs = require('fs');
const path = require('path');
(function loadEnv() {
  const envPath = path.join(__dirname, '.env');
  if (!fs.existsSync(envPath)) return;
  const lines = fs.readFileSync(envPath, 'utf8').split('\\n');
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx === -1) continue;
    const key = trimmed.slice(0, idx).trim();
    let value = trimmed.slice(idx + 1).trim();
    if ((value.startsWith('"') && value.endsWith('"')) || (value.startsWith("'") && value.endsWith("'"))) {
      value = value.slice(1, -1);
    }
    if (!(key in process.env)) process.env[key] = value;
  }
})();

'''

content = safe_loader + content

with open('server.js', 'w') as f:
    f.write(content)

print("✅ server.js actualizado con loader manual seguro (sin dotenv)")
PYEOF

echo ""
head -25 server.js
