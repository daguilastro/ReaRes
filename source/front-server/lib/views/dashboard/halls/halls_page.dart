import 'package:flutter/material.dart';

import '../../../services/admin_api.dart';
import '../../../utils/money.dart';
import '../menus/catalog_models.dart';
import 'hall_layout_page.dart';
import 'room_layout_models.dart';

typedef LoadRooms = Future<List<RoomSummary>> Function(String token);
typedef CreateRoom =
    Future<RoomSummary> Function({required String token, required String name});
typedef LoadRoomMenus = Future<CatalogSnapshot> Function(String token);
typedef SaveRoomMenus =
    Future<void> Function({
      required String token,
      required int roomId,
      required List<RoomMenuAssignment> assignments,
    });
typedef RoomEditorBuilder =
    Widget Function(RoomSummary room, VoidCallback onBack);

class HallsPage extends StatefulWidget {
  const HallsPage({
    super.key,
    required this.spanish,
    required this.token,
    this.loadRooms = getRooms,
    this.createNewRoom = createRoom,
    this.loadMenus = getCatalog,
    this.saveMenus = updateRoomMenus,
    this.editorBuilder,
  });

  final bool spanish;
  final String token;
  final LoadRooms loadRooms;
  final CreateRoom createNewRoom;
  final LoadRoomMenus loadMenus;
  final SaveRoomMenus saveMenus;
  final RoomEditorBuilder? editorBuilder;

  @override
  State<HallsPage> createState() => _HallsPageState();
}

class _HallsPageState extends State<HallsPage> {
  List<RoomSummary> _rooms = [];
  RoomSummary? _selectedRoom;
  bool _loading = true;
  String? _error;

  bool get _es => widget.spanish;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _rooms = await widget.loadRooms(widget.token);
    } on Object {
      _error = _es
          ? 'No se pudieron cargar los salones.'
          : 'Rooms could not be loaded.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedRoom;
    if (selected != null) {
      void onBack() {
        setState(() => _selectedRoom = null);
        _load();
      }

      if (widget.editorBuilder != null) {
        return widget.editorBuilder!(selected, onBack);
      }
      return HallLayoutPage(
        key: ValueKey('room-editor-${selected.id}'),
        spanish: _es,
        token: widget.token,
        roomId: selected.id,
        onBack: onBack,
      );
    }
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 12),
            sliver: SliverToBoxAdapter(child: _header()),
          ),
          if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyRooms(
                title: _error!,
                subtitle: _es
                    ? 'Comprueba el servidor e inténtalo de nuevo.'
                    : 'Check the server and try again.',
                icon: Icons.cloud_off_outlined,
              ),
            )
          else if (_rooms.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyRooms(
                title: _es ? 'Aún no hay salones' : 'No rooms yet',
                subtitle: _es
                    ? 'Crea el primero para diseñarlo completamente desde cero.'
                    : 'Create the first room and design it entirely from scratch.',
                icon: Icons.meeting_room_outlined,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(28, 12, 28, 32),
              sliver: SliverLayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.crossAxisExtent;
                  final columns = width >= 1000
                      ? 3
                      : width >= 620
                      ? 2
                      : 1;
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 16,
                      mainAxisExtent: 210,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _RoomCard(
                        room: _rooms[index],
                        spanish: _es,
                        onTap: () =>
                            setState(() => _selectedRoom = _rooms[index]),
                        onManageMenus: () => _manageRoomMenus(_rooms[index]),
                      ),
                      childCount: _rooms.length,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _header() => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 20,
    runSpacing: 14,
    children: [
      SizedBox(
        width: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _es ? 'Salones' : 'Rooms',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Color(0xFF242629),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              _es
                  ? 'Selecciona un salón para consultar o editar su distribución.'
                  : 'Select a room to view or edit its layout.',
              style: const TextStyle(color: Color(0xFF72767B)),
            ),
          ],
        ),
      ),
      FilledButton.icon(
        key: const ValueKey('create-room'),
        onPressed: _createRoom,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF71859B),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        ),
        icon: const Icon(Icons.add),
        label: Text(_es ? 'Crear salón' : 'Create room'),
      ),
    ],
  );

  Future<void> _createRoom() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_es ? 'Nuevo salón' : 'New room'),
        content: TextField(
          key: const ValueKey('new-room-name'),
          controller: controller,
          autofocus: true,
          maxLength: 80,
          decoration: InputDecoration(labelText: _es ? 'Nombre' : 'Name'),
          onSubmitted: (value) {
            if (value.trim().length >= 2) Navigator.pop(context, value.trim());
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_es ? 'Cancelar' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 2) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: Text(_es ? 'Crear' : 'Create'),
          ),
        ],
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400), controller.dispose);
    if (name == null || !mounted) return;
    try {
      final room = await widget.createNewRoom(token: widget.token, name: name);
      if (mounted) {
        setState(() {
          _rooms = [..._rooms, room];
          _selectedRoom = room;
        });
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _es
                  ? 'No se pudo crear el salón.'
                  : 'The room could not be created.',
            ),
            backgroundColor: const Color(0xFFB64A4A),
          ),
        );
      }
    }
  }

  Future<void> _manageRoomMenus(RoomSummary room) async {
    try {
      final catalog = await widget.loadMenus(widget.token);
      if (!mounted) return;
      if (catalog.menus.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _es
                  ? 'Primero debes crear al menos un menú.'
                  : 'Create at least one menu first.',
            ),
          ),
        );
        return;
      }
      final assignments = await showDialog<List<RoomMenuAssignment>>(
        context: context,
        builder: (_) =>
            _RoomMenusDialog(spanish: _es, room: room, menus: catalog.menus),
      );
      if (assignments == null || !mounted) return;
      await widget.saveMenus(
        token: widget.token,
        roomId: room.id,
        assignments: assignments,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _es ? 'Menús del salón actualizados.' : 'Room menus updated.',
          ),
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB64A4A),
          content: Text(
            _es
                ? 'No se pudieron actualizar los menús del salón.'
                : 'The room menus could not be updated.',
          ),
        ),
      );
    }
  }
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.spanish,
    required this.onTap,
    required this.onManageMenus,
  });
  final RoomSummary room;
  final bool spanish;
  final VoidCallback onTap;
  final VoidCallback onManageMenus;

  String _money(double value) => formatPesos(value);

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    elevation: 1,
    shadowColor: const Color(0x18000000),
    child: InkWell(
      key: ValueKey('room-card-${room.id}'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFE9EEF3),
                  child: Icon(
                    Icons.meeting_room_outlined,
                    color: Color(0xFF71859B),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    room.name,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: ValueKey('room-menus-${room.id}'),
                  tooltip: spanish ? 'Asignar menús' : 'Assign menus',
                  onPressed: onManageMenus,
                  icon: const Icon(
                    Icons.restaurant_menu_rounded,
                    color: Color(0xFF71859B),
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: Color(0xFF9DA2A7),
                ),
              ],
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: _Statistic(
                    label: spanish ? 'Mesas' : 'Tables',
                    value: '${room.tableCount}',
                  ),
                ),
                Expanded(
                  child: _Statistic(
                    label: spanish ? 'Pedidos' : 'Orders',
                    value: '${room.orderCount}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 17),
            Row(
              children: [
                Expanded(
                  child: _Statistic(
                    label: spanish ? 'Ventas' : 'Sales',
                    value: _money(room.totalSales),
                  ),
                ),
                Expanded(
                  child: _Statistic(
                    label: spanish ? 'Venta promedio' : 'Average sale',
                    value: _money(room.averageSale),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

enum _RoomMenuMode { none, primary, secondary }

class _RoomMenusDialog extends StatefulWidget {
  const _RoomMenusDialog({
    required this.spanish,
    required this.room,
    required this.menus,
  });

  final bool spanish;
  final RoomSummary room;
  final List<RestaurantMenu> menus;

  @override
  State<_RoomMenusDialog> createState() => _RoomMenusDialogState();
}

class _RoomMenusDialogState extends State<_RoomMenusDialog> {
  late final Map<int, _RoomMenuMode> _modes = {
    for (final menu in widget.menus)
      menu.id: menu.primaryHallIds.contains(widget.room.id)
          ? _RoomMenuMode.primary
          : menu.secondaryHallIds.contains(widget.room.id)
          ? _RoomMenuMode.secondary
          : _RoomMenuMode.none,
  };

  void _setMode(int menuId, _RoomMenuMode mode) {
    setState(() {
      if (mode == _RoomMenuMode.primary) {
        for (final entry in _modes.entries) {
          if (entry.value == _RoomMenuMode.primary && entry.key != menuId) {
            _modes[entry.key] = _RoomMenuMode.secondary;
          }
        }
      }
      _modes[menuId] = mode;
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.spanish
          ? 'Menús de ${widget.room.name}'
          : '${widget.room.name} menus',
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.spanish
                  ? 'Selecciona un menú principal y los menús secundarios disponibles en este salón.'
                  : 'Choose one primary menu and the secondary menus available in this room.',
              style: const TextStyle(color: Color(0xFF70757A)),
            ),
            const SizedBox(height: 16),
            for (final menu in widget.menus)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DropdownButtonFormField<_RoomMenuMode>(
                  key: ValueKey('room-menu-${menu.id}'),
                  initialValue: _modes[menu.id],
                  decoration: InputDecoration(
                    labelText: menu.name,
                    prefixIcon: const Icon(Icons.menu_book_outlined),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: _RoomMenuMode.none,
                      child: Text(
                        widget.spanish ? 'No asignado' : 'Not assigned',
                      ),
                    ),
                    DropdownMenuItem(
                      value: _RoomMenuMode.primary,
                      child: Text(
                        widget.spanish ? 'Menú principal' : 'Primary menu',
                      ),
                    ),
                    DropdownMenuItem(
                      value: _RoomMenuMode.secondary,
                      child: Text(
                        widget.spanish ? 'Menú secundario' : 'Secondary menu',
                      ),
                    ),
                  ],
                  onChanged: (mode) {
                    if (mode != null) _setMode(menu.id, mode);
                  },
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
      ),
      FilledButton.icon(
        key: const ValueKey('save-room-menus'),
        onPressed: () => Navigator.pop(context, [
          for (final menu in widget.menus)
            if (_modes[menu.id] != _RoomMenuMode.none)
              RoomMenuAssignment(
                menuId: menu.id,
                isPrimary: _modes[menu.id] == _RoomMenuMode.primary,
              ),
        ]),
        icon: const Icon(Icons.save_outlined),
        label: Text(widget.spanish ? 'Guardar' : 'Save'),
      ),
    ],
  );
}

class _Statistic extends StatelessWidget {
  const _Statistic({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFF85898E)),
      ),
      const SizedBox(height: 3),
      Text(
        value,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF303337),
        ),
      ),
    ],
  );
}

class _EmptyRooms extends StatelessWidget {
  const _EmptyRooms({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 58, color: const Color(0xFF9BA9B7)),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF777B80)),
          ),
        ],
      ),
    ),
  );
}
