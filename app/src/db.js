const { Pool } = require('pg');
const { encode } = require('./id');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: Number(process.env.DB_PORT || 5432),
  user: process.env.DB_USER || 'shortlink',
  password: process.env.DB_PASSWORD || 'shortlink',
  database: process.env.DB_NAME || 'shortlink',
  max: Number(process.env.DB_POOL_MAX || 10),
  connectionTimeoutMillis: 3000,
  // RDS (Postgres 15+) enforces TLS by default.
  ssl: process.env.DB_SSL === 'true' ? { rejectUnauthorized: false } : false,
});

async function init() {
  await pool.query(`
    CREATE SEQUENCE IF NOT EXISTS url_id_seq START 100000;
    CREATE TABLE IF NOT EXISTS urls (
      id         BIGINT PRIMARY KEY DEFAULT nextval('url_id_seq'),
      code       TEXT UNIQUE NOT NULL,
      long_url   TEXT NOT NULL,
      created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
      clicks     BIGINT NOT NULL DEFAULT 0
    );
  `);
}

async function createUrl(longUrl) {
  const { rows } = await pool.query("SELECT nextval('url_id_seq') AS id");
  const code = encode(rows[0].id);
  await pool.query('INSERT INTO urls (id, code, long_url) VALUES ($1, $2, $3)', [rows[0].id, code, longUrl]);
  return code;
}

async function getUrl(code) {
  const { rows } = await pool.query('SELECT long_url FROM urls WHERE code = $1', [code]);
  return rows[0] ? rows[0].long_url : null;
}

async function getStats(code) {
  const { rows } = await pool.query(
    'SELECT code, long_url, created_at, clicks FROM urls WHERE code = $1', [code]);
  return rows[0] || null;
}

async function addClicks(code, n) {
  await pool.query('UPDATE urls SET clicks = clicks + $2 WHERE code = $1', [code, n]);
}

module.exports = { pool, init, createUrl, getUrl, getStats, addClicks };
