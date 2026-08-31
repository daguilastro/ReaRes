import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:restaurante_front/views/pairing/pairing_page.dart';
import 'package:zxing2/qrcode.dart';

void main() {
  test('decodes a generated QR PNG through the desktop upload path', () {
    const payload = '{"version":1,"scheme":"https","host":"192.168.1.10"}';
    final matrix = Encoder.encode(payload, ErrorCorrectionLevel.m).matrix!;
    const scale = 10;
    const quietZone = 4;
    final output = image.Image(
      width: (matrix.width + quietZone * 2) * scale,
      height: (matrix.height + quietZone * 2) * scale,
    );
    image.fill(output, color: image.ColorRgb8(255, 255, 255));
    for (var y = 0; y < matrix.height; y++) {
      for (var x = 0; x < matrix.width; x++) {
        if (matrix.get(x, y) != 1) continue;
        image.fillRect(
          output,
          x1: (x + quietZone) * scale,
          y1: (y + quietZone) * scale,
          x2: (x + quietZone + 1) * scale - 1,
          y2: (y + quietZone + 1) * scale - 1,
          color: image.ColorRgb8(0, 0, 0),
        );
      }
    }

    expect(decodeQrImageBytes(image.encodePng(output)), payload);
  });
}
