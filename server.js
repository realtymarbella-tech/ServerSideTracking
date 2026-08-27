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
