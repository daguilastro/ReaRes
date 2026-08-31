import 'package:flutter/material.dart';

import '../../../services/admin_api.dart';
import '../halls/room_layout_models.dart';

const _ink = Color(0xFF222326);
const _muted = Color(0xFF7A7D82);
const _accent = Color(0xFF8798AC);
const _roles = ['waiter', 'kitchen', 'cashier', 'manager'];

class EmployeesPage extends StatefulWidget {
  const EmployeesPage({super.key, required this.spanish, required this.token});
  final bool spanish;
  final String token;

  @override
  State<EmployeesPage> createState() => _EmployeesPageState();
}

class _EmployeesPageState extends State<EmployeesPage> {
  List<EmployeeAccount> _employees = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final employees = await getEmployees(widget.token);
      if (mounted) {
        setState(() {
          _employees = employees;
          _loading = false;
          _error = null;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = widget.spanish
              ? 'No se pudieron cargar los empleados.'
              : 'Employees could not be loaded.';
        });
      }
    }
  }

  Future<void> _openEditor([EmployeeAccount? employee]) async {
    final changed = await showGeneralDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierLabel: widget.spanish ? 'Cerrar' : 'Close',
      barrierColor: const Color(0x99000000),
      transitionDuration: const Duration(milliseconds: 260),
      pageBuilder: (context, animation, secondaryAnimation) => _EmployeeDialog(
        spanish: widget.spanish,
        token: widget.token,
        employee: employee,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            ),
            child: child,
          ),
    );
    if (changed == true) {
      setState(() => _loading = true);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(24, 28, 24, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 570;
                final heading = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.spanish
                          ? 'Administrar empleados'
                          : 'Manage Employees',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 29,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.8,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      widget.spanish
                          ? 'Consulta y administra las cuentas del personal.'
                          : 'View and manage staff accounts.',
                      style: const TextStyle(color: _muted, fontSize: 13),
                    ),
                  ],
                );
                final button = FilledButton.icon(
                  key: const ValueKey('add-employee'),
                  onPressed: _openEditor,
                  icon: const Icon(Icons.add, size: 19),
                  label: Text(
                    widget.spanish ? 'Añadir empleado' : 'Add Employee',
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                  ),
                );
                return compact
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [heading, const SizedBox(height: 18), button],
                      )
                    : Row(
                        children: [
                          Expanded(child: heading),
                          button,
                        ],
                      );
              },
            ),
            const SizedBox(height: 30),
            if (_loading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(50),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_error != null)
              Center(
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              )
            else
              _EmployeeTable(
                spanish: widget.spanish,
                employees: _employees,
                onTap: _openEditor,
              ),
          ],
        ),
      ),
    ),
  );
}

class _EmployeeTable extends StatelessWidget {
  const _EmployeeTable({
    required this.spanish,
    required this.employees,
    required this.onTap,
  });
  final bool spanish;
  final List<EmployeeAccount> employees;
  final ValueChanged<EmployeeAccount> onTap;

  @override
  Widget build(BuildContext context) {
    if (employees.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(45),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          spanish ? 'Todavía no hay empleados.' : 'There are no employees yet.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted),
        ),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE4E6E8)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          _EmployeeRow(spanish: spanish, header: true),
          for (final employee in employees)
            _EmployeeRow(
              spanish: spanish,
              employee: employee,
              onTap: () => onTap(employee),
            ),
        ],
      ),
    );
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({
    required this.spanish,
    this.employee,
    this.header = false,
    this.onTap,
  });
  final bool spanish;
  final EmployeeAccount? employee;
  final bool header;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 17),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: header
                ? Text(spanish ? 'Nombre' : 'Name', style: _headerStyle)
                : Row(
                    children: [
                      CircleAvatar(
                        radius: 19,
                        backgroundColor: const Color(0xFFE5EDF8),
                        child: Text(
                          _initials(employee!.fullName),
                          style: const TextStyle(color: _ink),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Flexible(
                        child: Text(
                          employee!.fullName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _ink, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
          ),
          Expanded(
            flex: 4,
            child: Text(
              header ? (spanish ? 'Usuario' : 'Username') : employee!.username,
              overflow: TextOverflow.ellipsis,
              style: header
                  ? _headerStyle
                  : const TextStyle(color: Color(0xFF4D5055), fontSize: 13),
            ),
          ),
          Expanded(
            flex: 3,
            child: Align(
              alignment: Alignment.centerLeft,
              child: header
                  ? Text(spanish ? 'Rol' : 'Role', style: _headerStyle)
                  : _RoleChip(role: employee!.role),
            ),
          ),
          if (!header)
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 19),
        ],
      ),
    );
    return Material(
      color: header ? const Color(0xFFFAFAF9) : Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            row,
            const Divider(height: 1, color: Color(0xFFE4E6E8)),
          ],
        ),
      ),
    );
  }

  static const _headerStyle = TextStyle(
    color: Color(0xFF4D5055),
    fontSize: 11,
    fontWeight: FontWeight.w600,
    letterSpacing: .5,
  );
  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .take(2)
      .map((part) => part.isEmpty ? '' : part[0].toUpperCase())
      .join();
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({required this.role});
  final String role;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
    decoration: BoxDecoration(
      color: const Color(0xFFE4EED8),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      role,
      style: const TextStyle(color: Color(0xFF59634D), fontSize: 11),
    ),
  );
}

class _EmployeeDialog extends StatefulWidget {
  const _EmployeeDialog({
    required this.spanish,
    required this.token,
    this.employee,
  });
  final bool spanish;
  final String token;
  final EmployeeAccount? employee;
  @override
  State<_EmployeeDialog> createState() => _EmployeeDialogState();
}

class _EmployeeDialogState extends State<_EmployeeDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.employee?.fullName,
  );
  late final TextEditingController _username = TextEditingController(
    text: widget.employee?.username,
  );
  final _password = TextEditingController();
  late String _role = widget.employee?.role ?? 'waiter';
  late final Set<int> _selectedRoomIds = {...?widget.employee?.roomIds};
  List<RoomSummary> _rooms = const [];
  bool _loadingRooms = true;
  String? _roomsError;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    if (mounted) {
      setState(() {
        _loadingRooms = true;
        _roomsError = null;
      });
    }
    try {
      final rooms = await getRooms(widget.token);
      if (mounted) {
        setState(() {
          _rooms = rooms;
          _loadingRooms = false;
        });
      }
    } on Object {
      if (mounted) {
        setState(() {
          _loadingRooms = false;
          _roomsError = widget.spanish
              ? 'No se pudieron cargar los salones.'
              : 'Rooms could not be loaded.';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_loadingRooms || _roomsError != null) {
      setState(
        () => _error = widget.spanish
            ? 'Espera o reintenta la carga de salones.'
            : 'Wait for or retry the room list.',
      );
      return;
    }
    if (widget.employee == null &&
        (_name.text.trim().length < 2 ||
            _username.text.trim().length < 3 ||
            _password.text.length < 12)) {
      setState(
        () => _error = widget.spanish
            ? 'Completa los campos; la contraseña requiere 12 caracteres.'
            : 'Complete all fields; the password requires 12 characters.',
      );
      return;
    }
    if (widget.employee != null &&
        _password.text.isNotEmpty &&
        _password.text.length < 12) {
      setState(
        () => _error = widget.spanish
            ? 'La contraseña requiere 12 caracteres.'
            : 'The password requires 12 characters.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (widget.employee == null) {
        await createEmployee(
          token: widget.token,
          fullName: _name.text,
          username: _username.text,
          password: _password.text,
          role: _role,
          roomIds: _selectedRoomIds.toList()..sort(),
        );
      } else {
        await updateEmployee(
          token: widget.token,
          id: widget.employee!.id,
          role: _role,
          password: _password.text,
          roomIds: _selectedRoomIds.toList()..sort(),
        );
      }
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = error.toString().contains('USERNAME_TAKEN')
              ? (widget.spanish
                    ? 'Ese usuario ya existe.'
                    : 'That username already exists.')
              : (widget.spanish
                    ? 'No se pudieron guardar los cambios.'
                    : 'Changes could not be saved.');
        });
      }
    }
  }

  Future<void> _delete() async {
    setState(() => _busy = true);
    try {
      await deleteEmployee(token: widget.token, id: widget.employee!.id);
      if (mounted) {
        Navigator.pop(context, true);
      }
    } on Object {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = widget.spanish
              ? 'No se pudo eliminar el empleado.'
              : 'The employee could not be deleted.';
        });
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Material(
        color: Colors.white,
        elevation: 24,
        borderRadius: BorderRadius.circular(16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.employee == null
                            ? (widget.spanish
                                  ? 'Añadir empleado'
                                  : 'Add Employee')
                            : (widget.spanish
                                  ? 'Editar empleado'
                                  : 'Edit Employee'),
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 23,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('close-employee-dialog'),
                      onPressed: _busy ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (widget.employee == null) ...[
                  TextField(
                    key: const ValueKey('employee-name'),
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: widget.spanish
                          ? 'Nombre completo'
                          : 'Full Name',
                    ),
                  ),
                  const SizedBox(height: 13),
                  TextField(
                    key: const ValueKey('employee-username'),
                    controller: _username,
                    decoration: InputDecoration(
                      labelText: widget.spanish ? 'Usuario' : 'Username',
                    ),
                  ),
                  const SizedBox(height: 13),
                ] else
                  Text(
                    '${widget.employee!.fullName} · ${widget.employee!.username}',
                    style: const TextStyle(color: _muted),
                  ),
                const SizedBox(height: 13),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: InputDecoration(
                    labelText: widget.spanish ? 'Rol' : 'Role',
                  ),
                  items: _roles
                      .map(
                        (role) =>
                            DropdownMenuItem(value: role, child: Text(role)),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _role = value!),
                ),
                const SizedBox(height: 13),
                TextField(
                  key: const ValueKey('employee-password'),
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: widget.employee == null
                        ? (widget.spanish ? 'Contraseña' : 'Password')
                        : (widget.spanish
                              ? 'Nueva contraseña (opcional)'
                              : 'New password (optional)'),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  widget.spanish ? 'Salones asignados' : 'Assigned rooms',
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 9),
                if (_loadingRooms)
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else if (_roomsError != null)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _roomsError!,
                          style: const TextStyle(
                            color: Color(0xFFC94E4E),
                            fontSize: 12,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        key: const ValueKey('retry-employee-rooms'),
                        onPressed: _loadRooms,
                        icon: const Icon(Icons.refresh, size: 17),
                        label: Text(widget.spanish ? 'Reintentar' : 'Retry'),
                      ),
                    ],
                  )
                else if (_rooms.isEmpty)
                  Text(
                    widget.spanish
                        ? 'Todavía no existen salones. El empleado puede quedar sin asignación.'
                        : 'There are no rooms yet. The employee can remain unassigned.',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 7,
                    children: [
                      for (final room in _rooms)
                        FilterChip(
                          key: ValueKey('employee-room-${room.id}'),
                          label: Text(room.name),
                          selected: _selectedRoomIds.contains(room.id),
                          onSelected: _busy
                              ? null
                              : (selected) => setState(() {
                                  if (selected) {
                                    _selectedRoomIds.add(room.id);
                                  } else {
                                    _selectedRoomIds.remove(room.id);
                                  }
                                }),
                        ),
                    ],
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 13),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    if (widget.employee != null)
                      TextButton.icon(
                        key: const ValueKey('delete-employee'),
                        onPressed: _busy ? null : _delete,
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        icon: const Icon(Icons.delete_outline),
                        label: Text(widget.spanish ? 'Eliminar' : 'Delete'),
                      ),
                    const Spacer(),
                    FilledButton(
                      key: const ValueKey('save-employee'),
                      onPressed: _busy ? null : _save,
                      style: FilledButton.styleFrom(backgroundColor: _accent),
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(widget.spanish ? 'Guardar' : 'Save'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
