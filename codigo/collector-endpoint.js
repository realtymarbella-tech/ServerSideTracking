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
