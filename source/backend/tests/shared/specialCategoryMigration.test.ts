import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';
import { DatabaseSync } from 'node:sqlite';
import { ensureCatalogSchema } from '../../shared/schemaMigration';

test('migrates legacy special roots and permits inherited special children', () => {
  const database = new DatabaseSync(':memory:');
  const currentSchema = readFileSync(
    join(process.cwd(), 'db', 'schheme.sql'),
    'utf8',
  );
  const legacySchema = currentSchema.replace(
    '\t"position" INTEGER NOT NULL DEFAULT 0 CHECK ("position" >= 0),\n' +
      '\tFOREIGN KEY ("menu_id") REFERENCES "menu"("id") ON DELETE CASCADE,',
    '\t"position" INTEGER NOT NULL DEFAULT 0 CHECK ("position" >= 0),\n' +
    '\tCHECK ("is_special" = 0 OR "parent_category_id" IS NULL),\n' +
      '\tUNIQUE ("menu_id", "name"),\n' +
      '\tFOREIGN KEY ("menu_id") REFERENCES "menu"("id") ON DELETE CASCADE,',
  );
  database.exec(legacySchema);
  database.prepare('INSERT INTO menu (name) VALUES (?)').run('Main');
  const rootId = Number(database.prepare(
    `INSERT INTO menu_categories (menu_id, name, is_special)
     VALUES (1, 'Additions', 1)`,
  ).run().lastInsertRowid);
  const productId = Number(database.prepare(
    `INSERT INTO products (name, value, menu_id, category_id)
     VALUES ('Sauce', 2000, 1, ?)`,
  ).run(rootId).lastInsertRowid);
  database.prepare(
    `INSERT INTO category_product_positions (category_id, product_id, position)
     VALUES (?, ?, 0)`,
  ).run(rootId, productId);

  ensureCatalogSchema(database);
  database.prepare(
    `INSERT INTO menu_categories
       (menu_id, name, parent_category_id, is_special)
     VALUES (1, 'Premium', ?, 1)`,
  ).run(rootId);
  database.prepare(
    `INSERT INTO menu_categories
       (menu_id, name, parent_category_id, is_special)
     VALUES (1, 'Additions', NULL, 1),
            (1, 'Additions', ?, 1)`,
  ).run(rootId);

  assert.equal((database.prepare(
    `SELECT is_special AS special FROM menu_categories WHERE name = 'Premium'`,
  ).get() as { special: number }).special, 1);
  assert.equal((database.prepare(
    `SELECT COUNT(*) AS count FROM menu_categories WHERE name = 'Additions'`,
  ).get() as { count: number }).count, 3);
  const preservedProduct = database.prepare(
    `SELECT p.id, p.category_id AS categoryId, ordering.position
     FROM products p
     JOIN category_product_positions ordering ON ordering.product_id = p.id
     WHERE p.id = ?`,
  ).get(productId) as { id: number; categoryId: number; position: number };
  assert.equal(preservedProduct.id, productId);
  assert.equal(preservedProduct.categoryId, rootId);
  assert.equal(preservedProduct.position, 0);
  assert.deepEqual(database.prepare('PRAGMA foreign_key_check').all(), []);
  database.close();
});
