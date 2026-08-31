import 'package:flutter/material.dart';

import '../../../services/admin_api.dart';
import '../../../utils/money.dart';
import 'hall_layout_page.dart';
import 'room_layout_models.dart';

typedef LoadRooms = Future<List<RoomSummary>> Function(String token);
typedef CreateRoom =
    Future<RoomSummary> Function({required String token, required String name});
typedef RoomEditorBuilder =
    Widget Function(RoomSummary room, VoidCallback onBack);

class HallsPage extends StatefulWidget {
  const HallsPage({
    super.key,
    required this.spanish,
    required this.token,
    this.loadRooms = getRooms,
    this.createNewRoom = createRoom,
    this.editorBuilder,
  });

  final bool spanish;
  final String token;
  final LoadRooms loadRooms;
  final CreateRoom createNewRoom;
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
}

class _RoomCard extends StatelessWidget {
  const _RoomCard({
    required this.room,
    required this.spanish,
    required this.onTap,
  });
  final RoomSummary room;
  final bool spanish;
  final VoidCallback onTap;

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
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 16,
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
