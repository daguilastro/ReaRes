import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createAdminLayoutRoutes } from '../../admin/routes/layout';
import { roomRealtimeHub, type RoomSocket } from '../../shared/roomRealtime';

test('saves and loads a complete room layout atomically for an admin', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  database.prepare(
    `INSERT INTO users (name, role, username, password_hash)
     VALUES ('Admin', 'admin', 'admin', 'unused')`,
  ).run();
  database.prepare("INSERT INTO hall (id, name) VALUES (1, 'Main Hall')").run();
  const token = 'layout-session';
  database.prepare(
    `INSERT INTO admin_sessions (user_id, token_hash, created_at, expires_at)
     VALUES (1, ?, ?, ?)`,
  ).run(createHash('sha256').update(token).digest('hex'), new Date().toISOString(),
    new Date(Date.now() + 60_000).toISOString());
  const app = createAdminLayoutRoutes({ database });
  const realtimeMessages: Array<Record<string, unknown>> = [];
  const socket = {
    readyState: 1,
    send: (value: string) => realtimeMessages.push(
      JSON.parse(value) as Record<string, unknown>,
    ),
    close: () => undefined,
  } satisfies RoomSocket;
  roomRealtimeHub.connect(socket, 99);
  roomRealtimeHub.subscribe(socket, 1);
  const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json' };
  const layout = {
    tables: [
      { id: -1, identifier: 'T-01', x: 100, y: 100, width: 120, height: 80, rotation: 0 },
      { id: -2, identifier: '2', x: 240, y: 100, width: 120, height: 80, rotation: .25 },
    ],
    walls: [
      { id: -1, x: 30, y: 30, width: 700, height: 10, rotation: 0 },
      { id: -2, x: 30, y: 30, width: 10, height: 500, rotation: 0 },
    ],
    groups: [{ id: -1, tableIds: [-1, -2] }],
  };

  assert.equal((await app.request('/rooms/1/layout', { method: 'PUT',
    headers: { 'content-type': 'application/json' }, body: JSON.stringify(layout) })).status, 401);
  const saved = await app.request('/rooms/1/layout', {
    method: 'PUT', headers, body: JSON.stringify(layout),
  });
  assert.equal(saved.status, 200);
  assert.equal(realtimeMessages.at(-1)?.type, 'room-layout-changed');
  assert.equal(realtimeMessages.at(-1)?.roomId, 1);
  const payload = await saved.json() as {
    tables: Array<{ id: number; identifier: string; rotation: number }>;
    walls: unknown[];
    groups: Array<{ identifier: string; tableIds: number[] }>;
  };
  assert.equal(payload.tables.length, 2);
  assert.equal(payload.walls.length, 2);
  assert.match(payload.groups[0].identifier, /^G-\d+$/);
  assert.equal(payload.tables[1].rotation, .25);
  assert.ok(payload.tables.every(({ id }) => id > 0));

  const invalid = structuredClone(payload) as any;
  invalid.tables[1].x = invalid.tables[0].x;
  const rejected = await app.request('/rooms/1/layout', {
    method: 'PUT', headers, body: JSON.stringify(invalid),
  });
  assert.equal(rejected.status, 422);
  const loaded = await (await app.request('/rooms/1/layout', { headers })).json() as {
    tables: Array<{ x: number }>;
  };
  assert.equal(loaded.tables[1].x, 240);

  const roomsResponse = await app.request('/rooms', { headers });
  assert.equal(roomsResponse.status, 200);
  const roomsPayload = await roomsResponse.json() as {
    rooms: Array<{ name: string; tableCount: number; orderCount: number; averageSale: number }>;
  };
  assert.deepEqual(roomsPayload.rooms[0], {
    id: 1, name: 'Main Hall', tableCount: 2, orderCount: 0,
    totalSales: 0, averageSale: 0,
  });
  const overviewResponse = await app.request(
    '/overview?period=day&range=7',
    { headers },
  );
  assert.equal(overviewResponse.status, 200);
  const overview = await overviewResponse.json() as {
    salesToday: number; ordersToday: number; averageTicket: number;
    points: Array<{ label: string; value: number }>;
  };
  assert.equal(overview.salesToday, 0);
  assert.equal(overview.ordersToday, 0);
  assert.equal(overview.averageTicket, 0);
  assert.equal(overview.points.length, 7);
  const createdRoom = await app.request('/rooms', {
    method: 'POST', headers, body: JSON.stringify({ name: 'Terraza' }),
  });
  assert.equal(createdRoom.status, 201);
  roomRealtimeHub.disconnect(socket);
  database.close();
});
