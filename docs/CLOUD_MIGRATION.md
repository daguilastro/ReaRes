# Cloud migration

## Scope frozen for the migration

The cloud migration preserves the behavior that is currently working. New
business rules are deliberately out of scope until the cloud version reaches
functional parity with the local backend.

- The first cloud version supports one restaurant.
- Existing roles and permissions remain unchanged.
- Existing table and order states remain unchanged.
- A physical table belongs to at most one logical group.
- Tables with active orders cannot be linked or unlinked.
- A logical group is created when its tables are linked.
- Billing an order does not dissolve its logical table group.
- Automatic logical-group names join table identifiers with `, `.
- Orders can be transferred between individual and logical tables in either
  direction, subject to the existing availability rules.

## Migration boundary

The existing backend under `source/backend` remains the operational local
server during the migration. It must not import code from the Worker runtime.

The cloud implementation lives under `source/cloud-worker` and uses:

- Hono for HTTP routing.
- D1 through the `DB` environment binding.
- Wrangler SQL migrations under `migrations`.

Node-specific infrastructure remains local until its dedicated migration:

- TCP/HTTP listeners and random ports.
- mDNS and Linux/Android endpoint files.
- `node:sqlite` and filesystem database discovery.
- Local TLS certificate creation and pairing.
- The current Node WebSocket server.
- BLE printer access and the future print spooler.

## Stage 2 status

Stage 2 introduces only the cloud foundation:

- A Worker entry point.
- D1 configuration.
- A reproducible initial schema migration.
- `GET /health`, which verifies that the D1 binding can execute a query.

No Flutter client points to this Worker yet, and no production data is
imported during this stage.

## Environments

The committed `database_id` is intentionally a non-production placeholder. It
supports local development but must be replaced with the ID returned by:

```bash
npx wrangler d1 create restauranteapp-cloud
```

Local migration and development:

```bash
npm run cloud:d1:migrate:local
npm run cloud:dev
```

Remote staging migration, only after configuring the real D1 ID:

```bash
npm run cloud:d1:migrate:remote
```

Production must eventually use a separate Wrangler environment and a separate
D1 database from staging.

## Stage 3: read-only cloud API

The first cloud vertical slice is available under `/api/v1`:

- `GET /bootstrap` returns the complete catalog and hall summaries in one
  response. Layouts are intentionally excluded because they can be loaded only
  when a user opens a hall.
- `GET /catalog` returns menus, ingredients and ingredient categories.
- `GET /menus` returns all menus.
- `GET /menus/:menuId` returns one menu or `MENU_NOT_FOUND`.
- `GET /halls` returns hall summaries and table counts.
- `GET /halls/:hallId/layout` returns tables, walls and logical groups, or
  `HALL_NOT_FOUND`.

These preview routes are read-only and intentionally unauthenticated. They
must not be considered production-ready until the authentication stage is
complete.

To load deterministic development data into the local D1 database:

```bash
npm run cloud:d1:seed:local
```

The seed uses IDs in the 9000 range and is never applied by the migration or
remote deployment commands.

## Stage 4: cloud authentication

Cloud authentication no longer depends on mTLS, QR pairing, mDNS, a local IP
or a random port. Cloudflare terminates HTTPS for the stable Worker origin and
the Worker accesses D1 through its `DB` binding.

The cloud API exposes:

- `POST /api/v1/auth/login` with `username` and `password`.
- `GET /api/v1/auth/session` with a Bearer token.
- `POST /api/v1/auth/logout` to revoke the presented token.

Sessions are stored only as SHA-256 token hashes, expire after 12 hours and are
shared by administrator and employee roles. Password verification retains the
existing scrypt format so accounts can be migrated without resetting their
passwords.

Every Stage 3 route now requires a valid session. Catalog and complete menu
routes require an administrator. Administrators can read every hall, while an
employee can list and open only halls present in `employee_halls`.

The development fixture provides these local-only users; both use the password
`CloudTest123!`:

- `cloud.admin`
- `cloud.waiter`

The fixture must never be applied to a remote or production database.

The legacy local server still contains discovery and pairing code so the
currently working application remains usable during migration. That code is
not imported by the Worker and will be deleted only after cloud endpoint and
Flutter parity is complete.

Nginx is not needed for testing. Use `wrangler dev` for local API tests and a
staging `workers.dev` deployment for end-to-end mobile tests over real HTTPS.

## Stage 5: administrative catalog writes

The Worker now owns the cloud mutations required by the current catalog. All
of them require an authenticated administrator and live below
`/api/v1/admin` so their middleware cannot intercept employee endpoints:

- `PUT /halls/:hallId/menus` assigns one primary menu and selected products
  from secondary menus.
- `POST /ingredient-categories` and `POST /ingredients` create ingredients.
- `POST /menus` creates a menu and its initial hall assignments.
- `POST /menus/:menuId/categories`, `PATCH /categories/:categoryId` and
  `PUT /menus/:menuId/category-order` manage the recursive category tree.
- `POST /menus/:menuId/products`, `PATCH /products/:productId` and
  `DELETE /products/:productId` create, edit and deactivate products.
- `PUT /categories/:categoryId/product-order` persists the custom product
  order used by the ordering client.

Compound writes use D1 batches so assignments and relation tables cannot be
partially updated. Product deletion remains a soft delete to preserve order
history. Repeated product and category names remain valid where the current
schema permits them.

## Stage 6: orders and billing

Authenticated administrators and assigned employees can now use the cloud
order flow under `/api/v1/halls/:hallId`:

- Read the hall-specific primary and restricted secondary menus.
- Read active orders and closed orders from the 01:00–23:59 Bogotá business
  interval, optionally filtered by an explicit interval and payment method.
- Create table or external orders with descriptions, removed ingredients and
  special products attached to a normal parent item.
- Edit or delete an empty pending order without removing delivered units.
- Transfer an active table order to an available physical or logical table.
- Deliver and undo delivery one concrete unit at a time.
- Bill only an order whose items are all delivered and record cash, transfer
  or card as its payment method.

Every mutation also writes the existing activity and order-modification audit
records. Migration `0003_order_item_price_snapshot.sql` freezes the unit price
on each ordered item so later catalog edits cannot alter historical totals.

Stage 6 deliberately does not publish real-time messages. Requests currently
write directly to D1; routing these mutations through one Durable Object and
broadcasting versioned invalidations is the Stage 7 boundary. Flutter still
uses the local Node backend until the later client-adaptation stage.

## Stage 7: coordinated mutations and real-time patches

The cloud Worker now uses one `RestaurantCoordinator` Durable Object named
`restaurant:default`. The name intentionally represents the future tenancy
boundary: multi-restaurant support can select `restaurant:<restaurantId>`
without turning the whole service into one global coordinator.

Request routing is deliberately asymmetric:

- `GET`, `HEAD` and `OPTIONS` continue directly from Worker to D1.
- Authenticated `POST`, `PUT`, `PATCH` and `DELETE` requests are forwarded by
  the Worker to `RestaurantCoordinator`.
- `GET /api/v1/realtime` upgrades to a hibernatable WebSocket owned by the
  same coordinator.

The coordinator serializes mutations in arrival order, invokes the Stage 5/6
mutation router, records the idempotency receipt and multicasts the resulting
patch. D1 remains the source of truth; the Durable Object does not keep orders
or catalog data exclusively in volatile memory.

### Mutation idempotency

Clients should send a unique value for every logical mutation:

```http
Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000
```

If omitted, the Worker generates one and returns it in the response. Repeating
the same key for the same authenticated user returns the stored HTTP response
with `Idempotency-Replayed: true` and does not repeat the mutation.

### WebSocket protocol

The WebSocket uses the same Bearer token as HTTP. After `connected`, a client
subscribes to a hall:

```json
{"type":"subscribe","hallId":9001}
```

Only administrators and employees assigned to that hall may subscribe. An
administrator can additionally request the global administrative feed:

```json
{"type":"subscribe-admin"}
```

Connection metadata is serialized as a WebSocket attachment so subscriptions
survive Durable Object hibernation. Expired or explicitly revoked sessions are
closed with WebSocket policy code `1008`.

### Delta messages

Messages carry the changed entity rather than forcing every client to reload
the complete collection. An order mutation looks like:

```json
{
  "type": "hall.orders.changed",
  "resource": "hall:9001:orders",
  "version": 12,
  "mutationId": "550e8400-e29b-41d4-a716-446655440000",
  "hallId": 9001,
  "payload": {
    "operation": "upsert",
    "order": { "id": 42, "status": "waiting", "items": [] }
  }
}
```

Deletion uses `{ "operation": "delete", "orderId": 42 }`. Catalog messages
similarly carry a single menu, category, product, ingredient or ordering
change. Billing additionally emits `dashboard.changed`, and each order audit
entry emits `activity.created` for subscribed administrators.

Migration `0004_realtime_coordination.sql` maintains `resource_versions` using
D1 triggers in the same transaction as the business write. A subscription
acknowledgement includes the current versions of `catalog`, hall layout and
hall orders. A future cached client compares these with its local versions and
performs a GET only if it missed a patch while disconnected.

## Stage 8: Flutter cloud clients

Both Flutter applications now use the stable Worker origin directly. The
origin is selected at compile/run time and never comes from mDNS, a QR image,
a certificate fingerprint, a Unix socket or a random local port:

```bash
flutter run \
  --dart-define=RESTAURANT_API_URL=https://your-worker.workers.dev
```

For a Linux client running beside `wrangler dev`, use
`http://127.0.0.1:8787`. An Android device must use a reachable HTTPS staging
or production Worker URL; its own `127.0.0.1` does not refer to the development
computer.

Startup now checks `/health`, validates the securely stored 12-hour Bearer
token through `/api/v1/auth/session`, and shows login only when there is no
valid session. Pairing and discovery screens are no longer part of the active
navigation. Android manifests retain only normal Internet/network-state
permissions for this transport.

The employee client opens `/api/v1/realtime`, subscribes with `hallId`, and
applies `hall.orders.changed` upserts/deletions and `hall.layout.changed`
replacements directly to visible state. Table colors are recalculated for all
physical members of a logical table. The client records resource revisions,
ignores duplicate messages, and performs a canonical GET only after a
reconnection reports a changed revision or a patch cannot be parsed.

The administrator client requests `subscribe-admin`. Activity rows are added
from `activity.created` without polling; `dashboard.changed` refreshes billed
sales metrics. Remote catalog, hall and employee mutations refresh only the
affected administrative section, while mutations originated by that same app
are recognized by their `Idempotency-Key` and do not cause a disruptive
mid-operation rebuild.

Cloud parity routes added for the existing Flutter views include admin
overview/activity, employee management, hall creation/editor persistence and
employee live-layout movement/grouping. Layout and assignment patches are
scoped by hall or user. Every Flutter mutation supplies an idempotency key.
