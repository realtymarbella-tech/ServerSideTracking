#!/bin/bash
# apply-debug-patch.sh
# Agrega debug logging a fetchLeadData() en meta-leadform-webhook.js
# Corre esto DENTRO de /workspaces/ServerSideTracking en Codespaces

set -e

FILE="codigo/meta-leadform-webhook.js"

if [ ! -f "$FILE" ]; then
  echo "❌ No se encontró $FILE — asegúrate de correr esto desde /workspaces/ServerSideTracking"
  exit 1
fi

# Backup por seguridad
cp "$FILE" "${FILE}.bak"
echo "✅ Backup creado: ${FILE}.bak"

# Reemplaza la función fetchLeadData completa con la versión con debug logging
python3 << 'PYEOF'
import re

with open('codigo/meta-leadform-webhook.js', 'r') as f:
    content = f.read()

old_function = '''function fetchLeadData(leadgenId) {
  const https = require('https');
  const url = `https://graph.facebook.com/v19.0/${leadgenId}?access_token=${PAGE_ACCESS_TOKEN}`;
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.error) { console.error('[LeadRetrieval]', parsed.error.message); resolve(null); return; }
          const fields = {};
          for (const f of (parsed.field_data || [])) fields[f.name] = f.values?.[0] || null;
          resolve({ ...parsed, fields });
        } catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}'''

new_function = '''function fetchLeadData(leadgenId) {
  const https = require('https');
  const url = `https://graph.facebook.com/v19.0/${leadgenId}?access_token=${PAGE_ACCESS_TOKEN}`;
  return new Promise((resolve, reject) => {
    https.get(url, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (parsed.error) {
            console.error('[LeadRetrieval] ERROR:', JSON.stringify(parsed.error, null, 2));
            resolve(null);
            return;
          }

          // --- DEBUG: ver exactamente que campos manda Meta ---
          console.log('[DEBUG] Raw field_data:', JSON.stringify(parsed.field_data, null, 2));

          const fields = {};
          for (const f of (parsed.field_data || [])) fields[f.name] = f.values?.[0] || null;

          console.log('[DEBUG] Parsed fields object:', JSON.stringify(fields, null, 2));
          console.log('[DEBUG] Field names found:', Object.keys(fields));

          resolve({ ...parsed, fields });
        } catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}'''

if old_function not in content:
    print("⚠️  ADVERTENCIA: no se encontró coincidencia exacta de la función original.")
    print("El archivo pudo haber cambiado. Revisa manualmente.")
    exit(1)

content = content.replace(old_function, new_function)

with open('codigo/meta-leadform-webhook.js', 'w') as f:
    f.write(content)

print("✅ Función fetchLeadData() actualizada con debug logging")
PYEOF

echo ""
echo "=== Diff aplicado ==="
diff "${FILE}.bak" "$FILE" || true
echo ""
echo "✅ Listo. Ahora:"
echo "1. Reinicia el servicio del webhook (docker-compose restart, o el comando que uses)"
echo "2. Genera un lead de prueba en el formulario de Meta"
echo "3. Revisa los logs: docker logs [container_name] 2>&1 | grep DEBUG"
