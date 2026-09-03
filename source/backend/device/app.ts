import { upgradeWebSocket, type HttpBindings } from '@hono/node-server';
import { createHash, randomBytes, timingSafeEqual, X509Certificate } from 'node:crypto';
import { TLSSocket } from 'node:tls';
import { DatabaseSync } from 'node:sqlite';
import { Context, Hono } from 'hono';
import { verifyPassword } from '../shared/password';
import { openApplicationDatabase } from '../shared/schemaMigration';
import { roomRealtimeHub } from '../shared/roomRealtime';
import {
  persistLogicalGroups,
  updateLogicalTargetStatus,
} from '../shared/logicalTables';
import {
  activityHub,
  recordActivity,
  type ActivityEvent,
} from '../shared/activityLog';

const EMPLOYEE_SESSION_DURATION_MS = 12 * 60 * 60 * 1000;
const hash = (value: string) =>
  createHash('sha256').update(value, 'utf8').digest('hex');

type PresentedClientIdentity = {
  fingerprint: string;
  serialNumber: string;
  certificatePem: string;
};

type Options = {
  database?: DatabaseSync;
  resolveClientIdentity?: (
    context: Context<{ Bindings: HttpBindings }>,
  ) => PresentedClientIdentity | undefined;
};

type EmployeeSession = {
  userId: number;
  fullName: string;
  username: string;
  role: string;
  deviceId: number;
  expiresAt: string;
};

type StoredTable = {
  id: number;
  identifier: string;
  x: number;
  y: number;
  width: number;
  height: number;
  rotation: number;
};

type OrderItemPayload = {
  productId: number;
  quantity: number;
  specifications: string | null;
  removedIngredientIds: number[];
  parentIndex: number | null;
};

function peerClientIdentity(
  c: Context<{ Bindings: HttpBindings }>,
): PresentedClientIdentity | undefined {
  const socket = c.env.incoming.socket;
  if (!(socket instanceof TLSSocket)) return undefined;
  const peer = socket.getPeerCertificate(true);
  if (!peer.raw?.length) return undefined;
  const certificate = new X509Certificate(peer.raw);
  return {
    fingerprint: certificate.fingerprint256,
    serialNumber: certificate.serialNumber,
    certificatePem: certificate.toString(),
  };
}

export function createDeviceApp(options: Options = {}) {
  const app = new Hono<{ Bindings: HttpBindings }>();
  let database = options.database;
  const db = () => database ??= openApplicationDatabase();
  const identityFor = options.resolveClientIdentity ?? peerClientIdentity;

  const pairedDevice = (c: Context<{ Bindings: HttpBindings }>) => {
    const identity = identityFor(c);
    if (!identity) return undefined;
    const device = db().prepare(
      `SELECT id, name FROM paired_devices
       WHERE certificate_fingerprint = ? AND revoked_at IS NULL LIMIT 1`,
    ).get(identity.fingerprint) as { id: number; name: string } | undefined;
    return device ? { identity, device } : undefined;
  };

  const employeeSession = (
    c: Context<{ Bindings: HttpBindings }>,
  ): EmployeeSession | undefined => {
    const paired = pairedDevice(c);
    if (!paired) return undefined;
    const token = c.req.header('authorization')
      ?.match(/^Bearer ([A-Za-z0-9_-]+)$/)?.[1];
    if (!token) return undefined;
    return db().prepare(
      `SELECT u.id AS userId, u.name AS fullName, u.username, u.role,
              s.device_id AS deviceId, s.expires_at AS expiresAt
       FROM employee_sessions s
       JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = ? AND s.device_id = ? AND s.expires_at > ?
         AND u.role != 'admin'
       LIMIT 1`,
    ).get(hash(token), paired.device.id, new Date().toISOString()) as
      EmployeeSession | undefined;
  };

  app.get('/', (c) => c.text('Servidor funcionando'));

  app.get('/pairing', (c) => {
    return c.json({ service: 'restaurant-device-pairing', tls: true });
  });

  app.use('/realtime', async (c, next) => {
    if (!employeeSession(c)) {
      return c.json({ error: 'INVALID_SESSION' }, 401);
    }
    await next();
  });

  app.get('/realtime', upgradeWebSocket((c) => {
    const session = employeeSession(c)!;
    return {
      onOpen: (_event, socket) => {
        roomRealtimeHub.connect(socket, session.userId);
      },
      onMessage: (event, socket) => {
        if (typeof event.data !== 'string') return;
        let value: unknown;
        try { value = JSON.parse(event.data); } catch { return; }
        if (typeof value !== 'object' || value === null || Array.isArray(value)) return;
        const message = value as Record<string, unknown>;
        const roomId = message.roomId;
        if (!Number.isSafeInteger(roomId) || (roomId as number) < 1) return;
        if (message.type === 'unsubscribe') {
          roomRealtimeHub.unsubscribe(socket, roomId as number);
          return;
        }
        if (message.type !== 'subscribe') return;
        if (!employeeHasRoom(db(), session.userId, roomId as number)) {
          socket.send(JSON.stringify({ type: 'subscription-denied', roomId }));
          return;
        }
        roomRealtimeHub.subscribe(socket, roomId as number);
      },
      onClose: (_event, socket) => roomRealtimeHub.disconnect(socket),
      onError: (_event, socket) => roomRealtimeHub.disconnect(socket),
    };
  }));

  app.get('/device/connection', (c) => {
    const paired = pairedDevice(c);
    if (!identityFor(c)) {
      return c.json({ error: 'CLIENT_CERTIFICATE_REQUIRED' }, 401);
    }
    if (!paired) return c.json({ error: 'DEVICE_NOT_PAIRED' }, 403);
    return c.json({ connected: true, device: paired.device });
  });

  app.post('/auth/login', async (c) => {
    const presentedIdentity = identityFor(c);
    if (!presentedIdentity) {
      return c.json({ error: 'CLIENT_CERTIFICATE_REQUIRED' }, 401);
    }
    const paired = pairedDevice(c);
    if (!paired) return c.json({ error: 'DEVICE_NOT_PAIRED' }, 403);

    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ error: 'INVALID_JSON' }, 400); }
    if (typeof body !== 'object' || body === null || Array.isArray(body)) {
      return c.json({ error: 'INVALID_CREDENTIALS' }, 401);
    }
    const data = body as Record<string, unknown>;
    const username = typeof data.username === 'string'
      ? data.username.trim().toLowerCase() : '';
    const password = typeof data.password === 'string' ? data.password : '';
    const user = db().prepare(
      `SELECT id, name, username, role, password_hash FROM users
       WHERE username = ? AND role != 'admin' LIMIT 1`,
    ).get(username) as {
      id: number;
      name: string;
      username: string;
      role: string;
      password_hash: string;
    } | undefined;
    if (!user || !(await verifyPassword(password, user.password_hash))) {
      return c.json({
        error: 'INVALID_CREDENTIALS',
        message: 'Usuario o contraseña incorrectos.',
      }, 401);
    }

    const token = randomBytes(32).toString('base64url');
    const now = new Date();
    const expiresAt = new Date(now.getTime() + EMPLOYEE_SESSION_DURATION_MS);
    db().prepare('DELETE FROM employee_sessions WHERE expires_at <= ?')
      .run(now.toISOString());
    db().prepare(
      'DELETE FROM employee_sessions WHERE user_id = ? AND device_id = ?',
    ).run(user.id, paired.device.id);
    db().prepare(
      `INSERT INTO employee_sessions
       (user_id, device_id, token_hash, created_at, expires_at)
       VALUES (?, ?, ?, ?, ?)`,
    ).run(user.id, paired.device.id, hash(token), now.toISOString(),
      expiresAt.toISOString());
    return c.json({
      token,
      expiresAt: expiresAt.toISOString(),
      user: {
        id: user.id,
        fullName: user.name,
        username: user.username,
        role: user.role,
      },
    });
  });

  app.get('/auth/session', (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    return c.json({
      expiresAt: session.expiresAt,
      user: {
        id: session.userId,
        fullName: session.fullName,
        username: session.username,
        role: session.role,
      },
    });
  });

  app.post('/auth/logout', (c) => {
    const paired = pairedDevice(c);
    if (!identityFor(c)) {
      return c.json({ error: 'CLIENT_CERTIFICATE_REQUIRED' }, 401);
    }
    if (!paired) return c.json({ error: 'DEVICE_NOT_PAIRED' }, 403);
    const token = c.req.header('authorization')
      ?.match(/^Bearer ([A-Za-z0-9_-]+)$/)?.[1];
    if (token) {
      db().prepare(
        'DELETE FROM employee_sessions WHERE token_hash = ? AND device_id = ?',
      ).run(hash(token), paired.device.id);
    }
    return c.body(null, 204);
  });

  app.get('/rooms', (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const rooms = db().prepare(
      `SELECT h.id, h.name, COUNT(ht.id) AS tableCount
       FROM employee_halls eh
       JOIN hall h ON h.id = eh.hall_id
       LEFT JOIN hall_tables ht ON ht.hall_id = h.id
       WHERE eh.user_id = ?
       GROUP BY h.id
       ORDER BY h.name COLLATE NOCASE`,
    ).all(session.userId);
    return c.json({ rooms });
  });

  app.get('/rooms/:roomId/layout', (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    if (!roomId || !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'ROOM_NOT_ASSIGNED' }, 403);
    }
    return c.json(readLayout(db(), roomId));
  });

  app.get('/rooms/:roomId/menus', (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    if (!roomId || !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'ROOM_NOT_ASSIGNED' }, 403);
    }
    return c.json({ menus: readRoomMenus(db(), roomId) });
  });

  app.get('/rooms/:roomId/orders', (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    if (!roomId || !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'ROOM_NOT_ASSIGNED' }, 403);
    }
    return c.json({ orders: readRoomOrders(db(), roomId) });
  });

  app.get('/rooms/:roomId/orders/today', (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    if (!roomId || !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'ROOM_NOT_ASSIGNED' }, 403);
    }
    const ids = db().prepare(
      `SELECT o.id FROM orders o
       LEFT JOIN hall_tables t ON t.id = o.table_id
       WHERE COALESCE(o.hall_id, t.hall_id) = ?
         AND datetime(o.created_at, 'localtime') >=
             datetime(date('now', 'localtime'), '+1 hour')
         AND datetime(o.created_at, 'localtime') <
             datetime(date('now', 'localtime'), '+1 day')
       ORDER BY o.created_at DESC`,
    ).all(roomId) as Array<{ id: number }>;
    const orders = ids.map(({ id }) => readOrder(db(), id));
    return c.json({
      orders,
      total: orders.reduce((sum, order) => sum + Number(order.total), 0),
    });
  });

  app.post('/rooms/:roomId/tables/:tableId/orders', async (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    const tableId = readRoomId(c.req.param('tableId'));
    if (!roomId || !tableId || !employeeHasRoom(db(), session.userId, roomId) ||
        !tableBelongsToRoom(db(), tableId, roomId)) {
      return c.json({ error: 'ROOM_OR_TABLE_NOT_ASSIGNED' }, 403);
    }
    const tableGroupId = groupForTable(db(), tableId);
    const existing = db().prepare(
      `SELECT 1 FROM orders
       WHERE status != 'closed' AND
         (table_id = ? OR (? IS NOT NULL AND table_group_id = ?)) LIMIT 1`,
    ).get(tableId, tableGroupId, tableGroupId);
    if (existing) return c.json({ error: 'ACTIVE_ORDER_EXISTS' }, 409);
    const payload = await readOrderPayload(c, db(), roomId);
    if (payload instanceof Response) return payload;
    const now = new Date().toISOString();
    const database = db();
    let activity: ActivityEvent | undefined;
    try {
      database.exec('BEGIN IMMEDIATE');
      const result = database.prepare(
        `INSERT INTO orders
         (author_id, table_id, table_group_id, description, receiver,
          status, created_at, updated_at)
         VALUES (?, ?, ?, ?, NULL, 'waiting', ?, ?)`,
      ).run(session.userId, tableId, tableGroupId, payload.description, now, now);
      const orderId = Number(result.lastInsertRowid);
      replaceOrderItems(database, orderId, payload.items);
      recordOrderModification(database, orderId, null, session.userId,
        'create', null, JSON.stringify(payload), now);
      updateLogicalTargetStatus(database, tableId, tableGroupId, 'waiting');
      activity = recordActivity(database, {
        authorId: session.userId,
        author: session.fullName,
        roomId,
        type: 'Pedido',
        modification: tableGroupId === null
          ? `Creó un pedido en la mesa ${logicalTableLabel(database, tableId, null)}`
          : `Creó un pedido en la mesa ${logicalTableLabel(database, tableId, tableGroupId)}`,
      });
      database.exec('COMMIT');
      roomRealtimeHub.publishRoomOrdersChanged(roomId);
      activityHub.publish(activity);
      return c.json({ order: readOrder(database, orderId) }, 201);
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      throw error;
    }
  });

  app.post('/rooms/:roomId/external-orders', async (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    if (!roomId || !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'ROOM_NOT_ASSIGNED' }, 403);
    }
    let raw: unknown;
    try { raw = await c.req.json(); } catch {
      return c.json({ error: 'INVALID_JSON' }, 400);
    }
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      return c.json({ error: 'INVALID_ORDER' }, 422);
    }
    const externalName = typeof (raw as Record<string, unknown>).externalName === 'string'
      ? ((raw as Record<string, unknown>).externalName as string).trim().slice(0, 80)
      : '';
    if (!externalName) return c.json({ error: 'EXTERNAL_NAME_REQUIRED' }, 422);
    const payload = await readOrderPayload(c, db(), roomId);
    if (payload instanceof Response) return payload;
    const now = new Date().toISOString();
    const database = db();
    let activity: ActivityEvent | undefined;
    try {
      database.exec('BEGIN IMMEDIATE');
      const result = database.prepare(
        `INSERT INTO orders
         (author_id, table_id, table_group_id, hall_id, external_name,
          description, receiver, status, created_at, updated_at)
         VALUES (?, NULL, NULL, ?, ?, ?, NULL, 'waiting', ?, ?)`,
      ).run(session.userId, roomId, externalName, payload.description, now, now);
      const orderId = Number(result.lastInsertRowid);
      replaceOrderItems(database, orderId, payload.items);
      recordOrderModification(database, orderId, null, session.userId,
        'create', null, JSON.stringify(payload), now);
      activity = recordActivity(database, {
        authorId: session.userId,
        author: session.fullName,
        roomId,
        type: 'Pedido',
        modification: `Creó el pedido externo ${externalName}`,
      });
      database.exec('COMMIT');
      roomRealtimeHub.publishRoomOrdersChanged(roomId);
      activityHub.publish(activity);
      return c.json({ order: readOrder(database, orderId) }, 201);
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      throw error;
    }
  });

  app.put('/rooms/:roomId/orders/:orderId', async (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    const orderId = readRoomId(c.req.param('orderId'));
    if (!roomId || !orderId || !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'ORDER_NOT_FOUND' }, 404);
    }
    const order = db().prepare(
      `SELECT o.id, o.table_id AS tableId, o.table_group_id AS tableGroupId,
              o.external_name AS externalName, o.status
       FROM orders o
       LEFT JOIN hall_tables t ON t.id = o.table_id
       WHERE o.id = ? AND COALESCE(o.hall_id, t.hall_id) = ?
         AND o.status != 'closed'`,
    ).get(orderId, roomId) as {
      id: number; tableId: number | null; tableGroupId: number | null;
      externalName: string | null; status: string;
    } | undefined;
    if (!order) {
      return c.json({ error: 'ORDER_NOT_FOUND' }, 404);
    }
    const payload = await readOrderPayload(c, db(), roomId, true);
    if (payload instanceof Response) return payload;
    const database = db();
    if (!updateKeepsDeliveredItems(database, orderId, payload.items)) {
      return c.json({ error: 'DELIVERED_ITEM_CANNOT_BE_REMOVED' }, 409);
    }
    const oldValue = JSON.stringify(readOrder(database, orderId));
    const now = new Date().toISOString();
    let activity: ActivityEvent | undefined;
    try {
      database.exec('BEGIN IMMEDIATE');
      if (payload.items.length === 0) {
        database.prepare('DELETE FROM order_modifications WHERE order_id = ?')
          .run(orderId);
        database.prepare('DELETE FROM order_items WHERE order_id = ?').run(orderId);
        database.prepare('DELETE FROM removed_order_items WHERE order_id = ?')
          .run(orderId);
        database.prepare('DELETE FROM orders WHERE id = ?').run(orderId);
        if (order.tableId !== null) {
          updateLogicalTargetStatus(
            database, order.tableId, order.tableGroupId, 'available',
          );
        }
        activity = recordActivity(database, {
          authorId: session.userId,
          author: session.fullName,
          roomId,
          type: 'Pedido',
          modification: `Eliminó el pedido pendiente de ${logicalTableLabel(database, order.tableId, order.tableGroupId, order.externalName)}`,
        });
        database.exec('COMMIT');
        roomRealtimeHub.publishRoomOrdersChanged(roomId);
        activityHub.publish(activity);
        return c.json({ deleted: true });
      }
      database.prepare('UPDATE orders SET description = ?, updated_at = ? WHERE id = ?')
        .run(payload.description, now, orderId);
      replaceOrderItems(database, orderId, payload.items);
      const nextStatus = orderHasPendingItems(database, orderId)
        ? 'waiting' : 'eating';
      database.prepare('UPDATE orders SET status = ? WHERE id = ?')
        .run(nextStatus, orderId);
      if (order.tableId !== null) {
        updateLogicalTargetStatus(
          database, order.tableId, order.tableGroupId, nextStatus,
        );
      }
      recordOrderModification(database, orderId, null, session.userId,
        'update', oldValue, JSON.stringify(payload), now);
      activity = recordActivity(database, {
        authorId: session.userId,
        author: session.fullName,
        roomId,
        type: 'Pedido',
        modification: `Modificó el pedido de ${logicalTableLabel(database, order.tableId, order.tableGroupId, order.externalName)}`,
      });
      database.exec('COMMIT');
      roomRealtimeHub.publishRoomOrdersChanged(roomId);
      activityHub.publish(activity);
      return c.json({ order: readOrder(database, orderId) });
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      throw error;
    }
  });

  app.patch('/rooms/:roomId/orders/:orderId/transfer', async (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    const orderId = readRoomId(c.req.param('orderId'));
    let body: unknown;
    try { body = await c.req.json(); } catch {
      return c.json({ error: 'INVALID_JSON' }, 400);
    }
    const targetTableId = typeof body === 'object' && body !== null &&
      !Array.isArray(body) ? readRoomId(String(
        (body as Record<string, unknown>).tableId ?? '',
      )) : undefined;
    if (!roomId || !orderId || !targetTableId ||
        !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'INVALID_TRANSFER_TARGET' }, 422);
    }
    const order = db().prepare(
      `SELECT table_id AS tableId, table_group_id AS tableGroupId, status
       FROM orders WHERE id = ? AND status != 'closed'`,
    ).get(orderId) as {
      tableId: number; tableGroupId: number | null; status: string;
    } | undefined;
    if (!order || !tableBelongsToRoom(db(), order.tableId, roomId)) {
      return c.json({ error: 'ORDER_NOT_FOUND' }, 404);
    }
    const target = db().prepare(
      `SELECT status FROM hall_tables WHERE id = ? AND hall_id = ?`,
    ).get(targetTableId, roomId) as { status: string } | undefined;
    const targetGroupId = groupForTable(db(), targetTableId);
    if (!target || target.status !== 'available') {
      return c.json({ error: 'TABLE_NOT_AVAILABLE' }, 409);
    }
    const occupied = db().prepare(
      `SELECT 1 FROM orders WHERE status != 'closed' AND id != ?
       AND (table_id = ? OR (? IS NOT NULL AND table_group_id = ?)) LIMIT 1`,
    ).get(orderId, targetTableId, targetGroupId, targetGroupId);
    if (occupied) return c.json({ error: 'TABLE_NOT_AVAILABLE' }, 409);
    const database = db();
    const oldLabel = logicalTableLabel(
      database, order.tableId, order.tableGroupId,
    );
    const newLabel = logicalTableLabel(database, targetTableId, targetGroupId);
    const now = new Date().toISOString();
    let activity: ActivityEvent | undefined;
    try {
      database.exec('BEGIN IMMEDIATE');
      updateLogicalTargetStatus(
        database, order.tableId, order.tableGroupId, 'available',
      );
      database.prepare(
        `UPDATE orders SET table_id = ?, table_group_id = ?, updated_at = ?
         WHERE id = ?`,
      ).run(targetTableId, targetGroupId, now, orderId);
      updateLogicalTargetStatus(
        database, targetTableId, targetGroupId, order.status,
      );
      recordOrderModification(database, orderId, null, session.userId,
        'transfer', oldLabel, newLabel, now);
      activity = recordActivity(database, {
        authorId: session.userId,
        author: session.fullName,
        roomId,
        type: 'Mesa',
        modification: `Trasladó el pedido de ${oldLabel} a ${newLabel}`,
      });
      database.exec('COMMIT');
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      throw error;
    }
    roomRealtimeHub.publishRoomOrdersChanged(roomId);
    activityHub.publish(activity!);
    return c.json({ order: readOrder(database, orderId) });
  });

  app.patch('/rooms/:roomId/orders/:orderId/status', async (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    const orderId = readRoomId(c.req.param('orderId'));
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ error: 'INVALID_JSON' }, 400); }
    const status = typeof body === 'object' && body !== null &&
      !Array.isArray(body) ? (body as Record<string, unknown>).status : undefined;
    if (status !== 'eating' && status !== 'closed') {
      return c.json({ error: 'INVALID_ORDER_STATUS' }, 422);
    }
    if (!roomId || !orderId || !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'ORDER_NOT_FOUND' }, 404);
    }
    const order = db().prepare(
      `SELECT o.table_id AS tableId, o.table_group_id AS tableGroupId,
              o.external_name AS externalName, o.status FROM orders o
       LEFT JOIN hall_tables t ON t.id = o.table_id
       WHERE o.id = ? AND COALESCE(o.hall_id, t.hall_id) = ?
         AND o.status != 'closed'`,
    ).get(orderId, roomId) as {
      tableId: number | null; tableGroupId: number | null;
      externalName: string | null; status: string;
    } | undefined;
    if (!order) {
      return c.json({ error: 'ORDER_NOT_FOUND' }, 404);
    }
    if (status === 'eating' && order.status !== 'waiting') {
      return c.json({ error: 'INVALID_ORDER_STATUS' }, 409);
    }
    if (status === 'closed' && order.status !== 'eating') {
      return c.json({ error: 'ORDER_NOT_READY_TO_BILL' }, 409);
    }
    if (orderHasPendingItems(db(), orderId)) {
      return c.json({ error: 'ORDER_ITEMS_PENDING' }, 409);
    }
    const now = new Date().toISOString();
    let activity: ActivityEvent | undefined;
    db().exec('BEGIN IMMEDIATE');
    try {
      db().prepare('UPDATE orders SET status = ?, updated_at = ? WHERE id = ?')
        .run(status, now, orderId);
      const nextTableStatus = status === 'closed' ? 'available' : 'eating';
      if (order.tableId !== null) {
        updateLogicalTargetStatus(
          db(), order.tableId, order.tableGroupId, nextTableStatus,
        );
      }
      recordOrderModification(db(), orderId, null, session.userId, 'status',
        order.status, status, now);
      activity = recordActivity(db(), {
        authorId: session.userId,
        author: session.fullName,
        roomId,
        type: 'Mesa',
        modification: status === 'closed'
          ? `Facturó ${logicalTableLabel(db(), order.tableId, order.tableGroupId, order.externalName)}`
          : `Marcó ${logicalTableLabel(db(), order.tableId, order.tableGroupId, order.externalName)} como comiendo`,
      });
      db().exec('COMMIT');
    } catch (error) {
      try { db().exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      throw error;
    }
    roomRealtimeHub.publishRoomOrdersChanged(roomId);
    activityHub.publish(activity!);
    return c.json({ order: readOrder(db(), orderId) });
  });

  app.patch(
    '/rooms/:roomId/orders/:orderId/items/:itemId/units/:unitIndex/deliver',
    (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    const orderId = readRoomId(c.req.param('orderId'));
    const itemId = readRoomId(c.req.param('itemId'));
    const unitIndex = Number(c.req.param('unitIndex'));
    if (!roomId || !orderId || !itemId ||
        !Number.isSafeInteger(unitIndex) || unitIndex < 0 ||
        !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'ORDER_ITEM_NOT_FOUND' }, 404);
    }
    const item = db().prepare(
      `SELECT oi.delivered_quantity AS deliveredQuantity, oi.quantity,
              o.table_id AS tableId, o.table_group_id AS tableGroupId,
              o.external_name AS externalName
       FROM order_items oi
       JOIN orders o ON o.id = oi.order_id
       LEFT JOIN hall_tables t ON t.id = o.table_id
       WHERE oi.id = ? AND o.id = ?
         AND COALESCE(o.hall_id, t.hall_id) = ? AND o.status != 'closed'`,
    ).get(itemId, orderId, roomId) as {
      deliveredQuantity: number; quantity: number;
      tableId: number | null; tableGroupId: number | null;
      externalName: string | null;
    } | undefined;
    if (!item) return c.json({ error: 'ORDER_ITEM_NOT_FOUND' }, 404);
    if (unitIndex >= item.quantity) {
      return c.json({ error: 'ORDER_ITEM_UNIT_NOT_FOUND' }, 404);
    }
    const alreadyDelivered = db().prepare(
      `SELECT 1 FROM order_item_deliveries
       WHERE order_item_id = ? AND unit_index = ?`,
    ).get(itemId, unitIndex);
    if (alreadyDelivered) {
      return c.json({ error: 'ORDER_ITEM_ALREADY_DELIVERED' }, 409);
    }

    const database = db();
    const now = new Date().toISOString();
    let activity: ActivityEvent | undefined;
    try {
      database.exec('BEGIN IMMEDIATE');
      database.prepare(
        `INSERT INTO order_item_deliveries
         (order_item_id, unit_index, delivered_at, delivered_by)
         VALUES (?, ?, ?, ?)`,
      ).run(itemId, unitIndex, now, session.userId);
      const deliveredQuantity = Number((database.prepare(
        `SELECT COUNT(*) AS count FROM order_item_deliveries
         WHERE order_item_id = ?`,
      ).get(itemId) as { count: number }).count);
      database.prepare(
        `UPDATE order_items
         SET delivered_quantity = ?,
             status = CASE WHEN ? >= quantity THEN 'delivered' ELSE 'ordered' END
         WHERE id = ?`,
      ).run(deliveredQuantity, deliveredQuantity, itemId);
      const nextStatus = orderHasPendingItems(database, orderId)
        ? 'waiting' : 'eating';
      database.prepare(
        'UPDATE orders SET status = ?, updated_at = ? WHERE id = ?',
      ).run(nextStatus, now, orderId);
      if (item.tableId !== null) {
        updateLogicalTargetStatus(
          database, item.tableId, item.tableGroupId, nextStatus,
        );
      }
      recordOrderModification(
        database,
        orderId,
        itemId,
        session.userId,
        'deliver',
        String(item.deliveredQuantity),
        String(deliveredQuantity),
        now,
      );
      activity = recordActivity(database, {
        authorId: session.userId,
        author: session.fullName,
        roomId,
        type: 'Pedido',
        modification: nextStatus === 'eating'
          ? `Entregó el último producto de ${logicalTableLabel(database, item.tableId, item.tableGroupId, item.externalName)}`
          : `Entregó un producto de ${logicalTableLabel(database, item.tableId, item.tableGroupId, item.externalName)}`,
      });
      database.exec('COMMIT');
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      if (String(error).includes('UNIQUE constraint failed')) {
        return c.json({ error: 'ORDER_ITEM_ALREADY_DELIVERED' }, 409);
      }
      throw error;
    }
    roomRealtimeHub.publishRoomOrdersChanged(roomId);
    activityHub.publish(activity!);
    return c.json({ order: readOrder(database, orderId) });
  });

  app.patch(
    '/rooms/:roomId/orders/:orderId/items/:itemId/units/:unitIndex/undo-delivery',
    (c) => {
      const session = employeeSession(c);
      if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
      const roomId = readRoomId(c.req.param('roomId'));
      const orderId = readRoomId(c.req.param('orderId'));
      const itemId = readRoomId(c.req.param('itemId'));
      const unitIndex = Number(c.req.param('unitIndex'));
      if (!roomId || !orderId || !itemId ||
          !Number.isSafeInteger(unitIndex) || unitIndex < 0 ||
          !employeeHasRoom(db(), session.userId, roomId)) {
        return c.json({ error: 'ORDER_ITEM_NOT_FOUND' }, 404);
      }
      const item = db().prepare(
        `SELECT oi.quantity, oi.delivered_quantity AS deliveredQuantity,
                o.table_id AS tableId, o.table_group_id AS tableGroupId,
                o.external_name AS externalName
         FROM order_items oi
         JOIN orders o ON o.id = oi.order_id
         LEFT JOIN hall_tables t ON t.id = o.table_id
         WHERE oi.id = ? AND o.id = ?
           AND COALESCE(o.hall_id, t.hall_id) = ? AND o.status != 'closed'`,
      ).get(itemId, orderId, roomId) as {
        quantity: number; deliveredQuantity: number;
        tableId: number | null; tableGroupId: number | null;
        externalName: string | null;
      } | undefined;
      if (!item || unitIndex >= item.quantity) {
        return c.json({ error: 'ORDER_ITEM_NOT_FOUND' }, 404);
      }
      if (!db().prepare(
        `SELECT 1 FROM order_item_deliveries
         WHERE order_item_id = ? AND unit_index = ?`,
      ).get(itemId, unitIndex)) {
        return c.json({ error: 'ORDER_ITEM_NOT_DELIVERED' }, 409);
      }

      const database = db();
      const now = new Date().toISOString();
      let activity: ActivityEvent | undefined;
      try {
        database.exec('BEGIN IMMEDIATE');
        database.prepare(
          `DELETE FROM order_item_deliveries
           WHERE order_item_id = ? AND unit_index = ?`,
        ).run(itemId, unitIndex);
        const deliveredQuantity = Number((database.prepare(
          `SELECT COUNT(*) AS count FROM order_item_deliveries
           WHERE order_item_id = ?`,
        ).get(itemId) as { count: number }).count);
        database.prepare(
          `UPDATE order_items SET delivered_quantity = ?, status = 'ordered'
           WHERE id = ?`,
        ).run(deliveredQuantity, itemId);
        database.prepare(
          `UPDATE orders SET status = 'waiting', updated_at = ? WHERE id = ?`,
        ).run(now, orderId);
        if (item.tableId !== null) {
          updateLogicalTargetStatus(
            database, item.tableId, item.tableGroupId, 'waiting',
          );
        }
        recordOrderModification(
          database,
          orderId,
          itemId,
          session.userId,
          'undo_delivery',
          String(item.deliveredQuantity),
          String(deliveredQuantity),
          now,
        );
        activity = recordActivity(database, {
          authorId: session.userId,
          author: session.fullName,
          roomId,
          type: 'Pedido',
          modification: `Deshizo una entrega de ${logicalTableLabel(database, item.tableId, item.tableGroupId, item.externalName)}`,
        });
        database.exec('COMMIT');
      } catch (error) {
        try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
        throw error;
      }
      roomRealtimeHub.publishRoomOrdersChanged(roomId);
      activityHub.publish(activity!);
      return c.json({ order: readOrder(database, orderId) });
    },
  );

  app.put('/rooms/:roomId/live-layout', async (c) => {
    const session = employeeSession(c);
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);
    const roomId = readRoomId(c.req.param('roomId'));
    if (!roomId || !employeeHasRoom(db(), session.userId, roomId)) {
      return c.json({ error: 'ROOM_NOT_ASSIGNED' }, 403);
    }
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ error: 'INVALID_JSON' }, 400); }
    const validated = validateLiveLayout(db(), roomId, body);
    if (!validated.valid) {
      return c.json({ error: 'INVALID_LAYOUT', message: validated.message }, 422);
    }

    const database = db();
    const groupsBefore = logicalGroupSignature(database, roomId);
    let activity: ActivityEvent | undefined;
    try {
      database.exec('BEGIN IMMEDIATE');
      const update = database.prepare(
        'UPDATE hall_tables SET x = ?, y = ? WHERE id = ? AND hall_id = ?',
      );
      for (const table of validated.tables) {
        update.run(table.x, table.y, table.id, roomId);
      }
      persistLogicalGroups(database, roomId, validated.groups.map((group) => ({
        id: group.id,
        identifier: group.identifier,
        tableIds: group.tableIds,
      })), session.userId);
      const groupsAfter = logicalGroupSignature(database, roomId);
      if (groupsBefore !== groupsAfter) {
        activity = recordActivity(database, {
          authorId: session.userId,
          author: session.fullName,
          roomId,
          type: 'Mesas',
          modification: 'Actualizó las mesas enlazadas del salón',
        });
      }
      database.exec('COMMIT');
      roomRealtimeHub.publishRoomLayoutChanged(roomId);
      if (activity) activityHub.publish(activity);
      return c.json(readLayout(database, roomId));
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* No había transacción activa. */ }
      console.error('No se pudo guardar el live layout:', error);
      return c.json({ error: 'LAYOUT_SAVE_FAILED' }, 500);
    }
  });

  app.post('/pairing/complete', async (c) => {
    let body: unknown;
    try { body = await c.req.json(); } catch { return c.json({ error: 'INVALID_JSON' }, 400); }
    if (typeof body !== 'object' || body === null || Array.isArray(body)) {
      return c.json({ error: 'INVALID_PAIRING_REQUEST' }, 422);
    }
    const data = body as Record<string, unknown>;
    const pairingId = typeof data.pairingId === 'string' ? data.pairingId : '';
    const pairingSecret = typeof data.pairingSecret === 'string'
      ? data.pairingSecret : '';
    const deviceName = typeof data.deviceName === 'string'
      ? data.deviceName.trim().slice(0, 100) : '';
    const request = db().prepare(
      `SELECT secret_hash, expires_at, used_at FROM device_pairing_requests
       WHERE id = ? LIMIT 1`,
    ).get(pairingId) as {
      secret_hash: string;
      expires_at: string;
      used_at: string | null;
    } | undefined;
    const providedHash = hash(pairingSecret);
    const validSecret = request !== undefined &&
      timingSafeEqual(Buffer.from(request.secret_hash, 'hex'),
        Buffer.from(providedHash, 'hex'));
    if (!request || !validSecret || request.used_at !== null ||
        Date.parse(request.expires_at) <= Date.now()) {
      return c.json({ error: 'INVALID_OR_EXPIRED_PAIRING' }, 401);
    }

    const identity = identityFor(c);
    if (!identity) return c.json({ error: 'CLIENT_CERTIFICATE_REQUIRED' }, 401);
    const now = new Date().toISOString();
    try {
      db().exec('BEGIN IMMEDIATE');
      const consumed = db().prepare(
        `UPDATE device_pairing_requests SET used_at = ?
         WHERE id = ? AND used_at IS NULL AND expires_at > ?`,
      ).run(now, pairingId, now);
      if (consumed.changes !== 1) {
        throw new Error('PAIRING_ALREADY_USED');
      }
      db().prepare(
        `INSERT INTO paired_devices
         (name, certificate_fingerprint, certificate_serial, certificate_pem, paired_at)
         VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(certificate_fingerprint) DO UPDATE SET
           name = excluded.name, certificate_serial = excluded.certificate_serial,
           certificate_pem = excluded.certificate_pem, paired_at = excluded.paired_at,
           revoked_at = NULL`,
      ).run(deviceName || 'Restaurant client', identity.fingerprint,
        identity.serialNumber, identity.certificatePem, now);
      db().exec('COMMIT');
    } catch (error) {
      try { db().exec('ROLLBACK'); } catch { /* No había transacción activa. */ }
      if (String(error).includes('PAIRING_ALREADY_USED')) {
        return c.json({ error: 'INVALID_OR_EXPIRED_PAIRING' }, 401);
      }
      console.error('No se pudo completar el emparejamiento:', error);
      return c.json({ error: 'PAIRING_FAILED' }, 500);
    }
    return c.json({ paired: true, deviceFingerprint: identity.fingerprint });
  });

  return app;
}

function readRoomId(value: string) {
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : undefined;
}

function employeeHasRoom(database: DatabaseSync, userId: number, roomId: number) {
  return database.prepare(
    'SELECT 1 FROM employee_halls WHERE user_id = ? AND hall_id = ? LIMIT 1',
  ).get(userId, roomId) !== undefined;
}

function readLayout(database: DatabaseSync, roomId: number) {
  const room = database.prepare('SELECT id, name FROM hall WHERE id = ?').get(roomId);
  const tables = database.prepare(
    `SELECT id, identifier, x, y, width, height, rotation, status
     FROM hall_tables WHERE hall_id = ? ORDER BY id`,
  ).all(roomId);
  const walls = database.prepare(
    `SELECT id, x, y, width, height, rotation
     FROM hall_walls WHERE hall_id = ? ORDER BY id`,
  ).all(roomId);
  const groups = database.prepare(
    `SELECT g.id, g.visible_identifier AS identifier,
            json_group_array(m.table_id) AS table_ids
     FROM table_groups g JOIN table_group_members m ON m.group_id = g.id
     WHERE g.hall_id = ? GROUP BY g.id ORDER BY g.id`,
  ).all(roomId) as Array<{ id: number; identifier: string; table_ids: string }>;
  return {
    room,
    tables,
    walls,
    groups: groups.map((group) => ({
      id: group.id,
      identifier: group.identifier,
      tableIds: JSON.parse(group.table_ids) as number[],
    })),
  };
}

function tableBelongsToRoom(database: DatabaseSync, tableId: number, roomId: number) {
  return database.prepare(
    'SELECT 1 FROM hall_tables WHERE id = ? AND hall_id = ? LIMIT 1',
  ).get(tableId, roomId) !== undefined;
}

function groupForTable(database: DatabaseSync, tableId: number) {
  const row = database.prepare(
    'SELECT group_id AS groupId FROM table_group_members WHERE table_id = ?',
  ).get(tableId) as { groupId: number } | undefined;
  return row?.groupId ?? null;
}

function logicalGroupSignature(database: DatabaseSync, roomId: number) {
  return JSON.stringify(database.prepare(
    `SELECT g.id, group_concat(m.table_id, ',') AS members
     FROM table_groups g JOIN table_group_members m ON m.group_id = g.id
     WHERE g.hall_id = ? GROUP BY g.id ORDER BY g.id`,
  ).all(roomId));
}

async function readOrderPayload(
  c: any,
  database: DatabaseSync,
  roomId: number,
  allowEmpty = false,
):
  Promise<{ description: string | null; items: OrderItemPayload[] } | Response> {
  let body: unknown;
  try { body = await c.req.json(); } catch { return c.json({ error: 'INVALID_JSON' }, 400); }
  if (typeof body !== 'object' || body === null || Array.isArray(body)) {
    return c.json({ error: 'INVALID_ORDER' }, 422);
  }
  const data = body as Record<string, unknown>;
  if (!Array.isArray(data.items) || (!allowEmpty && data.items.length === 0)) {
    return c.json({ error: 'ORDER_ITEMS_REQUIRED' }, 422);
  }
  const description = typeof data.description === 'string'
    ? data.description.trim().slice(0, 1000) || null : null;
  const items: OrderItemPayload[] = [];
  for (let index = 0; index < data.items.length; index++) {
    const raw = data.items[index];
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      return c.json({ error: 'INVALID_ORDER_ITEM' }, 422);
    }
    const item = raw as Record<string, unknown>;
    const productId = Number(item.productId);
    const quantity = Number(item.quantity);
    const parentIndex = item.parentIndex == null ? null : Number(item.parentIndex);
    const removed = Array.isArray(item.removedIngredientIds)
      ? item.removedIngredientIds.map(Number) : [];
    if (!Number.isSafeInteger(productId) || productId < 1 ||
        !Number.isSafeInteger(quantity) || quantity < 1 || quantity > 99 ||
        (parentIndex !== null && (!Number.isSafeInteger(parentIndex) ||
          parentIndex < 0 || parentIndex >= index)) ||
        removed.some((id) => !Number.isSafeInteger(id) || id < 1) ||
        new Set(removed).size !== removed.length ||
        !productVisibleInRoom(database, productId, roomId) ||
        !removedIngredientsBelongToProduct(database, productId, removed)) {
      return c.json({ error: 'INVALID_ORDER_ITEM' }, 422);
    }
    const category = database.prepare(
      `SELECT c.is_special AS special FROM products p
       JOIN menu_categories c ON c.id = p.category_id WHERE p.id = ?`,
    ).get(productId) as { special: number } | undefined;
    if (parentIndex !== null) {
      const parentProductId = items[parentIndex]?.productId;
      const parentCategory = database.prepare(
        `SELECT c.is_special AS special FROM products p
         JOIN menu_categories c ON c.id = p.category_id WHERE p.id = ?`,
      ).get(parentProductId) as { special: number } | undefined;
      if (category?.special !== 1 || parentCategory?.special !== 0) {
        return c.json({ error: 'INVALID_SPECIAL_PRODUCT_PARENT' }, 422);
      }
    }
    items.push({ productId, quantity,
      specifications: typeof item.specifications === 'string'
        ? item.specifications.trim().slice(0, 1000) || null : null,
      removedIngredientIds: removed, parentIndex });
  }
  return { description, items };
}

function productVisibleInRoom(database: DatabaseSync, productId: number, roomId: number) {
  return database.prepare(
    `SELECT 1 FROM products p
     JOIN menu_halls mh ON mh.menu_id = p.menu_id AND mh.hall_id = ?
     WHERE p.id = ? AND p.is_active = 1 AND (mh.is_primary = 1 OR EXISTS (
       SELECT 1 FROM product_halls ph WHERE ph.product_id = p.id AND ph.hall_id = ?
     )) LIMIT 1`,
  ).get(roomId, productId, roomId) !== undefined;
}

function removedIngredientsBelongToProduct(database: DatabaseSync, productId: number,
  ingredientIds: number[]) {
  if (ingredientIds.length === 0) return true;
  const placeholders = ingredientIds.map(() => '?').join(',');
  const row = database.prepare(
    `SELECT COUNT(*) AS count FROM product_ingredients
     WHERE product_id = ? AND ingredient_id IN (${placeholders})`,
  ).get(productId, ...ingredientIds) as { count: number };
  return row.count === ingredientIds.length;
}

function updateKeepsDeliveredItems(
  database: DatabaseSync,
  orderId: number,
  items: OrderItemPayload[],
) {
  const requested = new Map<string, number>();
  for (const item of items) {
    const parentProductId = item.parentIndex === null
      ? null : items[item.parentIndex].productId;
    const signature = orderItemSignature(
      item.productId,
      item.specifications,
      item.removedIngredientIds,
      parentProductId,
    );
    requested.set(signature, (requested.get(signature) ?? 0) + item.quantity);
  }

  const delivered = new Map<string, number>();
  const stored = database.prepare(
    `SELECT oi.id, oi.product_id AS productId, oi.specifications,
            oi.delivered_quantity AS deliveredQuantity,
            parent.product_id AS parentProductId
     FROM order_items oi
     LEFT JOIN order_items parent ON parent.id = oi.parent_order_item_id
     WHERE oi.order_id = ? AND oi.delivered_quantity > 0`,
  ).all(orderId) as Array<{
    id: number; productId: number; specifications: string | null;
    deliveredQuantity: number; parentProductId: number | null;
  }>;
  for (const item of stored) {
    const removedIngredientIds = (database.prepare(
      `SELECT ingredient_id AS id FROM order_item_removed_ingredients
       WHERE order_item_id = ? ORDER BY ingredient_id`,
    ).all(item.id) as Array<{ id: number }>).map(({ id }) => id);
    const signature = orderItemSignature(
      item.productId,
      item.specifications,
      removedIngredientIds,
      item.parentProductId,
    );
    delivered.set(
      signature,
      (delivered.get(signature) ?? 0) + item.deliveredQuantity,
    );
  }
  return [...delivered.entries()].every(
    ([signature, quantity]) => (requested.get(signature) ?? 0) >= quantity,
  );
}

function replaceOrderItems(database: DatabaseSync, orderId: number, items: OrderItemPayload[]) {
  const deliveredBySignature = new Map<string, number>();
  const requestedBySignature = new Map<string, number>();
  for (const item of items) {
    const parentProductId = item.parentIndex === null
      ? null : items[item.parentIndex].productId;
    const signature = orderItemSignature(
      item.productId,
      item.specifications,
      item.removedIngredientIds,
      parentProductId,
    );
    requestedBySignature.set(
      signature,
      (requestedBySignature.get(signature) ?? 0) + item.quantity,
    );
  }
  const storedItems = database.prepare(
    `WITH RECURSIVE category_paths(id, path) AS (
       SELECT id, name FROM menu_categories WHERE parent_category_id IS NULL
       UNION ALL
       SELECT child.id, category_paths.path || ' › ' || child.name
       FROM menu_categories child
       JOIN category_paths ON child.parent_category_id = category_paths.id
     )
     SELECT oi.id, oi.product_id AS productId, oi.quantity,
            oi.delivered_quantity AS deliveredQuantity, oi.specifications,
            parent.product_id AS parentProductId, p.name,
            category_paths.path AS categoryName,
            p.description AS productDescription, p.value,
            parent_product.name AS parentProductName
     FROM order_items oi
     JOIN products p ON p.id = oi.product_id
     JOIN menu_categories category ON category.id = p.category_id
     JOIN category_paths ON category_paths.id = category.id
     LEFT JOIN order_items parent ON parent.id = oi.parent_order_item_id
     LEFT JOIN products parent_product ON parent_product.id = parent.product_id
     WHERE oi.order_id = ? ORDER BY oi.id`,
  ).all(orderId) as Array<{
    id: number; productId: number; quantity: number; deliveredQuantity: number;
    specifications: string | null; parentProductId: number | null;
    name: string; categoryName: string; productDescription: string | null;
    value: number;
    parentProductName: string | null;
  }>;
  const insertRemovedItem = database.prepare(
    `INSERT INTO removed_order_items
     (order_id, product_name, category_name, product_description, unit_value, quantity,
      specifications, parent_product_name, removed_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
  );
  for (const item of storedItems) {
    const removedIngredientIds = (database.prepare(
      `SELECT ingredient_id AS id FROM order_item_removed_ingredients
       WHERE order_item_id = ? ORDER BY ingredient_id`,
    ).all(item.id) as Array<{ id: number }>).map(({ id }) => id);
    const signature = orderItemSignature(
      item.productId,
      item.specifications,
      removedIngredientIds,
      item.parentProductId,
    );
    deliveredBySignature.set(
      signature,
      (deliveredBySignature.get(signature) ?? 0) + item.deliveredQuantity,
    );
    const requested = requestedBySignature.get(signature) ?? 0;
    const retained = Math.min(requested, item.quantity);
    requestedBySignature.set(signature, Math.max(0, requested - retained));
    const removedQuantity = item.quantity - retained;
    if (removedQuantity > 0) {
      insertRemovedItem.run(
        orderId,
        item.name,
        item.categoryName,
        item.productDescription,
        item.value,
        removedQuantity,
        item.specifications,
        item.parentProductName,
        new Date().toISOString(),
      );
    }
  }
  database.prepare(
    `UPDATE order_modifications SET order_item_id = NULL
     WHERE order_item_id IN (SELECT id FROM order_items WHERE order_id = ?)`,
  ).run(orderId);
  database.prepare('DELETE FROM order_items WHERE order_id = ?').run(orderId);
  const inserted: number[] = [];
  const insertItem = database.prepare(
    `INSERT INTO order_items
     (order_id, product_id, quantity, delivered_quantity, specifications,
      parent_order_item_id, status)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  );
  const insertRemoved = database.prepare(
    `INSERT INTO order_item_removed_ingredients (order_item_id, ingredient_id)
     VALUES (?, ?)`,
  );
  const insertDelivery = database.prepare(
    `INSERT INTO order_item_deliveries
     (order_item_id, unit_index, delivered_at, delivered_by)
     VALUES (?, ?, ?, NULL)`,
  );
  for (const item of items) {
    const parentProductId = item.parentIndex === null
      ? null : items[item.parentIndex].productId;
    const signature = orderItemSignature(
      item.productId,
      item.specifications,
      item.removedIngredientIds,
      parentProductId,
    );
    const preserved = deliveredBySignature.get(signature) ?? 0;
    const deliveredQuantity = Math.min(preserved, item.quantity);
    deliveredBySignature.set(signature, Math.max(0, preserved - deliveredQuantity));
    const status = deliveredQuantity === item.quantity ? 'delivered' : 'ordered';
    const result = insertItem.run(
      orderId,
      item.productId,
      item.quantity,
      deliveredQuantity,
      item.specifications,
      item.parentIndex === null ? null : inserted[item.parentIndex],
      status,
    );
    const itemId = Number(result.lastInsertRowid);
    inserted.push(itemId);
    for (let unitIndex = 0; unitIndex < deliveredQuantity; unitIndex++) {
      insertDelivery.run(itemId, unitIndex, new Date().toISOString());
    }
    for (const ingredientId of item.removedIngredientIds) {
      insertRemoved.run(itemId, ingredientId);
    }
  }
}

function orderItemSignature(
  productId: number,
  specifications: string | null,
  removedIngredientIds: number[],
  parentProductId: number | null,
) {
  return JSON.stringify([
    productId,
    specifications ?? '',
    [...removedIngredientIds].sort((left, right) => left - right),
    parentProductId,
  ]);
}

function orderHasPendingItems(database: DatabaseSync, orderId: number) {
  return database.prepare(
    `SELECT 1 FROM order_items
     WHERE order_id = ? AND delivered_quantity < quantity LIMIT 1`,
  ).get(orderId) !== undefined;
}

function recordOrderModification(database: DatabaseSync, orderId: number,
  orderItemId: number | null, modifierId: number, type: string,
  oldValue: string | null, newValue: string | null, createdAt: string) {
  database.prepare(
    `INSERT INTO order_modifications
     (order_id, order_item_id, modifier_id, modification_type, old_value, new_value, created_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)`,
  ).run(orderId, orderItemId, modifierId, type, oldValue, newValue, createdAt);
}

function readRoomOrders(database: DatabaseSync, roomId: number) {
  return (database.prepare(
    `SELECT o.id FROM orders o LEFT JOIN hall_tables t ON t.id = o.table_id
     WHERE COALESCE(o.hall_id, t.hall_id) = ? AND o.status != 'closed'
     ORDER BY o.created_at`,
  ).all(roomId) as Array<{ id: number }>).map(({ id }) => readOrder(database, id));
}

function logicalTableLabel(
  database: DatabaseSync,
  tableId: number | null,
  tableGroupId: number | null,
  externalName: string | null = null,
) {
  if (externalName) return externalName;
  if (tableGroupId !== null) {
    const group = database.prepare(
      'SELECT visible_identifier AS label FROM table_groups WHERE id = ?',
    ).get(tableGroupId) as { label: string } | undefined;
    if (group?.label) return group.label;
  }
  const table = database.prepare(
    'SELECT identifier AS label FROM hall_tables WHERE id = ?',
  ).get(tableId) as { label: string } | undefined;
  return table?.label ?? String(tableId ?? 'Pedido externo');
}

function readOrder(database: DatabaseSync, orderId: number) {
  const order = database.prepare(
    `SELECT o.id, o.table_id AS tableId, o.table_group_id AS tableGroupId,
            o.external_name AS externalName,
            o.author_id AS authorId, o.description,
            o.status, o.created_at AS createdAt, o.updated_at AS updatedAt,
            COALESCE(o.external_name, g.visible_identifier, t.identifier) AS tableLabel
     FROM orders o
     LEFT JOIN hall_tables t ON t.id = o.table_id
     LEFT JOIN table_groups g ON g.id = o.table_group_id
     WHERE o.id = ?`,
  ).get(orderId);
  const items = database.prepare(
    `WITH RECURSIVE category_paths(id, path) AS (
       SELECT id, name FROM menu_categories WHERE parent_category_id IS NULL
       UNION ALL
       SELECT child.id, category_paths.path || ' › ' || child.name
       FROM menu_categories child
       JOIN category_paths ON child.parent_category_id = category_paths.id
     )
     SELECT oi.id, oi.product_id AS productId, p.name,
            category_paths.path AS categoryName,
            p.description AS productDescription, p.value AS unitValue, oi.quantity,
            oi.delivered_quantity AS deliveredQuantity,
            oi.specifications, oi.parent_order_item_id AS parentOrderItemId,
            oi.status
     FROM order_items oi JOIN products p ON p.id = oi.product_id
     JOIN menu_categories category ON category.id = p.category_id
     JOIN category_paths ON category_paths.id = category.id
     WHERE oi.order_id = ? ORDER BY oi.id`,
  ).all(orderId) as Array<Record<string, unknown> & { id: number; productId: number }>;
  const removedItems = database.prepare(
    `SELECT id, product_name AS name, category_name AS categoryName,
            product_description AS productDescription,
            unit_value AS unitValue, quantity, specifications,
            parent_product_name AS parentProductName, removed_at AS removedAt
     FROM removed_order_items WHERE order_id = ? ORDER BY id`,
  ).all(orderId);
  const total = items.reduce(
    (sum, item) => sum + Number(item.unitValue) * Number(item.quantity),
    0,
  );
  return { ...order as object, total, removedItems, items: items.map((item) => ({
    ...item,
    deliveredUnitIndexes: (database.prepare(
      `SELECT unit_index AS unitIndex FROM order_item_deliveries
       WHERE order_item_id = ? ORDER BY unit_index`,
    ).all(item.id) as Array<{ unitIndex: number }>).map(({ unitIndex }) => unitIndex),
    removedIngredientIds: (database.prepare(
      `SELECT ingredient_id AS id FROM order_item_removed_ingredients
       WHERE order_item_id = ? ORDER BY ingredient_id`,
    ).all(item.id) as Array<{ id: number }>).map(({ id }) => id),
    ingredients: database.prepare(
      `SELECT i.id, i.name FROM product_ingredients pi
       JOIN ingredients i ON i.id = pi.ingredient_id
       WHERE pi.product_id = ? ORDER BY i.name`,
    ).all(item.productId),
  })) };
}

function readRoomMenus(database: DatabaseSync, roomId: number) {
  const menus = database.prepare(
    `SELECT m.id, m.name, mh.is_primary AS isPrimary FROM menu m
     JOIN menu_halls mh ON mh.menu_id = m.id
     WHERE mh.hall_id = ? ORDER BY m.name COLLATE NOCASE`,
  ).all(roomId) as Array<{ id: number; name: string; isPrimary: number }>;
  return menus.map((menu) => ({
    id: menu.id,
    name: menu.name,
    isPrimary: menu.isPrimary === 1,
    categories: (database.prepare(
      `SELECT id, name, parent_category_id AS parentCategoryId,
              is_special AS isSpecial FROM menu_categories
       WHERE menu_id = ?
       ORDER BY parent_category_id IS NOT NULL, parent_category_id,
                position, name COLLATE NOCASE, id`,
    ).all(menu.id) as Array<{
      id: number; name: string; parentCategoryId: number | null; isSpecial: number;
    }>).map((category) => ({
      id: category.id,
      name: category.name,
      parentCategoryId: category.parentCategoryId,
      isSpecial: category.isSpecial === 1,
      products: (database.prepare(
        `SELECT p.id, p.name, p.description, p.value
         FROM products p
         LEFT JOIN category_product_positions ordering
           ON ordering.category_id = p.category_id
          AND ordering.product_id = p.id
         WHERE p.category_id = ? AND p.is_active = 1
           AND (? = 1 OR EXISTS (
             SELECT 1 FROM product_halls allowed
             WHERE allowed.product_id = p.id AND allowed.hall_id = ?
           ))
         ORDER BY ordering.position IS NULL, ordering.position,
                  p.name COLLATE NOCASE, p.id`,
      ).all(category.id, menu.isPrimary, roomId) as Array<{
        id: number; name: string; description: string | null; value: number;
      }>).map((product) => ({
        ...product,
        ingredients: database.prepare(
          `SELECT i.id, i.name, i.description
           FROM product_ingredients pi
           JOIN ingredients i ON i.id = pi.ingredient_id
           WHERE pi.product_id = ? ORDER BY i.name COLLATE NOCASE`,
        ).all(product.id),
      })),
    })),
  }));
}

function validateLiveLayout(database: DatabaseSync, roomId: number, value: unknown):
  { valid: true; tables: StoredTable[]; groups: Array<{
    id?: number; identifier?: string; tableIds: number[];
  }> } |
  { valid: false; message: string } {
  if (typeof value !== 'object' || value === null || Array.isArray(value)) {
    return { valid: false, message: 'El payload debe ser un objeto.' };
  }
  const data = value as Record<string, unknown>;
  if (!Array.isArray(data.tables) || !Array.isArray(data.groups)) {
    return { valid: false, message: 'tables y groups deben ser listas.' };
  }
  const stored = database.prepare(
    `SELECT id, identifier, x, y, width, height, rotation
     FROM hall_tables WHERE hall_id = ? ORDER BY id`,
  ).all(roomId) as StoredTable[];
  if (data.tables.length !== stored.length) {
    return { valid: false, message: 'Deben enviarse todas las mesas del salón.' };
  }
  const storedById = new Map(stored.map((table) => [table.id, table]));
  const ids = new Set<number>();
  const tables: StoredTable[] = [];
  for (const raw of data.tables) {
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      return { valid: false, message: 'Mesa inválida.' };
    }
    const candidate = raw as Record<string, unknown>;
    const id = candidate.id;
    const x = candidate.x;
    const y = candidate.y;
    if (!Number.isSafeInteger(id) || ids.has(id as number) ||
        typeof x !== 'number' || !Number.isFinite(x) || Math.abs(x) > 10_000 ||
        typeof y !== 'number' || !Number.isFinite(y) || Math.abs(y) > 10_000 ||
        !storedById.has(id as number)) {
      return { valid: false, message: 'Posición o identificador de mesa inválido.' };
    }
    ids.add(id as number);
    tables.push({ ...storedById.get(id as number)!, x, y });
  }
  for (let index = 0; index < tables.length; index++) {
    for (let other = index + 1; other < tables.length; other++) {
      if (intersects(tables[index], tables[other])) {
        return { valid: false, message: 'Las mesas no pueden superponerse.' };
      }
    }
  }

  const groupedIds = new Set<number>();
  const groups: Array<{ id?: number; identifier?: string; tableIds: number[] }> = [];
  for (const raw of data.groups) {
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
      return { valid: false, message: 'Agrupación inválida.' };
    }
    const group = raw as Record<string, unknown>;
    const tableIds = group.tableIds;
    if (!Array.isArray(tableIds) || tableIds.length < 2 ||
        tableIds.some((id) => !Number.isSafeInteger(id) ||
          !storedById.has(id as number) || groupedIds.has(id as number))) {
      return { valid: false, message: 'Miembros de agrupación inválidos.' };
    }
    for (const id of tableIds) groupedIds.add(id as number);
    groups.push({
      id: Number.isSafeInteger(group.id) ? group.id as number : undefined,
      identifier: typeof group.identifier === 'string'
        ? group.identifier.trim().slice(0, 50) : undefined,
      tableIds: tableIds as number[],
    });
  }
  return { valid: true, tables, groups };
}

function intersects(first: StoredTable, second: StoredTable) {
  const bounds = (table: StoredTable) => {
    const cosine = Math.abs(Math.cos(table.rotation));
    const sine = Math.abs(Math.sin(table.rotation));
    const width = table.width * cosine + table.height * sine;
    const height = table.width * sine + table.height * cosine;
    return {
      left: table.x + table.width / 2 - width / 2,
      right: table.x + table.width / 2 + width / 2,
      top: table.y + table.height / 2 - height / 2,
      bottom: table.y + table.height / 2 + height / 2,
    };
  };
  const a = bounds(first);
  const b = bounds(second);
  const tolerance = .05;
  return a.left < b.right - tolerance && a.right > b.left + tolerance &&
    a.top < b.bottom - tolerance && a.bottom > b.top + tolerance;
}

const app = createDeviceApp();
export default app;
