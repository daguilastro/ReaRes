import {
  chmodSync,
  copyFileSync,
  existsSync,
  mkdirSync,
  rmSync,
} from 'node:fs';
import { homedir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

const DATABASE_FILENAME = 'restaurant.sqlite';

export function applicationDatabasePath(): string {
  const override = process.env.RESTAURANTE_DB_FILE?.trim();
  if (override) return resolve(override);
  const dataHome = process.env.XDG_DATA_HOME?.trim() ||
    join(homedir(), '.local', 'share');
  return join(dataHome, 'restaurante-app', DATABASE_FILENAME);
}

export function legacyApplicationDatabasePath(): string {
  return join(process.cwd(), 'db', DATABASE_FILENAME);
}

/**
 * Copies the former repository-local SQLite bundle once. The destination is
 * never replaced, so an update or git operation cannot overwrite live data.
 */
export function migrateLegacyApplicationDatabase(
  destination = applicationDatabasePath(),
  legacy = legacyApplicationDatabasePath(),
): boolean {
  mkdirSync(dirname(destination), { recursive: true, mode: 0o700 });
  if (resolve(destination) === resolve(legacy) || existsSync(destination) ||
      !existsSync(legacy)) {
    return false;
  }

  const copiedFiles: string[] = [];
  try {
    for (const suffix of ['', '-wal', '-shm']) {
      const source = `${legacy}${suffix}`;
      if (!existsSync(source)) continue;
      const target = `${destination}${suffix}`;
      copyFileSync(source, target);
      copiedFiles.push(target);
      chmodSync(target, 0o600);
    }
    return true;
  } catch (error) {
    for (const file of copiedFiles) rmSync(file, { force: true });
    throw error;
  }
}
