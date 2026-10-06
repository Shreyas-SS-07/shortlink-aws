const test = require('node:test');
const assert = require('node:assert');
const { encode, decode } = require('../src/id');

test('encode/decode round trip', () => {
  for (const n of [0, 1, 61, 62, 100000, 123456789, 9007199254740993n]) {
    assert.strictEqual(decode(encode(n)), BigInt(n));
  }
});

test('codes stay short for a large keyspace', () => {
  assert.ok(encode(62n ** 7n - 1n).length <= 7); // ~3.5 trillion URLs in 7 chars
});

test('rejects invalid input', () => {
  assert.throws(() => encode(-1));
  assert.throws(() => decode('ab-c'));
});
