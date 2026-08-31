import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

type Column = { name: string; type: string };

function ensureSpecialCategoryConstraints(database: DatabaseSync): void {
  database.exec(`
    CREATE TRIGGER IF NOT EXISTS menu_categories_special_root_insert
    BEFORE INSERT ON menu_categories
    WHEN NEW.parent_category_id IS NOT NULL AND (
      NEW.is_special = 1 OR EXISTS (
        SELECT 1 FROM menu_categories parent
        WHERE parent.id = NEW.parent_category_id AND parent.is_special = 1
      )
    )
    BEGIN
      SELECT RAISE(ABORT, 'SPECIAL_CATEGORY_MUST_BE_ROOT');
    END;
    CREATE TRIGGER IF NOT EXISTS menu_categories_special_root_update
    BEFORE UPDATE OF parent_category_id, is_special ON menu_categories
    WHEN NEW.parent_category_id IS NOT NULL AND (
      NEW.is_special = 1 OR EXISTS (
        SELECT 1 FROM menu_categories parent
        WHERE parent.id = NEW.parent_category_id AND parent.is_special = 1
      )
    )
    BEGIN
      SELECT RAISE(ABORT, 'SPECIAL_CATEGORY_MUST_BE_ROOT');
    END;
  `);
}

function ensureSpecialOrderItemConstraints(database: DatabaseSync): void {
  database.exec(`
    CREATE INDEX IF NOT EXISTS order_items_parent_order_item_id_idx
      ON order_items(parent_order_item_id);
    CREATE TRIGGER IF NOT EXISTS order_items_special_parent_insert
    BEFORE INSERT ON order_items
    WHEN NEW.parent_order_item_id IS NOT NULL
    BEGIN
      SELECT CASE WHEN NOT EXISTS (
        SELECT 1 FROM order_items parent
        WHERE parent.id = NEW.parent_order_item_id
          AND parent.order_id = NEW.order_id
          AND EXISTS (
            SELECT 1 FROM products parent_product
            JOIN menu_categories parent_category
              ON parent_category.id = parent_product.category_id
            WHERE parent_product.id = parent.product_id
              AND parent_category.is_special = 0
          )
      ) OR NOT EXISTS (
        SELECT 1 FROM products child_product
        JOIN menu_categories child_category
          ON child_category.id = child_product.category_id
        WHERE child_product.id = NEW.product_id
          AND child_category.is_special = 1
      ) THEN RAISE(ABORT, 'INVALID_SPECIAL_PRODUCT_PARENT') END;
    END;
    CREATE TRIGGER IF NOT EXISTS order_items_special_requires_parent_insert
    BEFORE INSERT ON order_items
    WHEN NEW.parent_order_item_id IS NULL AND EXISTS (
      SELECT 1 FROM products product
      JOIN menu_categories category ON category.id = product.category_id
      WHERE product.id = NEW.product_id AND category.is_special = 1
    )
    BEGIN
      SELECT RAISE(ABORT, 'SPECIAL_PRODUCT_PARENT_REQUIRED');
    END;
    CREATE TRIGGER IF NOT EXISTS order_items_special_parent_update
    BEFORE UPDATE OF order_id, product_id, parent_order_item_id ON order_items
    WHEN NEW.parent_order_item_id IS NOT NULL
    BEGIN
      SELECT CASE WHEN NOT EXISTS (
        SELECT 1 FROM order_items parent
        WHERE parent.id = NEW.parent_order_item_id
          AND parent.order_id = NEW.order_id
          AND EXISTS (
            SELECT 1 FROM products parent_product
            JOIN menu_categories parent_category
              ON parent_category.id = parent_product.category_id
            WHERE parent_product.id = parent.product_id
              AND parent_category.is_special = 0
          )
      ) OR NOT EXISTS (
        SELECT 1 FROM products child_product
        JOIN menu_categories child_category
          ON child_category.id = child_product.category_id
        WHERE child_product.id = NEW.product_id
          AND child_category.is_special = 1
      ) THEN RAISE(ABORT, 'INVALID_SPECIAL_PRODUCT_PARENT') END;
    END;
    CREATE TRIGGER IF NOT EXISTS order_items_special_requires_parent_update
    BEFORE UPDATE OF product_id, parent_order_item_id ON order_items
    WHEN NEW.parent_order_item_id IS NULL AND EXISTS (
      SELECT 1 FROM products product
      JOIN menu_categories category ON category.id = product.category_id
      WHERE product.id = NEW.product_id AND category.is_special = 1
    )
    BEGIN
      SELECT RAISE(ABORT, 'SPECIAL_PRODUCT_PARENT_REQUIRED');
    END;
  `);
}

export function ensureLayoutSchema(database: DatabaseSync): void {
  const columns = database.prepare('PRAGMA table_info(hall_tables)').all() as Column[];
  if (columns.length > 0 && !columns.some(({ name }) => name === 'identifier')) {
    const legacyRows = database.prepare(
      'SELECT id, number, position, status, hall_id FROM hall_tables',
    ).all() as Array<{
      id: number; number: number | string; position: string; status: string; hall_id: number;
    }>;
    database.exec(`
      PRAGMA foreign_keys = OFF;
      BEGIN IMMEDIATE;
      CREATE TABLE hall_tables_layout_migration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        identifier TEXT NOT NULL,
        x REAL NOT NULL,
        y REAL NOT NULL,
        width REAL NOT NULL,
        height REAL NOT NULL,
        rotation REAL NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'available',
        hall_id INTEGER NOT NULL,
        UNIQUE (hall_id, identifier),
        FOREIGN KEY (hall_id) REFERENCES hall(id) ON DELETE CASCADE
      );
    `);
    try {
      const insert = database.prepare(
        `INSERT INTO hall_tables_layout_migration
         (id, identifier, x, y, width, height, rotation, status, hall_id)
         VALUES (?, ?, ?, ?, ?, ?, 0, ?, ?)`,
      );
      for (const row of legacyRows) {
        let position: Record<string, unknown> = {};
        try {
          const parsed: unknown = JSON.parse(row.position);
          if (typeof parsed === 'object' && parsed !== null) {
            position = parsed as Record<string, unknown>;
          }
        } catch { /* El formato antiguo no era estructurado. */ }
        const numberValue = (key: string, fallback: number) =>
          typeof position[key] === 'number' && Number.isFinite(position[key])
            ? position[key] as number
            : fallback;
        insert.run(row.id, String(row.number), numberValue('x', 100 + row.id * 20),
          numberValue('y', 100 + row.id * 20), numberValue('width', 120),
          numberValue('height', 80), row.status, row.hall_id);
      }
      database.exec(`
        DROP TABLE hall_tables;
        ALTER TABLE hall_tables_layout_migration RENAME TO hall_tables;
        COMMIT;
        PRAGMA foreign_keys = ON;
      `);
    } catch (error) {
      database.exec('ROLLBACK; PRAGMA foreign_keys = ON;');
      throw error;
    }
  }

  const currentColumns = database.prepare('PRAGMA table_info(hall_tables)').all() as Column[];
  if (currentColumns.length > 0 && !currentColumns.some(({ name }) => name === 'rotation')) {
    database.exec('ALTER TABLE hall_tables ADD COLUMN rotation REAL NOT NULL DEFAULT 0;');
  }

  database.exec(`
    CREATE TABLE IF NOT EXISTS hall_walls (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      hall_id INTEGER NOT NULL,
      x REAL NOT NULL, y REAL NOT NULL, width REAL NOT NULL, height REAL NOT NULL,
      rotation REAL NOT NULL DEFAULT 0,
      FOREIGN KEY (hall_id) REFERENCES hall(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS table_groups (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      hall_id INTEGER NOT NULL,
      visible_identifier TEXT NOT NULL,
      FOREIGN KEY (hall_id) REFERENCES hall(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS table_group_members (
      group_id INTEGER NOT NULL,
      table_id INTEGER NOT NULL UNIQUE,
      PRIMARY KEY (group_id, table_id),
      FOREIGN KEY (group_id) REFERENCES table_groups(id) ON DELETE CASCADE,
      FOREIGN KEY (table_id) REFERENCES hall_tables(id) ON DELETE CASCADE
    );
  `);

  const groupColumns = database.prepare('PRAGMA table_info(table_groups)').all() as Column[];
  if (groupColumns.length > 0 && !groupColumns.some(({ name }) => name === 'status')) {
    database.exec(
      "ALTER TABLE table_groups ADD COLUMN status TEXT NOT NULL DEFAULT 'available' CHECK (status IN ('available', 'waiting', 'eating'));",
    );
  }
  if (groupColumns.length > 0 && !groupColumns.some(({ name }) => name === 'created_at')) {
    database.exec('ALTER TABLE table_groups ADD COLUMN created_at DATETIME;');
    database.exec('UPDATE table_groups SET created_at = CURRENT_TIMESTAMP WHERE created_at IS NULL;');
  }
}

export function ensureCatalogSchema(database: DatabaseSync): void {
  const menuColumns = database.prepare('PRAGMA table_info(menu)').all() as Column[];
  const productColumns = database.prepare('PRAGMA table_info(products)').all() as Column[];
  const legacyMenu = menuColumns.some(({ name }) => name === 'hall_id');
  const legacyProducts = productColumns.length > 0 &&
    (!productColumns.some(({ name }) => name === 'category_id') ||
      !productColumns.some(({ name }) => name === 'description'));

  if (legacyMenu || legacyProducts) {
    database.exec(`
      PRAGMA foreign_keys = OFF;
      BEGIN IMMEDIATE;
      CREATE TEMP TABLE legacy_menu_halls AS
        SELECT id AS menu_id, hall_id
        FROM menu WHERE hall_id IS NOT NULL;
      CREATE TABLE menu_catalog_migration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE
      );
      INSERT INTO menu_catalog_migration (id, name)
        SELECT id, 'Menu ' || id FROM menu;
      CREATE TABLE menu_categories_migration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        menu_id INTEGER NOT NULL,
        name TEXT NOT NULL,
        UNIQUE (menu_id, name),
        FOREIGN KEY (menu_id) REFERENCES menu_catalog_migration(id) ON DELETE CASCADE
      );
      INSERT INTO menu_categories_migration (menu_id, name)
        SELECT id, 'General' FROM menu_catalog_migration;
      CREATE TABLE products_catalog_migration (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        description TEXT,
        value INTEGER NOT NULL CHECK (value >= 0),
        menu_id INTEGER NOT NULL,
        category_id INTEGER NOT NULL,
        UNIQUE (menu_id, name),
        FOREIGN KEY (menu_id) REFERENCES menu_catalog_migration(id) ON DELETE CASCADE,
        FOREIGN KEY (category_id) REFERENCES menu_categories_migration(id) ON DELETE RESTRICT
      );
      INSERT INTO products_catalog_migration
        (id, name, description, value, menu_id, category_id)
        SELECT p.id, p.name, NULL, p.value, p.menu_id, c.id
        FROM products p
        JOIN menu_categories_migration c ON c.menu_id = p.menu_id;
      CREATE TABLE product_ingredients_catalog_migration (
        product_id INTEGER NOT NULL,
        ingredient_id INTEGER NOT NULL,
        PRIMARY KEY (product_id, ingredient_id),
        FOREIGN KEY (product_id) REFERENCES products_catalog_migration(id) ON DELETE CASCADE,
        FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE RESTRICT
      );
      INSERT OR IGNORE INTO product_ingredients_catalog_migration
        (product_id, ingredient_id)
        SELECT product_id, ingredient_id FROM product_ingredients;
      DROP TABLE product_ingredients;
      DROP TABLE products;
      DROP TABLE IF EXISTS product_halls;
      DROP TABLE IF EXISTS menu_halls;
      DROP TABLE IF EXISTS menu_categories;
      DROP TABLE menu;
      ALTER TABLE menu_catalog_migration RENAME TO menu;
      ALTER TABLE menu_categories_migration RENAME TO menu_categories;
      ALTER TABLE products_catalog_migration RENAME TO products;
      ALTER TABLE product_ingredients_catalog_migration RENAME TO product_ingredients;
      CREATE TABLE menu_halls (
        menu_id INTEGER NOT NULL,
        hall_id INTEGER NOT NULL,
        is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
        PRIMARY KEY (menu_id, hall_id),
        FOREIGN KEY (menu_id) REFERENCES menu(id) ON DELETE CASCADE,
        FOREIGN KEY (hall_id) REFERENCES hall(id) ON DELETE CASCADE
      );
      INSERT OR IGNORE INTO menu_halls (menu_id, hall_id)
        SELECT menu_id, hall_id FROM legacy_menu_halls;
      DROP TABLE legacy_menu_halls;
      COMMIT;
      PRAGMA foreign_keys = ON;
    `);
  }

  const menuHallColumns = database.prepare('PRAGMA table_info(menu_halls)').all() as Column[];
  if (menuHallColumns.length > 0 && !menuHallColumns.some(({ name }) => name === 'is_primary')) {
    database.exec(
      'ALTER TABLE menu_halls ADD COLUMN is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1));',
    );
    database.exec(`
      UPDATE menu_halls AS target SET is_primary = 1
      WHERE target.menu_id = (
        SELECT MIN(candidate.menu_id) FROM menu_halls candidate
        WHERE candidate.hall_id = target.hall_id
      );
    `);
  }

  const categoryColumns = database.prepare('PRAGMA table_info(menu_categories)').all() as Column[];
  if (categoryColumns.length > 0 &&
      !categoryColumns.some(({ name }) => name === 'parent_category_id')) {
    database.exec('ALTER TABLE menu_categories ADD COLUMN parent_category_id INTEGER REFERENCES menu_categories(id) ON DELETE CASCADE;');
  }
  if (categoryColumns.length > 0 && !categoryColumns.some(({ name }) => name === 'is_special')) {
    database.exec('ALTER TABLE menu_categories ADD COLUMN is_special INTEGER NOT NULL DEFAULT 0 CHECK (is_special IN (0, 1));');
  }

  database.exec(`
    CREATE TABLE IF NOT EXISTS ingredient_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE
    );
  `);
  const ingredientColumns = database.prepare('PRAGMA table_info(ingredients)').all() as Column[];
  if (ingredientColumns.length > 0 &&
      !ingredientColumns.some(({ name }) => name === 'category_id')) {
    const result = database.prepare(
      "INSERT OR IGNORE INTO ingredient_categories (name) VALUES ('Uncategorized')",
    ).run();
    const fallback = result.lastInsertRowid || (database.prepare(
      "SELECT id FROM ingredient_categories WHERE name = 'Uncategorized'",
    ).get() as { id: number }).id;
    database.exec('ALTER TABLE ingredients ADD COLUMN category_id INTEGER REFERENCES ingredient_categories(id) ON DELETE RESTRICT;');
    database.prepare('UPDATE ingredients SET category_id = ? WHERE category_id IS NULL').run(fallback);
  }

  database.exec(`
    CREATE TABLE IF NOT EXISTS menu_halls (
      menu_id INTEGER NOT NULL,
      hall_id INTEGER NOT NULL,
      is_primary INTEGER NOT NULL DEFAULT 0 CHECK (is_primary IN (0, 1)),
      PRIMARY KEY (menu_id, hall_id),
      FOREIGN KEY (menu_id) REFERENCES menu(id) ON DELETE CASCADE,
      FOREIGN KEY (hall_id) REFERENCES hall(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS menu_categories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      menu_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      UNIQUE (menu_id, name),
      FOREIGN KEY (menu_id) REFERENCES menu(id) ON DELETE CASCADE
    );
    CREATE TABLE IF NOT EXISTS product_halls (
      product_id INTEGER NOT NULL,
      hall_id INTEGER NOT NULL,
      PRIMARY KEY (product_id, hall_id),
      FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE,
      FOREIGN KEY (hall_id) REFERENCES hall(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS menu_halls_hall_id_idx ON menu_halls(hall_id);
    CREATE UNIQUE INDEX IF NOT EXISTS menu_halls_one_primary_per_hall_idx
      ON menu_halls(hall_id) WHERE is_primary = 1;
    CREATE INDEX IF NOT EXISTS menu_categories_menu_id_idx ON menu_categories(menu_id);
    CREATE INDEX IF NOT EXISTS products_category_id_idx ON products(category_id);
    CREATE INDEX IF NOT EXISTS product_halls_hall_id_idx ON product_halls(hall_id);
    CREATE INDEX IF NOT EXISTS ingredients_category_id_idx ON ingredients(category_id);
  `);
  ensureSpecialCategoryConstraints(database);
}

export function ensureOrderSchema(database: DatabaseSync): void {
  const orderColumns = database.prepare('PRAGMA table_info(orders)').all() as Column[];
  if (orderColumns.length > 0 && !orderColumns.some(({ name }) => name === 'status')) {
    database.exec(
      "ALTER TABLE orders ADD COLUMN status TEXT NOT NULL DEFAULT 'waiting' CHECK (status IN ('waiting', 'eating', 'closed'));",
    );
  }
  if (orderColumns.length > 0 && !orderColumns.some(({ name }) => name === 'updated_at')) {
    database.exec('ALTER TABLE orders ADD COLUMN updated_at DATETIME;');
    database.exec('UPDATE orders SET updated_at = created_at WHERE updated_at IS NULL;');
  }
  if (orderColumns.length > 0 && !orderColumns.some(({ name }) => name === 'table_group_id')) {
    database.exec(
      'ALTER TABLE orders ADD COLUMN table_group_id INTEGER REFERENCES table_groups(id) ON DELETE SET NULL;',
    );
  }
  const itemColumns = database.prepare('PRAGMA table_info(order_items)').all() as Column[];
  if (itemColumns.length > 0 && !itemColumns.some(({ name }) => name === 'quantity')) {
    database.exec('ALTER TABLE order_items ADD COLUMN quantity INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0);');
  }
  if (itemColumns.length > 0 &&
      !itemColumns.some(({ name }) => name === 'delivered_quantity')) {
    database.exec(
      'ALTER TABLE order_items ADD COLUMN delivered_quantity INTEGER NOT NULL DEFAULT 0 CHECK (delivered_quantity >= 0 AND delivered_quantity <= quantity);',
    );
    database.exec(
      "UPDATE order_items SET delivered_quantity = quantity WHERE status = 'delivered';",
    );
  }
  if (itemColumns.length > 0 &&
      !itemColumns.some(({ name }) => name === 'parent_order_item_id')) {
    database.exec('ALTER TABLE order_items ADD COLUMN parent_order_item_id INTEGER REFERENCES order_items(id) ON DELETE CASCADE;');
  }
  database.exec(`
    CREATE TABLE IF NOT EXISTS order_item_deliveries (
      order_item_id INTEGER NOT NULL,
      unit_index INTEGER NOT NULL CHECK (unit_index >= 0),
      delivered_at DATETIME NOT NULL,
      delivered_by INTEGER,
      PRIMARY KEY (order_item_id, unit_index),
      FOREIGN KEY (order_item_id) REFERENCES order_items(id) ON DELETE CASCADE,
      FOREIGN KEY (delivered_by) REFERENCES users(id) ON DELETE SET NULL
    );
    WITH RECURSIVE delivered_units(order_item_id, unit_index, quantity) AS (
      SELECT id, 0, quantity FROM order_items
      WHERE status = 'delivered' AND quantity > 0
      UNION ALL
      SELECT order_item_id, unit_index + 1, quantity FROM delivered_units
      WHERE unit_index + 1 < quantity
    )
    INSERT OR IGNORE INTO order_item_deliveries
      (order_item_id, unit_index, delivered_at, delivered_by)
      SELECT order_item_id, unit_index, CURRENT_TIMESTAMP, NULL
      FROM delivered_units;
    CREATE TABLE IF NOT EXISTS order_item_removed_ingredients (
      order_item_id INTEGER NOT NULL,
      ingredient_id INTEGER NOT NULL,
      PRIMARY KEY (order_item_id, ingredient_id),
      FOREIGN KEY (order_item_id) REFERENCES order_items(id) ON DELETE CASCADE,
      FOREIGN KEY (ingredient_id) REFERENCES ingredients(id) ON DELETE RESTRICT
    );
    CREATE TABLE IF NOT EXISTS removed_order_items (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id INTEGER NOT NULL,
      product_name TEXT NOT NULL,
      product_description TEXT,
      unit_value INTEGER NOT NULL,
      quantity INTEGER NOT NULL CHECK (quantity > 0),
      specifications TEXT,
      parent_product_name TEXT,
      removed_at DATETIME NOT NULL,
      FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS orders_table_status_idx ON orders(table_id, status);
    CREATE INDEX IF NOT EXISTS orders_table_group_status_idx
      ON orders(table_group_id, status);
    CREATE INDEX IF NOT EXISTS order_items_order_id_idx ON order_items(order_id);
    CREATE TABLE IF NOT EXISTS activity_log (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      author_id INTEGER,
      hall_id INTEGER,
      type TEXT NOT NULL,
      modification TEXT NOT NULL,
      created_at DATETIME NOT NULL,
      FOREIGN KEY (author_id) REFERENCES users(id) ON DELETE SET NULL,
      FOREIGN KEY (hall_id) REFERENCES hall(id) ON DELETE CASCADE
    );
    CREATE INDEX IF NOT EXISTS activity_log_created_at_idx
      ON activity_log(created_at DESC);
  `);
  ensureSpecialOrderItemConstraints(database);
}

export function openApplicationDatabase(): DatabaseSync {
  const database = new DatabaseSync(join(process.cwd(), 'db', 'restaurant.sqlite'));
  database.exec('PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  ensureLayoutSchema(database);
  ensureCatalogSchema(database);
  ensureOrderSchema(database);
  return database;
}
