import { DatabaseSync } from 'node:sqlite';

export type LogicalGroupInput = {
  id?: number;
  identifier?: string;
  tableIds: number[];
};

type ActiveOrder = {
  id: number;
  tableId: number;
  tableGroupId: number | null;
  status: 'waiting' | 'eating';
};

export function persistLogicalGroups(
  database: DatabaseSync,
  roomId: number,
  groups: LogicalGroupInput[],
  modifierId?: number,
) {
  const existing = database.prepare(
    'SELECT id FROM table_groups WHERE hall_id = ?',
  ).all(roomId) as Array<{ id: number }>;
  const existingIds = new Set(existing.map(({ id }) => id));
  const retained = new Set<number>();
  const resolved: Array<{ id: number; identifier: string; tableIds: number[] }> = [];

  for (const group of groups) {
    let groupId: number;
    let identifier = group.identifier?.trim() || '';
    if (group.id !== undefined && group.id > 0 && existingIds.has(group.id)) {
      groupId = group.id;
      if (!identifier) identifier = automaticIdentifier(database, group.tableIds);
      database.prepare(
        'UPDATE table_groups SET visible_identifier = ? WHERE id = ? AND hall_id = ?',
      ).run(identifier, groupId, roomId);
      database.prepare('DELETE FROM table_group_members WHERE group_id = ?').run(groupId);
    } else {
      const result = database.prepare(
        `INSERT INTO table_groups
         (hall_id, visible_identifier, status, created_at)
         VALUES (?, 'pending', 'available', ?)`,
      ).run(roomId, new Date().toISOString());
      groupId = Number(result.lastInsertRowid);
      if (!identifier) identifier = automaticIdentifier(database, group.tableIds);
      database.prepare(
        'UPDATE table_groups SET visible_identifier = ? WHERE id = ?',
      ).run(identifier, groupId);
    }
    retained.add(groupId);
    const insertMember = database.prepare(
      'INSERT INTO table_group_members (group_id, table_id) VALUES (?, ?)',
    );
    for (const tableId of group.tableIds) insertMember.run(groupId, tableId);
    bindOrdersToLogicalGroup(database, groupId, group.tableIds, modifierId);
    resolved.push({ id: groupId, identifier, tableIds: group.tableIds });
  }

  for (const { id } of existing) {
    if (retained.has(id)) continue;
    releaseLogicalGroup(database, id);
    database.prepare('DELETE FROM table_groups WHERE id = ?').run(id);
  }
  return resolved;
}

function bindOrdersToLogicalGroup(
  database: DatabaseSync,
  groupId: number,
  tableIds: number[],
  modifierId?: number,
) {
  const placeholders = tableIds.map(() => '?').join(',');
  const orders = database.prepare(
    `SELECT id, table_id AS tableId, table_group_id AS tableGroupId, status
     FROM orders
     WHERE status != 'closed' AND
       (table_id IN (${placeholders}) OR table_group_id = ?)
     ORDER BY created_at, id`,
  ).all(...tableIds, groupId) as ActiveOrder[];
  if (orders.length === 0) {
    database.prepare(
      "UPDATE table_groups SET status = 'available' WHERE id = ?",
    ).run(groupId);
    return;
  }

  const canonical = orders[0];
  const status = orders.some((order) => order.status === 'eating')
    ? 'eating'
    : 'waiting';
  for (const duplicate of orders.slice(1)) {
    database.prepare('UPDATE order_items SET order_id = ? WHERE order_id = ?')
      .run(canonical.id, duplicate.id);
    database.prepare(
      'UPDATE order_modifications SET order_id = ? WHERE order_id = ?',
    ).run(canonical.id, duplicate.id);
    database.prepare('DELETE FROM orders WHERE id = ?').run(duplicate.id);
  }
  const representative = Math.min(...tableIds);
  database.prepare(
    `UPDATE orders SET table_id = ?, table_group_id = ?, status = ?, updated_at = ?
     WHERE id = ?`,
  ).run(representative, groupId, status, new Date().toISOString(), canonical.id);
  database.prepare('UPDATE table_groups SET status = ? WHERE id = ?')
    .run(status, groupId);
  updateMemberStatuses(database, groupId, status);

  if (modifierId !== undefined &&
      (orders.length > 1 || canonical.tableGroupId !== groupId)) {
    database.prepare(
      `INSERT INTO order_modifications
       (order_id, order_item_id, modifier_id, modification_type,
        old_value, new_value, created_at)
       VALUES (?, NULL, ?, 'group', ?, ?, ?)`,
    ).run(canonical.id, modifierId,
      JSON.stringify({ tableIds: orders.map(({ tableId }) => tableId) }),
      JSON.stringify({ tableGroupId: groupId, tableIds }),
      new Date().toISOString());
  }
}

function releaseLogicalGroup(database: DatabaseSync, groupId: number) {
  const members = database.prepare(
    'SELECT table_id AS tableId FROM table_group_members WHERE group_id = ?',
  ).all(groupId) as Array<{ tableId: number }>;
  const order = database.prepare(
    `SELECT id, table_id AS tableId, status FROM orders
     WHERE table_group_id = ? AND status != 'closed' LIMIT 1`,
  ).get(groupId) as { id: number; tableId: number; status: string } | undefined;
  if (order) {
    database.prepare(
      'UPDATE orders SET table_group_id = NULL, updated_at = ? WHERE id = ?',
    ).run(new Date().toISOString(), order.id);
  }
  for (const { tableId } of members) {
    const ownOrder = database.prepare(
      `SELECT status FROM orders
       WHERE table_id = ? AND table_group_id IS NULL AND status != 'closed'
       ORDER BY created_at LIMIT 1`,
    ).get(tableId) as { status: string } | undefined;
    database.prepare('UPDATE hall_tables SET status = ? WHERE id = ?')
      .run(ownOrder?.status ?? 'available', tableId);
  }
}

export function updateLogicalTargetStatus(
  database: DatabaseSync,
  tableId: number,
  groupId: number | null,
  status: string,
) {
  if (groupId === null) {
    database.prepare('UPDATE hall_tables SET status = ? WHERE id = ?')
      .run(status, tableId);
    return;
  }
  database.prepare('UPDATE table_groups SET status = ? WHERE id = ?')
    .run(status, groupId);
  updateMemberStatuses(database, groupId, status);
}

function updateMemberStatuses(
  database: DatabaseSync,
  groupId: number,
  status: string,
) {
  database.prepare(
    `UPDATE hall_tables SET status = ? WHERE id IN (
       SELECT table_id FROM table_group_members WHERE group_id = ?
     )`,
  ).run(status, groupId);
}

function automaticIdentifier(database: DatabaseSync, tableIds: number[]) {
  const identifier = database.prepare(
    `SELECT group_concat(identifier, ' + ') AS identifier
     FROM (SELECT identifier FROM hall_tables
           WHERE id IN (${tableIds.map(() => '?').join(',')}) ORDER BY id)`,
  ).get(...tableIds) as { identifier: string | null };
  return identifier.identifier ?? tableIds.join(' + ');
}
