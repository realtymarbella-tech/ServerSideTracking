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
