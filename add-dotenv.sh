#!/bin/bash
set -e

FILE="server.js"
if [ ! -f "$FILE" ]; then
  echo "❌ No se encontró $FILE"
  exit 1
fi

cp "$FILE" "${FILE}.bak"

python3 << 'PYEOF'
with open('server.js', 'r') as f:
    content = f.read()

if "require('dotenv')" in content:
    print("✅ dotenv ya estaba cargado, no se hicieron cambios")
else:
    new_content = "require('dotenv').config();\n" + content
    with open('server.js', 'w') as f:
        f.write(new_content)
    print("✅ dotenv agregado al inicio de server.js")
PYEOF

echo ""
echo "=== server.js actualizado ==="
head -5 server.js
