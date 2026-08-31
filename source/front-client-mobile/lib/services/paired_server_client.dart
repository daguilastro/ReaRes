import 'dart:convert';
import 'dart:io';

import 'client_identity.dart';
import 'pairing_handshake.dart';

class PairedServerClient {
  const PairedServerClient({
    required this.http,
    required this.host,
    required this.port,
  });

  final HttpClient http;
  final String host;
  final int port;

  Uri uri(String path) =>
      Uri(scheme: 'https', host: host, port: port, path: path);

  void close() => http.close(force: true);
}

Future<PairedServerClient> openPairedServerClient() async {
  final identity = await ensureClientIdentity();
  final stateFile = File(
    '${identity.directory}${Platform.pathSeparator}paired-server.json',
  );
  if (!await stateFile.exists()) {
    throw const FormatException('SERVER_NOT_PAIRED');
  }
  final state = jsonDecode(await stateFile.readAsString());
  if (state is! Map<String, dynamic> ||
      state['host'] is! String ||
      state['port'] is! int ||
      state['certificateFingerprint'] is! String) {
    throw const FormatException('INVALID_SERVER_STATE');
  }
  final host = state['host'] as String;
  final port = state['port'] as int;
  return PairedServerClient(
    http: createPinnedMtlsClient(
      identity: identity,
      host: host,
      port: port,
      fingerprint: state['certificateFingerprint'] as String,
    ),
    host: host,
    port: port,
  );
}
