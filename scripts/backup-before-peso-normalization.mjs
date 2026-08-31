import { chmodSync, existsSync, mkdirSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { backup, DatabaseSync } from 'node:sqlite';

const migrationName = '2026-08-normalize-product-values-to-pesos';
const projectDirectory = resolve(import.meta.dirname, '..');
const dataHome = process.env.XDG_DATA_HOME?.trim() ||
  join(homedir(), '.local', 'share');
const configuredDatabase = process.env.RESTAURANTE_DB_FILE?.trim();
const destination = configuredDatabase
  ? resolve(configuredDatabase)
  : join(dataHome, 'restaurante-app', 'restaurant.sqlite');
const legacyDatabase = join(projectDirectory, 'db', 'restaurant.sqlite');
const source = existsSync(destination)
  ? destination
  : existsSync(legacyDatabase)
    ? legacyDatabase
    : null;

if (source === null) process.exit(0);

const database = new DatabaseSync(source);
try {
  const migrationTableExists = Boolean(database.prepare(`
    SELECT 1 FROM sqlite_master
    WHERE type = 'table' AND name = 'schema_migrations'
    LIMIT 1
  `).get());
  const alreadyNormalized = migrationTableExists && Boolean(database.prepare(`
    SELECT 1 FROM schema_migrations WHERE name = ? LIMIT 1
  `).get(migrationName));
  if (alreadyNormalized) process.exit(0);

  const backupDirectory = join(dirname(destination), 'backups');
  mkdirSync(backupDirectory, { recursive: true, mode: 0o700 });
  const timestamp = new Date().toISOString().replaceAll(':', '-');
  const backupPath = join(
    backupDirectory,
    `restaurant-before-peso-normalization-${timestamp}.sqlite`,
  );
  await backup(database, backupPath);
  chmodSync(backupPath, 0o600);
  console.log(`Respaldo previo a la normalización de precios: ${backupPath}`);
} finally {
  database.close();
}
