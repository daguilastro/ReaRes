import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { insertComMenu } from '../../../../scripts/import-com-menu';

test('imports the photographed .COM catalog with nested sizes and peso values', () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));

  const result = insertComMenu(database);
  assert.deepEqual(result, {
    menuId: 1,
    categories: 18,
    products: 104,
    created: true,
  });
  assert.deepEqual({ ...database.prepare(
    `SELECT p.name, p.value, size.name AS size, family.name AS family
     FROM products p
     JOIN menu_categories size ON size.id = p.category_id
     JOIN menu_categories family ON family.id = size.parent_category_id
     WHERE p.name = 'Godzilla' AND size.name = 'Gigante (35 cm)'`,
  ).get() }, {
    name: 'Godzilla', value: 59100,
    size: 'Gigante (35 cm)', family: 'Especiales',
  });
  assert.deepEqual({ ...database.prepare(
    `SELECT p.name, p.value, category.name AS category
     FROM products p JOIN menu_categories category ON category.id = p.category_id
     WHERE p.name = 'Carne' AND category.name = 'Americano'`,
  ).get() }, { name: 'Carne', value: 20500, category: 'Americano' });
  assert.equal((database.prepare(
    'SELECT COUNT(*) AS count FROM product_ingredients',
  ).get() as { count: number }).count, 0);
  assert.equal((database.prepare(
    'SELECT COUNT(*) AS count FROM menu_halls',
  ).get() as { count: number }).count, 0);

  const secondRun = insertComMenu(database);
  assert.equal(secondRun.created, false);
  assert.equal(secondRun.products, 104);
  database.close();
});
