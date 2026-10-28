# Plan Maestro — Barbería PRO (estado al 18-oct-2026)

Este documento sigue el orden del **Plan Maestro** en PDF
(`Plan_Maestro_Barberia_Salones_Agenda_Apartados.pdf`) y marca qué está hecho y qué falta.
El modelo visual de referencia está en [docs/modelo-visual.png](docs/modelo-visual.png).

**Objetivo de la V1:** organizar citas, reducir no-shows, cobrar un apartado y darle al dueño visibilidad del negocio.
**Primer objetivo:** que una barbería real use la V1.

| Símbolo | Significado |
|---|---|
| ✅ | Hecho y probado con pruebas automáticas |
| 🟡 | Parcial: hay una parte hecha y otra pendiente |
| ⬜ | Pendiente |
| ⏸️ | Aplazado por decisión |

---

## Resumen rápido

| # | Fase del Plan Maestro | Estado | En una línea |
|---|---|---|---|
| 0 | Preparación | ✅ | Proyecto Flutter, conexión a Supabase y repositorio git |
| 1 | Base (datos + seguridad multi-negocio) | ✅ | Tablas, RLS, aislamiento por negocio y protección de roles (001–005), probado en CI |
| 2 | Autenticación y roles | 🟡 | Login, registro y roles listos; falta recuperar contraseña e invitar barberos |
| 3 | Negocio (perfil, horarios, configuración) | ⬜ | Solo existe la pantalla "Próximamente"; faltan tablas de horarios |
| 4 | Servicios | 🟡 | Hecho en React (referencia); falta en Flutter |
| 5 | Empleados | 🟡 | Hecho en React (referencia); falta en Flutter, servicios asignados y disponibilidad |
| 6 | Clientes | ✅ | Lista, búsqueda, alta/edición, visitas, gasto y "Frecuente" |
| 7 | Agenda | 🟡 | Vista por día con Llegó/No vino y solapamientos bloqueados en la base; falta crear/editar citas |
| 8 | Reserva pública | ⬜ | Nada construido; requiere funciones nuevas en la base |
| 9 | Apartado | ⬜ | Tabla existe; sin pantallas. Cobro en línea aplazado |
| 10 | Estados de la cita | 🟡 | Llegó/No vino listos; faltan Completada, Cancelada y reglas en backend |
| 11 | Reportes | 🟡 | Indicadores del día en el panel; falta la pantalla de reportes |
| 12 | QA | 🟡 | 20 pruebas Flutter + pruebas SQL de seguridad en CI; faltan pruebas con cuenta real y dispositivos |
| 13 | Lanzamiento | ⬜ | Sin publicar, sin datos demo ni onboarding |

**Avance aproximado de la V1:** 3 fases completas, 6 parciales y 4 pendientes.

---

## Decisión de arquitectura (a validar con el arquitecto)

El PDF propone **React + Supabase** como web app y deja la **app móvil nativa fuera de la V1**.
Antes de este documento se decidió usar **Flutter** para web, Android e iOS desde un solo código,
manteniendo Supabase y el esquema/RLS existentes. La app React queda solo como referencia.

- La V1 sigue siendo **web responsive**: Flutter web cubre lo que pide el PDF.
- Android e iOS son un extra que no debe retrasar la V1. Se publican después de validar con el primer negocio.
- Según la regla del PDF ("cualquier cambio importante debe pasar primero por la arquitectura"), **este cambio debe quedar aprobado por el arquitecto**.

---

## Detalle por fase

### 0. Preparación ✅
- ✅ Proyecto Flutter en `flutter_app/` (web, Android, iOS) con `supabase_flutter`.
- ✅ URL y *publishable key* de Supabase fuera del código (`dart_defines.local.json`, ignorado por git).
- ✅ Repositorio git con historial; secretos y `_backups/` excluidos.
- ✅ App React conservada como referencia (`src/`); `npm run lint` y `npm run build` pasan.
- ✅ Limpieza: se eliminaron las carpetas duplicadas de la raíz (`pages/`, `services/`, `components/`, `styles/`, `utils/`, `migrations/`); `validacionesModulos.js` pasó a `src/utils/`.

### 1. Base: modelo de datos y seguridad multi-negocio ✅
- ✅ `001_initial_schema.sql`: negocios, perfiles, empleados, servicios, clientes, citas, apartados; enums de rol, estado de cita y estado de apartado; RLS por negocio.
- ✅ `002_hardening_multitenant.sql`: claves foráneas compuestas que impiden mezclar datos de dos negocios.
- ✅ `004_seguridad_perfiles.sql`: corrige una escalada de privilegios (un barbero podía cambiar su propio `rol` a OWNER) y quita el acceso a los perfiles desactivados.
- ✅ Pruebas SQL en `supabase/tests/` que corren en CI sobre PostgreSQL real: aislamiento entre negocios, roles, perfiles inactivos y solapamiento de citas.
- ⬜ **Confirmar que 001–005 están aplicadas en el proyecto real de Supabase** (no verificado desde aquí). 004 y 005 son nuevas y hay que aplicarlas en el SQL Editor.
- ⬜ Tabla `pagos` del PDF: no existe. Se crea cuando se decida el cobro en línea.

### 2. Autenticación y roles 🟡
- ✅ Login y sesión que se mantiene al reabrir.
- ✅ Registro del negocio + dueño (`bootstrap_negocio_owner`), también con confirmación de correo, incluso si se confirma desde otro dispositivo.
- ✅ Menú según rol: el dueño ve todo; el barbero ve Inicio, Mi agenda, Clientes y Reportes.
- ⬜ Recuperar y restablecer contraseña en Flutter (existe en React).
- ⬜ **Invitar barberos:** hoy no hay forma de crear la cuenta de un barbero ni de ligarla a su ficha (`empleados.perfil_id`). Requiere una función de servidor (Edge Function), porque crear usuarios necesita la clave secreta.
- ⬜ Enlaces de confirmación de correo que abran la app en Android/iOS (deep links).

### 3. Negocio: perfil, horarios y configuración ⬜
- ⬜ Pantalla Configuración: nombre, teléfono, dirección, logo e imagen (las columnas ya existen en `negocios`).
- ⬜ **Migración nueva:** horario de apertura del negocio por día de la semana.
- ⬜ **Migración nueva:** monto del apartado configurable (el PDF sugiere RD$100 de ejemplo).
- ⬜ **Migración nueva:** política de apartado configurable (devolución/pérdida) — el PDF pide que no quede fija en el código.
- ⬜ Mostrar y copiar el enlace público `reservar/<slug>`.

### 4. Servicios 🟡
- ✅ CRUD en React (referencia).
- ⬜ CRUD en Flutter: nombre, descripción, precio, duración, activo.
- ⬜ Criterio del PDF: los servicios aparecen correctamente en la reserva pública.

### 5. Empleados 🟡
- ✅ CRUD en React (referencia).
- ⬜ CRUD en Flutter.
- ⬜ **Migración nueva:** servicios que puede hacer cada barbero (tabla `empleado_servicios`).
- ⬜ **Migración nueva:** horario y días libres de cada barbero (disponibilidad).
- ⬜ Ligar la ficha del barbero con su cuenta (ver Fase 2).

### 6. Clientes ✅
- ✅ Lista, búsqueda, alta, edición y activar/desactivar, siempre filtrado por negocio.
- ✅ Visitas, gasto acumulado y etiqueta "Frecuente" (10+ visitas atendidas), calculados desde citas con estado Llegó/Completada.
- ⬜ Ficha con historial: última visita y servicios anteriores.
- ⬜ Recordatorio al cliente (el PDF lo menciona; WhatsApp simple, sin automatización avanzada).
- ⬜ Deuda técnica: el resumen se calcula en la app; si el volumen crece, pasarlo a una vista o RPC con migración.

### 7. Agenda 🟡
- ✅ Agenda por día (‹ › y "Hoy"); el dueño ve todas las citas y el barbero solo las suyas.
- ✅ Panel del dueño: citas hoy, llegaron, no-show, ventas y agenda de hoy.
- ⬜ Crear y editar citas desde el panel (cliente, servicio, barbero, fecha y hora).
- ✅ **Bloqueo de solapamientos** (`005_citas_sin_solapamiento.sql`): un barbero no puede tener dos citas activas cuyos horarios se crucen. Canceladas y no-shows liberan el horario. Error `23P01` para mostrar en la app.
- ⬜ Vista de semana o calendario (opcional para V1).

### 8. Reserva pública ⬜
Pantallas del modelo visual: link público → reservar (servicio, barbero, fecha y hora) → apartado → cita confirmada → "Mi cita".
- ⬜ **Migración nueva:** funciones para visitantes sin sesión: catálogo público del negocio por *slug*, horas disponibles y crear la reserva. Todo validado en el servidor; las políticas actuales no permiten nada sin sesión, y es correcto que así sea.
- ⬜ Pantallas en Flutter con la ruta `reservar/<slug>`.
- ⬜ "Mi cita": consultar, reprogramar o cancelar con un enlace seguro, sin cuenta.
- ⬜ Botones "Agregar al calendario" y "Escríbenos por WhatsApp".
- ⬜ **Prueba de oro del PDF:** una persona que nunca usó el sistema reserva desde el celular sin ayuda.

### 9. Apartado ⬜ / ⏸️ cobro en línea
- ✅ Tabla `apartados` con estados Pendiente/Pagado/Cancelado y un solo apartado activo por cita.
- ⬜ V1 sin pasarela (como recomienda el PDF): el cliente reserva, paga por transferencia y **el dueño valida el apartado a mano**. Al validarlo, la cita pasa a Confirmada.
- ⏸️ Pago con tarjeta (el modelo visual muestra Stripe): aplazado hasta elegir un proveedor compatible con RD y diseñar la confirmación segura en el servidor.

### 10. Estados de la cita 🟡
Estados definidos en la base: Pendiente, Confirmada, Llegó, Completada, No vino, Cancelada.
- ✅ Marcar Llegó / No vino desde la agenda (y deshacer).
- ⬜ Marcar Completada (registrar cobro final) y Cancelada (liberar horario).
- ⬜ Reglas en el servidor para que solo se permitan cambios válidos (por ejemplo, no pasar de Cancelada a Llegó).
- ⬜ Confirmada automáticamente al validar el apartado.

### 11. Reportes 🟡
- ✅ Indicadores del día en el panel.
- ⬜ Pantalla Reportes por período: ingresos, apartados, citas, no-shows y clientes frecuentes.
- ⬜ Prueba del PDF: los totales coinciden con las citas y los cobros registrados.

### 12. QA 🟡
- ✅ 20 pruebas automáticas de Flutter (formatos, registro, clientes, panel y agenda); análisis sin avisos; la versión web compila.
- ✅ CI en GitHub Actions (`.github/workflows/ci.yml`) en cada push: migraciones + pruebas SQL en PostgreSQL, `flutter analyze` + `flutter test` y lint/build de React.
- ✅ Revisión visual con capturas en computadora y celular.
- ⬜ Probar con una cuenta real de Supabase (registro con y sin confirmación de correo, panel y agenda).
- ⬜ Seguridad: comprobar que un negocio no puede leer datos de otro.
- ⬜ Probar en navegadores (Edge, Chrome, Safari) y en teléfonos reales.
- ⬜ Android: falta instalar el Android SDK en este equipo. iOS: requiere una Mac con Xcode.

### 13. Lanzamiento ⬜
- ⬜ Publicar la versión web con dominio.
- ⬜ Negocio de demostración con datos de prueba.
- ⬜ Onboarding: configurar un negocio nuevo en minutos.
- ⬜ Procedimiento para reportar y corregir incidencias.
- ⬜ Después de validar: Android (Google Play) e iOS (TestFlight/App Store).

---

## Plan de pruebas del PDF — estado

| Prueba | Estado | Nota |
|---|---|---|
| Crear negocio | 🟡 | Probado con pruebas automáticas; falta con cuenta real |
| Crear empleado | ⬜ | Falta pantalla e invitación |
| Crear servicio | ⬜ | Falta pantalla Flutter y link público |
| Crear cliente | ✅ | Queda en el negocio correcto |
| Reservar horario | ⬜ | Falta reserva pública |
| Intentar doble reserva | ✅ | La base rechaza solapamientos (prueba SQL en CI); falta el mensaje en la app |
| Apartado | ⬜ | |
| Cancelar | ⬜ | |
| No-show | ✅ | Se marca y se cuenta en el panel |
| Responsive | 🟡 | Panel, agenda y clientes probados en tamaño celular; falta la reserva pública |
| Seguridad | 🟡 | Probado en CI entre dos negocios y entre roles; falta repetirlo en el Supabase real |
| Reportes | 🟡 | Totales del día probados; falta pantalla de reportes |

---

## Orden recomendado de lo que falta

1. **Validar con una cuenta real:** aplicar 004 y 005, confirmar 001–005; probar registro, panel, agenda y clientes.
2. **Migración 006:** horarios del negocio y de cada barbero, servicios por barbero, monto y política del apartado.
3. **Servicios y Empleados en Flutter**, con la invitación de barberos.
4. **Configuración del negocio** y enlace público.
5. **Agenda:** crear/editar citas, Completada y Cancelada.
6. **Reserva pública** (migración con funciones para visitantes) y "Mi cita".
7. **Apartado con validación manual**; la cita pasa a Confirmada.
8. **Reportes** por período.
9. **QA completo**, datos demo y **publicación web**.
10. Primer negocio real → observar → corregir.
11. Android e iOS.

## Comparación con apps parecidas (27-oct-2026)

Referencias: Booksy, Fresha, Vagaro, Square Appointments, AgendaPro, Setmore.

| Función | Ellos | Barbería PRO | Decisión |
|---|---|---|---|
| Reserva en línea por enlace | ✅ todas | 🟡 en construcción (007) | V1 |
| Horario por barbero, días libres | ✅ | ✅ base (006), pantallas en curso | V1 |
| Apartado / depósito | ✅ con tarjeta | 🟡 transferencia + validación manual | V1 (tarjeta después) |
| Recordatorios | ✅ SMS/push automáticos | ⬜ | V1: botón de WhatsApp con mensaje listo (sin API) |
| Agregar al calendario | ✅ | ⬜ | V1 (.ics / Google Calendar) |
| Clientes sin cita (walk-in) | ✅ Booksy, Square | ⬜ | **V1: "Atender ahora"**: en barberías de RD es la mitad del día |
| Ficha del cliente con notas y preferencias | ✅ | 🟡 sin historial | V1 |
| Historial de no-shows del cliente | ✅ Booksy/Fresha | ⬜ | V1: contador visible y aviso |
| Método de pago al cobrar y propina | ✅ | ⬜ | V1 ligera: efectivo/transferencia/tarjeta + propina (migración 008) |
| App instalable | ✅ nativas | ⬜ | V1: web instalable (PWA); nativas después |
| Agenda en tiempo real | ✅ | ⬜ | V1.1 (Supabase Realtime) |
| Reseñas, marketplace, lista de espera | ✅ | ⬜ | V2+ |
| Comisiones, inventario, membresías | ✅ | ⬜ | V3–V4 (fuera de V1, según el PDF) |

**Ventajas que conservamos:** precio local (RD$), apartado por transferencia (lo normal en RD), WhatsApp
como canal principal y simplicidad (la "prueba de oro": reservar sin ayuda).

## Reparto del trabajo (equipo de agentes)

| Tanda | Trabajo | Estado |
|---|---|---|
| 0 | Migración 006 (horarios, servicios por barbero, apartado, estados) | ✅ en master |
| 1 | Servicios y Empleados · Configuración · Agenda (crear/editar/completar/cancelar) · Migración 007 reserva pública · Recuperar contraseña + invitar barberos | 🔄 |
| 1b | Reportes por período · PWA + publicación web + datos demo | 🔄 |
| 2 | Pantallas de reserva pública y "Mi cita" (+ calendario y WhatsApp) · Apartados: validar pagos · Migración 008 cobro (método y propina) · Atender ahora (walk-in) + recordatorio por WhatsApp · Ficha del cliente con historial, notas y no-shows | ⬜ |
| 3 | QA completo, revisión de seguridad, aplicar migraciones en Supabase real, publicar | ⬜ |

## Fuera de la V1 (según el PDF)

Inventario, nómina, comisiones complejas, multi-sucursal avanzada, membresías, promociones sofisticadas,
automatización avanzada de WhatsApp, integraciones contables y analítica con IA.
Roadmap: V2 WhatsApp + fidelización · V3 comisiones + caja · V4 inventario + membresías · V5 multi-sucursal + analítica.

---

## Forma de trabajo

1. Abordar una fase y un flujo concreto cada vez.
2. Antes de editar, confirmar el comportamiento actual y el criterio de aceptación.
3. Hacer el cambio mínimo coherente con la arquitectura existente.
4. Ejecutar la comprobación más cercana al cambio y luego el gate de la fase.
5. No marcar una fase como terminada solo porque compile: validar el flujo en navegador y, cuando corresponda, en dispositivos.
6. Todo cambio de tablas, RPC, índices, restricciones o RLS debe añadirse como migración SQL versionada en `supabase/migrations/` y validarse antes de que Flutter dependa de él. Los cambios de interfaz que usan el esquema actual no requieren una migración nueva.
7. Comparar cada pantalla nueva con el modelo visual (`docs/modelo-visual.png`).
