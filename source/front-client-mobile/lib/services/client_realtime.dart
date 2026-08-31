import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/client_user.dart';
import 'paired_server_client.dart';

class ClientRealtimeEvent {
  const ClientRealtimeEvent({required this.type, this.roomId});

  final String type;
  final int? roomId;
}

class ClientRealtimeService {
  ClientRealtimeService(this.session);

  final ClientSession session;
  final _events = StreamController<ClientRealtimeEvent>.broadcast();
  final _subscriptions = <int>{};
  WebSocket? _socket;
  PairedServerClient? _server;
  Timer? _reconnectTimer;
  bool _closed = false;
  bool _connecting = false;

  Stream<ClientRealtimeEvent> get events => _events.stream;

  Future<void> start() async {
    _closed = false;
    await _connect();
  }

  void subscribe(int roomId) {
    _subscriptions.add(roomId);
    _send({'type': 'subscribe', 'roomId': roomId});
  }

  void unsubscribe(int roomId) {
    _subscriptions.remove(roomId);
    _send({'type': 'unsubscribe', 'roomId': roomId});
  }

  Future<void> _connect() async {
    if (_closed || _connecting || _socket != null) return;
    _connecting = true;
    PairedServerClient? server;
    try {
      server = await openPairedServerClient();
      final socket = await WebSocket.connect(
        server.uri('/realtime').replace(scheme: 'wss').toString(),
        headers: {HttpHeaders.authorizationHeader: 'Bearer ${session.token}'},
        customClient: server.http,
      ).timeout(const Duration(seconds: 8));
      if (_closed) {
        await socket.close();
        server.close();
        return;
      }
      _server = server;
      _socket = socket;
      socket.listen(
        _receive,
        onError: (_) => _disconnected(socket),
        onDone: () => _disconnected(socket),
        cancelOnError: true,
      );
      for (final roomId in _subscriptions) {
        _send({'type': 'subscribe', 'roomId': roomId});
      }
    } on Object {
      server?.close();
      _scheduleReconnect();
    } finally {
      _connecting = false;
    }
  }

  void _receive(dynamic raw) {
    if (raw is! String) return;
    try {
      final value = jsonDecode(raw);
      if (value is! Map<String, dynamic> || value['type'] is! String) return;
      final roomId = value['roomId'];
      _events.add(
        ClientRealtimeEvent(
          type: value['type'] as String,
          roomId: roomId is int ? roomId : null,
        ),
      );
    } on FormatException {
      // Se ignoran mensajes que no pertenezcan al protocolo de la aplicación.
    }
  }

  void _send(Map<String, dynamic> message) {
    if (_socket?.readyState == WebSocket.open) {
      _socket!.add(jsonEncode(message));
    }
  }

  void _disconnected(WebSocket socket) {
    if (!identical(socket, _socket)) return;
    _socket = null;
    _server?.close();
    _server = null;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_closed || _reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 2), _connect);
  }

  Future<void> dispose() async {
    _closed = true;
    _reconnectTimer?.cancel();
    final socket = _socket;
    _socket = null;
    if (socket != null) await socket.close(1000, 'Client closed');
    _server?.close();
    _server = null;
    await _events.close();
  }
}
