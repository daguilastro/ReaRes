import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'client_identity.dart';
import '../models/pairing_invitation.dart';

class PairingHandshakeException implements Exception {
  const PairingHandshakeException(this.code, [this.details]);

  final String code;
  final String? details;

  @override
  String toString() => details == null ? code : '$code: $details';
}

HttpClient createPinnedMtlsClient({
  required ClientIdentity identity,
  required String host,
  required int port,
  required String fingerprint,
}) {
  final context = SecurityContext(withTrustedRoots: false)
    ..useCertificateChain(identity.certificatePath)
    ..usePrivateKey(identity.privateKeyPath);
  final client = HttpClient(context: context);
  client.connectionTimeout = const Duration(seconds: 6);
  client.idleTimeout = const Duration(seconds: 10);
  client.badCertificateCallback =
      (certificate, certificateHost, certificatePort) {
        final actual = sha256
            .convert(certificate.der)
            .bytes
            .map((byte) => byte.toRadixString(16).padLeft(2, '0').toUpperCase())
            .join(':');
        return certificateHost == host &&
            certificatePort == port &&
            actual == fingerprint.toUpperCase();
      };
  return client;
}

Future<void> completePairingHandshake(PairingInvitation invitation) async {
  final identity = await ensureClientIdentity();
  final client = createPinnedMtlsClient(
    identity: identity,
    host: invitation.host,
    port: invitation.port,
    fingerprint: invitation.certificateFingerprint,
  );
  try {
    final pairingEndpoint = Uri(
      scheme: 'https',
      host: invitation.host,
      port: invitation.port,
      path: '/pairing/complete',
    );
    final request = await client
        .postUrl(pairingEndpoint)
        .timeout(const Duration(seconds: 8));
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'pairingId': invitation.pairingId,
        'pairingSecret': invitation.pairingSecret,
        'deviceName': Platform.localHostname,
      }),
    );
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decoder
        .bind(response)
        .join()
        .timeout(const Duration(seconds: 6));
    if (response.statusCode != HttpStatus.ok) {
      throw PairingHandshakeException(
        'PAIRING_REJECTED',
        '${response.statusCode}: $body',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic> || decoded['paired'] != true) {
      throw const PairingHandshakeException('INVALID_PAIRING_RESPONSE');
    }

    // No avanzamos al login hasta demostrar que el mismo certificado ya fue
    // persistido y aceptado por las rutas mTLS normales del servidor.
    final verification = await client
        .getUrl(
          Uri(
            scheme: 'https',
            host: invitation.host,
            port: invitation.port,
            path: '/device/connection',
          ),
        )
        .timeout(const Duration(seconds: 8));
    final verificationResponse = await verification.close().timeout(
      const Duration(seconds: 10),
    );
    final verificationBody = await utf8.decoder
        .bind(verificationResponse)
        .join()
        .timeout(const Duration(seconds: 6));
    if (verificationResponse.statusCode != HttpStatus.ok) {
      throw PairingHandshakeException(
        'PAIRING_NOT_CONFIRMED',
        '${verificationResponse.statusCode}: $verificationBody',
      );
    }

    await _savePairedServer(identity, invitation);
  } finally {
    client.close(force: true);
  }
}

Future<void> _savePairedServer(
  ClientIdentity identity,
  PairingInvitation invitation,
) async {
  final localServer = await _isAddressOnThisDevice(invitation.host);
  final separator = Platform.pathSeparator;
  final destination = File(
    '${identity.directory}${separator}paired-server.json',
  );
  final temporary = File(
    '${destination.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
  );
  try {
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'host': invitation.host,
        'port': invitation.port,
        'certificateFingerprint': invitation.certificateFingerprint,
        'localServer': localServer,
        'pairedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await temporary.rename(destination.path);
  } finally {
    if (await temporary.exists()) await temporary.delete();
  }
}

Future<bool> _isAddressOnThisDevice(String host) async {
  if (InternetAddress.tryParse(host)?.isLoopback == true) return true;
  try {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: true,
    );
    return interfaces
        .expand((interface) => interface.addresses)
        .any((address) => address.address == host);
  } on Object {
    return false;
  }
}
