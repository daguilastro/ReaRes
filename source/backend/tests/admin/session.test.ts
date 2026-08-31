import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createAdminRegistrationRoutes } from '../../admin/routes/register';
import { createAdminSessionRoutes } from '../../admin/routes/session';

test('creates, verifies and revokes a 12-hour admin session', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  const registration = createAdminRegistrationRoutes({ database });
  await registration.request('/register', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ fullName: 'Admin Test', username: 'admin.test', password: 'a-secure-password' }),
  });
  const sessions = createAdminSessionRoutes({ database });
  const login = await sessions.request('/login', {
    method: 'POST', headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username: 'admin.test', password: 'a-secure-password' }),
  });
  assert.equal(login.status, 200);
  const payload = await login.json() as { token: string; expiresAt: string };
  const remaining = Date.parse(payload.expiresAt) - Date.now();
  assert.ok(remaining > 11.9 * 60 * 60 * 1000 && remaining <= 12 * 60 * 60 * 1000);
  const stored = database.prepare('SELECT token_hash FROM admin_sessions').get() as { token_hash: string };
  assert.notEqual(stored.token_hash, payload.token);

  const authorization = { authorization: `Bearer ${payload.token}` };
  assert.equal((await sessions.request('/session', { headers: authorization })).status, 200);
  assert.equal((await sessions.request('/logout', { method: 'POST', headers: authorization })).status, 204);
  assert.equal((await sessions.request('/session', { headers: authorization })).status, 401);
  database.close();
});
