import { Hono } from 'hono';
import { canAccessHall, requireAdmin, requireSession } from '../auth/session';
import { readCatalog, readHalls, readLayout } from '../repositories/readModel';
import type { CloudEnvironment } from '../types';

const routes = new Hono<CloudEnvironment>();

routes.use('*', requireSession);
routes.use('/catalog', requireAdmin);
routes.use('/menus', requireAdmin);
routes.use('/menus/*', requireAdmin);

routes.get('/bootstrap', async (c) => {
  const session = c.get('session');
  const isAdmin = session.user.role === 'admin';
  const [catalog, halls] = await Promise.all([
    isAdmin ? readCatalog(c.env.DB) : Promise.resolve(null),
    readHalls(c.env.DB, isAdmin ? undefined : session.user.id),
  ]);
  return c.json({
    schemaVersion: 1,
    generatedAt: new Date().toISOString(),
    catalog,
    halls,
    user: session.user,
  });
});

routes.get('/catalog', async (c) => c.json(await readCatalog(c.env.DB)));

routes.get('/menus', async (c) => {
  const { menus } = await readCatalog(c.env.DB);
  return c.json({ menus });
});

routes.get('/menus/:menuId', async (c) => {
  const menuId = positiveId(c.req.param('menuId'));
  if (!menuId) return c.json({ error: 'MENU_NOT_FOUND' }, 404);
  const { menus } = await readCatalog(c.env.DB, menuId);
  if (menus.length === 0) return c.json({ error: 'MENU_NOT_FOUND' }, 404);
  return c.json({ menu: menus[0] });
});

routes.get('/halls', async (c) => {
  const session = c.get('session');
  return c.json({
    halls: await readHalls(
      c.env.DB,
      session.user.role === 'admin' ? undefined : session.user.id,
    ),
  });
});

routes.get('/halls/:hallId/layout', async (c) => {
  const hallId = positiveId(c.req.param('hallId'));
  if (!hallId) return c.json({ error: 'HALL_NOT_FOUND' }, 404);
  const session = c.get('session');
  if (session.user.role !== 'admin' &&
      !await canAccessHall(c.env.DB, session, hallId)) {
    return c.json({ error: 'HALL_NOT_ASSIGNED' }, 403);
  }
  const layout = await readLayout(c.env.DB, hallId);
  if (!layout) return c.json({ error: 'HALL_NOT_FOUND' }, 404);
  return c.json(layout);
});

function positiveId(value: string): number | undefined {
  const id = Number(value);
  return Number.isSafeInteger(id) && id > 0 ? id : undefined;
}

export default routes;
