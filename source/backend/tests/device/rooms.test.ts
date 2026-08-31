import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createDeviceApp } from '../../device/app';
import { hashPassword } from '../../shared/password';
import { roomRealtimeHub, type RoomSocket } from '../../shared/roomRealtime';
import { createAdminActivityRoutes } from '../../admin/routes/activity';

const hash = (value: string) =>
  createHash('sha256').update(value, 'utf8').digest('hex');

test('an employee only loads and updates layouts from assigned rooms', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  const passwordHash = await hashPassword('employee-password');
  database.prepare(
    `INSERT INTO users (id, name, role, username, password_hash)
     VALUES (1, 'Carlos Ruiz', 'waiter', 'carlos', ?)`,
  ).run(passwordHash);
  database.prepare(
    `INSERT INTO paired_devices
     (id, name, certificate_fingerprint, certificate_serial, certificate_pem, paired_at)
     VALUES (1, 'Tablet', 'AA:BB', '01', 'certificate', ?)`,
  ).run(new Date().toISOString());
  database.prepare(
    "INSERT INTO hall (id, name) VALUES (1, 'Principal'), (2, 'Terraza')",
  ).run();
  database.prepare(
    'INSERT INTO employee_halls (user_id, hall_id) VALUES (1, 1)',
  ).run();
  database.prepare(
    `INSERT INTO hall_tables
     (id, identifier, x, y, width, height, rotation, hall_id)
     VALUES (1, 'T-01', 100, 100, 100, 70, 0, 1),
            (2, 'T-02', 260, 100, 100, 70, 0, 1)`,
  ).run();
  database.prepare(
    `INSERT INTO hall_walls (hall_id, x, y, width, height, rotation)
     VALUES (1, 20, 20, 400, 10, 0)`,
  ).run();
  database.prepare("INSERT INTO menu (id, name) VALUES (1, 'Dinner')").run();
  database.prepare(
    'INSERT INTO menu_halls (menu_id, hall_id, is_primary) VALUES (1, 1, 1)',
  ).run();
  database.prepare("INSERT INTO menu (id, name) VALUES (2, 'Specials')").run();
  database.prepare(
    'INSERT INTO menu_halls (menu_id, hall_id, is_primary) VALUES (2, 1, 0)',
  ).run();
  database.prepare(
    "INSERT INTO menu_categories (id, menu_id, name) VALUES (1, 1, 'Main courses')",
  ).run();
  database.prepare(
    `INSERT INTO products (id, name, description, value, menu_id, category_id)
     VALUES (1, 'Visible soup', 'For everyone', 1200, 1, 1),
            (2, 'Room soup', 'Only principal', 1500, 1, 1),
            (3, 'Hidden soup', 'Only terrace', 1800, 1, 1)`,
  ).run();
  database.prepare(
    'INSERT INTO product_halls (product_id, hall_id) VALUES (2, 1), (3, 2)',
  ).run();
  database.prepare(
    `INSERT INTO menu_categories
     (id, menu_id, name, parent_category_id, is_special)
     VALUES (2, 2, 'Additions', NULL, 1)`,
  ).run();
  database.prepare(
    `INSERT INTO products (id, name, description, value, menu_id, category_id)
     VALUES (4, 'Unselected addition', NULL, 200, 2, 2),
            (5, 'Selected addition', NULL, 300, 2, 2)`,
  ).run();
  database.prepare(
    'INSERT INTO product_halls (product_id, hall_id) VALUES (5, 1)',
  ).run();
  database.prepare("INSERT INTO ingredient_categories (id, name) VALUES (1, 'Vegetables')").run();
  database.prepare(
    "INSERT INTO ingredients (id, name, description, category_id) VALUES (1, 'Tomato', NULL, 1)",
  ).run();
  database.prepare(
    'INSERT INTO product_ingredients (product_id, ingredient_id) VALUES (1, 1)',
  ).run();

  const app = createDeviceApp({
    database,
    resolveClientIdentity: () => ({
      fingerprint: 'AA:BB',
      serialNumber: '01',
      certificatePem: 'certificate',
    }),
  });
  const realtimeMessages: Array<Record<string, unknown>> = [];
  const socket = {
    readyState: 1,
    send: (value: string) => realtimeMessages.push(
      JSON.parse(value) as Record<string, unknown>,
    ),
    close: () => undefined,
  } satisfies RoomSocket;
  roomRealtimeHub.connect(socket, 1);
  roomRealtimeHub.subscribe(socket, 1);
  const login = await app.request('/auth/login', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ username: 'carlos', password: 'employee-password' }),
  });
  assert.equal(login.status, 200);
  const loginBody = await login.json() as { token: string; user: { id: number } };
  assert.equal(loginBody.user.id, 1);
  const headers = {
    authorization: `Bearer ${loginBody.token}`,
    'content-type': 'application/json',
  };

  const rooms = await (await app.request('/rooms', { headers })).json() as {
    rooms: Array<{ id: number; tableCount: number }>;
  };
  assert.deepEqual(rooms.rooms, [{ id: 1, name: 'Principal', tableCount: 2 }]);
  assert.equal((await app.request('/rooms/2/layout', { headers })).status, 403);

  const layoutResponse = await app.request('/rooms/1/layout', { headers });
  assert.equal(layoutResponse.status, 200);
  const layout = await layoutResponse.json() as {
    tables: Array<{ id: number; x: number; y: number }>;
    walls: unknown[];
  };
  assert.equal(layout.walls.length, 1);

  const roomMenus = await (await app.request('/rooms/1/menus', { headers })).json() as {
    menus: Array<{ categories: Array<{ products: Array<{ name: string }> }> }>;
  };
  assert.deepEqual(
    roomMenus.menus[0].categories[0].products.map(({ name }) => name),
    ['Hidden soup', 'Room soup', 'Visible soup'],
  );
  assert.equal((roomMenus.menus[0] as unknown as { isPrimary: boolean }).isPrimary, true);
  assert.deepEqual(
    roomMenus.menus[1].categories[0].products.map(({ name }) => name),
    ['Selected addition'],
  );
  assert.equal((await app.request('/rooms/2/menus', { headers })).status, 403);

  const standaloneSpecial = await app.request('/rooms/1/tables/2/orders', {
    method: 'POST', headers,
    body: JSON.stringify({ items: [
      { productId: 5, quantity: 1, specifications: '',
        removedIngredientIds: [], parentIndex: null },
    ] }),
  });
  assert.equal(standaloneSpecial.status, 201);
  const disposableOrder = await standaloneSpecial.json() as {
    order: { id: number };
  };
  const deletedEmptyOrder = await app.request(
    `/rooms/1/orders/${disposableOrder.order.id}`,
    { method: 'PUT', headers, body: JSON.stringify({ items: [] }) },
  );
  assert.equal(deletedEmptyOrder.status, 200);
  assert.deepEqual(await deletedEmptyOrder.json(), { deleted: true });
  assert.equal((database.prepare(
    'SELECT COUNT(*) AS count FROM orders WHERE id = ?',
  ).get(disposableOrder.order.id) as { count: number }).count, 0);
  assert.equal((database.prepare(
    'SELECT status FROM hall_tables WHERE id = 2',
  ).get() as { status: string }).status, 'available');

  const createdOrder = await app.request('/rooms/1/tables/1/orders', {
    method: 'POST', headers,
    body: JSON.stringify({ description: 'Window table', items: [
      { productId: 1, quantity: 2, specifications: 'No salt',
        removedIngredientIds: [1], parentIndex: null },
      { productId: 5, quantity: 1, specifications: '',
        removedIngredientIds: [], parentIndex: 0 },
    ] }),
  });
  assert.equal(createdOrder.status, 201);
  const order = await createdOrder.json() as { order: {
    id: number; status: string; items: Array<{
      id: number; productId: number; deliveredQuantity: number;
      deliveredUnitIndexes: number[];
    }>;
  } };
  assert.equal(order.order.status, 'waiting');
  assert.equal((database.prepare(
    `SELECT COUNT(*) AS count FROM order_items child
     JOIN order_items parent ON parent.id = child.parent_order_item_id
     WHERE child.order_id = ? AND parent.order_id = child.order_id`,
  ).get(order.order.id) as { count: number }).count, 1);
  assert.equal((database.prepare('SELECT status FROM hall_tables WHERE id = 1').get() as
    { status: string }).status, 'waiting');
  assert.equal((database.prepare(
    "SELECT COUNT(*) AS count FROM order_modifications WHERE modification_type = 'create'",
  ).get() as { count: number }).count, 1);
  assert.equal(realtimeMessages.at(-1)?.type, 'room-orders-changed');
  assert.equal(realtimeMessages.at(-1)?.roomId, 1);

  const mainItem = order.order.items.find(({ productId }) => productId === 1)!;
  const deliveredSecondUnit = await app.request(
    `/rooms/1/orders/${order.order.id}/items/${mainItem.id}/units/1/deliver`,
    { method: 'PATCH', headers },
  );
  assert.equal(deliveredSecondUnit.status, 200);
  const partiallyDelivered = await deliveredSecondUnit.json() as {
    order: { status: string; items: Array<{
      productId: number; deliveredQuantity: number; deliveredUnitIndexes: number[];
    }> };
  };
  const partialMain = partiallyDelivered.order.items.find(
    ({ productId }) => productId === 1,
  )!;
  assert.equal(partiallyDelivered.order.status, 'waiting');
  assert.equal(partialMain.deliveredQuantity, 1);
  assert.deepEqual(partialMain.deliveredUnitIndexes, [1]);

  const forbiddenRemoval = await app.request(`/rooms/1/orders/${order.order.id}`, {
    method: 'PUT', headers,
    body: JSON.stringify({ description: 'Changed note', items: [
      { productId: 1, quantity: 1, specifications: 'Extra hot',
        removedIngredientIds: [], parentIndex: null },
    ] }),
  });
  assert.equal(forbiddenRemoval.status, 409);
  assert.deepEqual(await forbiddenRemoval.json(), {
    error: 'DELIVERED_ITEM_CANNOT_BE_REMOVED',
  });

  const forbiddenEmptyOrder = await app.request(`/rooms/1/orders/${order.order.id}`, {
    method: 'PUT', headers, body: JSON.stringify({ items: [] }),
  });
  assert.equal(forbiddenEmptyOrder.status, 409);
  assert.deepEqual(await forbiddenEmptyOrder.json(), {
    error: 'DELIVERED_ITEM_CANNOT_BE_REMOVED',
  });

  const undoOriginalDelivery = await app.request(
    `/rooms/1/orders/${order.order.id}/items/${mainItem.id}/units/1/undo-delivery`,
    { method: 'PATCH', headers },
  );
  assert.equal(undoOriginalDelivery.status, 200);

  const modifiedOrder = await app.request(`/rooms/1/orders/${order.order.id}`, {
    method: 'PUT', headers,
    body: JSON.stringify({ description: 'Changed note', items: [
      { productId: 1, quantity: 1, specifications: 'Extra hot',
        removedIngredientIds: [], parentIndex: null },
    ] }),
  });
  assert.equal(modifiedOrder.status, 200);
  const modified = await modifiedOrder.json() as {
    order: { id: number; status: string; removedItems: Array<{
      name: string; quantity: number;
    }>; items: Array<{
      id: number; deliveredQuantity: number; status: string;
    }> };
  };
  assert.equal(modified.order.status, 'waiting');
  assert.equal(modified.order.items[0].deliveredQuantity, 0);
  assert.equal(modified.order.removedItems[0].name, 'Visible soup');
  assert.equal(modified.order.removedItems[0].quantity, 2);
  assert.equal((database.prepare(
    "SELECT COUNT(*) AS count FROM order_modifications WHERE modification_type = 'update'",
  ).get() as { count: number }).count, 1);
  assert.equal(realtimeMessages.at(-1)?.type, 'room-orders-changed');

  const prematureEating = await app.request(`/rooms/1/orders/${order.order.id}/status`, {
    method: 'PATCH', headers, body: JSON.stringify({ status: 'eating' }),
  });
  assert.equal(prematureEating.status, 409);

  const prematureBilling = await app.request(`/rooms/1/orders/${order.order.id}/status`, {
    method: 'PATCH', headers, body: JSON.stringify({ status: 'closed' }),
  });
  assert.equal(prematureBilling.status, 409);
  assert.deepEqual(await prematureBilling.json(), {
    error: 'ORDER_NOT_READY_TO_BILL',
  });

  const delivered = await app.request(
    `/rooms/1/orders/${order.order.id}/items/${modified.order.items[0].id}/units/0/deliver`,
    { method: 'PATCH', headers },
  );
  assert.equal(delivered.status, 200);
  const deliveredOrder = await delivered.json() as {
    order: { status: string; items: Array<{
      deliveredQuantity: number; deliveredUnitIndexes: number[]; status: string;
    }> };
  };
  assert.equal(deliveredOrder.order.status, 'eating');
  assert.equal(deliveredOrder.order.items[0].deliveredQuantity, 1);
  assert.deepEqual(deliveredOrder.order.items[0].deliveredUnitIndexes, [0]);
  assert.equal(deliveredOrder.order.items[0].status, 'delivered');
  assert.equal((database.prepare('SELECT status FROM hall_tables WHERE id = 1').get() as
    { status: string }).status, 'eating');

  const undoneDelivery = await app.request(
    `/rooms/1/orders/${order.order.id}/items/${modified.order.items[0].id}/units/0/undo-delivery`,
    { method: 'PATCH', headers },
  );
  assert.equal(undoneDelivery.status, 200);
  const undoneOrder = await undoneDelivery.json() as {
    order: { status: string; items: Array<{ deliveredQuantity: number }> };
  };
  assert.equal(undoneOrder.order.status, 'waiting');
  assert.equal(undoneOrder.order.items[0].deliveredQuantity, 0);

  const redelivered = await app.request(
    `/rooms/1/orders/${order.order.id}/items/${modified.order.items[0].id}/units/0/deliver`,
    { method: 'PATCH', headers },
  );
  assert.equal(redelivered.status, 200);

  const todayAtTwo = new Date();
  todayAtTwo.setHours(2, 0, 0, 0);
  database.prepare('UPDATE orders SET created_at = ? WHERE id = ?')
    .run(todayAtTwo.toISOString(), order.order.id);
  const today = await app.request('/rooms/1/orders/today', { headers });
  assert.equal(today.status, 200);
  assert.equal((await today.json() as { orders: unknown[] }).orders.length, 1);
  assert.equal(realtimeMessages.at(-1)?.type, 'room-orders-changed');

  const addedItem = await app.request(`/rooms/1/orders/${order.order.id}`, {
    method: 'PUT', headers,
    body: JSON.stringify({ description: 'Changed note', items: [
      { productId: 1, quantity: 1, specifications: 'Extra hot',
        removedIngredientIds: [], parentIndex: null },
      { productId: 5, quantity: 1, specifications: 'Bring separately',
        removedIngredientIds: [], parentIndex: 0 },
    ] }),
  });
  assert.equal(addedItem.status, 200);
  const pendingAgain = await addedItem.json() as {
    order: { status: string; items: Array<{
      id: number; productId: number; status: string; deliveredQuantity: number;
    }> };
  };
  assert.equal(pendingAgain.order.status, 'waiting');
  assert.equal(pendingAgain.order.items.find(({ productId }) => productId === 1)?.status,
    'delivered');
  const newSpecial = pendingAgain.order.items.find(({ productId }) => productId === 5)!;
  assert.equal(newSpecial.deliveredQuantity, 0);
  assert.equal((database.prepare('SELECT status FROM hall_tables WHERE id = 1').get() as
    { status: string }).status, 'waiting');

  const deliveredAgain = await app.request(
    `/rooms/1/orders/${order.order.id}/items/${newSpecial.id}/units/0/deliver`,
    { method: 'PATCH', headers },
  );
  assert.equal(deliveredAgain.status, 200);
  assert.equal((await deliveredAgain.json() as { order: { status: string } })
    .order.status, 'eating');
  assert.equal((database.prepare('SELECT status FROM hall_tables WHERE id = 1').get() as
    { status: string }).status, 'eating');

  const updated = await app.request('/rooms/1/live-layout', {
    method: 'PUT',
    headers,
    body: JSON.stringify({
      tables: layout.tables.map((table) => ({
        id: table.id,
        x: table.id === 1 ? 130 : table.x,
        y: table.id === 1 ? 150 : table.y,
      })),
      groups: [{ tableIds: [1, 2] }],
    }),
  });
  assert.equal(updated.status, 200);
  assert.equal(realtimeMessages.at(-1)?.type, 'room-layout-changed');
  assert.equal(realtimeMessages.at(-1)?.roomId, 1);
  assert.deepEqual({ ...database.prepare(
    'SELECT x, y, width, height FROM hall_tables WHERE id = 1',
  ).get() }, { x: 130, y: 150, width: 100, height: 70 });
  assert.equal((database.prepare(
    'SELECT COUNT(*) AS count FROM table_group_members',
  ).get() as { count: number }).count, 2);
  const logicalOrder = database.prepare(
    `SELECT o.table_group_id AS groupId, g.status
     FROM orders o JOIN table_groups g ON g.id = o.table_group_id
     WHERE o.id = ?`,
  ).get(order.order.id) as { groupId: number; status: string };
  assert.equal(logicalOrder.status, 'eating');
  assert.deepEqual((database.prepare(
    'SELECT id, status FROM hall_tables WHERE id IN (1, 2) ORDER BY id',
  ).all() as Array<{ id: number; status: string }>).map((row) => ({ ...row })), [
    { id: 1, status: 'eating' },
    { id: 2, status: 'eating' },
  ]);
  assert.equal((database.prepare(
    "SELECT COUNT(*) AS count FROM activity_log WHERE type IN ('Pedido', 'Mesa', 'Mesas')",
  ).get() as { count: number }).count, 12);

  database.prepare(
    `INSERT INTO users (id, name, role, username, password_hash)
     VALUES (2, 'Administrator', 'admin', 'admin', 'unused')`,
  ).run();
  const adminToken = 'activity-token';
  database.prepare(
    `INSERT INTO admin_sessions (user_id, token_hash, created_at, expires_at)
     VALUES (2, ?, ?, ?)`,
  ).run(hash(adminToken), new Date().toISOString(),
    new Date(Date.now() + 60_000).toISOString());
  const activitiesApp = createAdminActivityRoutes({ database });
  const activitiesResponse = await activitiesApp.request('/activities', {
    headers: { authorization: `Bearer ${adminToken}` },
  });
  assert.equal(activitiesResponse.status, 200);
  const activities = await activitiesResponse.json() as {
    activities: Array<{ author: string; roomId: number }>;
  };
  assert.equal(activities.activities[0].author, 'Carlos Ruiz');
  assert.equal(activities.activities[0].roomId, 1);

  const otherDeviceApp = createDeviceApp({
    database,
    resolveClientIdentity: () => ({
      fingerprint: 'UNKNOWN',
      serialNumber: '02',
      certificatePem: 'other',
    }),
  });
  assert.equal((await otherDeviceApp.request('/rooms', { headers })).status, 401);
  roomRealtimeHub.disconnect(socket);
  database.close();
});
