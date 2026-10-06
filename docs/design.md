# Design doc: ShortLink

## Requirements
- Create a short link from a long URL; redirect from short link to long URL.
- Click counts per link.
- Redirect latency matters most. Reads dominate writes (assume 100:1).
- Survive loss of an instance, and (with Multi-AZ on) loss of an AZ.

## Back-of-envelope (fill in with your own numbers after load testing)
- 100M new links/year is about 3 writes/sec average; peak 10x is about 30/sec. Trivial for Postgres.
- 100:1 read ratio gives about 300 redirects/sec average, 3,000/sec peak. This is why the redirect path is cache-first.
- 7 base62 characters give 62^7 = 3.5 trillion codes. More than enough.
- Storage: about 500 bytes per row x 100M is about 50 GB per year. One RDS instance handles this.

## Key decisions and trade-offs
| Decision | Why | Trade-off |
|---|---|---|
| Code = base62(Postgres sequence) | Unique with no collision retries, safe under concurrency | Codes are guessable and enumerable. Mitigation: scramble the id (e.g. multiplicative permutation) or add random salt |
| Cache-aside with Redis, 1h TTL | Keeps most redirects off the DB | Stale entry possible if a link is edited or deleted (no edit/delete yet) |
| Negative caching (60s) | Scans for random codes don't hammer Postgres | Newly created code could 404 for up to 60s if probed first. Creation warms the cache, which fixes the common case |
| 302, not 301 | Browsers don't cache the redirect, so every click reaches us and is counted | More traffic than a 301 |
| Clicks: INCR in Redis, batch flush to Postgres every 10s | No DB write on the hot path | Up to 10s of counts lost if Redis dies before a flush. Acceptable for analytics; not for billing. The SCAN+GETDEL drain is safe against double-counting (second GETDEL returns null) but two instances racing can drop clicks silently — use a Lua script to fix at scale |
| Redis failure = degrade, not fail | Cache helpers swallow errors and fall back to the DB | DB takes full load during a Redis outage, so size accordingly |
| Rate limit fails open | Availability over strictness | Abuse possible during a Redis outage |
| ALB health check on /health (no deps) | A DB blip shouldn't cause the ASG to kill every instance at once | Unhealthy dependencies aren't detected by the ALB (use /ready and alarms) |
| Private app and data subnets, SG chaining | Only the ALB is internet-facing | NAT gateway cost |
| RDS-managed master password (Secrets Manager) | No secret in code or Terraform state | Instances need IAM permission to read it |

## Failure modes to demo (Week 4)
1. Terminate an app instance: ALB stops routing to it, ASG replaces it.
2. Reboot RDS with failover (Multi-AZ on): measure downtime.
3. Stop Redis traffic (edit the SG): confirm redirects still work, and record latency and DB CPU.
4. Load spike: confirm the ASG scales out; record time to scale.

## What I would change at 100x scale
- Read replicas for Postgres, or move the link store to DynamoDB (key-value access by code is a perfect fit).
- Redis cluster with replicas and automatic failover.
- CloudFront in front of redirects for hot links, cached at the edge.
- Click events into Kinesis/SQS with a Lambda consumer and a proper analytics store (this is the serverless project).
- Multi-region active-active with Route 53 latency routing.
- Distributed ID generation (Snowflake-style or pre-allocated ranges per instance) if a single sequence becomes a bottleneck.
