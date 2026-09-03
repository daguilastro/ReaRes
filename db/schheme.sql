CREATE TABLE IF NOT EXISTS "schema_migrations" (
	"name" TEXT PRIMARY KEY,
	"applied_at" DATETIME NOT NULL
);

CREATE TABLE IF NOT EXISTS "users" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"name" TEXT NOT NULL,
	"role" TEXT NOT NULL,
	"username" TEXT NOT NULL UNIQUE,
	"password_hash" TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS "admin_sessions" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"user_id" INTEGER NOT NULL,
	"token_hash" TEXT NOT NULL UNIQUE,
	"created_at" DATETIME NOT NULL,
	"expires_at" DATETIME NOT NULL,
	FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "admin_sessions_expires_at_idx"
	ON "admin_sessions"("expires_at");

CREATE TABLE IF NOT EXISTS "device_pairing_requests" (
	"id" TEXT PRIMARY KEY,
	"secret_hash" TEXT NOT NULL,
	"created_at" DATETIME NOT NULL,
	"expires_at" DATETIME NOT NULL,
	"used_at" DATETIME
);

CREATE INDEX IF NOT EXISTS "device_pairing_requests_expires_at_idx"
	ON "device_pairing_requests"("expires_at");

CREATE TABLE IF NOT EXISTS "paired_devices" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"name" TEXT NOT NULL,
	"certificate_fingerprint" TEXT NOT NULL UNIQUE,
	"certificate_serial" TEXT NOT NULL,
	"certificate_pem" TEXT NOT NULL,
	"paired_at" DATETIME NOT NULL,
	"revoked_at" DATETIME
);

CREATE TABLE IF NOT EXISTS "employee_sessions" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"user_id" INTEGER NOT NULL,
	"device_id" INTEGER NOT NULL,
	"token_hash" TEXT NOT NULL UNIQUE,
	"created_at" DATETIME NOT NULL,
	"expires_at" DATETIME NOT NULL,
	FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
	FOREIGN KEY ("device_id") REFERENCES "paired_devices"("id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "employee_sessions_expires_at_idx"
	ON "employee_sessions"("expires_at");

CREATE TABLE IF NOT EXISTS "hall_tables" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"identifier" TEXT NOT NULL,
	"x" REAL NOT NULL,
	"y" REAL NOT NULL,
	"width" REAL NOT NULL,
	"height" REAL NOT NULL,
	"rotation" REAL NOT NULL DEFAULT 0,
	"status" TEXT NOT NULL DEFAULT 'available',
	"hall_id" INTEGER NOT NULL,
	UNIQUE ("hall_id", "identifier"),
	FOREIGN KEY ("hall_id") REFERENCES "hall"("id")
	ON UPDATE NO ACTION ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "hall_walls" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"hall_id" INTEGER NOT NULL,
	"x" REAL NOT NULL,
	"y" REAL NOT NULL,
	"width" REAL NOT NULL,
	"height" REAL NOT NULL,
	"rotation" REAL NOT NULL DEFAULT 0,
	FOREIGN KEY ("hall_id") REFERENCES "hall"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "table_groups" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"hall_id" INTEGER NOT NULL,
	"visible_identifier" TEXT NOT NULL,
	"status" TEXT NOT NULL DEFAULT 'available' CHECK ("status" IN ('available', 'waiting', 'eating')),
	"created_at" DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
	FOREIGN KEY ("hall_id") REFERENCES "hall"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "table_group_members" (
	"group_id" INTEGER NOT NULL,
	"table_id" INTEGER NOT NULL UNIQUE,
	PRIMARY KEY ("group_id", "table_id"),
	FOREIGN KEY ("group_id") REFERENCES "table_groups"("id") ON DELETE CASCADE,
	FOREIGN KEY ("table_id") REFERENCES "hall_tables"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "ingredient_categories" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"name" TEXT NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS "ingredients" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"name" TEXT NOT NULL,
	"description" TEXT,
	"category_id" INTEGER NOT NULL,
	UNIQUE ("name"),
	FOREIGN KEY ("category_id") REFERENCES "ingredient_categories"("id") ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS "menu" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"name" TEXT NOT NULL,
	UNIQUE ("name")
);

CREATE TABLE IF NOT EXISTS "menu_halls" (
	"menu_id" INTEGER NOT NULL,
	"hall_id" INTEGER NOT NULL,
	"is_primary" INTEGER NOT NULL DEFAULT 0 CHECK ("is_primary" IN (0, 1)),
	PRIMARY KEY ("menu_id", "hall_id"),
	FOREIGN KEY ("menu_id") REFERENCES "menu"("id") ON DELETE CASCADE,
	FOREIGN KEY ("hall_id") REFERENCES "hall"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "menu_categories" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"menu_id" INTEGER NOT NULL,
	"name" TEXT NOT NULL,
	"parent_category_id" INTEGER,
	"is_special" INTEGER NOT NULL DEFAULT 0 CHECK ("is_special" IN (0, 1)),
	"position" INTEGER NOT NULL DEFAULT 0 CHECK ("position" >= 0),
	UNIQUE ("menu_id", "name"),
	FOREIGN KEY ("menu_id") REFERENCES "menu"("id") ON DELETE CASCADE,
	FOREIGN KEY ("parent_category_id") REFERENCES "menu_categories"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "products" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"name" TEXT NOT NULL,
	"description" TEXT,
	"value" INTEGER NOT NULL CHECK ("value" >= 0),
	"menu_id" INTEGER NOT NULL,
	"category_id" INTEGER NOT NULL,
	"is_active" INTEGER NOT NULL DEFAULT 1 CHECK ("is_active" IN (0, 1)),
	FOREIGN KEY ("menu_id") REFERENCES "menu"("id") ON DELETE CASCADE,
	FOREIGN KEY ("category_id") REFERENCES "menu_categories"("id") ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS "category_product_positions" (
	"category_id" INTEGER NOT NULL,
	"product_id" INTEGER NOT NULL,
	"position" INTEGER NOT NULL CHECK ("position" >= 0),
	PRIMARY KEY ("category_id", "product_id"),
	UNIQUE ("category_id", "position"),
	FOREIGN KEY ("category_id") REFERENCES "menu_categories"("id") ON DELETE CASCADE,
	FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "product_halls" (
	"product_id" INTEGER NOT NULL,
	"hall_id" INTEGER NOT NULL,
	PRIMARY KEY ("product_id", "hall_id"),
	FOREIGN KEY ("product_id") REFERENCES "products"("id") ON DELETE CASCADE,
	FOREIGN KEY ("hall_id") REFERENCES "hall"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "orders" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"author_id" INTEGER NOT NULL,
	"table_id" INTEGER,
	"table_group_id" INTEGER,
	"hall_id" INTEGER,
	"external_name" TEXT,
	"description" TEXT,
	"receiver" TEXT,
	"status" TEXT NOT NULL DEFAULT 'waiting' CHECK ("status" IN ('waiting', 'eating', 'closed')),
	"created_at" DATETIME NOT NULL,
	"updated_at" DATETIME NOT NULL,
	CHECK (("external_name" IS NULL AND "table_id" IS NOT NULL)
		OR ("external_name" IS NOT NULL AND "table_id" IS NULL
			AND "table_group_id" IS NULL AND "hall_id" IS NOT NULL)),
	FOREIGN KEY ("author_id") REFERENCES "users"("id")
	ON UPDATE NO ACTION ON DELETE NO ACTION,
	FOREIGN KEY ("table_id") REFERENCES "hall_tables"("id")
	ON UPDATE NO ACTION ON DELETE NO ACTION,
	FOREIGN KEY ("table_group_id") REFERENCES "table_groups"("id")
	ON UPDATE NO ACTION ON DELETE SET NULL,
	FOREIGN KEY ("hall_id") REFERENCES "hall"("id") ON DELETE NO ACTION
);

CREATE TABLE IF NOT EXISTS "order_items" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"order_id" INTEGER NOT NULL,
	"product_id" INTEGER NOT NULL,
	"quantity" INTEGER NOT NULL DEFAULT 1 CHECK ("quantity" > 0),
	"delivered_quantity" INTEGER NOT NULL DEFAULT 0
		CHECK ("delivered_quantity" >= 0 AND "delivered_quantity" <= "quantity"),
	"specifications" TEXT,
	"parent_order_item_id" INTEGER,
	"status" TEXT NOT NULL DEFAULT 'ordered'
		CHECK ("status" IN ('ordered', 'delivered')),
	FOREIGN KEY ("order_id") REFERENCES "orders"("id")
	ON UPDATE NO ACTION ON DELETE NO ACTION,
	FOREIGN KEY ("product_id") REFERENCES "products"("id")
	ON UPDATE NO ACTION ON DELETE NO ACTION,
	FOREIGN KEY ("parent_order_item_id") REFERENCES "order_items"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "order_item_deliveries" (
	"order_item_id" INTEGER NOT NULL,
	"unit_index" INTEGER NOT NULL CHECK ("unit_index" >= 0),
	"delivered_at" DATETIME NOT NULL,
	"delivered_by" INTEGER,
	PRIMARY KEY ("order_item_id", "unit_index"),
	FOREIGN KEY ("order_item_id") REFERENCES "order_items"("id") ON DELETE CASCADE,
	FOREIGN KEY ("delivered_by") REFERENCES "users"("id") ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS "order_item_removed_ingredients" (
	"order_item_id" INTEGER NOT NULL,
	"ingredient_id" INTEGER NOT NULL,
	PRIMARY KEY ("order_item_id", "ingredient_id"),
	FOREIGN KEY ("order_item_id") REFERENCES "order_items"("id") ON DELETE CASCADE,
	FOREIGN KEY ("ingredient_id") REFERENCES "ingredients"("id") ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS "removed_order_items" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"order_id" INTEGER NOT NULL,
	"product_name" TEXT NOT NULL,
	"category_name" TEXT,
	"product_description" TEXT,
	"unit_value" INTEGER NOT NULL,
	"quantity" INTEGER NOT NULL CHECK ("quantity" > 0),
	"specifications" TEXT,
	"parent_product_name" TEXT,
	"removed_at" DATETIME NOT NULL,
	FOREIGN KEY ("order_id") REFERENCES "orders"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "product_ingredients" (
	"product_id" INTEGER NOT NULL,
	"ingredient_id" INTEGER NOT NULL,
	PRIMARY KEY ("product_id", "ingredient_id"),
	FOREIGN KEY ("product_id") REFERENCES "products"("id")
	ON UPDATE NO ACTION ON DELETE CASCADE,
	FOREIGN KEY ("ingredient_id") REFERENCES "ingredients"("id")
	ON UPDATE NO ACTION ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS "order_modifications" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"order_id" INTEGER NOT NULL,
	"order_item_id" INTEGER,
	"modifier_id" INTEGER NOT NULL,
	"modification_type" TEXT NOT NULL,
	"old_value" TEXT,
	"new_value" TEXT,
	"created_at" DATETIME NOT NULL,
	FOREIGN KEY ("order_id") REFERENCES "orders"("id")
	ON UPDATE NO ACTION ON DELETE NO ACTION,
	FOREIGN KEY ("order_item_id") REFERENCES "order_items"("id")
	ON UPDATE NO ACTION ON DELETE NO ACTION,
	FOREIGN KEY ("modifier_id") REFERENCES "users"("id")
	ON UPDATE NO ACTION ON DELETE NO ACTION
);

CREATE TABLE IF NOT EXISTS "activity_log" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"author_id" INTEGER,
	"hall_id" INTEGER,
	"type" TEXT NOT NULL,
	"modification" TEXT NOT NULL,
	"created_at" DATETIME NOT NULL,
	FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE SET NULL,
	FOREIGN KEY ("hall_id") REFERENCES "hall"("id") ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS "hall" (
	"id" INTEGER PRIMARY KEY AUTOINCREMENT,
	"name" TEXT NOT NULL,
	UNIQUE ("name")
);

CREATE TABLE IF NOT EXISTS "employee_halls" (
	"user_id" INTEGER NOT NULL,
	"hall_id" INTEGER NOT NULL,
	PRIMARY KEY ("user_id", "hall_id"),
	FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE,
	FOREIGN KEY ("hall_id") REFERENCES "hall"("id") ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS "employee_halls_hall_id_idx"
	ON "employee_halls"("hall_id");

CREATE INDEX IF NOT EXISTS "order_items_parent_order_item_id_idx"
	ON "order_items"("parent_order_item_id");

CREATE TRIGGER IF NOT EXISTS "menu_categories_special_root_insert"
BEFORE INSERT ON "menu_categories"
WHEN NEW."parent_category_id" IS NOT NULL AND NOT EXISTS (
	SELECT 1 FROM "menu_categories" AS parent
	WHERE parent."id" = NEW."parent_category_id"
	  AND parent."menu_id" = NEW."menu_id"
	  AND parent."is_special" = NEW."is_special"
)
BEGIN
	SELECT RAISE(ABORT, 'INVALID_PARENT_CATEGORY');
END;

CREATE TRIGGER IF NOT EXISTS "menu_categories_special_root_update"
BEFORE UPDATE OF "parent_category_id", "is_special" ON "menu_categories"
WHEN (NEW."parent_category_id" IS NOT NULL AND NOT EXISTS (
	SELECT 1 FROM "menu_categories" AS parent
	WHERE parent."id" = NEW."parent_category_id"
	  AND parent."menu_id" = NEW."menu_id"
	  AND parent."is_special" = NEW."is_special"
)) OR NEW."parent_category_id" = NEW."id" OR NEW."parent_category_id" IN (
	WITH RECURSIVE descendants("id") AS (
		SELECT "id" FROM "menu_categories" WHERE "parent_category_id" = OLD."id"
		UNION ALL
		SELECT child."id" FROM "menu_categories" AS child
		JOIN descendants ON child."parent_category_id" = descendants."id"
	)
	SELECT "id" FROM descendants
) OR EXISTS (
	SELECT 1 FROM "menu_categories" AS child
	WHERE child."parent_category_id" = OLD."id"
	  AND (child."menu_id" != NEW."menu_id"
	       OR child."is_special" != NEW."is_special")
)
BEGIN
	SELECT RAISE(ABORT, 'INVALID_PARENT_CATEGORY');
END;

CREATE TRIGGER IF NOT EXISTS "order_items_special_parent_insert"
BEFORE INSERT ON "order_items"
WHEN NEW."parent_order_item_id" IS NOT NULL
BEGIN
	SELECT CASE WHEN NOT EXISTS (
		SELECT 1 FROM "order_items" AS parent
		WHERE parent."id" = NEW."parent_order_item_id"
		  AND parent."order_id" = NEW."order_id"
		  AND EXISTS (
			SELECT 1 FROM "products" AS parent_product
			JOIN "menu_categories" AS parent_category
			  ON parent_category."id" = parent_product."category_id"
			WHERE parent_product."id" = parent."product_id"
			  AND parent_category."is_special" = 0
		  )
	) OR NOT EXISTS (
		SELECT 1 FROM "products" AS child_product
		JOIN "menu_categories" AS child_category
		  ON child_category."id" = child_product."category_id"
		WHERE child_product."id" = NEW."product_id"
		  AND child_category."is_special" = 1
	)
	THEN RAISE(ABORT, 'INVALID_SPECIAL_PRODUCT_PARENT') END;
END;

CREATE TRIGGER IF NOT EXISTS "order_items_special_parent_update"
BEFORE UPDATE OF "order_id", "product_id", "parent_order_item_id" ON "order_items"
WHEN NEW."parent_order_item_id" IS NOT NULL
BEGIN
	SELECT CASE WHEN NOT EXISTS (
		SELECT 1 FROM "order_items" AS parent
		WHERE parent."id" = NEW."parent_order_item_id"
		  AND parent."order_id" = NEW."order_id"
		  AND EXISTS (
			SELECT 1 FROM "products" AS parent_product
			JOIN "menu_categories" AS parent_category
			  ON parent_category."id" = parent_product."category_id"
			WHERE parent_product."id" = parent."product_id"
			  AND parent_category."is_special" = 0
		  )
	) OR NOT EXISTS (
		SELECT 1 FROM "products" AS child_product
		JOIN "menu_categories" AS child_category
		  ON child_category."id" = child_product."category_id"
		WHERE child_product."id" = NEW."product_id"
		  AND child_category."is_special" = 1
	)
	THEN RAISE(ABORT, 'INVALID_SPECIAL_PRODUCT_PARENT') END;
END;
