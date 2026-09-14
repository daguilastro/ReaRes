import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:restaurante_front/services/paired_server_client.dart';

void main() {
  test('paired server URLs preserve query parameters outside the path', () {
    final client = PairedServerClient(
      http: HttpClient(),
      host: '192.168.1.20',
      port: 43210,
    );
    addTearDown(client.close);

    final uri = client.uri(
      '/rooms/4/orders/today?paymentMethod=transfer&from=2026-09-12T13%3A00%3A00Z',
    );

    expect(uri.path, '/rooms/4/orders/today');
    expect(uri.queryParameters['paymentMethod'], 'transfer');
    expect(uri.queryParameters['from'], '2026-09-12T13:00:00Z');
    expect(uri.toString(), isNot(contains('%3FpaymentMethod')));
  });
}
