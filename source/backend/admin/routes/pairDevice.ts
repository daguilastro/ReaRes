import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { DatabaseSync } from 'node:sqlite';
import { Hono } from 'hono';
import { getPairingRuntime } from '../../shared/pairingRuntime';
import { openApplicationDatabase } from '../../shared/schemaMigration';

const PAIRING_DURATION_MS = 2 * 60 * 1000;
type Options = { database?: DatabaseSync };

const hash = (value: string) =>
  createHash('sha256').update(value, 'utf8').digest('hex');

export function createAdminPairDeviceRoutes(options: Options = {}) {
  const routes = new Hono();
  let database = options.database;
  const db = () => {
    database ??= openApplicationDatabase();
    return database;
  };

  routes.post('/pairing-requests', (c) => {
    const authorization = c.req.header('authorization');
    const token = authorization?.match(/^Bearer ([A-Za-z0-9_-]+)$/)?.[1];
    if (!token) return c.json({ error: 'INVALID_SESSION' }, 401);
    const session = db().prepare(
      `SELECT 1 FROM admin_sessions
       WHERE token_hash = ? AND expires_at > ? LIMIT 1`,
    ).get(hash(token), new Date().toISOString());
    if (!session) return c.json({ error: 'INVALID_SESSION' }, 401);

    const runtime = getPairingRuntime();
    if (!runtime) {
      return c.json({ error: 'PAIRING_SERVER_UNAVAILABLE' }, 503);
    }

    const now = new Date();
    const expiresAt = new Date(now.getTime() + PAIRING_DURATION_MS);
    const id = randomUUID();
    const secret = randomBytes(32).toString('base64url');
    db().prepare(
      'DELETE FROM device_pairing_requests WHERE expires_at <= ? OR used_at IS NOT NULL',
    ).run(now.toISOString());
    db().prepare(
      `INSERT INTO device_pairing_requests
       (id, secret_hash, created_at, expires_at) VALUES (?, ?, ?, ?)`,
    ).run(id, hash(secret), now.toISOString(), expiresAt.toISOString());

    return c.json({
      pairingId: id,
      pairingSecret: secret,
      expiresAt: expiresAt.toISOString(),
      host: runtime.host,
      port: runtime.port,
      scheme: 'https',
      certificateFingerprint: runtime.certificateFingerprint,
    }, 201);
  });

  return routes;
}

export default createAdminPairDeviceRoutes();
