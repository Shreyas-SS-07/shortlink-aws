// Usage: BASE_URL=http://<alb-dns> k6 run loadtest/k6.js
// Mix: 95% redirects (hot path), 5% link creation. Redirects are NOT followed,
// so we measure our service, not the destination site.
import http from 'k6/http';
import { check } from 'k6';

const BASE = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
  stages: [
    { duration: '1m', target: 50 },
    { duration: '3m', target: 300 },  // watch the ASG scale out here
    { duration: '2m', target: 300 },
    { duration: '1m', target: 0 },
  ],
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<300'],
  },
};

export function setup() {
  const codes = [];
  for (let i = 0; i < 100; i++) {
    const r = http.post(`${BASE}/api/shorten`,
      JSON.stringify({ url: `https://example.com/page/${i}` }),
      { headers: { 'Content-Type': 'application/json' } });
    if (r.status === 201) codes.push(r.json('code'));
    // The create endpoint is rate limited per IP (20/min by default). Raise
    // RATE_LIMIT_PER_MIN on the app for load tests, or seed codes directly.
  }
  return { codes };
}

export default function (data) {
  if (Math.random() < 0.05) {
    const r = http.post(`${BASE}/api/shorten`,
      JSON.stringify({ url: `https://example.com/t/${Math.random()}` }),
      { headers: { 'Content-Type': 'application/json' } });
    check(r, { 'create ok or limited': (x) => x.status === 201 || x.status === 429 });
  } else {
    const code = data.codes[Math.floor(Math.random() * data.codes.length)];
    const r = http.get(`${BASE}/${code}`, { redirects: 0 });
    check(r, { 'redirect 302': (x) => x.status === 302 });
  }
}
