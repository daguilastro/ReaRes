# Arquitectura e implementación de RestauranteApp

Este documento describe la organización actual del repositorio, los procesos en ejecución, los límites de seguridad, la persistencia y los flujos implementados. Debe mantenerse sincronizado con los cambios estructurales del proyecto.

## 1. Resumen

RestauranteApp es una aplicación local-first compuesta por tres piezas:

1. Un backend Node.js independiente que utiliza Hono y SQLite.
2. Una aplicación Flutter administrativa que se ejecuta en la misma máquina del backend.
3. Una aplicación Flutter operativa que puede ejecutarse en celular o escritorio y se conecta por la red local.

El backend abre dos servidores distintos. La API administrativa solo escucha en loopback. La API de dispositivos escucha en la LAN mediante HTTPS y es la única que se anuncia por mDNS.

```text
┌──────────────────────────── computador central ────────────────────────────┐
│                                                                            │
│  front-server ── Unix socket ──► puerto dinámico                           │
│       │                              │                                     │
│       └──── HTTP 127.0.0.1 ─────────► API administrativa                   │
│                                      Node.js + Hono ─────► SQLite           │
│                                             │                              │
└─────────────────────────────────────────────┼──────────────────────────────┘
                                              │ HTTPS + certificado cliente
                                              │ puerto dinámico + mDNS
                              ┌───────────────┴────────────────┐
                              │ front-client-mobile           │
                              │ Android / Linux / otros targets│
                              └────────────────────────────────┘
```

## 2. Estructura del repositorio

```text
RestauranteApp/
├── db/
│   ├── schheme.sql                 Esquema declarativo inicial
│   ├── restaurant.sqlite           Base usada durante el desarrollo
│   ├── restaurant.sqlite-wal       Write-ahead log temporal de SQLite
│   └── restaurant.sqlite-shm       Índice compartido temporal de SQLite
├── docs/
│   ├── v1UserStories.docx          Requisitos preliminares originales
│   ├── v2UserStories.md            Requisitos e historias actualizados
│   ├── v2UserStories.docx          Versión Word generada de la versión 2
│   └── ARCHITECTURE.md              Este documento
├── source/
│   ├── backend/
│   │   ├── server.ts               Composición y ciclo de vida de listeners
│   │   ├── admin/                  API accesible únicamente por loopback
│   │   │   ├── app.ts
│   │   │   ├── infrastructure/
│   │   │   │   └── portSocket.ts
│   │   │   └── routes/
│   │   │       ├── register.ts
│   │   │       ├── session.ts
│   │   │       ├── employees.ts
│   │   │       ├── pairDevice.ts
│   │   │       └── layout.ts
│   │   ├── device/                 API HTTPS para dispositivos emparejados
│   │   │   └── app.ts
│   │   ├── shared/                 Identidad, hashing, DB y estado compartido
│   │   └── tests/                  Pruebas separadas por dominio/API
│   ├── front-server/               Cliente Flutter administrativo adaptable
│   │   ├── lib/services/
│   │   ├── lib/views/auth/
│   │   ├── lib/views/splash/
│   │   └── lib/views/dashboard/
│   └── front-client-mobile/        Cliente Flutter operativo móvil/escritorio
│       ├── lib/models/
│       ├── lib/services/
│       └── lib/views/
├── package.json
└── tsconfig.json
```

No deben volver a crearse `front-server-pc` y `front-server-mobile`: la decisión vigente es mantener un solo frontend administrativo responsivo.

## 3. Backend

### 3.1 Arranque

El punto de entrada es `source/backend/server.ts`. El orden de inicialización es importante:

1. Abre la base de datos, ejecuta el esquema idempotente y aplica migraciones estructurales.
2. Crea o recupera la identidad persistente del servidor.
3. Abre la API administrativa en `127.0.0.1` y puerto `0`.
4. Crea el socket Unix que comunica el puerto administrativo.
5. Abre la API HTTPS de dispositivos en un puerto asignado por el sistema operativo.
6. Publica únicamente la API HTTPS mediante mDNS.
7. Registra el host, puerto y huella actuales para generar invitaciones de pairing.
8. Instala cierre ordenado para `SIGINT` y `SIGTERM`.

El comando de desarrollo es:

```bash
npm start
```

### 3.2 API administrativa

La aplicación Hono administrativa vive en `source/backend/admin/app.ts` y escucha exclusivamente en `127.0.0.1`. No comparte listener con la API de dispositivos y no se anuncia por mDNS.

| Método | Ruta | Autorización | Función |
| --- | --- | --- | --- |
| GET | `/` | Local | Comprobación exacta de disponibilidad. |
| POST | `/api/admin/register` | Loopback | Registra una cuenta con rol `admin`. |
| POST | `/api/admin/login` | Credenciales admin | Crea una sesión de 12 horas. |
| GET | `/api/admin/session` | Bearer admin | Valida y restaura la sesión. |
| POST | `/api/admin/logout` | Bearer opcional | Revoca la sesión presentada. |
| GET | `/api/admin/employees` | Bearer admin | Lista empleados y sus salones asignados. |
| POST | `/api/admin/employees` | Bearer admin | Crea un empleado y sus asignaciones. |
| PATCH | `/api/admin/employees/:id` | Bearer admin | Cambia rol, contraseña o salones. |
| DELETE | `/api/admin/employees/:id` | Bearer admin | Elimina un empleado. |
| POST | `/api/admin/pairing-requests` | Bearer admin | Genera una invitación de dos minutos. |
| GET | `/api/admin/rooms` | Bearer admin | Lista salones y estadísticas agregadas. |
| POST | `/api/admin/rooms` | Bearer admin | Crea un salón vacío. |
| GET | `/api/admin/rooms/:id/layout` | Bearer admin | Carga el layout completo. |
| PUT | `/api/admin/rooms/:id/layout` | Bearer admin | Reemplaza el layout atómicamente. |

El endpoint de registro se apoya actualmente en el límite de loopback. Antes de una distribución multiusuario conviene añadir una regla de bootstrap, por ejemplo permitirlo solo mientras no exista ningún administrador.

### 3.3 Descubrimiento del puerto administrativo

El sistema operativo escoge un puerto libre porque el listener utiliza `port: 0`. El backend publica ese número a través de `admin-port.sock`.

Rutas actuales:

- Linux con `XDG_RUNTIME_DIR`: `$XDG_RUNTIME_DIR/restaurante-app/admin-port.sock`.
- Linux sin esa variable: `/tmp/restaurante-app-<uid>/restaurante-app/admin-port.sock`.
- Termux: `$PREFIX/var/run/restaurante-app/admin-port.sock`.

El directorio usa permisos `0700` y el socket `0600`. Si existe un socket abandonado por un cierre abrupto, Node verifica si sigue activo antes de reemplazarlo. Si está activo, el nuevo backend se niega a iniciar para evitar dos instancias administrativas.

La aplicación Flutter lee una línea, valida el rango del puerto y comprueba la respuesta exacta de `http://127.0.0.1:<puerto>/`.

### 3.4 API de dispositivos

La API en `source/backend/device/app.ts` usa HTTPS y se anuncia como `Restaurante._https._tcp.local`.

| Método | Ruta | Protección | Función |
| --- | --- | --- | --- |
| GET | `/` | TLS | Health check básico. |
| GET | `/pairing` | TLS | Indica disponibilidad del pairing. |
| POST | `/pairing/complete` | Certificado cliente + secreto | Consume la invitación y registra el dispositivo. |
| GET | `/device/connection` | Dispositivo emparejado | Confirma que el dispositivo sigue autorizado. |
| POST | `/auth/login` | Dispositivo emparejado + credenciales | Autentica una cuenta no administrativa. |
| GET | `/rooms` | Sesión de empleado + dispositivo | Lista únicamente los salones asignados. |
| GET | `/rooms/:id/layout` | Sesión de empleado + asignación | Obtiene el layout completo de un salón. |
| GET | `/rooms/:id/menus` | Sesión de empleado + asignación | Obtiene el menú principal y los productos secundarios habilitados. |
| GET | `/rooms/:id/orders` | Sesión de empleado + asignación | Obtiene los pedidos activos del salón. |
| POST | `/rooms/:id/tables/:tableId/orders` | Sesión de empleado + asignación | Crea el pedido de una mesa y la deja esperando. |
| PUT | `/rooms/:id/orders/:orderId` | Sesión de empleado + asignación | Reemplaza el contenido editable de un pedido activo y audita el cambio. |
| PATCH | `/rooms/:id/orders/:orderId/status` | Sesión de empleado + asignación | Cambia un pedido de esperando a comiendo. |
| PUT | `/rooms/:id/live-layout` | Sesión de empleado + asignación | Actualiza posiciones y grupos de mesas. |
| GET | `/realtime` | Sesión de empleado + dispositivo | Actualiza una conexión HTTP a WebSocket. |
| GET | `/api/admin/activities` | Sesión administrativa local | Consulta la actividad persistida más reciente. |
| GET | `/api/admin/events` | Sesión administrativa local | Abre un stream SSE de actividad en tiempo real. |

El servidor TLS solicita certificado cliente, pero utiliza `rejectUnauthorized: false` porque los clientes manejan certificados autofirmados. La autorización estricta se completa en la aplicación comparando la huella del certificado con `paired_devices`. Esto demuestra posesión de la clave privada asociada al certificado registrado, pero no equivale a validar una cadena contra una CA privada en la propia capa TLS.

### 3.5 Identidad del servidor

`shared/serverIdentity.ts` genera un certificado autofirmado EC P-256 con uso de servidor y vigencia de diez años. La clave se escribe con permisos `0600`; el certificado, con `0644`.

Rutas:

- Linux: `${XDG_DATA_HOME:-$HOME/.local/share}/restaurante-app/identity/`.
- Termux: `$PREFIX/var/lib/restaurante-app/identity/`.

Los archivos son `server-key.pem` y `server-cert.pem`. Si ambos existen se reutilizan. La huella publicada y usada para pinning es SHA-256.

### 3.6 Contraseñas y sesiones

Las contraseñas se derivan con `scrypt`:

- `N = 2^17`;
- `r = 8`;
- `p = 1`;
- sal aleatoria de 16 bytes;
- clave derivada de 64 bytes.

El valor almacenado incluye algoritmo, parámetros, sal y clave derivada. La comparación utiliza `timingSafeEqual`.

Las sesiones administrativas y operativas utilizan tokens aleatorios de 32 bytes codificados en Base64URL. El token original se entrega una sola vez; SQLite conserva únicamente SHA-256 del token. Ambas expiran como máximo a las 12 horas.

Una sesión operativa queda enlazada simultáneamente al usuario y al registro de `paired_devices`. Presentar el token desde otro certificado no es suficiente para reutilizarla. El mismo middleware protege HTTP y el handshake de WebSocket.

## 4. Emparejamiento y reconexión

### 4.1 Contenido del QR

El JSON codificado en el QR tiene esta forma:

```json
{
  "version": 1,
  "host": "192.168.1.20",
  "port": 43127,
  "scheme": "https",
  "pairingId": "uuid",
  "pairingSecret": "valor-aleatorio-base64url",
  "expiresAt": "2026-08-30T20:00:00.000Z",
  "certificateFingerprint": "SHA-256"
}
```

El QR no es una credencial permanente. Su secreto vence en dos minutos, se guarda hasheado en el servidor y queda marcado como usado dentro de la misma transacción que registra el dispositivo.

### 4.2 Handshake actual

1. El administrador autenticado solicita el QR por loopback.
2. El cliente valida estructura, versión y expiración.
3. El cliente abre HTTPS hacia el host y puerto del QR.
4. Presenta su certificado y clave privada.
5. Calcula SHA-256 del certificado del servidor y exige coincidencia exacta con el QR.
6. Envía el identificador y secreto temporal.
7. El servidor compara el hash usando una operación de tiempo constante.
8. Si el secreto es válido y el certificado existe en la conexión TLS, registra su huella, serie y PEM.
9. El cliente guarda host, puerto y huella en `paired-server.json`.

En Android/iOS el QR se captura mediante cámara. En escritorio se selecciona una imagen y se decodifica localmente.

### 4.3 Reconexión

El puerto de red puede cambiar después de reiniciar el backend. Por ello, el cliente no confía permanentemente en el host/puerto guardado:

1. Busca `_https._tcp.local` mediante mDNS.
2. Filtra servicios cuyo nombre comienza por `Restaurante`.
3. Prueba cada IPv4 y puerto anunciado.
4. Exige la huella del servidor guardada durante el pairing.
5. Presenta su propio certificado.
6. Consulta `/device/connection`.
7. Solo continúa al login si el servidor también reconoce el dispositivo.

En Android, donde mDNS no es suficientemente consistente, el primer pairing se
hace mediante QR. Después del handshake comprueba `/device/connection` con su
certificado antes de guardar atómicamente IP, puerto, huella y si Node vive en el
mismo dispositivo. En los siguientes arranques reutiliza ese endpoint con mTLS;
para Termux en el mismo teléfono prueba loopback primero. Si la comprobación
falla vuelve a ofrecer el QR. La reconexión solo descubre y autentica el servidor:
la cuenta del empleado debe iniciar sesión de nuevo.

`admin-port.txt` utiliza un objeto JSON con `adminPort`, `deviceHost`,
`devicePort` y `updatedAt`. Node revisa la IPv4 local cada tres segundos y
actualiza el archivo si cambia la red; el puerto de dispositivos permanece
estable mientras el proceso vive y se reemplaza al reiniciar el servidor.

## 5. Base de datos

### 5.1 Ubicación y apertura

Las APIs administrativa y de dispositivos comparten una única base fuera del
repositorio:

```text
${RESTAURANTE_DB_FILE}
```

Si `RESTAURANTE_DB_FILE` no está definido, se utiliza:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/restaurante-app/restaurant.sqlite
```

Esto aplica tanto a Linux de escritorio como a Termux. En la primera ejecución
posterior a la migración, si el destino todavía no existe, el backend copia
automáticamente `db/restaurant.sqlite` y su bundle WAL/SHM. Una base existente
en la ruta genérica nunca se sobrescribe.

Cada apertura habilita:

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;
```

`schheme.sql` se ejecuta de manera idempotente y después se aplican migraciones de compatibilidad en `schemaMigration.ts`.

Los precios se almacenan como pesos enteros, sin centavos implícitos. La
migración `2026-08-normalize-product-values-to-pesos` divide una sola vez entre
100 los valores heredados de productos y de productos retirados. El script
`scripts/start-server-background.sh` crea antes una copia SQLite consistente en
`restaurante-app/backups/`; la fila de `schema_migrations` impide repetir tanto
la transformación como el respaldo en arranques posteriores.

### 5.2 Archivos WAL y SHM

`restaurant.sqlite-wal` contiene cambios recientes del modo write-ahead logging. `restaurant.sqlite-shm` coordina lectores y escritores. Son archivos normales de SQLite, pueden aparecer junto a la base en el directorio genérico mientras existe una conexión y no deben borrarse con el servidor activo. Para respaldar la base se debe cerrar el servidor o utilizar la API de backup/checkpoint de SQLite.

### 5.3 Tablas actuales

| Tabla | Responsabilidad |
| --- | --- |
| `users` | Administradores y empleados, rol y hash de contraseña. |
| `admin_sessions` | Hashes y expiración de sesiones administrativas. |
| `employee_sessions` | Hashes y expiración de sesiones de empleados, enlazadas al dispositivo. |
| `device_pairing_requests` | Invitaciones temporales hasheadas, expiración y consumo. |
| `paired_devices` | Certificados de clientes autorizados y revocación. |
| `hall` | Salones del restaurante. |
| `employee_halls` | Relación muchos-a-muchos entre empleados y salones. |
| `hall_tables` | Mesas físicas, identificador, estado y geometría. |
| `hall_walls` | Paredes y su geometría. |
| `table_groups` | Mesas lógicas temporales con identidad y estado propios. |
| `table_group_members` | Relación entre grupos y mesas físicas. |
| `menu` | Catálogos de menú globales. |
| `menu_halls` | Disponibilidad muchos-a-muchos y marca de menú principal/secundario por salón. |
| `menu_categories` | Categorías, subcategorías y marca de categoría especial. |
| `products` | Productos, descripción, precio y categoría foránea. |
| `product_halls` | Productos habilitados desde menús secundarios para ciertos salones. |
| `ingredient_categories` | Clasificación administrativa de ingredientes. |
| `ingredients` | Ingredientes asociados obligatoriamente a una categoría. |
| `product_ingredients` | Relación producto–ingrediente. |
| `orders` | Pedidos por mesa física o mesa lógica agrupada y autor. |
| `order_items` | Productos, cantidades, indicaciones, estado y relación con una adición especial. |
| `order_item_deliveries` | Entrega individual de cada unidad, con índice, empleado y momento. |
| `order_item_removed_ingredients` | Ingredientes que el cliente pidió retirar de cada ítem. |
| `order_modifications` | Auditoría de creación, edición y cambios de estado de pedidos. |
| `activity_log` | Feed administrativo persistente de pedidos, estados y agrupaciones. |

El catálogo administrativo permite crear menús, categorías, subcategorías, productos e ingredientes. Un menú puede no estar publicado en ningún salón o publicarse en varios. `menu_halls.is_primary` permite un único menú principal por salón mediante un índice único parcial. El menú principal expone todos sus productos; un menú secundario solo expone los productos expresamente relacionados con el salón en `product_halls`.

`menu_categories.parent_category_id` admite un nivel de subcategoría. Las categorías especiales para combos, adiciones u otros ítems facturables siempre viven en la raíz: no pueden convertirse en subcategorías ni recibir subcategorías. Un producto normal referencia una categoría o subcategoría mediante `category_id`; los productos especiales referencian una categoría raíz marcada con `is_special`.

El endpoint operativo `GET /rooms/:id/menus` aplica estas reglas después de verificar la asignación del empleado al salón. El pedido conserva cantidades, notas generales y por producto e ingredientes retirados. `order_items.parent_order_item_id` vincula cada adición especial con un producto normal dentro de esa orden concreta; no modifica el catálogo. Triggers de SQLite y la validación HTTP impiden guardar una adición huérfana, enlazarla a otro pedido o usar como padre otro producto especial. `order_item_deliveries` identifica exactamente qué unidad fue entregada, sin agrupar productos visualmente ni perder variantes de indicaciones. Crear, editar, entregar o cambiar el estado escribe una entrada en `order_modifications` dentro de la misma transacción.

### 5.4 Persistencia de layouts

Cada mesa guarda `x`, `y`, `width`, `height` y `rotation`. Cada pared guarda la misma geometría. Los grupos conservan una identificación visible y referencias a mesas existentes.

`PUT /api/admin/rooms/:id/layout` valida todo el payload antes de iniciar la escritura. La actualización se ejecuta dentro de una transacción `BEGIN IMMEDIATE`; si alguna inserción o relación falla se hace rollback.

`PUT /rooms/:id/live-layout` aplica un contrato más limitado: un trabajador puede modificar las posiciones de todas las mesas y sus agrupaciones lógicas, pero no puede crear o eliminar mesas, cambiar sus identificadores, dimensiones o rotaciones, ni editar paredes. También se valida la asignación del empleado antes de leer o escribir.

La eliminación de un salón se propaga a su layout mediante claves foráneas con `ON DELETE CASCADE`.

## 6. Frontend administrativo

### 6.1 Arranque

`front-server/lib/main.dart` detecta el locale y crea la aplicación Material 3. En release siempre inicia por el splash. En debug se puede saltar temporalmente a una vista mediante:

```bash
flutter run --dart-define=START_SCREEN=dashboard
flutter run --dart-define=START_SCREEN=login
flutter run --dart-define=START_SCREEN=register
```

El splash ejecuta simultáneamente la verificación del backend local y un tiempo mínimo visual. Luego intenta restaurar el token seguro. Si el backend no está disponible muestra 404; si la sesión es válida entra al dashboard; de lo contrario muestra autenticación.

### 6.2 Organización por vista

- `views/auth/`: login, registro y transición entre ambos.
- `views/splash/`: comprobaciones iniciales y transición sin cuadro negro.
- `views/dashboard/admin_dashboard.dart`: navegación adaptable y composición principal.
- `views/dashboard/employees/`: listado y modales de empleados.
- `views/dashboard/pair_device/`: QR, renovación, expiración y descarga.
- `views/dashboard/halls/`: listado de salones, editor, modelos y controlador de interacción.
- `services/`: acceso HTTP, sesión segura y descubrimiento local.

La UI no debe ejecutar SQL ni conocer rutas físicas de SQLite. Toda persistencia pasa por `admin_api.dart` y los endpoints locales.

### 6.3 Editor de salones

El editor separa responsabilidades:

- `RoomLayoutModel` y modelos relacionados representan JSON y geometría.
- `RoomLayoutController` mantiene selección, estado sucio, snapshot persistido, colisiones, snapping y operaciones.
- `HallLayoutPage` traduce mouse/touch en operaciones del controlador y dibuja los objetos.

Comportamiento relevante:

- un salón nuevo no recibe datos de ejemplo;
- el lienzo se presenta como un espacio continuo, sin habitación blanca fija;
- el área renderizada mantiene un origen lógico amplio alrededor de las coordenadas del layout, de modo que los objetos con posiciones negativas continúan dentro del hit testing y no aparecen zonas visibles pero imposibles de editar;
- al cargar o centrar se calcula el encuadre a partir de los límites reales de todos los objetos;
- clic en el fondo limpia la selección;
- el arrastre de escritorio usa eventos de puntero para evitar la competencia con el paneo de `InteractiveViewer`;
- en móvil una mesa requiere pulsación larga;
- el movimiento se transforma solo por la cámara, no por la rotación del objeto;
- el redimensionado sí transforma el delta a ejes locales;
- el resize de paredes, igual que el de mesas, acumula el delta local desde la geometría existente al comenzar el gesto y desplaza el centro rotado para mantener fija la esquina visual opuesta al handle;
- rotación y resize tienen controles independientes;
- durante la rotación se deshabilita temporalmente el paneo de cámara;
- la rotación se calcula con el vector entre el centro del objeto y el cursor: la cara superior queda perpendicular a ese vector y el handle apunta hacia el cursor;
- el ángulo se fija exactamente a múltiplos de 90° dentro de una tolerancia de 5°;
- las colisiones y el snapping usan el AABB de la geometría rotada;
- se admite una tolerancia pequeña de coma flotante para que dos bordes en contacto no se consideren superpuestos;
- cuando hay varios posibles imanes, se aplica una corrección que no produzca colisión;
- los muros también aplican snapping entre sus límites visuales rotados al trasladarse;
- mesas y muros nuevos se crean alrededor del centro visible y buscan una posición cercana libre para no apilarse;
- un objeto seleccionado puede copiarse con `Ctrl+C` y pegarse con `Ctrl+V`; el menú contextual ofrece copiar sobre objetos y pegar sobre el fondo en la posición del cursor;
- guardar envía el layout completo; cancelar restaura el último snapshot aceptado.

## 7. Cliente operativo

### 7.1 Arranque e identidad

El splash crea o carga la identidad del cliente. La generación RSA-2048 se ejecuta en otro isolate para no bloquear la animación. Los archivos `client-key.pem` y `client-cert.pem` se guardan dentro del application support directory privado de Flutter.

Después intenta reconectarse por mDNS. Si no existe estado previo o no encuentra el servidor correcto, abre pairing. Si reconecta, abre login.

### 7.2 Diferencias por plataforma

- Android/iOS: cámara mediante `mobile_scanner`.
- Linux/Windows/macOS: selector de archivos y decodificación local de PNG, JPG, JPEG o WebP.

No existen dos proyectos cliente. La decisión es compartir vistas, servicios y modelos, aislando únicamente la interacción dependiente de plataforma.

### 7.3 Login, salones y vista en vivo

El cliente usa el canal HTTPS pinneado y presenta su certificado. `/auth/login` solo permite usuarios cuyo rol no sea `admin`, crea una sesión operativa de 12 horas ligada al dispositivo y devuelve token, expiración y usuario.

Después del login se solicitan únicamente los salones relacionados con el empleado en `employee_halls`. La vista inicial muestra nombre, rol y tarjetas adaptables; una cuenta sin asignaciones ve un estado vacío. Al abrir una tarjeta se consume el layout actual del salón y se entra en live view.

En live view las paredes son de solo lectura. Las mesas se pueden seleccionar, mover, acoplar por bordes y unir o separar lógicamente mediante una única acción contextual. En escritorio el movimiento comienza al arrastrar; en móvil requiere pulsación larga. Cada cambio válido se persiste automáticamente mediante el endpoint operativo restringido.

La barra inferior está centrada y mantiene tres modos visuales mutuamente excluyentes: edición, facturación y selección. Al activar edición, el siguiente clic sobre una mesa o grupo abre su pedido en un diálogo superpuesto con transición fade. Allí se navegan categorías y subcategorías, se ajustan cantidades, se revisan ingredientes, se retiran ingredientes, se agregan notas y se asocian productos especiales. Al enviar un pedido nuevo la mesa pasa a `waiting` y se pinta amarilla. En modo selección, tocar una mesa esperando abre la vista de entrega: cada unidad aparece por separado con descripción, indicaciones e ingredientes retirados, y las adiciones aparecen anidadas bajo su producto padre. La última unidad entregada cambia automáticamente pedido, mesa o grupo a `eating`. Si una mesa que estaba comiendo recibe productos nuevos, conserva las entregas anteriores y vuelve a `waiting` hasta entregar lo pendiente. En móvil, el inicio de una pulsación prolongada para mover una mesa produce feedback háptico.

Una agrupación se persiste como una mesa lógica `table_groups` estable, con identificador `G-<id>`. Si sus mesas ya tenían pedidos activos, el backend los consolida transaccionalmente bajo esa mesa lógica. El estado esperando/comiendo se proyecta sobre todos los miembros físicos. Desagrupar conserva el pedido en su mesa física de respaldo. Abrir un pedido en modo edición no selecciona ni resalta visualmente la mesa.

### 7.4 Actualización en tiempo real

Después de autenticar al empleado, `RoomsPage` abre una sola conexión WSS y la comparte con las vistas de salón. El upgrade exige el mismo token, certificado cliente y dispositivo emparejado que los endpoints HTTP.

Al entrar en un salón el cliente envía `subscribe` con su identificador. El servidor comprueba que el empleado siga asignado y registra la suscripción. Cuando un administrador guarda un layout o un trabajador mueve o agrupa mesas, el backend emite `room-layout-changed`. Crear, editar o cambiar el estado de un pedido emite `room-orders-changed`. Ambos eventos se envían exclusivamente a los sockets suscritos a ese salón.

El evento es una invalidación, no una copia del estado: contiene el identificador del salón y el momento del cambio. Al recibirlo, cada cliente vuelve a consumir `GET /rooms/:id/layout`. De esta forma HTTP y SQLite siguen siendo la única fuente de verdad y no se mantiene un segundo modelo de datos dentro del WebSocket.

Cambiar las asignaciones emite `room-assignments-changed` solamente a las conexiones del empleado afectado; su lista se vuelve a consultar. Eliminar la cuenta invalida sus sesiones por cascada y cierra sus sockets con código 1008. El cliente vuelve a conectar automáticamente después de interrupciones transitorias y restaura sus suscripciones activas.

El cliente administrativo, que solo usa loopback, mantiene además un stream SSE autenticado. Node publica cada creación o modificación de pedido, cambio de estado y modificación de agrupaciones después del commit. El dashboard actualiza Actividad reciente —incluso expandida— y la vista en vivo administrativa vuelve a consultar el layout del salón afectado, por lo que muestra los mismos colores que el cliente operativo.

## 8. Seguridad y límites de confianza

### 8.1 Lo que protege la API administrativa

Escuchar en `127.0.0.1` impide conexiones directas desde otros equipos de la LAN. El socket Unix evita explorar puertos y restringe el descubrimiento al usuario local. La sesión limita operaciones después del login.

Esto no protege contra malware o un usuario hostil que ya pueda ejecutar procesos bajo la misma cuenta del sistema operativo. La seguridad del computador central, sus permisos, actualizaciones y acceso físico continúan siendo parte del modelo de amenaza.

### 8.2 Lo que protege el pairing

La huella del servidor evita aceptar otro certificado durante el primer contacto. El secreto temporal demuestra que el administrador autorizó el intento reciente. El certificado cliente vincula futuras conexiones con una clave privada persistente.

Copiar únicamente una huella o un certificado público no permite suplantar una identidad, porque durante TLS también se necesita la clave privada correspondiente. Copiar el QR completo dentro de su ventana de dos minutos sí representa una credencial temporal; debe mostrarse y compartirse únicamente durante el emparejamiento intencional.

### 8.3 Limitaciones actuales

- El servidor solicita certificados cliente, pero la confianza se decide en el código de la ruta y no mediante una CA configurada con `rejectUnauthorized: true`.
- Falta una pantalla y endpoint administrativo para revocar dispositivos.
- Falta persistir de forma segura la sesión operativa en Flutter si se desea omitir el login después de reiniciar el cliente.
- El registro del primer administrador debería cerrarse después del bootstrap.
- La base de datos aún vive dentro del repositorio de desarrollo.
- TLS no reemplaza la validación de payload, autorización, auditoría ni protección del host.

## 9. Pruebas y calidad

### Backend

```bash
npm run typecheck
npm test
```

Las pruebas cubren registro, sesiones administrativas y operativas, asignaciones de empleados, pairing, autorización por salón, catálogo y restricciones de productos, layouts/estadísticas y distribución segmentada de invalidaciones en tiempo real.

### Flutter administrativo

```bash
cd source/front-server
flutter analyze
flutter test
```

Incluye pruebas de splash, localización, autenticación, dashboard, empleados, pairing, salones, expansión de actividad y controlador del layout.

### Flutter operativo

```bash
cd source/front-client-mobile
flutter analyze
flutter test
```

Las pruebas cubren QR, identidad, reconexión, login, transición, listado de salones, movimiento, snapping y agrupación lógica en live view.

Para evaluar fluidez real debe usarse profile o release. Debug añade instrumentación y no representa el rendimiento final:

```bash
flutter run --profile
flutter build linux --release
```

## 10. Convenciones de implementación

- Backend separado en `admin`, `device`, `shared` y `tests`.
- Frontends separados por `views`, `services` y `models`; cada área del dashboard conserva sus subvistas en su carpeta.
- Los puertos permanecen dinámicos; no introducir números fijos como mecanismo de descubrimiento.
- No anunciar la API administrativa por mDNS.
- No almacenar contraseñas, tokens o secretos temporales en texto plano en SQLite.
- No leer SQLite directamente desde Flutter.
- No crear layouts de ejemplo al crear un salón.
- Mantener JSON compatible y validar tipos y rangos antes de persistir.
- Toda modificación compuesta del layout debe permanecer transaccional.
- WebSocket solo comunica invalidaciones; el estado se vuelve a consultar por el endpoint HTTP autorizado.
- Una suscripción de tiempo real debe validarse contra `employee_halls` y limitarse al salón solicitado.
- Las migraciones deben conservar bases existentes; `schheme.sql` debe seguir siendo idempotente.
- Las diferencias de interacción por plataforma deben localizarse en la vista, no duplicar proyectos completos.

## 11. Próximos pasos recomendados

1. Persistir/restaurar la sesión operativa de forma segura si se desea evitar un nuevo login tras reiniciar.
2. Implementar preparación, estados individuales de ítems, cobro y cierre de mesa.
3. Definir control de versiones o resolución de ediciones simultáneas del layout.
4. Conectar actividad reciente y gráficos con consultas reales.
5. Administrar y revocar dispositivos emparejados.
6. Restringir el registro administrativo después del bootstrap.
7. Mover SQLite a una ruta de datos estable y diseñar backup/restauración.
8. Evaluar una CA local y validación mTLS estricta si el modelo de despliegue lo requiere.
9. Diseñar migraciones versionadas antes de distribuir instalaciones con datos reales.
