import assert from 'node:assert/strict';
import {
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { migrateLegacyApplicationDatabase } from '../../shared/databasePath';

test('migrates the legacy SQLite bundle once without replacing live data', () => {
  const directory = mkdtempSync(join(tmpdir(), 'restaurant-db-path-'));
  const legacy = join(directory, 'legacy', 'restaurant.sqlite');
  const destination = join(directory, 'data', 'restaurant.sqlite');
  try {
    const legacyDirectory = join(directory, 'legacy');
    mkdirSync(legacyDirectory, { recursive: true });
    writeFileSync(legacy, 'database-v1');
    writeFileSync(`${legacy}-wal`, 'wal-v1');
    writeFileSync(`${legacy}-shm`, 'shm-v1');

    assert.equal(migrateLegacyApplicationDatabase(destination, legacy), true);
    assert.equal(readFileSync(destination, 'utf8'), 'database-v1');
    assert.equal(readFileSync(`${destination}-wal`, 'utf8'), 'wal-v1');
    assert.equal(readFileSync(`${destination}-shm`, 'utf8'), 'shm-v1');

    writeFileSync(legacy, 'database-v2');
    assert.equal(migrateLegacyApplicationDatabase(destination, legacy), false);
    assert.equal(readFileSync(destination, 'utf8'), 'database-v1');
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
});
