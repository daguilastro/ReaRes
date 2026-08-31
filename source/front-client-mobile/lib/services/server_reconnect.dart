import 'dart:convert';
import 'dart:io';

import 'package:multicast_dns/multicast_dns.dart';

import 'client_identity.dart';
import 'pairing_handshake.dart';

Future<bool> reconnectToPairedServer() async {
  final identity = await ensureClientIdentity();
  final stateFile = File(
    '${identity.directory}${Platform.pathSeparator}paired-server.json',
  );
  if (!await stateFile.exists()) return false;
  try {
    final state = jsonDecode(await stateFile.readAsString());
    if (state is! Map<String, dynamic> ||
        state['certificateFingerprint'] is! String) {
      return false;
    }
    final fingerprint = state['certificateFingerprint'] as String;
    final mdns = MDnsClient();
    await mdns.start().timeout(const Duration(seconds: 2));
    try {
      await for (final pointer in mdns.lookup<PtrResourceRecord>(
        ResourceRecordQuery.serverPointer('_https._tcp.local'),
        timeout: const Duration(seconds: 3),
      )) {
        if (!pointer.domainName.toLowerCase().startsWith('restaurante')) {
          continue;
        }
        await for (final service in mdns.lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(pointer.domainName),
          timeout: const Duration(seconds: 2),
        )) {
          await for (final address in mdns.lookup<IPAddressResourceRecord>(
            ResourceRecordQuery.addressIPv4(service.target),
            timeout: const Duration(seconds: 2),
          )) {
            if (await _verifyCandidate(
              identity,
              address.address.address,
              service.port,
              fingerprint,
            )) {
              return true;
            }
          }
        }
      }
    } finally {
      mdns.stop();
    }
  } on Object catch (error) {
    // Es una condición normal si el servidor está apagado o cambió de red.
    // El splash continuará hacia el flujo de emparejamiento.
    stderr.writeln('No se pudo reconectar por mDNS: $error');
    return false;
  }
  return false;
}

Future<bool> _verifyCandidate(
  ClientIdentity identity,
  String host,
  int port,
  String fingerprint,
) async {
  final client = createPinnedMtlsClient(
    identity: identity,
    host: host,
    port: port,
    fingerprint: fingerprint,
  );
  try {
    final request = await client.getUrl(
      Uri(scheme: 'https', host: host, port: port, path: '/device/connection'),
    );
    final response = await request.close().timeout(const Duration(seconds: 4));
    await response.drain<void>();
    if (response.statusCode != HttpStatus.ok) return false;
    final stateFile = File(
      '${identity.directory}${Platform.pathSeparator}paired-server.json',
    );
    await stateFile.writeAsString(
      jsonEncode({
        'host': host,
        'port': port,
        'certificateFingerprint': fingerprint,
      }),
      flush: true,
    );
    return true;
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}
