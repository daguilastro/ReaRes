import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:zxing2/qrcode.dart' as zxing;

import '../../services/pairing_handshake.dart';
import '../../models/pairing_invitation.dart';

String? decodeQrImageBytes(Uint8List bytes) {
  try {
    final decoded = image.decodeImage(bytes);
    if (decoded == null) return null;
    final padding = (decoded.width ~/ 20).clamp(16, 64);
    final paddedWidth = decoded.width + padding * 2;
    final paddedHeight = decoded.height + padding * 2;
    final pixels = Int32List(paddedWidth * paddedHeight)
      ..fillRange(0, paddedWidth * paddedHeight, 0xFFFFFFFF);
    for (var y = 0; y < decoded.height; y++) {
      for (var x = 0; x < decoded.width; x++) {
        final pixel = decoded.getPixel(x, y);
        final transparent = pixel.a.toInt() < 128;
        pixels[(y + padding) * paddedWidth + x + padding] = transparent
            ? 0xFFFFFFFF
            : (0xFF << 24) |
                  (pixel.r.toInt() << 16) |
                  (pixel.g.toInt() << 8) |
                  pixel.b.toInt();
      }
    }
    final source = zxing.RGBLuminanceSource(paddedWidth, paddedHeight, pixels);
    return zxing.QRCodeReader()
        .decode(zxing.BinaryBitmap(zxing.HybridBinarizer(source)))
        .text;
  } on Object {
    return null;
  }
}

class PairingPage extends StatefulWidget {
  const PairingPage({
    super.key,
    required this.spanish,
    required this.onPaired,
    this.handshake = completePairingHandshake,
    this.handshakeTimeout = const Duration(seconds: 16),
  });

  final bool spanish;
  final VoidCallback onPaired;
  final Future<void> Function(PairingInvitation invitation) handshake;
  final Duration handshakeTimeout;

  @override
  State<PairingPage> createState() => _PairingPageState();
}

class _PairingPageState extends State<PairingPage> {
  bool _processing = false;
  bool _scanning = false;
  String? _error;
  bool get _mobile => Platform.isAndroid || Platform.isIOS;

  Future<void> _acceptRawValue(String? raw) async {
    if (_processing || raw == null) {
      if (raw == null) {
        debugPrint('Pairing QR: no se pudo decodificar la imagen.');
      }
      return;
    }
    final invitation = PairingInvitation.tryParse(raw);
    if (invitation == null) {
      debugPrint('Pairing QR: contenido inválido o invitación vencida.');
      return;
    }
    debugPrint('Pairing QR válido: ${invitation.host}:${invitation.port}');
    setState(() {
      _processing = true;
      _error = null;
    });
    try {
      await widget.handshake(invitation).timeout(widget.handshakeTimeout);
      debugPrint('Pairing mTLS completado correctamente.');
      if (mounted) widget.onPaired();
    } on Object catch (error, stackTrace) {
      debugPrint('Pairing mTLS falló: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _processing = false;
          _error = error is TimeoutException
              ? widget.spanish
                    ? 'El servidor no respondió. Verifica que siga encendido y que ambos dispositivos estén en la misma red.'
                    : 'The server did not respond. Check that it is running and both devices are on the same network.'
              : widget.spanish
              ? 'No se pudo completar el emparejamiento. Genera un QR nuevo e inténtalo otra vez.'
              : 'Pairing could not be completed. Generate a new QR and try again.';
        });
      }
    }
  }

  Future<void> _chooseQrImage() async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(
            label: 'QR image',
            extensions: ['png', 'jpg', 'jpeg', 'webp'],
          ),
        ],
      );
      if (file == null) return;
      debugPrint('Pairing QR: analizando ${file.name}.');
      final raw = decodeQrImageBytes(
        await file.readAsBytes().timeout(const Duration(seconds: 8)),
      );
      if (raw == null && mounted) {
        setState(() {
          _error = widget.spanish
              ? 'No se pudo leer un QR válido en esa imagen.'
              : 'No valid QR code could be read from that image.';
        });
      }
      await _acceptRawValue(raw);
    } on Object catch (error, stackTrace) {
      debugPrint('Pairing QR: no se pudo abrir la imagen: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (mounted) {
        setState(() {
          _processing = false;
          _error = widget.spanish
              ? 'No se pudo abrir o procesar la imagen.'
              : 'The image could not be opened or processed.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _mobile && _scanning ? _camera() : _upload()),
    );
  }

  Widget _camera() => Stack(
    fit: StackFit.expand,
    children: [
      MobileScanner(
        key: const ValueKey('pairing-camera'),
        onDetect: (capture) {
          for (final barcode in capture.barcodes) {
            if (PairingInvitation.tryParse(barcode.rawValue ?? '') != null) {
              _acceptRawValue(barcode.rawValue);
              break;
            }
          }
        },
      ),
      Center(
        child: Container(
          width: 260,
          height: 260,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 3),
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
      Positioned(
        left: 24,
        right: 24,
        top: 28,
        child: Text(
          widget.spanish ? 'Escanea el QR del servidor' : 'Scan the server QR',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 21,
            fontWeight: FontWeight.w700,
            shadows: [Shadow(blurRadius: 8)],
          ),
        ),
      ),
      Positioned(
        left: 18,
        top: 18,
        child: Material(
          color: const Color(0x99000000),
          shape: const CircleBorder(),
          child: IconButton(
            tooltip: widget.spanish ? 'Volver' : 'Back',
            color: Colors.white,
            onPressed: _processing
                ? null
                : () => setState(() {
                    _scanning = false;
                    _error = null;
                  }),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
        ),
      ),
      if (_processing)
        const ColoredBox(
          color: Color(0x66000000),
          child: Center(child: CircularProgressIndicator(color: Colors.white)),
        ),
      if (_error != null)
        Positioned(
          left: 24,
          right: 24,
          bottom: 30,
          child: _ErrorCard(message: _error!),
        ),
    ],
  );

  Widget _upload() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 500),
        child: Container(
          padding: const EdgeInsets.all(36),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Color(0x0B000000),
                blurRadius: 24,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.qr_code_2_rounded,
                size: 78,
                color: Color(0xFF8798AC),
              ),
              const SizedBox(height: 20),
              Text(
                widget.spanish
                    ? 'Selecciona el QR del servidor'
                    : 'Select the server QR',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF202020),
                ),
              ),
              const SizedBox(height: 9),
              Text(
                widget.spanish
                    ? _mobile
                          ? 'Carga una imagen del QR o escanéalo con la cámara.'
                          : 'Carga la imagen descargada desde la aplicación administrativa.'
                    : _mobile
                    ? 'Upload a QR image or scan it with the camera.'
                    : 'Upload the image downloaded from the admin application.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6D7075), fontSize: 14),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                key: const ValueKey('upload-pairing-qr'),
                onPressed: _processing ? null : _chooseQrImage,
                icon: _processing
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.upload_file_rounded),
                label: Text(
                  widget.spanish ? 'Escoger imagen QR' : 'Choose QR image',
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8798AC),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 16,
                  ),
                ),
              ),
              if (_mobile) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  key: const ValueKey('scan-pairing-qr'),
                  onPressed: _processing
                      ? null
                      : () => setState(() {
                          _scanning = true;
                          _error = null;
                        }),
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: Text(
                    widget.spanish ? 'Escanear con cámara' : 'Scan with camera',
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF65788F),
                    side: const BorderSide(color: Color(0xFF8798AC)),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 22,
                      vertical: 16,
                    ),
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 18),
                _ErrorCard(message: _error!),
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFFFEEEE),
    borderRadius: BorderRadius.circular(10),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFB64848)),
      ),
    ),
  );
}
