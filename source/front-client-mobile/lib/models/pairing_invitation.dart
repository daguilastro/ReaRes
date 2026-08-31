import 'dart:convert';

class PairingInvitation {
  const PairingInvitation({
    required this.host,
    required this.port,
    required this.pairingId,
    required this.pairingSecret,
    required this.expiresAt,
    required this.certificateFingerprint,
  });

  final String host;
  final int port;
  final String pairingId;
  final String pairingSecret;
  final DateTime expiresAt;
  final String certificateFingerprint;

  static PairingInvitation? tryParse(String raw) {
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> ||
          value.length < 8 ||
          value['version'] != 1 ||
          value['scheme'] != 'https' ||
          value['host'] is! String ||
          value['port'] is! int ||
          value['pairingId'] is! String ||
          value['pairingSecret'] is! String ||
          value['expiresAt'] is! String ||
          value['certificateFingerprint'] is! String) {
        return null;
      }
      final host = value['host'] as String;
      final port = value['port'] as int;
      final id = value['pairingId'] as String;
      final secret = value['pairingSecret'] as String;
      final expiration = DateTime.tryParse(value['expiresAt'] as String);
      final fingerprint = value['certificateFingerprint'] as String;
      if (host.isEmpty ||
          host.length > 253 ||
          port < 1 ||
          port > 65535 ||
          !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ||
          !RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(secret) ||
          expiration == null ||
          !expiration.isAfter(DateTime.now()) ||
          !RegExp(
            r'^(?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}$',
          ).hasMatch(fingerprint)) {
        return null;
      }
      return PairingInvitation(
        host: host,
        port: port,
        pairingId: id,
        pairingSecret: secret,
        expiresAt: expiration,
        certificateFingerprint: fingerprint.toUpperCase(),
      );
    } on Object {
      return null;
    }
  }
}
