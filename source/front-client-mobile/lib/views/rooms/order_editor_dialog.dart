import 'package:flutter/material.dart';

import '../../models/client_order.dart';
import '../../services/client_rooms_api.dart';
import '../../utils/money.dart';

class OrderEditorDialog extends StatefulWidget {
  const OrderEditorDialog({
    super.key,
    required this.spanish,
    required this.tableLabel,
    required this.menus,
    required this.existingOrder,
    required this.onSubmit,
  });
  final bool spanish;
  final String tableLabel;
  final List<ClientRoomMenu> menus;
  final ClientOrder? existingOrder;
  final Future<void> Function(String description, List<OrderItemWrite> items)
  onSubmit;
  @override
  State<OrderEditorDialog> createState() => _OrderEditorDialogState();
}

class _OrderEditorDialogState extends State<OrderEditorDialog> {
  final Map<String, _DraftLine> _lines = {};
  final List<Map<String, _DraftLine>> _undo = [];
  int _nextLine = 1;
  final _orderDescription = TextEditingController();
  int? _categoryId;
  bool _saving = false;
  String? _submitError;
  bool get _es => widget.spanish;
  List<ClientMenuCategory> get _categories => [
    for (final menu in widget.menus) ...menu.categories,
  ];
  List<ClientMenuProduct> get _products => [
    for (final category in _categories) ...category.products,
  ];

  @override
  void initState() {
    super.initState();
    _orderDescription.text = widget.existingOrder?.description ?? '';
    final existing = widget.existingOrder;
    if (existing != null) {
      for (final item in existing.items) {
        final product = _products
            .where((value) => value.id == item.productId)
            .firstOrNull;
        if (product == null) continue;
        final parentKey = item.parentOrderItemId == null
            ? null
            : 'existing:${item.parentOrderItemId}';
        _lines['existing:${item.id}'] = _DraftLine(
          product: product,
          quantity: item.quantity,
          deliveredQuantity: item.deliveredQuantity,
          specifications: item.specifications ?? '',
          removedIngredientIds: {...item.removedIngredientIds},
          parentLineKey: parentKey,
        );
      }
    }
  }

  @override
  void dispose() {
    _orderDescription.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFFAF9F6),
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [
                BoxShadow(color: Color(0x44000000), blurRadius: 30),
              ],
            ),
            child: Column(
              children: [
                _header(),
                const Divider(height: 1),
                _selectedProducts(),
                const Divider(height: 1),
                Expanded(child: _catalog()),
                const Divider(height: 1),
                _footer(),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _header() => Padding(
    padding: const EdgeInsets.fromLTRB(22, 16, 12, 14),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _es
                    ? 'Pedido · Mesa ${widget.tableLabel}'
                    : 'Order · Table ${widget.tableLabel}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                widget.existingOrder == null
                    ? (_es ? 'Nuevo pedido' : 'New order')
                    : (_es
                          ? 'Modificar pedido enviado'
                          : 'Modify submitted order'),
                style: const TextStyle(color: Color(0xFF73777C)),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('undo-order-edit'),
          tooltip: _es ? 'Deshacer' : 'Undo',
          onPressed: _saving || _undo.isEmpty ? null : _undoLast,
          icon: const Icon(Icons.undo_rounded),
        ),
        IconButton(
          key: const ValueKey('close-order-editor'),
          onPressed: _saving ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _selectedProducts() {
    final selected = _lines.values.where((line) => line.quantity > 0).toList();
    return SizedBox(
      height: 82,
      child: selected.isEmpty
          ? Center(
              child: Text(
                _es
                    ? 'Aún no hay productos seleccionados.'
                    : 'No products selected yet.',
                style: const TextStyle(color: Color(0xFF7A7D82)),
              ),
            )
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              itemCount: selected.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, index) {
                final entry = _lines.entries
                    .where((entry) => entry.value.quantity > 0)
                    .elementAt(index);
                final line = entry.value;
                return InputChip(
                  key: ValueKey('selected-order-line-${entry.key}'),
                  avatar: CircleAvatar(child: Text('${line.quantity}')),
                  label: Text(line.product.name),
                  onPressed: () =>
                      _showProductDetails(line.product, draftKey: entry.key),
                  onDeleted: _canRemove(entry.key)
                      ? () => _removeOne(entry.key)
                      : null,
                  deleteIcon: const Icon(Icons.remove_circle_outline, size: 19),
                  deleteButtonTooltipMessage: _es
                      ? 'Quitar una unidad no entregada'
                      : 'Remove one undelivered unit',
                );
              },
            ),
    );
  }

  Widget _catalog() {
    final current = _categories
        .where((item) => item.id == _categoryId)
        .firstOrNull;
    if (current == null) {
      final roots = _categories
          .where((item) => item.parentCategoryId == null)
          .toList();
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        itemCount: roots.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          final category = roots[index];
          return _CategoryButton(
            key: ValueKey('order-category-${category.id}'),
            category: category,
            onTap: () => setState(() => _categoryId = category.id),
          );
        },
      );
    }
    final children = _categories
        .where((item) => item.parentCategoryId == current.id)
        .toList();
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            IconButton(
              onPressed: () =>
                  setState(() => _categoryId = current.parentCategoryId),
              icon: const Icon(Icons.arrow_back),
            ),
            Expanded(
              child: Text(
                current.name,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        if (children.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (var index = 0; index < children.length; index++) ...[
            _CategoryButton(
              key: ValueKey('order-category-${children[index].id}'),
              category: children[index],
              onTap: () => setState(() => _categoryId = children[index].id),
            ),
            if (index < children.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 16),
        ],
        for (final product in current.products) _productRow(product),
      ],
    );
  }

  Widget _productRow(ClientMenuProduct product) {
    final quantity = _lines[_defaultKey(product.id)]?.quantity ?? 0;
    return Card(
      key: ValueKey('order-product-${product.id}'),
      child: InkWell(
        onTap: () => _showProductDetails(product),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      formatPesos(product.value),
                      style: const TextStyle(
                        color: Color(0xFF71859B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if ((product.description ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          product.description!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: Color(0xFF777B80)),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton(
                key: ValueKey('decrease-product-${product.id}'),
                onPressed: quantity == 0 ? null : () => _change(product, -1),
                icon: const Icon(Icons.remove_circle_outline),
              ),
              SizedBox(
                width: 24,
                child: Text('$quantity', textAlign: TextAlign.center),
              ),
              IconButton(
                key: ValueKey('increase-product-${product.id}'),
                onPressed: () => _change(product, 1),
                icon: const Icon(Icons.add_circle_outline),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _change(ClientMenuProduct product, int delta) {
    _remember();
    setState(() {
      final key = _defaultKey(product.id);
      final line = _lines.putIfAbsent(key, () => _DraftLine(product: product));
      line.quantity = (line.quantity + delta).clamp(0, 99);
      if (line.quantity == 0) _lines.remove(key);
    });
  }

  bool _canRemove(String key) {
    final line = _lines[key];
    if (line == null || line.quantity <= line.deliveredQuantity) return false;
    if (line.parentLineKey != null) return true;
    return !_lines.values.any(
      (candidate) =>
          candidate.parentLineKey == key && candidate.deliveredQuantity > 0,
    );
  }

  void _removeOne(String key) {
    if (!_canRemove(key)) return;
    _remember();
    setState(() {
      final line = _lines[key]!;
      line.quantity--;
      if (line.quantity == 0) {
        _lines.remove(key);
        _lines.removeWhere((_, candidate) => candidate.parentLineKey == key);
      }
    });
  }

  Future<void> _showProductDetails(
    ClientMenuProduct product, {
    String? draftKey,
  }) async {
    final editingExisting = draftKey != null && _lines.containsKey(draftKey);
    final line = editingExisting
        ? _lines[draftKey]!
        : _DraftLine(product: product, quantity: 1);
    final notes = TextEditingController(text: line.specifications);
    final removed = {...line.removedIngredientIds};
    final specialCategories = _isSpecialProduct(product.id)
        ? const <ClientMenuCategory>[]
        : [
            for (final menu in widget.menus)
              if (menu.categories.any(
                (category) => category.products.any(
                  (candidate) => candidate.id == product.id,
                ),
              ))
                ...menu.categories.where((category) => category.isSpecial),
          ];
    final specialQuantities = {
      for (final category in specialCategories)
        for (final special in category.products)
          special.id: editingExisting
              ? _lines.values
                        .where(
                          (line) =>
                              line.parentLineKey == draftKey &&
                              line.product.id == special.id,
                        )
                        .firstOrNull
                        ?.quantity ??
                    0
              : 0,
    };
    int? selectedSpecialCategoryId;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: _es ? 'Editar producto' : 'Edit product',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      transitionBuilder: (_, animation, _, child) => FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: ScaleTransition(
          scale: Tween(begin: .98, end: 1.0).animate(animation),
          child: child,
        ),
      ),
      pageBuilder: (context, _, _) => StatefulBuilder(
        builder: (context, modalSetState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 22, 12, 8),
          title: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFE9EFF5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.restaurant_menu,
                  color: Color(0xFF71859B),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      formatPesos(product.value),
                      style: const TextStyle(
                        color: Color(0xFF71859B),
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if ((product.description ?? '').isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF4F5F6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        product.description!,
                        style: const TextStyle(
                          color: Color(0xFF5F646A),
                          height: 1.35,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: notes,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: _es
                          ? 'Descripción o indicaciones'
                          : 'Notes or instructions',
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(
                    icon: Icons.eco_outlined,
                    label: _es ? 'Ingredientes' : 'Ingredients',
                  ),
                  if (product.ingredients.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _es
                            ? 'Este producto no tiene ingredientes registrados.'
                            : 'This product has no registered ingredients.',
                        style: const TextStyle(color: Color(0xFF7A7D82)),
                      ),
                    ),
                  for (final ingredient in product.ingredients)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E5E8)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: CheckboxListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                        ),
                        dense: true,
                        title: Text(ingredient.name),
                        value: !removed.contains(ingredient.id),
                        onChanged: (included) => modalSetState(() {
                          included == true
                              ? removed.remove(ingredient.id)
                              : removed.add(ingredient.id);
                        }),
                      ),
                    ),
                  if (specialCategories.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionTitle(
                      icon: Icons.auto_awesome_outlined,
                      label: _es
                          ? 'Personaliza con categorías especiales'
                          : 'Customize with special categories',
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final category in specialCategories)
                          _SpecialCategoryButton(
                            key: ValueKey('special-category-${category.id}'),
                            category: category,
                            selected: selectedSpecialCategoryId == category.id,
                            quantity: category.products.fold(
                              0,
                              (total, item) =>
                                  total + (specialQuantities[item.id] ?? 0),
                            ),
                            onTap: () => modalSetState(() {
                              selectedSpecialCategoryId =
                                  selectedSpecialCategoryId == category.id
                                  ? null
                                  : category.id;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SizeTransition(
                          sizeFactor: animation,
                          alignment: Alignment.topCenter,
                          child: child,
                        ),
                      ),
                      child: selectedSpecialCategoryId == null
                          ? const SizedBox.shrink()
                          : _SpecialProductsPanel(
                              key: ValueKey(selectedSpecialCategoryId),
                              category: specialCategories.firstWhere(
                                (item) => item.id == selectedSpecialCategoryId,
                              ),
                              quantities: specialQuantities,
                              onChanged: (special, delta) => modalSetState(() {
                                specialQuantities[special.id] =
                                    ((specialQuantities[special.id] ?? 0) +
                                            delta)
                                        .clamp(0, 99);
                              }),
                            ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(_es ? 'Cancelar' : 'Cancel'),
            ),
            FilledButton(
              onPressed: () {
                _remember();
                setState(() {
                  final targetKey = editingExisting
                      ? draftKey
                      : 'custom:${_nextLine++}';
                  line.specifications = notes.text.trim();
                  line.removedIngredientIds = removed;
                  if (line.quantity == 0) line.quantity = 1;
                  _lines[targetKey] = line;
                  final specialIds = {
                    for (final category in specialCategories)
                      for (final special in category.products) special.id,
                  };
                  _lines.removeWhere(
                    (_, candidate) =>
                        candidate.parentLineKey == targetKey &&
                        specialIds.contains(candidate.product.id),
                  );
                  for (final category in specialCategories) {
                    for (final special in category.products) {
                      final specialKey = 'special:$targetKey:${special.id}';
                      final quantity = specialQuantities[special.id] ?? 0;
                      if (quantity == 0) {
                        _lines.remove(specialKey);
                      } else {
                        final specialLine = _lines.putIfAbsent(
                          specialKey,
                          () => _DraftLine(
                            product: special,
                            parentLineKey: targetKey,
                          ),
                        );
                        specialLine.quantity = quantity;
                      }
                    }
                  }
                });
                Navigator.pop(context);
              },
              child: Text(_es ? 'Guardar cambios' : 'Save changes'),
            ),
          ],
        ),
      ),
    );
    notes.dispose();
  }

  String _defaultKey(int productId) => 'default:$productId';

  void _remember() => _undo.add({
    for (final entry in _lines.entries) entry.key: entry.value.copy(),
  });

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _lines
        ..clear()
        ..addAll(_undo.removeLast());
    });
  }

  bool _isSpecialProduct(int productId) => _categories
      .where((category) => category.isSpecial)
      .any((category) => category.products.any((item) => item.id == productId));

  Widget _footer() => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_submitError != null) ...[
          Text(_submitError!, style: const TextStyle(color: Color(0xFFB64A4A))),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _orderDescription,
                decoration: InputDecoration(
                  labelText: _es
                      ? 'Nota general del pedido'
                      : 'General order note',
                ),
              ),
            ),
            const SizedBox(width: 14),
            FilledButton.icon(
              key: const ValueKey('submit-order'),
              onPressed:
                  _saving ||
                      (widget.existingOrder == null &&
                          !_lines.values.any((line) => line.quantity > 0))
                  ? null
                  : _submit,
              style:
                  widget.existingOrder != null &&
                      !_lines.values.any((line) => line.quantity > 0)
                  ? FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFB64A4A),
                    )
                  : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      widget.existingOrder != null &&
                              !_lines.values.any((line) => line.quantity > 0)
                          ? Icons.delete_outline
                          : Icons.send_outlined,
                    ),
              label: Text(
                widget.existingOrder != null &&
                        !_lines.values.any((line) => line.quantity > 0)
                    ? (_es ? 'Eliminar pedido' : 'Delete order')
                    : (_es ? 'Enviar' : 'Send'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _submitError = null;
    });
    final normal = _lines.entries
        .where(
          (entry) =>
              entry.value.parentLineKey == null && entry.value.quantity > 0,
        )
        .toList();
    final specials = _lines.entries
        .where(
          (entry) =>
              entry.value.parentLineKey != null && entry.value.quantity > 0,
        )
        .toList();
    final ordered = [...normal, ...specials];
    final indexByLineKey = {
      for (var index = 0; index < normal.length; index++)
        normal[index].key: index,
    };
    try {
      await widget.onSubmit(_orderDescription.text.trim(), [
        for (final entry in ordered)
          OrderItemWrite(
            productId: entry.value.product.id,
            quantity: entry.value.quantity,
            specifications: entry.value.specifications,
            removedIngredientIds: entry.value.removedIngredientIds.toList(),
            parentIndex: entry.value.parentLineKey == null
                ? null
                : indexByLineKey[entry.value.parentLineKey],
          ),
      ]);
      if (mounted) Navigator.pop(context);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          final code = error is ClientRoomsException ? error.code : null;
          _submitError = code == 'DELIVERED_ITEM_CANNOT_BE_REMOVED'
              ? (_es
                    ? 'No se pueden retirar productos que ya fueron entregados.'
                    : 'Delivered products cannot be removed.')
              : code == 'ORDER_ITEMS_REQUIRED'
              ? (_es
                    ? 'El servidor está desactualizado y todavía rechaza pedidos vacíos.'
                    : 'The server is outdated and still rejects empty orders.')
              : (_es
                    ? 'No se pudo guardar el pedido${code == null ? '.' : ' ($code).'}'
                    : 'The order could not be saved${code == null ? '.' : ' ($code).'}');
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DraftLine {
  _DraftLine({
    required this.product,
    this.quantity = 0,
    this.deliveredQuantity = 0,
    this.specifications = '',
    Set<int>? removedIngredientIds,
    this.parentLineKey,
  }) : removedIngredientIds = removedIngredientIds ?? {};
  final ClientMenuProduct product;
  int quantity;
  int deliveredQuantity;
  String specifications;
  Set<int> removedIngredientIds;
  String? parentLineKey;

  _DraftLine copy() => _DraftLine(
    product: product,
    quantity: quantity,
    deliveredQuantity: deliveredQuantity,
    specifications: specifications,
    removedIngredientIds: {...removedIngredientIds},
    parentLineKey: parentLineKey,
  );
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    super.key,
    required this.category,
    required this.onTap,
  });
  final ClientMenuCategory category;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: const BorderSide(color: Color(0xFFE1E5E9)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      splashColor: const Color(0x2271859B),
      hoverColor: const Color(0xFFF2F5F8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF0F5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.restaurant_menu_rounded,
                color: Color(0xFF647C94),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                category.name,
                style: const TextStyle(
                  color: Color(0xFF292D32),
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: Color(0xFF98A2AD),
            ),
          ],
        ),
      ),
    ),
  );
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 19, color: const Color(0xFF71859B)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          label,
          softWrap: true,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
        ),
      ),
    ],
  );
}

class _SpecialCategoryButton extends StatelessWidget {
  const _SpecialCategoryButton({
    super.key,
    required this.category,
    required this.selected,
    required this.quantity,
    required this.onTap,
  });

  final ClientMenuCategory category;
  final bool selected;
  final int quantity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    decoration: BoxDecoration(
      color: selected ? const Color(0xFF71859B) : const Color(0xFFF2F5F8),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: selected ? const Color(0xFF71859B) : const Color(0xFFDCE2E7),
      ),
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.add_circle_outline_rounded,
                size: 18,
                color: selected ? Colors.white : const Color(0xFF71859B),
              ),
              const SizedBox(width: 7),
              Text(
                category.name,
                style: TextStyle(
                  color: selected ? Colors.white : const Color(0xFF3D4751),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (quantity > 0) ...[
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 22),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : const Color(0xFF71859B),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$quantity',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: selected ? const Color(0xFF71859B) : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 5),
              AnimatedRotation(
                turns: selected ? .5 : 0,
                duration: const Duration(milliseconds: 180),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 19,
                  color: selected ? Colors.white : const Color(0xFF71859B),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _SpecialProductsPanel extends StatelessWidget {
  const _SpecialProductsPanel({
    super.key,
    required this.category,
    required this.quantities,
    required this.onChanged,
  });

  final ClientMenuCategory category;
  final Map<int, int> quantities;
  final void Function(ClientMenuProduct product, int delta) onChanged;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE2E7)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F000000),
          blurRadius: 12,
          offset: Offset(0, 4),
        ),
      ],
    ),
    child: category.products.isEmpty
        ? const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'No hay productos en esta categoría.',
              style: TextStyle(color: Color(0xFF7A7D82)),
            ),
          )
        : Column(
            children: [
              for (
                var index = 0;
                index < category.products.length;
                index++
              ) ...[
                if (index > 0) const Divider(height: 1),
                _SpecialProductRow(
                  product: category.products[index],
                  quantity: quantities[category.products[index].id] ?? 0,
                  onChanged: (delta) =>
                      onChanged(category.products[index], delta),
                ),
              ],
            ],
          ),
  );
}

class _SpecialProductRow extends StatelessWidget {
  const _SpecialProductRow({
    required this.product,
    required this.quantity,
    required this.onChanged,
  });

  final ClientMenuProduct product;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                formatPesos(product.value),
                style: const TextStyle(
                  color: Color(0xFF71859B),
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          key: ValueKey('decrease-special-product-${product.id}'),
          visualDensity: VisualDensity.compact,
          onPressed: quantity == 0 ? null : () => onChanged(-1),
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 25,
          child: Text('$quantity', textAlign: TextAlign.center),
        ),
        IconButton(
          key: ValueKey('increase-special-product-${product.id}'),
          visualDensity: VisualDensity.compact,
          onPressed: () => onChanged(1),
          icon: const Icon(Icons.add_circle_outline),
        ),
      ],
    ),
  );
}
