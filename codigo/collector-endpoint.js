const express = require('express');
const { v4: uuidv4 } = require('uuid');
const router = express.Router();

const VALID_EVENTS = [
  'page_view','view_property','contact_property',
  'view_meta_form','submit_meta_form',
  'view_landing_page','landing_page_cta_click'
];

const VALID_PROPERTY_IDS = ['SCR-001','SCR-002','SCR-003','SCR-004'];

function getClientIP(req) {
  return req.headers['x-forwarded-for']?.split(',')[0].trim()
    || req.headers['x-real-ip']
    || req.socket.remoteAddress;
}

function validateEvent(event) {
  const errors = [];
  if (!event.event_name) errors.push('event_name requerido');
  if (!event.event_source_url) errors.push('event_source_url requerido');
  if (!event.action_source) errors.push('action_source requerido');
  if (event.event_name && !VALID_EVENTS.includes(event.event_name))
    errors.push('event_name invalido: ' + event.event_name);
  if (['view_property','contact_property'].includes(event.event_name)) {
    if (!event.property_id) errors.push('property_id requerido');
    if (event.property_id && !VALID_PROPERTY_IDS.includes(event.property_id))
      errors.push('property_id invalido: ' + event.property_id);
  }
  if (['contact_property','submit_meta_form'].includes(event.event_name)) {
    if (!event.user_data?.em && !event.user_data?.ph)
      errors.push('email (em) o telefono (ph) hasheado requerido');
  }
  return errors;
}

function enrichEvent(event, req) {
  return {
    ...event,
    event_id: event.event_id || uuidv4(),
    event_time: Math.floor(Date.now() / 1000),
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

router.post('/track', async (req, res) => {
  try {
    const rawEvent = req.body;
    const errors = validateEvent(rawEvent);
    if (errors.length > 0) {
      return res.status(400).json({ ok: false, errors });
    }
    const enrichedEvent = enrichEvent(rawEvent, req);
    console.info('[Collector]', enrichedEvent.event_name, enrichedEvent.event_id);
    // TODO: await queue.send(enrichedEvent);
    // TODO: await metaSender.send(enrichedEvent);
    return res.status(200).json({ ok: true, event_id: enrichedEvent.event_id });
  } catch (err) {
    console.error('[Collector] Error:', err);
    return res.status(500).json({ ok: false, error: 'Internal server error' });
  }
});

router.get('/health', (req, res) => {
  res.json({ ok: true, ts: new Date().toISOString() });
});

module.exports = router;
