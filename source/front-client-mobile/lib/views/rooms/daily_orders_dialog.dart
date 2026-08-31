import 'package:flutter/material.dart';

import '../../models/client_order.dart';
import '../../utils/money.dart';
import 'bill_order_dialog.dart';

class DailyOrdersDialog extends StatelessWidget {
  const DailyOrdersDialog({
    super.key,
    required this.spanish,
    required this.orders,
  });

  final bool spanish;
  final List<ClientOrder> orders;

  @override
  Widget build(BuildContext context) {
    final total = orders.fold<int>(0, (sum, order) => sum + order.total);
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
                                spanish ? 'Órdenes del día' : 'Today’s orders',
                                style: const TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              Text(
                                spanish
                                    ? 'Desde la 1:00 hasta las 23:59'
                                    : 'From 1:00 through 23:59',
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
                  Expanded(
                    child: orders.isEmpty
                        ? Center(
                            child: Text(
                              spanish
                                  ? 'Aún no hay órdenes hoy.'
                                  : 'There are no orders today yet.',
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(18),
                            itemCount: orders.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 9),
                            itemBuilder: (context, index) {
                              final order = orders[index];
                              return Card(
                                margin: EdgeInsets.zero,
                                child: ListTile(
                                  leading: const CircleAvatar(
                                    child: Icon(Icons.table_restaurant),
                                  ),
                                  title: Text(
                                    '${spanish ? 'Mesa' : 'Table'} ${order.tableLabel}',
                                  ),
                                  subtitle: Text(
                                    '${order.items.fold<int>(0, (sum, item) => sum + item.quantity)} ${spanish ? 'productos' : 'items'}',
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
                          spanish ? 'Total del día' : 'Daily total',
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
