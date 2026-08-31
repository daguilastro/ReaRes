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
        state['host'] is! String ||
        state['port'] is! int ||
        state['certificateFingerprint'] is! String) {
      return false;
    }
    final fingerprint = state['certificateFingerprint'] as String;
    final savedHost = state['host'] as String;
    final savedPort = state['port'] as int;
    final localServer =
        state['localServer'] == true || await _isAddressOnThisDevice(savedHost);

    // Android no depende de mDNS: primero reutiliza el endpoint autenticado
    // del pairing anterior. Si Node corre en el mismo teléfono, loopback sigue
    // siendo estable incluso cuando cambia la red Wi-Fi.
    if (Platform.isAndroid) {
      if (localServer &&
          await _verifyCandidate(
            identity,
            InternetAddress.loopbackIPv4.address,
            savedPort,
            fingerprint,
            localServer: true,
          )) {
        return true;
      }
      return _verifyCandidate(
        identity,
        savedHost,
        savedPort,
        fingerprint,
        localServer: localServer,
      );
    }

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
              localServer: localServer,
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

Future<bool> _verifyCandidate(
  ClientIdentity identity,
  String host,
  int port,
  String fingerprint, {
  required bool localServer,
}) async {
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
    final temporary = File('${stateFile.path}.reconnect.tmp');
    await temporary.writeAsString(
      jsonEncode({
        'version': 1,
        'host': host,
        'port': port,
        'certificateFingerprint': fingerprint,
        'localServer': localServer,
        'reconnectedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
    await temporary.rename(stateFile.path);
    return true;
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}
