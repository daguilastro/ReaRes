import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { Hono } from 'hono';
import { hashPassword } from './register';
import { roomRealtimeHub } from '../../shared/roomRealtime';
import { openApplicationDatabase } from '../../shared/schemaMigration';

const ALLOWED_ROLES = new Set(['waiter', 'kitchen', 'cashier', 'manager']);
type Options = { database?: DatabaseSync };

type EmployeeRow = {
  id: number;
  fullName: string;
  username: string;
  role: string;
};

export function createAdminEmployeeRoutes(options: Options = {}) {
  const routes = new Hono();
  let database = options.database;
  const db = () => {
    database ??= openApplicationDatabase();
    return database;
  };

  routes.use('*', async (c, next) => {
    const token = c.req.header('authorization')?.match(/^Bearer ([A-Za-z0-9_-]+)$/)?.[1];
    if (!token) return c.json({ error: 'INVALID_SESSION' }, 401);
    const tokenHash = createHash('sha256').update(token).digest('hex');
    const session = db().prepare(
      'SELECT 1 FROM admin_sessions WHERE token_hash = ? AND expires_at > ? LIMIT 1',
    ).get(tokenHash, new Date().toISOString());
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    await next();
  });

  routes.get('/employees', (c) => {
    const rows = db().prepare(
      `SELECT id, name AS fullName, username, role FROM users
       WHERE role != 'admin' ORDER BY name COLLATE NOCASE`,
    ).all() as EmployeeRow[];
    return c.json({ employees: rows.map((row) => readEmployee(db(), row.id)!) });
  });

  routes.post('/employees', async (c) => {
    const data = await readJson(c);
    if (data instanceof Response) return data;
    const validation = validateEmployee(data, true);
    if (!validation.valid) {
      return c.json({ error: 'VALIDATION_ERROR', fields: validation.fields }, 422);
    }
    const roomIds = validateRoomIds(data.roomIds);
    if (!roomIds.valid || !roomsExist(db(), roomIds.value)) {
      return c.json({ error: 'INVALID_ROOMS' }, 422);
    }

    const passwordHash = await hashPassword(validation.password!);
    const database = db();
    try {
      database.exec('BEGIN IMMEDIATE');
      const result = database.prepare(
        'INSERT INTO users (name, role, username, password_hash) VALUES (?, ?, ?, ?)',
      ).run(validation.fullName!, validation.role!, validation.username!, passwordHash);
      const employeeId = Number(result.lastInsertRowid);
      replaceEmployeeRooms(database, employeeId, roomIds.value);
      database.exec('COMMIT');
      roomRealtimeHub.publishAssignmentsChanged(employeeId);
      return c.json({ employee: readEmployee(database, employeeId) }, 201);
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* No había transacción activa. */ }
      if (String(error).includes('UNIQUE constraint failed')) {
        return c.json({ error: 'USERNAME_TAKEN' }, 409);
      }
      throw error;
    }
  });

  routes.patch('/employees/:id', async (c) => {
    const id = Number(c.req.param('id'));
    if (!Number.isSafeInteger(id) || id < 1) return c.json({ error: 'NOT_FOUND' }, 404);
    const existing = db().prepare(
      "SELECT id FROM users WHERE id = ? AND role != 'admin'",
    ).get(id);
    if (!existing) return c.json({ error: 'NOT_FOUND' }, 404);
    const data = await readJson(c);
    if (data instanceof Response) return data;
    const role = typeof data.role === 'string' ? data.role : undefined;
    const password = typeof data.password === 'string' ? data.password : undefined;
    const roomIds = data.roomIds === undefined ? undefined : validateRoomIds(data.roomIds);
    if (role === undefined && password === undefined && roomIds === undefined) {
      return c.json({ error: 'VALIDATION_ERROR' }, 422);
    }
    if (role !== undefined && !ALLOWED_ROLES.has(role)) {
      return c.json({ error: 'INVALID_ROLE' }, 422);
    }
    if (password !== undefined && (password.length < 12 || password.length > 128)) {
      return c.json({ error: 'INVALID_PASSWORD' }, 422);
    }
    if (roomIds !== undefined && (!roomIds.valid || !roomsExist(db(), roomIds.value))) {
      return c.json({ error: 'INVALID_ROOMS' }, 422);
    }

    const passwordHash = password === undefined ? undefined : await hashPassword(password);
    const database = db();
    try {
      database.exec('BEGIN IMMEDIATE');
      if (role !== undefined) {
        database.prepare('UPDATE users SET role = ? WHERE id = ?').run(role, id);
      }
      if (passwordHash !== undefined) {
        database.prepare('UPDATE users SET password_hash = ? WHERE id = ?').run(passwordHash, id);
      }
      if (roomIds !== undefined) replaceEmployeeRooms(database, id, roomIds.value);
      database.exec('COMMIT');
      if (roomIds !== undefined) roomRealtimeHub.publishAssignmentsChanged(id);
      return c.json({ employee: readEmployee(database, id) });
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* No había transacción activa. */ }
      throw error;
    }
  });

  routes.delete('/employees/:id', (c) => {
    const id = Number(c.req.param('id'));
    if (!Number.isSafeInteger(id) || id < 1) return c.json({ error: 'NOT_FOUND' }, 404);
    const result = db().prepare("DELETE FROM users WHERE id = ? AND role != 'admin'").run(id);
    if (result.changes === 0) return c.json({ error: 'NOT_FOUND' }, 404);
    roomRealtimeHub.disconnectUser(id);
    return c.body(null, 204);
  });
  return routes;
}

function readEmployee(database: DatabaseSync, id: number) {
  const employee = database.prepare(
    `SELECT id, name AS fullName, username, role FROM users
     WHERE id = ? AND role != 'admin'`,
  ).get(id) as EmployeeRow | undefined;
  if (!employee) return undefined;
  const roomIds = (database.prepare(
    'SELECT hall_id AS hallId FROM employee_halls WHERE user_id = ? ORDER BY hall_id',
  ).all(id) as Array<{ hallId: number }>).map(({ hallId }) => hallId);
  return { ...employee, roomIds };
}

function replaceEmployeeRooms(database: DatabaseSync, employeeId: number, roomIds: number[]) {
  database.prepare('DELETE FROM employee_halls WHERE user_id = ?').run(employeeId);
  const insert = database.prepare(
    'INSERT INTO employee_halls (user_id, hall_id) VALUES (?, ?)',
  );
  for (const roomId of roomIds) insert.run(employeeId, roomId);
}

function roomsExist(database: DatabaseSync, roomIds: number[]) {
  if (roomIds.length === 0) return true;
  const placeholders = roomIds.map(() => '?').join(', ');
  const row = database.prepare(
    `SELECT COUNT(*) AS count FROM hall WHERE id IN (${placeholders})`,
  ).get(...roomIds) as { count: number };
  return row.count === roomIds.length;
}

function validateRoomIds(value: unknown):
  { valid: true; value: number[] } | { valid: false; value: [] } {
  if (value === undefined) return { valid: true, value: [] };
  if (!Array.isArray(value)) return { valid: false, value: [] };
  const ids = value.filter((id): id is number => Number.isSafeInteger(id) && id > 0);
  if (ids.length !== value.length || new Set(ids).size !== ids.length) {
    return { valid: false, value: [] };
  }
  return { valid: true, value: ids };
}

async function readJson(c: any): Promise<Record<string, unknown> | Response> {
  try {
    const value: unknown = await c.req.json();
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return c.json({ error: 'INVALID_JSON' }, 400);
    }
    return value as Record<string, unknown>;
  } catch {
    return c.json({ error: 'INVALID_JSON' }, 400);
  }
}

function validateEmployee(data: Record<string, unknown>, requirePassword: boolean) {
  const fullName = typeof data.fullName === 'string' ? data.fullName.trim() : '';
  const username = typeof data.username === 'string' ? data.username.trim().toLowerCase() : '';
  const password = typeof data.password === 'string' ? data.password : '';
  const role = typeof data.role === 'string' ? data.role : '';
  const fields: Record<string, string> = {};
  if (fullName.length < 2 || fullName.length > 100) fields.fullName = 'INVALID';
  if (!/^[a-z0-9](?:[a-z0-9._-]{1,30}[a-z0-9])?$/.test(username)) fields.username = 'INVALID';
  if (requirePassword && (password.length < 12 || password.length > 128)) fields.password = 'INVALID';
  if (!ALLOWED_ROLES.has(role)) fields.role = 'INVALID';
  return { valid: Object.keys(fields).length === 0, fields, fullName, username, password, role };
}

export default createAdminEmployeeRoutes();
