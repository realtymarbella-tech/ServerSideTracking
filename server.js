// --- Carga manual y segura de .env (sin dependencias externas) ---
const fs = require('fs');
const path = require('path');
(function loadEnv() {
  const envPath = path.join(__dirname, '.env');
  if (!fs.existsSync(envPath)) return;
  const lines = fs.readFileSync(envPath, 'utf8').split('\n');
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

const express      = require('express');
const cookieParser = require('cookie-parser');
const collector    = require('./codigo/collector-endpoint');
const webhook      = require('./codigo/meta-leadform-webhook');

const app  = express();
const PORT = process.env.PORT || 3000;

app.use(express.json({ verify: (req, res, buf) => { req.rawBody = buf; } }));
app.use(cookieParser());
app.use('/api', collector);
app.use('/webhook', webhook);
app.get('/health', (req, res) => res.json({ ok: true, ts: new Date().toISOString() }));

app.listen(PORT, () => console.log(`[Server] SST Pro corriendo en puerto ${PORT}`));
