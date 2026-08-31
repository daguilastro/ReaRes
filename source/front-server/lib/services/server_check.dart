import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';

const _socketFilename = 'admin-port.sock';
const _portFilename = 'admin-port.txt';

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
  final port = await _discoverAdminPort();
  return Uri(scheme: 'http', host: '127.0.0.1', port: port);
}

Future<int> _discoverAdminPort() async {
  if (Platform.isAndroid) await _ensureSharedStorageAccess();
  try {
    return await _readAdminPortFile(_adminPortFilePath());
  } on Object {
    // Compatibilidad con servidores anteriores que solo publicaban el socket.
    return _readAdminPort(await _adminPortSocketPath());
  }
}

Future<void> _ensureSharedStorageAccess() async {
  if (await Permission.manageExternalStorage.isGranted) return;
  final manageStatus = await Permission.manageExternalStorage.request();
  if (manageStatus.isGranted) return;

  // Android 10 y versiones anteriores usan el permiso de almacenamiento
  // tradicional en lugar de "administrar todos los archivos".
  final storageStatus = await Permission.storage.request();
  if (!storageStatus.isGranted) throw const ServerNotFoundException();
}

String _adminPortFilePath() {
  if (Platform.isAndroid) {
    return '/storage/emulated/0/Download/restaurante-app/$_portFilename';
  }
  if (!Platform.isLinux) throw const ServerNotFoundException();

  final runtimeDirectory = Platform.environment['XDG_RUNTIME_DIR'];
  if (runtimeDirectory != null && runtimeDirectory.isNotEmpty) {
    return '$runtimeDirectory/restaurante-app/$_portFilename';
  }
  return '/tmp/restaurante-app-${_linuxUserIdSync()}/restaurante-app/'
      '$_portFilename';
}

String _linuxUserIdSync() {
  final userId = Platform.environment['UID'];
  if (userId != null && RegExp(r'^\d+$').hasMatch(userId)) return userId;
  // Esta rama solo se usa como fallback; el socket resolverá el UID de forma
  // asíncrona si la variable no está disponible.
  return 'unknown';
}

Future<int> _readAdminPortFile(String path) async {
  final value = await File(
    path,
  ).readAsString().timeout(const Duration(seconds: 2));
  return parseAdminRuntimePort(value);
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
    return parseAdminRuntimePort(line);
  } finally {
    await socket.close();
  }
}

int parseAdminRuntimePort(String value) {
  final trimmed = value.trim();
  int? port = int.tryParse(trimmed);
  if (port == null) {
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic> && decoded['adminPort'] is int) {
        port = decoded['adminPort'] as int;
      }
    } on FormatException {
      // Compatibilidad con el formato histórico de una sola línea.
    }
  }
  if (port == null || port < 1 || port > 65535) {
    throw const ServerNotFoundException();
  }
  return port;
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
