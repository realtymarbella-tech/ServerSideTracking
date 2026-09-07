#!/bin/bash
# temp-disable-sig.sh
# Comenta temporalmente verifyMetaSignature() para pruebas locales
# EJECUTAR SOLO EN LOCAL/TESTING, NUNCA EN PRODUCCION

set -e
FILE="codigo/meta-leadform-webhook.js"

if [ ! -f "$FILE" ]; then
  echo "❌ No se encontró $FILE"
  exit 1
fi

cp "$FILE" "${FILE}.bak2"
echo "✅ Backup creado: ${FILE}.bak2"

python3 << 'PYEOF'
with open('codigo/meta-leadform-webhook.js', 'r') as f:
    content = f.read()

old = '''  if (!verifyMetaSignature(req)) {
    console.warn('[Webhook] Firma inválida');
    return res.status(401).json({ error: 'Invalid signature' });
  }'''

new = '''  // --- TEMPORAL: firma deshabilitada para testing local ---
  // if (!verifyMetaSignature(req)) {
  //   console.warn('[Webhook] Firma inválida');
  //   return res.status(401).json({ error: 'Invalid signature' });
  // }
  console.warn('[Webhook] TESTING MODE - firma NO verificada');'''

if old not in content:
    print("⚠️ No se encontró el bloque exacto. Revisa manualmente.")
    exit(1)

content = content.replace(old, new)

with open('codigo/meta-leadform-webhook.js', 'w') as f:
    f.write(content)

print("✅ Verificación de firma deshabilitada temporalmente")
PYEOF

echo ""
echo "🎯 Ahora corre:"
echo "  kill %1 2>/dev/null || pkill -f 'node server.js'"
echo "  node server.js > server.log 2>&1 &"
echo "  sleep 2"
echo "  curl http://localhost:3000/health"
