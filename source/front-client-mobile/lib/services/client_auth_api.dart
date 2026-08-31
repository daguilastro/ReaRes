import 'dart:convert';
import 'dart:io';

import '../models/client_user.dart';
import 'paired_server_client.dart';

class ClientLoginException implements Exception {
  const ClientLoginException(this.code);
  final String code;
}

Future<ClientSession> loginClient(String username, String password) async {
  try {
    final server = await openPairedServerClient();
    try {
      final request = await server.http.postUrl(server.uri('/auth/login'));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({'username': username, 'password': password}));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode == HttpStatus.unauthorized) {
        throw const ClientLoginException('INVALID_CREDENTIALS');
      }
      if (response.statusCode != HttpStatus.ok) {
        throw ClientLoginException('HTTP_${response.statusCode}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic> ||
          decoded['user'] is! Map<String, dynamic> ||
          decoded['token'] is! String ||
          decoded['expiresAt'] is! String) {
        throw const ClientLoginException('INVALID_RESPONSE');
      }
      return ClientSession(
        token: decoded['token'] as String,
        expiresAt: DateTime.parse(decoded['expiresAt'] as String),
        user: ClientUser.fromJson(decoded['user'] as Map<String, dynamic>),
      );
    } finally {
      server.close();
    }
  } on ClientLoginException {
    rethrow;
  } on Object {
    throw const ClientLoginException('CONNECTION_FAILED');
  }
}
