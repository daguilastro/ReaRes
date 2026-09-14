import { Hono } from 'hono';
import { hashPassword } from '../../domain/security/password';
import { requireAdmin, requireSession } from '../auth/session';
import { readLayout } from '../repositories/readModel';
import { generatedId, jsonObject, positiveId, rows } from '../shared/http';
import type { CloudEnvironment } from '../types';

const allowedRoles = new Set(['waiter', 'kitchen', 'cashier', 'manager']);
const routes = new Hono<CloudEnvironment>();
routes.use('*', requireSession, requireAdmin);

routes.get('/activities', async (c) => c.json({
  activities: await rows(c.env.DB.prepare(
    `SELECT a.id, COALESCE(u.name, 'System') AS author, a.type,
            a.modification, a.hall_id AS roomId, a.created_at AS createdAt
     FROM activity_log a LEFT JOIN users u ON u.id = a.author_id
     ORDER BY a.id DESC LIMIT 100`,
  )),
}));

routes.get('/overview', async (c) => {
  const period = ['hour', 'day', 'month', 'year'].includes(c.req.query('period') ?? '')
    ? c.req.query('period') as 'hour' | 'day' | 'month' | 'year' : 'day';
  const requested = Number(c.req.query('range'));
  const limits = period === 'day' ? [2, 31] : period === 'month'
    ? [2, 24] : period === 'year' ? [2, 10] : [24, 24];
  const range = Number.isSafeInteger(requested)
    ? Math.max(limits[0], Math.min(limits[1], requested))
    : period === 'day' ? 7 : period === 'month' ? 6 : period === 'year' ? 5 : 24;
  const now = new Date();
  const today = bogotaParts(now);
  const todayStart = localIso(today.year, today.month, today.day);
  const tomorrow = addDays(todayStart, 1);
  const summary = await c.env.DB.prepare(
    `SELECT COALESCE(SUM(COALESCE(oi.unit_value, p.value) * oi.quantity), 0) AS sales,
            COUNT(DISTINCT o.id) AS orders
     FROM orders o LEFT JOIN order_items oi ON oi.order_id = o.id
     LEFT JOIN products p ON p.id = oi.product_id
     WHERE o.status = 'closed' AND o.updated_at >= ? AND o.updated_at < ?`,
  ).bind(todayStart, tomorrow).first<{ sales: number; orders: number }>();
  const points = await Promise.all(revenueBuckets(period, range, todayStart).map(
    async (bucket) => ({
      label: bucket.label,
      value: Number((await c.env.DB.prepare(
        `SELECT COALESCE(SUM(COALESCE(oi.unit_value, p.value) * oi.quantity), 0) AS value
         FROM orders o LEFT JOIN order_items oi ON oi.order_id = o.id
         LEFT JOIN products p ON p.id = oi.product_id
         WHERE o.status = 'closed' AND o.updated_at >= ? AND o.updated_at < ?`,
      ).bind(bucket.start, bucket.end).first<{ value: number }>())?.value ?? 0),
    }),
  ));
  const topProduct = await c.env.DB.prepare(
    `SELECT p.name, COALESCE(oi.unit_value, p.value) AS value,
            SUM(oi.quantity) AS quantity
     FROM orders o JOIN order_items oi ON oi.order_id = o.id
     JOIN products p ON p.id = oi.product_id
     WHERE o.status = 'closed' AND o.updated_at >= ? AND o.updated_at < ?
     GROUP BY p.id ORDER BY quantity DESC, p.name LIMIT 1`,
  ).bind(todayStart, tomorrow).first();
  const categories = await rows(c.env.DB.prepare(
    `SELECT category_paths.name,
            SUM(COALESCE(oi.unit_value, p.value) * oi.quantity) AS value
     FROM orders o JOIN order_items oi ON oi.order_id = o.id
     JOIN products p ON p.id = oi.product_id
     JOIN menu_categories category_paths ON category_paths.id = p.category_id
     WHERE o.status = 'closed' AND o.updated_at >= ? AND o.updated_at < ?
     GROUP BY category_paths.id ORDER BY value DESC LIMIT 4`,
  ).bind(todayStart, tomorrow));
  const sales = Number(summary?.sales ?? 0);
  const orderCount = Number(summary?.orders ?? 0);
  return c.json({
    salesToday: sales,
    ordersToday: orderCount,
    averageTicket: orderCount === 0 ? 0 : Math.round(sales / orderCount),
    points,
    topProduct,
    categories,
  });
});

routes.post('/halls', async (c) => {
  const body = await jsonObject(c);
  if (body instanceof Response) return body;
  const name = typeof body.name === 'string' ? body.name.trim() : '';
  if (name.length < 2 || name.length > 80) {
    return c.json({ error: 'INVALID_ROOM_NAME' }, 422);
  }
  const id = generatedId();
  try {
    await c.env.DB.prepare('INSERT INTO hall (id, name) VALUES (?, ?)').bind(id, name).run();
  } catch (error) {
    if (String(error).includes('UNIQUE')) return c.json({ error: 'ROOM_NAME_TAKEN' }, 409);
    throw error;
  }
  return c.json({ room: hallSummary(id, name) }, 201);
});

routes.get('/employees', async (c) => {
  const employees = await rows<{ id: number; fullName: string; username: string; role: string }>(
    c.env.DB.prepare(
      `SELECT id, name AS fullName, username, role FROM users
       WHERE role != 'admin' ORDER BY name COLLATE NOCASE`,
    ),
  );
  return c.json({ employees: await Promise.all(employees.map(
    (employee) => employeeWithHalls(c.env.DB, employee),
  )) });
});

routes.post('/employees', async (c) => {
  const body = await jsonObject(c);
  if (body instanceof Response) return body;
  const parsed = employeeInput(body, true);
  if (!parsed || !await hallsExist(c.env.DB, parsed.roomIds)) {
    return c.json({ error: 'VALIDATION_ERROR' }, 422);
  }
  const id = generatedId();
  const statements = [
    c.env.DB.prepare(
      'INSERT INTO users (id, name, role, username, password_hash) VALUES (?, ?, ?, ?, ?)',
    ).bind(id, parsed.fullName, parsed.role, parsed.username,
      await hashPassword(parsed.password!)),
    ...parsed.roomIds.map((hallId) => c.env.DB.prepare(
      'INSERT INTO employee_halls (user_id, hall_id) VALUES (?, ?)',
    ).bind(id, hallId)),
  ];
  try {
    await c.env.DB.batch(statements);
  } catch (error) {
    if (String(error).includes('UNIQUE')) return c.json({ error: 'USERNAME_TAKEN' }, 409);
    throw error;
  }
  return c.json({ employee: await employeeWithHalls(c.env.DB, {
    id, fullName: parsed.fullName, username: parsed.username, role: parsed.role,
  }) }, 201);
});

routes.patch('/employees/:employeeId', async (c) => {
  const id = positiveId(c.req.param('employeeId'));
  const existing = id ? await c.env.DB.prepare(
    "SELECT id, name AS fullName, username, role FROM users WHERE id = ? AND role != 'admin'",
  ).bind(id).first<{ id: number; fullName: string; username: string; role: string }>() : null;
  if (!id || !existing) return c.json({ error: 'NOT_FOUND' }, 404);
  const body = await jsonObject(c);
  if (body instanceof Response) return body;
  const role = body.role === undefined ? existing.role : String(body.role);
  const roomIds = body.roomIds === undefined ? undefined : idArray(body.roomIds);
  const password = body.password === undefined ? undefined : String(body.password);
  if (!allowedRoles.has(role) || roomIds === null ||
      (password !== undefined && (password.length < 12 || password.length > 128)) ||
      (roomIds !== undefined && !await hallsExist(c.env.DB, roomIds))) {
    return c.json({ error: 'VALIDATION_ERROR' }, 422);
  }
  const statements: D1PreparedStatement[] = [
    c.env.DB.prepare('UPDATE users SET role = ? WHERE id = ?').bind(role, id),
  ];
  if (password !== undefined) statements.push(c.env.DB.prepare(
    'UPDATE users SET password_hash = ? WHERE id = ?',
  ).bind(await hashPassword(password), id));
  if (roomIds !== undefined) {
    statements.push(c.env.DB.prepare('DELETE FROM employee_halls WHERE user_id = ?').bind(id));
    statements.push(...roomIds.map((hallId) => c.env.DB.prepare(
      'INSERT INTO employee_halls (user_id, hall_id) VALUES (?, ?)',
    ).bind(id, hallId)));
  }
  await c.env.DB.batch(statements);
  return c.json({ employee: await employeeWithHalls(c.env.DB, { ...existing, role }) });
});

routes.delete('/employees/:employeeId', async (c) => {
  const id = positiveId(c.req.param('employeeId'));
  if (!id) return c.json({ error: 'NOT_FOUND' }, 404);
  const result = await c.env.DB.prepare(
    "DELETE FROM users WHERE id = ? AND role != 'admin'",
  ).bind(id).run();
  return result.meta.changes === 0
    ? c.json({ error: 'NOT_FOUND' }, 404) : c.body(null, 204);
});

routes.put('/halls/:hallId/layout', async (c) => {
  const hallId = positiveId(c.req.param('hallId'));
  if (!hallId || !await c.env.DB.prepare('SELECT 1 FROM hall WHERE id = ?')
    .bind(hallId).first()) return c.json({ error: 'ROOM_NOT_FOUND' }, 404);
  if (await c.env.DB.prepare(
    `SELECT 1 FROM orders o LEFT JOIN hall_tables t ON t.id = o.table_id
     WHERE o.status != 'closed' AND COALESCE(o.hall_id, t.hall_id) = ? LIMIT 1`,
  ).bind(hallId).first()) return c.json({ error: 'HALL_HAS_ACTIVE_ORDERS' }, 409);
  const body = await jsonObject(c);
  if (body instanceof Response) return body;
  const layout = parseEditorLayout(body);
  if (!layout) return c.json({ error: 'INVALID_LAYOUT' }, 422);
  const existing = new Set((await rows<{ id: number }>(c.env.DB.prepare(
    'SELECT id FROM hall_tables WHERE hall_id = ?',
  ).bind(hallId))).map(({ id }) => id));
  if (layout.tables.some((table) => table.id > 0 && !existing.has(table.id))) {
    return c.json({ error: 'INVALID_LAYOUT' }, 422);
  }
  const idMap = new Map<number, number>();
  layout.tables.forEach((table) => idMap.set(
    table.id, table.id > 0 ? table.id : generatedId(),
  ));
  const retained = new Set(layout.tables.filter((table) => table.id > 0).map((table) => table.id));
  const statements: D1PreparedStatement[] = [
    c.env.DB.prepare(
      `DELETE FROM table_group_members WHERE group_id IN
       (SELECT id FROM table_groups WHERE hall_id = ?)`,
    ).bind(hallId),
    c.env.DB.prepare('DELETE FROM hall_walls WHERE hall_id = ?').bind(hallId),
    ...[...existing].filter((id) => !retained.has(id)).map((id) =>
      c.env.DB.prepare('DELETE FROM hall_tables WHERE id = ?').bind(id)),
  ];
  for (const table of layout.tables) {
    const id = idMap.get(table.id)!;
    statements.push(table.id > 0
      ? c.env.DB.prepare(
        `UPDATE hall_tables SET identifier = ?, x = ?, y = ?, width = ?, height = ?, rotation = ?
         WHERE id = ? AND hall_id = ?`,
      ).bind(table.identifier, table.x, table.y, table.width, table.height,
        table.rotation, id, hallId)
      : c.env.DB.prepare(
        `INSERT INTO hall_tables
         (id, identifier, x, y, width, height, rotation, status, hall_id)
         VALUES (?, ?, ?, ?, ?, ?, ?, 'available', ?)`,
      ).bind(id, table.identifier, table.x, table.y, table.width, table.height,
        table.rotation, hallId));
  }
  statements.push(...layout.walls.map((wall) => c.env.DB.prepare(
    `INSERT INTO hall_walls (id, hall_id, x, y, width, height, rotation)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).bind(generatedId(), hallId, wall.x, wall.y, wall.width, wall.height, wall.rotation)));
  for (const group of layout.groups) {
    const groupId = group.id > 0 ? group.id : generatedId();
    const known = group.id > 0 && await c.env.DB.prepare(
      'SELECT 1 FROM table_groups WHERE id = ? AND hall_id = ?',
    ).bind(group.id, hallId).first();
    statements.push(known
      ? c.env.DB.prepare('UPDATE table_groups SET visible_identifier = ? WHERE id = ?')
        .bind(group.identifier, groupId)
      : c.env.DB.prepare(
        `INSERT INTO table_groups
         (id, hall_id, visible_identifier, status, created_at)
         VALUES (?, ?, ?, 'available', ?)`,
      ).bind(groupId, hallId, group.identifier, new Date().toISOString()));
    statements.push(...group.tableIds.map((tableId) => c.env.DB.prepare(
      'INSERT INTO table_group_members (group_id, table_id) VALUES (?, ?)',
    ).bind(groupId, idMap.get(tableId)!)));
  }
  try {
    await c.env.DB.batch(statements);
  } catch (error) {
    if (String(error).includes('constraint')) return c.json({ error: 'LAYOUT_SAVE_FAILED' }, 409);
    throw error;
  }
  return c.json(await readLayout(c.env.DB, hallId));
});

function hallSummary(id: number, name: string) {
  return { id, name, tableCount: 0, orderCount: 0, totalSales: 0, averageSale: 0 };
}

async function employeeWithHalls(database: D1Database,
  employee: { id: number; fullName: string; username: string; role: string }) {
  const assigned = await rows<{ hallId: number }>(database.prepare(
    'SELECT hall_id AS hallId FROM employee_halls WHERE user_id = ? ORDER BY hall_id',
  ).bind(employee.id));
  return { ...employee, roomIds: assigned.map(({ hallId }) => hallId) };
}

function employeeInput(body: Record<string, unknown>, passwordRequired: boolean) {
  const fullName = typeof body.fullName === 'string' ? body.fullName.trim() : '';
  const username = typeof body.username === 'string' ? body.username.trim().toLowerCase() : '';
  const password = typeof body.password === 'string' ? body.password : undefined;
  const role = typeof body.role === 'string' ? body.role : '';
  const roomIds = idArray(body.roomIds);
  if (fullName.length < 2 || fullName.length > 100 ||
      !/^[a-z0-9](?:[a-z0-9._-]{1,30}[a-z0-9])?$/.test(username) ||
      !allowedRoles.has(role) || roomIds === null ||
      (passwordRequired && (password === undefined || password.length < 12)) ||
      (password?.length ?? 0) > 128) return undefined;
  return { fullName, username, password, role, roomIds };
}

function idArray(value: unknown): number[] | null {
  if (!Array.isArray(value)) return null;
  const ids = value.map(Number);
  return ids.every((id) => Number.isSafeInteger(id) && id > 0) &&
    new Set(ids).size === ids.length ? ids : null;
}

async function hallsExist(database: D1Database, ids: number[]) {
  if (ids.length === 0) return true;
  const result = await database.prepare(
    `SELECT COUNT(*) AS count FROM hall WHERE id IN (${ids.map(() => '?').join(',')})`,
  ).bind(...ids).first<{ count: number }>();
  return Number(result?.count ?? 0) === ids.length;
}

type Geometry = { x: number; y: number; width: number; height: number; rotation: number };
type EditorTable = Geometry & { id: number; identifier: string };
type EditorGroup = { id: number; identifier: string; tableIds: number[] };

function parseEditorLayout(body: Record<string, unknown>) {
  if (!Array.isArray(body.tables) || !Array.isArray(body.walls) ||
      !Array.isArray(body.groups)) return undefined;
  const tables: EditorTable[] = [];
  const identifiers = new Set<string>();
  const ids = new Set<number>();
  for (const raw of body.tables) {
    if (!object(raw)) return undefined;
    const id = Number(raw.id);
    const identifier = typeof raw.identifier === 'string' ? raw.identifier.trim() : '';
    const geometry = geometryOf(raw, 32);
    if (!Number.isSafeInteger(id) || id === 0 || ids.has(id) || !identifier ||
        identifiers.has(identifier) || !geometry) return undefined;
    ids.add(id); identifiers.add(identifier);
    tables.push({ id, identifier, ...geometry });
  }
  const walls: Geometry[] = [];
  for (const raw of body.walls) {
    if (!object(raw)) return undefined;
    const geometry = geometryOf(raw, 2);
    if (!geometry) return undefined;
    walls.push(geometry);
  }
  const members = new Set<number>();
  const groups: EditorGroup[] = [];
  for (const raw of body.groups) {
    if (!object(raw) || !Array.isArray(raw.tableIds)) return undefined;
    const id = Number(raw.id);
    const tableIds = raw.tableIds.map(Number);
    if (!Number.isSafeInteger(id) || id === 0 || tableIds.length < 2 ||
        tableIds.some((tableId) => !ids.has(tableId) || members.has(tableId))) return undefined;
    tableIds.forEach((id) => members.add(id));
    const identifier = typeof raw.identifier === 'string' && raw.identifier.trim()
      ? raw.identifier.trim().slice(0, 80) : tableIds.join(', ');
    groups.push({ id, identifier, tableIds });
  }
  return { tables, walls, groups };
}

function geometryOf(value: Record<string, unknown>, minimum: number): Geometry | undefined {
  const x = Number(value.x); const y = Number(value.y);
  const width = Number(value.width); const height = Number(value.height);
  const rotation = Number(value.rotation ?? 0);
  return [x, y, width, height, rotation].every(Number.isFinite) &&
    Math.abs(x) <= 30_000 && Math.abs(y) <= 30_000 &&
    width >= minimum && height >= minimum && width <= 5_000 && height <= 5_000
    ? { x, y, width, height, rotation } : undefined;
}

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function bogotaParts(value: Date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Bogota', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(value);
  const get = (type: string) => Number(parts.find((part) => part.type === type)?.value);
  return { year: get('year'), month: get('month'), day: get('day') };
}

function localIso(year: number, month: number, day: number, hour = 0) {
  return new Date(`${year.toString().padStart(4, '0')}-${month.toString().padStart(2, '0')}-${day.toString().padStart(2, '0')}T${hour.toString().padStart(2, '0')}:00:00-05:00`).toISOString();
}

function addDays(iso: string, days: number) {
  return new Date(Date.parse(iso) + days * 86_400_000).toISOString();
}

function revenueBuckets(period: 'hour' | 'day' | 'month' | 'year', range: number,
  todayStart: string) {
  const start = new Date(todayStart);
  const result: Array<{ start: string; end: string; label: string }> = [];
  if (period === 'hour') {
    for (let hour = 0; hour < 24; hour++) {
      const from = new Date(start.getTime() + hour * 3_600_000);
      result.push({ start: from.toISOString(), end: new Date(from.getTime() + 3_600_000).toISOString(),
        label: `${hour.toString().padStart(2, '0')}:00` });
    }
    return result;
  }
  if (period === 'day') {
    for (let offset = range - 1; offset >= 0; offset--) {
      const from = new Date(start.getTime() - offset * 86_400_000);
      result.push({ start: from.toISOString(), end: new Date(from.getTime() + 86_400_000).toISOString(),
        label: `${from.getUTCDate()}/${from.getUTCMonth() + 1}` });
    }
    return result;
  }
  const date = bogotaParts(start);
  for (let offset = range - 1; offset >= 0; offset--) {
    const year = period === 'year' ? date.year - offset : date.year;
    const month = period === 'month' ? date.month - offset : 1;
    const from = new Date(Date.UTC(year, month - 1, 1, 5));
    const end = period === 'year'
      ? new Date(Date.UTC(year + 1, 0, 1, 5))
      : new Date(Date.UTC(year, month, 1, 5));
    result.push({ start: from.toISOString(), end: end.toISOString(),
      label: period === 'year' ? String(year) : `${from.getUTCMonth() + 1}/${from.getUTCFullYear()}` });
  }
  return result;
}

export default routes;
