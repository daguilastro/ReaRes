import { rows } from '../shared/http';

type OrderBase = {
  id: number; tableId: number | null; tableGroupId: number | null;
  externalName: string | null; hallId: number; authorId: number;
  description: string | null; status: string; paymentMethod: string | null;
  createdAt: string; updatedAt: string; tableLabel: string;
};

type OrderItemRow = Record<string, unknown> & {
  id: number;
  productId: number;
  unitValue: number;
  quantity: number;
  deliveredQuantity: number;
  specifications: string | null;
  parentOrderItemId: number | null;
  name: string;
  categoryName: string;
  productDescription: string | null;
};

export async function readOrder(database: D1Database, orderId: number) {
  const order = await database.prepare(
    `SELECT o.id, o.table_id AS tableId, o.table_group_id AS tableGroupId,
            o.external_name AS externalName,
            COALESCE(o.hall_id, t.hall_id) AS hallId,
            o.author_id AS authorId, o.description, o.status,
            o.payment_method AS paymentMethod, o.created_at AS createdAt,
            o.updated_at AS updatedAt,
            COALESCE(o.external_name, g.visible_identifier, t.identifier) AS tableLabel
     FROM orders o
     LEFT JOIN hall_tables t ON t.id = o.table_id
     LEFT JOIN table_groups g ON g.id = o.table_group_id
     WHERE o.id = ?`,
  ).bind(orderId).first<OrderBase>();
  if (!order) return undefined;

  const items = await rows<OrderItemRow>(
    database.prepare(
      `WITH RECURSIVE category_paths(id, path) AS (
         SELECT id, name FROM menu_categories WHERE parent_category_id IS NULL
         UNION ALL
         SELECT child.id, category_paths.path || ' › ' || child.name
         FROM menu_categories child
         JOIN category_paths ON child.parent_category_id = category_paths.id
       )
       SELECT oi.id, oi.product_id AS productId, p.name,
              category_paths.path AS categoryName,
              p.description AS productDescription,
              COALESCE(oi.unit_value, p.value) AS unitValue,
              oi.quantity, oi.delivered_quantity AS deliveredQuantity,
              oi.specifications, oi.parent_order_item_id AS parentOrderItemId,
              oi.status
       FROM order_items oi
       JOIN products p ON p.id = oi.product_id
       JOIN category_paths ON category_paths.id = p.category_id
       WHERE oi.order_id = ? ORDER BY oi.id`,
    ).bind(orderId),
  );
  const ids = items.map((item) => item.id);
  const productIds = [...new Set(items.map((item) => item.productId))];
  const placeholders = ids.map(() => '?').join(',');
  const productPlaceholders = productIds.map(() => '?').join(',');
  const [deliveries, removedIngredients, ingredients, removedItems] = await Promise.all([
    ids.length === 0 ? [] : rows<{ itemId: number; unitIndex: number }>(database.prepare(
      `SELECT order_item_id AS itemId, unit_index AS unitIndex
       FROM order_item_deliveries WHERE order_item_id IN (${placeholders})
       ORDER BY order_item_id, unit_index`,
    ).bind(...ids)),
    ids.length === 0 ? [] : rows<{ itemId: number; ingredientId: number }>(database.prepare(
      `SELECT order_item_id AS itemId, ingredient_id AS ingredientId
       FROM order_item_removed_ingredients WHERE order_item_id IN (${placeholders})
       ORDER BY order_item_id, ingredient_id`,
    ).bind(...ids)),
    productIds.length === 0 ? [] : rows<{ productId: number; id: number; name: string }>(
      database.prepare(
        `SELECT pi.product_id AS productId, i.id, i.name
         FROM product_ingredients pi JOIN ingredients i ON i.id = pi.ingredient_id
         WHERE pi.product_id IN (${productPlaceholders})
         ORDER BY pi.product_id, i.name COLLATE NOCASE`,
      ).bind(...productIds),
    ),
    rows(database.prepare(
      `SELECT id, product_name AS name, category_name AS categoryName,
              product_description AS productDescription, unit_value AS unitValue,
              quantity, specifications, parent_product_name AS parentProductName,
              removed_at AS removedAt
       FROM removed_order_items WHERE order_id = ? ORDER BY id`,
    ).bind(orderId)),
  ]);
  const enriched = items.map((item) => ({
    ...item,
    deliveredUnitIndexes: deliveries.filter((row) => row.itemId === item.id)
      .map((row) => row.unitIndex),
    removedIngredientIds: removedIngredients.filter((row) => row.itemId === item.id)
      .map((row) => row.ingredientId),
    ingredients: ingredients.filter((row) => row.productId === item.productId)
      .map(({ id, name }) => ({ id, name })),
  }));
  return {
    ...order,
    total: enriched.reduce(
      (sum, item) => sum + Number(item.unitValue) * Number(item.quantity), 0,
    ),
    removedItems,
    items: enriched,
  };
}

export async function readHallOrders(database: D1Database, hallId: number,
  closed = false, from?: string, to?: string, paymentMethod?: string) {
  const clauses = [
    'COALESCE(o.hall_id, t.hall_id) = ?',
    closed ? "o.status = 'closed'" : "o.status != 'closed'",
  ];
  const bindings: Array<string | number> = [hallId];
  if (from && to) {
    clauses.push('o.updated_at >= ?', 'o.updated_at < ?');
    bindings.push(from, to);
  }
  if (paymentMethod) {
    clauses.push('o.payment_method = ?');
    bindings.push(paymentMethod);
  }
  const ids = await rows<{ id: number }>(database.prepare(
    `SELECT o.id FROM orders o LEFT JOIN hall_tables t ON t.id = o.table_id
     WHERE ${clauses.join(' AND ')}
     ORDER BY ${closed ? 'o.updated_at DESC' : 'o.created_at, o.id'}`,
  ).bind(...bindings));
  return Promise.all(ids.map((row) => readOrder(database, row.id)));
}

export async function tableLabel(database: D1Database, tableId: number | null,
  groupId: number | null, externalName?: string | null) {
  if (externalName) return externalName;
  if (groupId !== null) {
    const group = await database.prepare(
      'SELECT visible_identifier AS label FROM table_groups WHERE id = ?',
    ).bind(groupId).first<{ label: string }>();
    if (group?.label) return group.label;
  }
  const table = tableId === null ? null : await database.prepare(
    'SELECT identifier AS label FROM hall_tables WHERE id = ?',
  ).bind(tableId).first<{ label: string }>();
  return table?.label ?? String(tableId ?? 'Pedido externo');
}
