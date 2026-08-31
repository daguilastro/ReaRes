import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createAdminRegistrationRoutes } from '../../admin/routes/register';

test('registers an admin in users with a hashed password', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  const app = createAdminRegistrationRoutes({ database });

  const response = await app.request('/register', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      fullName: 'Jane Doe',
      username: 'jane.doe',
      password: 'a-secure-password',
    }),
  });

  assert.equal(response.status, 201);
  const user = database
    .prepare('SELECT id, role, password_hash FROM users LIMIT 1')
    .get() as { id: number; role: string; password_hash: string };
  assert.equal(user.id, 1);
  assert.equal(user.role, 'admin');
  assert.match(user.password_hash, /^scrypt\$/);
  assert.doesNotMatch(user.password_hash, /a-secure-password/);
  database.close();
});
