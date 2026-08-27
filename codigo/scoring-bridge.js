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
