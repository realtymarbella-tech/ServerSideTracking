const https = require('https');

const PIXEL_ID    = process.env.META_PIXEL_ID;
const ACCESS_TOKEN = process.env.META_ACCESS_TOKEN;
const API_VERSION  = 'v19.0';
const MAX_RETRIES  = 3;
const RETRY_DELAY  = 1000;

function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

function postToMeta(payload) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify(payload);
    const options = {
      hostname: 'graph.facebook.com',
      path:     `/${API_VERSION}/${PIXEL_ID}/events?access_token=${ACCESS_TOKEN}`,
      method:   'POST',
      headers:  {
        'Content-Type':   'application/json',
        'Content-Length': Buffer.byteLength(body)
      }
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const parsed = JSON.parse(data);
        if (res.statusCode === 200) {
          resolve(parsed);
        } else {
          reject(new Error(JSON.stringify(parsed)));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

async function send(metaEvent, retries = 0) {
  const payload = {
    data: [metaEvent],
    test_event_code: process.env.META_TEST_EVENT_CODE || undefined
  };

  try {
    const result = await postToMeta(payload);
    console.info('[MetaSender] OK:', metaEvent.event_name, metaEvent.event_id,
      'events_received:', result.events_received);
    return result;
  } catch (err) {
    if (retries < MAX_RETRIES) {
      console.warn('[MetaSender] Reintento', retries + 1, 'para', metaEvent.event_name);
      await sleep(RETRY_DELAY * (retries + 1));
      return send(metaEvent, retries + 1);
    }
    console.error('[MetaSender] FALLO tras', MAX_RETRIES, 'intentos:', err.message);
    throw err;
  }
}

async function sendBatch(metaEvents) {
  const payload = {
    data: metaEvents,
    test_event_code: process.env.META_TEST_EVENT_CODE || undefined
  };

  try {
    const result = await postToMeta(payload);
    console.info('[MetaSender] Batch OK:', metaEvents.length, 'eventos');
    return result;
  } catch (err) {
    console.error('[MetaSender] Batch FALLO:', err.message);
    throw err;
  }
}

module.exports = { send, sendBatch };
