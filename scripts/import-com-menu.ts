import { DatabaseSync } from 'node:sqlite';
import { openApplicationDatabase } from '../source/backend/shared/schemaMigration';

type ProductSeed = readonly [name: string, value: number];
type CategorySeed = {
  readonly name: string;
  readonly products?: readonly ProductSeed[];
  readonly children?: readonly CategorySeed[];
};

const sandwichSizes = (
  baby: readonly ProductSeed[],
  giant: readonly ProductSeed[],
): readonly CategorySeed[] => [
  { name: 'Bebé (20 cm)', products: baby },
  { name: 'Gigante (35 cm)', products: giant },
];

export const comMenuCatalog: readonly CategorySeed[] = [
  {
    name: 'Hamburguesa',
    products: [
      ['Corriente 1/4 de libra', 15900],
      ['Doble queso', 18000],
      ['Hawaiana', 19900],
      ['Tocineta', 19900],
      ['Pollo', 22300],
      ['Pollo y tocineta', 26900],
      ['Doble carne y queso', 27900],
      ['Bistec', 27900],
      ['Rex', 31500],
      ['Súper especial con todo', 31500],
      ['Doble carne, pollo y tocineta', 35900],
    ],
  },
  {
    name: 'Salchipapa',
    products: [
      ['Corriente', 20900],
      ['Americana', 24200],
      ['Especial', 45000],
      ['La Vecina', 50100],
      ['De mi tierra', 97900],
      ['De mi tierra XL', 151900],
    ],
  },
  {
    name: 'Perro',
    children: [
      {
        name: 'Americano',
        products: [
          ['Sencillo', 14400],
          ['Hawaiano', 15500],
          ['Champiñón', 19900],
          ['Pollo', 19900],
          ['Carne', 20500],
          ['Tocineta', 19700],
          ['Pollo champiñón', 22900],
          ['Carne y mazorca', 22900],
          ['Pollo y tocineta', 22900],
          ['Ranchero', 23800],
          ['Mexicano', 30000],
          ['Con todo', 29200],
        ],
      },
      {
        name: 'Anaconda',
        products: [
          ['Sencillo', 18300],
          ['Pollo champiñón', 29900],
          ['Carne y mazorca', 29900],
          ['Pollo y tocineta', 29900],
          ['Ranchero', 31900],
          ['Mexicano', 39700],
          ['Con todo', 44700],
        ],
      },
      {
        name: 'Chorizo',
        products: [
          ['Sencillo', 14400],
          ['Hawaiano', 15500],
          ['Champiñón', 19900],
          ['Pollo', 19900],
          ['Carne', 20500],
          ['Tocineta', 19700],
          ['Pollo champiñón', 22900],
          ['Carne y mazorca', 22900],
          ['Pollo y tocineta', 22900],
          ['Ranchero', 23800],
          ['Mexicano', 30000],
          ['Con todo', 29200],
        ],
      },
    ],
  },
  {
    name: 'Mazorcada',
    products: [
      ['Sencilla', 24900],
      ['Vegetariana', 25500],
      ['Mixta', 26900],
      ['La Nacional', 29900],
      ['Especial', 38400],
    ],
  },
  {
    name: 'Sandwich',
    children: [
      {
        name: 'Ligeros',
        children: sandwichSizes(
          [
            ['Hawaiano', 15900],
            ['Carne de hamburguesa', 16400],
            ['Pollo', 22100],
            ['Carne desmechada', 22500],
          ],
          [
            ['Hawaiano', 31000],
            ['Carne de hamburguesa', 28600],
            ['Pollo', 32000],
            ['Carne desmechada', 34000],
          ],
        ),
      },
      {
        name: 'Mixtos',
        children: sandwichSizes(
          [
            ['Pollo y tocineta', 21400],
            ['Pollo y champiñón', 23900],
            ['Carne y tocineta', 23400],
            ['Carne y pollo', 25000],
          ],
          [
            ['Pollo y tocineta', 34500],
            ['Pollo y champiñón', 36300],
            ['Carne y tocineta', 34500],
            ['Carne y pollo', 39400],
          ],
        ),
      },
      {
        name: 'Especiales',
        children: sandwichSizes(
          [
            ['Vegetariano', 22500],
            ['Criollo', 24600],
            ['Ranchero', 25500],
            ['Costeño', 25600],
            ['Mexicano', 29900],
            ['Colombiano', 28400],
            ['Súper especial', 29900],
            ['Monstruo', 31000],
            ['Godzilla', 31000],
          ],
          [
            ['Vegetariano', 35900],
            ['Criollo', 37300],
            ['Ranchero', 39300],
            ['Costeño', 40500],
            ['Mexicano', 48900],
            ['Colombiano', 52900],
            ['Súper especial', 53900],
            ['Monstruo', 53900],
            ['Godzilla', 59100],
          ],
        ),
      },
    ],
  },
  {
    name: 'Arepa',
    products: [
      ['Estortillada', 9900],
      ['Estrellada', 9900],
      ['Calienta huevos', 9900],
      ['Contenta', 10900],
      ['Solterona', 15900],
      ['Quinceañera', 19500],
      ['Veterana', 19900],
      ['Ardiente', 21900],
      ['Universitaria', 23500],
      ['Gomela', 20900],
      ['Ranchera', 23500],
      ["Pa'l marido", 22500],
      ['Colombiana', 25800],
      ['Mexicana', 25800],
      ["Pa'l mozo", 27800],
      ["Pa'l novio", 29900],
      ['La Vecina con todo', 29900],
    ],
  },
];

export type ComMenuImportResult = {
  menuId: number;
  categories: number;
  products: number;
  created: boolean;
};

export function insertComMenu(
  database: DatabaseSync,
  menuName = '.COM menu',
): ComMenuImportResult {
  const normalizedName = menuName.trim();
  if (!normalizedName) throw new Error('El nombre del menú no puede estar vacío.');
  const existing = database.prepare(
    'SELECT id FROM menu WHERE name = ? LIMIT 1',
  ).get(normalizedName) as { id: number } | undefined;
  if (existing) {
    const categories = Number((database.prepare(
      'SELECT COUNT(*) AS count FROM menu_categories WHERE menu_id = ?',
    ).get(existing.id) as { count: number }).count);
    const products = Number((database.prepare(
      'SELECT COUNT(*) AS count FROM products WHERE menu_id = ?',
    ).get(existing.id) as { count: number }).count);
    return { menuId: existing.id, categories, products, created: false };
  }

  const insertCategory = database.prepare(
    `INSERT INTO menu_categories
     (menu_id, name, parent_category_id, is_special, position)
     VALUES (?, ?, ?, 0, ?)`,
  );
  const insertProduct = database.prepare(
    `INSERT INTO products
     (name, description, value, menu_id, category_id, is_active)
     VALUES (?, NULL, ?, ?, ?, 1)`,
  );
  const insertProductPosition = database.prepare(
    `INSERT INTO category_product_positions
     (category_id, product_id, position) VALUES (?, ?, ?)`,
  );
  let categoryCount = 0;
  let productCount = 0;

  try {
    database.exec('BEGIN IMMEDIATE');
    const menuId = Number(database.prepare(
      'INSERT INTO menu (name) VALUES (?)',
    ).run(normalizedName).lastInsertRowid);

    const addCategories = (
      categories: readonly CategorySeed[],
      parentCategoryId: number | null,
    ) => {
      categories.forEach((category, categoryPosition) => {
        const categoryId = Number(insertCategory.run(
          menuId,
          category.name,
          parentCategoryId,
          categoryPosition,
        ).lastInsertRowid);
        categoryCount++;
        category.products?.forEach(([name, value], productPosition) => {
          const productId = Number(insertProduct.run(
            name,
            value,
            menuId,
            categoryId,
          ).lastInsertRowid);
          insertProductPosition.run(categoryId, productId, productPosition);
          productCount++;
        });
        if (category.children) addCategories(category.children, categoryId);
      });
    };

    addCategories(comMenuCatalog, null);
    database.exec('COMMIT');
    return {
      menuId,
      categories: categoryCount,
      products: productCount,
      created: true,
    };
  } catch (error) {
    try { database.exec('ROLLBACK'); } catch { /* No había transacción activa. */ }
    throw error;
  }
}

if (require.main === module) {
  const requestedName = process.argv.slice(2).join(' ').trim() || '.COM menu';
  const database = openApplicationDatabase();
  try {
    const result = insertComMenu(database, requestedName);
    if (!result.created) {
      console.log(
        `El menú "${requestedName}" ya existe; no se insertaron duplicados.`,
      );
    } else {
      console.log(`Menú "${requestedName}" creado correctamente.`);
    }
    console.log(`ID: ${result.menuId}`);
    console.log(`Categorías y subcategorías: ${result.categories}`);
    console.log(`Productos: ${result.products}`);
    console.log('El menú quedó sin salón asignado.');
  } finally {
    database.close();
  }
}
