const crypto = require('crypto');

const CAPI_MAPPING = {
  page_view:              'PageView',
  view_property:          'ViewContent',
  contact_property:       'Lead',
  view_meta_form:         'PageView',
  submit_meta_form:       'Lead',
  view_landing_page:      'PageView',
  landing_page_cta_click: 'Contact'
};

function hashSHA256(value) {
  if (!value) return undefined;
  return crypto.createHash('sha256')
    .update(value.toString().trim().toLowerCase())
    .digest('hex');
}

function normalizePhone(phone) {
  if (!phone) return undefined;
  const digits = phone.replace(/[^\d+]/g, '');
  return digits.startsWith('+') ? digits : '+34' + digits;
}

function buildUserData(event) {
  const ud = event.user_data || {};
  return {
    em:                ud.em  || hashSHA256(ud.email),
    ph:                ud.ph  || hashSHA256(normalizePhone(ud.phone)),
    external_id:       ud.external_id,
    client_ip_address: ud.client_ip_address,
    client_user_agent: ud.client_user_agent,
    fbp:               ud.fbp,
    fbc:               ud.fbc
  };
}

function buildCustomData(event) {
  const base = {
    currency: 'EUR',
    value:    event.value || 0
  };

  if (event.event_name === 'view_property' || event.event_name === 'contact_property') {
    return {
      ...base,
      content_ids:      [event.property_id],
      content_type:     'product',
      content_name:     event.property_name,
      content_category: 'inmobiliaria',
      value:            event.value || (event.event_name === 'contact_property' ? 3000 : 0)
    };
  }

  if (event.event_name === 'submit_meta_form') {
    return {
      ...base,
      content_name:     event.form_name,
      content_category: 'meta_lead_form',
      form_id:          event.form_id,
      lead_type:        'meta_native_form',
      value:            event.value || 3000
    };
  }

  if (event.event_name === 'landing_page_cta_click') {
    return {
      ...base,
      content_name:     event.cta_text,
      content_category: 'landing_cta',
      cta_id:           event.cta_id,
      page_id:          event.page_id
    };
  }

  return {
    ...base,
    content_name:     event.page_title || event.page_name,
    content_category: event.page_category || 'general'
  };
}

function transform(event) {
  const metaEventName = CAPI_MAPPING[event.event_name];
  if (!metaEventName) {
    throw new Error('Evento no mapeado: ' + event.event_name);
  }

  return {
    event_name:       metaEventName,
    event_id:         event.event_id,
    event_time:       event.event_time,
    event_source_url: event.event_source_url,
    action_source:    event.action_source || 'website',
    user_data:        buildUserData(event),
    custom_data:      buildCustomData(event)
  };
}

module.exports = { transform };
