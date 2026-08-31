import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createAdminEmployeeRoutes } from '../../admin/routes/employees';

test('an admin session can create, update and delete an employee', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  database.prepare("INSERT INTO users (name, role, username, password_hash) VALUES ('Admin', 'admin', 'admin', 'hash')").run();
  database.prepare("INSERT INTO hall (id, name) VALUES (1, 'Main Hall'), (2, 'Terraza')").run();
  const token = 'admin-session';
  database.prepare(`INSERT INTO admin_sessions (user_id, token_hash, created_at, expires_at)
    VALUES (1, ?, ?, ?)`).run(createHash('sha256').update(token).digest('hex'),
      new Date().toISOString(), new Date(Date.now() + 60_000).toISOString());
  const app = createAdminEmployeeRoutes({ database });
  const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json' };

  const created = await app.request('/employees', { method: 'POST', headers,
    body: JSON.stringify({ fullName: 'Carlos Ruiz', username: 'carlos.r',
      password: 'secure-password', role: 'waiter', roomIds: [1, 2] }) });
  assert.equal(created.status, 201);
  assert.deepEqual((await created.json() as { employee: { roomIds: number[] } })
    .employee.roomIds, [1, 2]);
  const stored = database
    .prepare("SELECT id, role, password_hash FROM users WHERE username = 'carlos.r'")
    .get() as { id: number; role: string; password_hash: string };
  assert.equal(stored.role, 'waiter');
  assert.match(stored.password_hash, /^scrypt\$/);

  const updated = await app.request(`/employees/${stored.id}`, { method: 'PATCH', headers,
    body: JSON.stringify({ role: 'cashier', password: 'another-password', roomIds: [2] }) });
  assert.equal(updated.status, 200);
  assert.equal((database.prepare('SELECT role FROM users WHERE id = ?').get(stored.id) as { role: string }).role, 'cashier');
  assert.deepEqual((database.prepare(
    'SELECT hall_id AS hallId FROM employee_halls WHERE user_id = ?',
  ).all(stored.id) as Array<{ hallId: number }>).map(({ hallId }) => hallId), [2]);

  const invalidRoom = await app.request(`/employees/${stored.id}`, {
    method: 'PATCH', headers, body: JSON.stringify({ roomIds: [999] }),
  });
  assert.equal(invalidRoom.status, 422);
  assert.equal((await app.request(`/employees/${stored.id}`, { method: 'DELETE', headers })).status, 204);
  assert.equal(database.prepare('SELECT 1 FROM users WHERE id = ?').get(stored.id), undefined);
  assert.equal(database.prepare(
    'SELECT 1 FROM employee_halls WHERE user_id = ?',
  ).get(stored.id), undefined);
  database.close();
});
