import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:restaurante_front/views/auth/login_page.dart';
import 'package:restaurante_front/main.dart';
import 'package:restaurante_front/views/pairing/pairing_page.dart';
import 'package:restaurante_front/views/splash/splash_screen.dart';
import 'package:restaurante_front/models/client_user.dart';
import 'package:restaurante_front/models/client_room.dart';
import 'package:restaurante_front/models/client_order.dart';
import 'package:restaurante_front/services/client_realtime.dart';
import 'package:restaurante_front/views/rooms/rooms_page.dart';
import 'package:restaurante_front/views/rooms/live_room_page.dart';
import 'package:restaurante_front/views/rooms/order_editor_dialog.dart';
import 'package:restaurante_front/views/rooms/delivery_order_dialog.dart';
import 'package:restaurante_front/utils/money.dart';

Future<void> completeChecksImmediately() async {}
Future<bool> reconnectFails() async => false;
Future<bool> reconnectNeverFinishes() => Completer<bool>().future;

void main() {
  test('formats cent values as whole pesos separated with spaces', () {
    expect(formatPesos(1800), r'$18');
    expect(formatPesos(123400), r'$1 234');
  });
  testWidgets('splash waits until initial checks finish', (tester) async {
    final checks = Completer<void>();

    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          strings: AppStrings.fromLocale(const Locale('en')),
          initialChecks: () => checks.future,
          reconnectCheck: reconnectFails,
        ),
      ),
    );

    expect(find.byKey(const ValueKey('splash-logo')), findsOneWidget);
    expect(find.byType(LoginPage), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(LoginPage), findsNothing);

    checks.complete();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byType(PairingPage), findsOneWidget);
  });

  testWidgets('login form animates and toggles password visibility', (
    tester,
  ) async {
    await tester.pumpWidget(
      const RestaurantApp(
        initialChecks: completeChecksImmediately,
        skipPairing: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.text('Welcome!'), findsOneWidget);
    expect(find.text('Username'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'restaurant.user');
    await tester.pumpAndSettle();
    expect(find.text('restaurant.user'), findsOneWidget);

    final passwordField = find.byType(TextField).last;
    expect(tester.widget<TextField>(passwordField).obscureText, isTrue);

    await tester.tap(find.bySemanticsLabel('Show password'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(passwordField).obscureText, isFalse);
  });

  testWidgets('successful login keeps its fields while parent transitions', (
    tester,
  ) async {
    ClientSession? authenticatedSession;
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(
          strings: AppStrings.fromLocale(const Locale('en')),
          authenticate: (username, password) async => ClientSession(
            token: 'employee-token',
            expiresAt: DateTime.utc(2026, 8, 31),
            user: const ClientUser(
              id: 7,
              fullName: 'Daniel Tellez',
              username: 'daniel',
              role: 'cashier',
            ),
          ),
          onAuthenticated: (session) => authenticatedSession = session,
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).first, 'daniel');
    await tester.enterText(find.byType(TextField).last, 'a-secure-password');
    await tester.tap(find.text('Sign In'));
    await tester.pump();

    expect(authenticatedSession?.user.role, 'cashier');
    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields.first.controller?.text, 'daniel');
    expect(fields.last.controller?.text, 'a-secure-password');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('a successful mDNS reconnect skips pairing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          strings: AppStrings.fromLocale(const Locale('en')),
          initialChecks: completeChecksImmediately,
          reconnectCheck: () async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LoginPage), findsOneWidget);
    expect(find.byType(PairingPage), findsNothing);
  });

  testWidgets('a stalled mDNS reconnect falls back to desktop pairing', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SplashScreen(
          strings: AppStrings.fromLocale(const Locale('en')),
          initialChecks: completeChecksImmediately,
          reconnectCheck: reconnectNeverFinishes,
          reconnectTimeout: const Duration(milliseconds: 20),
        ),
      ),
    );

    await tester.pump(const Duration(milliseconds: 25));
    await tester.pumpAndSettle();
    expect(find.byType(PairingPage), findsOneWidget);
    expect(find.byKey(const ValueKey('upload-pairing-qr')), findsOneWidget);
  });

  testWidgets('uses Spanish for a Spanish device locale', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('es');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(
      const RestaurantApp(
        initialChecks: completeChecksImmediately,
        skipPairing: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.text('¡Bienvenido!'), findsOneWidget);
    expect(find.text('Usuario'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);
    expect(find.text('Ingresar'), findsOneWidget);
    expect(find.bySemanticsLabel('Mostrar contraseña'), findsOneWidget);
  });

  testWidgets('falls back to English for unsupported locales', (tester) async {
    tester.binding.platformDispatcher.localeTestValue = const Locale('fr');
    addTearDown(tester.binding.platformDispatcher.clearLocaleTestValue);

    await tester.pumpWidget(
      const RestaurantApp(
        initialChecks: completeChecksImmediately,
        skipPairing: true,
      ),
    );
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();

    expect(find.text('Welcome!'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('employee sees only assigned rooms and can open live view', (
    tester,
  ) async {
    final session = ClientSession(
      token: 'employee-token',
      expiresAt: DateTime.utc(2026, 8, 31),
      user: const ClientUser(
        id: 7,
        fullName: 'Carlos Ruiz',
        username: 'carlos',
        role: 'waiter',
      ),
    );
    final realtime = ClientRealtimeService(session);
    await tester.pumpWidget(
      MaterialApp(
        home: RoomsPage(
          session: session,
          spanish: true,
          realtime: realtime,
          loadRooms: (_) async => const [
            ClientRoomSummary(id: 3, name: 'Terraza', tableCount: 8),
          ],
          liveRoomBuilder: (_, room, realtimeService) =>
              Scaffold(body: Text('Live: ${room.name}')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Carlos Ruiz'), findsOneWidget);
    expect(find.text('Terraza'), findsOneWidget);
    expect(find.text('8 mesas · Abrir vista en vivo'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('assigned-room-3')));
    await tester.pumpAndSettle();
    expect(find.text('Live: Terraza'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    await realtime.dispose();
  });

  testWidgets('live room exposes view controls and floating work modes', (
    tester,
  ) async {
    var menuLoads = 0;
    final session = ClientSession(
      token: 'employee-token',
      expiresAt: DateTime.utc(2026, 8, 31),
      user: const ClientUser(
        id: 7,
        fullName: 'Carlos Ruiz',
        username: 'carlos',
        role: 'waiter',
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: LiveRoomPage(
          session: session,
          room: const ClientRoomSummary(id: 3, name: 'Terraza', tableCount: 1),
          spanish: true,
          loadOrders: ({required session, required roomId}) async => const [
            ClientOrder(
              id: 8,
              tableId: 13,
              tableGroupId: null,
              status: 'waiting',
              description: null,
              items: [],
            ),
          ],
          loadMenus: ({required session, required roomId}) async {
            menuLoads++;
            return const [];
          },
          loadLayout: ({required session, required roomId}) async =>
              const LiveRoomLayout(
                roomId: 3,
                roomName: 'Terraza',
                groups: [],
                walls: [],
                tables: [
                  LiveRoomTable(
                    id: 13,
                    identifier: '13',
                    x: -1300,
                    y: -700,
                    width: 100,
                    height: 70,
                    rotation: 0,
                    status: 'waiting',
                  ),
                ],
              ),
          saveLayout:
              ({required session, required roomId, required layout}) async =>
                  layout,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('live-mode-edit')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-mode-bill')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-mode-select')), findsOneWidget);
    expect(find.byKey(const ValueKey('live-table-13')), findsOneWidget);
    final toolbarCenter = tester.getCenter(
      find.byKey(const ValueKey('live-bottom-tools')),
    );
    expect(toolbarCenter.dx, closeTo(400, 1));

    await tester.tap(find.byKey(const ValueKey('live-mode-edit')));
    await tester.pump();
    expect(menuLoads, 0);
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('live-mode-edit')))
          .isSelected,
      isTrue,
    );
    expect(
      tester
          .widget<IconButton>(find.byKey(const ValueKey('live-mode-select')))
          .isSelected,
      isFalse,
    );
    await tester.tap(find.byKey(const ValueKey('live-table-13')));
    await tester.pumpAndSettle();
    expect(menuLoads, 1);
    expect(find.byType(OrderEditorDialog), findsOneWidget);
    expect(find.text('Mesa esperando'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('close-order-editor')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('live-mode-select')));
    await tester.tap(find.byKey(const ValueKey('live-table-13')));
    await tester.pumpAndSettle();
    expect(find.text('Entrega · Mesa 13'), findsOneWidget);
    expect(find.text('Este pedido no tiene productos.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('close-order-delivery')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('rotate-live-room')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('fit-live-room')));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('delivery view preserves item details and linked additions', (
    tester,
  ) async {
    var deliveredNormal = 0;
    var deliveredSpecial = 0;

    ClientOrder order() => ClientOrder(
      id: 8,
      tableId: 13,
      tableGroupId: null,
      status: deliveredNormal == 1 && deliveredSpecial == 1
          ? 'eating'
          : 'waiting',
      description: 'Pedido de la ventana',
      items: [
        ClientOrderItem(
          id: 101,
          productId: 20,
          name: 'Hamburguesa',
          productDescription: 'Carne y pan artesanal',
          quantity: 1,
          deliveredQuantity: deliveredNormal,
          deliveredUnitIndexes: deliveredNormal == 1 ? const [0] : const [],
          status: deliveredNormal == 1 ? 'delivered' : 'ordered',
          specifications: 'Término medio',
          parentOrderItemId: null,
          removedIngredientIds: const [7],
          ingredients: const [ClientProductIngredient(id: 7, name: 'Cebolla')],
        ),
        ClientOrderItem(
          id: 102,
          productId: 21,
          name: 'Tocineta',
          productDescription: 'Porción crujiente',
          quantity: 1,
          deliveredQuantity: deliveredSpecial,
          deliveredUnitIndexes: deliveredSpecial == 1 ? const [0] : const [],
          status: deliveredSpecial == 1 ? 'delivered' : 'ordered',
          specifications: 'Muy tostada',
          parentOrderItemId: 101,
          removedIngredientIds: const [],
          ingredients: const [],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: DeliveryOrderDialog(
          spanish: true,
          tableLabel: '13',
          initialOrder: order(),
          onDeliver: (itemId, unitIndex) async {
            expect(unitIndex, 0);
            if (itemId == 101) deliveredNormal++;
            if (itemId == 102) deliveredSpecial++;
            return order();
          },
          onUndoDelivery: (itemId, unitIndex) async => order(),
          onEditOrder: () {},
        ),
      ),
    );

    expect(find.text('Hamburguesa'), findsOneWidget);
    expect(find.text('+ Tocineta'), findsOneWidget);
    expect(find.text('Adiciones asociadas'), findsOneWidget);
    expect(find.textContaining('Carne y pan artesanal'), findsOneWidget);
    expect(find.textContaining('Término medio'), findsOneWidget);
    expect(find.text('Sin Cebolla'), findsOneWidget);
    expect(find.textContaining('Porción crujiente'), findsOneWidget);
    expect(find.textContaining('Muy tostada'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('deliver-order-item-101-unit-0')),
    );
    await tester.pumpAndSettle();
    expect(deliveredNormal, 1);
    expect(find.textContaining('ahora está comiendo'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('deliver-order-item-102-unit-0')),
    );
    await tester.pumpAndSettle();
    expect(deliveredSpecial, 1);
    expect(find.textContaining('ahora está comiendo'), findsOneWidget);
  });

  testWidgets('order editor navigates categories and submits quantities', (
    tester,
  ) async {
    List<OrderItemWrite>? submitted;
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: OrderEditorDialog(
          spanish: true,
          tableLabel: '13',
          existingOrder: null,
          menus: const [
            ClientRoomMenu(
              id: 1,
              name: 'Principal',
              isPrimary: true,
              categories: [
                ClientMenuCategory(
                  id: 10,
                  name: 'Platos',
                  parentCategoryId: null,
                  isSpecial: false,
                  products: [
                    ClientMenuProduct(
                      id: 20,
                      name: 'Hamburguesa',
                      description: 'Carne y pan',
                      value: 1800,
                      ingredients: [],
                    ),
                  ],
                ),
                ClientMenuCategory(
                  id: 11,
                  name: 'Adiciones',
                  parentCategoryId: null,
                  isSpecial: true,
                  products: [
                    ClientMenuProduct(
                      id: 21,
                      name: 'Tocineta',
                      description: 'Porción adicional',
                      value: 300,
                      ingredients: [],
                    ),
                  ],
                ),
              ],
            ),
          ],
          onSubmit: (description, items) async => submitted = items,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('order-category-10')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('order-product-20')));
    await tester.pumpAndSettle();
    expect(find.text('Hamburguesa'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('special-category-11')));
    await tester.pumpAndSettle();
    expect(find.text('Tocineta'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('increase-special-product-21')));
    await tester.pump();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('increase-product-20')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('submit-order')));
    await tester.pumpAndSettle();

    expect(submitted, hasLength(3));
    expect(submitted![0].productId, 20);
    expect(submitted![0].quantity, 1);
    expect(submitted![1].productId, 20);
    expect(submitted![1].quantity, 1);
    expect(submitted![1].specifications, isEmpty);
    expect(submitted![1].removedIngredientIds, isEmpty);
    expect(submitted![2].productId, 21);
    expect(submitted![2].quantity, 1);
    expect(submitted![2].parentIndex, 0);
  });

  testWidgets('order editor removes only undelivered units', (tester) async {
    List<OrderItemWrite>? submitted;
    const product = ClientMenuProduct(
      id: 20,
      name: 'Hamburguesa',
      description: null,
      value: 18000,
      ingredients: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OrderEditorDialog(
          spanish: true,
          tableLabel: '4',
          menus: const [
            ClientRoomMenu(
              id: 1,
              name: 'Principal',
              isPrimary: true,
              categories: [
                ClientMenuCategory(
                  id: 10,
                  name: 'Platos',
                  parentCategoryId: null,
                  isSpecial: false,
                  products: [product],
                ),
              ],
            ),
          ],
          existingOrder: const ClientOrder(
            id: 7,
            tableId: 4,
            tableGroupId: null,
            status: 'waiting',
            description: null,
            items: [
              ClientOrderItem(
                id: 70,
                productId: 20,
                name: 'Hamburguesa',
                productDescription: null,
                quantity: 2,
                deliveredQuantity: 1,
                deliveredUnitIndexes: [0],
                status: 'ordered',
                specifications: null,
                parentOrderItemId: null,
                removedIngredientIds: [],
                ingredients: [],
              ),
            ],
          ),
          onSubmit: (_, items) async => submitted = items,
        ),
      ),
    );

    final line = find.byKey(const ValueKey('selected-order-line-existing:70'));
    final remove = find.descendant(
      of: line,
      matching: find.byIcon(Icons.remove_circle_outline),
    );
    expect(remove, findsOneWidget);
    await tester.tap(remove);
    await tester.pump();
    expect(tester.widget<InputChip>(line).onDeleted, isNull);
    await tester.tap(find.byKey(const ValueKey('submit-order')));
    await tester.pumpAndSettle();
    expect(submitted, hasLength(1));
    expect(submitted!.single.quantity, 1);
  });

  testWidgets('an entirely pending order can be submitted empty', (
    tester,
  ) async {
    List<OrderItemWrite>? submitted;
    const product = ClientMenuProduct(
      id: 20,
      name: 'Hamburguesa',
      description: null,
      value: 18000,
      ingredients: [],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: OrderEditorDialog(
          spanish: true,
          tableLabel: '4',
          menus: const [
            ClientRoomMenu(
              id: 1,
              name: 'Principal',
              isPrimary: true,
              categories: [
                ClientMenuCategory(
                  id: 10,
                  name: 'Platos',
                  parentCategoryId: null,
                  isSpecial: false,
                  products: [product],
                ),
              ],
            ),
          ],
          existingOrder: const ClientOrder(
            id: 8,
            tableId: 4,
            tableGroupId: null,
            status: 'waiting',
            description: null,
            items: [
              ClientOrderItem(
                id: 80,
                productId: 20,
                name: 'Hamburguesa',
                productDescription: null,
                quantity: 1,
                deliveredQuantity: 0,
                deliveredUnitIndexes: [],
                status: 'ordered',
                specifications: null,
                parentOrderItemId: null,
                removedIngredientIds: [],
                ingredients: [],
              ),
            ],
          ),
          onSubmit: (_, items) async => submitted = items,
        ),
      ),
    );

    final line = find.byKey(const ValueKey('selected-order-line-existing:80'));
    await tester.tap(
      find.descendant(
        of: line,
        matching: find.byIcon(Icons.remove_circle_outline),
      ),
    );
    await tester.pump();
    expect(find.text('Eliminar pedido'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('submit-order')));
    await tester.pumpAndSettle();
    expect(submitted, isEmpty);
  });
}
