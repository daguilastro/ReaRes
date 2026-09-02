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
    '\tUNIQUE ("menu_id", "name"),\n\tFOREIGN KEY ("menu_id") REFERENCES "menu"("id") ON DELETE CASCADE,',
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

  ensureCatalogSchema(database);
  database.prepare(
    `INSERT INTO menu_categories
       (menu_id, name, parent_category_id, is_special)
     VALUES (1, 'Premium', ?, 1)`,
  ).run(rootId);

  assert.equal((database.prepare(
    `SELECT is_special AS special FROM menu_categories WHERE name = 'Premium'`,
  ).get() as { special: number }).special, 1);
  assert.deepEqual(database.prepare('PRAGMA foreign_key_check').all(), []);
  database.close();
});
