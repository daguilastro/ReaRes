import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr/qr.dart' as qr;

import '../../../services/admin_api.dart';

class PairDevicePage extends StatefulWidget {
  const PairDevicePage({
    super.key,
    required this.spanish,
    required this.token,
    this.createRequest = createDevicePairingRequest,
  });

  final bool spanish;
  final String token;
  final Future<DevicePairingRequest> Function(String token) createRequest;

  @override
  State<PairDevicePage> createState() => _PairDevicePageState();
}

class _PairDevicePageState extends State<PairDevicePage> {
  DevicePairingRequest? _request;
  Timer? _timer;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generate();
  }

  Future<void> _generate() async {
    _timer?.cancel();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final request = await widget.createRequest(widget.token);
      if (!mounted) return;
      setState(() {
        _request = request;
        _loading = false;
      });
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() {});
        if (_remaining == Duration.zero) _timer?.cancel();
      });
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = widget.spanish
              ? 'No se pudo crear la invitación.'
              : 'The pairing invitation could not be created.';
        });
      }
    }
  }

  Duration get _remaining {
    final difference =
        _request?.expiresAt.difference(DateTime.now()) ?? Duration.zero;
    return difference.isNegative ? Duration.zero : difference;
  }

  Future<void> _download() async {
    final request = _request;
    if (request == null || _remaining == Duration.zero) return;
    final qrMatrix = qr.QrImage(
      qr.QrCode.fromData(
        data: request.qrData,
        errorCorrectLevel: qr.QrErrorCorrectLevel.M,
      ),
    );
    const imageSize = 1024;
    const quietZoneModules = 4;
    final moduleSize =
        imageSize ~/ (qrMatrix.moduleCount + quietZoneModules * 2);
    final renderedSize =
        moduleSize * (qrMatrix.moduleCount + quietZoneModules * 2);
    final origin =
        (imageSize - renderedSize) ~/ 2 + quietZoneModules * moduleSize;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 1024, 1024),
        Paint()..color = Colors.white,
      );
    final darkPaint = Paint()
      ..color = const Color(0xFF222326)
      ..isAntiAlias = false;
    for (var row = 0; row < qrMatrix.moduleCount; row++) {
      for (var column = 0; column < qrMatrix.moduleCount; column++) {
        if (!qrMatrix.isDark(row, column)) continue;
        canvas.drawRect(
          Rect.fromLTWH(
            (origin + column * moduleSize).toDouble(),
            (origin + row * moduleSize).toDouble(),
            moduleSize.toDouble(),
            moduleSize.toDouble(),
          ),
          darkPaint,
        );
      }
    }
    final qrImage = await recorder.endRecording().toImage(imageSize, imageSize);
    final data = await qrImage.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) return;
    final location = await getSaveLocation(
      suggestedName: 'restaurant-pairing-qr.png',
    );
    if (location == null) return;
    final bytes = Uint8List.view(data.buffer);
    await XFile.fromData(
      bytes,
      mimeType: 'image/png',
      name: 'restaurant-pairing-qr.png',
    ).saveTo(location.path);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.spanish ? 'Código QR guardado.' : 'QR code saved.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    final seconds = _remaining.inSeconds;
    final expired = request != null && seconds == 0;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.spanish ? 'VINCULAR DISPOSITIVO' : 'PAIR DEVICE',
                style: const TextStyle(
                  color: Color(0xFF8798AC),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                widget.spanish ? 'Añadir un dispositivo' : 'Add a device',
                style: const TextStyle(
                  color: Color(0xFF222326),
                  fontSize: 29,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.spanish
                    ? 'Escanea este código desde el cliente. La invitación solo funciona una vez y vence en dos minutos.'
                    : 'Scan this code from the client. The invitation works once and expires in two minutes.',
                style: const TextStyle(color: Color(0xFF7A7D82), fontSize: 13),
              ),
              const SizedBox(height: 24),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(13),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x08000000),
                      blurRadius: 18,
                      offset: Offset(0, 7),
                    ),
                  ],
                ),
                child: _loading
                    ? const SizedBox(
                        height: 360,
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _error != null
                    ? SizedBox(
                        height: 360,
                        child: Center(
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                      )
                    : Column(
                        children: [
                          AnimatedOpacity(
                            duration: const Duration(milliseconds: 240),
                            opacity: expired ? .16 : 1,
                            child: QrImageView(
                              key: const ValueKey('pairing-qr'),
                              data: request!.qrData,
                              size: 280,
                              backgroundColor: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            expired
                                ? (widget.spanish
                                      ? 'Invitación vencida'
                                      : 'Invitation expired')
                                : '${widget.spanish ? 'Expira en' : 'Expires in'} '
                                      '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
                            key: const ValueKey('pairing-countdown'),
                            style: TextStyle(
                              color: expired
                                  ? Colors.red
                                  : const Color(0xFF52657A),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${request.host}:${request.port}',
                            style: const TextStyle(
                              color: Color(0xFF7A7D82),
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 22),
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              OutlinedButton.icon(
                                key: const ValueKey('new-pairing-qr'),
                                onPressed: _generate,
                                icon: const Icon(Icons.refresh_rounded),
                                label: Text(
                                  widget.spanish
                                      ? 'Crear otro QR'
                                      : 'Create another QR',
                                ),
                              ),
                              FilledButton.icon(
                                key: const ValueKey('download-pairing-qr'),
                                onPressed: expired ? null : _download,
                                icon: const Icon(Icons.download_rounded),
                                label: Text(
                                  widget.spanish
                                      ? 'Descargar QR'
                                      : 'Download QR',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
