import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createDeviceApp } from '../../device/app';

const identity = {
  fingerprint: 'AA:BB:CC',
  serialNumber: '1234',
  certificatePem: 'client-certificate',
};

test('the same certificate can pair again with a fresh invitation', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  const app = createDeviceApp({
    database,
    resolveClientIdentity: () => identity,
  });

  const pair = async (id: string, secret: string) => {
    database.prepare(
      `INSERT INTO device_pairing_requests
       (id, secret_hash, created_at, expires_at) VALUES (?, ?, ?, ?)`,
    ).run(
      id,
      createHash('sha256').update(secret).digest('hex'),
      new Date().toISOString(),
      new Date(Date.now() + 120_000).toISOString(),
    );
    return app.request('/pairing/complete', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        pairingId: id,
        pairingSecret: secret,
        deviceName: 'Android waiter',
      }),
    });
  };

  assert.equal((await pair('first', 'secret-one')).status, 200);
  assert.equal((await app.request('/device/connection')).status, 200);
  assert.equal((await pair('second', 'secret-two')).status, 200);
  assert.equal(
    (database.prepare('SELECT COUNT(*) AS count FROM paired_devices').get() as
      { count: number }).count,
    1,
  );
  assert.equal(
    (database.prepare(
      'SELECT name FROM paired_devices WHERE certificate_fingerprint = ?',
    ).get(identity.fingerprint) as { name: string }).name,
    'Android waiter',
  );
  database.close();
});
