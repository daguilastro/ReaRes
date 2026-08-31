import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restaurante_front/services/client_identity.dart';

void main() {
  test('creates the identity once and reuses both files', () async {
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'restaurante-client-identity-',
    );
    addTearDown(() => temporaryDirectory.delete(recursive: true));

    final first = await ensureClientIdentity(
      supportDirectory: temporaryDirectory,
    );
    final firstKey = await File(first.privateKeyPath).readAsString();
    final firstCertificate = await File(first.certificatePath).readAsString();

    expect(first.wasCreated, isTrue);
    expect(firstKey, contains('BEGIN PRIVATE KEY'));
    expect(firstCertificate, contains('BEGIN CERTIFICATE'));

    final second = await ensureClientIdentity(
      supportDirectory: temporaryDirectory,
    );

    expect(second.wasCreated, isFalse);
    expect(await File(second.privateKeyPath).readAsString(), firstKey);
    expect(await File(second.certificatePath).readAsString(), firstCertificate);
  });
}
