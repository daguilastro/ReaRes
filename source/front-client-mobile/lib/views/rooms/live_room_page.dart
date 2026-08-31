import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/client_room.dart';
import '../../models/client_user.dart';
import '../../models/client_order.dart';
import '../../services/client_realtime.dart';
import '../../services/client_rooms_api.dart';
import 'bill_order_dialog.dart';
import 'delivery_order_dialog.dart';
import 'daily_orders_dialog.dart';
import 'live_room_controller.dart';
import 'order_editor_dialog.dart';

enum _LiveToolMode { edit, bill, select }

typedef LoadLiveLayout =
    Future<LiveRoomLayout> Function({
      required ClientSession session,
      required int roomId,
    });
typedef SaveLiveLayout =
    Future<LiveRoomLayout> Function({
      required ClientSession session,
      required int roomId,
      required LiveRoomLayout layout,
    });
typedef LoadRoomOrders =
    Future<List<ClientOrder>> Function({
      required ClientSession session,
      required int roomId,
    });
typedef LoadTodayRoomOrders = LoadRoomOrders;
typedef LoadRoomMenus =
    Future<List<ClientRoomMenu>> Function({
      required ClientSession session,
      required int roomId,
    });
typedef WriteTableOrder =
    Future<ClientOrder> Function({
      required ClientSession session,
      required int roomId,
      required int tableId,
      int? orderId,
      required String description,
      required List<OrderItemWrite> items,
    });
typedef SetOrderEating =
    Future<ClientOrder> Function({
      required ClientSession session,
      required int roomId,
      required int orderId,
    });
typedef DeliverOrderItem =
    Future<ClientOrder> Function({
      required ClientSession session,
      required int roomId,
      required int orderId,
      required int itemId,
      required int unitIndex,
    });
typedef UndoDeliveredOrderItem = DeliverOrderItem;
typedef SetOrderClosed =
    Future<ClientOrder> Function({
      required ClientSession session,
      required int roomId,
      required int orderId,
    });

class LiveRoomPage extends StatefulWidget {
  const LiveRoomPage({
    super.key,
    required this.session,
    required this.room,
    required this.spanish,
    this.realtime,
    this.loadLayout = getLiveRoomLayout,
    this.saveLayout = saveLiveRoomLayout,
    this.loadOrders = getRoomOrders,
    this.loadTodayOrders = getTodayRoomOrders,
    this.loadMenus = getRoomMenus,
    this.writeOrder = saveTableOrder,
    this.setEating = markOrderEating,
    this.deliverItem = deliverOrderItem,
    this.undoDeliveredItem = undoDeliveredOrderItem,
    this.setClosed = markOrderClosed,
  });

  final ClientSession session;
  final ClientRoomSummary room;
  final bool spanish;
  final ClientRealtimeService? realtime;
  final LoadLiveLayout loadLayout;
  final SaveLiveLayout saveLayout;
  final LoadRoomOrders loadOrders;
  final LoadTodayRoomOrders loadTodayOrders;
  final LoadRoomMenus loadMenus;
  final WriteTableOrder writeOrder;
  final SetOrderEating setEating;
  final DeliverOrderItem deliverItem;
  final UndoDeliveredOrderItem undoDeliveredItem;
  final SetOrderClosed setClosed;

  @override
  State<LiveRoomPage> createState() => _LiveRoomPageState();
}

class _LiveRoomPageState extends State<LiveRoomPage> {
  static const _canvasOrigin = Offset(12000, 12000);
  static const _canvasExtent = 30000.0;
  final _layout = LiveRoomController();
  final _camera = TransformationController();
  final _viewportKey = GlobalKey();
  StreamSubscription<ClientRealtimeEvent>? _events;
  bool _loading = true;
  bool _saving = false;
  bool _reloadPending = false;
  String? _error;
  int? _activePointer;
  int? _activeTable;
  bool _pointerMoved = false;
  Offset _dragDelta = Offset.zero;
  Offset _lastGlobalPosition = Offset.zero;
  double _rotation = 0;
  List<ClientOrder> _orders = [];
  _LiveToolMode _mode = _LiveToolMode.select;

  bool get _desktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  bool get _canInteract => !_loading && !_saving;

  @override
  void initState() {
    super.initState();
    widget.realtime?.subscribe(widget.room.id);
    _events = widget.realtime?.events.listen(_handleRealtimeEvent);
    _load();
  }

  void _handleRealtimeEvent(ClientRealtimeEvent event) {
    if ((event.type == 'room-layout-changed' ||
            event.type == 'room-orders-changed') &&
        event.roomId == widget.room.id) {
      if (_saving ||
          _layout.dirty ||
          _layout.interaction != LiveLayoutInteraction.normal) {
        _reloadPending = true;
      } else {
        _reload(realtime: true);
      }
    } else if (event.type == 'room-assignments-changed') {
      _reload(realtime: true, closeWhenUnauthorized: true);
    }
  }

  Future<void> _load() async {
    try {
      final values = await Future.wait([
        widget.loadLayout(session: widget.session, roomId: widget.room.id),
        widget.loadOrders(session: widget.session, roomId: widget.room.id),
      ]);
      final layout = values[0] as LiveRoomLayout;
      if (mounted) {
        _layout.load(layout);
        _orders = values[1] as List<ClientOrder>;
        setState(() {
          _loading = false;
          _error = null;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusLayout();
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = widget.spanish
              ? 'No se pudo cargar el salón.'
              : 'The room could not be loaded.';
        });
      }
    }
  }

  Future<void> _reload({
    bool realtime = false,
    bool closeWhenUnauthorized = false,
  }) async {
    try {
      final values = await Future.wait([
        widget.loadLayout(session: widget.session, roomId: widget.room.id),
        widget.loadOrders(session: widget.session, roomId: widget.room.id),
      ]);
      final layout = values[0] as LiveRoomLayout;
      if (!mounted) return;
      _layout.replaceFromRealtime(layout);
      _orders = values[1] as List<ClientOrder>;
      if (!realtime) setState(() => _error = null);
    } on Object {
      if (!mounted) return;
      if (closeWhenUnauthorized && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else if (!realtime) {
        setState(() {
          _error = widget.spanish
              ? 'No se pudo actualizar el salón.'
              : 'The room could not be refreshed.';
        });
      }
    }
  }

  Future<void> _persist() async {
    if (_saving || !_layout.dirty) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.saveLayout(
        session: widget.session,
        roomId: widget.room.id,
        layout: _layout.snapshot(),
      );
      if (!mounted) return;
      _layout.acceptSaved(saved);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.spanish
                  ? 'No se pudo guardar el cambio.'
                  : 'The change could not be saved.',
            ),
            backgroundColor: const Color(0xFFB64A4A),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
        if (_reloadPending) {
          _reloadPending = false;
          _reload(realtime: true);
        }
      }
    }
  }

  @override
  void dispose() {
    widget.realtime?.unsubscribe(widget.room.id);
    _events?.cancel();
    _camera.dispose();
    _layout.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFFAF9F6),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: _layout,
        builder: (context, _) => Column(
          children: [
            _header(),
            const Divider(height: 1, color: Color(0xFFE7E5E1)),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? _errorView()
                  : Stack(
                      children: [
                        Positioned.fill(child: _canvas()),
                        Positioned(left: 16, top: 16, child: _historyButton()),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 18,
                          child: Center(child: _tools()),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _historyButton() => Material(
    elevation: 5,
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
    child: IconButton(
      key: const ValueKey('daily-orders'),
      tooltip: widget.spanish ? 'Órdenes del día' : 'Today’s orders',
      onPressed: _openDailyOrders,
      icon: const Icon(Icons.history_rounded),
    ),
  );

  Future<void> _openDailyOrders() async {
    try {
      final orders = await widget.loadTodayOrders(
        session: widget.session,
        roomId: widget.room.id,
      );
      if (!mounted) return;
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Daily orders',
        barrierColor: Colors.black45,
        transitionDuration: const Duration(milliseconds: 180),
        transitionBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (_, _, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: DailyOrdersDialog(spanish: widget.spanish, orders: orders),
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.spanish
                ? 'No se pudo cargar el historial del día.'
                : 'Could not load today’s history.',
          ),
        ),
      );
    }
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    child: Row(
      children: [
        IconButton(
          key: const ValueKey('back-to-assigned-rooms'),
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            widget.room.name,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F0E8),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_saving) ...[
                const SizedBox.square(
                  dimension: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 7),
              ] else ...[
                const Icon(Icons.circle, size: 8, color: Color(0xFF5B9B66)),
                const SizedBox(width: 7),
              ],
              Text(
                _saving
                    ? (widget.spanish ? 'Guardando' : 'Saving')
                    : 'Live View',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _saving ? null : _reload,
          tooltip: widget.spanish ? 'Actualizar' : 'Refresh',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
  );

  Widget _errorView() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(_error!, style: const TextStyle(color: Color(0xFFC94E4E))),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(widget.spanish ? 'Reintentar' : 'Retry'),
        ),
      ],
    ),
  );

  Widget _canvas() => ClipRect(
    key: _viewportKey,
    child: InteractiveViewer(
      key: const ValueKey('live-room-canvas'),
      transformationController: _camera,
      alignment: Alignment.topLeft,
      minScale: .35,
      maxScale: 3.5,
      boundaryMargin: const EdgeInsets.all(10000),
      constrained: false,
      panEnabled: _layout.interaction == LiveLayoutInteraction.normal,
      scaleEnabled: _layout.interaction == LiveLayoutInteraction.normal,
      child: Transform.rotate(
        angle: _rotation,
        alignment: Alignment.topLeft,
        origin: _canvasOrigin + _layout.contentBounds.center,
        child: SizedBox(
          width: _canvasExtent,
          height: _canvasExtent,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  key: const ValueKey('live-layout-background'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _canInteract ? _layout.clearSelection : null,
                ),
              ),
              for (final wall in _layout.walls) _wall(wall),
              for (final table in _layout.tables) _table(table),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _wall(LiveRoomWall wall) => Positioned(
    left: _canvasOrigin.dx + wall.x,
    top: _canvasOrigin.dy + wall.y,
    width: wall.width,
    height: wall.height,
    child: Transform.rotate(
      angle: wall.rotation,
      child: const ColoredBox(color: Color(0xFF74818D)),
    ),
  );

  Widget _table(LiveRoomTable table) {
    final selected = _layout.selectedTableIds.contains(table.id);
    final invalid = selected && _layout.invalidPlacement;
    final grouped = _layout.groupForTable(table.id) != null;
    return Positioned(
      left: _canvasOrigin.dx + table.x,
      top: _canvasOrigin.dy + table.y,
      width: table.width,
      height: table.height,
      child: Transform.rotate(
        angle: table.rotation,
        child: Listener(
          key: ValueKey('live-table-${table.id}'),
          onPointerDown: _canInteract && _desktop
              ? (event) => _pointerDown(event, table.id)
              : null,
          onPointerMove: _canInteract && _desktop ? _pointerMove : null,
          onPointerUp: _canInteract && _desktop ? _pointerUp : null,
          onPointerCancel: _canInteract && _desktop ? _pointerCancel : null,
          child: GestureDetector(
            onTap: _canInteract && !_desktop
                ? () => _activateTable(table)
                : null,
            onLongPressStart: _canInteract && !_desktop
                ? (details) {
                    HapticFeedback.mediumImpact();
                    _dragDelta = Offset.zero;
                    _lastGlobalPosition = details.globalPosition;
                    _layout.beginMove(table.id);
                  }
                : null,
            onLongPressMoveUpdate: _canInteract && !_desktop
                ? (details) {
                    final delta = details.globalPosition - _lastGlobalPosition;
                    _lastGlobalPosition = details.globalPosition;
                    _dragDelta += _logicalDelta(delta);
                    _layout.moveBy(_dragDelta);
                  }
                : null,
            onLongPressEnd: _canInteract && !_desktop
                ? (_) {
                    if (_layout.endMove()) _persist();
                  }
                : null,
            child: MouseRegion(
              cursor: _canInteract
                  ? SystemMouseCursors.move
                  : MouseCursor.defer,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 100),
                decoration: BoxDecoration(
                  color: invalid
                      ? const Color(0xFFFFE4E2)
                      : table.status == 'waiting'
                      ? const Color(0xFFFFF1B8)
                      : table.status == 'eating'
                      ? const Color(0xFFDDF1D9)
                      : const Color(0xFFF7F6F4),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: invalid
                        ? const Color(0xFFE14B43)
                        : selected
                        ? const Color(0xFF4C9EF8)
                        : const Color(0xFFD4D8DC),
                    width: selected ? 2 : 1,
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x10000000), blurRadius: 7),
                  ],
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (grouped) ...[
                        const Icon(
                          Icons.link,
                          size: 14,
                          color: Color(0xFF6D8DAC),
                        ),
                        const SizedBox(width: 4),
                      ],
                      Flexible(
                        child: Text(
                          table.identifier,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? const Color(0xFF4C9EF8)
                                : const Color(0xFF6D7075),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _pointerDown(PointerDownEvent event, int tableId) {
    if (_activePointer != null) return;
    _activePointer = event.pointer;
    _activeTable = tableId;
    _pointerMoved = false;
    _dragDelta = Offset.zero;
    _lastGlobalPosition = event.position;
    _layout.pressTable();
  }

  void _pointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _activeTable == null) return;
    final delta = event.position - _lastGlobalPosition;
    _lastGlobalPosition = event.position;
    if (!_pointerMoved && delta.distanceSquared > 0) {
      _pointerMoved = true;
      _layout.beginMove(_activeTable!);
    }
    if (_pointerMoved) {
      _dragDelta += _logicalDelta(delta);
      _layout.moveBy(_dragDelta);
    }
  }

  void _pointerUp(PointerUpEvent event) {
    if (_activePointer != event.pointer || _activeTable == null) return;
    if (_pointerMoved) {
      if (_layout.endMove()) _persist();
    } else {
      _layout.cancelTablePress();
      final table = _layout.tables.firstWhere(
        (item) => item.id == _activeTable,
      );
      _activateTable(table);
    }
    _clearPointer();
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    if (_pointerMoved) _layout.cancelMove();
    _layout.cancelTablePress();
    _clearPointer();
  }

  void _clearPointer() {
    _activePointer = null;
    _activeTable = null;
    _pointerMoved = false;
  }

  Offset _logicalDelta(Offset screenDelta) {
    final scale = _camera.value.getMaxScaleOnAxis();
    final dx = screenDelta.dx / scale;
    final dy = screenDelta.dy / scale;
    return Offset(
      dx * math.cos(_rotation) + dy * math.sin(_rotation),
      -dx * math.sin(_rotation) + dy * math.cos(_rotation),
    );
  }

  void _focusLayout() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final bounds = _layout.contentBounds.inflate(80);
    final availableWidth = math.max(1.0, viewport.size.width - 48);
    final availableHeight = math.max(1.0, viewport.size.height - 48);
    final scale = math
        .min(availableWidth / bounds.width, availableHeight / bounds.height)
        .clamp(.35, 1.35)
        .toDouble();
    final renderedCenter = bounds.center + _canvasOrigin;
    final translation = Offset(
      viewport.size.width / 2 - renderedCenter.dx * scale,
      viewport.size.height / 2 - renderedCenter.dy * scale,
    );
    if (_rotation != 0) setState(() => _rotation = 0);
    _camera.value = Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0, 1)
      ..scaleByDouble(scale, scale, scale, 1);
  }

  void _rotateView() => setState(() => _rotation -= math.pi / 2);

  Widget _tools() => Material(
    key: const ValueKey('live-bottom-tools'),
    color: Colors.white,
    elevation: 4,
    borderRadius: BorderRadius.circular(20),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _modeButton(
          key: const ValueKey('live-mode-edit'),
          mode: _LiveToolMode.edit,
          tooltip: widget.spanish ? 'Editar pedido' : 'Edit order',
          icon: Icons.edit_outlined,
        ),
        _modeButton(
          key: const ValueKey('live-mode-bill'),
          mode: _LiveToolMode.bill,
          tooltip: widget.spanish ? 'Facturar' : 'Bill',
          icon: Icons.receipt_long_outlined,
        ),
        _modeButton(
          key: const ValueKey('live-mode-select'),
          mode: _LiveToolMode.select,
          tooltip: widget.spanish ? 'Seleccionar' : 'Select',
          icon: Icons.touch_app_outlined,
        ),
        IconButton(
          key: const ValueKey('toggle-live-table-link'),
          onPressed: _canInteract && _layout.canToggleGroup
              ? () {
                  _layout.toggleSelectedGroup();
                  _persist();
                }
              : null,
          tooltip: _layout.canUngroup
              ? (widget.spanish ? 'Desenlazar selección' : 'Unlink selection')
              : (widget.spanish ? 'Enlazar selección' : 'Link selection'),
          icon: Icon(_layout.canUngroup ? Icons.link_off : Icons.link),
        ),
        IconButton(
          key: const ValueKey('rotate-live-room'),
          onPressed: _rotateView,
          tooltip: widget.spanish ? 'Rotar vista' : 'Rotate view',
          icon: const Icon(Icons.rotate_left),
        ),
        IconButton(
          key: const ValueKey('fit-live-room'),
          onPressed: _focusLayout,
          tooltip: widget.spanish ? 'Ver salón completo' : 'Fit to screen',
          icon: const Icon(Icons.center_focus_strong),
        ),
      ],
    ),
  );

  Widget _modeButton({
    required Key key,
    required _LiveToolMode mode,
    required String tooltip,
    required IconData icon,
  }) => IconButton(
    key: key,
    isSelected: _mode == mode,
    style: IconButton.styleFrom(
      backgroundColor: _mode == mode ? const Color(0xFFDCE8F5) : null,
    ),
    onPressed: () {
      setState(() => _mode = mode);
      if (mode == _LiveToolMode.edit) _layout.clearSelection();
    },
    tooltip: tooltip,
    icon: Icon(icon),
  );

  void _activateTable(LiveRoomTable table) {
    switch (_mode) {
      case _LiveToolMode.edit:
        _openOrderEditor(table.id);
      case _LiveToolMode.bill:
        _layout.selectTableOrGroup(table.id);
        _openBillDialog(table.id);
      case _LiveToolMode.select:
        _layout.toggleSelection(table.id);
        _openDeliveryDialog(table);
    }
  }

  ClientOrder? _orderForTable(int tableId) {
    final groupId = _layout.groupForTable(tableId)?.id;
    return _orders.where((order) {
      if (groupId != null) return order.tableGroupId == groupId;
      return order.tableGroupId == null && order.tableId == tableId;
    }).firstOrNull;
  }

  Future<void> _openDeliveryDialog(LiveRoomTable table) async {
    final order = _orderForTable(table.id);
    if (table.status != 'waiting' || order == null || !mounted) return;
    final group = _layout.groupForTable(table.id);
    final tableIds = group?.tableIds ?? [table.id];
    final tableLabel = _layout.tables
        .where((candidate) => tableIds.contains(candidate.id))
        .map((candidate) => candidate.identifier)
        .join(' + ');
    final editRequested = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Order delivery',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween(begin: .985, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      pageBuilder: (_, _, _) => Padding(
        padding: const EdgeInsets.all(18),
        child: DeliveryOrderDialog(
          spanish: widget.spanish,
          tableLabel: tableLabel,
          initialOrder: order,
          onDeliver: (itemId, unitIndex) => widget.deliverItem(
            session: widget.session,
            roomId: widget.room.id,
            orderId: order.id,
            itemId: itemId,
            unitIndex: unitIndex,
          ),
          onUndoDelivery: (itemId, unitIndex) => widget.undoDeliveredItem(
            session: widget.session,
            roomId: widget.room.id,
            orderId: order.id,
            itemId: itemId,
            unitIndex: unitIndex,
          ),
          onEditOrder: () => Navigator.pop(context, true),
        ),
      ),
    );
    await _reload();
    if (editRequested == true && mounted) {
      await _openOrderEditor(table.id);
    }
  }

  Future<void> _openOrderEditor(int clickedTableId) async {
    final group = _layout.groupForTable(clickedTableId);
    final tableIds = group?.tableIds ?? [clickedTableId];
    final existingOrder = _orders.where((order) {
      if (group != null) return order.tableGroupId == group.id;
      return order.tableGroupId == null && order.tableId == clickedTableId;
    }).firstOrNull;
    final tableId =
        existingOrder?.tableId ??
        tableIds.reduce((first, second) => first < second ? first : second);
    final labels = _layout.tables
        .where((table) => tableIds.contains(table.id))
        .map((table) => table.identifier)
        .toList();
    final tableLabel = labels.join(' + ');
    try {
      final menus = await widget.loadMenus(
        session: widget.session,
        roomId: widget.room.id,
      );
      if (!mounted) return;
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Order editor',
        barrierColor: Colors.black45,
        transitionDuration: const Duration(milliseconds: 180),
        transitionBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (_, _, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: OrderEditorDialog(
            spanish: widget.spanish,
            tableLabel: tableLabel,
            menus: menus,
            existingOrder: existingOrder,
            onSubmit: (description, items) async {
              await widget.writeOrder(
                session: widget.session,
                roomId: widget.room.id,
                tableId: tableId,
                orderId: existingOrder?.id,
                description: description,
                items: items,
              );
            },
          ),
        ),
      );
      await _reload();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFB64A4A),
            content: Text(
              widget.spanish
                  ? 'No se pudo abrir el pedido.'
                  : 'Could not open order.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _openBillDialog(int clickedTableId) async {
    final group = _layout.groupForTable(clickedTableId);
    final tableIds = group?.tableIds ?? [clickedTableId];
    final order = _orders.where((value) {
      if (group != null) return value.tableGroupId == group.id;
      return value.tableGroupId == null && value.tableId == clickedTableId;
    }).firstOrNull;
    if (order == null || !mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB64A4A),
          content: Text(
            widget.spanish
                ? 'No hay pedido activo para facturar.'
                : 'There is no active order to bill.',
          ),
        ),
      );
      return;
    }
    final hasPendingItems = order.items.any(
      (item) => item.deliveredQuantity < item.quantity,
    );
    if (order.status != 'eating' || hasPendingItems) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB68232),
          content: Text(
            widget.spanish
                ? 'Solo puedes facturar cuando todos los productos hayan sido entregados y la mesa esté comiendo.'
                : 'You can only bill after every item is delivered and the table is eating.',
          ),
        ),
      );
      return;
    }

    final labels = _layout.tables
        .where((table) => tableIds.contains(table.id))
        .map((table) => table.identifier)
        .toList();
    final tableLabel = labels.join(' + ');

    try {
      final menus = await widget.loadMenus(
        session: widget.session,
        roomId: widget.room.id,
      );
      if (!mounted) return;
      final productsById = {
        for (final menu in menus)
          for (final category in menu.categories)
            for (final product in category.products) product.id: product,
      };

      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierLabel: 'Order bill',
        barrierColor: Colors.black45,
        transitionDuration: const Duration(milliseconds: 180),
        transitionBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (_, _, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: BillOrderDialog(
            spanish: widget.spanish,
            tableLabel: tableLabel,
            order: order,
            productsById: productsById,
            onBill: () => widget.setClosed(
              session: widget.session,
              roomId: widget.room.id,
              orderId: order.id,
            ),
          ),
        ),
      );
      await _reload();
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB64A4A),
          content: Text(
            widget.spanish
                ? 'No se pudo abrir la caja de esta mesa.'
                : 'Could not open the cashier view for this table.',
          ),
        ),
      );
    }
  }
}
