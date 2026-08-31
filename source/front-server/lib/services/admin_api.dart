import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'server_check.dart';
import '../views/dashboard/halls/room_layout_models.dart';
import '../views/dashboard/menus/catalog_models.dart';

class RegisteredAdmin {
  const RegisteredAdmin({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
  });

  final int id;
  final String fullName;
  final String username;
  final String role;
}

class AdminSession {
  const AdminSession({
    required this.token,
    required this.expiresAt,
    required this.admin,
  });
  final String token;
  final DateTime expiresAt;
  final RegisteredAdmin admin;
}

class AdminActivity {
  const AdminActivity({
    required this.id,
    required this.author,
    required this.type,
    required this.modification,
    required this.roomId,
    required this.createdAt,
  });

  factory AdminActivity.fromJson(Map<String, dynamic> json) => AdminActivity(
    id: json['id'] as int,
    author: json['author'] as String,
    type: json['type'] as String,
    modification: json['modification'] as String,
    roomId: json['roomId'] as int?,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  final int id;
  final String author;
  final String type;
  final String modification;
  final int? roomId;
  final DateTime createdAt;
}

class AdminRevenuePoint {
  const AdminRevenuePoint({required this.label, required this.value});
  factory AdminRevenuePoint.fromJson(Map<String, dynamic> json) =>
      AdminRevenuePoint(
        label: json['label'] as String,
        value: (json['value'] as num).toDouble(),
      );
  final String label;
  final double value;
}

class AdminOverviewMetrics {
  const AdminOverviewMetrics({
    required this.salesToday,
    required this.ordersToday,
    required this.averageTicket,
    required this.points,
    required this.topProduct,
    required this.categories,
  });
  factory AdminOverviewMetrics.fromJson(Map<String, dynamic> json) =>
      AdminOverviewMetrics(
        salesToday: (json['salesToday'] as num).round(),
        ordersToday: (json['ordersToday'] as num).round(),
        averageTicket: (json['averageTicket'] as num).round(),
        points: (json['points'] as List)
            .map(
              (value) =>
                  AdminRevenuePoint.fromJson(value as Map<String, dynamic>),
            )
            .toList(),
        topProduct: json['topProduct'] is Map<String, dynamic>
            ? AdminTopProduct.fromJson(
                json['topProduct'] as Map<String, dynamic>,
              )
            : null,
        categories: (json['categories'] as List? ?? const [])
            .map(
              (value) =>
                  AdminCategoryMetric.fromJson(value as Map<String, dynamic>),
            )
            .toList(),
      );
  final int salesToday;
  final int ordersToday;
  final int averageTicket;
  final List<AdminRevenuePoint> points;
  final AdminTopProduct? topProduct;
  final List<AdminCategoryMetric> categories;
}

class AdminTopProduct {
  const AdminTopProduct({
    required this.name,
    required this.value,
    required this.quantity,
  });
  factory AdminTopProduct.fromJson(Map<String, dynamic> json) =>
      AdminTopProduct(
        name: json['name'] as String,
        value: (json['value'] as num).round(),
        quantity: (json['quantity'] as num).round(),
      );
  final String name;
  final int value;
  final int quantity;
}

class AdminCategoryMetric {
  const AdminCategoryMetric({required this.name, required this.value});
  factory AdminCategoryMetric.fromJson(Map<String, dynamic> json) =>
      AdminCategoryMetric(
        name: json['name'] as String,
        value: (json['value'] as num).toDouble(),
      );
  final String name;
  final double value;
}

Future<AdminOverviewMetrics> getAdminOverview(
  String token, {
  String period = 'day',
  int range = 7,
}) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve(
    '/api/admin/overview?period=$period&range=$range',
  );
  final response = await http
      .get(endpoint, headers: {'authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 8));
  final body = jsonDecode(response.body);
  if (response.statusCode != 200 || body is! Map<String, dynamic>) {
    throw AdminRegistrationException(
      'OVERVIEW_LOAD_FAILED',
      statusCode: response.statusCode,
    );
  }
  return AdminOverviewMetrics.fromJson(body);
}

Future<List<AdminActivity>> getAdminActivities(String token) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve(
    '/api/admin/activities',
  );
  final response = await http
      .get(endpoint, headers: {'authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 8));
  final body = jsonDecode(response.body);
  if (response.statusCode != 200 ||
      body is! Map<String, dynamic> ||
      body['activities'] is! List) {
    throw AdminRegistrationException(
      'ACTIVITIES_LOAD_FAILED',
      statusCode: response.statusCode,
    );
  }
  return (body['activities'] as List)
      .map((value) => AdminActivity.fromJson(value as Map<String, dynamic>))
      .toList();
}

Stream<AdminActivity> watchAdminActivities(String token) async* {
  final client = http.Client();
  try {
    final endpoint = (await getLocalAdminBaseUri()).resolve(
      '/api/admin/events',
    );
    final request = http.Request('GET', endpoint)
      ..headers['authorization'] = 'Bearer $token'
      ..headers['accept'] = 'text/event-stream';
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw AdminRegistrationException(
        'ACTIVITY_STREAM_FAILED',
        statusCode: response.statusCode,
      );
    }
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (!line.startsWith('data:')) continue;
      final value = jsonDecode(line.substring(5).trim());
      if (value is Map<String, dynamic> && value['id'] is int) {
        yield AdminActivity.fromJson(value);
      }
    }
  } finally {
    client.close();
  }
}

class DevicePairingRequest {
  const DevicePairingRequest({
    required this.pairingId,
    required this.pairingSecret,
    required this.expiresAt,
    required this.host,
    required this.port,
    required this.scheme,
    required this.certificateFingerprint,
  });

  final String pairingId;
  final String pairingSecret;
  final DateTime expiresAt;
  final String host;
  final int port;
  final String scheme;
  final String certificateFingerprint;

  String get qrData => jsonEncode({
    'version': 1,
    'host': host,
    'port': port,
    'scheme': scheme,
    'pairingId': pairingId,
    'pairingSecret': pairingSecret,
    'expiresAt': expiresAt.toUtc().toIso8601String(),
    'certificateFingerprint': certificateFingerprint,
  });
}

class EmployeeAccount {
  const EmployeeAccount({
    required this.id,
    required this.fullName,
    required this.username,
    required this.role,
    required this.roomIds,
  });
  final int id;
  final String fullName;
  final String username;
  final String role;
  final List<int> roomIds;

  factory EmployeeAccount.fromJson(Map<String, dynamic> json) =>
      EmployeeAccount(
        id: json['id'] as int,
        fullName: json['fullName'] as String,
        username: json['username'] as String,
        role: json['role'] as String,
        roomIds: (json['roomIds'] as List? ?? const []).whereType<int>().toList(
          growable: false,
        ),
      );
}

Future<CatalogSnapshot> getCatalog(String token) async {
  final body = await _catalogRequest(
    token: token,
    method: 'GET',
    path: '/api/admin/catalog',
  );
  return CatalogSnapshot.fromJson(body);
}

Future<CatalogIngredient> createIngredient({
  required String token,
  required String name,
  required int categoryId,
  String? description,
}) async {
  final body = await _catalogRequest(
    token: token,
    method: 'POST',
    path: '/api/admin/ingredients',
    payload: {
      'name': name,
      'description': description,
      'categoryId': categoryId,
    },
    expectedStatus: 201,
  );
  return CatalogIngredient.fromJson(body['ingredient'] as Map<String, dynamic>);
}

Future<IngredientCategory> createIngredientCategory({
  required String token,
  required String name,
}) async {
  final body = await _catalogRequest(
    token: token,
    method: 'POST',
    path: '/api/admin/ingredient-categories',
    payload: {'name': name},
    expectedStatus: 201,
  );
  return IngredientCategory.fromJson(body['category'] as Map<String, dynamic>);
}

Future<RestaurantMenu> createMenu({
  required String token,
  required String name,
  required List<MenuHallAssignment> hallAssignments,
}) async {
  final body = await _catalogRequest(
    token: token,
    method: 'POST',
    path: '/api/admin/menus',
    payload: {
      'name': name,
      'hallAssignments': [
        for (final assignment in hallAssignments)
          {'hallId': assignment.hallId, 'isPrimary': assignment.isPrimary},
      ],
    },
    expectedStatus: 201,
  );
  return RestaurantMenu.fromJson(body['menu'] as Map<String, dynamic>);
}

Future<MenuCategory> createMenuCategory({
  required String token,
  required int menuId,
  required String name,
  int? parentCategoryId,
  bool isSpecial = false,
}) async {
  final body = await _catalogRequest(
    token: token,
    method: 'POST',
    path: '/api/admin/menus/$menuId/categories',
    payload: {
      'name': name,
      'parentCategoryId': parentCategoryId,
      'isSpecial': isSpecial,
    },
    expectedStatus: 201,
  );
  return MenuCategory.fromJson(body['category'] as Map<String, dynamic>);
}

Future<CatalogProduct> createMenuProduct({
  required String token,
  required int menuId,
  required String name,
  required String description,
  required int value,
  required int categoryId,
  required List<int> ingredientIds,
  required List<int> hallIds,
}) async {
  final body = await _catalogRequest(
    token: token,
    method: 'POST',
    path: '/api/admin/menus/$menuId/products',
    payload: {
      'name': name,
      'description': description,
      'value': value,
      'categoryId': categoryId,
      'ingredientIds': ingredientIds,
      'hallIds': hallIds,
    },
    expectedStatus: 201,
  );
  return CatalogProduct.fromJson(body['product'] as Map<String, dynamic>);
}

Future<CatalogProduct> updateMenuProduct({
  required String token,
  required int productId,
  required String name,
  required String description,
  required int value,
  required List<int> ingredientIds,
  required List<int> hallIds,
}) async {
  final body = await _catalogRequest(
    token: token,
    method: 'PATCH',
    path: '/api/admin/products/$productId',
    payload: {
      'name': name,
      'description': description,
      'value': value,
      'ingredientIds': ingredientIds,
      'hallIds': hallIds,
    },
  );
  return CatalogProduct.fromJson(body['product'] as Map<String, dynamic>);
}

Future<void> deactivateMenuProduct({
  required String token,
  required int productId,
}) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve(
    '/api/admin/products/$productId',
  );
  final response = await http
      .delete(endpoint, headers: {'authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 12));
  if (response.statusCode != 204) {
    throw AdminRegistrationException(
      'PRODUCT_DEACTIVATION_FAILED',
      statusCode: response.statusCode,
    );
  }
}

Future<Map<String, dynamic>> _catalogRequest({
  required String token,
  required String method,
  required String path,
  Map<String, Object?>? payload,
  int expectedStatus = 200,
}) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve(path);
  final request = http.Request(method, endpoint)
    ..headers['authorization'] = 'Bearer $token';
  if (payload != null) {
    request.headers['content-type'] = 'application/json';
    request.body = jsonEncode(payload);
  }
  final streamed = await request.send().timeout(const Duration(seconds: 12));
  final response = await http.Response.fromStream(streamed);
  Object? decoded;
  try {
    decoded = jsonDecode(response.body);
  } on FormatException {
    decoded = null;
  }
  if (response.statusCode == expectedStatus &&
      decoded is Map<String, dynamic>) {
    return decoded;
  }
  final code = decoded is Map<String, dynamic> && decoded['error'] is String
      ? decoded['error'] as String
      : 'CATALOG_REQUEST_FAILED';
  throw AdminRegistrationException(code, statusCode: response.statusCode);
}

Future<RoomLayoutModel> getRoomLayout({
  required String token,
  required int roomId,
}) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve(
    '/api/admin/rooms/$roomId/layout',
  );
  final response = await http
      .get(endpoint, headers: {'authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 8));
  final body = jsonDecode(response.body);
  if (response.statusCode != 200 || body is! Map<String, dynamic>) {
    throw AdminRegistrationException(
      'LAYOUT_LOAD_FAILED',
      statusCode: response.statusCode,
    );
  }
  return RoomLayoutModel.fromJson(body);
}

Future<List<RoomSummary>> getRooms(String token) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve('/api/admin/rooms');
  final response = await http
      .get(endpoint, headers: {'authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 8));
  final body = jsonDecode(response.body);
  if (response.statusCode != 200 ||
      body is! Map<String, dynamic> ||
      body['rooms'] is! List) {
    throw AdminRegistrationException(
      'ROOMS_LOAD_FAILED',
      statusCode: response.statusCode,
    );
  }
  return (body['rooms'] as List)
      .map((room) => RoomSummary.fromJson(room as Map<String, dynamic>))
      .toList();
}

Future<RoomSummary> createRoom({
  required String token,
  required String name,
}) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve('/api/admin/rooms');
  final response = await http
      .post(
        endpoint,
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode({'name': name}),
      )
      .timeout(const Duration(seconds: 8));
  final body = jsonDecode(response.body);
  if (response.statusCode != 201 ||
      body is! Map<String, dynamic> ||
      body['room'] is! Map<String, dynamic>) {
    final code = body is Map<String, dynamic> && body['error'] is String
        ? body['error'] as String
        : 'ROOM_CREATE_FAILED';
    throw AdminRegistrationException(code, statusCode: response.statusCode);
  }
  return RoomSummary.fromJson(body['room'] as Map<String, dynamic>);
}

Future<RoomLayoutModel> saveRoomLayout({
  required String token,
  required int roomId,
  required RoomLayoutModel layout,
}) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve(
    '/api/admin/rooms/$roomId/layout',
  );
  final response = await http
      .put(
        endpoint,
        headers: {
          'authorization': 'Bearer $token',
          'content-type': 'application/json',
        },
        body: jsonEncode(layout.toJson()),
      )
      .timeout(const Duration(seconds: 12));
  final body = jsonDecode(response.body);
  if (response.statusCode != 200 || body is! Map<String, dynamic>) {
    final code = body is Map<String, dynamic> && body['error'] is String
        ? body['error'] as String
        : 'LAYOUT_SAVE_FAILED';
    throw AdminRegistrationException(code, statusCode: response.statusCode);
  }
  return RoomLayoutModel.fromJson(body);
}

Future<List<EmployeeAccount>> getEmployees(String token) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve(
    '/api/admin/employees',
  );
  final response = await http
      .get(endpoint, headers: {'authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 8));
  final body = jsonDecode(response.body);
  if (response.statusCode != 200 ||
      body is! Map<String, dynamic> ||
      body['employees'] is! List) {
    throw AdminRegistrationException(
      'EMPLOYEES_LOAD_FAILED',
      statusCode: response.statusCode,
    );
  }
  return (body['employees'] as List)
      .map((value) => EmployeeAccount.fromJson(value as Map<String, dynamic>))
      .toList();
}

Future<EmployeeAccount> createEmployee({
  required String token,
  required String fullName,
  required String username,
  required String password,
  required String role,
  required List<int> roomIds,
}) => _writeEmployee(
  token: token,
  method: 'POST',
  path: '/api/admin/employees',
  body: {
    'fullName': fullName,
    'username': username,
    'password': password,
    'role': role,
    'roomIds': roomIds,
  },
);

Future<EmployeeAccount> updateEmployee({
  required String token,
  required int id,
  required String role,
  required List<int> roomIds,
  String? password,
}) => _writeEmployee(
  token: token,
  method: 'PATCH',
  path: '/api/admin/employees/$id',
  body: {
    'role': role,
    'roomIds': roomIds,
    if (password != null && password.isNotEmpty) 'password': password,
  },
);

Future<EmployeeAccount> _writeEmployee({
  required String token,
  required String method,
  required String path,
  required Map<String, Object> body,
}) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve(path);
  final request = http.Request(method, endpoint)
    ..headers.addAll({
      'authorization': 'Bearer $token',
      'content-type': 'application/json',
    })
    ..body = jsonEncode(body);
  final streamed = await request.send().timeout(const Duration(seconds: 12));
  final response = await http.Response.fromStream(streamed);
  final decoded = jsonDecode(response.body);
  if ((response.statusCode == 200 || response.statusCode == 201) &&
      decoded is Map<String, dynamic> &&
      decoded['employee'] is Map<String, dynamic>) {
    return EmployeeAccount.fromJson(
      decoded['employee'] as Map<String, dynamic>,
    );
  }
  final code = decoded is Map<String, dynamic> && decoded['error'] is String
      ? decoded['error'] as String
      : 'EMPLOYEE_WRITE_FAILED';
  throw AdminRegistrationException(code, statusCode: response.statusCode);
}

Future<void> deleteEmployee({required String token, required int id}) async {
  final endpoint = (await getLocalAdminBaseUri()).resolve(
    '/api/admin/employees/$id',
  );
  final response = await http
      .delete(endpoint, headers: {'authorization': 'Bearer $token'})
      .timeout(const Duration(seconds: 8));
  if (response.statusCode != 204) {
    throw AdminRegistrationException(
      'EMPLOYEE_DELETE_FAILED',
      statusCode: response.statusCode,
    );
  }
}

Future<DevicePairingRequest> createDevicePairingRequest(String token) async {
  try {
    final endpoint = (await getLocalAdminBaseUri()).resolve(
      '/api/admin/pairing-requests',
    );
    final response = await http
        .post(endpoint, headers: {'authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 8));
    final body = jsonDecode(response.body);
    if (response.statusCode == 201 &&
        body is Map<String, dynamic> &&
        body['pairingId'] is String &&
        body['pairingSecret'] is String &&
        body['expiresAt'] is String &&
        body['host'] is String &&
        body['port'] is int &&
        body['scheme'] is String &&
        body['certificateFingerprint'] is String) {
      return DevicePairingRequest(
        pairingId: body['pairingId'] as String,
        pairingSecret: body['pairingSecret'] as String,
        expiresAt: DateTime.parse(body['expiresAt'] as String),
        host: body['host'] as String,
        port: body['port'] as int,
        scheme: body['scheme'] as String,
        certificateFingerprint: body['certificateFingerprint'] as String,
      );
    }
    final code = body is Map<String, dynamic> && body['error'] is String
        ? body['error'] as String
        : 'INVALID_RESPONSE';
    throw AdminRegistrationException(code, statusCode: response.statusCode);
  } on AdminRegistrationException {
    rethrow;
  } on Object catch (error) {
    throw AdminRegistrationException(
      'SERVER_UNAVAILABLE',
      details: error.toString(),
    );
  }
}

RegisteredAdmin _parseAdmin(Object? value) {
  if (value is! Map<String, dynamic> ||
      value['id'] is! int ||
      value['fullName'] is! String ||
      value['username'] is! String ||
      value['role'] is! String) {
    throw const AdminRegistrationException('INVALID_RESPONSE');
  }
  return RegisteredAdmin(
    id: value['id'] as int,
    fullName: value['fullName'] as String,
    username: value['username'] as String,
    role: value['role'] as String,
  );
}

Future<AdminSession> loginAdmin({
  required String username,
  required String password,
}) async {
  try {
    final endpoint = (await getLocalAdminBaseUri()).resolve('/api/admin/login');
    final response = await http
        .post(
          endpoint,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 8));
    debugPrint('Admin login: HTTP ${response.statusCode}');
    final body = jsonDecode(response.body);
    if (response.statusCode == 200 &&
        body is Map<String, dynamic> &&
        body['token'] is String &&
        body['expiresAt'] is String) {
      return AdminSession(
        token: body['token'] as String,
        expiresAt: DateTime.parse(body['expiresAt'] as String),
        admin: _parseAdmin(body['admin']),
      );
    }
    final code = body is Map<String, dynamic> && body['error'] is String
        ? body['error'] as String
        : 'INVALID_RESPONSE';
    throw AdminRegistrationException(code, statusCode: response.statusCode);
  } on AdminRegistrationException {
    rethrow;
  } on Object catch (error) {
    throw AdminRegistrationException(
      'SERVER_UNAVAILABLE',
      details: error.toString(),
    );
  }
}

Future<AdminSession?> verifyAdminSession(String token) async {
  try {
    final endpoint = (await getLocalAdminBaseUri()).resolve(
      '/api/admin/session',
    );
    final response = await http
        .get(endpoint, headers: {'authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 8));
    if (response.statusCode == 401) return null;
    final body = jsonDecode(response.body);
    if (response.statusCode != 200 ||
        body is! Map<String, dynamic> ||
        body['expiresAt'] is! String) {
      return null;
    }
    return AdminSession(
      token: token,
      expiresAt: DateTime.parse(body['expiresAt'] as String),
      admin: _parseAdmin(body['admin']),
    );
  } on Object {
    return null;
  }
}

Future<void> logoutAdmin(String token) async {
  try {
    final endpoint = (await getLocalAdminBaseUri()).resolve(
      '/api/admin/logout',
    );
    await http
        .post(endpoint, headers: {'authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 5));
  } on Object {
    /* La sesión local se elimina incluso si el servidor se cerró. */
  }
}

class AdminRegistrationException implements Exception {
  const AdminRegistrationException(this.code, {this.statusCode, this.details});

  final String code;
  final int? statusCode;
  final String? details;

  @override
  String toString() =>
      'AdminRegistrationException(code: $code, '
      'statusCode: $statusCode, details: $details)';
}

Future<RegisteredAdmin> registerAdmin({
  required String fullName,
  required String username,
  required String password,
}) async {
  try {
    final baseUri = await getLocalAdminBaseUri();
    final endpoint = baseUri.resolve('/api/admin/register');
    debugPrint('Admin register: POST $endpoint');
    final response = await http
        .post(
          endpoint,
          headers: const {'content-type': 'application/json'},
          body: jsonEncode({
            'fullName': fullName,
            'username': username,
            'password': password,
          }),
        )
        .timeout(const Duration(seconds: 8));

    debugPrint('Admin register: HTTP ${response.statusCode} ${response.body}');
    Object? body;
    try {
      body = jsonDecode(response.body);
    } on FormatException {
      throw AdminRegistrationException(
        'HTTP_${response.statusCode}',
        statusCode: response.statusCode,
        details: response.body,
      );
    }
    if (response.statusCode == 201 && body is Map<String, dynamic>) {
      final admin = body['admin'];
      if (admin is Map<String, dynamic> &&
          admin['id'] is int &&
          admin['fullName'] is String &&
          admin['username'] is String &&
          admin['role'] is String) {
        return RegisteredAdmin(
          id: admin['id'] as int,
          fullName: admin['fullName'] as String,
          username: admin['username'] as String,
          role: admin['role'] as String,
        );
      }
    }

    if (body is Map<String, dynamic> && body['error'] is String) {
      throw AdminRegistrationException(
        body['error'] as String,
        statusCode: response.statusCode,
        details: body['message']?.toString(),
      );
    }
    throw AdminRegistrationException(
      'INVALID_RESPONSE',
      statusCode: response.statusCode,
      details: response.body,
    );
  } on AdminRegistrationException catch (error) {
    debugPrint('Admin register failed: $error');
    rethrow;
  } on Object catch (error, stackTrace) {
    debugPrint('Admin register failed: $error');
    debugPrintStack(stackTrace: stackTrace);
    throw AdminRegistrationException(
      'SERVER_UNAVAILABLE',
      details: error.toString(),
    );
  }
}
