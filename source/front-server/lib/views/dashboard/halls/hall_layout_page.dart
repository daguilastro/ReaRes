import 'dart:async';
import 'dart:math' as math;
import 'dart:io';

import 'package:flutter/gestures.dart' show kPrimaryMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../services/admin_api.dart';
import 'room_layout_controller.dart';
import 'room_layout_models.dart';

typedef LoadRoomLayout =
    Future<RoomLayoutModel> Function({
      required String token,
      required int roomId,
    });
typedef SaveRoomLayout =
    Future<RoomLayoutModel> Function({
      required String token,
      required int roomId,
      required RoomLayoutModel layout,
    });

enum HallViewMode { live, edit }

class HallLayoutPage extends StatefulWidget {
  const HallLayoutPage({
    super.key,
    required this.spanish,
    required this.token,
    this.roomId = 1,
    this.isAdmin = true,
    this.loadLayout = getRoomLayout,
    this.saveLayout = saveRoomLayout,
    this.onBack,
  });

  final bool spanish;
  final String token;
  final int roomId;
  final bool isAdmin;
  final LoadRoomLayout loadLayout;
  final SaveRoomLayout saveLayout;
  final VoidCallback? onBack;

  @override
  State<HallLayoutPage> createState() => _HallLayoutPageState();
}

class _HallLayoutPageState extends State<HallLayoutPage> {
  static const _canvasOrigin = Offset(12000, 12000);
  static const _canvasExtent = 30000.0;
  final _layout = RoomLayoutController();
  final _camera = TransformationController();
  final _layoutSpaceKey = GlobalKey();
  final _viewportKey = GlobalKey();
  HallViewMode _mode = HallViewMode.edit;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  double _rotation = 0;
  Offset _dragDelta = Offset.zero;
  Offset _resizeDelta = Offset.zero;
  Offset _lastGlobalPosition = Offset.zero;
  int? _activeDesktopPointer;
  int? _activeDesktopTable;
  bool _desktopTableMoved = false;
  _CopiedLayoutObject? _copiedObject;
  Offset? _lastPointerPosition;
  StreamSubscription<AdminActivity>? _activitySubscription;

  bool get _es => widget.spanish;
  bool get _editing => widget.isAdmin && _mode == HallViewMode.edit;
  bool get _editingTables =>
      _editing && _layout.interaction != LayoutInteraction.editingWalls;
  bool get _desktop =>
      Platform.isLinux || Platform.isMacOS || Platform.isWindows;

  @override
  void initState() {
    super.initState();
    if (!widget.isAdmin) _mode = HallViewMode.live;
    _activitySubscription = watchAdminActivities(widget.token).listen((
      activity,
    ) {
      if (activity.roomId == widget.roomId &&
          _mode == HallViewMode.live &&
          !_layout.dirty) {
        _load();
      }
    }, onError: (_) {});
    _load();
  }

  @override
  void didUpdateWidget(covariant HallLayoutPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.isAdmin && _mode != HallViewMode.live) {
      _mode = HallViewMode.live;
    }
    if (oldWidget.roomId != widget.roomId ||
        oldWidget.token != widget.token ||
        oldWidget.loadLayout != widget.loadLayout) {
      _load();
    }
  }

  @override
  void dispose() {
    _activitySubscription?.cancel();
    _camera.dispose();
    _layout.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var loadedSuccessfully = false;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await widget.loadLayout(
        token: widget.token,
        roomId: widget.roomId,
      );
      _layout.load(loaded);
      loadedSuccessfully = true;
    } on Object {
      _error = _es
          ? 'No se pudo cargar el salón.'
          : 'The room could not be loaded.';
    } finally {
      if (mounted) {
        setState(() => _loading = false);
        if (loadedSuccessfully) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _focusLayout();
          });
        }
      }
    }
  }

  Future<void> _save() async {
    if (_saving || !_layout.dirty) return;
    setState(() => _saving = true);
    try {
      final saved = await widget.saveLayout(
        token: widget.token,
        roomId: widget.roomId,
        layout: _layout.snapshot(),
      );
      _layout.acceptSaved(saved);
      if (mounted) {
        _message(_es ? 'Cambios guardados.' : 'Changes saved.');
      }
    } on Object {
      if (mounted) {
        _message(
          _es
              ? 'No se pudo guardar el layout.'
              : 'The layout could not be saved.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error
            ? const Color(0xFFB64A4A)
            : const Color(0xFF52677D),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text(_es ? 'Reintentar' : 'Retry'),
            ),
          ],
        ),
      );
    }
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyC, control: true):
            _copySelection,
        const SingleActivator(LogicalKeyboardKey.keyV, control: true): () =>
            _pasteCopied(_lastPointerPosition ?? _visibleLayoutCenter()),
      },
      child: Focus(
        autofocus: true,
        child: AnimatedBuilder(
          animation: _layout,
          builder: (context, _) => ColoredBox(
            color: const Color(0xFFFAF9F6),
            child: Column(
              children: [
                _header(),
                const Divider(height: 1, color: Color(0xFFE7E5E1)),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final compact = constraints.maxWidth < 720;
                      return Stack(
                        children: [
                          Positioned.fill(child: _canvas()),
                          if (_editing)
                            Positioned(
                              right: compact ? 14 : 22,
                              bottom: compact ? 76 : null,
                              top: compact ? null : 24,
                              child: _editTools(compact),
                            ),
                          Positioned(
                            bottom: 14,
                            left: 0,
                            right: 0,
                            child: Center(child: _cameraTools()),
                          ),
                          if (_mode == HallViewMode.live)
                            Positioned(
                              left: 18,
                              bottom: 18,
                              child: _LiveBadge(spanish: _es),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
    child: Wrap(
      spacing: 12,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (widget.onBack != null)
          IconButton(
            key: const ValueKey('back-to-rooms'),
            onPressed: widget.onBack,
            tooltip: _es ? 'Volver a salones' : 'Back to rooms',
            icon: const Icon(Icons.arrow_back),
          ),
        SizedBox(
          width: 220,
          child: Text(
            _layout.snapshot().roomName,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
        ),
        SegmentedButton<HallViewMode>(
          key: const ValueKey('hall-view-mode'),
          segments: [
            ButtonSegment(
              value: HallViewMode.live,
              label: Text(_es ? 'Vista en vivo' : 'Live View'),
            ),
            if (widget.isAdmin)
              ButtonSegment(
                value: HallViewMode.edit,
                label: Text(_es ? 'Editar layout' : 'Edit Layout'),
              ),
          ],
          selected: {_mode},
          onSelectionChanged: (selection) {
            setState(() => _mode = selection.first);
            if (_mode == HallViewMode.live) _load();
          },
          showSelectedIcon: true,
        ),
        if (_editing) ...[
          TextButton(
            key: const ValueKey('cancel-layout'),
            onPressed: _layout.dirty ? _layout.cancel : null,
            child: Text(_es ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton.icon(
            key: const ValueKey('save-layout'),
            onPressed: _layout.dirty && !_saving ? _save : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF52677D),
            ),
            icon: _saving
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.save_outlined, size: 19),
            label: Text(_es ? 'Guardar cambios' : 'Save Changes'),
          ),
        ],
      ],
    ),
  );

  Widget _canvas() => ClipRect(
    key: _viewportKey,
    child: MouseRegion(
      onHover: (event) {
        final position = _layoutPosition(event.position);
        if (position != null) _lastPointerPosition = position;
      },
      child: InteractiveViewer(
        key: const ValueKey('room-layout-canvas'),
        transformationController: _camera,
        alignment: Alignment.topLeft,
        minScale: .35,
        maxScale: 3.5,
        boundaryMargin: const EdgeInsets.all(10000),
        panEnabled:
            _layout.interaction == LayoutInteraction.normal || !_editing,
        scaleEnabled:
            _layout.interaction == LayoutInteraction.normal || !_editing,
        constrained: false,
        child: Transform.rotate(
          angle: _rotation,
          child: SizedBox(
            key: _layoutSpaceKey,
            width: _canvasExtent,
            height: _canvasExtent,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    key: const ValueKey('layout-background'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _editing ? _layout.clearSelection : null,
                    onSecondaryTapDown: _editing
                        ? _showBackgroundContextMenu
                        : null,
                  ),
                ),
                for (final wall in _layout.walls) _wall(wall),
                for (final table in _layout.tables) _table(table),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _wall(RoomWallModel wall) => Positioned(
    left: _canvasOrigin.dx + wall.x - 40,
    top: _canvasOrigin.dy + wall.y - 40,
    width: wall.width + 80,
    height: wall.height + 80,
    child: Transform.rotate(
      angle: wall.rotation,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 40,
            top: 40,
            width: wall.width,
            height: wall.height,
            child: GestureDetector(
              onTap: _editing ? () => _layout.selectWall(wall.id) : null,
              onSecondaryTapDown: _editing
                  ? (details) => _showObjectContextMenu(
                      details.globalPosition,
                      wallId: wall.id,
                    )
                  : null,
              onPanStart: _editing
                  ? (details) {
                      _dragDelta = Offset.zero;
                      _lastGlobalPosition = details.globalPosition;
                      _layout.beginWallMove(wall.id);
                    }
                  : null,
              onPanUpdate: _editing
                  ? (details) {
                      final delta =
                          details.globalPosition - _lastGlobalPosition;
                      _lastGlobalPosition = details.globalPosition;
                      _dragDelta += _logicalDelta(delta);
                      _layout.moveWall(wall.id, _dragDelta);
                    }
                  : null,
              onPanEnd: _editing ? (_) => _layout.finishWallEditing() : null,
              onPanCancel: _editing ? _layout.cancelWallMove : null,
              child: MouseRegion(
                cursor: _editing ? SystemMouseCursors.move : MouseCursor.defer,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: _layout.selectedWallId == wall.id
                        ? const Color(0xFF5A7898)
                        : const Color(0xFF74818D),
                    border: _layout.selectedWallId == wall.id
                        ? Border.all(color: const Color(0xFF4C9EF8), width: 2)
                        : null,
                  ),
                ),
              ),
            ),
          ),
          if (_editing && _layout.selectedWallId == wall.id) ...[
            Positioned(
              left: 40 + wall.width - 7,
              top: 40 + wall.height - 7,
              child: GestureDetector(
                onPanStart: (details) {
                  _resizeDelta = Offset.zero;
                  _lastGlobalPosition = details.globalPosition;
                  _layout.beginWallResize(wall.id);
                },
                onPanUpdate: (details) {
                  final delta = details.globalPosition - _lastGlobalPosition;
                  _lastGlobalPosition = details.globalPosition;
                  _resizeDelta += _objectDelta(delta, wall.rotation);
                  _layout.resizeWallBy(_resizeDelta);
                },
                onPanEnd: (_) => _layout.endWallResize(),
                onPanCancel: _layout.cancelWallResize,
                child: const MouseRegion(
                  cursor: SystemMouseCursors.resizeDownRight,
                  child: _ResizeHandle(),
                ),
              ),
            ),
            Positioned(
              left: 40 + wall.width / 2 - 10,
              top: 2,
              child: _RotationHandle(
                key: ValueKey('rotate-wall-${wall.id}'),
                onStart: (position) {
                  _layout.beginObjectRotation();
                },
                onUpdate: (position) {
                  final pointer = _layoutPosition(position);
                  if (pointer != null) {
                    _layout.rotateWallToward(wall.id, pointer);
                  }
                },
                onEnd: _layout.finishObjectRotation,
              ),
            ),
          ],
        ],
      ),
    ),
  );

  Widget _table(RoomTableModel table) {
    final selected = _layout.selectedTableIds.contains(table.id);
    final invalid = selected && _layout.invalidPlacement;
    final magnet =
        selected && _layout.interaction == LayoutInteraction.magnetPreview;
    return Positioned(
      left: _canvasOrigin.dx + table.x - 40,
      top: _canvasOrigin.dy + table.y - 40,
      width: table.width + 80,
      height: table.height + 80,
      child: Transform.rotate(
        angle: table.rotation,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 40,
              top: 40,
              width: table.width,
              height: table.height,
              child: Listener(
                key: ValueKey('room-table-${table.id}'),
                onPointerDown: _editingTables && _desktop
                    ? (event) => _desktopTablePointerDown(event, table.id)
                    : null,
                onPointerMove: _editingTables && _desktop
                    ? _desktopTablePointerMove
                    : null,
                onPointerUp: _editingTables && _desktop
                    ? _desktopTablePointerUp
                    : null,
                onPointerCancel: _editingTables && _desktop
                    ? _desktopTablePointerCancel
                    : null,
                child: GestureDetector(
                  onSecondaryTapDown: _editingTables
                      ? (details) => _showObjectContextMenu(
                          details.globalPosition,
                          tableId: table.id,
                        )
                      : null,
                  onTap: _editingTables && !_desktop
                      ? () => _layout.toggleSelection(table.id)
                      : null,
                  onLongPressStart: _editingTables && !_desktop
                      ? (details) {
                          _dragDelta = Offset.zero;
                          _lastGlobalPosition = details.globalPosition;
                          _layout.beginMove(table.id);
                        }
                      : null,
                  onLongPressMoveUpdate: _editingTables && !_desktop
                      ? (details) {
                          final delta =
                              details.globalPosition - _lastGlobalPosition;
                          _lastGlobalPosition = details.globalPosition;
                          _dragDelta += _logicalDelta(delta);
                          _layout.moveBy(_dragDelta);
                        }
                      : null,
                  onLongPressEnd: _editingTables && !_desktop
                      ? (_) => _layout.endMove()
                      : null,
                  child: MouseRegion(
                    cursor: _editingTables
                        ? SystemMouseCursors.move
                        : MouseCursor.defer,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 110),
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
                        boxShadow: [
                          BoxShadow(
                            color: magnet
                                ? const Color(0x554C9EF8)
                                : const Color(0x10000000),
                            blurRadius: magnet ? 16 : 7,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_layout.groupForTable(table.id) != null) ...[
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
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? const Color(0xFF4C9EF8)
                                      : const Color(0xFF6D7075),
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
            if (_editingTables &&
                selected &&
                _layout.selectedTableIds.length == 1) ...[
              Positioned(
                left: 40 + table.width - 7,
                top: 40 + table.height - 7,
                child: GestureDetector(
                  key: const ValueKey('resize-table-handle'),
                  onPanStart: (details) {
                    _resizeDelta = Offset.zero;
                    _lastGlobalPosition = details.globalPosition;
                    _layout.beginResize(table.id);
                  },
                  onPanUpdate: (details) {
                    final delta = details.globalPosition - _lastGlobalPosition;
                    _lastGlobalPosition = details.globalPosition;
                    _resizeDelta += _objectDelta(delta, table.rotation);
                    _layout.resizeBy(_resizeDelta);
                  },
                  onPanEnd: (_) => _layout.endResize(),
                  child: const MouseRegion(
                    cursor: SystemMouseCursors.resizeDownRight,
                    child: _ResizeHandle(),
                  ),
                ),
              ),
              Positioned(
                left: 40 + table.width / 2 - 10,
                top: 2,
                child: _RotationHandle(
                  key: ValueKey('rotate-table-${table.id}'),
                  onStart: (position) {
                    _layout.beginObjectRotation();
                  },
                  onUpdate: (position) {
                    final pointer = _layoutPosition(position);
                    if (pointer != null) {
                      _layout.rotateTableToward(table.id, pointer);
                    }
                  },
                  onEnd: _layout.finishObjectRotation,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _desktopTablePointerDown(PointerDownEvent event, int tableId) {
    if ((event.buttons & kPrimaryMouseButton) == 0) return;
    if (_activeDesktopPointer != null) return;
    _activeDesktopPointer = event.pointer;
    _activeDesktopTable = tableId;
    _desktopTableMoved = false;
    _dragDelta = Offset.zero;
    _lastGlobalPosition = event.position;
    _layout.pressTable();
  }

  void _desktopTablePointerMove(PointerMoveEvent event) {
    if (_activeDesktopPointer != event.pointer || _activeDesktopTable == null) {
      return;
    }
    final delta = event.position - _lastGlobalPosition;
    _lastGlobalPosition = event.position;
    if (!_desktopTableMoved && delta.distanceSquared > 0) {
      _desktopTableMoved = true;
      _layout.beginMove(_activeDesktopTable!);
    }
    if (_desktopTableMoved) {
      _dragDelta += _logicalDelta(delta);
      _layout.moveBy(_dragDelta);
    }
  }

  void _desktopTablePointerUp(PointerUpEvent event) {
    if (_activeDesktopPointer != event.pointer || _activeDesktopTable == null) {
      return;
    }
    if (_desktopTableMoved) {
      _layout.endMove();
    } else {
      _layout.cancelTablePress();
      _layout.toggleSelection(_activeDesktopTable!);
    }
    _clearDesktopPointer();
  }

  void _desktopTablePointerCancel(PointerCancelEvent event) {
    if (_activeDesktopPointer != event.pointer) return;
    if (_desktopTableMoved) _layout.endMove();
    _layout.cancelTablePress();
    _clearDesktopPointer();
  }

  void _clearDesktopPointer() {
    _activeDesktopPointer = null;
    _activeDesktopTable = null;
    _desktopTableMoved = false;
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

  Offset _objectDelta(Offset screenDelta, double objectRotation) {
    final logical = _logicalDelta(screenDelta);
    return Offset(
      logical.dx * math.cos(objectRotation) +
          logical.dy * math.sin(objectRotation),
      -logical.dx * math.sin(objectRotation) +
          logical.dy * math.cos(objectRotation),
    );
  }

  Offset? _layoutPosition(Offset globalPosition) {
    final renderObject = _layoutSpaceKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.globalToLocal(globalPosition) - _canvasOrigin;
  }

  Offset _visibleLayoutCenter() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) {
      return _layout.contentBounds.center;
    }
    final globalCenter = viewport.localToGlobal(
      viewport.size.center(Offset.zero),
    );
    return _layoutPosition(globalCenter) ?? _layout.contentBounds.center;
  }

  void _focusLayout() {
    final viewport = _viewportKey.currentContext?.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final bounds = _layout.contentBounds.inflate(100);
    final availableWidth = math.max(1.0, viewport.size.width - 80);
    final availableHeight = math.max(1.0, viewport.size.height - 80);
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

  Widget _editTools(bool compact) => Material(
    color: Colors.white,
    elevation: 5,
    borderRadius: BorderRadius.circular(18),
    child: compact
        ? Row(mainAxisSize: MainAxisSize.min, children: _toolButtons())
        : Column(mainAxisSize: MainAxisSize.min, children: _toolButtons()),
  );

  List<Widget> _toolButtons() => [
    _ToolButton(
      icon: Icons.table_restaurant_outlined,
      tooltip: _es ? 'Crear mesa' : 'Create table',
      onPressed: _createTable,
    ),
    _ToolButton(
      icon: Icons.architecture_outlined,
      tooltip: _es ? 'Agregar pared' : 'Add wall',
      onPressed: _createWall,
    ),
    _ToolButton(
      icon: Icons.link,
      tooltip: _es ? 'Agrupar mesas' : 'Group tables',
      onPressed: _layout.selectedTableIds.length >= 2
          ? _layout.groupSelected
          : null,
    ),
    _ToolButton(
      icon: Icons.link_off,
      tooltip: _es ? 'Separar grupo' : 'Ungroup',
      onPressed:
          _layout.selectedTableIds.any(
            (id) => _layout.groupForTable(id) != null,
          )
          ? _layout.ungroupSelected
          : null,
    ),
    const SizedBox(width: 1, height: 1),
    _ToolButton(
      icon: Icons.delete_outline,
      color: const Color(0xFFD73333),
      tooltip: _es ? 'Eliminar selección' : 'Delete selection',
      onPressed:
          _layout.selectedTableIds.isEmpty && _layout.selectedWallId == null
          ? null
          : _confirmDelete,
    ),
  ];

  Widget _cameraTools() => Material(
    color: Colors.white,
    elevation: 3,
    borderRadius: BorderRadius.circular(22),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => _zoom(.82),
          icon: const Icon(Icons.remove),
          tooltip: _es ? 'Alejar' : 'Zoom out',
        ),
        IconButton(
          onPressed: () => _zoom(1.22),
          icon: const Icon(Icons.add),
          tooltip: _es ? 'Acercar' : 'Zoom in',
        ),
        IconButton(
          onPressed: () => setState(() => _rotation -= math.pi / 2),
          icon: const Icon(Icons.rotate_left),
          tooltip: _es ? 'Rotar' : 'Rotate',
        ),
        IconButton(
          onPressed: () {
            _focusLayout();
          },
          icon: const Icon(Icons.center_focus_strong),
          tooltip: _es ? 'Centrar' : 'Reset camera',
        ),
      ],
    ),
  );

  void _zoom(double factor) {
    final matrix = _camera.value.clone();
    matrix.scaleByDouble(factor, factor, factor, 1);
    _camera.value = matrix;
  }

  Future<void> _createTable() async {
    final controller = TextEditingController();
    final identifier = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_es ? 'Nueva mesa' : 'New table'),
        content: TextField(
          key: const ValueKey('new-table-identifier'),
          controller: controller,
          autofocus: true,
          maxLength: 50,
          decoration: InputDecoration(
            labelText: _es ? 'Identificador visible' : 'Visible identifier',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_es ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: Text(_es ? 'Crear' : 'Create'),
          ),
        ],
      ),
    );
    // showDialog completa al iniciar la animación de salida; el TextField aún
    // puede vivir algunos frames y no debe perder su controller antes.
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (identifier == null || !mounted) return;
    if (_layout.tables.any((table) => table.identifier == identifier)) {
      _message(
        _es
            ? 'Ese identificador ya existe.'
            : 'That identifier already exists.',
        error: true,
      );
      return;
    }
    _layout.createTable(identifier, center: _visibleLayoutCenter());
  }

  void _createWall() {
    _layout.addWall(center: _visibleLayoutCenter());
  }

  void _copySelection() {
    if (!_editing) return;
    final table = _layout.selectedTable;
    final wall = _layout.selectedWall;
    if (table == null && wall == null) return;
    _copiedObject = table != null
        ? _CopiedLayoutObject.table(table)
        : _CopiedLayoutObject.wall(wall!);
    _message(_es ? 'Objeto copiado.' : 'Object copied.');
  }

  void _pasteCopied(Offset position) {
    if (!_editing) return;
    final copied = _copiedObject;
    if (copied == null) return;
    if (copied.table != null) {
      _layout.pasteTable(copied.table!, position);
    } else {
      _layout.pasteWall(copied.wall!, position);
    }
  }

  Future<void> _showObjectContextMenu(
    Offset globalPosition, {
    int? tableId,
    int? wallId,
  }) async {
    if (tableId != null) {
      _layout.selectTable(tableId);
    } else if (wallId != null) {
      _layout.selectWall(wallId);
    }
    final action = await _showEditorMenu(globalPosition, const [
      _EditorMenuAction.copy,
    ]);
    if (!mounted) return;
    if (action == _EditorMenuAction.copy) _copySelection();
  }

  Future<void> _showBackgroundContextMenu(TapDownDetails details) async {
    _layout.clearSelection();
    final position = _layoutPosition(details.globalPosition);
    if (position != null) _lastPointerPosition = position;
    final action = await _showEditorMenu(details.globalPosition, const [
      _EditorMenuAction.paste,
    ]);
    if (!mounted || action != _EditorMenuAction.paste) return;
    _pasteCopied(position ?? _visibleLayoutCenter());
  }

  Future<_EditorMenuAction?> _showEditorMenu(
    Offset globalPosition,
    List<_EditorMenuAction> actions,
  ) {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(globalPosition);
    return showMenu<_EditorMenuAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        local.dx,
        local.dy,
        overlay.size.width - local.dx,
        overlay.size.height - local.dy,
      ),
      items: [
        for (final action in actions)
          PopupMenuItem<_EditorMenuAction>(
            value: action,
            enabled: action != _EditorMenuAction.paste || _copiedObject != null,
            child: Row(
              children: [
                Icon(
                  action == _EditorMenuAction.copy
                      ? Icons.copy_outlined
                      : Icons.content_paste_outlined,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  action == _EditorMenuAction.copy
                      ? (_es ? 'Copiar' : 'Copy')
                      : (_es ? 'Pegar' : 'Paste'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_es ? 'Eliminar selección' : 'Delete selection'),
        content: Text(
          _es
              ? 'Esta acción eliminará los elementos seleccionados al guardar los cambios.'
              : 'This will delete the selected items when changes are saved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_es ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD33A3A),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(_es ? 'Eliminar' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) _layout.deleteSelected();
  }
}

enum _EditorMenuAction { copy, paste }

class _CopiedLayoutObject {
  const _CopiedLayoutObject.table(this.table) : wall = null;
  const _CopiedLayoutObject.wall(this.wall) : table = null;

  final RoomTableModel? table;
  final RoomWallModel? wall;
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.color,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    color: color,
    disabledColor: const Color(0xFFCDCFD0),
    icon: Icon(icon),
  );
}

class _ResizeHandle extends StatelessWidget {
  const _ResizeHandle();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(
      color: Colors.white,
      shape: BoxShape.circle,
      border: Border.fromBorderSide(
        BorderSide(color: Color(0xFF4C9EF8), width: 2),
      ),
    ),
    child: SizedBox.square(dimension: 14),
  );
}

class _RotationHandle extends StatelessWidget {
  const _RotationHandle({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final ValueChanged<Offset> onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: (event) => onStart(event.position),
    onPointerMove: (event) => onUpdate(event.position),
    onPointerUp: (_) => onEnd(),
    onPointerCancel: (_) => onEnd(),
    child: const MouseRegion(
      cursor: SystemMouseCursors.grab,
      child: SizedBox(
        width: 20,
        height: 38,
        child: Stack(
          alignment: Alignment.topCenter,
          children: [
            Positioned(
              top: 17,
              child: SizedBox(
                width: 2,
                height: 20,
                child: ColoredBox(color: Color(0xFF4C9EF8)),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.fromBorderSide(
                  BorderSide(color: Color(0xFF4C9EF8), width: 2),
                ),
              ),
              child: SizedBox.square(
                dimension: 20,
                child: Icon(
                  Icons.rotate_right,
                  size: 13,
                  color: Color(0xFF4C9EF8),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge({required this.spanish});
  final bool spanish;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('admin-live-view-badge'),
    color: const Color(0xEFFFFFFF),
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.visibility_outlined,
            size: 18,
            color: Color(0xFF71859B),
          ),
          const SizedBox(width: 8),
          Text(spanish ? 'Vista en vivo' : 'Live View'),
        ],
      ),
    ),
  );
}
