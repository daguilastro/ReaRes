import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const _socketFilename = 'admin-port.sock';

class ServerNotFoundException implements Exception {
  const ServerNotFoundException();

  @override
  String toString() => 'No se encontró el servidor Restaurante local.';
}

/// Lee el puerto administrativo mediante el socket Unix local y confirma que
/// la API está respondiendo exclusivamente por loopback.
Future<void> verifyLocalServerIsRunning() async {
  try {
    final baseUri = await getLocalAdminBaseUri();
    final port = baseUri.port;
    if (await _isAdminServer(port)) return;
  } on Object {
    // Socket ausente/inaccesible, contenido inválido y API apagada se
    // traducen al estado 404 existente de la pantalla de arranque.
  }
  throw const ServerNotFoundException();
}

Future<Uri> getLocalAdminBaseUri() async {
  final socketPath = await _adminPortSocketPath();
  final port = await _readAdminPort(socketPath);
  return Uri(scheme: 'http', host: '127.0.0.1', port: port);
}

Future<String> _adminPortSocketPath() async {
  if (Platform.isAndroid) {
    return '/data/data/com.termux/files/usr/var/run/'
        'restaurante-app/$_socketFilename';
  }
  if (!Platform.isLinux) throw const ServerNotFoundException();

  final runtimeDirectory = Platform.environment['XDG_RUNTIME_DIR'];
  if (runtimeDirectory != null && runtimeDirectory.isNotEmpty) {
    return '$runtimeDirectory/restaurante-app/$_socketFilename';
  }

  final id = await Process.run('id', const [
    '-u',
  ]).timeout(const Duration(seconds: 1));
  if (id.exitCode != 0) throw const ServerNotFoundException();
  final userId = id.stdout.toString().trim();
  if (!RegExp(r'^\d+$').hasMatch(userId)) {
    throw const ServerNotFoundException();
  }
  return '/tmp/restaurante-app-$userId/restaurante-app/$_socketFilename';
}

Future<int> _readAdminPort(String path) async {
  final address = InternetAddress(path, type: InternetAddressType.unix);
  final socket = await Socket.connect(
    address,
    0,
    timeout: const Duration(seconds: 2),
  );
  try {
    final line = await socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first
        .timeout(const Duration(seconds: 2));
    final port = int.tryParse(line.trim());
    if (port == null || port < 1 || port > 65535) {
      throw const ServerNotFoundException();
    }
    return port;
  } finally {
    await socket.close();
  }
}

Future<bool> _isAdminServer(int port) async {
  try {
    final response = await http
        .get(Uri.parse('http://127.0.0.1:$port/'))
        .timeout(const Duration(seconds: 2));
    return response.statusCode == 200 &&
        response.body.trim() == 'Servidor administrativo funcionando';
  } on Object {
    return false;
  }
}
