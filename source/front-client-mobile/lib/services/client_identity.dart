import 'dart:io';
import 'dart:isolate';

import 'package:basic_utils/basic_utils.dart';
import 'package:path_provider/path_provider.dart';

const _identityDirectoryName = 'identity';
const _privateKeyFileName = 'client-key.pem';
const _certificateFileName = 'client-cert.pem';

class ClientIdentity {
  const ClientIdentity({
    required this.directory,
    required this.privateKeyPath,
    required this.certificatePath,
    required this.wasCreated,
  });

  final String directory;
  final String privateKeyPath;
  final String certificatePath;
  final bool wasCreated;
}

/// Reutiliza la identidad existente o crea una nueva dentro del almacenamiento
/// privado persistente de la aplicación.
Future<ClientIdentity> ensureClientIdentity({
  Directory? supportDirectory,
}) async {
  final appSupportDirectory =
      supportDirectory ?? await getApplicationSupportDirectory();
  final separator = Platform.pathSeparator;
  final identityDirectory = Directory(
    '${appSupportDirectory.path}$separator$_identityDirectoryName',
  );
  final privateKeyFile = File(
    '${identityDirectory.path}$separator$_privateKeyFileName',
  );
  final certificateFile = File(
    '${identityDirectory.path}$separator$_certificateFileName',
  );

  await identityDirectory.create(recursive: true);

  final filesExist = await Future.wait([
    privateKeyFile.exists(),
    certificateFile.exists(),
  ]);
  if (filesExist.every((exists) => exists)) {
    return ClientIdentity(
      directory: identityDirectory.path,
      privateKeyPath: privateKeyFile.path,
      certificatePath: certificateFile.path,
      wasCreated: false,
    );
  }

  // RSA puede tardar varios cientos de milisegundos; se ejecuta en otro
  // isolate para que la pulsación del logo siga siendo fluida.
  final generatedIdentity = await Isolate.run(_generateIdentityPem);
  await _writeAtomically(privateKeyFile, generatedIdentity.privateKey);
  await _writeAtomically(certificateFile, generatedIdentity.certificate);

  return ClientIdentity(
    directory: identityDirectory.path,
    privateKeyPath: privateKeyFile.path,
    certificatePath: certificateFile.path,
    wasCreated: true,
  );
}

({String privateKey, String certificate}) _generateIdentityPem() {
  final keyPair = CryptoUtils.generateRSAKeyPair(keySize: 2048);
  final privateKey = keyPair.privateKey as RSAPrivateKey;
  final publicKey = keyPair.publicKey as RSAPublicKey;
  final subject = {'CN': 'Restaurante Mobile Client', 'O': 'RestauranteApp'};
  final csr = X509Utils.generateRsaCsrPem(subject, privateKey, publicKey);
  final certificate = X509Utils.generateSelfSignedCertificate(
    privateKey,
    csr,
    3650,
    keyUsage: const [KeyUsage.DIGITAL_SIGNATURE],
    extKeyUsage: const [ExtendedKeyUsage.CLIENT_AUTH],
    cA: false,
    serialNumber: DateTime.now().microsecondsSinceEpoch.toString(),
  );

  return (
    privateKey: CryptoUtils.encodeRSAPrivateKeyToPem(privateKey),
    certificate: certificate,
  );
}

Future<void> _writeAtomically(File destination, String contents) async {
  final temporary = File(
    '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  await temporary.writeAsString(contents, flush: true);
  await temporary.rename(destination.path);
}
