# Historias de usuario y requisitos — versión 2

Fecha: 30 de agosto de 2026  
Proyecto: RestauranteApp  
Estado del documento: versión de trabajo actualizada a partir de las decisiones de arquitectura y de producto tomadas durante el prototipado.

## 1. Propósito de esta versión

Esta versión reemplaza las suposiciones preliminares de `v1UserStories.docx` cuando exista una contradicción. Conserva el objetivo de gestionar visualmente la operación de un restaurante, pero incorpora las decisiones que ya se tomaron al construir el servidor, el cliente administrativo y el cliente operativo.

La palabra **implementado** describe una capacidad que ya tiene código funcional en el repositorio. **Parcial** indica que existe la base técnica o una vista temporal, pero todavía falta el flujo de negocio. **Planificado** identifica trabajo posterior.

## 2. Cambios principales respecto a la versión 1

| Tema | Decisión actual |
| --- | --- |
| Ejecución | El backend Node.js se ejecuta como proceso independiente de las aplicaciones Flutter. |
| Equipo central | El escenario principal utiliza un computador Linux central. Termux en Android sigue contemplado por las rutas de almacenamiento del backend, pero no es el despliegue principal. |
| Frontend administrativo | Existe un único proyecto Flutter, `front-server`, adaptable a escritorio y celular. Se descartaron proyectos administrativos separados para PC y móvil. |
| Cliente operativo | Existe un único proyecto Flutter, `front-client-mobile`, con comportamiento específico para móvil y escritorio. |
| API administrativa | Utiliza un listener HTTP independiente enlazado exclusivamente a `127.0.0.1`, con puerto aleatorio asignado por el sistema operativo. Nunca se anuncia por mDNS. |
| Descubrimiento administrativo | El backend comunica el puerto administrativo mediante un socket Unix local con permisos `0600`. |
| API para dispositivos | Utiliza un listener HTTPS de red local independiente, puerto aleatorio y anuncio mDNS. |
| Identidad del servidor | Node.js genera y conserva una clave privada y un certificado persistentes antes de abrir los listeners. |
| Identidad del cliente | Flutter genera una clave y un certificado persistentes dentro del almacenamiento privado de cada aplicación cliente. |
| Emparejamiento | El administrador genera un QR de un solo uso que vence en dos minutos. Contiene host, puerto, huella del servidor, identificador y secreto temporal. |
| Reconexión | Después del primer emparejamiento, el cliente descubre el servidor mediante mDNS y solo acepta el certificado cuya huella guardó. |
| Autenticación administrativa | La sesión administrativa dura como máximo 12 horas. El token se guarda de forma segura en Flutter y solo su hash se persiste en SQLite. |
| Contraseñas | Se almacenan mediante `scrypt` con una sal aleatoria; nunca se guarda la contraseña en texto plano. |
| Asignación operativa | Un empleado puede pertenecer a cero o varios salones mediante una relación muchos-a-muchos. |
| Sesión de empleado | Dura 12 horas, se almacena hasheada y queda ligada tanto al usuario como al certificado del dispositivo. |
| Tiempo real | Un WebSocket autenticado distribuye invalidaciones solo a los clientes suscritos al salón modificado; el estado se recarga por HTTP. |
| Salones | Antes del editor existe una vista de salones con estadísticas. Un salón nuevo comienza vacío, sin layout predeterminado. |
| Editor | El lienzo no representa un rectángulo blanco fijo. Mesas y paredes pueden moverse, redimensionarse y rotarse. La geometría completa se persiste en SQLite. |
| Interacción por plataforma | En escritorio una mesa se selecciona con clic y se mueve arrastrándola. En móvil se mantiene presionada antes de moverla. |
| Ajustes del editor | Las mesas se acoplan por sus bordes sin superponerse y la rotación se fija cerca de múltiplos de 90°. |
| Idiomas | Las interfaces detectan el idioma del dispositivo. Se soportan español e inglés; cualquier otro idioma utiliza inglés. |
| Estado sin Internet | El servidor local y la operación dentro de la LAN no dependen de Internet. La sincronización remota continúa planificada. |

## 3. Descripción del problema

El restaurante necesita reemplazar el registro fragmentado mediante papel, mensajería y transcripción manual. La solución debe permitir que cada trabajador opere con su propia cuenta, que los cambios se reflejen dentro de la red local y que las mesas, pedidos y productos tengan estado y trazabilidad.

Los productos de una misma orden no siempre avanzan juntos. Una bebida puede estar lista mientras un plato continúa pendiente. Por ello, el sistema debe representar el estado de cada ítem y conservar quién realizó cada modificación.

La solución tampoco puede depender de Internet para la operación diaria. El computador central mantiene el backend y la base de datos local; los demás dispositivos se conectan a él dentro de la red del restaurante.

## 4. Objetivo general

Construir una plataforma local, visual y colaborativa para administrar salones, usuarios, mesas, pedidos y preparación de productos, con autenticación por usuario, dispositivos previamente emparejados, trazabilidad de cambios y una interfaz adaptable a escritorio y móvil.

## 5. Actores

### 5.1 Administrador

Configura el restaurante desde la misma máquina donde se ejecuta el backend. Registra la cuenta administrativa, administra empleados, empareja dispositivos, crea salones, diseña layouts y consulta métricas.

### 5.2 Mesero

Accede desde un dispositivo emparejado, inicia sesión con una cuenta autorizada, consulta mesas, abre servicios, registra pedidos y marca entregas.

### 5.3 Cocina y barra

Consultan los productos asignados a su estación y actualizan sus estados de preparación.

### 5.4 Cajero

Consulta cuentas, revisa modificaciones, registra el pago y cierra mesas.

### 5.5 Gerente

Consulta métricas de ventas, demanda, tiempos, cancelaciones y actividad. Puede coincidir con el administrador, pero conceptualmente es un actor de análisis.

### 5.6 Servidor local

Proceso Node.js independiente que mantiene SQLite, atiende la API administrativa por loopback y la API de dispositivos por HTTPS en la red local.

### 5.7 Dispositivo cliente

Aplicación Flutter que posee su propia identidad criptográfica. Debe emparejarse antes de acceder a rutas operativas.

## 6. Historias de usuario actuales

### Módulo A — Administración y sesiones

#### HU-01 — Registrar el administrador inicial — Implementado

Como administrador, quiero registrar mi nombre, usuario y contraseña desde la aplicación administrativa local para crear mi cuenta de administración.

Criterios de aceptación:

- la API solo está disponible por loopback;
- el nombre de usuario es único y se normaliza a minúsculas;
- la contraseña debe contener entre 12 y 128 caracteres;
- la contraseña se guarda mediante `scrypt` con sal aleatoria;
- el rol asignado es `admin`.

#### HU-02 — Iniciar sesión administrativa — Implementado

Como administrador, quiero iniciar sesión para acceder al dashboard y a las operaciones protegidas.

Criterios de aceptación:

- solo una cuenta con rol `admin` puede usar este login;
- el servidor genera un token aleatorio y guarda únicamente su hash;
- la sesión vence como máximo 12 horas después de su creación;
- Flutter conserva el token en almacenamiento seguro.

#### HU-03 — Restaurar una sesión administrativa — Implementado

Como administrador, quiero que la aplicación compruebe mi sesión durante el splash para no iniciar sesión de nuevo después de reiniciar la aplicación.

#### HU-04 — Cerrar sesión administrativa — Implementado

Como administrador, quiero cerrar sesión para revocar el token actual y eliminarlo del almacenamiento local.

#### HU-05 — Detectar el backend local — Implementado

Como administrador, quiero que la aplicación confirme que el backend está ejecutándose en mi misma máquina para evitar conectarse por error a una API administrativa de la red.

Criterios de aceptación:

- la aplicación lee el puerto desde el socket Unix local;
- valida que sea un puerto entre 1 y 65535;
- consulta exclusivamente `127.0.0.1`;
- si el socket, el puerto o el servicio no son válidos, muestra la pantalla 404 con opción de reintento.

### Módulo B — Empleados y permisos

#### HU-06 — Listar empleados — Implementado

Como administrador, quiero consultar las cuentas no administrativas para conocer quién puede usar el cliente operativo.

#### HU-07 — Crear un empleado — Implementado

Como administrador, quiero crear una cuenta con nombre, usuario, contraseña y rol para autorizar a un trabajador.

Roles admitidos actualmente: `waiter`, `kitchen`, `cashier` y `manager`.

La cuenta puede crearse sin salones o asignarse a uno o varios salones existentes.

#### HU-08 — Modificar un empleado — Implementado

Como administrador, quiero cambiar el rol, la contraseña o los salones de un empleado para mantener sus permisos, credenciales y áreas de trabajo actualizados.

#### HU-09 — Eliminar un empleado — Implementado

Como administrador, quiero eliminar una cuenta de empleado para revocar su acceso.

La eliminación revoca sus sesiones por cascada, elimina sus asignaciones y cierra sus conexiones WebSocket activas.

#### HU-10 — Aplicar permisos por rol — Parcial

Como administrador, quiero que cada rol acceda únicamente a las funciones correspondientes. La distinción entre administrador y empleado ya existe; los permisos operativos detallados todavía deben definirse por endpoint y vista.

### Módulo C — Identidad y emparejamiento de dispositivos

#### HU-11 — Mantener una identidad estable del servidor — Implementado

Como sistema local, quiero generar una clave privada y un certificado la primera vez y reutilizarlos después para mantener la misma identidad criptográfica entre reinicios.

#### HU-12 — Mantener una identidad estable del cliente — Implementado

Como dispositivo cliente, quiero generar mi clave y certificado en almacenamiento privado y reutilizarlos para demostrar que soy el mismo dispositivo después de reiniciar.

#### HU-13 — Generar una invitación temporal — Implementado

Como administrador autenticado, quiero generar un QR temporal para autorizar deliberadamente un dispositivo.

Criterios de aceptación:

- el secreto utiliza aleatoriedad criptográfica;
- la base de datos conserva el hash del secreto, no el valor original;
- la invitación vence en dos minutos;
- una invitación utilizada no puede reutilizarse;
- el QR contiene versión de formato, host, puerto HTTPS, identificador, secreto, expiración y huella SHA-256 del certificado del servidor;
- es posible renovar y descargar el QR.

#### HU-14 — Escanear el QR en un celular — Implementado

Como trabajador con un celular, quiero escanear la invitación mediante la cámara para emparejar el dispositivo.

Un QR con formato desconocido, campos inválidos o expirado se ignora y no inicia el handshake.

#### HU-15 — Cargar el QR en un computador — Implementado

Como trabajador desde un computador, quiero seleccionar una imagen PNG, JPG o WebP con el QR para emparejar el cliente sin cámara.

#### HU-16 — Verificar el servidor durante el emparejamiento — Implementado

Como cliente, quiero calcular la huella del certificado recibido y compararla con la invitación para no entregar el secreto a otro servidor.

#### HU-17 — Autorizar el certificado del dispositivo — Implementado

Como servidor, quiero registrar la huella, serie y certificado del cliente que presenta un secreto temporal válido para reconocerlo en futuras conexiones.

#### HU-18 — Rechazar dispositivos desconocidos o revocados — Implementado en las rutas actuales

Como servidor, quiero rechazar una conexión operativa si el cliente no presenta certificado o su huella no está autorizada.

#### HU-19 — Reconectar mediante mDNS — Implementado

Como cliente emparejado, quiero descubrir el puerto actual del servidor mediante mDNS para reconectarme aunque el sistema operativo asigne un puerto diferente.

Criterios de aceptación:

- el nombre mDNS esperado comienza por `Restaurante`;
- el certificado debe coincidir con la huella guardada durante el emparejamiento;
- el servidor debe reconocer el certificado del cliente;
- si no se encuentra una coincidencia válida, se vuelve al flujo de emparejamiento.

### Módulo D — Dashboard administrativo

#### HU-20 — Visualizar el resumen operativo — Implementado con datos de demostración

Como administrador, quiero consultar ventas, cantidad de órdenes, ticket promedio, tendencia y categorías para tener una visión rápida del restaurante.

#### HU-21 — Cambiar el período del gráfico — Implementado en la interfaz

Como administrador, quiero consultar la tendencia por hora, días, meses o años y ajustar el rango disponible para analizar distintos períodos.

Rangos actuales de interfaz:

- días: de 2 a 31;
- meses: de 2 a 24;
- años: de 2 a 10.

La alimentación con datos históricos reales continúa pendiente.

#### HU-22 — Consultar actividad reciente — Implementado en la interfaz

Como administrador, quiero visualizar autor, tipo y modificación de las acciones recientes, y expandir la tarjeta sobre un fondo bloqueado para concentrarme en el historial.

La persistencia y consulta real del historial siguen pendientes.

### Módulo E — Salones y editor de layout

#### HU-23 — Listar salones — Implementado

Como administrador, quiero ver todos los salones existentes antes de entrar al editor para escoger el área que deseo administrar.

#### HU-24 — Consultar estadísticas por salón — Implementado

Como administrador, quiero ver cantidad de mesas, cantidad de órdenes, ventas totales y venta promedio por salón para comparar su actividad.

#### HU-25 — Crear un salón vacío — Implementado

Como administrador, quiero crear un salón sin paredes ni mesas predeterminadas para diseñarlo desde cero.

#### HU-26 — Abrir el layout de un salón — Implementado

Como administrador, quiero seleccionar un salón y cargar desde SQLite únicamente sus mesas, paredes y agrupaciones.

#### HU-27 — Trabajar sobre un lienzo continuo — Implementado

Como administrador, quiero editar el layout sin quedar limitado visualmente por una única habitación blanca predeterminada.

Los objetos con coordenadas negativas siguen siendo visibles e interactivos. Al centrar la cámara se encuadran los límites reales del contenido y no un rectángulo predeterminado.

#### HU-28 — Crear mesas identificables — Implementado

Como administrador, quiero crear mesas con un identificador visible y único dentro del salón.

Las mesas y paredes nuevas aparecen alrededor del centro visible del editor y buscan una posición cercana libre para no quedar apiladas.

#### HU-29 — Mover mesas según la plataforma — Implementado

Como administrador de escritorio, quiero seleccionar una mesa con clic y moverla arrastrando inmediatamente. Como administrador móvil, quiero mantenerla presionada antes de moverla para evitar desplazamientos accidentales.

#### HU-30 — Acoplar mesas sin superponerlas — Implementado

Como administrador, quiero que una mesa cercana se acople al borde real de otra, incluso si está rotada, para alinearlas sin recibir un falso error de colisión.

#### HU-31 — Redimensionar mesas — Implementado

Como administrador, quiero usar un control visual para cambiar el ancho y alto de una mesa, respetando un tamaño mínimo y evitando colisiones.

#### HU-32 — Rotar mesas con ajuste angular — Implementado

Como administrador, quiero rotar una mesa mediante un control visual y que se fije exactamente al eje al acercarse a un múltiplo de 90°.

El ángulo se obtiene de la dirección entre el centro de la mesa y el cursor: el control de rotación apunta al cursor y la cara correspondiente permanece perpendicular a esa dirección.

#### HU-33 — Crear y editar paredes — Implementado

Como administrador, quiero crear, seleccionar, mover, redimensionar y rotar paredes sin activar un modo separado de movimiento.

El redimensionado utiliza los ejes locales de la pared y acumula el gesto desde su geometría inicial, igual que el redimensionado de las mesas. Si el objeto está rotado, la esquina visual opuesta al handle permanece fija mientras se desplazan el centro, el ancho y el alto de manera coordinada.

Al trasladar un muro cerca de otro se aplica snapping sobre sus límites visuales rotados.

#### HU-34 — Mover correctamente paredes rotadas — Implementado

Como administrador, quiero que una pared rotada se desplace en la misma dirección del puntero y no en sus ejes locales.

#### HU-35 — Rotar paredes con ajuste angular — Implementado

Como administrador, quiero que una pared se fije exactamente al eje al acercarse a 0°, 90°, 180° o 270°.

El handle debe apuntar hacia el cursor; la rotación no se deriva de sumar desplazamientos horizontales o verticales.

#### HU-36 — Deseleccionar desde el fondo — Implementado

Como administrador, quiero hacer clic en el fondo para retirar la selección actual y ocultar sus controles de edición.

#### HU-37 — Agrupar y separar mesas — Implementado

Como administrador, quiero agrupar varias mesas físicas sin destruir su geometría y separarlas posteriormente.

#### HU-38 — Guardar el layout de forma atómica — Implementado

Como administrador, quiero guardar mesas, paredes y grupos en una sola operación para evitar un layout parcialmente actualizado.

#### HU-39 — Cancelar cambios no guardados — Implementado

Como administrador, quiero restaurar el último layout persistido si cancelo la edición.

#### HU-39A — Copiar y pegar objetos — Implementado

Como administrador, quiero copiar una mesa o pared seleccionada con `Ctrl+C` o desde su menú contextual y pegarla con `Ctrl+V` o desde el menú del fondo.

Criterios de aceptación:

- la copia conserva dimensiones y rotación;
- una mesa copiada recibe un identificador único;
- pegar desde el menú contextual coloca el centro de la copia en el cursor o en la posición libre más cercana;
- el nuevo objeto queda seleccionado;
- hacer clic derecho en el fondo limpia la selección y ofrece pegar cuando existe una copia.

#### HU-40 — Consultar y operar el layout en vivo — Implementado

Como trabajador asignado, quiero consultar el layout sin controles administrativos, mover mesas y unirlas o separarlas lógicamente. Las paredes y la estructura definida por el administrador permanecen protegidas. Una sola acción enlaza toda la selección cuando ninguna mesa está agrupada y deshace los grupos implicados cuando alguna ya estaba enlazada.

Cada grupo es una mesa lógica persistida con identidad propia. Sus pedidos activos se consolidan bajo esa identidad y el estado visual se aplica a todas las mesas físicas integrantes.

### Módulo F — Cliente operativo y autenticación

#### HU-41 — Completar comprobaciones iniciales — Implementado

Como usuario del cliente, quiero que el splash espere la creación o carga de mi identidad y el intento de reconexión antes de decidir la siguiente pantalla.

#### HU-42 — Iniciar sesión como empleado — Implementado

Como empleado, quiero iniciar sesión con una cuenta no administrativa desde un dispositivo emparejado para que el servidor identifique mi nombre y rol.

Criterios de aceptación:

- se crea un token de 12 horas y SQLite guarda únicamente su hash;
- la sesión queda asociada al certificado del dispositivo que inició sesión;
- reutilizar el token desde otro dispositivo no concede acceso.

#### HU-43 — Mantener limpia la transición del login — Implementado

Como usuario, quiero que los campos y el estado del formulario permanezcan visibles durante el fade-out para evitar saltos visuales antes de entrar a la siguiente vista.

#### HU-44 — Escoger un salón asignado — Implementado

Como empleado autenticado, quiero ver exclusivamente los salones en los que trabajo y abrir uno para cargar su layout actual.

Criterios de aceptación:

- una cuenta puede tener cero, uno o varios salones;
- un salón no asignado no aparece y su endpoint responde con acceso denegado;
- el nombre y el rol del empleado aparecen en la vista;
- la cuadrícula se adapta a escritorio y celular.

### Módulo G — Mesas y pedidos operativos

#### HU-45 — Consultar el estado de las mesas — Implementado parcialmente

Como trabajador, quiero distinguir mesas disponibles, ocupadas y pendientes para comprender la situación del salón rápidamente.

Actualmente se distinguen disponible, esperando en amarillo y comiendo en verde. Falta el ciclo de cobro y cierre.

#### HU-46 — Abrir una mesa — Implementado

Como mesero, quiero abrir el servicio de una mesa para comenzar un pedido.

#### HU-47 — Agregar productos y cantidades — Implementado

Como mesero, quiero agregar productos con sus cantidades para registrar lo solicitado.

El selector presenta categorías y subcategorías, resumen superior y controles `+`/`−`. Los productos de menús secundarios respetan la habilitación del salón.

#### HU-48 — Registrar observaciones — Implementado

Como mesero, quiero añadir instrucciones especiales a un producto para comunicar correctamente la solicitud.

Se aceptan una nota general, indicaciones por producto, ingredientes retirados y adiciones especiales vinculadas al producto padre.

#### HU-49 — Modificar o cancelar un producto — Implementado parcialmente

Como mesero autorizado, quiero modificar o cancelar un ítem conservando la acción en el historial.

El pedido activo puede reenviarse con cantidades, notas, ingredientes o productos modificados. La instantánea anterior y la nueva quedan en `order_modifications`; falta modelar la cancelación posterior a preparación.

#### HU-50 — Consultar el pedido completo — Implementado

Como trabajador, quiero consultar todos los ítems y estados de una mesa para conocer su servicio completo.

#### HU-51 — Gestionar estados independientes — Implementado parcialmente

Como trabajador de preparación, quiero cambiar cada ítem entre pendiente, en preparación y listo; como mesero quiero marcarlo entregado.

La entrega ya funciona por unidad exacta, conserva descripciones, ingredientes retirados y la relación visual con adiciones. Al entregar la última unidad, la mesa cambia automáticamente a `eating`; añadir algo nuevo la devuelve a `waiting` sin perder lo ya entregado. Siguen pendientes los estados de cocina `preparing` y `ready`.

#### HU-52 — Conservar productos preparados retirados — Planificado

Como trabajador, quiero registrar un producto preparado que se retiró de una orden para poder reutilizarlo o contabilizar la pérdida.

#### HU-53 — Cerrar una mesa — Planificado

Como mesero o cajero autorizado, quiero revisar, cobrar y cerrar una mesa para dejarla disponible y conservar su historial.

### Módulo H — Tiempo real, auditoría y continuidad

#### HU-54 — Recibir cambios de salón en tiempo real — Implementado para layouts, pedidos, actividad y asignaciones

Como trabajador, quiero recibir automáticamente los cambios realizados por otros dispositivos para operar con información actualizada.

Criterios de aceptación:

- el WebSocket exige sesión de empleado y certificado emparejado;
- cada vista se suscribe únicamente al salón abierto y el servidor revalida la asignación;
- guardar un layout administrativo u operativo emite una invalidación a todos los sockets suscritos a ese salón;
- el evento indica qué recurso cambió y el cliente vuelve a consumir el endpoint HTTP autorizado;
- los clientes de otros salones no reciben la invalidación;
- la conexión intenta recuperarse y vuelve a suscribir los salones activos;
- un cambio de asignaciones actualiza la lista del empleado afectado.

#### HU-55 — Consultar historial — Parcial

Como usuario autorizado, quiero conocer autor, tipo, valores y momento de cada modificación. El esquema de modificaciones y la interfaz de actividad existen, pero falta completar su integración.

#### HU-56 — Operar sin Internet — Decisión de arquitectura implementada parcialmente

Como restaurante, quiero que las funciones esenciales dependan del servidor local y la LAN, no de Internet. La infraestructura es local; falta implementar el conjunto completo de operaciones.

#### HU-57 — Recuperarse de una interrupción local — Parcial

Como cliente, quiero reencontrar automáticamente el servidor después de un cambio de puerto o una interrupción. La reconexión y autenticación del dispositivo existen; layouts y pedidos activos se recuperan desde la API después de cada invalidación.

#### HU-58 — Sincronizar copias remotas — Planificado

Como administrador, quiero respaldar y sincronizar información cuando exista Internet sin duplicar operaciones.

### Módulo I — Menú, preparación y extensiones

#### HU-59 — Administrar productos y precios — Implementado parcialmente

Como administrador, quiero crear menús, ingredientes, categorías y productos con descripción, precio y disponibilidad por salón.

Criterios implementados:

- un menú puede pertenecer a cero o varios salones y ser principal o secundario en cada uno;
- solo puede existir un menú principal por salón;
- el menú principal muestra todos sus productos y los secundarios únicamente los productos seleccionados para ese salón;
- no se puede crear un producto antes de crear al menos una categoría;
- las categorías normales admiten un nivel de subcategorías;
- las categorías especiales para combos o adiciones viven únicamente en la raíz y no admiten subcategorías;
- cada producto referencia una categoría o subcategoría del mismo menú mediante clave foránea;
- una adición especial se vincula a su producto normal únicamente dentro de la orden mediante `parent_order_item_id`, sin alterar el catálogo;
- un producto puede seleccionar cero o varios ingredientes globales y crear un ingrediente desde su formulario;
- los ingredientes se organizan en categorías desde un módulo administrativo independiente;
- un mesero solo puede consultar menús del salón que tiene asignado y productos visibles en ese salón.

Quedan pendientes edición y eliminación de los elementos del catálogo y su integración visual en el cliente operativo.

#### HU-60 — Asignar estaciones de preparación — Planificado

Como administrador, quiero asignar cada producto a cocina, barra u otra estación.

#### HU-61 — Consultar cola por estación — Planificado

Como trabajador de cocina o barra, quiero ver únicamente los productos correspondientes a mi estación, ordenados por prioridad.

#### HU-62 — Imprimir comandas — Futuro

Como restaurante, quiero enviar e imprimir comandas por estación mediante impresoras térmicas.

#### HU-63 — Sincronización en la nube — Futuro

Como administrador, quiero disponer de respaldos y acceso externo controlado cuando haya Internet.

#### HU-64 — Soportar inventario, facturación y varias sedes — Futuro

Como propietario, quiero ampliar el sistema con inventario, facturación, múltiples sedes e integraciones externas sin reemplazar la arquitectura central.

## 7. Reglas de negocio vigentes

- **RN-01 — Identidad de usuario:** toda operación de negocio relevante debe asociarse con un usuario autenticado.
- **RN-02 — Roles:** la cuenta administrativa es distinta de las cuentas operativas. Los empleados no pueden iniciar sesión en la API administrativa.
- **RN-03 — Contraseñas:** nunca se almacenan en texto plano.
- **RN-04 — Sesiones administrativas:** vencen a las 12 horas y pueden revocarse mediante logout.
- **RN-05 — API administrativa local:** solo escucha en loopback y no se anuncia por mDNS.
- **RN-06 — Puerto administrativo:** lo asigna el sistema operativo y se comunica por un socket Unix local protegido.
- **RN-07 — API de dispositivos:** se anuncia por mDNS únicamente para dispositivos de la LAN.
- **RN-08 — Emparejamiento explícito:** un dispositivo necesita un secreto temporal válido y presentar su certificado.
- **RN-09 — Invitación temporal:** vence en dos minutos y solo puede consumirse una vez.
- **RN-10 — Pinning:** el cliente debe comprobar la huella del certificado del servidor antes de confiar en él.
- **RN-11 — Dispositivo conocido:** las rutas operativas protegidas requieren un certificado cuya huella esté activa en `paired_devices`.
- **RN-11A — Sesión operativa:** el token de empleado vence en 12 horas, se guarda hasheado y solo es válido junto al dispositivo que lo creó.
- **RN-11B — Asignación de salón:** leer, mover o agrupar mesas requiere una fila vigente en `employee_halls` para el usuario y salón.
- **RN-12 — Salón vacío:** crear un salón no genera paredes ni mesas automáticamente.
- **RN-13 — Identificador de mesa:** es único dentro del salón.
- **RN-14 — Layout persistente:** posición, dimensiones y rotación de mesas y paredes deben conservarse entre sesiones.
- **RN-15 — Guardado atómico:** el layout completo debe confirmarse o revertirse como una unidad.
- **RN-16 — Colisiones:** dos mesas no pueden ocupar un área común; el contacto exacto entre bordes sí es válido.
- **RN-17 — Snapping de traslación:** el acople usa los límites visuales rotados de las mesas.
- **RN-18 — Snapping angular:** cerca de cada múltiplo de 90°, el ángulo se almacena exactamente sobre ese eje.
- **RN-19 — Productos independientes:** cada ítem de una orden tendrá un estado propio.
- **RN-20 — Auditoría:** una cancelación o modificación relevante no debe desaparecer del historial.
- **RN-21 — Operación local:** una caída de Internet no debe detener las funciones esenciales mientras el servidor local y la LAN sigan disponibles.
- **RN-22 — Fuente de verdad:** los eventos WebSocket invalidan caché; los clientes obtienen el estado actualizado mediante HTTP y nunca toman el evento como layout definitivo.
- **RN-23 — Segmentación de eventos:** un cambio de layout se publica solamente a conexiones autenticadas y suscritas al salón afectado.

## 8. Requisitos no funcionales

- **RNF-01 — Seguridad por capas:** loopback para administración; sesión para autorización; TLS, pinning y certificado cliente para dispositivos.
- **RNF-02 — Persistencia de secretos:** claves privadas dentro de almacenamiento privado y con permisos restrictivos cuando la plataforma los soporte.
- **RNF-03 — Fluidez:** animaciones y gestos deben evitar trabajo pesado en el hilo de UI. La generación de identidad del cliente se ejecuta en otro isolate.
- **RNF-04 — Adaptabilidad:** un mismo código Flutter debe responder a tamaños de escritorio y celular.
- **RNF-05 — Accesibilidad visual:** etiquetas animadas, mensajes de error y controles deben conservar contraste y significado.
- **RNF-06 — Internacionalización:** español e inglés según el idioma del dispositivo; inglés como fallback.
- **RNF-07 — Integridad:** SQLite utiliza claves foráneas y las operaciones compuestas críticas utilizan transacciones.
- **RNF-08 — Pruebas:** controladores, vistas y endpoints críticos deben disponer de pruebas automatizadas.
- **RNF-09 — Arranque seguro:** las identidades, el esquema y los listeners deben inicializarse en un orden determinista antes de aceptar operaciones.
- **RNF-10 — Recuperación:** archivos de identidad y estado deben escribirse de manera atómica cuando sea posible.
- **RNF-11 — Local-first:** la operación esencial debe mantenerse dentro de la red del restaurante.
- **RNF-12 — Escalabilidad funcional:** la separación entre API administrativa, API operativa y módulos Flutter debe permitir añadir pedidos, menú e inventario.

## 9. Alcance actualizado

### Base implementada

- backend Node.js independiente con Hono y SQLite;
- listener administrativo por loopback y listener HTTPS para dispositivos;
- puertos dinámicos y descubrimiento apropiado para cada listener;
- identidad persistente de servidor y clientes;
- emparejamiento QR temporal y reconexión mDNS;
- registro, login, validación y cierre de sesión administrativa;
- almacenamiento seguro del token administrativo;
- gestión de empleados;
- relación de cero a varios salones por empleado;
- login y sesión operativa ligada al dispositivo emparejado;
- listado de salones asignados y live view adaptable;
- movimiento, snapping y agrupación de mesas por trabajadores;
- captura y modificación de pedidos con categorías, cantidades, notas, ingredientes retirados y productos especiales;
- estados de mesa esperando/comiendo y auditoría transaccional de pedidos;
- WebSocket autenticado con invalidaciones por salón y reconexión;
- dashboard administrativo adaptable;
- listado, estadísticas, creación y edición de salones;
- persistencia atómica de mesas, paredes y agrupaciones;
- localización español/inglés;
- pruebas automatizadas del backend y de las principales vistas/controladores Flutter.

### Siguiente incremento funcional

- definir permisos exactos por rol;
- implementar cobro y cierre de mesas;
- implementar estaciones y estados individuales de preparación;
- completar estados individuales por producto;
- conectar actividad reciente y métricas con datos reales;
- definir resolución de conflictos para ediciones simultáneas.

### Fuera del MVP actual

- sincronización remota;
- inventario completo;
- facturación fiscal;
- múltiples sedes;
- impresión térmica;
- integraciones con POS externos;
- analítica avanzada.

## 10. Riesgos y decisiones pendientes

- Definir permisos por rol para cada endpoint operativo.
- Definir la resolución de conflictos cuando dos empleados mueven el mismo grupo casi simultáneamente.
- Decidir si la sesión operativa se restaura desde almacenamiento seguro después de reiniciar la aplicación.
- Definir el ciclo final de estados de los ítems.
- Decidir cómo se dividen cuentas y cómo se transfieren productos o mesas.
- Definir propinas, descuentos, cortesías y devoluciones.
- Añadir revocación administrativa de dispositivos emparejados.
- Evaluar una autoridad certificadora local si se desea reemplazar la autorización de certificados por huella a nivel de aplicación por validación mTLS estricta en la capa TLS.
- Mover la base de datos desde la carpeta del proyecto a una ruta de datos genérica antes de distribución.
- Definir respaldo, restauración y política de retención de auditoría.

## 11. Flujo de operación objetivo

Administrador inicia el backend local  
→ la aplicación administrativa descubre el puerto mediante el socket Unix  
→ el administrador inicia o restaura su sesión  
→ crea empleados, salones y layouts  
→ genera una invitación QR temporal  
→ el cliente verifica la huella del servidor y presenta su certificado  
→ el servidor registra el dispositivo  
→ en usos posteriores el cliente descubre el servidor por mDNS y valida ambas identidades  
→ el empleado inicia sesión  
→ consulta únicamente sus salones asignados y abre uno en live view  
→ se conecta por WebSocket al salón y recarga el endpoint cuando recibe una invalidación  
→ selecciona una mesa y registra productos  
→ cada producto avanza de manera independiente por su estación  
→ los cambios se distribuyen a los demás dispositivos y quedan auditados  
→ se revisa la cuenta y se cierra la mesa  
→ los datos permanecen disponibles para métricas y respaldo.
