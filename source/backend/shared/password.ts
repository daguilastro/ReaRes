import { randomBytes, scrypt, timingSafeEqual } from 'node:crypto';

const SCRYPT_COST = 2 ** 17;
const SCRYPT_BLOCK_SIZE = 8;
const SCRYPT_PARALLELISM = 1;
const SCRYPT_KEY_LENGTH = 64;
const SCRYPT_MAX_MEMORY = 256 * 1024 * 1024;

export async function hashPassword(password: string): Promise<string> {
  const salt = randomBytes(16);
  const derivedKey = await new Promise<Buffer>((resolve, reject) => {
    scrypt(password, salt, SCRYPT_KEY_LENGTH, {
      N: SCRYPT_COST,
      r: SCRYPT_BLOCK_SIZE,
      p: SCRYPT_PARALLELISM,
      maxmem: SCRYPT_MAX_MEMORY,
    }, (error, key) => error ? reject(error) : resolve(key));
  });
  return ['scrypt', SCRYPT_COST, SCRYPT_BLOCK_SIZE, SCRYPT_PARALLELISM,
    salt.toString('base64'), derivedKey.toString('base64')].join('$');
}

export async function verifyPassword(password: string, encoded: string) {
  const [algorithm, n, r, p, salt, expected] = encoded.split('$');
  if (algorithm !== 'scrypt' || !n || !r || !p || !salt || !expected) return false;
  const expectedKey = Buffer.from(expected, 'base64');
  try {
    const actual = await new Promise<Buffer>((resolve, reject) => {
      scrypt(password, Buffer.from(salt, 'base64'), expectedKey.length, {
        N: Number(n), r: Number(r), p: Number(p), maxmem: SCRYPT_MAX_MEMORY,
      }, (error, key) => error ? reject(error) : resolve(key));
    });
    return actual.length === expectedKey.length && timingSafeEqual(actual, expectedKey);
  } catch {
    return false;
  }
}
