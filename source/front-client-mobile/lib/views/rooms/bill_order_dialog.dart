import 'package:flutter/material.dart';

import '../../models/client_order.dart';
import '../../utils/money.dart';

class BillOrderDialog extends StatefulWidget {
  const BillOrderDialog({
    super.key,
    required this.spanish,
    required this.tableLabel,
    required this.order,
    required this.productsById,
    this.onBill,
    this.readOnly = false,
  });

  final bool spanish;
  final String tableLabel;
  final ClientOrder order;
  final Map<int, ClientMenuProduct> productsById;
  final Future<void> Function()? onBill;
  final bool readOnly;

  @override
  State<BillOrderDialog> createState() => _BillOrderDialogState();
}

class _BillOrderDialogState extends State<BillOrderDialog> {
  bool _billing = false;
  String? _submitError;

  bool get _es => widget.spanish;

  int _lineTotal(ClientOrderItem item) {
    final value = item.unitValue != 0
        ? item.unitValue
        : widget.productsById[item.productId]?.value ?? 0;
    return value * item.quantity;
  }

  int get _totalPesos => widget.order.items.fold<int>(
    0,
    (total, item) => total + _lineTotal(item),
  );

  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760, maxHeight: 700),
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
                Expanded(child: _items()),
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
                    ? 'Caja · Mesa ${widget.tableLabel}'
                    : 'Cashier · Table ${widget.tableLabel}',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                _es ? 'Resumen de consumo' : 'Order summary',
                style: const TextStyle(color: Color(0xFF73777C)),
              ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('close-order-bill'),
          onPressed: _billing ? null : () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
      ],
    ),
  );

  Widget _items() {
    if (widget.order.items.isEmpty && widget.order.removedItems.isEmpty) {
      return Center(
        child: Text(
          _es ? 'No hay productos en este pedido.' : 'No items in this order.',
          style: const TextStyle(color: Color(0xFF7A7D82)),
        ),
      );
    }
    final rows = <Widget>[
      for (final item in widget.order.items)
        for (var unit = 0; unit < item.quantity; unit++)
          _activeItem(item, unit),
      if (widget.order.removedItems.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 12, 2, 4),
          child: Text(
            _es ? 'Productos retirados' : 'Removed products',
            style: const TextStyle(
              color: Color(0xFFAA5A56),
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      for (final item in widget.order.removedItems)
        for (var unit = 0; unit < item.quantity; unit++) _removedItem(item),
    ];
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemBuilder: (_, index) => rows[index],
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemCount: rows.length,
    );
  }

  Widget _activeItem(ClientOrderItem item, int unitIndex) {
    final unit = item.unitValue != 0
        ? item.unitValue
        : widget.productsById[item.productId]?.value ?? 0;
    return Padding(
      padding: EdgeInsets.only(left: item.parentOrderItemId == null ? 0 : 22),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: item.parentOrderItemId == null
              ? Colors.white
              : const Color(0xFFF2F5F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE2E0DD)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(
                item.parentOrderItemId == null
                    ? Icons.receipt_long_outlined
                    : Icons.subdirectory_arrow_right_rounded,
                size: 20,
                color: const Color(0xFF71859B),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.parentOrderItemId == null
                          ? item.name
                          : '+ ${item.name}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    if ((item.specifications ?? '').trim().isNotEmpty)
                      Text(
                        item.specifications!.trim(),
                        style: const TextStyle(color: Color(0xFF7A7D82)),
                      ),
                    if (item.quantity > 1)
                      Text(
                        '${_es ? 'Unidad' : 'Unit'} ${unitIndex + 1}/${item.quantity}',
                        style: const TextStyle(
                          color: Color(0xFF90949A),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                formatPesos(unit),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _removedItem(ClientRemovedOrderItem item) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFF1F0),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFF0CBC8)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.remove_circle_outline, color: Color(0xFFB56B65)),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.parentProductName == null ? item.name : '+ ${item.name}',
                  style: const TextStyle(
                    color: Color(0xFF8D6966),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((item.specifications ?? '').trim().isNotEmpty)
                  Text(
                    item.specifications!.trim(),
                    style: const TextStyle(color: Color(0xFFA38380)),
                  ),
              ],
            ),
          ),
          Text(
            formatPesos(item.unitValue),
            style: const TextStyle(
              color: Color(0xFFB56B65),
              decoration: TextDecoration.lineThrough,
            ),
          ),
        ],
      ),
    ),
  );

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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _es ? 'Total' : 'Total',
                    style: const TextStyle(
                      color: Color(0xFF676B71),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatPesos(_totalPesos),
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            if (!widget.readOnly)
              FilledButton.icon(
                key: const ValueKey('submit-order-bill'),
                onPressed: _billing ? null : _submit,
                icon: _billing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.point_of_sale_outlined),
                label: Text(_es ? 'Facturar' : 'Bill'),
              ),
          ],
        ),
      ],
    ),
  );

  Future<void> _submit() async {
    setState(() {
      _billing = true;
      _submitError = null;
    });
    try {
      await widget.onBill!();
      if (mounted) Navigator.pop(context);
    } on Object {
      if (!mounted) return;
      setState(() {
        _submitError = _es
            ? 'No se pudo facturar esta mesa.'
            : 'This table could not be billed.';
      });
    } finally {
      if (mounted) setState(() => _billing = false);
    }
  }
}
