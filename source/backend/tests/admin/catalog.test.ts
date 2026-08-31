import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { DatabaseSync } from 'node:sqlite';
import test from 'node:test';
import { createAdminCatalogRoutes } from '../../admin/routes/catalog';

test('an admin builds menus with categories, products and room restrictions', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  database.prepare(
    "INSERT INTO users (name, role, username, password_hash) VALUES ('Admin', 'admin', 'admin', 'hash')",
  ).run();
  database.prepare("INSERT INTO hall (id, name) VALUES (1, 'Main'), (2, 'Terrace')").run();
  const token = 'admin-session';
  database.prepare(`INSERT INTO admin_sessions (user_id, token_hash, created_at, expires_at)
    VALUES (1, ?, ?, ?)`).run(createHash('sha256').update(token).digest('hex'),
      new Date().toISOString(), new Date(Date.now() + 60_000).toISOString());
  const app = createAdminCatalogRoutes({ database });
  const headers = { authorization: `Bearer ${token}`, 'content-type': 'application/json' };

  const ingredientCategoryResponse = await app.request('/ingredient-categories', {
    method: 'POST', headers, body: JSON.stringify({ name: 'Vegetables' }),
  });
  assert.equal(ingredientCategoryResponse.status, 201);
  const ingredientCategoryId = (await ingredientCategoryResponse.json() as
    { category: { id: number } }).category.id;
  const ingredientResponse = await app.request('/ingredients', {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Tomato', description: 'Fresh tomato',
      categoryId: ingredientCategoryId }),
  });
  assert.equal(ingredientResponse.status, 201);
  const ingredientId = (await ingredientResponse.json() as
    { ingredient: { id: number } }).ingredient.id;

  const menuResponse = await app.request('/menus', {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Dinner', hallAssignments: [
      { hallId: 1, isPrimary: true }, { hallId: 2, isPrimary: false },
    ] }),
  });
  assert.equal(menuResponse.status, 201);
  const menuId = (await menuResponse.json() as { menu: { id: number } }).menu.id;
  const duplicatePrimary = await app.request('/menus', {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Lunch', hallAssignments: [
      { hallId: 1, isPrimary: true },
    ] }),
  });
  assert.equal(duplicatePrimary.status, 409);

  const withoutCategory = await app.request(`/menus/${menuId}/products`, {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Soup', description: '', value: 1200,
      categoryId: 999, ingredientIds: [], hallIds: [] }),
  });
  assert.equal(withoutCategory.status, 422);

  const categoryResponse = await app.request(`/menus/${menuId}/categories`, {
    method: 'POST', headers, body: JSON.stringify({ name: 'Starters' }),
  });
  assert.equal(categoryResponse.status, 201);
  const categoryId = (await categoryResponse.json() as
    { category: { id: number } }).category.id;
  const specialCategoryResponse = await app.request(`/menus/${menuId}/categories`, {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Additions', isSpecial: true }),
  });
  assert.equal(specialCategoryResponse.status, 201);
  const specialCategory = (await specialCategoryResponse.json() as { category: {
    id: number; parentCategoryId: number | null; isSpecial: boolean;
  } }).category;
  assert.equal(specialCategory.parentCategoryId, null);
  assert.equal(specialCategory.isSpecial, true);

  const specialSubcategory = await app.request(`/menus/${menuId}/categories`, {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Invalid special child',
      parentCategoryId: categoryId, isSpecial: true }),
  });
  assert.equal(specialSubcategory.status, 422);
  assert.deepEqual(await specialSubcategory.json(), {
    error: 'SPECIAL_CATEGORY_MUST_BE_ROOT',
  });

  const childOfSpecial = await app.request(`/menus/${menuId}/categories`, {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Invalid child',
      parentCategoryId: specialCategory.id }),
  });
  assert.equal(childOfSpecial.status, 422);

  const subcategoryResponse = await app.request(`/menus/${menuId}/categories`, {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Soups', parentCategoryId: categoryId }),
  });
  assert.equal(subcategoryResponse.status, 201);

  const productResponse = await app.request(`/menus/${menuId}/products`, {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Tomato soup', description: 'Creamy soup', value: 1250,
      categoryId, ingredientIds: [ingredientId], hallIds: [2] }),
  });
  assert.equal(productResponse.status, 201);
  const product = (await productResponse.json() as { product: {
    id: number; description: string; categoryId: number;
    ingredientIds: number[]; hallIds: number[];
  } }).product;
  assert.equal(product.description, 'Creamy soup');
  assert.equal(product.categoryId, categoryId);
  assert.deepEqual(product.ingredientIds, [ingredientId]);
  assert.deepEqual(product.hallIds, [2]);

  const updateResponse = await app.request(`/products/${product.id}`, {
    method: 'PATCH', headers,
    body: JSON.stringify({ name: 'Updated soup', description: 'New recipe',
      value: 20500, ingredientIds: [], hallIds: [] }),
  });
  assert.equal(updateResponse.status, 200);
  const updated = (await updateResponse.json() as {
    product: { name: string; value: number };
  }).product;
  assert.equal(updated.name, 'Updated soup');
  assert.equal(updated.value, 20500);

  const duplicateName = await app.request(`/menus/${menuId}/products`, {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Tomato soup', description: 'Another recipe', value: 1500,
      categoryId, ingredientIds: [], hallIds: [] }),
  });
  assert.equal(duplicateName.status, 201);

  const invalidRestriction = await app.request(`/menus/${menuId}/products`, {
    method: 'POST', headers,
    body: JSON.stringify({ name: 'Hidden soup', value: 500, categoryId,
      ingredientIds: [], hallIds: [3] }),
  });
  assert.equal(invalidRestriction.status, 422);

  const catalogResponse = await app.request('/catalog', { headers });
  assert.equal(catalogResponse.status, 200);
  const catalog = await catalogResponse.json() as { menus: Array<{
    hallIds: number[]; categories: Array<{
      id: number; isSpecial: boolean; products: unknown[];
      subcategories: Array<{ isSpecial: boolean }>;
    }>;
  }>; ingredients: unknown[] };
  assert.deepEqual((catalog.menus[0] as unknown as {
    hallAssignments: unknown[];
  }).hallAssignments, [
    { hallId: 1, isPrimary: true }, { hallId: 2, isPrimary: false },
  ]);
  const regular = catalog.menus[0].categories.find(({ id }) => id === categoryId)!;
  const special = catalog.menus[0].categories.find(
    ({ id }) => id === specialCategory.id,
  )!;
  assert.equal(regular.products.length, 2);
  assert.equal(regular.subcategories[0].isSpecial, false);
  assert.equal(special.isSpecial, true);
  assert.equal(special.subcategories.length, 0);
  assert.equal(catalog.ingredients.length, 1);

  const deactivateResponse = await app.request(`/products/${product.id}`, {
    method: 'DELETE', headers,
  });
  assert.equal(deactivateResponse.status, 204);
  assert.equal((database.prepare(
    'SELECT is_active AS active FROM products WHERE id = ?',
  ).get(product.id) as { active: number }).active, 0);
  const afterDeactivate = await app.request('/catalog', { headers });
  const afterCatalog = await afterDeactivate.json() as { menus: Array<{
    categories: Array<{ products: Array<{ id: number }> }>;
  }> };
  assert.equal(afterCatalog.menus[0].categories
    .flatMap(({ products }) => products)
    .some(({ id }) => id === product.id), false);
  database.close();
});

test('a menu may be created without any room assignment', async () => {
  const database = new DatabaseSync(':memory:');
  database.exec(readFileSync(join(process.cwd(), 'db', 'schheme.sql'), 'utf8'));
  database.prepare(
    "INSERT INTO users (name, role, username, password_hash) VALUES ('Admin', 'admin', 'admin', 'hash')",
  ).run();
  const token = 'admin-session';
  database.prepare(`INSERT INTO admin_sessions (user_id, token_hash, created_at, expires_at)
    VALUES (1, ?, ?, ?)`).run(createHash('sha256').update(token).digest('hex'),
      new Date().toISOString(), new Date(Date.now() + 60_000).toISOString());
  const app = createAdminCatalogRoutes({ database });
  const response = await app.request('/menus', {
    method: 'POST',
    headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ name: 'Future menu', hallAssignments: [] }),
  });
  assert.equal(response.status, 201);
  assert.deepEqual((await response.json() as {
    menu: { hallAssignments: unknown[] };
  }).menu.hallAssignments, []);
  database.close();
});
