import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { Hono } from 'hono';
import { ensureCatalogSchema, openApplicationDatabase } from '../../shared/schemaMigration';

type Options = { database?: DatabaseSync };
type JsonObject = Record<string, unknown>;

const hashToken = (token: string) => createHash('sha256').update(token).digest('hex');

export function createAdminCatalogRoutes(options: Options = {}) {
  const routes = new Hono();
  let database = options.database;
  const db = () => {
    if (!database) database = openApplicationDatabase();
    else ensureCatalogSchema(database);
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

  routes.get('/catalog', (c) => c.json({
    menus: readMenus(db()),
    ingredients: readIngredients(db()),
    ingredientCategories: readIngredientCategories(db()),
  }));

  routes.post('/ingredient-categories', async (c) => {
    const body = await readJson(c);
    if (body instanceof Response) return body;
    const name = text(body.name, 2, 80);
    if (!name) return c.json({ error: 'INVALID_INGREDIENT_CATEGORY' }, 422);
    try {
      const result = db().prepare(
        'INSERT INTO ingredient_categories (name) VALUES (?)',
      ).run(name);
      return c.json({ category: {
        id: Number(result.lastInsertRowid), name, ingredients: [],
      } }, 201);
    } catch (error) {
      if (String(error).includes('UNIQUE constraint failed')) {
        return c.json({ error: 'INGREDIENT_CATEGORY_NAME_TAKEN' }, 409);
      }
      throw error;
    }
  });

  routes.post('/ingredients', async (c) => {
    const body = await readJson(c);
    if (body instanceof Response) return body;
    const name = text(body.name, 2, 80);
    const description = optionalText(body.description, 500);
    const categoryId = Number(body.categoryId);
    if (!name || description === undefined || !Number.isSafeInteger(categoryId) ||
        categoryId < 1 || !exists(db(), 'ingredient_categories', categoryId)) {
      return c.json({ error: 'INVALID_INGREDIENT' }, 422);
    }
    try {
      const result = db().prepare(
        'INSERT INTO ingredients (name, description, category_id) VALUES (?, ?, ?)',
      ).run(name, description, categoryId);
      return c.json({ ingredient: {
        id: Number(result.lastInsertRowid), name, description, categoryId,
      } }, 201);
    } catch (error) {
      if (String(error).includes('UNIQUE constraint failed')) {
        return c.json({ error: 'INGREDIENT_NAME_TAKEN' }, 409);
      }
      throw error;
    }
  });

  routes.post('/menus', async (c) => {
    const body = await readJson(c);
    if (body instanceof Response) return body;
    const name = text(body.name, 2, 80);
    const assignments = hallAssignments(body.hallAssignments);
    if (!name || !assignments ||
        !allExist(db(), 'hall', assignments.map(({ hallId }) => hallId))) {
      return c.json({ error: 'INVALID_MENU' }, 422);
    }
    const database = db();
    try {
      database.exec('BEGIN IMMEDIATE');
      const result = database.prepare('INSERT INTO menu (name) VALUES (?)').run(name);
      const menuId = Number(result.lastInsertRowid);
      const insertAssignment = database.prepare(
        'INSERT INTO menu_halls (menu_id, hall_id, is_primary) VALUES (?, ?, ?)',
      );
      for (const assignment of assignments) {
        insertAssignment.run(menuId, assignment.hallId, assignment.isPrimary ? 1 : 0);
      }
      database.exec('COMMIT');
      return c.json({ menu: readMenu(database, menuId) }, 201);
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      if (String(error).includes('UNIQUE constraint failed')) {
        if (String(error).includes('menu_halls.hall_id')) {
          return c.json({ error: 'PRIMARY_MENU_TAKEN' }, 409);
        }
        return c.json({ error: 'MENU_NAME_TAKEN' }, 409);
      }
      throw error;
    }
  });

  routes.post('/menus/:menuId/categories', async (c) => {
    const menuId = positiveId(c.req.param('menuId'));
    if (!menuId || !exists(db(), 'menu', menuId)) return c.json({ error: 'MENU_NOT_FOUND' }, 404);
    const body = await readJson(c);
    if (body instanceof Response) return body;
    const name = text(body.name, 2, 60);
    const parentCategoryId = body.parentCategoryId == null
      ? null : Number(body.parentCategoryId);
    let isSpecial = body.isSpecial === true;
    if (!name || (parentCategoryId !== null &&
        (!Number.isSafeInteger(parentCategoryId) || parentCategoryId < 1))) {
      return c.json({ error: 'INVALID_CATEGORY' }, 422);
    }
    if (parentCategoryId !== null) {
      const parent = db().prepare(
        `SELECT parent_category_id AS parentId, is_special AS isSpecial
         FROM menu_categories
         WHERE id = ? AND menu_id = ?`,
      ).get(parentCategoryId, menuId) as {
        parentId: number | null; isSpecial: number;
      } | undefined;
      if (!parent || parent.parentId !== null) {
        return c.json({ error: 'INVALID_PARENT_CATEGORY' }, 422);
      }
      isSpecial = parent.isSpecial === 1;
    }
    try {
      const result = db().prepare(
        `INSERT INTO menu_categories
         (menu_id, name, parent_category_id, is_special, position)
         VALUES (?, ?, ?, ?, COALESCE((
           SELECT MAX(position) + 1 FROM menu_categories
           WHERE menu_id = ? AND parent_category_id IS ?
         ), 0))`,
      ).run(menuId, name, parentCategoryId, isSpecial ? 1 : 0,
        menuId, parentCategoryId);
      return c.json({ category: { id: Number(result.lastInsertRowid), menuId,
        name, parentCategoryId, isSpecial, products: [], subcategories: [] } }, 201);
    } catch (error) {
      if (String(error).includes('UNIQUE constraint failed')) {
        return c.json({ error: 'CATEGORY_NAME_TAKEN' }, 409);
      }
      throw error;
    }
  });

  routes.put('/menus/:menuId/category-order', async (c) => {
    const menuId = positiveId(c.req.param('menuId'));
    if (!menuId || !exists(db(), 'menu', menuId)) {
      return c.json({ error: 'MENU_NOT_FOUND' }, 404);
    }
    const body = await readJson(c);
    if (body instanceof Response) return body;
    const parentCategoryId = body.parentCategoryId == null
      ? null : Number(body.parentCategoryId);
    if (parentCategoryId !== null &&
        (!Number.isSafeInteger(parentCategoryId) || parentCategoryId < 1)) {
      return c.json({ error: 'INVALID_CATEGORY_ORDER' }, 422);
    }
    const categoryIds = ids(body.categoryIds);
    const currentIds = (db().prepare(
      `SELECT id FROM menu_categories
       WHERE menu_id = ? AND parent_category_id IS ? ORDER BY id`,
    ).all(menuId, parentCategoryId) as Array<{ id: number }>).map(({ id }) => id);
    if (!categoryIds || categoryIds.length !== currentIds.length ||
        new Set(categoryIds).size !== categoryIds.length ||
        categoryIds.some((id) => !currentIds.includes(id))) {
      return c.json({ error: 'INVALID_CATEGORY_ORDER' }, 422);
    }
    const database = db();
    try {
      database.exec('BEGIN IMMEDIATE');
      const update = database.prepare(
        'UPDATE menu_categories SET position = ? WHERE id = ? AND menu_id = ?',
      );
      categoryIds.forEach((categoryId, position) => {
        update.run(position, categoryId, menuId);
      });
      database.exec('COMMIT');
      return c.json({ categoryIds });
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      throw error;
    }
  });

  routes.patch('/categories/:categoryId', async (c) => {
    const categoryId = positiveId(c.req.param('categoryId'));
    const current = categoryId ? db().prepare(
      'SELECT menu_id AS menuId FROM menu_categories WHERE id = ?',
    ).get(categoryId) as { menuId: number } | undefined : undefined;
    if (!categoryId || !current) {
      return c.json({ error: 'CATEGORY_NOT_FOUND' }, 404);
    }
    const body = await readJson(c);
    if (body instanceof Response) return body;
    const name = text(body.name, 2, 60);
    if (!name) return c.json({ error: 'INVALID_CATEGORY' }, 422);
    try {
      db().prepare('UPDATE menu_categories SET name = ? WHERE id = ?')
        .run(name, categoryId);
      return c.json({ category: { id: categoryId, menuId: current.menuId, name } });
    } catch (error) {
      if (String(error).includes('UNIQUE constraint failed')) {
        return c.json({ error: 'CATEGORY_NAME_TAKEN' }, 409);
      }
      throw error;
    }
  });

  routes.post('/menus/:menuId/products', async (c) => {
    const menuId = positiveId(c.req.param('menuId'));
    if (!menuId || !exists(db(), 'menu', menuId)) return c.json({ error: 'MENU_NOT_FOUND' }, 404);
    const body = await readJson(c);
    if (body instanceof Response) return body;
    const name = text(body.name, 2, 100);
    const description = optionalText(body.description, 1000);
    const value = body.value;
    const categoryId = Number(body.categoryId);
    const ingredientIds = ids(body.ingredientIds);
    const hallIds = ids(body.hallIds);
    if (!name || description === undefined || !Number.isSafeInteger(value) ||
        (value as number) < 0 || !Number.isSafeInteger(categoryId) || categoryId < 1 ||
        !ingredientIds || !hallIds || !allExist(db(), 'ingredients', ingredientIds)) {
      return c.json({ error: 'INVALID_PRODUCT' }, 422);
    }
    const category = db().prepare(
      'SELECT 1 FROM menu_categories WHERE id = ? AND menu_id = ?',
    ).get(categoryId, menuId);
    if (!category) return c.json({ error: 'INVALID_CATEGORY' }, 422);
    const secondaryHallIds = (db().prepare(
      'SELECT hall_id AS id FROM menu_halls WHERE menu_id = ? AND is_primary = 0',
    ).all(menuId) as Array<{ id: number }>).map(({ id }) => id);
    if (hallIds.some((id) => !secondaryHallIds.includes(id))) {
      return c.json({ error: 'INVALID_PRODUCT_HALLS' }, 422);
    }
    const database = db();
    try {
      database.exec('BEGIN IMMEDIATE');
      const result = database.prepare(
        `INSERT INTO products (name, description, value, menu_id, category_id)
         VALUES (?, ?, ?, ?, ?)`,
      ).run(name, description, value as number, menuId, categoryId);
      const productId = Number(result.lastInsertRowid);
      database.prepare(
        `INSERT INTO category_product_positions (category_id, product_id, position)
         VALUES (?, ?, COALESCE((
           SELECT MAX(position) + 1 FROM category_product_positions
           WHERE category_id = ?
         ), 0))`,
      ).run(categoryId, productId, categoryId);
      insertRelations(database, 'product_ingredients', 'product_id', productId,
        'ingredient_id', ingredientIds);
      insertRelations(database, 'product_halls', 'product_id', productId, 'hall_id', hallIds);
      database.exec('COMMIT');
      return c.json({ product: readProduct(database, productId) }, 201);
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      if (String(error).includes('UNIQUE constraint failed')) {
        return c.json({ error: 'PRODUCT_NAME_TAKEN' }, 409);
      }
      throw error;
    }
  });

  routes.patch('/products/:productId', async (c) => {
    const productId = positiveId(c.req.param('productId'));
    if (!productId) return c.json({ error: 'PRODUCT_NOT_FOUND' }, 404);
    const current = db().prepare(
      'SELECT id FROM products WHERE id = ? AND is_active = 1',
    ).get(productId);
    if (!current) return c.json({ error: 'PRODUCT_NOT_FOUND' }, 404);
    const body = await readJson(c);
    if (body instanceof Response) return body;
    const name = text(body.name, 2, 100);
    const description = optionalText(body.description, 1000);
    const value = body.value;
    const ingredientIds = ids(body.ingredientIds);
    const hallIds = ids(body.hallIds);
    if (!name || description === undefined || !Number.isSafeInteger(value) ||
        (value as number) < 0 || !ingredientIds || !hallIds ||
        !allExist(db(), 'ingredients', ingredientIds)) {
      return c.json({ error: 'INVALID_PRODUCT' }, 422);
    }
    const database = db();
    try {
      database.exec('BEGIN IMMEDIATE');
      database.prepare(
        'UPDATE products SET name = ?, description = ?, value = ? WHERE id = ?',
      ).run(name, description, value as number, productId);
      database.prepare('DELETE FROM product_ingredients WHERE product_id = ?')
        .run(productId);
      database.prepare('DELETE FROM product_halls WHERE product_id = ?')
        .run(productId);
      insertRelations(database, 'product_ingredients', 'product_id', productId,
        'ingredient_id', ingredientIds);
      insertRelations(database, 'product_halls', 'product_id', productId,
        'hall_id', hallIds);
      database.exec('COMMIT');
      return c.json({ product: readProduct(database, productId) });
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      throw error;
    }
  });

  routes.put('/categories/:categoryId/product-order', async (c) => {
    const categoryId = positiveId(c.req.param('categoryId'));
    if (!categoryId || !exists(db(), 'menu_categories', categoryId)) {
      return c.json({ error: 'CATEGORY_NOT_FOUND' }, 404);
    }
    const body = await readJson(c);
    if (body instanceof Response) return body;
    const productIds = ids(body.productIds);
    const currentIds = (db().prepare(
      `SELECT id FROM products
       WHERE category_id = ? AND is_active = 1 ORDER BY id`,
    ).all(categoryId) as Array<{ id: number }>).map(({ id }) => id);
    if (!productIds || productIds.length !== currentIds.length ||
        new Set(productIds).size !== productIds.length ||
        productIds.some((id) => !currentIds.includes(id))) {
      return c.json({ error: 'INVALID_PRODUCT_ORDER' }, 422);
    }
    const database = db();
    try {
      database.exec('BEGIN IMMEDIATE');
      database.prepare(
        'DELETE FROM category_product_positions WHERE category_id = ?',
      ).run(categoryId);
      const insert = database.prepare(
        `INSERT INTO category_product_positions
         (category_id, product_id, position) VALUES (?, ?, ?)`,
      );
      productIds.forEach((productId, position) => {
        insert.run(categoryId, productId, position);
      });
      database.exec('COMMIT');
      return c.json({ productIds });
    } catch (error) {
      try { database.exec('ROLLBACK'); } catch { /* Sin transacción activa. */ }
      throw error;
    }
  });

  routes.delete('/products/:productId', (c) => {
    const productId = positiveId(c.req.param('productId'));
    if (!productId) return c.json({ error: 'PRODUCT_NOT_FOUND' }, 404);
    const result = db().prepare(
      'UPDATE products SET is_active = 0 WHERE id = ? AND is_active = 1',
    ).run(productId);
    if (result.changes === 0) return c.json({ error: 'PRODUCT_NOT_FOUND' }, 404);
    return c.body(null, 204);
  });

  return routes;
}

function readMenus(database: DatabaseSync) {
  return (database.prepare('SELECT id FROM menu ORDER BY name COLLATE NOCASE').all() as
    Array<{ id: number }>).map(({ id }) => readMenu(database, id));
}

function readMenu(database: DatabaseSync, id: number) {
  const menu = database.prepare('SELECT id, name FROM menu WHERE id = ?').get(id) as
    { id: number; name: string };
  const hallAssignments = database.prepare(
    `SELECT hall_id AS hallId, is_primary AS isPrimary
     FROM menu_halls WHERE menu_id = ? ORDER BY hall_id`,
  ).all(id) as Array<{ hallId: number; isPrimary: number }>;
  const rows = database.prepare(
    `SELECT id, name, parent_category_id AS parentCategoryId,
            is_special AS isSpecial
     FROM menu_categories WHERE menu_id = ?
     ORDER BY parent_category_id IS NOT NULL, parent_category_id,
              position, name COLLATE NOCASE, id`,
  ).all(id) as Array<{
    id: number; name: string; parentCategoryId: number | null; isSpecial: number;
  }>;
  const category = (row: typeof rows[number]): Record<string, unknown> => ({
    id: row.id,
    name: row.name,
    menuId: id,
    parentCategoryId: row.parentCategoryId,
    isSpecial: row.isSpecial === 1,
    products: (database.prepare(
      `SELECT p.id FROM products p
       LEFT JOIN category_product_positions ordering
         ON ordering.category_id = p.category_id
        AND ordering.product_id = p.id
       WHERE p.category_id = ? AND p.is_active = 1
       ORDER BY ordering.position IS NULL, ordering.position,
                p.name COLLATE NOCASE, p.id`,
    ).all(row.id) as Array<{ id: number }>).map(({ id: productId }) =>
      readProduct(database, productId)),
    subcategories: row.parentCategoryId === null
      ? rows.filter((candidate) => candidate.parentCategoryId === row.id)
        .map((child) => category(child))
      : [],
  });
  const categories = rows.filter(({ parentCategoryId }) => parentCategoryId === null)
    .map(category);
  return { ...menu, hallAssignments: hallAssignments.map((assignment) => ({
    hallId: assignment.hallId, isPrimary: assignment.isPrimary === 1,
  })), categories };
}

function readProduct(database: DatabaseSync, id: number) {
  const product = database.prepare(
    `SELECT id, name, description, value, menu_id AS menuId,
            category_id AS categoryId, is_active AS isActive
     FROM products WHERE id = ?`,
  ).get(id) as JsonObject;
  return {
    ...product,
    isActive: product.isActive === 1,
    ingredientIds: relationIds(database, 'product_ingredients', 'product_id', id, 'ingredient_id'),
    hallIds: relationIds(database, 'product_halls', 'product_id', id, 'hall_id'),
  };
}

function readIngredients(database: DatabaseSync) {
  return database.prepare(
    `SELECT id, name, description, category_id AS categoryId
     FROM ingredients ORDER BY name COLLATE NOCASE`,
  ).all();
}

function readIngredientCategories(database: DatabaseSync) {
  return (database.prepare(
    'SELECT id, name FROM ingredient_categories ORDER BY name COLLATE NOCASE',
  ).all() as Array<{ id: number; name: string }>).map((category) => ({
    ...category,
    ingredients: database.prepare(
      `SELECT id, name, description, category_id AS categoryId
       FROM ingredients WHERE category_id = ? ORDER BY name COLLATE NOCASE`,
    ).all(category.id),
  }));
}

function relationIds(database: DatabaseSync, table: string, ownerColumn: string,
  ownerId: number, valueColumn: string) {
  return (database.prepare(
    `SELECT ${valueColumn} AS id FROM ${table} WHERE ${ownerColumn} = ? ORDER BY ${valueColumn}`,
  ).all(ownerId) as Array<{ id: number }>).map(({ id }) => id);
}

function insertRelations(database: DatabaseSync, table: string, ownerColumn: string,
  ownerId: number, valueColumn: string, values: number[]) {
  const insert = database.prepare(
    `INSERT INTO ${table} (${ownerColumn}, ${valueColumn}) VALUES (?, ?)`,
  );
  for (const value of values) insert.run(ownerId, value);
}

function exists(database: DatabaseSync, table: string, id: number) {
  return database.prepare(`SELECT 1 FROM ${table} WHERE id = ? LIMIT 1`).get(id) !== undefined;
}

function allExist(database: DatabaseSync, table: string, values: number[]) {
  if (values.length === 0) return true;
  const placeholders = values.map(() => '?').join(',');
  const row = database.prepare(
    `SELECT COUNT(*) AS count FROM ${table} WHERE id IN (${placeholders})`,
  ).get(...values) as { count: number };
  return row.count === values.length;
}

function positiveId(value: string) {
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : undefined;
}

function ids(value: unknown): number[] | undefined {
  if (value === undefined) return [];
  if (!Array.isArray(value) || value.some((id) => !Number.isSafeInteger(id) || id < 1)) {
    return undefined;
  }
  const unique = [...new Set(value as number[])];
  return unique.length === value.length ? unique : undefined;
}

function hallAssignments(value: unknown): Array<{
  hallId: number; isPrimary: boolean;
}> | undefined {
  if (value === undefined) return [];
  if (!Array.isArray(value)) return undefined;
  const result: Array<{ hallId: number; isPrimary: boolean }> = [];
  const seen = new Set<number>();
  for (const raw of value) {
    if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) return undefined;
    const item = raw as Record<string, unknown>;
    if (!Number.isSafeInteger(item.hallId) || (item.hallId as number) < 1 ||
        typeof item.isPrimary !== 'boolean' || seen.has(item.hallId as number)) {
      return undefined;
    }
    seen.add(item.hallId as number);
    result.push({ hallId: item.hallId as number, isPrimary: item.isPrimary });
  }
  return result;
}

function text(value: unknown, minimum: number, maximum: number) {
  if (typeof value !== 'string') return undefined;
  const result = value.trim();
  return result.length >= minimum && result.length <= maximum ? result : undefined;
}

function optionalText(value: unknown, maximum: number): string | null | undefined {
  if (value === undefined || value === null) return null;
  if (typeof value !== 'string') return undefined;
  const result = value.trim();
  return result.length <= maximum ? (result || null) : undefined;
}

async function readJson(c: any): Promise<JsonObject | Response> {
  try {
    const value: unknown = await c.req.json();
    if (typeof value !== 'object' || value === null || Array.isArray(value)) {
      return c.json({ error: 'INVALID_JSON' }, 400);
    }
    return value as JsonObject;
  } catch {
    return c.json({ error: 'INVALID_JSON' }, 400);
  }
}

export default createAdminCatalogRoutes();
