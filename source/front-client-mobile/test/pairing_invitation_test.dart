import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:restaurante_front/models/pairing_invitation.dart';

void main() {
  test('accepts only a complete, current pairing QR payload', () {
    final valid = jsonEncode({
      'version': 1,
      'scheme': 'https',
      'host': '192.168.1.20',
      'port': 43210,
      'pairingId': '123e4567-e89b-12d3-a456-426614174000',
      'pairingSecret': List.filled(43, 'A').join(),
      'expiresAt': DateTime.now()
          .add(const Duration(minutes: 2))
          .toIso8601String(),
      'certificateFingerprint': List.filled(32, 'AA').join(':'),
    });
    expect(PairingInvitation.tryParse(valid), isNotNull);
    final invalid = jsonDecode(valid) as Map<String, dynamic>
      ..remove('pairingSecret');
    expect(PairingInvitation.tryParse(jsonEncode(invalid)), isNull);
    final expired = jsonDecode(valid) as Map<String, dynamic>
      ..['expiresAt'] = DateTime.now()
          .subtract(const Duration(seconds: 1))
          .toIso8601String();
    expect(PairingInvitation.tryParse(jsonEncode(expired)), isNull);
  });
}
