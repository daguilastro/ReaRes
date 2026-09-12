import 'package:flutter/material.dart';

import '../../models/client_order.dart';
import '../../utils/money.dart';
import 'bill_order_dialog.dart';

typedef LoadFilteredOrders =
    Future<List<ClientOrder>> Function({
      required DateTime from,
      required DateTime to,
      ClientPaymentMethod? paymentMethod,
    });

class DailyOrdersDialog extends StatefulWidget {
  const DailyOrdersDialog({
    super.key,
    required this.spanish,
    required this.orders,
    this.loadOrders,
  });

  final bool spanish;
  final List<ClientOrder> orders;
  final LoadFilteredOrders? loadOrders;

  @override
  State<DailyOrdersDialog> createState() => _DailyOrdersDialogState();
}

class _DailyOrdersDialogState extends State<DailyOrdersDialog> {
  late List<ClientOrder> _orders;
  late DateTime _fromDay;
  late DateTime _toDay;
  ClientPaymentMethod? _paymentMethod;
  bool _loading = false;
  String? _error;

  bool get spanish => widget.spanish;

  @override
  void initState() {
    super.initState();
    _orders = widget.orders;
    final now = DateTime.now();
    _fromDay = DateTime(now.year, now.month, now.day);
    _toDay = _fromDay;
  }

  @override
  Widget build(BuildContext context) {
    final billedOrders = _orders
        .where((order) => order.status == 'closed')
        .where(
          (order) =>
              _paymentMethod == null || order.paymentMethod == _paymentMethod,
        )
        .toList();
    final total = billedOrders.fold<int>(0, (sum, order) => sum + order.total);
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
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
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 12, 14),
                    child: Row(
                      children: [
                        const Icon(Icons.history_rounded),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                spanish
                                    ? 'Historial de ventas'
                                    : 'Sales history',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                _periodLabel(),
                                style: const TextStyle(
                                  color: Color(0xFF73777C),
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
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            OutlinedButton.icon(
                              key: const ValueKey('sales-history-period'),
                              onPressed: _loading ? null : _selectPeriod,
                              icon: const Icon(Icons.date_range_outlined),
                              label: Text(
                                '${_shortDate(_fromDay)} – ${_shortDate(_toDay)}',
                              ),
                            ),
                            _paymentChip(null),
                            for (final method in ClientPaymentMethod.values)
                              _paymentChip(method),
                          ],
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _error!,
                            style: const TextStyle(color: Color(0xFFB64A4A)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : billedOrders.isEmpty
                        ? Center(
                            child: Text(
                              spanish
                                  ? 'Aún no hay cuentas facturadas hoy.'
                                  : 'There are no billed orders today yet.',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(18),
                            itemCount: billedOrders.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 9),
                            itemBuilder: (context, index) {
                              final order = billedOrders[index];
                              return Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.table_restaurant),
                                  ),
                                  title: Text(
                                    '${spanish ? 'Mesa' : 'Table'} ${order.tableLabel}',
                                  ),
                                  subtitle: Wrap(
                                    spacing: 7,
                                    runSpacing: 4,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '${order.items.fold<int>(0, (sum, item) => sum + item.quantity)} ${spanish ? 'productos' : 'items'}',
                                      ),
                                      _PaymentBadge(
                                        spanish: spanish,
                                        method: order.paymentMethod,
                                      ),
                                    ],
                                  ),
                                  trailing: Text(
                                    formatPesos(order.total),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  onTap: () => _openBill(context, order),
                                ),
                              );
                            },
                          ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          spanish ? 'Total del periodo' : 'Period total',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          formatPesos(total),
                          style: const TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _paymentChip(ClientPaymentMethod? method) => ChoiceChip(
    key: ValueKey('history-payment-${method?.apiValue ?? 'all'}'),
    label: Text(
      method == null ? (spanish ? 'Todos' : 'All') : _paymentLabel(method),
    ),
    selected: _paymentMethod == method,
    onSelected: _loading
        ? null
        : (_) {
            setState(() => _paymentMethod = method);
            _reload();
          },
  );

  Future<void> _selectPeriod() async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 366)),
      initialDateRange: DateTimeRange(start: _fromDay, end: _toDay),
      helpText: spanish ? 'Intervalo de cobro' : 'Billing period',
      cancelText: spanish ? 'Cancelar' : 'Cancel',
      confirmText: spanish ? 'Aplicar' : 'Apply',
    );
    if (selected == null || !mounted) return;
    setState(() {
      _fromDay = DateTime(
        selected.start.year,
        selected.start.month,
        selected.start.day,
      );
      _toDay = DateTime(
        selected.end.year,
        selected.end.month,
        selected.end.day,
      );
    });
    await _reload();
  }

  Future<void> _reload() async {
    final loader = widget.loadOrders;
    if (loader == null) {
      setState(() {});
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final from = DateTime(_fromDay.year, _fromDay.month, _fromDay.day, 1);
      final dayAfterEnd = _toDay.add(const Duration(days: 1));
      final to = DateTime(dayAfterEnd.year, dayAfterEnd.month, dayAfterEnd.day);
      final orders = await loader(
        from: from,
        to: to,
        paymentMethod: _paymentMethod,
      );
      if (mounted) setState(() => _orders = orders);
    } on Object {
      if (mounted) {
        setState(() {
          _error = spanish
              ? 'No se pudo actualizar el historial.'
              : 'Could not refresh sales history.';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _periodLabel() => _fromDay == _toDay
      ? '${spanish ? 'Cobrado el' : 'Billed on'} ${_shortDate(_fromDay)}'
      : '${spanish ? 'Cobrado entre' : 'Billed from'} '
            '${_shortDate(_fromDay)} ${spanish ? 'y' : 'to'} ${_shortDate(_toDay)}';

  String _shortDate(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/'
      '${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _paymentLabel(ClientPaymentMethod method) => switch (method) {
    ClientPaymentMethod.cash => spanish ? 'Efectivo' : 'Cash',
    ClientPaymentMethod.transfer => spanish ? 'Transferencia' : 'Transfer',
    ClientPaymentMethod.card => spanish ? 'Tarjeta' : 'Card',
  };

  Future<void> _openBill(BuildContext context, ClientOrder order) =>
      showGeneralDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Order detail',
        barrierColor: Colors.black45,
        transitionDuration: const Duration(milliseconds: 180),
        transitionBuilder: (_, animation, _, child) =>
            FadeTransition(opacity: animation, child: child),
        pageBuilder: (_, _, _) => Padding(
          padding: const EdgeInsets.all(18),
          child: BillOrderDialog(
            spanish: spanish,
            tableLabel: order.tableLabel,
            order: order,
            productsById: const {},
            readOnly: true,
          ),
        ),
      );
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.spanish, required this.method});

  final bool spanish;
  final ClientPaymentMethod? method;

  @override
  Widget build(BuildContext context) {
    final label = switch (method) {
      ClientPaymentMethod.cash => spanish ? 'Efectivo' : 'Cash',
      ClientPaymentMethod.transfer => spanish ? 'Transferencia' : 'Transfer',
      ClientPaymentMethod.card => spanish ? 'Tarjeta' : 'Card',
      null => spanish ? 'Sin registrar' : 'Unknown',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFE9EFF5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF5C7187),
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
