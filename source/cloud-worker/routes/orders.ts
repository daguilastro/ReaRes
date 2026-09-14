import { Hono } from 'hono';
import { canAccessHall, requireSession } from '../auth/session';
import { readHallOrders, readOrder, tableLabel } from '../repositories/orderModel';
import { generatedId, jsonObject, positiveId, rows } from '../shared/http';
import type { CloudEnvironment } from '../types';
import { parseOrderInput, type OrderInput, type OrderItemInput } from '../orders/validation';

const routes = new Hono<CloudEnvironment>();
routes.use('*', requireSession);

routes.get('/halls/:hallId/menus', async (c) => {
  const hallId = await accessibleHall(c);
  if (hallId instanceof Response) return hallId;
  const menus = await rows<{ id: number; name: string; isPrimary: number }>(c.env.DB.prepare(
    `SELECT m.id, m.name, mh.is_primary AS isPrimary FROM menu m
     JOIN menu_halls mh ON mh.menu_id = m.id
     WHERE mh.hall_id = ? ORDER BY mh.is_primary DESC, m.name COLLATE NOCASE`,
  ).bind(hallId));
  const catalog = await Promise.all(menus.map(async (menu) => {
    const categories = await rows<Record<string, unknown>>(c.env.DB.prepare(
      `SELECT id, name, parent_category_id AS parentCategoryId,
              is_special AS isSpecial, position
       FROM menu_categories WHERE menu_id = ?
       ORDER BY position, name COLLATE NOCASE, id`,
    ).bind(menu.id));
    const products = await rows<Record<string, unknown> & { id: number; categoryId: number }>(
      c.env.DB.prepare(
        `SELECT p.id, p.name, p.description, p.value, p.category_id AS categoryId,
                ordering.position
         FROM products p
         LEFT JOIN category_product_positions ordering
           ON ordering.category_id = p.category_id AND ordering.product_id = p.id
         WHERE p.menu_id = ? AND p.is_active = 1
           AND (? = 1 OR EXISTS (
             SELECT 1 FROM product_halls ph
             WHERE ph.product_id = p.id AND ph.hall_id = ?
           ))
         ORDER BY p.category_id, ordering.position IS NULL, ordering.position,
                  p.name COLLATE NOCASE, p.id`,
      ).bind(menu.id, menu.isPrimary, hallId),
    );
    const ingredients = products.length === 0 ? [] : await rows<{
      productId: number; id: number; name: string; description: string | null;
    }>(c.env.DB.prepare(
      `SELECT pi.product_id AS productId, i.id, i.name, i.description
       FROM product_ingredients pi
       JOIN ingredients i ON i.id = pi.ingredient_id
       JOIN products p ON p.id = pi.product_id
       WHERE p.menu_id = ? AND p.is_active = 1
         AND (? = 1 OR EXISTS (
           SELECT 1 FROM product_halls ph
           WHERE ph.product_id = p.id AND ph.hall_id = ?
         ))
       ORDER BY i.name COLLATE NOCASE`,
    ).bind(menu.id, menu.isPrimary, hallId));
    return {
      id: menu.id, name: menu.name, isPrimary: menu.isPrimary === 1,
      categories: categories.map((category) => ({
        ...category,
        isSpecial: category.isSpecial === 1,
        products: products.filter((product) => product.categoryId === category.id)
          .map((product) => ({ ...product, ingredients: ingredients.filter(
            (ingredient) => ingredient.productId === product.id,
          ).map(({ productId: _, ...ingredient }) => ingredient) })),
      })),
    };
  }));
  return c.json({ menus: catalog });
});

routes.get('/halls/:hallId/orders', async (c) => {
  const hallId = await accessibleHall(c);
  if (hallId instanceof Response) return hallId;
  return c.json({ orders: await readHallOrders(c.env.DB, hallId) });
});

routes.get('/halls/:hallId/orders/today', async (c) => {
  const hallId = await accessibleHall(c);
  if (hallId instanceof Response) return hallId;
  const fromQuery = c.req.query('from');
  const toQuery = c.req.query('to');
  const paymentMethod = c.req.query('paymentMethod');
  if ((fromQuery === undefined) !== (toQuery === undefined) ||
      (paymentMethod !== undefined && !paymentMethods.has(paymentMethod))) {
    return c.json({ error: 'INVALID_HISTORY_FILTER' }, 422);
  }
  let from = fromQuery;
  let to = toQuery;
  if (from && to) {
    const start = new Date(from);
    const end = new Date(to);
    if (Number.isNaN(start.getTime()) || Number.isNaN(end.getTime()) || start >= end) {
      return c.json({ error: 'INVALID_HISTORY_FILTER' }, 422);
    }
    from = start.toISOString();
    to = end.toISOString();
  } else {
    const range = bogotaBusinessDay(new Date());
    from = range.from;
    to = range.to;
  }
  const orders = (await readHallOrders(c.env.DB, hallId, true, from, to, paymentMethod))
    .filter((order) => order !== undefined);
  return c.json({
    orders,
    total: orders.reduce((sum, order) => sum + Number(order?.total ?? 0), 0),
  });
});

routes.post('/halls/:hallId/tables/:tableId/orders', async (c) => {
  const hallId = await accessibleHall(c);
  if (hallId instanceof Response) return hallId;
  const tableId = positiveId(c.req.param('tableId'));
  const target = tableId ? await tableTarget(c.env.DB, hallId, tableId) : null;
  if (!tableId || !target) return c.json({ error: 'HALL_OR_TABLE_NOT_ASSIGNED' }, 403);
  if (await activeOrderAt(c.env.DB, tableId, target.groupId)) {
    return c.json({ error: 'ACTIVE_ORDER_EXISTS' }, 409);
  }
  const body = await jsonObject(c);
  if (body instanceof Response) return body;
  const input = await parseOrderInput(c.env.DB, body, hallId);
  if (!input) return c.json({ error: 'INVALID_ORDER' }, 422);
  const orderId = generatedId();
  const now = new Date().toISOString();
  const session = c.get('session');
  const label = await tableLabel(c.env.DB, tableId, target.groupId);
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO orders
       (id, author_id, table_id, table_group_id, description, receiver,
        status, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, NULL, 'waiting', ?, ?)`,
    ).bind(orderId, session.user.id, tableId, target.groupId, input.description, now, now),
    ...itemStatements(c.env.DB, orderId, input.items),
    modification(c.env.DB, orderId, null, session.user.id, 'create', null,
      JSON.stringify(input), now),
    ...targetStatusStatements(c.env.DB, tableId, target.groupId, 'waiting'),
    activity(c.env.DB, session.user.id, hallId, 'Pedido',
      `Creó un pedido en la mesa ${label}`, now),
  ]);
  return c.json({ order: await readOrder(c.env.DB, orderId) }, 201);
});

routes.post('/halls/:hallId/external-orders', async (c) => {
  const hallId = await accessibleHall(c);
  if (hallId instanceof Response) return hallId;
  const body = await jsonObject(c);
  if (body instanceof Response) return body;
  const externalName = typeof body.externalName === 'string'
    ? body.externalName.trim().slice(0, 80) : '';
  if (!externalName) return c.json({ error: 'EXTERNAL_NAME_REQUIRED' }, 422);
  const input = await parseOrderInput(c.env.DB, body, hallId);
  if (!input) return c.json({ error: 'INVALID_ORDER' }, 422);
  const orderId = generatedId();
  const now = new Date().toISOString();
  const session = c.get('session');
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO orders
       (id, author_id, table_id, table_group_id, hall_id, external_name,
        description, receiver, status, created_at, updated_at)
       VALUES (?, ?, NULL, NULL, ?, ?, ?, NULL, 'waiting', ?, ?)`,
    ).bind(orderId, session.user.id, hallId, externalName, input.description, now, now),
    ...itemStatements(c.env.DB, orderId, input.items),
    modification(c.env.DB, orderId, null, session.user.id, 'create', null,
      JSON.stringify(input), now),
    activity(c.env.DB, session.user.id, hallId, 'Pedido',
      `Creó el pedido externo ${externalName}`, now),
  ]);
  return c.json({ order: await readOrder(c.env.DB, orderId) }, 201);
});

routes.put('/halls/:hallId/orders/:orderId', async (c) => {
  const hallId = await accessibleHall(c);
  if (hallId instanceof Response) return hallId;
  const orderId = positiveId(c.req.param('orderId'));
  const current = orderId ? await activeOrder(c.env.DB, hallId, orderId) : null;
  if (!orderId || !current) return c.json({ error: 'ORDER_NOT_FOUND' }, 404);
  const body = await jsonObject(c);
  if (body instanceof Response) return body;
  const input = await parseOrderInput(c.env.DB, body, hallId, true);
  if (!input) return c.json({ error: 'INVALID_ORDER' }, 422);
  const oldOrder = await readOrder(c.env.DB, orderId);
  if (!oldOrder || !keepsDelivered(oldOrder.items, input.items)) {
    return c.json({ error: 'DELIVERED_ITEM_CANNOT_BE_REMOVED' }, 409);
  }
  const session = c.get('session');
  const now = new Date().toISOString();
  const label = await tableLabel(c.env.DB, current.tableId, current.tableGroupId,
    current.externalName);
  if (input.items.length === 0) {
    await c.env.DB.batch([
      c.env.DB.prepare('DELETE FROM order_modifications WHERE order_id = ?').bind(orderId),
      c.env.DB.prepare('DELETE FROM order_items WHERE order_id = ?').bind(orderId),
      c.env.DB.prepare('DELETE FROM removed_order_items WHERE order_id = ?').bind(orderId),
      c.env.DB.prepare('DELETE FROM orders WHERE id = ?').bind(orderId),
      ...(current.tableId === null ? [] : targetStatusStatements(
        c.env.DB, current.tableId, current.tableGroupId, 'available')),
      activity(c.env.DB, session.user.id, hallId, 'Pedido',
        `Eliminó el pedido pendiente de ${label}`, now),
    ]);
    return c.json({ deleted: true });
  }
  const replacement = buildReplacement(c.env.DB, orderId, oldOrder.items, input.items, now);
  const nextStatus = replacement.pending ? 'waiting' : 'eating';
  await c.env.DB.batch([
    ...replacement.statements,
    c.env.DB.prepare(
      'UPDATE orders SET description = ?, status = ?, updated_at = ? WHERE id = ?',
    ).bind(input.description, nextStatus, now, orderId),
    ...(current.tableId === null ? [] : targetStatusStatements(
      c.env.DB, current.tableId, current.tableGroupId, nextStatus)),
    modification(c.env.DB, orderId, null, session.user.id, 'update',
      JSON.stringify(oldOrder), JSON.stringify(input), now),
    activity(c.env.DB, session.user.id, hallId, 'Pedido',
      `Modificó el pedido de ${label}`, now),
  ]);
  return c.json({ order: await readOrder(c.env.DB, orderId) });
});

routes.patch('/halls/:hallId/orders/:orderId/transfer', async (c) => {
  const hallId = await accessibleHall(c);
  if (hallId instanceof Response) return hallId;
  const orderId = positiveId(c.req.param('orderId'));
  const current = orderId ? await activeOrder(c.env.DB, hallId, orderId) : null;
  const body = await jsonObject(c);
  if (body instanceof Response) return body;
  const tableId = positiveId(body.tableId);
  if (!orderId || !current || current.tableId === null) {
    return c.json({ error: 'ORDER_NOT_FOUND' }, 404);
  }
  const target = tableId ? await tableTarget(c.env.DB, hallId, tableId) : null;
  if (!tableId || !target || target.status !== 'available' ||
      await activeOrderAt(c.env.DB, tableId, target.groupId, orderId)) {
    return c.json({ error: 'TABLE_NOT_AVAILABLE' }, 409);
  }
  const session = c.get('session');
  const now = new Date().toISOString();
  const oldLabel = await tableLabel(c.env.DB, current.tableId, current.tableGroupId);
  const newLabel = await tableLabel(c.env.DB, tableId, target.groupId);
  await c.env.DB.batch([
    ...targetStatusStatements(c.env.DB, current.tableId, current.tableGroupId, 'available'),
    c.env.DB.prepare(
      `UPDATE orders SET table_id = ?, table_group_id = ?, updated_at = ? WHERE id = ?`,
    ).bind(tableId, target.groupId, now, orderId),
    ...targetStatusStatements(c.env.DB, tableId, target.groupId, current.status),
    modification(c.env.DB, orderId, null, session.user.id, 'transfer', oldLabel, newLabel, now),
    activity(c.env.DB, session.user.id, hallId, 'Mesa',
      `Trasladó el pedido de ${oldLabel} a ${newLabel}`, now),
  ]);
  return c.json({ order: await readOrder(c.env.DB, orderId) });
});

routes.patch('/halls/:hallId/orders/:orderId/status', async (c) => {
  const hallId = await accessibleHall(c);
  if (hallId instanceof Response) return hallId;
  const orderId = positiveId(c.req.param('orderId'));
  const current = orderId ? await activeOrder(c.env.DB, hallId, orderId) : null;
  if (!orderId || !current) return c.json({ error: 'ORDER_NOT_FOUND' }, 404);
  const body = await jsonObject(c);
  if (body instanceof Response) return body;
  const status = body.status;
  const paymentMethod = body.paymentMethod;
  if (status !== 'eating' && status !== 'closed') {
    return c.json({ error: 'INVALID_ORDER_STATUS' }, 422);
  }
  if (status === 'closed' && (typeof paymentMethod !== 'string' ||
      !paymentMethods.has(paymentMethod))) {
    return c.json({ error: 'INVALID_PAYMENT_METHOD' }, 422);
  }
  if ((status === 'eating' && current.status !== 'waiting') ||
      (status === 'closed' && current.status !== 'eating')) {
    return c.json({ error: status === 'closed'
      ? 'ORDER_NOT_READY_TO_BILL' : 'INVALID_ORDER_STATUS' }, 409);
  }
  if (await hasPendingItems(c.env.DB, orderId)) {
    return c.json({ error: 'ORDER_ITEMS_PENDING' }, 409);
  }
  const session = c.get('session');
  const now = new Date().toISOString();
  const label = await tableLabel(c.env.DB, current.tableId, current.tableGroupId,
    current.externalName);
  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE orders SET status = ?, payment_method = ?, updated_at = ? WHERE id = ?`,
    ).bind(status, status === 'closed' ? paymentMethod : null, now, orderId),
    ...(current.tableId === null ? [] : targetStatusStatements(c.env.DB,
      current.tableId, current.tableGroupId, status === 'closed' ? 'available' : 'eating')),
    modification(c.env.DB, orderId, null, session.user.id, 'status', current.status, status, now),
    activity(c.env.DB, session.user.id, hallId, 'Mesa', status === 'closed'
      ? `Facturó ${label}` : `Marcó ${label} como comiendo`, now),
  ]);
  return c.json({ order: await readOrder(c.env.DB, orderId) });
});

routes.patch(
  '/halls/:hallId/orders/:orderId/items/:itemId/units/:unitIndex/deliver',
  async (c) => changeDelivery(c, true),
);
routes.patch(
  '/halls/:hallId/orders/:orderId/items/:itemId/units/:unitIndex/undo-delivery',
  async (c) => changeDelivery(c, false),
);

async function changeDelivery(c: Parameters<typeof accessibleHall>[0], deliver: boolean) {
  const hallId = await accessibleHall(c);
  if (hallId instanceof Response) return hallId;
  const orderId = positiveId(c.req.param('orderId'));
  const itemId = positiveId(c.req.param('itemId'));
  const unitIndex = Number(c.req.param('unitIndex'));
  if (!orderId || !itemId || !Number.isSafeInteger(unitIndex) || unitIndex < 0) {
    return c.json({ error: 'ORDER_ITEM_NOT_FOUND' }, 404);
  }
  const item = await c.env.DB.prepare(
    `SELECT oi.quantity, oi.delivered_quantity AS deliveredQuantity,
            o.table_id AS tableId, o.table_group_id AS tableGroupId,
            o.external_name AS externalName
     FROM order_items oi JOIN orders o ON o.id = oi.order_id
     LEFT JOIN hall_tables t ON t.id = o.table_id
     WHERE oi.id = ? AND o.id = ? AND COALESCE(o.hall_id, t.hall_id) = ?
       AND o.status != 'closed'`,
  ).bind(itemId, orderId, hallId).first<{
    quantity: number; deliveredQuantity: number; tableId: number | null;
    tableGroupId: number | null; externalName: string | null;
  }>();
  if (!item || unitIndex >= item.quantity) {
    return c.json({ error: 'ORDER_ITEM_UNIT_NOT_FOUND' }, 404);
  }
  const delivery = await c.env.DB.prepare(
    `SELECT 1 FROM order_item_deliveries
     WHERE order_item_id = ? AND unit_index = ?`,
  ).bind(itemId, unitIndex).first();
  if (deliver === (delivery !== null)) {
    return c.json({ error: deliver
      ? 'ORDER_ITEM_ALREADY_DELIVERED' : 'ORDER_ITEM_NOT_DELIVERED' }, 409);
  }
  const deliveredQuantity = item.deliveredQuantity + (deliver ? 1 : -1);
  const pendingElsewhere = await c.env.DB.prepare(
    `SELECT 1 FROM order_items
     WHERE order_id = ? AND id != ? AND delivered_quantity < quantity LIMIT 1`,
  ).bind(orderId, itemId).first() !== null;
  const nextStatus = !deliver || deliveredQuantity < item.quantity || pendingElsewhere
    ? 'waiting' : 'eating';
  const session = c.get('session');
  const now = new Date().toISOString();
  const label = await tableLabel(c.env.DB, item.tableId, item.tableGroupId, item.externalName);
  await c.env.DB.batch([
    deliver
      ? c.env.DB.prepare(
        `INSERT INTO order_item_deliveries
         (order_item_id, unit_index, delivered_at, delivered_by) VALUES (?, ?, ?, ?)`,
      ).bind(itemId, unitIndex, now, session.user.id)
      : c.env.DB.prepare(
        `DELETE FROM order_item_deliveries WHERE order_item_id = ? AND unit_index = ?`,
      ).bind(itemId, unitIndex),
    c.env.DB.prepare(
      `UPDATE order_items SET delivered_quantity = ?, status = ? WHERE id = ?`,
    ).bind(deliveredQuantity, deliveredQuantity === item.quantity ? 'delivered' : 'ordered', itemId),
    c.env.DB.prepare('UPDATE orders SET status = ?, updated_at = ? WHERE id = ?')
      .bind(nextStatus, now, orderId),
    ...(item.tableId === null ? [] : targetStatusStatements(
      c.env.DB, item.tableId, item.tableGroupId, nextStatus)),
    modification(c.env.DB, orderId, itemId, session.user.id,
      deliver ? 'deliver' : 'undo_delivery', String(item.deliveredQuantity),
      String(deliveredQuantity), now),
    activity(c.env.DB, session.user.id, hallId, 'Pedido', deliver
      ? `${nextStatus === 'eating' ? 'Entregó el último producto' : 'Entregó un producto'} de ${label}`
      : `Deshizo una entrega de ${label}`, now),
  ]);
  return c.json({ order: await readOrder(c.env.DB, orderId) });
}

async function accessibleHall(c: import('hono').Context<CloudEnvironment>) {
  const hallId = positiveId(c.req.param('hallId'));
  if (!hallId || !await canAccessHall(c.env.DB, c.get('session'), hallId)) {
    return c.json({ error: 'HALL_NOT_ASSIGNED' }, 403);
  }
  return hallId;
}

async function tableTarget(database: D1Database, hallId: number, tableId: number) {
  return database.prepare(
    `SELECT t.status, m.group_id AS groupId
     FROM hall_tables t LEFT JOIN table_group_members m ON m.table_id = t.id
     WHERE t.id = ? AND t.hall_id = ?`,
  ).bind(tableId, hallId).first<{ status: string; groupId: number | null }>();
}

async function activeOrderAt(database: D1Database, tableId: number,
  groupId: number | null, excludedId = -1) {
  return await database.prepare(
    `SELECT 1 FROM orders WHERE status != 'closed' AND id != ?
     AND (table_id = ? OR (? IS NOT NULL AND table_group_id = ?)) LIMIT 1`,
  ).bind(excludedId, tableId, groupId, groupId).first() !== null;
}

async function activeOrder(database: D1Database, hallId: number, orderId: number) {
  return database.prepare(
    `SELECT o.table_id AS tableId, o.table_group_id AS tableGroupId,
            o.external_name AS externalName, o.status
     FROM orders o LEFT JOIN hall_tables t ON t.id = o.table_id
     WHERE o.id = ? AND COALESCE(o.hall_id, t.hall_id) = ? AND o.status != 'closed'`,
  ).bind(orderId, hallId).first<{
    tableId: number | null; tableGroupId: number | null;
    externalName: string | null; status: string;
  }>();
}

function itemStatements(database: D1Database, orderId: number, items: OrderItemInput[]) {
  const ids = items.map(() => generatedId());
  const statements: D1PreparedStatement[] = [];
  items.forEach((item, index) => {
    statements.push(database.prepare(
      `INSERT INTO order_items
       (id, order_id, product_id, quantity, delivered_quantity, specifications,
        parent_order_item_id, status, unit_value)
       SELECT ?, ?, ?, ?, 0, ?, ?, 'ordered', value FROM products WHERE id = ?`,
    ).bind(ids[index], orderId, item.productId, item.quantity, item.specifications,
      item.parentIndex === null ? null : ids[item.parentIndex], item.productId));
    statements.push(...item.removedIngredientIds.map((ingredientId) => database.prepare(
      `INSERT INTO order_item_removed_ingredients (order_item_id, ingredient_id)
       VALUES (?, ?)`,
    ).bind(ids[index], ingredientId)));
  });
  return statements;
}

function targetStatusStatements(database: D1Database, tableId: number,
  groupId: number | null, status: string) {
  if (groupId === null) return [database.prepare(
    'UPDATE hall_tables SET status = ? WHERE id = ?',
  ).bind(status, tableId)];
  return [
    database.prepare('UPDATE table_groups SET status = ? WHERE id = ?').bind(status, groupId),
    database.prepare(
      `UPDATE hall_tables SET status = ? WHERE id IN (
         SELECT table_id FROM table_group_members WHERE group_id = ?
       )`,
    ).bind(status, groupId),
  ];
}

function modification(database: D1Database, orderId: number, itemId: number | null,
  userId: number, type: string, oldValue: string | null, newValue: string | null, now: string) {
  return database.prepare(
    `INSERT INTO order_modifications
     (id, order_id, order_item_id, modifier_id, modification_type,
      old_value, new_value, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`,
  ).bind(generatedId(), orderId, itemId, userId, type, oldValue, newValue, now);
}

function activity(database: D1Database, userId: number, hallId: number,
  type: string, message: string, now: string) {
  return database.prepare(
    `INSERT INTO activity_log
     (id, author_id, hall_id, type, modification, created_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  ).bind(generatedId(), userId, hallId, type, message, now);
}

async function hasPendingItems(database: D1Database, orderId: number) {
  return await database.prepare(
    `SELECT 1 FROM order_items
     WHERE order_id = ? AND delivered_quantity < quantity LIMIT 1`,
  ).bind(orderId).first() !== null;
}

type StoredItem = Record<string, unknown> & {
  id: number; productId: number; quantity: number; deliveredQuantity: number;
  specifications: string | null; parentOrderItemId: number | null;
  removedIngredientIds: number[]; unitValue: number; name: string;
  categoryName: string; productDescription: string | null;
};

function signature(productId: number, specifications: string | null,
  removed: number[], parentProductId: number | null) {
  return JSON.stringify([productId, specifications ?? '', [...removed].sort((a, b) => a - b),
    parentProductId]);
}

function requestedCounts(items: OrderItemInput[]) {
  const counts = new Map<string, number>();
  items.forEach((item) => {
    const parentProductId = item.parentIndex === null ? null : items[item.parentIndex].productId;
    const key = signature(item.productId, item.specifications,
      item.removedIngredientIds, parentProductId);
    counts.set(key, (counts.get(key) ?? 0) + item.quantity);
  });
  return counts;
}

function keepsDelivered(stored: StoredItem[], requested: OrderItemInput[]) {
  const counts = requestedCounts(requested);
  const byId = new Map(stored.map((item) => [item.id, item]));
  const delivered = new Map<string, number>();
  stored.forEach((item) => {
    const parent = item.parentOrderItemId === null ? null : byId.get(item.parentOrderItemId);
    const key = signature(item.productId, item.specifications, item.removedIngredientIds,
      parent?.productId ?? null);
    delivered.set(key, (delivered.get(key) ?? 0) + item.deliveredQuantity);
  });
  return [...delivered].every(([key, count]) => (counts.get(key) ?? 0) >= count);
}

function buildReplacement(database: D1Database, orderId: number,
  stored: StoredItem[], requested: OrderItemInput[], now: string) {
  const byId = new Map(stored.map((item) => [item.id, item]));
  const delivered = new Map<string, number>();
  stored.forEach((item) => {
    const parent = item.parentOrderItemId === null ? null : byId.get(item.parentOrderItemId);
    const key = signature(item.productId, item.specifications, item.removedIngredientIds,
      parent?.productId ?? null);
    delivered.set(key, (delivered.get(key) ?? 0) + item.deliveredQuantity);
  });
  const ids = requested.map(() => generatedId());
  const remaining = requestedCounts(requested);
  const statements: D1PreparedStatement[] = [
    database.prepare(
      `UPDATE order_modifications SET order_item_id = NULL
       WHERE order_item_id IN (SELECT id FROM order_items WHERE order_id = ?)`,
    ).bind(orderId),
    database.prepare('DELETE FROM order_items WHERE order_id = ?').bind(orderId),
  ];
  for (const item of stored) {
    const parent = item.parentOrderItemId === null ? null : byId.get(item.parentOrderItemId);
    const key = signature(item.productId, item.specifications, item.removedIngredientIds,
      parent?.productId ?? null);
    const retained = Math.min(remaining.get(key) ?? 0, item.quantity);
    remaining.set(key, Math.max(0, (remaining.get(key) ?? 0) - retained));
    const removedQuantity = item.quantity - retained;
    if (removedQuantity > 0) {
      statements.unshift(database.prepare(
        `INSERT INTO removed_order_items
         (id, order_id, product_name, category_name, product_description,
          unit_value, quantity, specifications, parent_product_name, removed_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      ).bind(generatedId(), orderId, item.name, item.categoryName,
        item.productDescription, item.unitValue, removedQuantity, item.specifications,
        parent?.name ?? null, now));
    }
  }
  const priceQueues = new Map<string, number[]>();
  for (const item of stored) {
    const parent = item.parentOrderItemId === null ? null : byId.get(item.parentOrderItemId);
    const key = signature(item.productId, item.specifications, item.removedIngredientIds,
      parent?.productId ?? null);
    const queue = priceQueues.get(key) ?? [];
    for (let unit = 0; unit < item.quantity; unit++) queue.push(item.unitValue);
    priceQueues.set(key, queue);
  }
  let pending = false;
  requested.forEach((item, index) => {
    const parentProductId = item.parentIndex === null ? null : requested[item.parentIndex].productId;
    const key = signature(item.productId, item.specifications,
      item.removedIngredientIds, parentProductId);
    const deliveredQuantity = Math.min(delivered.get(key) ?? 0, item.quantity);
    delivered.set(key, Math.max(0, (delivered.get(key) ?? 0) - deliveredQuantity));
    pending ||= deliveredQuantity < item.quantity;
    statements.push(database.prepare(
      `INSERT INTO order_items
       (id, order_id, product_id, quantity, delivered_quantity, specifications,
        parent_order_item_id, status, unit_value)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?,
         (SELECT value FROM products WHERE id = ?)))`,
    ).bind(ids[index], orderId, item.productId, item.quantity, deliveredQuantity,
      item.specifications, item.parentIndex === null ? null : ids[item.parentIndex],
      deliveredQuantity === item.quantity ? 'delivered' : 'ordered',
      priceQueues.get(key)?.shift() ?? null, item.productId));
    for (let unit = 0; unit < deliveredQuantity; unit++) {
      statements.push(database.prepare(
        `INSERT INTO order_item_deliveries
         (order_item_id, unit_index, delivered_at, delivered_by)
         VALUES (?, ?, ?, NULL)`,
      ).bind(ids[index], unit, now));
    }
    statements.push(...item.removedIngredientIds.map((ingredientId) => database.prepare(
      `INSERT INTO order_item_removed_ingredients (order_item_id, ingredient_id)
       VALUES (?, ?)`,
    ).bind(ids[index], ingredientId)));
  });
  return { statements, pending };
}

function bogotaBusinessDay(now: Date) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'America/Bogota', year: 'numeric', month: '2-digit', day: '2-digit',
  }).formatToParts(now);
  const value = (type: string) => parts.find((part) => part.type === type)?.value ?? '';
  const date = `${value('year')}-${value('month')}-${value('day')}`;
  return {
    from: new Date(`${date}T01:00:00-05:00`).toISOString(),
    to: new Date(`${date}T23:59:59.999-05:00`).toISOString(),
  };
}

const paymentMethods = new Set(['cash', 'transfer', 'card']);

export default routes;
