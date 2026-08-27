"""
scoring-model.py
Santamaría Collection - Lead Scoring Model
Califica leads de 0-100 y los categoriza en SQL/MQL/Lead
"""

import hashlib
import json
from datetime import datetime

# ─── Pesos por criterio ───────────────────────────────────────
WEIGHTS = {
  'source':           25,
  'behavior':         30,
  'contact_data':     25,
  'engagement':       20
}

# ─── Fuentes y puntuación ─────────────────────────────────────
SOURCE_SCORES = {
  'meta_lead_form':     100,
  'contact_property':   100,
  'landing_cta':         80,
  'organic_search':      70,
  'direct':              60,
  'referral':            50,
  'social_organic':      40,
  'unknown':             20
}

# ─── Desarrollos y valor estimado ─────────────────────────────
PROPERTY_VALUES = {
  'SCR-001': 1500000,
  'SCR-002': 2000000,
  'SCR-003': 2500000,
  'SCR-004': 3000000
}


def score_source(lead):
  """Puntúa según fuente del lead"""
  source = lead.get('source', 'unknown')
  raw = SOURCE_SCORES.get(source, 20)
  return raw * WEIGHTS['source'] / 100


def score_behavior(lead):
  """Puntúa según comportamiento en web"""
  score = 0
  max_score = WEIGHTS['behavior']

  views         = lead.get('property_views', 0)
  time_on_site  = lead.get('time_on_site_seconds', 0)
  pages_visited = lead.get('pages_visited', 0)
  cta_clicks    = lead.get('cta_clicks', 0)

  # Vistas de propiedad (max 40% del behavior score)
  score += min(views / 3, 1) * max_score * 0.40

  # Tiempo en sitio (max 30% del behavior score)
  score += min(time_on_site / 180, 1) * max_score * 0.30

  # Páginas visitadas (max 20% del behavior score)
  score += min(pages_visited / 5, 1) * max_score * 0.20

  # CTA clicks (max 10% del behavior score)
  score += min(cta_clicks / 2, 1) * max_score * 0.10

  return score


def score_contact_data(lead):
  """Puntúa calidad de datos de contacto"""
  score = 0
  max_score = WEIGHTS['contact_data']

  has_email  = bool(lead.get('email'))
  has_phone  = bool(lead.get('phone'))
  has_name   = bool(lead.get('first_name'))
  has_fbp    = bool(lead.get('fbp'))

  if has_email:  score += max_score * 0.40
  if has_phone:  score += max_score * 0.35
  if has_name:   score += max_score * 0.15
  if has_fbp:    score += max_score * 0.10

  return score


def score_engagement(lead):
  """Puntúa engagement con desarrollos específicos"""
  score = 0
  max_score = WEIGHTS['engagement']

  property_id    = lead.get('property_id')
  scroll_depth   = lead.get('scroll_depth_pct', 0)
  repeat_visit   = lead.get('repeat_visit', False)

  # Interés en desarrollo específico
  if property_id and property_id in PROPERTY_VALUES:
    score += max_score * 0.50

  # Scroll depth
  score += (scroll_depth / 100) * max_score * 0.30

  # Visita repetida
  if repeat_visit:
    score += max_score * 0.20

  return score


def categorize(score):
  """Categoriza el lead según score"""
  if score >= 80:
    return 'SQL'   # Sales Qualified Lead — pasar a ventas inmediatamente
  elif score >= 50:
    return 'MQL'   # Marketing Qualified Lead — nurturing
  else:
    return 'Lead'  # Lead frío — retargeting


def score_lead(lead):
  """
  Función principal. Recibe dict con datos del lead y devuelve scoring completo.

  Ejemplo de input:
  {
    "lead_id":              "lead_123",
    "source":               "contact_property",
    "property_id":          "SCR-002",
    "email":                "buyer@example.com",
    "phone":                "+34600000000",
    "first_name":           "John",
    "fbp":                  "fb.1.xxx.yyy",
    "property_views":       3,
    "time_on_site_seconds": 240,
    "pages_visited":        5,
    "cta_clicks":           2,
    "scroll_depth_pct":     80,
    "repeat_visit":         True
  }
  """
  s_source   = score_source(lead)
  s_behavior = score_behavior(lead)
  s_contact  = score_contact_data(lead)
  s_engage   = score_engagement(lead)

  total = round(s_source + s_behavior + s_contact + s_engage, 1)
  total = min(total, 100)

  category = categorize(total)

  return {
    'lead_id':        lead.get('lead_id'),
    'scored_at':      datetime.utcnow().isoformat(),
    'lead_score':     total,
    'lead_status':    category,
    'score_breakdown': {
      'source':       round(s_source, 1),
      'behavior':     round(s_behavior, 1),
      'contact_data': round(s_contact, 1),
      'engagement':   round(s_engage, 1)
    },
    'property_id':    lead.get('property_id'),
    'estimated_value': PROPERTY_VALUES.get(lead.get('property_id'), 0)
  }


# ─── Test rápido ──────────────────────────────────────────────
if __name__ == '__main__':
  test_lead = {
    'lead_id':              'lead_test_001',
    'source':               'contact_property',
    'property_id':          'SCR-002',
    'email':                'buyer@example.com',
    'phone':                '+34600000000',
    'first_name':           'John',
    'fbp':                  'fb.1.xxx.yyy',
    'property_views':       3,
    'time_on_site_seconds': 240,
    'pages_visited':        5,
    'cta_clicks':           2,
    'scroll_depth_pct':     80,
    'repeat_visit':         True
  }

  result = score_lead(test_lead)
  print(json.dumps(result, indent=2))
