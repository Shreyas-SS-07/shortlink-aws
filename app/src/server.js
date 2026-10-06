const express = require('express');
const path = require('path');
const db = require('./db');
const cache = require('./cache');

const crypto = require('crypto');

function log(level, message, meta = {}) {
  const entry = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...meta,
  };
  if (level === 'error') {
    process.stderr.write(JSON.stringify(entry) + '\n');
  } else {
    process.stdout.write(JSON.stringify(entry) + '\n');
  }
}

const app = express();
app.set('trust proxy', 1); // behind the ALB: use X-Forwarded-For for the client IP

// Structured request access logger with X-Request-Id
app.use((req, res, next) => {
  const start = Date.now();
  const reqId = req.headers['x-request-id'] || crypto.randomUUID();
  res.setHeader('X-Request-Id', reqId);
  req.id = reqId;

  res.on('finish', () => {
    // Don't flood logs with ALB /health liveness probes unless error
    if (req.path === '/health' && res.statusCode === 200) return;
    log('info', 'http_request', {
      reqId,
      method: req.method,
      path: req.path,
      status: res.statusCode,
      durationMs: Date.now() - start,
      ip: req.ip,
    });
  });
  next();
});

app.use(express.json({ limit: '10kb' }));
app.use(express.static(path.join(__dirname, '..', 'public')));

const PORT = Number(process.env.PORT || 8080);
const BASE_URL = (process.env.BASE_URL || `http://localhost:${PORT}`).replace(/\/$/, '');
const RATE_LIMIT = Number(process.env.RATE_LIMIT_PER_MIN || 20);
const FLUSH_MS = Number(process.env.CLICK_FLUSH_MS || 10000);

function validUrl(s) {
  if (typeof s !== 'string' || s.length > 2048) return false;
  try {
    const u = new URL(s);
    return u.protocol === 'http:' || u.protocol === 'https:';
  } catch { return false; }
}

// Liveness: cheap, used by the ALB target group health check.
app.get('/health', (req, res) => res.json({ status: 'ok' }));

// Readiness: checks dependencies. Useful for debugging and deploy verification.
app.get('/ready', async (req, res) => {
  try {
    await db.pool.query('SELECT 1');
    await cache.ping();
    res.json({ db: 'ok', redis: 'ok' });
  } catch (e) {
    res.status(503).json({ error: e.message });
  }
});

app.post('/api/shorten', async (req, res) => {
  const ok = await cache.allow('shorten:' + req.ip, RATE_LIMIT, 60);
  if (!ok) return res.status(429).json({ error: 'rate limit exceeded' });
  const { url } = req.body || {};
  if (!validUrl(url)) return res.status(400).json({ error: 'url must be a valid http(s) URL' });
  try {
    const code = await db.createUrl(url);
    await cache.setCachedUrl(code, url); // warm the cache
    res.status(201).json({ code, shortUrl: `${BASE_URL}/${code}`, longUrl: url });
  } catch (e) {
    log('error', 'shorten_failed', { error: e.message, stack: e.stack });
    res.status(500).json({ error: 'internal error' });
  }
});

app.get('/api/stats/:code', async (req, res) => {
  try {
    const row = await db.getStats(req.params.code);
    if (!row) return res.status(404).json({ error: 'not found' });
    const pending = await cache.pendingClicks(req.params.code);
    res.json({ ...row, clicks: Number(row.clicks) + pending });
  } catch (e) {
    log('error', 'stats_failed', { code: req.params.code, error: e.message });
    res.status(500).json({ error: 'internal error' });
  }
});

// Hot path: cache first, DB on miss, click counted in Redis (never a DB write per redirect).
app.get('/:code', async (req, res) => {
  const { code } = req.params;
  if (!/^[0-9a-zA-Z]{1,11}$/.test(code)) return res.status(404).send('Not found');
  try {
    let target = await cache.getCachedUrl(code);
    if (target === cache.MISS) return res.status(404).send('Not found');
    if (!target) {
      target = await db.getUrl(code);
      if (!target) {
        await cache.setCachedMiss(code);
        return res.status(404).send('Not found');
      }
      await cache.setCachedUrl(code, target);
    }
    cache.countClick(code); // fire and forget
    res.redirect(302, target); // 302, not 301, so browsers keep hitting us and clicks are counted
  } catch (e) {
    log('error', 'redirect_failed', { code, error: e.message });
    res.status(500).send('Internal error');
  }
});

// Background: move click counters from Redis into Postgres in batches.
async function flushClicks() {
  const drained = await cache.drainClicks();
  for (const [code, n] of drained) {
    try { await db.addClicks(code, n); } catch (e) { log('error', 'flush_failed', { code, error: e.message }); }
  }
}

async function main() {
  await db.init();
  const server = app.listen(PORT, () => log('info', 'server_started', { port: PORT, env: process.env.NODE_ENV || 'development' }));
  const timer = setInterval(flushClicks, FLUSH_MS);

  // Graceful shutdown: ASG scale-in and deploys send SIGTERM. Finish in-flight work, flush counters.
  const shutdown = () => {
    log('info', 'shutdown_initiated');
    clearInterval(timer);
    server.close(async () => {
      await flushClicks();
      await db.pool.end();
      log('info', 'shutdown_complete');
      process.exit(0);
    });
    setTimeout(() => process.exit(1), 10000).unref();
  };
  process.on('SIGTERM', shutdown);
  process.on('SIGINT', shutdown);
}

main().catch((e) => { log('error', 'fatal_init_error', { error: e.message, stack: e.stack }); process.exit(1); });
