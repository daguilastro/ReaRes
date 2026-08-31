import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../auth/login_page.dart';
import 'pair_device/pair_device_page.dart';
import 'employees/employees_page.dart';
import 'halls/halls_page.dart';
import 'menus/menus_page.dart';
import 'ingredients/ingredients_page.dart';
import '../../services/admin_api.dart';
import '../../utils/money.dart';

const _ink = Color(0xFF222326);
const _muted = Color(0xFF7A7D82);
const _accent = Color(0xFF8798AC);
const _surface = Colors.white;

const _emptyOverview = AdminOverviewMetrics(
  salesToday: 0,
  ordersToday: 0,
  averageTicket: 0,
  points: [],
  topProduct: null,
  categories: [],
);

Future<AdminOverviewMetrics> _loadOverview(
  String token, {
  String period = 'day',
  int range = 7,
}) => token.isEmpty
    ? Future.value(_emptyOverview)
    : getAdminOverview(token, period: period, range: range);

enum _AdminSection {
  overview,
  menus,
  ingredients,
  halls,
  employees,
  pairDevice,
}

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({
    super.key,
    required this.strings,
    required this.onLogout,
    this.adminName = 'Admin User',
    this.sessionToken = '',
  });

  final AppStrings strings;
  final VoidCallback onLogout;
  final String adminName;
  final String sessionToken;

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  _AdminSection _section = _AdminSection.overview;

  bool get _es => widget.strings.isSpanish;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 840;
        if (desktop) {
          return Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: 244,
                  child: _NavigationPanel(
                    adminName: widget.adminName,
                    spanish: _es,
                    onLogout: widget.onLogout,
                    selected: _section,
                    onSelected: (value) => setState(() => _section = value),
                  ),
                ),
                const VerticalDivider(width: 1, color: Color(0xFFE3E4E4)),
                Expanded(child: _content()),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: _surface,
            surfaceTintColor: Colors.transparent,
            titleSpacing: 4,
            title: _AdminIdentity(name: widget.adminName, compact: true),
          ),
          drawer: Drawer(
            child: SafeArea(
              child: _NavigationPanel(
                adminName: widget.adminName,
                spanish: _es,
                onLogout: widget.onLogout,
                hideIdentity: true,
                selected: _section,
                closeOnSelect: true,
                onSelected: (value) => setState(() => _section = value),
              ),
            ),
          ),
          body: _content(),
        );
      },
    );
  }

  Widget _content() => switch (_section) {
    _AdminSection.overview => _DashboardContent(
      spanish: _es,
      token: widget.sessionToken,
    ),
    _AdminSection.pairDevice => PairDevicePage(
      spanish: _es,
      token: widget.sessionToken,
    ),
    _AdminSection.employees => EmployeesPage(
      spanish: _es,
      token: widget.sessionToken,
    ),
    _AdminSection.halls => HallsPage(spanish: _es, token: widget.sessionToken),
    _AdminSection.menus => MenusPage(spanish: _es, token: widget.sessionToken),
    _AdminSection.ingredients => IngredientsPage(
      spanish: _es,
      token: widget.sessionToken,
    ),
  };
}

class _NavigationPanel extends StatelessWidget {
  const _NavigationPanel({
    required this.adminName,
    required this.spanish,
    required this.onLogout,
    this.hideIdentity = false,
    this.closeOnSelect = false,
    required this.selected,
    required this.onSelected,
  });

  final String adminName;
  final bool spanish;
  final VoidCallback onLogout;
  final bool hideIdentity;
  final bool closeOnSelect;
  final _AdminSection selected;
  final ValueChanged<_AdminSection> onSelected;

  void _select(BuildContext context, _AdminSection section) {
    onSelected(section);
    if (closeOnSelect) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: _surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 24, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!hideIdentity) ...[
              _AdminIdentity(name: adminName),
              const SizedBox(height: 40),
            ],
            _NavItem(
              icon: Icons.dashboard_outlined,
              label: spanish ? 'Resumen' : 'Overview',
              selected: selected == _AdminSection.overview,
              onTap: () => _select(context, _AdminSection.overview),
            ),
            _NavItem(
              icon: Icons.menu_book_outlined,
              label: spanish ? 'Administrar menús' : 'Manage menus',
              selected: selected == _AdminSection.menus,
              onTap: () => _select(context, _AdminSection.menus),
            ),
            _NavItem(
              icon: Icons.grass_outlined,
              label: spanish ? 'Ingredientes' : 'Ingredients',
              selected: selected == _AdminSection.ingredients,
              onTap: () => _select(context, _AdminSection.ingredients),
            ),
            _NavItem(
              icon: Icons.meeting_room_outlined,
              label: spanish ? 'Salones y mesas' : 'Halls and tables',
              selected: selected == _AdminSection.halls,
              onTap: () => _select(context, _AdminSection.halls),
            ),
            _NavItem(
              icon: Icons.groups_outlined,
              label: spanish ? 'Empleados' : 'Employees',
              selected: selected == _AdminSection.employees,
              onTap: () => _select(context, _AdminSection.employees),
            ),
            _NavItem(
              icon: Icons.devices_other_outlined,
              label: spanish ? 'Vincular dispositivo' : 'Pair device',
              selected: selected == _AdminSection.pairDevice,
              onTap: () => _select(context, _AdminSection.pairDevice),
            ),
            const Spacer(),
            _NavItem(
              key: const ValueKey('dashboard-logout'),
              icon: Icons.logout,
              label: spanish ? 'Cerrar sesión' : 'Logout',
              onTap: onLogout,
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminIdentity extends StatelessWidget {
  const _AdminIdentity({required this.name, this.compact = false});

  final String name;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(
          radius: compact ? 16 : 19,
          backgroundColor: const Color(0xFFE8EDF2),
          child: const Icon(Icons.person_outline, color: _accent, size: 21),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!compact)
                const Text(
                  'Administrator',
                  style: TextStyle(color: _muted, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    super.key,
    required this.icon,
    required this.label,
    this.selected = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected ? const Color(0xFFF0F3F6) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap ?? () {},
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 21, color: selected ? _accent : _ink),
                const SizedBox(width: 13),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      color: _ink,
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatefulWidget {
  const _DashboardContent({required this.spanish, required this.token});

  final bool spanish;
  final String token;

  @override
  State<_DashboardContent> createState() => _DashboardContentState();
}

class _DashboardContentState extends State<_DashboardContent> {
  late Future<AdminOverviewMetrics> _summary;
  StreamSubscription<AdminActivity>? _metricsSubscription;
  int _revision = 0;

  bool get spanish => widget.spanish;
  String get token => widget.token;

  @override
  void initState() {
    super.initState();
    _summary = _loadOverview(token);
    _connectMetrics();
  }

  @override
  void didUpdateWidget(covariant _DashboardContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.token == token) return;
    _metricsSubscription?.cancel();
    _summary = _loadOverview(token);
    _connectMetrics();
  }

  void _connectMetrics() {
    if (token.isEmpty) return;
    _metricsSubscription = watchAdminActivities(token).listen((activity) {
      final modification = activity.modification.toLowerCase();
      if (activity.type == 'Mesa' && modification.startsWith('facturó')) {
        _refreshMetrics();
      }
    }, onError: (_) {});
  }

  void _refreshMetrics() {
    if (!mounted) return;
    setState(() {
      _summary = _loadOverview(token);
      _revision++;
    });
  }

  @override
  void dispose() {
    _metricsSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 760;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    spanish ? 'RESUMEN' : 'OVERVIEW',
                    style: const TextStyle(
                      color: _accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: .8,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          spanish
                              ? 'Rendimiento de hoy'
                              : "Today's Performance",
                          style: TextStyle(
                            color: _ink,
                            fontSize: wide ? 29 : 25,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -.8,
                          ),
                        ),
                      ),
                      if (wide)
                        Text(
                          _dateLabel(),
                          style: const TextStyle(color: _muted, fontSize: 12),
                        ),
                    ],
                  ),
                  const SizedBox(height: 26),
                  FutureBuilder<AdminOverviewMetrics>(
                    future: _summary,
                    builder: (context, snapshot) => _MetricsGrid(
                      spanish: spanish,
                      wide: wide,
                      metrics: snapshot.data,
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (wide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: _RevenueCard(
                            spanish: spanish,
                            token: token,
                            revision: _revision,
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 296,
                          child: Column(
                            children: [
                              _TopItemCard(spanish: spanish, metrics: _summary),
                              const SizedBox(height: 16),
                              _CategoryCard(
                                spanish: spanish,
                                metrics: _summary,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _RevenueCard(
                      spanish: spanish,
                      token: token,
                      revision: _revision,
                    ),
                    const SizedBox(height: 16),
                    _TopItemCard(spanish: spanish, metrics: _summary),
                    const SizedBox(height: 16),
                    _CategoryCard(spanish: spanish, metrics: _summary),
                  ],
                  const SizedBox(height: 22),
                  _RecentActivityCard(spanish: spanish, token: token),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  String _dateLabel() {
    final now = DateTime.now();
    const monthsEn = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    const monthsEs = [
      'ene',
      'feb',
      'mar',
      'abr',
      'may',
      'jun',
      'jul',
      'ago',
      'sep',
      'oct',
      'nov',
      'dic',
    ];
    final months = spanish ? monthsEs : monthsEn;
    return '${months[now.month - 1]} ${now.day}, ${now.year}';
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.spanish,
    required this.wide,
    required this.metrics,
  });
  final bool spanish;
  final bool wide;
  final AdminOverviewMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _MetricData(
        spanish ? 'Ventas de hoy' : 'Sales today',
        formatPesos(metrics?.salesToday ?? 0),
        Icons.payments_outlined,
        spanish ? 'Total registrado hoy' : 'Recorded today',
      ),
      _MetricData(
        spanish ? 'Pedidos totales' : 'Total orders',
        '${metrics?.ordersToday ?? 0}',
        Icons.receipt_long_outlined,
        spanish ? 'Órdenes creadas hoy' : 'Orders created today',
      ),
      _MetricData(
        spanish ? 'Ticket promedio' : 'Average ticket',
        formatPesos(metrics?.averageTicket ?? 0),
        Icons.local_activity_outlined,
        spanish ? 'Promedio real de hoy' : 'Today’s actual average',
      ),
    ];
    if (wide) {
      return Row(
        children: [
          for (var index = 0; index < cards.length; index++) ...[
            Expanded(child: _MetricCard(data: cards[index])),
            if (index != cards.length - 1) const SizedBox(width: 12),
          ],
        ],
      );
    }
    return Column(
      children: [
        for (final card in cards) ...[
          _MetricCard(data: card),
          if (card != cards.last) const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _MetricData {
  const _MetricData(this.label, this.value, this.icon, this.detail);
  final String label;
  final String value;
  final IconData icon;
  final String detail;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});
  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: SizedBox(
        height: 92,
        child: Stack(
          children: [
            Positioned(
              right: 0,
              child: Icon(data.icon, color: const Color(0xFFD8DBDF), size: 29),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 12,
                    letterSpacing: .4,
                  ),
                ),
                const Spacer(),
                Text(
                  data.value,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 27,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  data.detail,
                  style: const TextStyle(
                    color: Color(0xFF626760),
                    fontSize: 10,
                    letterSpacing: .4,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

enum _RevenuePeriod { hour, day, month, year }

class _RevenueCard extends StatefulWidget {
  const _RevenueCard({
    required this.spanish,
    required this.token,
    required this.revision,
  });
  final bool spanish;
  final String token;
  final int revision;

  @override
  State<_RevenueCard> createState() => _RevenueCardState();
}

class _RevenueCardState extends State<_RevenueCard> {
  _RevenuePeriod _period = _RevenuePeriod.day;
  int _days = 7;
  int _months = 6;
  int _years = 5;
  AdminOverviewMetrics? _metrics;
  int? _hoveredIndex;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _RevenueCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.revision != widget.revision ||
        oldWidget.token != widget.token) {
      _load();
    }
  }

  bool get spanish => widget.spanish;

  int get _range => switch (_period) {
    _RevenuePeriod.hour => 0,
    _RevenuePeriod.day => _days,
    _RevenuePeriod.month => _months,
    _RevenuePeriod.year => _years,
  };

  ({String title, List<String> labels, List<double> values})
  get _data => switch (_period) {
    _RevenuePeriod.hour => (
      title: spanish ? 'Ingresos: hoy por hora' : 'Revenue: today by hour',
      labels: _metrics?.points.map((point) => point.label).toList() ?? const [],
      values: _metrics?.points.map((point) => point.value).toList() ?? const [],
    ),
    _RevenuePeriod.day => (
      title: spanish
          ? 'Ingresos: últimos $_days días'
          : 'Revenue: $_days-day trend',
      labels: _metrics?.points.map((point) => point.label).toList() ?? const [],
      values: _metrics?.points.map((point) => point.value).toList() ?? const [],
    ),
    _RevenuePeriod.month => (
      title: spanish
          ? 'Ingresos: últimos $_months meses'
          : 'Revenue: $_months-month trend',
      labels: _metrics?.points.map((point) => point.label).toList() ?? const [],
      values: _metrics?.points.map((point) => point.value).toList() ?? const [],
    ),
    _RevenuePeriod.year => (
      title: spanish
          ? 'Ingresos: últimos $_years años'
          : 'Revenue: $_years-year trend',
      labels: _metrics?.points.map((point) => point.label).toList() ?? const [],
      values: _metrics?.points.map((point) => point.value).toList() ?? const [],
    ),
  };

  Future<void> _load() async {
    try {
      final metrics = await _loadOverview(
        widget.token,
        period: _period.name,
        range: _period == _RevenuePeriod.hour ? 24 : _range,
      );
      if (mounted) setState(() => _metrics = metrics);
    } on Object {
      if (mounted) setState(() => _metrics = null);
    }
  }

  List<int> _visibleIndices(int count) {
    if (count == 0) return const [];
    if (count == 1) return const [0];
    final visible = count.clamp(2, 7);
    return List.generate(
      visible,
      (index) => (index * (count - 1) / (visible - 1)).round(),
    );
  }

  Future<void> _changeRange() async {
    if (_period == _RevenuePeriod.hour) return;
    final (minimum, maximum) = switch (_period) {
      _RevenuePeriod.day => (2, 31),
      _RevenuePeriod.month => (2, 24),
      _RevenuePeriod.year => (2, 10),
      _RevenuePeriod.hour => (0, 0),
    };
    var selected = _range;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(spanish ? 'Rango del gráfico' : 'Chart range'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _rangeLabel(selected),
                  key: const ValueKey('revenue-range-value'),
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Slider(
                  key: const ValueKey('revenue-range-slider'),
                  min: minimum.toDouble(),
                  max: maximum.toDouble(),
                  divisions: maximum - minimum,
                  value: selected.toDouble(),
                  label: '$selected',
                  onChanged: (value) =>
                      setDialogState(() => selected = value.round()),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(spanish ? 'Cancelar' : 'Cancel'),
            ),
            FilledButton(
              key: const ValueKey('apply-revenue-range'),
              onPressed: () => Navigator.pop(context, selected),
              child: Text(spanish ? 'Aplicar' : 'Apply'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      switch (_period) {
        case _RevenuePeriod.day:
          _days = result;
          break;
        case _RevenuePeriod.month:
          _months = result;
          break;
        case _RevenuePeriod.year:
          _years = result;
          break;
        case _RevenuePeriod.hour:
          break;
      }
    });
    _load();
  }

  String _rangeLabel(int value) => switch (_period) {
    _RevenuePeriod.day => spanish ? '$value días' : '$value days',
    _RevenuePeriod.month => spanish ? '$value meses' : '$value months',
    _RevenuePeriod.year => spanish ? '$value años' : '$value years',
    _RevenuePeriod.hour => '',
  };

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return _Panel(
      child: SizedBox(
        height: 390,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    data.title,
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Wrap(
                  spacing: 7,
                  children: [
                    if (_period != _RevenuePeriod.hour)
                      _RevenueControlButton(
                        key: const ValueKey('revenue-range-selector'),
                        label: _rangeLabel(_range),
                        icon: Icons.tune_rounded,
                        onTap: _changeRange,
                      ),
                    _RevenuePeriodSelector(
                      period: _period,
                      spanish: spanish,
                      onChanged: (value) {
                        setState(() {
                          _period = value;
                          _metrics = null;
                          _hoveredIndex = null;
                        });
                        _load();
                      },
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeOutCubic,
                child: TweenAnimationBuilder<double>(
                  key: ValueKey('${_period.name}-$_range'),
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 420),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, child) => LayoutBuilder(
                    builder: (context, constraints) => MouseRegion(
                      onExit: (_) => setState(() => _hoveredIndex = null),
                      onHover: (event) {
                        if (data.values.isEmpty) return;
                        final width = (constraints.maxWidth - 54).clamp(
                          1.0,
                          double.infinity,
                        );
                        final x = (event.localPosition.dx - 52).clamp(
                          0.0,
                          width,
                        );
                        final index = data.values.length == 1
                            ? 0
                            : (x / width * (data.values.length - 1)).round();
                        if (index != _hoveredIndex) {
                          setState(() => _hoveredIndex = index);
                        }
                      },
                      child: Stack(
                        children: [
                          Positioned.fill(
                            child: CustomPaint(
                              painter: _RevenuePainter(
                                values: data.values,
                                progress: progress,
                                hoveredIndex: _hoveredIndex,
                              ),
                            ),
                          ),
                          if (_hoveredIndex case final index?)
                            Positioned(
                              left: 60,
                              top: 2,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _ink,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 6,
                                  ),
                                  child: Text(
                                    '${data.labels[index]} · ${formatPesos(data.values[index])}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                    ),
                                  ),
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
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: _visibleIndices(data.labels.length)
                  .map(
                    (index) => Text(
                      data.labels[index],
                      style: TextStyle(color: _muted, fontSize: 10),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _RevenueControlButton extends StatelessWidget {
  const _RevenueControlButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF0F3F6),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: _accent, size: 15),
              const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  color: _accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenuePeriodSelector extends StatelessWidget {
  const _RevenuePeriodSelector({
    required this.period,
    required this.spanish,
    required this.onChanged,
  });

  final _RevenuePeriod period;
  final bool spanish;
  final ValueChanged<_RevenuePeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = spanish
        ? const ['Hora', 'Día', 'Mes', 'Año']
        : const ['Hour', 'Day', 'Month', 'Year'];
    return PopupMenuButton<_RevenuePeriod>(
      key: const ValueKey('revenue-period-selector'),
      initialValue: period,
      tooltip: spanish ? 'Cambiar período' : 'Change period',
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (var index = 0; index < _RevenuePeriod.values.length; index++)
          PopupMenuItem(
            value: _RevenuePeriod.values[index],
            child: Text(labels[index]),
          ),
      ],
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF0F3F6),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labels[period.index],
                style: const TextStyle(
                  color: _accent,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 5),
              const Icon(Icons.expand_more_rounded, color: _accent, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _RevenuePainter extends CustomPainter {
  const _RevenuePainter({
    required this.values,
    required this.progress,
    required this.hoveredIndex,
  });

  final List<double> values;
  final double progress;
  final int? hoveredIndex;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    const left = 52.0;
    final graphWidth = size.width - left;
    final maximum = values.fold<double>(
      0,
      (current, value) => value > current ? value : current,
    );
    final scaleMaximum = maximum <= 0 ? 1.0 : maximum;
    final grid = Paint()
      ..color = const Color(0xFFE5E7E8)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(left, y), Offset(size.width, y), grid);
    }
    for (final fraction in const [0.0, .5, 1.0]) {
      final label = TextPainter(
        text: TextSpan(
          text: formatPesos(scaleMaximum * fraction),
          style: const TextStyle(color: _muted, fontSize: 9),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: left - 4);
      label.paint(
        canvas,
        Offset(0, size.height * (1 - fraction) - label.height / 2),
      );
    }
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final point = Offset(
        left +
            (values.length == 1
                ? graphWidth / 2
                : graphWidth * i / (values.length - 1)),
        size.height * (1 - (values[i] / scaleMaximum) * progress),
      );
      i == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = _accent
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    if (hoveredIndex != null) {
      final index = hoveredIndex!.clamp(0, values.length - 1);
      final point = Offset(
        left +
            (values.length == 1
                ? graphWidth / 2
                : graphWidth * index / (values.length - 1)),
        size.height * (1 - (values[index] / scaleMaximum) * progress),
      );
      canvas.drawCircle(point, 5, Paint()..color = Colors.white);
      canvas.drawCircle(
        point,
        5,
        Paint()
          ..color = _accent
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RevenuePainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.values != values ||
      oldDelegate.hoveredIndex != hoveredIndex;
}

class _TopItemCard extends StatelessWidget {
  const _TopItemCard({required this.spanish, required this.metrics});
  final bool spanish;
  final Future<AdminOverviewMetrics> metrics;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminOverviewMetrics>(
      future: metrics,
      builder: (context, snapshot) {
        final product = snapshot.data?.topProduct;
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spanish ? 'MÁS VENDIDO' : 'TOP SELLING ITEM',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 10),
              Container(
                height: 112,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  gradient: const LinearGradient(
                    colors: [Color(0xFFD8C8B4), Color(0xFF899389)],
                  ),
                ),
                child: const Center(
                  child: Icon(
                    Icons.ramen_dining,
                    color: Colors.white,
                    size: 54,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                product?.name ??
                    (spanish ? 'Sin ventas hoy' : 'No sales today'),
                style: const TextStyle(
                  color: _ink,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                product == null
                    ? '—'
                    : '${formatPesos(product.value)} / ${spanish ? 'unidad' : 'unit'} · ${product.quantity} ${spanish ? 'unidades' : 'units'}',
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.spanish, required this.metrics});
  final bool spanish;
  final Future<AdminOverviewMetrics> metrics;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminOverviewMetrics>(
      future: metrics,
      builder: (context, snapshot) {
        final categories = snapshot.data?.categories ?? const [];
        final total = categories.fold<double>(
          0,
          (sum, item) => sum + item.value,
        );
        const colors = [
          Color(0xFF52657A),
          Color(0xFF8798AC),
          Color(0xFFD9E8C8),
          Color(0xFFE2E3E1),
        ];
        final rows = [
          for (var index = 0; index < categories.length; index++)
            (
              categories[index].name,
              total == 0 ? 0 : (categories[index].value / total * 100).round(),
              colors[index % colors.length],
            ),
        ];
        return _Panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                spanish ? 'VENTAS POR CATEGORÍA' : 'CATEGORY BREAKDOWN',
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
              const SizedBox(height: 15),
              for (final row in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: row.$3,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          row.$1,
                          style: const TextStyle(color: _ink, fontSize: 12),
                        ),
                      ),
                      Text(
                        '${row.$2}%',
                        style: const TextStyle(color: _muted, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 3),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  children: rows
                      .map(
                        (row) => Expanded(
                          flex: row.$2 == 0 ? 1 : row.$2,
                          child: Container(height: 8, color: row.$3),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RecentActivityCard extends StatefulWidget {
  const _RecentActivityCard({required this.spanish, required this.token});

  final bool spanish;
  final String token;

  @override
  State<_RecentActivityCard> createState() => _RecentActivityCardState();
}

class _RecentActivityCardState extends State<_RecentActivityCard> {
  final _cardKey = GlobalKey();
  bool _isExpanded = false;
  final _activities = ValueNotifier<List<AdminActivity>>([]);
  StreamSubscription<AdminActivity>? _activitySubscription;

  @override
  void initState() {
    super.initState();
    if (widget.token.isNotEmpty) _connect();
  }

  Future<void> _connect() async {
    try {
      final loaded = await getAdminActivities(widget.token);
      if (mounted) _activities.value = loaded;
    } on Object {
      // El stream puede seguir entregando actividad aunque falle la carga inicial.
    }
    if (!mounted) return;
    _activitySubscription = watchAdminActivities(widget.token).listen((
      activity,
    ) {
      if (!mounted) return;
      _activities.value = [
        activity,
        ..._activities.value.where((item) => item.id != activity.id),
      ].take(100).toList();
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _activitySubscription?.cancel();
    _activities.dispose();
    super.dispose();
  }

  Future<void> _expand() async {
    final renderBox = _cardKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final sourceRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final route = PageRouteBuilder<void>(
      opaque: false,
      barrierDismissible: true,
      barrierColor: const Color(0xA6000000),
      barrierLabel: widget.spanish ? 'Actividad reciente' : 'Recent activity',
      transitionDuration: const Duration(milliseconds: 460),
      reverseTransitionDuration: const Duration(milliseconds: 380),
      pageBuilder: (context, animation, secondaryAnimation) =>
          _ExpandedActivitySurface(
            spanish: widget.spanish,
            activities: _activities,
          ),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        return _ActivityExpansionTransition(
          animation: animation,
          sourceRect: sourceRect,
          child: child,
        );
      },
    );
    final navigation = Navigator.of(context).push<void>(route);
    // Navigator.push instala primero la copia animada sobre la tarjeta. Ocultar
    // el origen después evita el frame vacío que aparecía antes de la ruta.
    setState(() => _isExpanded = true);
    final routeAnimation = route.animation;

    void restoreCard(AnimationStatus status) {
      // Este callback ocurre durante el tick del último frame de la ruta. La
      // tarjeta original se reconstruye en ese mismo frame, debajo de la copia
      // animada, evitando un frame vacío entre ambas.
      if (status == AnimationStatus.dismissed && mounted && _isExpanded) {
        setState(() => _isExpanded = false);
      }
    }

    routeAnimation?.addStatusListener(restoreCard);
    await navigation;
    await route.completed;
    routeAnimation?.removeStatusListener(restoreCard);
    if (mounted && _isExpanded) setState(() => _isExpanded = false);
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: _cardKey,
      child: IgnorePointer(
        ignoring: _isExpanded,
        child: Opacity(
          opacity: _isExpanded ? 0 : 1,
          child: _Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.spanish
                            ? 'Actividad reciente'
                            : 'Recent activity',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('expand-recent-activity'),
                      tooltip: widget.spanish ? 'Expandir' : 'Expand',
                      onPressed: _expand,
                      icon: const Icon(Icons.open_in_full_rounded, size: 19),
                      color: _accent,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ValueListenableBuilder<List<AdminActivity>>(
                  valueListenable: _activities,
                  builder: (context, activities, _) => _ActivityTable(
                    spanish: widget.spanish,
                    compact: true,
                    activities: activities,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityExpansionTransition extends StatelessWidget {
  const _ActivityExpansionTransition({
    required this.animation,
    required this.sourceRect,
    required this.child,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = Size(constraints.maxWidth, constraints.maxHeight);
        final horizontalMargin = available.width < 600 ? 14.0 : 28.0;
        final verticalMargin = available.height < 700 ? 14.0 : 28.0;
        final targetWidth = (available.width - horizontalMargin * 2).clamp(
          0.0,
          920.0,
        );
        final targetHeight = (available.height - verticalMargin * 2).clamp(
          0.0,
          680.0,
        );
        final targetRect = Rect.fromLTWH(
          (available.width - targetWidth) / 2,
          (available.height - targetHeight) / 2,
          targetWidth,
          targetHeight,
        );

        return AnimatedBuilder(
          animation: animation,
          child: child,
          builder: (context, child) {
            final curve = animation.status == AnimationStatus.reverse
                ? Curves.easeInOutCubic
                : Curves.easeInOutCubicEmphasized;
            final progress = curve.transform(animation.value);
            final rect = Rect.lerp(sourceRect, targetRect, progress)!;
            return Stack(
              children: [
                Positioned.fromRect(
                  rect: rect,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13 + (5 * progress)),
                    child: child,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ExpandedActivitySurface extends StatelessWidget {
  const _ExpandedActivitySurface({
    required this.spanish,
    required this.activities,
  });

  final bool spanish;
  final ValueListenable<List<AdminActivity>> activities;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surface,
      elevation: 24,
      shadowColor: Colors.black54,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    spanish ? 'Actividad reciente' : 'Recent activity',
                    style: const TextStyle(
                      color: _ink,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('close-recent-activity'),
                  tooltip: spanish ? 'Cerrar' : 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ValueListenableBuilder<List<AdminActivity>>(
                valueListenable: activities,
                builder: (context, values, _) => SingleChildScrollView(
                  child: _ActivityTable(
                    spanish: spanish,
                    compact: false,
                    activities: values,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivityTable extends StatelessWidget {
  const _ActivityTable({
    required this.spanish,
    required this.compact,
    required this.activities,
  });

  final bool spanish;
  final bool compact;
  final List<AdminActivity> activities;

  @override
  Widget build(BuildContext context) {
    final rows = compact ? activities.take(2) : activities;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE4E6E8)),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _ActivityRow(
            author: spanish ? 'Autor' : 'Author',
            type: spanish ? 'Tipo' : 'Type',
            modification: spanish ? 'Modificación' : 'Modification',
            header: true,
          ),
          if (activities.isEmpty)
            _ActivityRow(
              author: '—',
              type: '—',
              modification: spanish
                  ? 'Aún no hay actividad registrada.'
                  : 'No activity has been recorded yet.',
            ),
          for (final row in rows)
            _ActivityRow(
              author: row.author,
              type: row.type,
              modification: row.modification,
            ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({
    required this.author,
    required this.type,
    required this.modification,
    this.header = false,
  });

  final String author;
  final String type;
  final String modification;
  final bool header;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      color: header ? _muted : _ink,
      fontSize: header ? 11 : 12,
      fontWeight: header ? FontWeight.w700 : FontWeight.w400,
      letterSpacing: header ? .35 : 0,
    );
    return Container(
      color: header ? const Color(0xFFF5F6F6) : _surface,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(author, style: style)),
          const SizedBox(width: 12),
          Expanded(flex: 2, child: Text(type, style: style)),
          const SizedBox(width: 12),
          Expanded(flex: 5, child: Text(modification, style: style)),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(13),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }
}
