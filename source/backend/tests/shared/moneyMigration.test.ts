import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { ensurePesoValueMigration } from '../../shared/schemaMigration';

test('normalizes legacy values with two extra zeros exactly once', () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  database.exec(`
    INSERT INTO menu (id, name) VALUES (1, 'Menu');
    INSERT INTO menu_categories (id, menu_id, name) VALUES (1, 1, 'Food');
    INSERT INTO products (id, name, value, menu_id, category_id)
      VALUES (1, 'Carne', 2050000, 1, 1);
  `);

  ensurePesoValueMigration(database);
  ensurePesoValueMigration(database);

  database.exec(`
    INSERT INTO products (id, name, value, menu_id, category_id)
      VALUES (2, 'Nuevo', 14000, 1, 1);
  `);
  ensurePesoValueMigration(database);

  assert.equal(
    (database.prepare('SELECT value FROM products WHERE id = 1').get() as
      { value: number }).value,
    20500,
  );
  assert.equal(
    (database.prepare('SELECT value FROM products WHERE id = 2').get() as
      { value: number }).value,
    14000,
  );
  assert.equal(
    (database.prepare(
      `SELECT COUNT(*) AS count FROM schema_migrations
       WHERE name = '2026-08-normalize-product-values-to-pesos'`,
    ).get() as { count: number }).count,
    1,
  );
  database.close();
});
