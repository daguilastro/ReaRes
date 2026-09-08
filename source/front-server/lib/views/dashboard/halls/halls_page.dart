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
      required RoomMenuConfiguration configuration,
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
      final configuration = await showDialog<RoomMenuConfiguration>(
        context: context,
        builder: (_) =>
            _RoomMenusDialog(spanish: _es, room: room, menus: catalog.menus),
      );
      if (configuration == null || !mounted) return;
      await widget.saveMenus(
        token: widget.token,
        roomId: room.id,
        configuration: configuration,
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
  late int? _primaryMenuId = widget.menus
      .where((menu) => menu.primaryHallIds.contains(widget.room.id))
      .firstOrNull
      ?.id;
  late final Set<int> _secondaryMenuIds = {
    for (final menu in widget.menus)
      if (menu.secondaryHallIds.contains(widget.room.id)) menu.id,
  };
  late final Map<int, Set<int>> _secondaryProductIds = {
    for (final menu in widget.menus)
      menu.id: {
        for (final product in menu.products)
          if (product.hallIds.contains(widget.room.id)) product.id,
      },
  };

  bool get _canSave =>
      _primaryMenuId != null &&
      _secondaryMenuIds.every(
        (menuId) => _secondaryProductIds[menuId]!.isNotEmpty,
      );

  void _toggleSecondary(RestaurantMenu menu, bool selected) {
    setState(() {
      if (selected) {
        _secondaryMenuIds.add(menu.id);
      } else {
        _secondaryMenuIds.remove(menu.id);
      }
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
      width: 620,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.spanish
                  ? 'Escoge el menú principal y, si lo necesitas, menús secundarios con sus productos permitidos.'
                  : 'Choose the primary menu and, if needed, secondary menus with their allowed products.',
              style: const TextStyle(color: Color(0xFF70757A)),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              key: const ValueKey('room-primary-menu'),
              initialValue: _primaryMenuId,
              decoration: InputDecoration(
                labelText: widget.spanish
                    ? 'Escoger menú principal'
                    : 'Choose primary menu',
                prefixIcon: const Icon(Icons.menu_book_outlined),
              ),
              items: [
                for (final menu in widget.menus)
                  DropdownMenuItem(value: menu.id, child: Text(menu.name)),
              ],
              onChanged: (menuId) => setState(() {
                _primaryMenuId = menuId;
                if (menuId != null) _secondaryMenuIds.remove(menuId);
              }),
            ),
            const SizedBox(height: 22),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.spanish ? 'Menús secundarios' : 'Secondary menus',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            for (final menu in widget.menus)
              if (menu.id != _primaryMenuId)
                _SecondaryMenuOption(
                  spanish: widget.spanish,
                  roomId: widget.room.id,
                  menu: menu,
                  selected: _secondaryMenuIds.contains(menu.id),
                  selectedProductIds: _secondaryProductIds[menu.id]!,
                  onSelected: (selected) => _toggleSecondary(menu, selected),
                  onProductChanged: (productId, selected) => setState(() {
                    if (selected) {
                      _secondaryProductIds[menu.id]!.add(productId);
                    } else {
                      _secondaryProductIds[menu.id]!.remove(productId);
                    }
                  }),
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
        onPressed: !_canSave
            ? null
            : () => Navigator.pop(
                context,
                RoomMenuConfiguration(
                  primaryMenuId: _primaryMenuId!,
                  secondaryMenus: [
                    for (final menuId in _secondaryMenuIds)
                      SecondaryRoomMenuSelection(
                        menuId: menuId,
                        productIds: _secondaryProductIds[menuId]!.toList(),
                      ),
                  ],
                ),
              ),
        icon: const Icon(Icons.save_outlined),
        label: Text(widget.spanish ? 'Guardar' : 'Save'),
      ),
    ],
  );
}

class _SecondaryMenuOption extends StatelessWidget {
  const _SecondaryMenuOption({
    required this.spanish,
    required this.roomId,
    required this.menu,
    required this.selected,
    required this.selectedProductIds,
    required this.onSelected,
    required this.onProductChanged,
  });

  final bool spanish;
  final int roomId;
  final RestaurantMenu menu;
  final bool selected;
  final Set<int> selectedProductIds;
  final ValueChanged<bool> onSelected;
  final void Function(int productId, bool selected) onProductChanged;

  @override
  Widget build(BuildContext context) {
    final choices = _menuProductChoices(menu);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF7F8F9),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Color(0xFFE2E5E8)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            CheckboxListTile(
              key: ValueKey('secondary-menu-${menu.id}'),
              value: selected,
              onChanged: choices.isEmpty
                  ? null
                  : (value) => onSelected(value ?? false),
              title: Text(menu.name),
              subtitle: choices.isEmpty
                  ? Text(spanish ? 'No tiene productos' : 'No products')
                  : Text(
                      spanish
                          ? '${selectedProductIds.length} productos permitidos'
                          : '${selectedProductIds.length} allowed products',
                    ),
              controlAffinity: ListTileControlAffinity.leading,
            ),
            if (selected) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    spanish
                        ? 'Escoge los productos disponibles:'
                        : 'Choose the available products:',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              for (final choice in choices)
                CheckboxListTile(
                  key: ValueKey(
                    'secondary-product-${menu.id}-${choice.product.id}',
                  ),
                  dense: true,
                  value: selectedProductIds.contains(choice.product.id),
                  onChanged: (value) =>
                      onProductChanged(choice.product.id, value ?? false),
                  title: Text(choice.product.name),
                  subtitle: Text(choice.categoryPath),
                  controlAffinity: ListTileControlAffinity.leading,
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MenuProductChoice {
  const _MenuProductChoice(this.product, this.categoryPath);
  final CatalogProduct product;
  final String categoryPath;
}

List<_MenuProductChoice> _menuProductChoices(RestaurantMenu menu) {
  final result = <_MenuProductChoice>[];
  void visit(MenuCategory category, List<String> parents) {
    final path = [...parents, category.name];
    for (final product in category.products.where((item) => item.isActive)) {
      result.add(_MenuProductChoice(product, path.join(' › ')));
    }
    for (final child in category.subcategories) {
      visit(child, path);
    }
  }

  for (final category in menu.categories) {
    visit(category, const []);
  }
  return result;
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
