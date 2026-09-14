import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { insertCatalogMenu } from '../../../../scripts/import-com-menu';
import { gourmetMenuCatalog } from '../../../../scripts/import-gourmet-menu';

test('imports the photographed Gourmet catalog with its special combos', () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));

  const result = insertCatalogMenu(database, gourmetMenuCatalog, 'Gourmet');
  assert.deepEqual(result, {
    menuId: 1,
    categories: 52,
    products: 233,
    created: true,
  });
  assert.deepEqual({ ...database.prepare(
    `SELECT p.value, size.name AS size, family.name AS family
     FROM products p
     JOIN menu_categories size ON size.id = p.category_id
     JOIN menu_categories family ON family.id = size.parent_category_id
     WHERE p.name = 'Monstruo' AND family.name = 'Gourmet'
       AND size.name = 'Large (60 cm)'`,
  ).get() }, { value: 84400, size: 'Large (60 cm)', family: 'Gourmet' });
  assert.deepEqual(database.prepare(
    `SELECT p.name, p.value FROM products p
     JOIN menu_categories category ON category.id = p.category_id
     WHERE category.name = 'Gigante (35 cm)'
     ORDER BY p.name`,
  ).all().map((row) => ({ ...row })), [
    { name: 'Godzilla', value: 59600 },
    { name: 'Monstruo', value: 54400 },
  ]);
  assert.equal((database.prepare(
    `SELECT COUNT(*) AS count FROM products p
     JOIN menu_categories category ON category.id = p.category_id
     WHERE category.name = 'Sencillo' AND category.is_special = 1
       AND p.value = 10300`,
  ).get() as { count: number }).count, 5);
  assert.equal((database.prepare(
    `SELECT COUNT(*) AS count FROM products p
     JOIN menu_categories category ON category.id = p.category_id
     WHERE category.name = 'Agrandado' AND category.is_special = 1
       AND p.value = 14000`,
  ).get() as { count: number }).count, 17);
  assert.equal((database.prepare(
    `SELECT COUNT(*) AS count FROM menu_categories
     WHERE name = 'Bebidas' AND is_special = 1`,
  ).get() as { count: number }).count, 1);
  assert.equal((database.prepare(
    `SELECT COUNT(*) AS count FROM products WHERE name LIKE '%del Valle%'`,
  ).get() as { count: number }).count, 0);
  assert.equal((database.prepare(
    'SELECT COUNT(*) AS count FROM menu_halls',
  ).get() as { count: number }).count, 0);

  const secondRun = insertCatalogMenu(database, gourmetMenuCatalog, 'Gourmet');
  assert.equal(secondRun.created, false);
  assert.equal(secondRun.products, 233);
  database.close();
});
