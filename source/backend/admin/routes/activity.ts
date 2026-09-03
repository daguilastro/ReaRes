import { createHash } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { Hono } from 'hono';
import { streamSSE } from 'hono/streaming';
import { activityHub } from '../../shared/activityLog';
import { openApplicationDatabase } from '../../shared/schemaMigration';

type Options = { database?: DatabaseSync };
const hashToken = (token: string) => createHash('sha256').update(token).digest('hex');

export function createAdminActivityRoutes(options: Options = {}) {
  const routes = new Hono();
  let database = options.database;
  const db = () => database ??= openApplicationDatabase();

  routes.use('*', async (c, next) => {
    const token = c.req.header('authorization')
      ?.match(/^Bearer ([A-Za-z0-9_-]+)$/)?.[1];
    const session = token && db().prepare(
      `SELECT 1 FROM admin_sessions s JOIN users u ON u.id = s.user_id
       WHERE s.token_hash = ? AND s.expires_at > ? AND u.role = 'admin' LIMIT 1`,
    ).get(hashToken(token), new Date().toISOString());
    if (!session) return c.json({ error: 'ADMIN_REQUIRED' }, 403);
    await next();
  });

  routes.get('/activities', (c) => {
    const activities = db().prepare(
      `SELECT a.id, COALESCE(u.name, 'System') AS author, a.type,
              a.modification, a.hall_id AS roomId, a.created_at AS createdAt
       FROM activity_log a LEFT JOIN users u ON u.id = a.author_id
       ORDER BY a.id DESC LIMIT 100`,
    ).all() as Array<Record<string, unknown> & { modification: string }>;
    return c.json({
      activities: activities.map((activity) => ({
        ...activity,
        modification: normalizeLegacyOrderReference(
          db(),
          activity.modification,
        ),
      })),
    });
  });

  routes.get('/events', (c) => streamSSE(c, async (stream) => {
    await stream.writeSSE({ event: 'connected', data: '{}' });
    const unsubscribe = activityHub.subscribe((activity) => {
      void stream.writeSSE({
        event: 'activity',
        id: String(activity.id),
        data: JSON.stringify(activity),
      }).catch(() => undefined);
    });
    await new Promise<void>((resolve) => {
      stream.onAbort(() => {
        unsubscribe();
        resolve();
      });
    });
  }));

  return routes;
}

export default createAdminActivityRoutes();

function normalizeLegacyOrderReference(
  database: DatabaseSync,
  modification: string,
) {
  const match = modification.match(/pedido\s+(\d+)/i);
  if (!match) return modification;
  const order = database.prepare(
    `SELECT COALESCE(o.external_name, g.visible_identifier, t.identifier) AS tableLabel
     FROM orders o LEFT JOIN hall_tables t ON t.id = o.table_id
     LEFT JOIN table_groups g ON g.id = o.table_group_id
     WHERE o.id = ?`,
  ).get(Number(match[1])) as { tableLabel: string } | undefined;
  if (!order) return modification;
  return modification.replace(
    new RegExp(`pedido\\s+${match[1]}`, 'i'),
    `pedido de la mesa ${order.tableLabel}`,
  );
}
