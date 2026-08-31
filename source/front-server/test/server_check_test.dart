import 'package:flutter_test/flutter_test.dart';
import 'package:restaurante_server/services/server_check.dart';

void main() {
  test('reads both legacy and structured admin port files', () {
    expect(parseAdminRuntimePort('32100\n'), 32100);
    expect(
      parseAdminRuntimePort(
        '{"version":1,"adminPort":32100,"deviceHost":"192.168.1.25","devicePort":45600}',
      ),
      32100,
    );
  });
}
