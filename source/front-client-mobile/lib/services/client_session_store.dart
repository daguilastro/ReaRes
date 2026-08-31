import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/client_user.dart';

const _storage = FlutterSecureStorage();
const _sessionKey = 'employee_session';

Future<void> saveClientSession(ClientSession session) => _storage.write(
  key: _sessionKey,
  value: jsonEncode({
    'token': session.token,
    'expiresAt': session.expiresAt.toUtc().toIso8601String(),
    'user': {
      'id': session.user.id,
      'fullName': session.user.fullName,
      'username': session.user.username,
      'role': session.user.role,
    },
  }),
);

Future<ClientSession?> readClientSession() async {
  try {
    final encoded = await _storage.read(key: _sessionKey);
    if (encoded == null) return null;
    final value = jsonDecode(encoded);
    if (value is! Map<String, dynamic> ||
        value['token'] is! String ||
        value['expiresAt'] is! String ||
        value['user'] is! Map<String, dynamic>) {
      await clearClientSession();
      return null;
    }
    final session = ClientSession(
      token: value['token'] as String,
      expiresAt: DateTime.parse(value['expiresAt'] as String),
      user: ClientUser.fromJson(value['user'] as Map<String, dynamic>),
    );
    if (!session.expiresAt.isAfter(DateTime.now())) {
      await clearClientSession();
      return null;
    }
    return session;
  } on Object {
    try {
      await clearClientSession();
    } on Object {
      // El plugin no existe en pruebas unitarias o el almacén no está disponible.
    }
    return null;
  }
}

Future<void> clearClientSession() => _storage.delete(key: _sessionKey);
