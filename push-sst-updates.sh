#!/usr/bin/env bash
# =============================================================
# push-sst-updates.sh
# Santamaría Collection — SST Pro
# Copia los 6 archivos nuevos al repo, hace commit individual
# de cada uno y push al final.
#
# USO EN CODESPACES:
#   1. Abre el terminal de tu Codespace (ya tienes el repo abierto)
#   2. Descarga este script en la raíz del repo
#   3. chmod +x push-sst-updates.sh
#   4. ./push-sst-updates.sh
# =============================================================

set -e  # Abortar si cualquier comando falla

# ─── Colores para output legible ─────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
RESET='\033[0m'

echo -e "${CYAN}=== SST Pro — Push de actualizaciones ===${RESET}\n"

# ─── Verificaciones previas ───────────────────────────────────
if [ ! -d ".git" ]; then
  echo "❌ Ejecuta este script desde la raíz del repo ServerSideTracking"
  exit 1
fi

REMOTE_URL=$(git remote get-url origin)
if [[ "$REMOTE_URL" != *"ServerSideTracking"* ]]; then
  echo "❌ Remote incorrecto: $REMOTE_URL"
  exit 1
fi

echo -e "✅ Repo OK: $REMOTE_URL"
echo -e "✅ Branch: $(git branch --show-current)\n"

# ─── Asegurarse de estar en main y al día ────────────────────
git checkout main
git pull origin main --quiet
echo -e "✅ main actualizado\n"

# =============================================================
# COMMIT 1 — collector-endpoint.js (TODOs resueltos)
# =============================================================
echo -e "${YELLOW}[1/6] collector-endpoint.js${RESET}"

cat > codigo/collector-endpoint.js << 'COLLECTOR_EOF'
/**
 * collector-endpoint.js
 * Santamaría Collection — SST Pro
 * Endpoint de recopilación con flujo completo:
 * Recibe → Valida → Enriquece → Scoring → Transforma → Meta CAPI
 */

const express    = require('express');
const { v4: uuidv4 } = require('uuid');
const metaSender = require('./meta-sender');
const { transform } = require('./event-transformer');
const { score_lead_js } = require('./scoring-bridge');

const router = express.Router();

// ─── Constantes ───────────────────────────────────────────────
const VALID_EVENTS = [
  'page_view',
  'view_property',
  'contact_property',
  'view_meta_form',
  'submit_meta_form',
  'view_landing_page',
  'landing_page_cta_click'
];

const VALID_PROPERTY_IDS = ['SCR-001', 'SCR-002', 'SCR-003', 'SCR-004'];

// Eventos que disparan envío a Meta CAPI
const CAPI_EVENTS = new Set([
  'view_property',
  'contact_property',
  'submit_meta_form',
  'landing_page_cta_click'
]);

// Eventos que disparan scoring de lead
const SCORING_EVENTS = new Set([
  'contact_property',
  'submit_meta_form'
]);

// ─── Helpers ──────────────────────────────────────────────────
function getClientIP(req) {
  return (
    req.headers['x-forwarded-for']?.split(',')[0].trim() ||
    req.headers['x-real-ip'] ||
    req.socket.remoteAddress
  );
}

// ─── Validación ───────────────────────────────────────────────
function validateEvent(event) {
  const errors = [];

  if (!event.event_name)
    errors.push('event_name requerido');
  if (!event.event_source_url)
    errors.push('event_source_url requerido');
  if (!event.action_source)
    errors.push('action_source requerido');

  if (event.event_name && !VALID_EVENTS.includes(event.event_name))
    errors.push('event_name invalido: ' + event.event_name);

  if (['view_property', 'contact_property'].includes(event.event_name)) {
    if (!event.property_id)
      errors.push('property_id requerido');
    if (event.property_id && !VALID_PROPERTY_IDS.includes(event.property_id))
      errors.push('property_id invalido: ' + event.property_id);
  }

  if (['contact_property', 'submit_meta_form'].includes(event.event_name)) {
    if (!event.user_data?.em && !event.user_data?.ph)
      errors.push('email (em) o telefono (ph) hasheado requerido');
  }

  return errors;
}

// ─── Enriquecimiento ──────────────────────────────────────────
function enrichEvent(event, req) {
  return {
    ...event,
    event_id:           event.event_id || uuidv4(),
    event_time:         Math.floor(Date.now() / 1000),
    server_received_at: new Date().toISOString(),
    user_data: {
      ...event.user_data,
      client_ip_address: getClientIP(req),
      client_user_agent: req.headers['user-agent'],
      fbp: req.cookies?._fbp || event.user_data?.fbp,
      fbc: req.cookies?._fbc || event.user_data?.fbc
    }
  };
}

// ─── Scoring payload ──────────────────────────────────────────
function buildScoringPayload(event) {
  const ud = event.user_data || {};
  return {
    lead_id:               event.event_id,
    source:                event.event_name,
    property_id:           event.property_id || null,
    email:                 !!ud.em,
    phone:                 !!ud.ph,
    first_name:            !!ud.fn,
    fbp:                   !!ud.fbp,
    property_views:        event.property_views        || 0,
    time_on_site_seconds:  event.time_on_site_seconds  || 0,
    pages_visited:         event.pages_visited         || 0,
    cta_clicks:            event.cta_clicks            || 0,
    scroll_depth_pct:      event.scroll_depth_pct      || 0,
    repeat_visit:          event.repeat_visit          || false
  };
}

// ─── Ruta principal ───────────────────────────────────────────
router.post('/track', async (req, res) => {
  try {
    const rawEvent = req.body;
    const errors = validateEvent(rawEvent);
    if (errors.length > 0) {
      return res.status(400).json({ ok: false, errors });
    }

    const enrichedEvent = enrichEvent(rawEvent, req);
    console.info('[Collector] Evento recibido:', enrichedEvent.event_name, enrichedEvent.event_id);

    // Scoring (non-fatal)
    let leadScore  = null;
    let leadStatus = null;

    if (SCORING_EVENTS.has(enrichedEvent.event_name)) {
      try {
        const scoreResult = await score_lead_js(buildScoringPayload(enrichedEvent));
        leadScore  = scoreResult.lead_score;
        leadStatus = scoreResult.lead_status;
        enrichedEvent.custom_data = {
          ...enrichedEvent.custom_data,
          lead_score:  leadScore,
          lead_status: leadStatus
        };
        console.info('[Scorer]', enrichedEvent.event_id,
          '→ score:', leadScore, '| status:', leadStatus);
      } catch (scoringErr) {
        console.warn('[Scorer] Error (non-fatal):', scoringErr.message);
      }
    }

    // Meta CAPI (non-fatal)
    if (CAPI_EVENTS.has(enrichedEvent.event_name)) {
      try {
        const metaPayload = transform(enrichedEvent);
        const metaResult  = await metaSender.send(metaPayload);
        console.info('[CAPI] Entregado:', metaPayload.event_name,
          '| events_received:', metaResult.events_received);
      } catch (capiErr) {
        console.error('[CAPI] Error al enviar:', capiErr.message);
      }
    }

    return res.status(200).json({
      ok:          true,
      event_id:    enrichedEvent.event_id,
      lead_score:  leadScore,
      lead_status: leadStatus
    });

  } catch (err) {
    console.error('[Collector] Error inesperado:', err);
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

router.get('/health', (req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

module.exports = router;
COLLECTOR_EOF

git add codigo/collector-endpoint.js
git commit -m "fix(collector): conectar flujo completo Scoring + Meta CAPI — resolver TODOs

- Integrar score_lead_js desde scoring-bridge en eventos contact_property y submit_meta_form
- Integrar metaSender.send + transform en eventos CAPI_EVENTS
- lead_score y lead_status adjuntos en custom_data antes del envío a CAPI
- Scoring y CAPI son non-fatal: fallos logueados sin bloquear respuesta al cliente
- Respuesta al cliente incluye event_id, lead_score, lead_status"

echo -e "${GREEN}✅ Commit 1 OK${RESET}\n"

# =============================================================
# COMMIT 2 — scoring-bridge.js (nuevo archivo)
# =============================================================
echo -e "${YELLOW}[2/6] scoring-bridge.js${RESET}"

cat > codigo/scoring-bridge.js << 'BRIDGE_EOF'
/**
 * scoring-bridge.js
 * Santamaría Collection — SST Pro
 *
 * Puente Node.js → microservicio Python de scoring (FastAPI).
 * El collector llama a score_lead_js() para puntuar leads en tiempo real.
 *
 * Arranque del scorer:
 *   pip install fastapi uvicorn
 *   uvicorn scoring-api:app --host 0.0.0.0 --port 8001
 *
 * En producción: servicio `scorer` en docker-compose.yml
 */

const http = require('http');

const SCORER_HOST       = process.env.SCORER_HOST    || 'scorer';
const SCORER_PORT       = process.env.SCORER_PORT    || 8001;
const SCORER_TIMEOUT_MS = 2000; // 2s máximo — no bloquear CAPI

/**
 * Llama al microservicio Python de scoring.
 * @param {Object} payload
 * @returns {Promise<{lead_score, lead_status, score_breakdown}>}
 */
function score_lead_js(payload) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload);

    const options = {
      hostname: SCORER_HOST,
      port:     SCORER_PORT,
      path:     '/score',
      method:   'POST',
      headers: {
        'Content-Type':   'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    };

    const req = http.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          res.statusCode === 200
            ? resolve(parsed)
            : reject(new Error('Scorer ' + res.statusCode + ': ' + data));
        } catch (e) {
          reject(new Error('Scorer parse error: ' + e.message));
        }
      });
    });

    req.setTimeout(SCORER_TIMEOUT_MS, () => {
      req.destroy();
      reject(new Error('Scorer timeout after ' + SCORER_TIMEOUT_MS + 'ms'));
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

module.exports = { score_lead_js };
BRIDGE_EOF

git add codigo/scoring-bridge.js
git commit -m "feat(scoring): añadir scoring-bridge.js — puente Node.js a microservicio Python

- HTTP client interno hacia FastAPI scorer en puerto 8001
- Timeout de 2s para no bloquear pipeline CAPI si scorer no responde
- Variables de entorno SCORER_HOST y SCORER_PORT configurables"

echo -e "${GREEN}✅ Commit 2 OK${RESET}\n"

# =============================================================
# COMMIT 3 — scoring-api.py (nuevo archivo)
# =============================================================
echo -e "${YELLOW}[3/6] scoring-api.py${RESET}"

cat > scoring/scoring-api.py << 'SCORER_API_EOF'
"""
scoring-api.py
Santamaría Collection — SST Pro

Microservicio FastAPI que expone scoring-model.py como endpoint HTTP.
El collector Node.js llama a este servicio para puntuar leads en tiempo real.

Arranque:
  pip install fastapi uvicorn
  uvicorn scoring-api:app --host 0.0.0.0 --port 8001 --workers 2
"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from typing import Optional
import logging

from scoring_model import score_lead

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("scorer")

app = FastAPI(title="SMC Lead Scorer", version="1.0.0")


class LeadPayload(BaseModel):
    lead_id:              Optional[str]   = None
    source:               Optional[str]   = "unknown"
    property_id:          Optional[str]   = None
    email:                Optional[bool]  = False
    phone:                Optional[bool]  = False
    first_name:           Optional[bool]  = False
    fbp:                  Optional[bool]  = False
    property_views:       Optional[int]   = 0
    time_on_site_seconds: Optional[int]   = 0
    pages_visited:        Optional[int]   = 0
    cta_clicks:           Optional[int]   = 0
    scroll_depth_pct:     Optional[float] = 0.0
    repeat_visit:         Optional[bool]  = False


@app.post("/score")
def score_endpoint(payload: LeadPayload):
    try:
        result = score_lead(payload.dict())
        logger.info(
            f"[Scorer] lead_id={result['lead_id']} "
            f"score={result['lead_score']} "
            f"status={result['lead_status']}"
        )
        return result
    except Exception as e:
        logger.error(f"[Scorer] Error: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/health")
def health():
    return {"ok": True}
SCORER_API_EOF

git add scoring/scoring-api.py
git commit -m "feat(scoring): añadir scoring-api.py — FastAPI wrapper para scoring-model.py

- Endpoint POST /score recibe LeadPayload y devuelve score completo
- Endpoint GET /health para healthcheck de docker-compose
- Pydantic model con valores por defecto — compatible con payloads parciales
- Logs estructurados con lead_id, score y status"

echo -e "${GREEN}✅ Commit 3 OK${RESET}\n"

# =============================================================
# COMMIT 4 — meta-leadform-webhook.js (nuevo archivo)
# =============================================================
echo -e "${YELLOW}[4/6] meta-leadform-webhook.js${RESET}"

cat > codigo/meta-leadform-webhook.js << 'WEBHOOK_EOF'
/**
 * meta-leadform-webhook.js
 * Santamaría Collection — SST Pro
 *
 * Recibe leads del formulario nativo de Meta (SMC-Luxury-Video-Leads-Aug26),
 * los puntúa con el scoring model y los reenvía enriquecidos
 * a Meta CAPI como evento `Lead` con leadScore en custom_data.
 *
 * SETUP EN META:
 * 1. Meta for Developers → tu App → Webhooks
 * 2. Suscribirse al objeto "leadgen"
 * 3. Callback URL: https://tu-servidor.com/webhook/meta-leads
 * 4. Verify Token: valor de META_WEBHOOK_VERIFY_TOKEN en .env
 *
 * PENDIENTE: rellenar FORM_PROPERTY_MAP con los form_ids reales
 * de Meta Ads Manager → tu lead form → ID del formulario
 */

const express = require('express');
const crypto  = require('crypto');
const http    = require('https');
const { v4: uuidv4 } = require('uuid');
const metaSender = require('./meta-sender');
const { score_lead_js } = require('./scoring-bridge');

const router = express.Router();

const VERIFY_TOKEN      = process.env.META_WEBHOOK_VERIFY_TOKEN;
const APP_SECRET        = process.env.META_APP_SECRET;
const PAGE_ACCESS_TOKEN = process.env.META_PAGE_ACCESS_TOKEN;

// ─── Mapa form_id → property_id ──────────────────────────────
// RELLENAR con los IDs reales de Meta Ads Manager
const FORM_PROPERTY_MAP = {
  // 'FORM_ID_META': 'SCR-001',  // Cipriani
  // 'FORM_ID_META': 'SCR-002',  // Elle
  // 'FORM_ID_META': 'SCR-003',  // Domus
  // 'FORM_ID_META': 'SCR-004',  // One Twenty
};

// ─── Verificación de firma Meta ───────────────────────────────
function verifyMetaSignature(req) {
  const signature = req.headers['x-hub-signature-256'];
  if (!signature || !APP_SECRET) return false;
  const expected = 'sha256=' + crypto
    .createHmac('sha256', APP_SECRET)
    .update(req.rawBody || JSON.stringify(req.body))
    .digest('hex');
  return crypto.timingSafeEqual(Buffer.from(signature), Buffer.from(expected));
}

// ─── GET: handshake de verificación ──────────────────────────
router.get('/meta-leads', (req, res) => {
  const mode      = req.query['hub.mode'];
  const token     = req.query['hub.verify_token'];
  const challenge = req.query['hub.challenge'];
  if (mode === 'subscribe' && token === VERIFY_TOKEN) {
    console.info('[Webhook] Meta verificación OK');
    return res.status(200).send(challenge);
  }
  console.warn('[Webhook] Meta verificación FALLIDA');
  return res.status(403).json({ error: 'Forbidden' });
});

// ─── POST: recepción de lead nuevo ────────────────────────────
router.post('/meta-leads', async (req, res) => {
  if (!verifyMetaSignature(req)) {
    console.warn('[Webhook] Firma inválida');
    return res.status(401).json({ error: 'Invalid signature' });
  }

  // Responder 200 inmediatamente (Meta requiere < 20s)
  res.status(200).json({ ok: true });

  try {
    for (const entry of (req.body.entry || [])) {
      for (const change of (entry.changes || [])) {
        if (change.field !== 'leadgen') continue;

        const { leadgen_id, form_id, ad_id, adset_id, campaign_id, created_time } = change.value;
        console.info('[Webhook] Lead recibido — leadgen_id:', leadgen_id, 'form_id:', form_id);

        const leadData = await fetchLeadData(leadgen_id);
        if (!leadData) { console.error('[Webhook] No se pudo recuperar lead:', leadgen_id); continue; }

        const propertyId    = FORM_PROPERTY_MAP[form_id] || null;
        const scoringPayload = buildScoringPayload(leadData, propertyId);

        let leadScore = null, leadStatus = null;
        try {
          const sr = await score_lead_js(scoringPayload);
          leadScore  = sr.lead_score;
          leadStatus = sr.lead_status;
          console.info('[Scorer] Lead', leadgen_id, '→ score:', leadScore, '| status:', leadStatus);
        } catch (e) { console.warn('[Scorer] Error (non-fatal):', e.message); }

        const metaEvent = buildMetaCapiEvent({
          leadData, leadgen_id, form_id, propertyId,
          ad_id, adset_id, campaign_id,
          leadScore, leadStatus, created_time
        });

        try {
          const result = await metaSender.send(metaEvent);
          console.info('[CAPI] Lead enviado OK — events_received:', result.events_received);
        } catch (e) { console.error('[CAPI] Error al enviar:', e.message); }
      }
    }
  } catch (err) {
    console.error('[Webhook] Error procesando payload:', err);
  }
});

// ─── Lead Retrieval API ───────────────────────────────────────
function fetchLeadData(leadgenId) {
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
}

// ─── Builders ─────────────────────────────────────────────────
function buildScoringPayload(leadData, propertyId) {
  const f = leadData.fields || {};
  return {
    lead_id:    leadData.id,
    source:     'meta_lead_form',
    property_id: propertyId,
    email:      !!f.email,
    phone:      !!f.phone_number,
    first_name: !!(f.full_name || f.first_name),
    fbp:        false,
    property_views: 0, time_on_site_seconds: 0,
    pages_visited: 0, cta_clicks: 0,
    scroll_depth_pct: 0, repeat_visit: false
  };
}

function sha256(value) {
  if (!value) return undefined;
  return crypto.createHash('sha256').update(value.toString().trim().toLowerCase()).digest('hex');
}

function buildMetaCapiEvent({ leadData, leadgen_id, form_id, propertyId, ad_id, adset_id, campaign_id, leadScore, leadStatus, created_time }) {
  const f = leadData.fields || {};
  return {
    event_name:       'Lead',
    event_id:         `leadgen_${leadgen_id}`,
    event_time:       created_time || Math.floor(Date.now() / 1000),
    event_source_url: 'https://www.santamaria-collection.com',
    action_source:    'website',
    user_data: {
      em: sha256(f.email),
      ph: sha256(f.phone_number?.replace(/\D/g, '')),
      fn: sha256(f.first_name || f.full_name?.split(' ')[0]),
      ln: sha256(f.last_name  || f.full_name?.split(' ').slice(1).join(' '))
    },
    custom_data: {
      currency: 'USD', value: 3000,
      content_name: form_id, content_category: 'meta_lead_form',
      lead_type: 'meta_native_form', form_id,
      property_id: propertyId, ad_id, adset_id, campaign_id,
      lead_score: leadScore, lead_status: leadStatus
    }
  };
}

module.exports = router;
WEBHOOK_EOF

git add codigo/meta-leadform-webhook.js
git commit -m "feat(webhook): añadir meta-leadform-webhook.js — Lead Form nativo → Scoring → CAPI

- GET /webhook/meta-leads: handshake de verificación con Meta
- POST /webhook/meta-leads: recepción de leads, verificación de firma HMAC-SHA256
- Recuperación de datos del lead via Lead Retrieval API (graph.facebook.com/v19.0)
- Scoring en tiempo real vía scoring-bridge antes del envío a CAPI
- event_id: leadgen_\${id} para deduplicación con pixel de browser
- Responde 200 inmediatamente, procesa en background (req. Meta < 20s)
- PENDIENTE: rellenar FORM_PROPERTY_MAP con form_ids reales"

echo -e "${GREEN}✅ Commit 4 OK${RESET}\n"

# =============================================================
# COMMIT 5 — docker-compose.yml actualizado (servicio scorer)
# =============================================================
echo -e "${YELLOW}[5/6] docker-compose.yml${RESET}"

cat > configuracion/docker-compose.yml << 'DOCKER_EOF'
version: '3.8'

services:
  postgres:
    image: postgres:14
    environment:
      POSTGRES_DB: tracking_db
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5

  redis:
    image: redis:7
    ports:
      - "6379:6379"
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5

  scorer:
    build:
      context: ../scoring
      dockerfile: Dockerfile
    command: uvicorn scoring-api:app --host 0.0.0.0 --port 8001 --workers 2
    environment:
      - PYTHONUNBUFFERED=1
    ports:
      - "8001:8001"
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8001/health"]
      interval: 15s
      timeout: 5s
      retries: 3

  app:
    build: ..
    environment:
      NODE_ENV: production
      DB_HOST: postgres
      REDIS_HOST: redis
      SCORER_HOST: scorer
      SCORER_PORT: 8001
      META_PIXEL_ID: ${META_PIXEL_ID}
      META_ACCESS_TOKEN: ${META_ACCESS_TOKEN}
      META_WEBHOOK_VERIFY_TOKEN: ${META_WEBHOOK_VERIFY_TOKEN}
      META_APP_SECRET: ${META_APP_SECRET}
      META_PAGE_ACCESS_TOKEN: ${META_PAGE_ACCESS_TOKEN}
      META_TEST_EVENT_CODE: ${META_TEST_EVENT_CODE}
    ports:
      - "3000:3000"
    depends_on:
      postgres:
        condition: service_healthy
      redis:
        condition: service_healthy
      scorer:
        condition: service_healthy

volumes:
  postgres_data:
DOCKER_EOF

git add configuracion/docker-compose.yml
git commit -m "feat(infra): añadir servicio scorer a docker-compose con healthcheck

- Nuevo servicio scorer: FastAPI Python en puerto 8001
- app depende de scorer (condition: service_healthy) antes de arrancar
- Variables de entorno META_WEBHOOK_VERIFY_TOKEN, META_APP_SECRET y META_PAGE_ACCESS_TOKEN
- Healthcheck curl /health en scorer cada 15s"

echo -e "${GREEN}✅ Commit 5 OK${RESET}\n"

# =============================================================
# COMMIT 6 — .env.example actualizado con nuevas variables
# =============================================================
echo -e "${YELLOW}[6/6] .env.example${RESET}"

cat > configuracion/.env.example << 'ENV_EOF'
# ─── Meta Pixel ───────────────────────────────────────────────
META_ACCESS_TOKEN=your_access_token_here
META_PIXEL_ID=2277888696292134
META_DATASET_ID=your_dataset_id
META_TEST_EVENT_CODE=TEST12345

# ─── Meta Webhook ─────────────────────────────────────────────
META_WEBHOOK_VERIFY_TOKEN=your_random_verify_token_here
META_APP_SECRET=your_meta_app_secret_here
META_PAGE_ACCESS_TOKEN=your_page_access_token_here

# ─── Database ─────────────────────────────────────────────────
DB_HOST=localhost
DB_PORT=5432
DB_NAME=tracking_db
DB_USER=postgres
DB_PASSWORD=password

# ─── Scorer microservicio ─────────────────────────────────────
SCORER_HOST=scorer
SCORER_PORT=8001

# ─── Cloud ────────────────────────────────────────────────────
AWS_REGION=eu-west-1
AWS_ACCESS_KEY_ID=your_key
AWS_SECRET_ACCESS_KEY=your_secret

# ─── App ──────────────────────────────────────────────────────
NODE_ENV=production
PORT=3000
LOG_LEVEL=info
ENV_EOF

git add configuracion/.env.example
git commit -m "chore(config): actualizar .env.example con variables de webhook y scorer

- META_WEBHOOK_VERIFY_TOKEN — token para handshake con Meta
- META_APP_SECRET — para verificación de firma HMAC-SHA256
- META_PAGE_ACCESS_TOKEN — para Lead Retrieval API
- META_TEST_EVENT_CODE — para testing en Events Manager
- SCORER_HOST / SCORER_PORT — configuración del microservicio Python
- META_PIXEL_ID pre-rellenado con 2277888696292134"

echo -e "${GREEN}✅ Commit 6 OK${RESET}\n"

# =============================================================
# PUSH
# =============================================================
echo -e "${CYAN}Haciendo push de los 6 commits a origin/main...${RESET}"
git push origin main

echo -e "\n${GREEN}=== ✅ Push completado ===${RESET}"
echo -e "Commits subidos:\n"
git log --oneline -6
echo -e "\n${CYAN}Próximos pasos:${RESET}"
echo "1. En .env: rellenar META_WEBHOOK_VERIFY_TOKEN, META_APP_SECRET, META_PAGE_ACCESS_TOKEN"
echo "2. En codigo/meta-leadform-webhook.js: añadir FORM_PROPERTY_MAP con form_ids reales"
echo "3. En scoring/: crear Dockerfile para el servicio scorer"
echo "4. docker-compose up --build"
echo "5. Registrar webhook en Meta for Developers → Webhooks → leadgen"
