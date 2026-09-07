#!/bin/bash
# restore-sig.sh
# Restaura la verificación de firma original después de las pruebas

set -e
FILE="codigo/meta-leadform-webhook.js"

if [ ! -f "${FILE}.bak2" ]; then
  echo "❌ No se encontró backup ${FILE}.bak2 — no hay nada que restaurar"
  exit 1
fi

cp "${FILE}.bak2" "$FILE"
echo "✅ Verificación de firma restaurada desde backup"
echo ""
echo "🎯 Reinicia el servidor:"
echo "  kill %1 2>/dev/null || pkill -f 'node server.js'"
echo "  node server.js > server.log 2>&1 &"
