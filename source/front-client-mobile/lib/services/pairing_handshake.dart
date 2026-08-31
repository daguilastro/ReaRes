import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'client_identity.dart';
import '../models/pairing_invitation.dart';

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
    final request = await client.postUrl(
      Uri(
        scheme: 'https',
        host: invitation.host,
        port: invitation.port,
        path: '/pairing/complete',
      ),
    );
    request.headers.contentType = ContentType.json;
    request.write(
      jsonEncode({
        'pairingId': invitation.pairingId,
        'pairingSecret': invitation.pairingSecret,
        'deviceName': Platform.localHostname,
      }),
    );
    final response = await request.close().timeout(const Duration(seconds: 10));
    final body = await utf8.decoder.bind(response).join();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Pairing failed (${response.statusCode}): $body');
    }
    await File(
      '${identity.directory}${Platform.pathSeparator}paired-server.json',
    ).writeAsString(
      jsonEncode({
        'host': invitation.host,
        'port': invitation.port,
        'certificateFingerprint': invitation.certificateFingerprint,
      }),
      flush: true,
    );
  } finally {
    client.close(force: true);
  }
}
