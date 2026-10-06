const Redis = require('ioredis');

const redis = new Redis(process.env.REDIS_URL || 'redis://localhost:6379', {
  maxRetriesPerRequest: 1,
  enableOfflineQueue: false, // fail fast instead of piling up requests when Redis is down
});
redis.on('error', (e) => console.error('[redis]', e.message));

const URL_TTL = 3600;     // cache hits for 1 hour
const MISS_TTL = 60;      // negative-cache unknown codes for 1 minute (protects the DB from scans)
const MISS = '__miss__';

// Every helper degrades gracefully: if Redis is down, the service keeps working off Postgres.
async function safe(fn, fallback) {
  try { return await fn(); } catch (e) { return fallback; }
}

const getCachedUrl = (code) => safe(() => redis.get('url:' + code), null);
const setCachedUrl = (code, url) => safe(() => redis.set('url:' + code, url, 'EX', URL_TTL), null);
const setCachedMiss = (code) => safe(() => redis.set('url:' + code, MISS, 'EX', MISS_TTL), null);
const countClick = (code) => safe(() => redis.incr('clicks:' + code), null);
const pendingClicks = (code) => safe(async () => Number((await redis.get('clicks:' + code)) || 0), 0);

// Fixed-window rate limiter. Returns true if the request is allowed.
async function allow(key, limit, windowSec) {
  return safe(async () => {
    const k = `rl:${key}:${Math.floor(Date.now() / 1000 / windowSec)}`;
    const n = await redis.incr(k);
    if (n === 1) await redis.expire(k, windowSec);
    return n <= limit;
  }, true); // fail open
}

// Atomically drain click counters (GETDEL) so multiple instances never double count.
async function drainClicks() {
  const drained = [];
  await safe(async () => {
    let cursor = '0';
    do {
      const [next, keys] = await redis.scan(cursor, 'MATCH', 'clicks:*', 'COUNT', 200);
      cursor = next;
      for (const key of keys) {
        const v = await redis.getdel(key);
        if (v) drained.push([key.slice('clicks:'.length), Number(v)]);
      }
    } while (cursor !== '0');
  }, null);
  return drained;
}

const ping = () => redis.ping();

module.exports = { MISS, getCachedUrl, setCachedUrl, setCachedMiss, countClick, pendingClicks, allow, drainClicks, ping };
