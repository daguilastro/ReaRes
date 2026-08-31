import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'room_layout_models.dart';

enum LayoutInteraction {
  normal,
  navigating,
  tablePressed,
  draggingTable,
  magnetPreview,
  resizingTable,
  resizingWall,
  rotatingObject,
  editingWalls,
  creatingTable,
}

class RoomLayoutController extends ChangeNotifier {
  static const minimumTableSize = 44.0;
  static const snapDistance = 12.0;
  static const collisionTolerance = .05;
  static const rotationSnapThreshold = math.pi / 36;

  RoomLayoutModel? _persisted;
  List<RoomTableModel> tables = [];
  List<RoomWallModel> walls = [];
  List<RoomTableGroupModel> groups = [];
  Set<int> selectedTableIds = {};
  int? selectedWallId;
  LayoutInteraction interaction = LayoutInteraction.normal;
  bool invalidPlacement = false;
  bool dirty = false;
  int _nextTemporaryId = -1;
  Map<int, RoomTableModel> _interactionOrigin = {};
  RoomWallModel? _wallMoveOrigin;
  RoomWallModel? _wallResizeOrigin;

  void load(RoomLayoutModel layout) {
    _persisted = layout;
    _replaceWith(layout);
  }

  void _replaceWith(RoomLayoutModel layout) {
    tables = [...layout.tables];
    walls = [...layout.walls];
    groups = layout.groups
        .map(
          (group) => RoomTableGroupModel(
            id: group.id,
            identifier: group.identifier,
            tableIds: [...group.tableIds],
          ),
        )
        .toList();
    selectedTableIds = {};
    selectedWallId = null;
    interaction = LayoutInteraction.normal;
    invalidPlacement = false;
    dirty = false;
    _nextTemporaryId = -1;
    _wallMoveOrigin = null;
    _wallResizeOrigin = null;
    notifyListeners();
  }

  RoomLayoutModel snapshot() => RoomLayoutModel(
    roomId: _persisted?.roomId ?? 1,
    roomName: _persisted?.roomName ?? 'Main Hall',
    tables: [...tables],
    walls: [...walls],
    groups: groups
        .map(
          (group) => RoomTableGroupModel(
            id: group.id,
            identifier: group.identifier,
            tableIds: [...group.tableIds],
          ),
        )
        .toList(),
  );

  void acceptSaved(RoomLayoutModel layout) => load(layout);
  void cancel() {
    if (_persisted != null) _replaceWith(_persisted!);
  }

  void toggleSelection(int id) {
    selectedWallId = null;
    if (selectedTableIds.contains(id)) {
      selectedTableIds = {...selectedTableIds}..remove(id);
    } else {
      selectedTableIds = {...selectedTableIds, id};
    }
    interaction = LayoutInteraction.normal;
    notifyListeners();
  }

  void selectTable(int id) {
    selectedTableIds = {id};
    selectedWallId = null;
    interaction = LayoutInteraction.normal;
    invalidPlacement = false;
    notifyListeners();
  }

  void clearSelection() {
    selectedTableIds = {};
    selectedWallId = null;
    interaction = LayoutInteraction.normal;
    invalidPlacement = false;
    notifyListeners();
  }

  void beginMove(int id) {
    selectedWallId = null;
    final group = groupForTable(id);
    selectedTableIds = group == null ? {id} : group.tableIds.toSet();
    _interactionOrigin = {
      for (final table in tables)
        if (selectedTableIds.contains(table.id)) table.id: table,
    };
    interaction = LayoutInteraction.tablePressed;
    invalidPlacement = false;
    notifyListeners();
  }

  void pressTable() {
    interaction = LayoutInteraction.tablePressed;
    notifyListeners();
  }

  void cancelTablePress() {
    if (interaction == LayoutInteraction.tablePressed) {
      interaction = LayoutInteraction.normal;
      notifyListeners();
    }
  }

  void moveBy(Offset delta) {
    if (_interactionOrigin.isEmpty) return;
    var adjusted = delta;
    final movingIds = _interactionOrigin.keys.toSet();
    final proposed = _interactionOrigin.values
        .map(
          (table) =>
              table.copyWith(x: table.x + delta.dx, y: table.y + delta.dy),
        )
        .toList();
    final correction = _snapCorrection(proposed, movingIds);
    adjusted += correction;
    final moved = _interactionOrigin.values
        .map(
          (table) => table.copyWith(
            x: table.x + adjusted.dx,
            y: table.y + adjusted.dy,
          ),
        )
        .toList();
    _replaceMoving(moved);
    invalidPlacement = _hasCollision(moved, movingIds);
    interaction = correction == Offset.zero
        ? LayoutInteraction.draggingTable
        : LayoutInteraction.magnetPreview;
    notifyListeners();
  }

  void endMove() {
    if (invalidPlacement) {
      _replaceMoving(_interactionOrigin.values.toList());
    } else {
      dirty = true;
    }
    _interactionOrigin = {};
    invalidPlacement = false;
    interaction = LayoutInteraction.normal;
    notifyListeners();
  }

  void beginResize(int id) {
    final table = tables.firstWhere((table) => table.id == id);
    selectedTableIds = {id};
    selectedWallId = null;
    _interactionOrigin = {id: table};
    interaction = LayoutInteraction.resizingTable;
    invalidPlacement = false;
    notifyListeners();
  }

  void resizeBy(Offset delta) {
    if (_interactionOrigin.length != 1) return;
    final original = _interactionOrigin.values.single;
    final width = math.max(minimumTableSize, original.width + delta.dx);
    final height = math.max(minimumTableSize, original.height + delta.dy);
    final position = _resizedPosition(
      x: original.x,
      y: original.y,
      oldWidth: original.width,
      oldHeight: original.height,
      newWidth: width,
      newHeight: height,
      rotation: original.rotation,
    );
    final resized = original.copyWith(
      x: position.dx,
      y: position.dy,
      width: width,
      height: height,
    );
    _replaceMoving([resized]);
    invalidPlacement = _hasCollision([resized], {resized.id});
    notifyListeners();
  }

  void endResize() => endMove();

  void rotateTable(int id, double delta) {
    final table = tables.firstWhere((table) => table.id == id);
    setTableRotation(id, table.rotation + delta);
  }

  void setTableRotation(int id, double angle) {
    final table = tables.firstWhere((table) => table.id == id);
    final rotated = table.copyWith(rotation: _snapRotation(angle));
    if (_hasCollision([rotated], {id})) {
      invalidPlacement = true;
      notifyListeners();
      return;
    }
    invalidPlacement = false;
    _replaceMoving([rotated]);
    dirty = true;
    notifyListeners();
  }

  void rotateTableToward(int id, Offset pointer) {
    final table = tables.firstWhere((table) => table.id == id);
    final center = Offset(
      table.x + table.width / 2,
      table.y + table.height / 2,
    );
    final angle = _rotationTowardPointer(center, pointer);
    if (angle != null) setTableRotation(id, angle);
  }

  void beginObjectRotation() {
    interaction = LayoutInteraction.rotatingObject;
    invalidPlacement = false;
    notifyListeners();
  }

  void finishObjectRotation() {
    interaction = LayoutInteraction.normal;
    invalidPlacement = false;
    notifyListeners();
  }

  void createTable(String identifier, {Offset? center}) {
    interaction = LayoutInteraction.creatingTable;
    const width = 130.0;
    const height = 82.0;
    final targetCenter = center ?? const Offset(165, 131);
    final position = _freeTablePosition(
      targetCenter,
      width: width,
      height: height,
    );
    final table = RoomTableModel(
      id: _nextTemporaryId--,
      identifier: identifier.trim(),
      x: position.dx,
      y: position.dy,
      width: width,
      height: height,
    );
    tables = [...tables, table];
    selectedTableIds = {table.id};
    selectedWallId = null;
    interaction = LayoutInteraction.normal;
    dirty = true;
    notifyListeners();
  }

  void deleteSelected() {
    final deleted = selectedTableIds;
    tables = tables.where((table) => !deleted.contains(table.id)).toList();
    groups = groups
        .map(
          (group) => RoomTableGroupModel(
            id: group.id,
            identifier: group.identifier,
            tableIds: group.tableIds
                .where((id) => !deleted.contains(id))
                .toList(),
          ),
        )
        .where((group) => group.tableIds.length >= 2)
        .toList();
    selectedTableIds = {};
    if (selectedWallId != null) {
      walls = walls.where((wall) => wall.id != selectedWallId).toList();
      selectedWallId = null;
    }
    dirty = true;
    notifyListeners();
  }

  void groupSelected() {
    if (selectedTableIds.length < 2) return;
    selectedWallId = null;
    final selected = tables
        .where((table) => selectedTableIds.contains(table.id))
        .toList();
    groups = groups
        .where(
          (group) =>
              group.tableIds.every((id) => !selectedTableIds.contains(id)),
        )
        .toList();
    final numeric =
        selected
            .where((table) => int.tryParse(table.identifier) != null)
            .toList()
          ..sort(
            (a, b) =>
                int.parse(a.identifier).compareTo(int.parse(b.identifier)),
          );
    groups = [
      ...groups,
      RoomTableGroupModel(
        id: _nextTemporaryId--,
        identifier: numeric.isNotEmpty
            ? numeric.first.identifier
            : selected.first.identifier,
        tableIds: selectedTableIds.toList(),
      ),
    ];
    dirty = true;
    notifyListeners();
  }

  void ungroupSelected() {
    groups = groups
        .where(
          (group) =>
              group.tableIds.every((id) => !selectedTableIds.contains(id)),
        )
        .toList();
    dirty = true;
    notifyListeners();
  }

  RoomTableGroupModel? groupForTable(int tableId) {
    for (final group in groups) {
      if (group.tableIds.contains(tableId)) return group;
    }
    return null;
  }

  void addWall({Offset? center}) {
    const width = 210.0;
    const height = 10.0;
    final targetCenter = center ?? const Offset(465, 345);
    final position = _freeWallPosition(
      targetCenter,
      width: width,
      height: height,
    );
    final wall = RoomWallModel(
      id: _nextTemporaryId--,
      x: position.dx,
      y: position.dy,
      width: width,
      height: height,
      rotation: 0,
    );
    walls = [...walls, wall];
    selectedWallId = wall.id;
    selectedTableIds = {};
    interaction = LayoutInteraction.normal;
    dirty = true;
    notifyListeners();
  }

  void selectWall(int id) {
    selectedWallId = id;
    selectedTableIds = {};
    interaction = LayoutInteraction.normal;
    notifyListeners();
  }

  void beginWallMove(int id) {
    selectWall(id);
    _wallMoveOrigin = walls.firstWhere((wall) => wall.id == id);
    interaction = LayoutInteraction.editingWalls;
    notifyListeners();
  }

  void moveWall(int id, Offset delta) {
    final original = _wallMoveOrigin;
    if (original == null || original.id != id) return;
    final proposed = original.copyWith(
      x: original.x + delta.dx,
      y: original.y + delta.dy,
    );
    final correction = _wallSnapCorrection(proposed, id);
    walls = [
      for (final wall in walls)
        if (wall.id == id)
          proposed.copyWith(
            x: proposed.x + correction.dx,
            y: proposed.y + correction.dy,
          )
        else
          wall,
    ];
    interaction = correction == Offset.zero
        ? LayoutInteraction.editingWalls
        : LayoutInteraction.magnetPreview;
    notifyListeners();
  }

  void beginWallResize(int id) {
    final wall = walls.firstWhere((wall) => wall.id == id);
    selectedWallId = id;
    selectedTableIds = {};
    _wallResizeOrigin = wall;
    interaction = LayoutInteraction.resizingWall;
    notifyListeners();
  }

  void resizeWallBy(Offset delta) {
    final original = _wallResizeOrigin;
    if (original == null) return;
    final width = math.max(4.0, original.width + delta.dx);
    final height = math.max(4.0, original.height + delta.dy);
    final position = _resizedPosition(
      x: original.x,
      y: original.y,
      oldWidth: original.width,
      oldHeight: original.height,
      newWidth: width,
      newHeight: height,
      rotation: original.rotation,
    );
    walls = [
      for (final wall in walls)
        if (wall.id == original.id)
          wall.copyWith(
            x: position.dx,
            y: position.dy,
            width: width,
            height: height,
          )
        else
          wall,
    ];
    notifyListeners();
  }

  void endWallResize() {
    if (_wallResizeOrigin != null) dirty = true;
    _wallResizeOrigin = null;
    interaction = LayoutInteraction.normal;
    notifyListeners();
  }

  void cancelWallResize() {
    final original = _wallResizeOrigin;
    if (original != null) {
      walls = [
        for (final wall in walls)
          if (wall.id == original.id) original else wall,
      ];
    }
    _wallResizeOrigin = null;
    interaction = LayoutInteraction.normal;
    notifyListeners();
  }

  void rotateWall(int id, double delta) {
    final wall = walls.firstWhere((wall) => wall.id == id);
    setWallRotation(id, wall.rotation + delta);
  }

  void setWallRotation(int id, double angle) {
    walls = [
      for (final wall in walls)
        if (wall.id == id)
          RoomWallModel(
            id: wall.id,
            x: wall.x,
            y: wall.y,
            width: wall.width,
            height: wall.height,
            rotation: _snapRotation(angle),
          )
        else
          wall,
    ];
    dirty = true;
    notifyListeners();
  }

  void rotateWallToward(int id, Offset pointer) {
    final wall = walls.firstWhere((wall) => wall.id == id);
    final center = Offset(wall.x + wall.width / 2, wall.y + wall.height / 2);
    final angle = _rotationTowardPointer(center, pointer);
    if (angle != null) setWallRotation(id, angle);
  }

  void finishWallEditing() {
    if (_wallMoveOrigin != null) dirty = true;
    _wallMoveOrigin = null;
    interaction = LayoutInteraction.normal;
    notifyListeners();
  }

  void cancelWallMove() {
    final original = _wallMoveOrigin;
    if (original != null) {
      walls = [
        for (final wall in walls)
          if (wall.id == original.id) original else wall,
      ];
    }
    _wallMoveOrigin = null;
    interaction = LayoutInteraction.normal;
    notifyListeners();
  }

  void pasteTable(RoomTableModel source, Offset center) {
    final identifier = _copiedIdentifier(source.identifier);
    final position = _freeTablePosition(
      center,
      width: source.width,
      height: source.height,
      rotation: source.rotation,
    );
    final table = source.copyWith(
      id: _nextTemporaryId--,
      identifier: identifier,
      x: position.dx,
      y: position.dy,
    );
    tables = [...tables, table];
    selectedTableIds = {table.id};
    selectedWallId = null;
    interaction = LayoutInteraction.normal;
    dirty = true;
    notifyListeners();
  }

  void pasteWall(RoomWallModel source, Offset center) {
    final wall = RoomWallModel(
      id: _nextTemporaryId--,
      x: center.dx - source.width / 2,
      y: center.dy - source.height / 2,
      width: source.width,
      height: source.height,
      rotation: source.rotation,
    );
    walls = [...walls, wall];
    selectedWallId = wall.id;
    selectedTableIds = {};
    interaction = LayoutInteraction.normal;
    dirty = true;
    notifyListeners();
  }

  RoomTableModel? get selectedTable => selectedTableIds.length == 1
      ? tables.firstWhere((table) => table.id == selectedTableIds.single)
      : null;

  RoomWallModel? get selectedWall => selectedWallId == null
      ? null
      : walls.firstWhere((wall) => wall.id == selectedWallId);

  Rect get contentBounds {
    Rect? result;
    for (final table in tables) {
      result = result?.expandToInclude(_bounds(table)) ?? _bounds(table);
    }
    for (final wall in walls) {
      result = result?.expandToInclude(_wallBounds(wall)) ?? _wallBounds(wall);
    }
    return result ?? const Rect.fromLTWH(-200, -150, 400, 300);
  }

  void _replaceMoving(List<RoomTableModel> replacements) {
    final byId = {for (final table in replacements) table.id: table};
    tables = [for (final table in tables) byId[table.id] ?? table];
  }

  bool _hasCollision(List<RoomTableModel> moving, Set<int> movingIds) {
    final stationary = tables.where((table) => !movingIds.contains(table.id));
    for (final first in moving) {
      for (final second in stationary) {
        if (_intersects(first, second)) return true;
      }
    }
    return false;
  }

  Offset _snapCorrection(List<RoomTableModel> moving, Set<int> movingIds) {
    var bestX = snapDistance + 1;
    var bestY = snapDistance + 1;
    var correctionX = 0.0;
    var correctionY = 0.0;
    for (final movingTable in moving) {
      final movingBounds = _bounds(movingTable);
      for (final other in tables.where(
        (table) => !movingIds.contains(table.id),
      )) {
        final otherBounds = _bounds(other);
        final verticalOverlap =
            movingBounds.top < otherBounds.bottom &&
            movingBounds.bottom > otherBounds.top;
        final horizontalOverlap =
            movingBounds.left < otherBounds.right &&
            movingBounds.right > otherBounds.left;
        if (verticalOverlap) {
          for (final difference in [
            otherBounds.left - movingBounds.right,
            otherBounds.right - movingBounds.left,
          ]) {
            if (difference.abs() <= snapDistance && difference.abs() < bestX) {
              bestX = difference.abs();
              correctionX = difference;
            }
          }
        }
        if (horizontalOverlap) {
          for (final difference in [
            otherBounds.top - movingBounds.bottom,
            otherBounds.bottom - movingBounds.top,
          ]) {
            if (difference.abs() <= snapDistance && difference.abs() < bestY) {
              bestY = difference.abs();
              correctionY = difference;
            }
          }
        }
      }
    }
    final candidates = <Offset>[
      Offset(correctionX, correctionY),
      Offset(correctionX, 0),
      Offset(0, correctionY),
    ];
    for (final correction in candidates) {
      if (correction == Offset.zero) continue;
      final corrected = moving
          .map(
            (table) => table.copyWith(
              x: table.x + correction.dx,
              y: table.y + correction.dy,
            ),
          )
          .toList();
      if (!_hasCollision(corrected, movingIds)) return correction;
    }
    return Offset.zero;
  }

  Offset _wallSnapCorrection(RoomWallModel moving, int movingId) {
    final movingBounds = _wallBounds(moving);
    var bestX = snapDistance + 1;
    var bestY = snapDistance + 1;
    var correctionX = 0.0;
    var correctionY = 0.0;
    for (final other in walls.where((wall) => wall.id != movingId)) {
      final otherBounds = _wallBounds(other);
      final verticallyNear =
          movingBounds.top <= otherBounds.bottom + snapDistance &&
          movingBounds.bottom >= otherBounds.top - snapDistance;
      final horizontallyNear =
          movingBounds.left <= otherBounds.right + snapDistance &&
          movingBounds.right >= otherBounds.left - snapDistance;
      if (verticallyNear) {
        for (final difference in [
          otherBounds.left - movingBounds.left,
          otherBounds.left - movingBounds.right,
          otherBounds.right - movingBounds.left,
          otherBounds.right - movingBounds.right,
        ]) {
          if (difference.abs() <= snapDistance && difference.abs() < bestX) {
            bestX = difference.abs();
            correctionX = difference;
          }
        }
      }
      if (horizontallyNear) {
        for (final difference in [
          otherBounds.top - movingBounds.top,
          otherBounds.top - movingBounds.bottom,
          otherBounds.bottom - movingBounds.top,
          otherBounds.bottom - movingBounds.bottom,
        ]) {
          if (difference.abs() <= snapDistance && difference.abs() < bestY) {
            bestY = difference.abs();
            correctionY = difference;
          }
        }
      }
    }
    return Offset(correctionX, correctionY);
  }

  Offset _freeTablePosition(
    Offset center, {
    required double width,
    required double height,
    double rotation = 0,
  }) {
    for (final offset in _placementOffsets()) {
      final candidateCenter = center + offset;
      final candidate = RoomTableModel(
        id: _nextTemporaryId,
        identifier: '',
        x: candidateCenter.dx - width / 2,
        y: candidateCenter.dy - height / 2,
        width: width,
        height: height,
        rotation: rotation,
      );
      if (tables.every((table) => !_intersects(candidate, table)) &&
          walls.every(
            (wall) => !_bounds(candidate).overlaps(_wallBounds(wall)),
          )) {
        return Offset(candidate.x, candidate.y);
      }
    }
    return Offset(center.dx - width / 2 + 480, center.dy - height / 2 + 480);
  }

  Offset _freeWallPosition(
    Offset center, {
    required double width,
    required double height,
  }) {
    for (final offset in _placementOffsets()) {
      final candidateCenter = center + offset;
      final candidate = RoomWallModel(
        id: _nextTemporaryId,
        x: candidateCenter.dx - width / 2,
        y: candidateCenter.dy - height / 2,
        width: width,
        height: height,
        rotation: 0,
      );
      if (walls.every(
            (wall) => !_wallBounds(candidate).overlaps(_wallBounds(wall)),
          ) &&
          tables.every(
            (table) => !_wallBounds(candidate).overlaps(_bounds(table)),
          )) {
        return Offset(candidate.x, candidate.y);
      }
    }
    return Offset(center.dx - width / 2 + 480, center.dy - height / 2 + 480);
  }

  Iterable<Offset> _placementOffsets() sync* {
    yield Offset.zero;
    const step = 36.0;
    for (var ring = 1; ring <= 14; ring++) {
      for (var x = -ring; x <= ring; x++) {
        yield Offset(x * step, -ring * step);
        yield Offset(x * step, ring * step);
      }
      for (var y = -ring + 1; y < ring; y++) {
        yield Offset(-ring * step, y * step);
        yield Offset(ring * step, y * step);
      }
    }
  }

  String _copiedIdentifier(String original) {
    final used = tables.map((table) => table.identifier).toSet();
    var candidate = '$original copy';
    var suffix = 2;
    while (used.contains(candidate)) {
      candidate = '$original copy ${suffix++}';
    }
    return candidate;
  }

  bool _intersects(RoomTableModel a, RoomTableModel b) =>
      _bounds(a).left < _bounds(b).right - collisionTolerance &&
      _bounds(a).right > _bounds(b).left + collisionTolerance &&
      _bounds(a).top < _bounds(b).bottom - collisionTolerance &&
      _bounds(a).bottom > _bounds(b).top + collisionTolerance;

  double _snapRotation(double angle) {
    const fullTurn = math.pi * 2;
    var normalized = angle % fullTurn;
    if (normalized > math.pi) normalized -= fullTurn;
    if (normalized <= -math.pi) normalized += fullTurn;
    final quarterTurn = math.pi / 2;
    final nearestAxis = (normalized / quarterTurn).round() * quarterTurn;
    return (normalized - nearestAxis).abs() <= rotationSnapThreshold
        ? nearestAxis
        : normalized;
  }

  double? _rotationTowardPointer(Offset center, Offset pointer) {
    final direction = pointer - center;
    if (direction.distanceSquared < 1) return null;
    // El handle nace sobre el centro de la cara superior. Por eso el ángulo
    // visual del cursor (atan2) necesita un cuarto de vuelta para convertirse
    // en la rotación del rectángulo: la cara queda perpendicular al cursor y
    // el handle apunta exactamente hacia él.
    return math.atan2(direction.dy, direction.dx) + math.pi / 2;
  }

  Offset _resizedPosition({
    required double x,
    required double y,
    required double oldWidth,
    required double oldHeight,
    required double newWidth,
    required double newHeight,
    required double rotation,
  }) {
    final halfWidthDelta = (newWidth - oldWidth) / 2;
    final halfHeightDelta = (newHeight - oldHeight) / 2;
    final cosine = math.cos(rotation);
    final sine = math.sin(rotation);

    // Transform.rotate gira alrededor del centro. Al redimensionar desde la
    // esquina inferior derecha, el centro debe desplazarse en los ejes
    // rotados para conservar inmóvil la esquina superior izquierda visual.
    final rotatedCenterDelta = Offset(
      halfWidthDelta * cosine - halfHeightDelta * sine,
      halfWidthDelta * sine + halfHeightDelta * cosine,
    );
    return Offset(
      x + rotatedCenterDelta.dx - halfWidthDelta,
      y + rotatedCenterDelta.dy - halfHeightDelta,
    );
  }

  Rect _bounds(RoomTableModel table) {
    final cosine = math.cos(table.rotation).abs();
    final sine = math.sin(table.rotation).abs();
    final width = table.width * cosine + table.height * sine;
    final height = table.width * sine + table.height * cosine;
    return Rect.fromCenter(
      center: Offset(table.x + table.width / 2, table.y + table.height / 2),
      width: width,
      height: height,
    );
  }

  Rect _wallBounds(RoomWallModel wall) {
    final cosine = math.cos(wall.rotation).abs();
    final sine = math.sin(wall.rotation).abs();
    final width = wall.width * cosine + wall.height * sine;
    final height = wall.width * sine + wall.height * cosine;
    return Rect.fromCenter(
      center: Offset(wall.x + wall.width / 2, wall.y + wall.height / 2),
      width: width,
      height: height,
    );
  }
}
