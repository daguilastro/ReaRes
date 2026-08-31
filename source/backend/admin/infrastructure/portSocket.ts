import { createConnection, createServer, type Server } from 'node:net';
import { chmod, lstat, mkdir, rename, unlink, writeFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';

const SOCKET_FILENAME = 'admin-port.sock';
const PORT_FILENAME = 'admin-port.txt';

type RuntimeFileState = {
  version: 1;
  adminPort: number;
  deviceHost: string | null;
  devicePort: number | null;
  updatedAt: string;
};

function isTermuxAndroid(): boolean {
  const prefix = process.env.PREFIX ?? '';
  return (
    process.platform === 'android' ||
    process.env.TERMUX_VERSION !== undefined ||
    prefix.includes('com.termux')
  );
}

export function getAdminPortSocketPath(): string {
  if (isTermuxAndroid()) {
    const prefix = process.env.PREFIX;
    if (!prefix) {
      throw new Error('Termux fue detectado, pero PREFIX no está definido.');
    }
    return join(prefix, 'var', 'run', 'restaurante-app', SOCKET_FILENAME);
  }

  const runtimeDirectory =
    process.env.XDG_RUNTIME_DIR ??
    join('/tmp', `restaurante-app-${process.getuid?.() ?? 'unknown'}`);
  return join(runtimeDirectory, 'restaurante-app', SOCKET_FILENAME);
}

export function getAdminPortFilePath(): string {
  const configuredPath = process.env.RESTAURANTE_ADMIN_PORT_FILE?.trim();
  if (configuredPath) return configuredPath;

  if (isTermuxAndroid()) {
    const sharedStorage = process.env.EXTERNAL_STORAGE ?? '/storage/emulated/0';
    return join(sharedStorage, 'Download', 'restaurante-app', PORT_FILENAME);
  }

  const runtimeDirectory =
    process.env.XDG_RUNTIME_DIR ??
    join('/tmp', `restaurante-app-${process.getuid?.() ?? 'unknown'}`);
  return join(runtimeDirectory, 'restaurante-app', PORT_FILENAME);
}

async function writePortFile(
  path: string,
  state: RuntimeFileState,
): Promise<void> {
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });
  const temporaryPath = `${path}.${process.pid}.tmp`;
  await writeFile(temporaryPath, `${JSON.stringify(state)}\n`, {
    encoding: 'utf8',
    mode: 0o600,
  });
  await rename(temporaryPath, path);
  await chmod(path, 0o600).catch(() => {
    // El almacenamiento compartido emulado de Android no implementa chmod.
  });
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await lstat(path);
    return true;
  } catch {
    return false;
  }
}

async function socketIsActive(path: string): Promise<boolean> {
  return new Promise((resolve) => {
    const client = createConnection(path);
    let settled = false;

    const finish = (active: boolean) => {
      if (settled) return;
      settled = true;
      client.destroy();
      resolve(active);
    };

    client.once('connect', () => finish(true));
    client.once('error', () => finish(false));
    client.setTimeout(500, () => finish(false));
  });
}

export type AdminPortSocket = {
  path: string;
  portFilePath: string;
  server: Server;
  updateDeviceEndpoint: (
    host: string | null,
    port: number | null,
  ) => Promise<void>;
  close: () => Promise<void>;
};

export async function createAdminPortSocket(
  port: number,
  path = getAdminPortSocketPath(),
): Promise<AdminPortSocket> {
  const portFilePath = getAdminPortFilePath();
  await mkdir(dirname(path), { recursive: true, mode: 0o700 });

  if (await pathExists(path)) {
    if (await socketIsActive(path)) {
      throw new Error(`Ya existe un servidor usando el socket ${path}.`);
    }
    // Un cierre abrupto puede dejar el nombre del socket sin un listener.
    await unlink(path);
  }

  const server = createServer((connection) => {
    connection.on('error', () => {
      // Un cliente puede desconectarse mientras lee el puerto; no es fatal.
    });
    connection.end(`${port}\n`);
  });

  await new Promise<void>((resolve, reject) => {
    server.once('error', reject);
    server.listen(path, () => {
      server.removeListener('error', reject);
      resolve();
    });
  });
  await chmod(path, 0o600);
  let deviceHost: string | null = null;
  let devicePort: number | null = null;
  let pendingWrite = Promise.resolve();
  const persistRuntime = () => {
    const state: RuntimeFileState = {
      version: 1,
      adminPort: port,
      deviceHost,
      devicePort,
      updatedAt: new Date().toISOString(),
    };
    pendingWrite = pendingWrite.catch(() => {
      // Una escritura fallida no debe bloquear permanentemente las siguientes.
    }).then(() => writePortFile(portFilePath, state));
    return pendingWrite;
  };
  await persistRuntime();

  return {
    path,
    portFilePath,
    server,
    updateDeviceEndpoint: async (host, networkPort) => {
      deviceHost = host;
      devicePort = networkPort;
      await persistRuntime();
    },
    close: async () => {
      await new Promise<void>((resolve) => server.close(() => resolve()));
      await pendingWrite.catch(() => {
        // El cierre igualmente debe retirar los archivos publicados.
      });
      if (await pathExists(path)) await unlink(path);
      if (await pathExists(portFilePath)) await unlink(portFilePath);
    },
  };
}
