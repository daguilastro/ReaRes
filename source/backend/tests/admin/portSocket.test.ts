import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createAdminPortSocket } from '../../admin/infrastructure/portSocket';

test('the runtime file contains both admin and device endpoints', async () => {
  const directory = mkdtempSync(join(tmpdir(), 'restaurant-runtime-'));
  const previous = process.env.RESTAURANTE_ADMIN_PORT_FILE;
  process.env.RESTAURANTE_ADMIN_PORT_FILE = join(directory, 'admin-port.txt');
  try {
    const runtime = await createAdminPortSocket(
      32100,
      join(directory, 'admin-port.sock'),
    );
    await runtime.updateDeviceEndpoint('192.168.1.25', 45600);
    const state = JSON.parse(readFileSync(runtime.portFilePath, 'utf8')) as {
      adminPort: number;
      deviceHost: string;
      devicePort: number;
    };
    assert.equal(state.adminPort, 32100);
    assert.equal(state.deviceHost, '192.168.1.25');
    assert.equal(state.devicePort, 45600);
    await runtime.close();
  } finally {
    if (previous === undefined) delete process.env.RESTAURANTE_ADMIN_PORT_FILE;
    else process.env.RESTAURANTE_ADMIN_PORT_FILE = previous;
    rmSync(directory, { recursive: true, force: true });
  }
});
