import { createHash, randomBytes } from 'node:crypto';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import { Hono } from 'hono';
import { verifyPassword } from '../../shared/password';

const SESSION_DURATION_MS = 12 * 60 * 60 * 1000;

type Options = { database?: DatabaseSync };

const tokenHash = (token: string) =>
  createHash('sha256').update(token, 'utf8').digest('hex');

function bearerToken(header?: string) {
  const match = header?.match(/^Bearer ([A-Za-z0-9_-]+)$/);
  return match?.[1];
}

export function createAdminSessionRoutes(options: Options = {}) {
  const routes = new Hono();
  let database = options.database;
  const db = () => {
    database ??= new DatabaseSync(join(process.cwd(), 'db', 'restaurant.sqlite'));
    database.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');
    return database;
  };

  routes.post('/login', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ error: 'INVALID_JSON' }, 400); }
    if (typeof body !== 'object' || body === null || Array.isArray(body))
      return c.json({ error: 'INVALID_CREDENTIALS' }, 401);
    const data = body as Record<string, unknown>;
    const username = typeof data.username === 'string' ? data.username.trim().toLowerCase() : '';
    const password = typeof data.password === 'string' ? data.password : '';
    const user = db().prepare(
      `SELECT id, name, username, role, password_hash FROM users
       WHERE username = ? AND role = 'admin' LIMIT 1`,
    ).get(username) as { id: number; name: string; username: string; role: string; password_hash: string } | undefined;
    if (!user || !(await verifyPassword(password, user.password_hash)))
      return c.json({ error: 'INVALID_CREDENTIALS', message: 'Usuario o contraseña incorrectos.' }, 401);

    const token = randomBytes(32).toString('base64url');
    const now = new Date();
    const expiresAt = new Date(now.getTime() + SESSION_DURATION_MS);
    db().prepare('DELETE FROM admin_sessions WHERE expires_at <= ?').run(now.toISOString());
    db().prepare(
      'INSERT INTO admin_sessions (user_id, token_hash, created_at, expires_at) VALUES (?, ?, ?, ?)',
    ).run(user.id, tokenHash(token), now.toISOString(), expiresAt.toISOString());
    return c.json({
      token,
      expiresAt: expiresAt.toISOString(),
      admin: { id: user.id, fullName: user.name, username: user.username, role: user.role },
    });
  });

  const readSession = (authorization?: string) => {
    const token = bearerToken(authorization);
    if (!token) return undefined;
    const row = db().prepare(
      `SELECT s.id AS session_id, s.expires_at, u.id, u.name, u.username, u.role
       FROM admin_sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = ? AND u.role = 'admin' LIMIT 1`,
    ).get(tokenHash(token)) as { session_id: number; expires_at: string; id: number; name: string; username: string; role: string } | undefined;
    if (!row) return undefined;
    if (Date.parse(row.expires_at) <= Date.now()) {
      db().prepare('DELETE FROM admin_sessions WHERE id = ?').run(row.session_id);
      return undefined;
    }
    return { token, row };
  };

  routes.get('/session', (c) => {
    const session = readSession(c.req.header('authorization'));
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const { row } = session;
    return c.json({ expiresAt: row.expires_at, admin: { id: row.id, fullName: row.name, username: row.username, role: row.role } });
  });

  routes.post('/logout', (c) => {
    const token = bearerToken(c.req.header('authorization'));
    if (token) db().prepare('DELETE FROM admin_sessions WHERE token_hash = ?').run(tokenHash(token));
    return c.body(null, 204);
  });

  return routes;
}

export default createAdminSessionRoutes();
