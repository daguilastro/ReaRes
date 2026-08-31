import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createDeviceApp } from '../../device/app';
import { hashPassword } from '../../shared/password';

test('restores an employee session only for its paired certificate', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  database.prepare(
    `INSERT INTO users (id, name, role, username, password_hash)
     VALUES (1, 'Carlos Ruiz', 'waiter', 'carlos', ?)`,
  ).run(await hashPassword('employee-password'));
  database.prepare(
    `INSERT INTO paired_devices
     (id, name, certificate_fingerprint, certificate_serial,
      certificate_pem, paired_at)
     VALUES (1, 'Phone A', 'AA:BB', '01', 'certificate-a', ?),
            (2, 'Phone B', 'CC:DD', '02', 'certificate-b', ?)`,
  ).run(new Date().toISOString(), new Date().toISOString());

  let fingerprint = 'AA:BB';
  const app = createDeviceApp({
    database,
    resolveClientIdentity: () => ({
      fingerprint,
      serialNumber: fingerprint == 'AA:BB' ? '01' : '02',
      certificatePem: fingerprint == 'AA:BB'
        ? 'certificate-a'
        : 'certificate-b',
    }),
  });

  const logIn = async () => {
    const response = await app.request('/auth/login', {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        username: 'carlos',
        password: 'employee-password',
      }),
    });
    assert.equal(response.status, 200);
    return response.json() as Promise<{ token: string; expiresAt: string }>;
  };

  const first = await logIn();
  const remaining = Date.parse(first.expiresAt) - Date.now();
  assert.ok(remaining > 11.9 * 60 * 60 * 1000);
  assert.ok(remaining <= 12 * 60 * 60 * 1000);
  const firstRestore = await app.request('/auth/session', {
    headers: { authorization: `Bearer ${first.token}` },
  });
  assert.equal(firstRestore.status, 200);
  const restored = await firstRestore.json() as Record<string, unknown>;
  assert.equal(restored.expiresAt, first.expiresAt);
  assert.equal((restored.user as { fullName: string }).fullName, 'Carlos Ruiz');
  assert.equal('token' in restored, false);

  fingerprint = 'CC:DD';
  assert.equal((await app.request('/auth/session', {
    headers: { authorization: `Bearer ${first.token}` },
  })).status, 401);

  fingerprint = 'AA:BB';
  const second = await logIn();
  assert.notEqual(second.token, first.token);
  assert.equal((database.prepare(
    'SELECT COUNT(*) AS count FROM employee_sessions',
  ).get() as { count: number }).count, 1);
  assert.equal((await app.request('/auth/session', {
    headers: { authorization: `Bearer ${first.token}` },
  })).status, 401);
  assert.equal((await app.request('/auth/session', {
    headers: { authorization: `Bearer ${second.token}` },
  })).status, 200);

  const logout = await app.request('/auth/logout', {
    method: 'POST',
    headers: { authorization: `Bearer ${second.token}` },
  });
  assert.equal(logout.status, 204);
  assert.equal((await app.request('/auth/session', {
    headers: { authorization: `Bearer ${second.token}` },
  })).status, 401);

  const expired = await logIn();
  database.prepare(
    'UPDATE employee_sessions SET expires_at = ? WHERE user_id = 1',
  ).run(new Date(Date.now() - 1000).toISOString());
  assert.equal((await app.request('/auth/session', {
    headers: { authorization: `Bearer ${expired.token}` },
  })).status, 401);
  database.close();
});
