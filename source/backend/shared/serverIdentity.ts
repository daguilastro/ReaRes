import { X509Certificate } from 'node:crypto';
import { access, chmod, mkdir, readFile, rename, writeFile } from 'node:fs/promises';
import { homedir, hostname } from 'node:os';
import { join } from 'node:path';
import { generate } from 'selfsigned';

const APP_DIRECTORY = 'restaurante-app';
const IDENTITY_DIRECTORY = 'identity';
const KEY_FILENAME = 'server-key.pem';
const CERTIFICATE_FILENAME = 'server-cert.pem';

export type ServerIdentity = {
  environment: 'termux-android' | 'linux';
  directory: string;
  keyPath: string;
  certificatePath: string;
  fingerprint: string;
};

function isTermuxAndroid(): boolean {
  const prefix = process.env.PREFIX ?? '';
  return (
    process.platform === 'android' ||
    process.env.TERMUX_VERSION !== undefined ||
    prefix.includes('com.termux')
  );
}

function getIdentityDirectory(): {
  environment: ServerIdentity['environment'];
  directory: string;
} {
  if (isTermuxAndroid()) {
    const prefix = process.env.PREFIX;
    if (!prefix) {
      throw new Error('Termux fue detectado, pero la variable PREFIX no existe.');
    }

    return {
      environment: 'termux-android',
      directory: join(prefix, 'var', 'lib', APP_DIRECTORY, IDENTITY_DIRECTORY),
    };
  }

  const dataHome =
    process.env.XDG_DATA_HOME ?? join(homedir(), '.local', 'share');
  return {
    environment: 'linux',
    directory: join(dataHome, APP_DIRECTORY, IDENTITY_DIRECTORY),
  };
}

async function fileExists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function writeIdentityAtomically(
  keyPath: string,
  certificatePath: string,
  privateKey: string,
  certificate: string,
): Promise<void> {
  const suffix = `${process.pid}-${Date.now()}`;
  const temporaryKeyPath = `${keyPath}.${suffix}.tmp`;
  const temporaryCertificatePath = `${certificatePath}.${suffix}.tmp`;

  await writeFile(temporaryKeyPath, privateKey, { encoding: 'utf8', mode: 0o600 });
  await writeFile(temporaryCertificatePath, certificate, {
    encoding: 'utf8',
    mode: 0o644,
  });

  await rename(temporaryKeyPath, keyPath);
  await rename(temporaryCertificatePath, certificatePath);
  await chmod(keyPath, 0o600);
  await chmod(certificatePath, 0o644);
}

export async function ensureServerIdentity(): Promise<ServerIdentity> {
  const { environment, directory } = getIdentityDirectory();
  const keyPath = join(directory, KEY_FILENAME);
  const certificatePath = join(directory, CERTIFICATE_FILENAME);

  await mkdir(directory, { recursive: true, mode: 0o700 });

  const [keyExists, certificateExists] = await Promise.all([
    fileExists(keyPath),
    fileExists(certificatePath),
  ]);

  if (!keyExists || !certificateExists) {
    const commonName = `Restaurante ${hostname()}`;
    const notBeforeDate = new Date();
    const notAfterDate = new Date(notBeforeDate);
    notAfterDate.setFullYear(notAfterDate.getFullYear() + 10);

    const identity = await generate(
      [{ name: 'commonName', value: commonName }],
      {
        keyType: 'ec',
        curve: 'P-256',
        algorithm: 'sha256',
        notBeforeDate,
        notAfterDate,
        extensions: [
          { name: 'basicConstraints', cA: false, critical: true },
          {
            name: 'keyUsage',
            digitalSignature: true,
            keyAgreement: true,
            critical: true,
          },
          { name: 'extKeyUsage', serverAuth: true },
          {
            name: 'subjectAltName',
            altNames: [
              { type: 2, value: hostname() },
              { type: 2, value: 'restaurante.local' },
              { type: 2, value: 'localhost' },
              { type: 7, ip: '127.0.0.1' },
              { type: 7, ip: '::1' },
            ],
          },
        ],
      },
    );

    await writeIdentityAtomically(
      keyPath,
      certificatePath,
      identity.private,
      identity.cert,
    );
    console.log(`Nueva identidad del servidor creada en ${directory}`);
  }

  const certificate = await readFile(certificatePath, 'utf8');
  const fingerprint = new X509Certificate(certificate).fingerprint256;

  return {
    environment,
    directory,
    keyPath,
    certificatePath,
    fingerprint,
  };
}
