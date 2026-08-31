import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createAdminPairDeviceRoutes } from '../../admin/routes/pairDevice';
import { setPairingRuntime } from '../../shared/pairingRuntime';

test('creates a hashed, two-minute, authenticated pairing request', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  database.prepare(
    `INSERT INTO users (name, role, username, password_hash)
     VALUES ('Admin', 'admin', 'admin', 'unused')`,
  ).run();
  const token = 'valid-session-token';
  database.prepare(
    `INSERT INTO admin_sessions (user_id, token_hash, created_at, expires_at)
     VALUES (1, ?, ?, ?)`,
  ).run(
    createHash('sha256').update(token).digest('hex'),
    new Date().toISOString(),
    new Date(Date.now() + 60_000).toISOString(),
  );
  setPairingRuntime({ host: '192.168.1.10', port: 43210,
    certificateFingerprint: 'AA:BB' });
  const app = createAdminPairDeviceRoutes({ database });

  assert.equal((await app.request('/pairing-requests', { method: 'POST' })).status, 401);
  const response = await app.request('/pairing-requests', {
    method: 'POST', headers: { authorization: `Bearer ${token}` },
  });
  assert.equal(response.status, 201);
  const payload = await response.json() as { pairingSecret: string; expiresAt: string; host: string; port: number };
  assert.equal(payload.host, '192.168.1.10');
  assert.equal(payload.port, 43210);
  const remaining = Date.parse(payload.expiresAt) - Date.now();
  assert.ok(remaining > 119_000 && remaining <= 120_000);
  const stored = database.prepare('SELECT secret_hash FROM device_pairing_requests').get() as { secret_hash: string };
  assert.notEqual(stored.secret_hash, payload.pairingSecret);
  database.close();
});
