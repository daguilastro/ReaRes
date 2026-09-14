import 'dart:convert';

import 'package:http/http.dart' as http;

const _configuredOrigin = String.fromEnvironment(
  'RESTAURANT_API_URL',
  defaultValue: 'https://restauranteapp-cloud.daaguilarc.workers.dev',
);

class ServerNotFoundException implements Exception {
  const ServerNotFoundException();

  @override
  String toString() => 'No se encontró el servicio Restaurante en la nube.';
}

Uri getCloudApiBaseUri() {
  final value = Uri.parse(_configuredOrigin.trim());
  if (!value.hasScheme || value.host.isEmpty) {
    throw const ServerNotFoundException();
  }
  return value.replace(path: '/', query: null, fragment: null);
}

/// Kept as an alias while the rest of the admin service is migrated from its
/// former loopback transport.
Future<Uri> getLocalAdminBaseUri() async => getCloudApiBaseUri();

Future<void> verifyCloudServerIsRunning() async {
  try {
    final response = await http
        .get(getCloudApiBaseUri().resolve('/health'))
        .timeout(const Duration(seconds: 8));
    final decoded = jsonDecode(response.body);
    if (response.statusCode == 200 &&
        decoded is Map<String, dynamic> &&
        decoded['status'] == 'ok') {
      return;
    }
  } on Object {
    // All transport/configuration failures use the existing unavailable view.
  }
  throw const ServerNotFoundException();
}

Future<void> verifyLocalServerIsRunning() => verifyCloudServerIsRunning();

/// Legacy parser retained for backwards-compatible unit tests and rollback
/// builds. It is no longer used to discover the cloud endpoint.
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
      // Invalid input is reported below.
    }
  }
  if (port == null || port < 1 || port > 65535) {
    throw const ServerNotFoundException();
  }
  return port;
}
