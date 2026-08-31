import { serve, type ServerType } from '@hono/node-server';
import Bonjour from 'bonjour-service';
import { readFile } from 'node:fs/promises';
import { createServer as createHttpsServer } from 'node:https';
import { networkInterfaces } from 'node:os';
import { WebSocketServer } from 'ws';
import adminApp from './admin/app';
import { createAdminPortSocket, type AdminPortSocket } from './admin/infrastructure/portSocket';
import app from './device/app';
import { ensureServerIdentity } from './shared/serverIdentity';
import { clearPairingRuntime, setPairingRuntime } from './shared/pairingRuntime';
import { openApplicationDatabase } from './shared/schemaMigration';

const SERVICE_NAME = 'Restaurante';
const SERVICE_TYPE = 'https';

function localIpv4Address(): string {
  const candidates: { name: string; address: string }[] = [];
  for (const [name, addresses] of Object.entries(networkInterfaces())) {
    for (const address of addresses ?? []) {
      if (address.family === 'IPv4' && !address.internal) {
        candidates.push({ name, address: address.address });
      }
    }
  }
  const physical = candidates.find(
    ({ name, address }) =>
      !/^(docker|veth|br-|virbr|podman|tailscale)/i.test(name) &&
      (/^10\./.test(address) || /^192\.168\./.test(address) ||
        /^172\.(1[6-9]|2\d|3[01])\./.test(address)),
  );
  if (physical) return physical.address;
  if (candidates[0]) return candidates[0].address;
  throw new Error('No se encontró una dirección IPv4 en la red local.');
}

async function startServer(): Promise<void> {
  // Aplica migraciones estructurales antes de aceptar peticiones.
  openApplicationDatabase().close();
  // La identidad debe estar disponible antes de abrir el puerto del servidor.
  const identity = await ensureServerIdentity();
  const [privateKey, certificate] = await Promise.all([
    readFile(identity.keyPath, 'utf8'),
    readFile(identity.certificatePath, 'utf8'),
  ]);
  let networkHost: string | undefined;
  try {
    networkHost = localIpv4Address();
  } catch {
    // La API administrativa puede iniciar sin red; el monitor publicará el
    // endpoint de dispositivos cuando aparezca una IPv4 utilizable.
  }
  const bonjour = new Bonjour(undefined, (error: unknown) => {
    console.error('Error de mDNS:', error);
  });
  const deviceWebSocketServer = new WebSocketServer({ noServer: true });

  let networkServer: ServerType;
  let adminServer: ServerType;
  let adminPortSocket: AdminPortSocket;
  let devicePort: number | undefined;
  let networkMonitor: NodeJS.Timeout | undefined;
  let isShuttingDown = false;

  const shutdown = (signal: NodeJS.Signals) => {
    if (isShuttingDown) return;
    isShuttingDown = true;
    if (networkMonitor) clearInterval(networkMonitor);
    clearPairingRuntime();
    console.log(`\n${signal}: cerrando servidor...`);

    bonjour.unpublishAll(() => {
      bonjour.destroy();
      let pendingServers = 3;
      const finishClosing = () => {
        pendingServers -= 1;
        if (pendingServers === 0) process.exit(0);
      };
      for (const client of deviceWebSocketServer.clients) {
        client.close(1001, 'Server shutting down');
      }
      deviceWebSocketServer.close();
      networkServer.close(finishClosing);
      adminServer.close(finishClosing);
      void adminPortSocket.close().then(finishClosing);
    });
  };

  const adminPortReady = new Promise<number>((resolve) => {
    adminServer = serve(
      {
        fetch: adminApp.fetch,
        hostname: '127.0.0.1',
        // El sistema operativo selecciona un puerto local libre.
        port: 0,
      },
      ({ port }) => resolve(port),
    );
  });
  const adminPort = await adminPortReady;
  adminPortSocket = await createAdminPortSocket(adminPort);
  console.log(`API administrativa: http://127.0.0.1:${adminPort}`);
  console.log(`Socket administrativo: ${adminPortSocket.path}`);
  console.log(`Archivo de puerto administrativo: ${adminPortSocket.portFilePath}`);

  networkServer = serve(
    {
      fetch: app.fetch,
      createServer: createHttpsServer,
      serverOptions: {
        key: privateKey,
        cert: certificate,
        // El endpoint de pairing aún no exige certificado. Las rutas normales
        // validarán el certificado cliente una vez terminado el emparejamiento.
        requestCert: true,
        rejectUnauthorized: false,
      },
      websocket: { server: deviceWebSocketServer },
      // El valor 0 permite que el sistema operativo seleccione un puerto libre.
      port: 0,
    },
    ({ port }) => {
      devicePort = port;
      if (networkHost) {
        setPairingRuntime({
          host: networkHost,
          port,
          certificateFingerprint: identity.fingerprint,
        });
      }
      void adminPortSocket.updateDeviceEndpoint(networkHost ?? null, port).catch(
        (error: unknown) => console.error(
          'No se pudo actualizar el endpoint de dispositivos:', error,
        ),
      );
      bonjour.publish({
        name: SERVICE_NAME,
        type: SERVICE_TYPE,
        protocol: 'tcp',
        port,
        txt: {
          path: '/',
          service: 'restaurant-api',
          certificateFingerprint: identity.fingerprint,
        },
      });

      console.log(`Entorno detectado: ${identity.environment}`);
      console.log(`Certificado: ${identity.certificatePath}`);
      console.log(`Huella SHA-256: ${identity.fingerprint}`);
      console.log(networkHost
        ? `API para dispositivos: https://${networkHost}:${port}`
        : `API para dispositivos escuchando en puerto ${port}; esperando red local.`);
      console.log(`mDNS: ${SERVICE_NAME}._${SERVICE_TYPE}._tcp.local`);
    },
  );

  // El listener mantiene su puerto mientras el proceso vive, pero la IP puede
  // cambiar al alternar entre redes. El archivo compartido y los QR nuevos
  // deben reflejar siempre el endpoint más reciente.
  networkMonitor = setInterval(() => {
    let currentHost: string;
    try {
      currentHost = localIpv4Address();
    } catch {
      if (networkHost !== undefined && devicePort !== undefined) {
        networkHost = undefined;
        clearPairingRuntime();
        void adminPortSocket.updateDeviceEndpoint(null, devicePort).catch(
          (error: unknown) => console.error(
            'No se pudo retirar el endpoint de dispositivos:', error,
          ),
        );
      }
      return;
    }
    if (currentHost === networkHost || devicePort === undefined) return;
    networkHost = currentHost;
    setPairingRuntime({
      host: networkHost,
      port: devicePort,
      certificateFingerprint: identity.fingerprint,
    });
    void adminPortSocket.updateDeviceEndpoint(networkHost, devicePort).catch(
      (error: unknown) => console.error(
        'No se pudo actualizar el endpoint de dispositivos:', error,
      ),
    );
    console.log(`Nuevo endpoint para dispositivos: https://${networkHost}:${devicePort}`);
  }, 3000);
  networkMonitor.unref();

  process.once('SIGINT', shutdown);
  process.once('SIGTERM', shutdown);
}

void startServer().catch((error: unknown) => {
  console.error('No se pudo iniciar el servidor:', error);
  process.exit(1);
});
