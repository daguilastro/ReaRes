import { DatabaseSync } from 'node:sqlite';
import { openApplicationDatabase } from '../source/backend/shared/schemaMigration';

type ProductSeed = readonly [name: string, value: number];
type CategorySeed = {
  readonly name: string;
  readonly special?: boolean;
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
  {
    name: 'Combo',
    special: true,
    children: [
      {
        name: 'Sencillo',
        special: true,
        products: [
          ['Combo sencillo · Limonada 12 oz', 8500],
          ['Combo sencillo · Coca-Cola mini', 8500],
          ['Combo sencillo · Quatro mini', 8500],
          ['Combo sencillo · Coca-Cola Zero mini', 8500],
          ['Combo sencillo · Sprite mini', 8500],
        ],
      },
      {
        name: 'Agrandado',
        special: true,
        products: [
          ['Combo agrandado · Fuze Tea durazno', 12500],
          ['Combo agrandado · Fuze Tea mango', 12500],
          ['Combo agrandado · Fuze Tea manzanilla', 12500],
          ['Combo agrandado · Fuze Tea limón', 12500],
          ['Combo agrandado · Fuze Tea manzana', 12500],
          ['Combo agrandado · Coca-Cola personal', 12500],
          ['Combo agrandado · Quatro personal', 12500],
          ['Combo agrandado · Coca-Cola Zero personal', 12500],
          ['Combo agrandado · Sprite personal', 12500],
          ['Combo agrandado · Jugo del Valle mango', 12500],
          ['Combo agrandado · Jugo del Valle naranja', 12500],
          ['Combo agrandado · Jugo del Valle mora', 12500],
          ['Combo agrandado · Agua con gas', 12500],
          ['Combo agrandado · Agua sin gas', 12500],
          ['Combo agrandado · Cerveza Águila', 12500],
          ['Combo agrandado · Cerveza Póker', 12500],
          ['Combo agrandado · Cerveza Cola y Pola', 12500],
          ['Combo agrandado · Limonada 16 oz', 12500],
        ],
      },
    ],
  },
  {
    name: 'Bebida',
    special: true,
    children: [
      {
        name: 'Gaseosa',
        special: true,
        products: [['Coca-Cola 1.5 L', 10800]],
        children: [
          {
            name: 'Personal',
            special: true,
            products: [
              ['Coca-Cola', 5800],
              ['Quatro', 5800],
              ['Coca-Cola Zero', 5800],
              ['Sprite', 5800],
            ],
          },
          {
            name: 'Mini',
            special: true,
            products: [
              ['Coca-Cola', 3500],
              ['Quatro', 3500],
              ['Coca-Cola Zero', 3500],
              ['Sprite', 3500],
            ],
          },
          {
            name: 'Mediana',
            special: true,
            products: [['Coca-Cola', 7900]],
          },
        ],
      },
      {
        name: 'Limonada',
        special: true,
        products: [
          ['Limonada 12 oz', 3500],
          ['Limonada 16 oz', 7900],
        ],
      },
      {
        name: 'Fuze Tea',
        special: true,
        products: [
          ['Durazno', 5800],
          ['Mango', 5800],
          ['Manzanilla', 5800],
          ['Limón', 5800],
          ['Manzana', 5800],
        ],
      },
      {
        name: 'Jugo del Valle',
        special: true,
        products: [
          ['Mango', 5800],
          ['Naranja', 5800],
          ['Mora', 5800],
        ],
      },
      {
        name: 'Agua',
        special: true,
        products: [
          ['Con gas', 5800],
          ['Sin gas', 5800],
        ],
      },
      {
        name: 'Cerveza',
        special: true,
        products: [
          ['Águila', 6000],
          ['Póker', 6000],
          ['Cola y Pola', 6000],
        ],
      },
    ],
  },
  {
    name: 'Adición',
    special: true,
    products: [
      ['Papa francesa', 8500],
      ['Papa criolla', 8500],
      ['Huevos de codorniz', 12500],
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

  const insertCategory = database.prepare(
    `INSERT INTO menu_categories
     (menu_id, name, parent_category_id, is_special, position)
     VALUES (?, ?, ?, ?, ?)`,
  );
  const insertProduct = database.prepare(
    `INSERT INTO products
     (name, description, value, menu_id, category_id, is_active)
     VALUES (?, NULL, ?, ?, ?, 1)`,
  );
  const insertProductPosition = database.prepare(
    `INSERT INTO category_product_positions
     (category_id, product_id, position)
     VALUES (?, ?, COALESCE((
       SELECT MAX(position) + 1 FROM category_product_positions
       WHERE category_id = ?
     ), 0))`,
  );
  let categoryCount = 0;
  let productCount = 0;

  try {
    database.exec('BEGIN IMMEDIATE');
    const menuId = existing?.id ?? Number(database.prepare(
      'INSERT INTO menu (name) VALUES (?)',
    ).run(normalizedName).lastInsertRowid);

    const addCategories = (
      categories: readonly CategorySeed[],
      parentCategoryId: number | null,
    ) => {
      categories.forEach((category, categoryPosition) => {
        const existingCategory = database.prepare(
          `SELECT id FROM menu_categories
           WHERE menu_id = ? AND name = ?
             AND parent_category_id IS ? AND is_special = ?
           ORDER BY id LIMIT 1`,
        ).get(
          menuId,
          category.name,
          parentCategoryId,
          category.special ? 1 : 0,
        ) as { id: number } | undefined;
        const categoryId = existingCategory?.id ?? Number(insertCategory.run(
          menuId,
          category.name,
          parentCategoryId,
          category.special ? 1 : 0,
          categoryPosition,
        ).lastInsertRowid);
        category.products?.forEach(([name, value]) => {
          const existingProduct = database.prepare(
            `SELECT id FROM products
             WHERE menu_id = ? AND category_id = ? AND name = ?
             ORDER BY id LIMIT 1`,
          ).get(menuId, categoryId, name) as { id: number } | undefined;
          if (!existingProduct) {
            const productId = Number(insertProduct.run(
              name,
              value,
              menuId,
              categoryId,
            ).lastInsertRowid);
            insertProductPosition.run(categoryId, productId, categoryId);
          }
        });
        if (category.children) addCategories(category.children, categoryId);
      });
    };

    addCategories(comMenuCatalog, null);
    categoryCount = Number((database.prepare(
      'SELECT COUNT(*) AS count FROM menu_categories WHERE menu_id = ?',
    ).get(menuId) as { count: number }).count);
    productCount = Number((database.prepare(
      'SELECT COUNT(*) AS count FROM products WHERE menu_id = ?',
    ).get(menuId) as { count: number }).count);
    database.exec('COMMIT');
    return {
      menuId,
      categories: categoryCount,
      products: productCount,
      created: existing === undefined,
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
      console.log(`El menú "${requestedName}" ya existía; se agregaron solamente los datos faltantes.`);
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
