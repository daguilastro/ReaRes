import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { Hono } from 'hono';
import { ensureLayoutSchema, openApplicationDatabase } from '../../shared/schemaMigration';
import { roomRealtimeHub } from '../../shared/roomRealtime';
import { persistLogicalGroups } from '../../shared/logicalTables';

type Options = { database?: DatabaseSync };
type Geometry = { x: number; y: number; width: number; height: number; rotation: number };
type LayoutTable = Geometry & { id: number; identifier: string };
type LayoutWall = Geometry & { id?: number };
type LayoutGroup = { id?: number; identifier?: string; tableIds: number[] };
type LayoutPayload = { tables: LayoutTable[]; walls: LayoutWall[]; groups: LayoutGroup[] };

const hashToken = (token: string) => createHash('sha256').update(token).digest('hex');
const finite = (value: unknown): value is number =>
  typeof value === 'number' && Number.isFinite(value);

export function createAdminLayoutRoutes(options: Options = {}) {
  const routes = new Hono();
  let database = options.database;
  const db = () => {
    if (!database) database = openApplicationDatabase();
    else ensureLayoutSchema(database);
    return database;
  };

  routes.use('*', async (c, next) => {
    const token = c.req.header('authorization')?.match(/^Bearer ([A-Za-z0-9_-]+)$/)?.[1];
    if (!token) return c.json({ error: 'INVALID_SESSION' }, 401);
    const admin = db().prepare(
      `SELECT 1 FROM admin_sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = ? AND s.expires_at > ? AND u.role = 'admin' LIMIT 1`,
    ).get(hashToken(token), new Date().toISOString());
    if (!admin) return c.json({ error: 'ADMIN_REQUIRED' }, 403);
    await next();
  });

  routes.get('/rooms', (c) => {
    const rooms = db().prepare(
      `WITH order_totals AS (
         SELECT o.id AS order_id, t.hall_id,
                COALESCE(SUM(p.value * oi.quantity), 0) AS total
         FROM orders o
         JOIN hall_tables t ON t.id = o.table_id
         LEFT JOIN order_items oi ON oi.order_id = o.id
         LEFT JOIN products p ON p.id = oi.product_id
         WHERE o.status = 'closed'
         GROUP BY o.id
       )
       SELECT h.id, h.name,
              (SELECT COUNT(*) FROM hall_tables count_tables
               WHERE count_tables.hall_id = h.id) AS tableCount,
              COUNT(DISTINCT ot.order_id) AS orderCount,
              COALESCE(SUM(ot.total), 0) AS totalSales,
              COALESCE(AVG(ot.total), 0) AS averageSale
       FROM hall h
       LEFT JOIN order_totals ot ON ot.hall_id = h.id
       GROUP BY h.id ORDER BY h.name COLLATE NOCASE`,
    ).all();
    return c.json({ rooms });
  });

  routes.get('/overview', (c) => {
    const period = ['hour', 'day', 'month', 'year'].includes(c.req.query('period') ?? '')
      ? c.req.query('period') as 'hour' | 'day' | 'month' | 'year'
      : 'day';
    const requestedRange = Number(c.req.query('range'));
    const limits = period === 'day' ? [2, 31] : period === 'month'
      ? [2, 24] : period === 'year' ? [2, 10] : [24, 24];
    const range = Number.isSafeInteger(requestedRange)
      ? Math.max(limits[0], Math.min(limits[1], requestedRange))
      : period === 'day' ? 7 : period === 'month' ? 6 : period === 'year' ? 5 : 24;
    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const tomorrow = new Date(todayStart);
    tomorrow.setDate(tomorrow.getDate() + 1);
    const summary = db().prepare(
      `SELECT COALESCE(SUM(p.value * oi.quantity), 0) AS sales,
              COUNT(DISTINCT o.id) AS orders
       FROM orders o
       LEFT JOIN order_items oi ON oi.order_id = o.id
       LEFT JOIN products p ON p.id = oi.product_id
       WHERE o.status = 'closed'
         AND o.updated_at >= ? AND o.updated_at < ?`,
    ).get(todayStart.toISOString(), tomorrow.toISOString()) as {
      sales: number; orders: number;
    };
    const points = revenueBuckets(period, range, now).map((bucket) => ({
      label: bucket.label,
      value: Number((db().prepare(
        `SELECT COALESCE(SUM(p.value * oi.quantity), 0) AS value
         FROM orders o
         LEFT JOIN order_items oi ON oi.order_id = o.id
         LEFT JOIN products p ON p.id = oi.product_id
         WHERE o.status = 'closed'
           AND o.updated_at >= ? AND o.updated_at < ?`,
      ).get(bucket.start.toISOString(), bucket.end.toISOString()) as { value: number }).value),
    }));
    const topProduct = db().prepare(
      `SELECT p.name, p.value, SUM(oi.quantity) AS quantity
       FROM orders o JOIN order_items oi ON oi.order_id = o.id
       JOIN products p ON p.id = oi.product_id
       WHERE o.status = 'closed'
         AND o.updated_at >= ? AND o.updated_at < ?
       GROUP BY p.id ORDER BY quantity DESC, p.name LIMIT 1`,
    ).get(todayStart.toISOString(), tomorrow.toISOString());
    const categories = db().prepare(
      `SELECT c.name, SUM(p.value * oi.quantity) AS value
       FROM orders o JOIN order_items oi ON oi.order_id = o.id
       JOIN products p ON p.id = oi.product_id
       JOIN menu_categories c ON c.id = p.category_id
       WHERE o.status = 'closed'
         AND o.updated_at >= ? AND o.updated_at < ?
       GROUP BY c.id ORDER BY value DESC LIMIT 4`,
    ).all(todayStart.toISOString(), tomorrow.toISOString());
    return c.json({
      salesToday: Number(summary.sales),
      ordersToday: Number(summary.orders),
      averageTicket: summary.orders === 0 ? 0 : Math.round(summary.sales / summary.orders),
      points,
      topProduct,
      categories,
    });
  });

  routes.post('/rooms', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ error: 'INVALID_JSON' }, 400); }
    const name = typeof body === 'object' && body !== null && !Array.isArray(body) &&
      typeof (body as Record<string, unknown>).name === 'string'
      ? ((body as Record<string, unknown>).name as string).trim() : '';
    if (name.length < 2 || name.length > 80) {
      return c.json({ error: 'INVALID_ROOM_NAME' }, 422);
    }
    try {
      const result = db().prepare('INSERT INTO hall (name) VALUES (?)').run(name);
      return c.json({ room: { id: Number(result.lastInsertRowid), name,
        tableCount: 0, orderCount: 0, totalSales: 0, averageSale: 0 } }, 201);
    } catch (error) {
      if (String(error).includes('UNIQUE constraint failed')) {
        return c.json({ error: 'ROOM_NAME_TAKEN' }, 409);
      }
      throw error;
    }
  });

  routes.get('/rooms/:roomId/layout', (c) => {
    const roomId = readRoomId(c.req.param('roomId'));
    if (!roomId || !roomExists(db(), roomId)) return c.json({ error: 'ROOM_NOT_FOUND' }, 404);
    return c.json(readLayout(db(), roomId));
  });

  routes.put('/rooms/:roomId/layout', async (c) => {
    const roomId = readRoomId(c.req.param('roomId'));
    if (!roomId || !roomExists(db(), roomId)) return c.json({ error: 'ROOM_NOT_FOUND' }, 404);
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ error: 'INVALID_JSON' }, 400); }
    const validated = validateLayout(body);
    if (!validated.valid) {
      return c.json({ error: 'INVALID_LAYOUT', message: validated.message }, 422);
    }

    const database = db();
    try {
      database.exec('BEGIN IMMEDIATE');
      persistLayout(database, roomId, validated.layout);
      database.exec('COMMIT');
      roomRealtimeHub.publishRoomLayoutChanged(roomId);
      return c.json(readLayout(database, roomId));
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* No había transacción activa. */ }
      const message = error instanceof Error ? error.message : String(error);
      if (message.startsWith('INVALID_LAYOUT:')) {
        return c.json({ error: 'INVALID_LAYOUT', message: message.slice(15) }, 422);
      }
      console.error('No se pudo guardar el layout:', error);
      return c.json({ error: 'LAYOUT_SAVE_FAILED' }, 500);
    }
  });
  return routes;
}

function readRoomId(value: string) {
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : undefined;
}

function roomExists(database: DatabaseSync, roomId: number) {
  return database.prepare('SELECT 1 FROM hall WHERE id = ? LIMIT 1').get(roomId) !== undefined;
}

function validateGeometry(value: Record<string, unknown>, minimumSize: number) {
  return finite(value.x) && finite(value.y) && finite(value.width) && finite(value.height) &&
    Math.abs(value.x) <= 10_000 && Math.abs(value.y) <= 10_000 &&
    value.width >= minimumSize && value.width <= 5_000 &&
    value.height >= minimumSize && value.height <= 5_000;
}

function validateLayout(value: unknown):
  { valid: true; layout: LayoutPayload } | { valid: false; message: string } {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return { valid: false, message: 'El payload debe ser un objeto.' };
  }
  const data = value as Record<string, unknown>;
  if (!Array.isArray(data.tables) || !Array.isArray(data.walls) || !Array.isArray(data.groups)) {
    return { valid: false, message: 'tables, walls y groups deben ser listas.' };
  }
  const ids = new Set<number>();
  const identifiers = new Set<string>();
  const tables: LayoutTable[] = [];
  for (const raw of data.tables) {
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw))
      return { valid: false, message: 'Mesa inválida.' };
    const table = raw as Record<string, unknown>;
    const identifier = typeof table.identifier === 'string' ? table.identifier.trim() : '';
    const rotation = table.rotation ?? 0;
    if (!Number.isSafeInteger(table.id) || table.id === 0 || ids.has(table.id as number) ||
        identifier.length < 1 || identifier.length > 50 || identifiers.has(identifier) ||
        !validateGeometry(table, 32) || !finite(rotation)) {
      return { valid: false, message: 'Geometría o identificador de mesa inválido.' };
    }
    ids.add(table.id as number); identifiers.add(identifier);
    tables.push({ id: table.id as number, identifier, x: table.x as number,
      y: table.y as number, width: table.width as number, height: table.height as number,
      rotation });
  }
  for (let index = 0; index < tables.length; index++) {
    for (let other = index + 1; other < tables.length; other++) {
      if (intersects(tables[index], tables[other])) {
        return { valid: false, message: 'Las mesas no pueden superponerse.' };
      }
    }
  }
  const walls: LayoutWall[] = [];
  for (const raw of data.walls) {
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw))
      return { valid: false, message: 'Pared inválida.' };
    const wall = raw as Record<string, unknown>;
    if (!validateGeometry(wall, 2) || !finite(wall.rotation))
      return { valid: false, message: 'Geometría de pared inválida.' };
    walls.push({ id: Number.isSafeInteger(wall.id) ? wall.id as number : undefined,
      x: wall.x as number, y: wall.y as number, width: wall.width as number,
      height: wall.height as number, rotation: wall.rotation as number });
  }
  const memberIds = new Set<number>();
  const groups: LayoutGroup[] = [];
  for (const raw of data.groups) {
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw))
      return { valid: false, message: 'Agrupación inválida.' };
    const group = raw as Record<string, unknown>;
    if (!Array.isArray(group.tableIds) || group.tableIds.length < 2 ||
        group.tableIds.some((id) => !Number.isSafeInteger(id) || !ids.has(id as number) || memberIds.has(id as number))) {
      return { valid: false, message: 'Miembros de agrupación inválidos.' };
    }
    for (const id of group.tableIds) memberIds.add(id as number);
    groups.push({ id: Number.isSafeInteger(group.id) ? group.id as number : undefined,
      identifier: typeof group.identifier === 'string' ? group.identifier.trim().slice(0, 50) : undefined,
      tableIds: group.tableIds as number[] });
  }
  return { valid: true, layout: { tables, walls, groups } };
}

function intersects(a: Geometry, b: Geometry) {
  const bounds = (item: Geometry) => {
    const cosine = Math.abs(Math.cos(item.rotation));
    const sine = Math.abs(Math.sin(item.rotation));
    const width = item.width * cosine + item.height * sine;
    const height = item.width * sine + item.height * cosine;
    const centerX = item.x + item.width / 2;
    const centerY = item.y + item.height / 2;
    return { x: centerX - width / 2, y: centerY - height / 2, width, height };
  };
  const first = bounds(a);
  const second = bounds(b);
  const tolerance = .05;
  return first.x < second.x + second.width - tolerance &&
    first.x + first.width > second.x + tolerance &&
    first.y < second.y + second.height - tolerance &&
    first.y + first.height > second.y + tolerance;
}

function persistLayout(database: DatabaseSync, roomId: number, layout: LayoutPayload) {
  const existingIds = new Set((database.prepare(
    'SELECT id FROM hall_tables WHERE hall_id = ?',
  ).all(roomId) as Array<{ id: number }>).map(({ id }) => id));
  for (const table of layout.tables) {
    if (table.id > 0 && !existingIds.has(table.id)) {
      throw new Error(`INVALID_LAYOUT:La mesa ${table.id} no pertenece al salón.`);
    }
  }
  database.prepare('DELETE FROM hall_walls WHERE hall_id = ?').run(roomId);

  const retained = new Set(layout.tables.filter(({ id }) => id > 0).map(({ id }) => id));
  for (const id of existingIds) {
    if (!retained.has(id)) database.prepare('DELETE FROM hall_tables WHERE id = ?').run(id);
  }
  const idMap = new Map<number, number>();
  for (const table of layout.tables) {
    if (table.id > 0) {
      database.prepare(
        `UPDATE hall_tables SET identifier = ?, x = ?, y = ?, width = ?, height = ?, rotation = ?
         WHERE id = ? AND hall_id = ?`,
      ).run(table.identifier, table.x, table.y, table.width, table.height,
        table.rotation, table.id, roomId);
      idMap.set(table.id, table.id);
    } else {
      const result = database.prepare(
        `INSERT INTO hall_tables (identifier, x, y, width, height, rotation, status, hall_id)
         VALUES (?, ?, ?, ?, ?, ?, 'available', ?)`,
      ).run(table.identifier, table.x, table.y, table.width, table.height,
        table.rotation, roomId);
      idMap.set(table.id, Number(result.lastInsertRowid));
    }
  }
  const insertWall = database.prepare(
    'INSERT INTO hall_walls (hall_id, x, y, width, height, rotation) VALUES (?, ?, ?, ?, ?, ?)',
  );
  for (const wall of layout.walls) {
    insertWall.run(roomId, wall.x, wall.y, wall.width, wall.height, wall.rotation);
  }
  const logicalGroups = [];
  for (const group of layout.groups) {
    const tableIds = group.tableIds.map((id) => idMap.get(id)!);
    const members = group.tableIds.map((id) => layout.tables.find((table) => table.id === id)!);
    const numeric = members.filter(({ identifier }) => /^\d+$/.test(identifier));
    const identifier = numeric.length > 0
      ? numeric.reduce((a, b) => Number(a.identifier) <= Number(b.identifier) ? a : b).identifier
      : group.identifier || members[0].identifier;
    logicalGroups.push({
      id: group.id,
      identifier,
      tableIds,
    });
  }
  persistLogicalGroups(database, roomId, logicalGroups);
}

function readLayout(database: DatabaseSync, roomId: number) {
  const room = database.prepare('SELECT id, name FROM hall WHERE id = ?').get(roomId);
  const tables = database.prepare(
    `SELECT id, identifier, x, y, width, height, rotation, status
     FROM hall_tables WHERE hall_id = ? ORDER BY id`,
  ).all(roomId);
  const walls = database.prepare(
    'SELECT id, x, y, width, height, rotation FROM hall_walls WHERE hall_id = ? ORDER BY id',
  ).all(roomId);
  const groups = database.prepare(
    `SELECT g.id, g.visible_identifier AS identifier,
            json_group_array(m.table_id) AS table_ids
     FROM table_groups g JOIN table_group_members m ON m.group_id = g.id
     WHERE g.hall_id = ? GROUP BY g.id ORDER BY g.id`,
  ).all(roomId) as Array<{ id: number; identifier: string; table_ids: string }>;
  return { room, tables, walls, groups: groups.map((group) => ({
    id: group.id, identifier: group.identifier,
    tableIds: JSON.parse(group.table_ids) as number[],
  })) };
}

export default createAdminLayoutRoutes();

function revenueBuckets(
  period: 'hour' | 'day' | 'month' | 'year',
  range: number,
  now: Date,
) {
  const buckets: Array<{ start: Date; end: Date; label: string }> = [];
  if (period === 'hour') {
    for (let hour = 0; hour < 24; hour++) {
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), hour);
      const end = new Date(start); end.setHours(end.getHours() + 1);
      buckets.push({ start, end, label: `${hour.toString().padStart(2, '0')}:00` });
    }
  } else if (period === 'day') {
    for (let offset = range - 1; offset >= 0; offset--) {
      const start = new Date(now.getFullYear(), now.getMonth(), now.getDate() - offset);
      const end = new Date(start); end.setDate(end.getDate() + 1);
      buckets.push({ start, end, label: `${start.getDate()}/${start.getMonth() + 1}` });
    }
  } else if (period === 'month') {
    for (let offset = range - 1; offset >= 0; offset--) {
      const start = new Date(now.getFullYear(), now.getMonth() - offset, 1);
      const end = new Date(start); end.setMonth(end.getMonth() + 1);
      buckets.push({ start, end, label: `${start.getMonth() + 1}/${start.getFullYear()}` });
    }
  } else {
    for (let offset = range - 1; offset >= 0; offset--) {
      const start = new Date(now.getFullYear() - offset, 0, 1);
      const end = new Date(start); end.setFullYear(end.getFullYear() + 1);
      buckets.push({ start, end, label: `${start.getFullYear()}` });
    }
  }
  return buckets;
}
