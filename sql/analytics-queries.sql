-- ─────────────────────────────────────────────────────────────
-- Santamaría Collection - Analytics Queries
-- Server-Side Tracking - Meta CAPI
-- ─────────────────────────────────────────────────────────────


-- ─── 1. CPL - Costo por Lead ──────────────────────────────────
SELECT
  DATE_TRUNC('week', event_date)          AS week,
  COUNT(DISTINCT lead_id)                  AS total_leads,
  SUM(spend)                               AS total_spend,
  ROUND(SUM(spend) / COUNT(DISTINCT lead_id), 2) AS cpl
FROM leads_meta_campaign
GROUP BY 1
ORDER BY 1 DESC;


-- ─── 2. CPQL - Costo por Lead Cualificado ─────────────────────
SELECT
  DATE_TRUNC('week', event_date)           AS week,
  COUNT(DISTINCT CASE WHEN lead_score >= 70
    THEN lead_id END)                       AS qualified_leads,
  SUM(spend)                                AS total_spend,
  ROUND(SUM(spend) / NULLIF(COUNT(DISTINCT
    CASE WHEN lead_score >= 70 THEN lead_id
    END), 0), 2)                            AS cpql
FROM leads_meta_campaign
GROUP BY 1
ORDER BY 1 DESC;


-- ─── 3. Funnel completo ────────────────────────────────────────
SELECT
  'page_view'              AS stage, COUNT(DISTINCT user_id) AS users FROM events WHERE event_name = 'page_view'
UNION ALL SELECT
  'view_property',                   COUNT(DISTINCT user_id) FROM events WHERE event_name = 'view_property'
UNION ALL SELECT
  'landing_page_cta_click',          COUNT(DISTINCT user_id) FROM events WHERE event_name = 'landing_page_cta_click'
UNION ALL SELECT
  'contact_property',                COUNT(DISTINCT user_id) FROM events WHERE event_name = 'contact_property'
UNION ALL SELECT
  'submit_meta_form',                COUNT(DISTINCT user_id) FROM events WHERE event_name = 'submit_meta_form'
UNION ALL SELECT
  'lead_cualificado',                COUNT(DISTINCT lead_id) FROM leads  WHERE lead_score >= 70;


-- ─── 4. Conversión por desarrollo ─────────────────────────────
SELECT
  property_id,
  property_name,
  COUNT(DISTINCT CASE WHEN event_name = 'view_property'
    THEN user_id END)                       AS views,
  COUNT(DISTINCT CASE WHEN event_name = 'contact_property'
    THEN user_id END)                       AS contacts,
  ROUND(100.0 * COUNT(DISTINCT CASE WHEN event_name = 'contact_property'
    THEN user_id END) /
    NULLIF(COUNT(DISTINCT CASE WHEN event_name = 'view_property'
    THEN user_id END), 0), 2)              AS conversion_rate_pct
FROM events
WHERE property_id IN ('SCR-001','SCR-002','SCR-003','SCR-004')
GROUP BY 1, 2
ORDER BY conversion_rate_pct DESC;


-- ─── 5. Distribución de Lead Score ────────────────────────────
SELECT
  CASE
    WHEN lead_score >= 80 THEN 'Alto (80-100)'
    WHEN lead_score >= 50 THEN 'Medio (50-79)'
    ELSE                       'Bajo (0-49)'
  END                                       AS score_range,
  COUNT(*)                                  AS total,
  ROUND(100.0 * COUNT(*) /
    SUM(COUNT(*)) OVER (), 2)               AS pct
FROM leads
GROUP BY 1
ORDER BY 1 DESC;


-- ─── 6. Leads por fuente UTM ──────────────────────────────────
SELECT
  utm_source,
  utm_medium,
  utm_campaign,
  COUNT(DISTINCT lead_id)                   AS leads,
  ROUND(AVG(lead_score), 1)                 AS avg_score,
  SUM(spend)                                AS spend,
  ROUND(SUM(spend) /
    NULLIF(COUNT(DISTINCT lead_id), 0), 2)  AS cpl
FROM leads_meta_campaign
GROUP BY 1, 2, 3
ORDER BY leads DESC;


-- ─── 7. Deduplicación - eventos duplicados Meta ───────────────
SELECT
  event_name,
  event_id,
  COUNT(*)                                  AS duplicates
FROM meta_events_log
GROUP BY 1, 2
HAVING COUNT(*) > 1
ORDER BY duplicates DESC;


-- ─── 8. Match Rate Meta CAPI ──────────────────────────────────
SELECT
  DATE_TRUNC('day', sent_at)                AS day,
  COUNT(*)                                  AS events_sent,
  SUM(CASE WHEN matched = true
    THEN 1 ELSE 0 END)                      AS events_matched,
  ROUND(100.0 * SUM(CASE WHEN matched = true
    THEN 1 ELSE 0 END) /
    NULLIF(COUNT(*), 0), 2)                 AS match_rate_pct
FROM meta_events_log
GROUP BY 1
ORDER BY 1 DESC;

