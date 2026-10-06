// Base62 encoding of a database sequence value.
// Unique by construction (no collision checks), short, and safe under concurrency.
const ALPHABET = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';

function encode(n) {
  let x = BigInt(n);
  if (x < 0n) throw new RangeError('id must be non-negative');
  if (x === 0n) return ALPHABET[0];
  let out = '';
  while (x > 0n) {
    out = ALPHABET[Number(x % 62n)] + out;
    x /= 62n;
  }
  return out;
}

function decode(s) {
  let n = 0n;
  for (const ch of s) {
    const i = ALPHABET.indexOf(ch);
    if (i === -1) throw new RangeError('invalid character: ' + ch);
    n = n * 62n + BigInt(i);
  }
  return n;
}

module.exports = { encode, decode };
