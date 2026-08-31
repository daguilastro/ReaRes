import 'package:flutter/material.dart';

import '../../../services/admin_api.dart';
import '../../../utils/money.dart';
import '../halls/room_layout_models.dart';
import 'catalog_models.dart';

typedef LoadCatalog = Future<CatalogSnapshot> Function(String token);
typedef LoadMenuRooms = Future<List<RoomSummary>> Function(String token);
typedef AddMenu =
    Future<RestaurantMenu> Function({
      required String token,
      required String name,
      required List<MenuHallAssignment> hallAssignments,
    });
typedef AddIngredient =
    Future<CatalogIngredient> Function({
      required String token,
      required String name,
      required int categoryId,
      String? description,
    });
typedef AddCategory =
    Future<MenuCategory> Function({
      required String token,
      required int menuId,
      required String name,
      int? parentCategoryId,
      bool isSpecial,
    });
typedef AddProduct =
    Future<CatalogProduct> Function({
      required String token,
      required int menuId,
      required String name,
      required String description,
      required int value,
      required int categoryId,
      required List<int> ingredientIds,
      required List<int> hallIds,
    });

class MenusPage extends StatefulWidget {
  const MenusPage({
    super.key,
    required this.spanish,
    required this.token,
    this.loadCatalog = getCatalog,
    this.loadRooms = getRooms,
    this.addMenu = createMenu,
    this.addIngredient = createIngredient,
    this.addCategory = createMenuCategory,
    this.addProduct = createMenuProduct,
  });
  final bool spanish;
  final String token;
  final LoadCatalog loadCatalog;
  final LoadMenuRooms loadRooms;
  final AddMenu addMenu;
  final AddIngredient addIngredient;
  final AddCategory addCategory;
  final AddProduct addProduct;
  @override
  State<MenusPage> createState() => _MenusPageState();
}

class _MenusPageState extends State<MenusPage> {
  CatalogSnapshot _catalog = const CatalogSnapshot(menus: [], ingredients: []);
  List<RoomSummary> _rooms = [];
  int? _menuId;
  int? _categoryId;
  int? _subcategoryId;
  bool _loading = true;
  String? _error;
  bool get _es => widget.spanish;
  RestaurantMenu? get _menu =>
      _catalog.menus.where((item) => item.id == _menuId).firstOrNull;
  MenuCategory? get _category =>
      _menu?.categories.where((item) => item.id == _categoryId).firstOrNull;
  MenuCategory? get _subcategory => _category?.subcategories
      .where((item) => item.id == _subcategoryId)
      .firstOrNull;

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
      final values = await Future.wait([
        widget.loadCatalog(widget.token),
        widget.loadRooms(widget.token),
      ]);
      _catalog = values[0] as CatalogSnapshot;
      _rooms = values[1] as List<RoomSummary>;
      if (_menuId != null && _menu == null) _resetNavigation();
    } on Object {
      _error = _es
          ? 'No se pudo cargar el catálogo.'
          : 'The catalog could not be loaded.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _resetNavigation() {
    _menuId = null;
    _categoryId = null;
    _subcategoryId = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: OutlinedButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh),
          label: Text(_error!),
        ),
      );
    }
    if (_subcategory != null) {
      return _categoryDetail(_subcategory!, subcategory: true);
    }
    if (_category != null) return _categoryDetail(_category!);
    if (_menu != null) return _menuDetail(_menu!);
    return _overview();
  }

  Widget _overview() => ListView(
    padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
    children: [
      _pageHeader(
        title: _es ? 'Menús' : 'Menus',
        subtitle: _es
            ? 'Configura el menú principal y las selecciones secundarias de cada salón.'
            : 'Configure each room main menu and its secondary selections.',
        actions: [
          FilledButton.icon(
            key: const ValueKey('add-menu'),
            onPressed: _createMenu,
            icon: const Icon(Icons.add),
            label: Text(_es ? 'Añadir menú' : 'Add menu'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      if (_catalog.menus.isEmpty)
        _empty(_es ? 'Aún no hay menús' : 'No menus yet')
      else
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 950
                ? 3
                : constraints.maxWidth >= 600
                ? 2
                : 1;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _catalog.menus.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                mainAxisExtent: 190,
              ),
              itemBuilder: (context, index) {
                final menu = _catalog.menus[index];
                return _CatalogCard(
                  key: ValueKey('menu-card-${menu.id}'),
                  icon: Icons.menu_book_outlined,
                  title: menu.name,
                  lines: [
                    '${menu.categories.length} ${_es ? 'categorías' : 'categories'} · ${menu.productCount} ${_es ? 'productos' : 'products'}',
                    '${menu.primaryHallIds.length} ${_es ? 'principales' : 'primary'} · ${menu.secondaryHallIds.length} ${_es ? 'secundarios' : 'secondary'}',
                  ],
                  onTap: () => setState(() => _menuId = menu.id),
                );
              },
            );
          },
        ),
    ],
  );

  Widget _menuDetail(RestaurantMenu menu) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
    children: [
      _pageHeader(
        back: () => setState(_resetNavigation),
        title: menu.name,
        subtitle: _assignmentText(menu),
        actions: [
          OutlinedButton.icon(
            key: const ValueKey('add-category'),
            onPressed: () => _createCategory(menu),
            icon: const Icon(Icons.category_outlined),
            label: Text(_es ? 'Añadir categoría' : 'Add category'),
          ),
          FilledButton.icon(
            key: const ValueKey('add-ingredient'),
            onPressed: _catalog.ingredientCategories.isEmpty
                ? null
                : _createIngredientQuick,
            icon: const Icon(Icons.grass_outlined),
            label: Text(_es ? 'Añadir ingrediente' : 'Add ingredient'),
          ),
        ],
      ),
      const SizedBox(height: 24),
      if (menu.categories.isEmpty)
        _empty(_es ? 'Crea la primera categoría' : 'Create the first category')
      else
        for (final category in menu.categories) ...[
          _CatalogCard(
            icon: category.isSpecial
                ? Icons.auto_awesome_outlined
                : Icons.category_outlined,
            title: category.name,
            badge: category.isSpecial ? (_es ? 'Especial' : 'Special') : null,
            lines: [
              '${category.products.length} ${_es ? 'productos' : 'products'}',
              '${category.subcategories.length} ${_es ? 'subcategorías' : 'subcategories'}',
            ],
            onTap: () => setState(() => _categoryId = category.id),
          ),
          const SizedBox(height: 14),
        ],
    ],
  );

  Widget _categoryDetail(MenuCategory category, {bool subcategory = false}) {
    final menu = _menu!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 24, 28, 40),
      children: [
        _pageHeader(
          back: () => setState(() {
            if (subcategory) {
              _subcategoryId = null;
            } else {
              _categoryId = null;
            }
          }),
          title: category.name,
          subtitle: category.isSpecial
              ? (_es
                    ? 'Categoría especial: combos, adiciones u otros productos asociados.'
                    : 'Special category: combos, additions, or associated products.')
              : (subcategory
                    ? (_es ? 'Subcategoría' : 'Subcategory')
                    : menu.name),
          actions: [
            if (!subcategory && !category.isSpecial)
              OutlinedButton.icon(
                key: const ValueKey('add-subcategory'),
                onPressed: () => _createCategory(menu, parent: category),
                icon: const Icon(Icons.account_tree_outlined),
                label: Text(_es ? 'Añadir subcategoría' : 'Add subcategory'),
              ),
            FilledButton.icon(
              key: const ValueKey('add-product'),
              onPressed: () => _createProduct(menu, category),
              icon: const Icon(Icons.add),
              label: Text(_es ? 'Añadir producto' : 'Add product'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        if (!subcategory && category.subcategories.isNotEmpty) ...[
          Text(
            _es ? 'Subcategorías' : 'Subcategories',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          for (final child in category.subcategories) ...[
            _CatalogCard(
              icon: Icons.account_tree_outlined,
              title: child.name,
              badge: child.isSpecial ? (_es ? 'Especial' : 'Special') : null,
              lines: [
                '${child.products.length} ${_es ? 'productos' : 'products'}',
              ],
              onTap: () => setState(() => _subcategoryId = child.id),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
        ],
        Text(
          _es ? 'Productos' : 'Products',
          style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        if (category.products.isEmpty)
          _empty(_es ? 'No hay productos.' : 'No products.')
        else
          DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7E9)),
            ),
            child: Column(
              children: [
                for (final product in category.products)
                  ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: Color(0xFFE9EEF3),
                      child: Icon(
                        Icons.restaurant_menu,
                        color: Color(0xFF71859B),
                      ),
                    ),
                    title: Text(product.name),
                    subtitle: Text(product.description ?? ''),
                    trailing: Text(formatPesos(product.value)),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _pageHeader({
    VoidCallback? back,
    required String title,
    required String subtitle,
    required List<Widget> actions,
  }) => Wrap(
    alignment: WrapAlignment.spaceBetween,
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 16,
    runSpacing: 12,
    children: [
      SizedBox(
        width: 500,
        child: Row(
          children: [
            if (back != null) ...[
              IconButton(onPressed: back, icon: const Icon(Icons.arrow_back)),
              const SizedBox(width: 5),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Color(0xFF72767B)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      Wrap(spacing: 10, runSpacing: 8, children: actions),
    ],
  );

  Widget _empty(String text) => Container(
    padding: const EdgeInsets.all(38),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(text, style: const TextStyle(color: Color(0xFF72767B))),
  );

  String _assignmentText(RestaurantMenu menu) {
    String names(List<int> ids) => _rooms
        .where((room) => ids.contains(room.id))
        .map((room) => room.name)
        .join(', ');
    final primary = names(menu.primaryHallIds);
    final secondary = names(menu.secondaryHallIds);
    return '${_es ? 'Principal' : 'Primary'}: ${primary.isEmpty ? '—' : primary} · '
        '${_es ? 'Secundario' : 'Secondary'}: ${secondary.isEmpty ? '—' : secondary}';
  }

  Future<void> _createMenu() async {
    final draft = await showDialog<_MenuDraft>(
      context: context,
      builder: (_) => _MenuDialog(spanish: _es, rooms: _rooms),
    );
    if (draft == null) return;
    await _write(
      () => widget.addMenu(
        token: widget.token,
        name: draft.name,
        hallAssignments: draft.assignments,
      ),
    );
  }

  Future<void> _createCategory(
    RestaurantMenu menu, {
    MenuCategory? parent,
  }) async {
    if (parent != null && parent.isSpecial) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: const Color(0xFFB64A4A),
          content: Text(
            _es
                ? 'Una categoría especial no puede tener subcategorías.'
                : 'A special category cannot have subcategories.',
          ),
        ),
      );
      return;
    }
    final draft = await showDialog<_CategoryDraft>(
      context: context,
      builder: (_) =>
          _CategoryDialog(spanish: _es, subcategory: parent != null),
    );
    if (draft == null) return;
    await _write(
      () => widget.addCategory(
        token: widget.token,
        menuId: menu.id,
        name: draft.name,
        parentCategoryId: parent?.id,
        isSpecial: draft.isSpecial,
      ),
    );
  }

  Future<void> _createIngredientQuick() async {
    final draft = await showDialog<_IngredientDraft>(
      context: context,
      builder: (_) => _IngredientDialog(
        spanish: _es,
        categories: _catalog.ingredientCategories,
      ),
    );
    if (draft == null) return;
    await _write(
      () => widget.addIngredient(
        token: widget.token,
        name: draft.name,
        categoryId: draft.categoryId,
        description: draft.description,
      ),
    );
  }

  Future<void> _createProduct(
    RestaurantMenu menu,
    MenuCategory category,
  ) async {
    final draft = await showDialog<_ProductDraft>(
      context: context,
      builder: (_) => _ProductDialog(
        spanish: _es,
        ingredients: _catalog.ingredients,
        secondaryRooms: _rooms
            .where((room) => menu.secondaryHallIds.contains(room.id))
            .toList(),
      ),
    );
    if (draft == null) return;
    await _write(
      () => widget.addProduct(
        token: widget.token,
        menuId: menu.id,
        name: draft.name,
        description: draft.description,
        value: draft.value,
        categoryId: category.id,
        ingredientIds: draft.ingredientIds,
        hallIds: draft.hallIds,
      ),
    );
  }

  Future<void> _write(Future<Object> Function() action) async {
    try {
      await action();
      if (mounted) await _load();
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFB64A4A),
            content: Text(_es ? 'No se pudo guardar.' : 'Could not save.'),
          ),
        );
      }
    }
  }
}

class _CatalogCard extends StatelessWidget {
  const _CatalogCard({
    super.key,
    required this.icon,
    required this.title,
    required this.lines,
    required this.onTap,
    this.badge,
  });
  final IconData icon;
  final String title;
  final List<String> lines;
  final VoidCallback onTap;
  final String? badge;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
    elevation: 1,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: const Color(0xFFE9EEF3),
              child: Icon(icon, color: const Color(0xFF71859B)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (badge != null)
                        Chip(
                          label: Text(badge!),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                  for (final line in lines)
                    Text(
                      line,
                      style: const TextStyle(
                        color: Color(0xFF72767B),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    ),
  );
}

enum _AssignmentMode { none, primary, secondary }

class _MenuDraft {
  const _MenuDraft(this.name, this.assignments);
  final String name;
  final List<MenuHallAssignment> assignments;
}

class _MenuDialog extends StatefulWidget {
  const _MenuDialog({required this.spanish, required this.rooms});
  final bool spanish;
  final List<RoomSummary> rooms;
  @override
  State<_MenuDialog> createState() => _MenuDialogState();
}

class _MenuDialogState extends State<_MenuDialog> {
  final _name = TextEditingController();
  final Map<int, _AssignmentMode> _modes = {};
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.spanish ? 'Nuevo menú' : 'New menu'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: const ValueKey('new-menu-name'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.spanish ? 'Nombre' : 'Name',
              ),
            ),
            const SizedBox(height: 16),
            for (final room in widget.rooms)
              DropdownButtonFormField<_AssignmentMode>(
                initialValue: _modes[room.id] ?? _AssignmentMode.none,
                decoration: InputDecoration(labelText: room.name),
                items: [
                  DropdownMenuItem(
                    value: _AssignmentMode.none,
                    child: Text(
                      widget.spanish ? 'No asignado' : 'Not assigned',
                    ),
                  ),
                  DropdownMenuItem(
                    value: _AssignmentMode.primary,
                    child: Text(
                      widget.spanish ? 'Menú principal' : 'Primary menu',
                    ),
                  ),
                  DropdownMenuItem(
                    value: _AssignmentMode.secondary,
                    child: Text(
                      widget.spanish ? 'Menú secundario' : 'Secondary menu',
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _modes[room.id] = value!),
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
      FilledButton(
        key: const ValueKey('submit-menu'),
        onPressed: () {
          if (_name.text.trim().length < 2) return;
          Navigator.pop(
            context,
            _MenuDraft(_name.text.trim(), [
              for (final room in widget.rooms)
                if ((_modes[room.id] ?? _AssignmentMode.none) !=
                    _AssignmentMode.none)
                  MenuHallAssignment(
                    hallId: room.id,
                    isPrimary: _modes[room.id] == _AssignmentMode.primary,
                  ),
            ]),
          );
        },
        child: Text(widget.spanish ? 'Crear' : 'Create'),
      ),
    ],
  );
}

class _CategoryDraft {
  const _CategoryDraft(this.name, this.isSpecial);
  final String name;
  final bool isSpecial;
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({required this.spanish, required this.subcategory});
  final bool spanish;
  final bool subcategory;
  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  final _name = TextEditingController();
  bool _special = false;
  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.subcategory
          ? (widget.spanish ? 'Nueva subcategoría' : 'New subcategory')
          : (widget.spanish ? 'Nueva categoría' : 'New category'),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          decoration: InputDecoration(
            labelText: widget.spanish ? 'Nombre' : 'Name',
          ),
        ),
        if (!widget.subcategory)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _special,
            title: Text(
              widget.spanish ? 'Categoría especial' : 'Special category',
            ),
            onChanged: (value) => setState(() => _special = value),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().length >= 2) {
            Navigator.pop(context, _CategoryDraft(_name.text.trim(), _special));
          }
        },
        child: Text(widget.spanish ? 'Crear' : 'Create'),
      ),
    ],
  );
}

class _IngredientDraft {
  const _IngredientDraft(this.name, this.description, this.categoryId);
  final String name;
  final String description;
  final int categoryId;
}

class _IngredientDialog extends StatefulWidget {
  const _IngredientDialog({required this.spanish, required this.categories});
  final bool spanish;
  final List<IngredientCategory> categories;
  @override
  State<_IngredientDialog> createState() => _IngredientDialogState();
}

class _IngredientDialogState extends State<_IngredientDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  late int _categoryId = widget.categories.first.id;
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.spanish ? 'Nuevo ingrediente' : 'New ingredient'),
    content: SizedBox(
      width: 430,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.spanish ? 'Nombre' : 'Name',
            ),
          ),
          TextField(
            controller: _description,
            decoration: InputDecoration(
              labelText: widget.spanish ? 'Descripción' : 'Description',
            ),
          ),
          DropdownButtonFormField<int>(
            initialValue: _categoryId,
            decoration: InputDecoration(
              labelText: widget.spanish ? 'Categoría' : 'Category',
            ),
            items: [
              for (final item in widget.categories)
                DropdownMenuItem(value: item.id, child: Text(item.name)),
            ],
            onChanged: (value) => setState(() => _categoryId = value!),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(widget.spanish ? 'Cancelar' : 'Cancel'),
      ),
      FilledButton(
        onPressed: () {
          if (_name.text.trim().length >= 2) {
            Navigator.pop(
              context,
              _IngredientDraft(
                _name.text.trim(),
                _description.text.trim(),
                _categoryId,
              ),
            );
          }
        },
        child: Text(widget.spanish ? 'Crear' : 'Create'),
      ),
    ],
  );
}

class _ProductDraft {
  const _ProductDraft(
    this.name,
    this.description,
    this.value,
    this.ingredientIds,
    this.hallIds,
  );
  final String name;
  final String description;
  final int value;
  final List<int> ingredientIds;
  final List<int> hallIds;
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({
    required this.spanish,
    required this.ingredients,
    required this.secondaryRooms,
  });
  final bool spanish;
  final List<CatalogIngredient> ingredients;
  final List<RoomSummary> secondaryRooms;
  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final Set<int> _ingredients = {};
  final Set<int> _halls = {};
  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.spanish ? 'Nuevo producto' : 'New product'),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: widget.spanish ? 'Nombre' : 'Name',
              ),
            ),
            TextField(
              controller: _description,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: widget.spanish ? 'Descripción' : 'Description',
              ),
            ),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: widget.spanish ? 'Precio' : 'Price',
                prefixText: '\$ ',
              ),
            ),
            const SizedBox(height: 14),
            Text(widget.spanish ? 'Ingredientes' : 'Ingredients'),
            Wrap(
              spacing: 7,
              children: [
                for (final item in widget.ingredients)
                  FilterChip(
                    label: Text(item.name),
                    selected: _ingredients.contains(item.id),
                    onSelected: (value) => setState(
                      () => value
                          ? _ingredients.add(item.id)
                          : _ingredients.remove(item.id),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              widget.spanish
                  ? 'Mostrar desde este menú secundario en:'
                  : 'Expose from this secondary menu in:',
            ),
            for (final room in widget.secondaryRooms)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _halls.contains(room.id),
                title: Text(room.name),
                onChanged: (value) => setState(
                  () => value == true
                      ? _halls.add(room.id)
                      : _halls.remove(room.id),
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
      FilledButton(
        key: const ValueKey('submit-product'),
        onPressed: () {
          final price = double.tryParse(_price.text.replaceAll(',', '.'));
          if (_name.text.trim().length >= 2 && price != null && price >= 0) {
            Navigator.pop(
              context,
              _ProductDraft(
                _name.text.trim(),
                _description.text.trim(),
                (price * 100).round(),
                _ingredients.toList(),
                _halls.toList(),
              ),
            );
          }
        },
        child: Text(widget.spanish ? 'Crear' : 'Create'),
      ),
    ],
  );
}
