# Plan Maestro — Barbería PRO (estado al 28-oct-2026)

Este documento sigue el orden del **Plan Maestro** en PDF
(`Plan_Maestro_Barberia_Salones_Agenda_Apartados.pdf`) y marca qué está hecho y qué falta.
El modelo visual de referencia está en [docs/modelo-visual.png](docs/modelo-visual.png).

**Objetivo de la V1:** organizar citas, reducir no-shows, cobrar un apartado y darle al dueño visibilidad del negocio.
**Primer objetivo:** que una barbería o salón real use la V1.

| Símbolo | Significado |
|---|---|
| ✅ | Hecho, publicado y con pruebas automáticas |
| 🟡 | Parcial: hay una parte hecha y otra pendiente |
| ⬜ | Pendiente |
| ⏸️ | Aplazado por decisión |

---

## Resumen rápido

| # | Fase del Plan Maestro | Estado | En una línea |
|---|---|---|---|
| 0 | Preparación | ✅ | Flutter + Supabase + GitHub, con publicación automática |
| 1 | Base (datos + seguridad multi-negocio) | ✅ | Migraciones 001–013 aplicadas en Supabase real; RLS, límites por rol y pruebas SQL en CI |
| 2 | Autenticación y roles | ✅ | Registro con código, recuperar contraseña con código, invitar barberos con código |
| 3 | Negocio (perfil, horarios, configuración) | ✅ | Perfil, horario semanal, apartado configurable y enlace público |
| 4 | Servicios | ✅ | CRUD, catálogo de 20 servicios de salón, íconos y foto por servicio |
| 5 | Empleados | ✅ | CRUD, servicios por barbero, horario, días libres, invitación; el dueño puede atender ("Atiendo yo") |
| 6 | Clientes | ✅ | Ficha con historial, preferencias, faltas y favoritos |
| 7 | Agenda | ✅ | Crear/editar, "Atender ahora", cobro con método y propina, recordatorio por WhatsApp |
| 8 | Reserva pública | 🟡 | `#/reservar/<slug>` y "Mi cita" funcionando. Falta la **prueba de oro** con un cliente real |
| 9 | Apartado | ✅ | Transferencia + validación del dueño; vencen solas a las 3 h sin reporte. Tarjeta ⏸️ |
| 10 | Estados de la cita | ✅ | Transiciones validadas en el servidor; pagar confirma; cancelar libera el horario y el apartado |
| 11 | Reportes | ✅ | Por período y por barbero; descarga en **Excel** |
| 12 | QA | 🟡 | 143 pruebas Flutter + 6 archivos SQL en CI y revisión de seguridad. Falta probar en celulares reales |
| 13 | Lanzamiento | 🟡 | Publicada en https://barberia-pro.pages.dev. Falta dominio propio y primer negocio real |

**Avance de la V1:** 11 fases completas y 3 parciales. Lo que falta de la V1 es sobre todo **probar con un negocio real**.

---

## Cómo está montado (operación)

| Pieza | Dónde | Cómo se actualiza |
|---|---|---|
| App web (Flutter) | Cloudflare Pages: https://barberia-pro.pages.dev | Sola, tras cada push a `master` con CI en verde (`deploy-web.yml`) |
| Base de datos y Edge Functions | Supabase `ncieqndyjqwkgxrbqcee` | Sola, tras CI verde (`deploy-supabase.yml`: `db push` + `functions deploy`) |
| Pruebas | GitHub Actions (`ci.yml`) | En cada push: SQL en PostgreSQL, `flutter analyze` + `flutter test`, React |
| Correo (códigos e invitaciones) | SMTP de Gmail (contraseña de aplicación) | Configurado en Supabase → Emails |
| Fotos de servicios | Supabase Storage, bucket público `servicios` | Desde la app (solo el dueño) |
| Tareas programadas | `pg_cron`: vence reservas sin pago cada 15 min | Automático |

Secretos en GitHub: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_ACCESS_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`. Guía: [docs/PUBLICAR.md](docs/PUBLICAR.md).

---

## Decisión de arquitectura (a validar con el arquitecto)

El PDF propone **React + Supabase** como web app y deja la **app móvil nativa fuera de la V1**.
Se decidió usar **Flutter** para web, Android e iOS desde un solo código, manteniendo Supabase.
La app React queda solo como referencia (`src/`).

- La V1 es **web responsive e instalable (PWA)**: Flutter web cubre lo que pide el PDF.
- Android e iOS se publican después de validar con el primer negocio.
- Según la regla del PDF, **este cambio debe quedar aprobado por el arquitecto**. ⬜

---

## Detalle por fase

### 0. Preparación ✅
- ✅ Proyecto Flutter en `flutter_app/`, Supabase enlazado, repositorio con historial.
- ✅ Publicación automática de web, migraciones y funciones (ver "Cómo está montado").

### 1. Base: datos y seguridad ✅
- ✅ 001–005: esquema, RLS por negocio, FK compuestas, protección de perfiles, sin citas solapadas.
- ✅ 006: horarios del negocio y del barbero, días libres, servicios por barbero, apartado configurable, reglas de estados.
- ✅ 007 y 011: reserva pública por funciones seguras (sin abrir tablas a visitantes).
- ✅ 008: método de pago, propina y hora de cobro.
- ✅ 010: revisión de seguridad — límites del barbero, sin altas manuales de perfiles, tope y vencimiento de reservas públicas, zona horaria válida.
- ✅ 012–013: ícono y foto por servicio (Storage con permisos solo para el dueño).
- ⏸️ Tabla `pagos` del PDF: cuando se decida el cobro en línea.

### 2. Autenticación y roles ✅
- ✅ Registro del negocio con código por correo; recuperar contraseña con código.
- ✅ Invitar barberos: Edge Function `invitar-barbero`; el barbero activa su cuenta con un código.
- ✅ Permisos del barbero: solo sus citas, sus apartados y sus reportes (014, en la base); no valida apartados ni cambia precios (salvo al cobrar).
- ✅ **Decisión (28-oct):** los clientes son del negocio; todos los barberos pueden verlos y darles cita. Cada barbero solo ve el historial de las citas que atendió él.
- ⬜ Enlaces que abran la app nativa en Android/iOS (solo cuando existan las apps).

### 3. Negocio ✅
- ✅ Perfil, horario semanal, apartado (monto, política, datos de transferencia), anticipación para cancelar, intervalo de reservas.
- ✅ Enlace público para copiar.
- ⬜ Subir el **logo** del negocio como archivo (hoy es una dirección web).
- ⬜ Usar el **color principal** del negocio en la reserva pública.

### 4. Servicios ✅
- ✅ CRUD, "Visible en reservas", catálogo de 20 servicios de salón con precio del dueño.
- ✅ Íconos por servicio y **foto subida por el dueño** (ícono como respaldo).
- ✅ **Catálogo de barbería** (15 servicios) junto al de salón, con selector Barbería / Salón.
- ⬜ Elegir el tipo de negocio (barbería / salón / ambos) al registrarse para mostrar el catálogo correcto.

### 5. Empleados ✅
- ✅ CRUD, servicios por barbero, horario, días libres, invitación a la app.
- ✅ "Atiendo yo": el dueño se registra como barbero si trabaja solo.
- ⬜ Foto del barbero subida como archivo (la reserva ya la muestra si existe).

### 6. Clientes ✅
- ✅ Ficha con historial, preferencias, faltas (aviso a partir de 2) y favoritos.
- ⬜ Deuda técnica: el resumen de clientes se calcula en la app; pasarlo a la base si el volumen crece.

### 7. Agenda ✅
- ✅ Crear/editar, Completada con cobro (método y propina), Cancelar, "Atender ahora", WhatsApp.
- ✅ **Filtro por barbero** en la agenda del dueño (chips "Todos · Luis 4…").
- ⬜ Vista de semana.
- ⬜ Avisar al crear una cita fuera del horario o en un día libre del barbero.
- ⬜ **Actualización en vivo** (Supabase Realtime) y aviso cuando un barbero cobra o llega una reserva.

### 8. Reserva pública 🟡
- ✅ Pasos: servicio (con foto o ícono) → barbero → fecha y hora → datos → apartado → confirmación.
- ✅ "Mi cita": consultar, reprogramar, cancelar, reportar la transferencia, calendario y WhatsApp.
- ⬜ **Prueba de oro del PDF:** una persona que nunca usó el sistema reserva desde su celular sin ayuda.
- ⬜ Protección extra contra spam (captcha) si aparecen reservas falsas.

### 9. Apartado ✅ / ⏸️ cobro en línea
- ✅ Validar o rechazar pagos (solo el dueño); la cita pasa a Confirmada al validar.
- ✅ Vencen solas a las 3 h si el cliente no reporta la transferencia.
- ⏸️ Pago con tarjeta: cuando se elija un proveedor compatible con RD.

### 10. Estados de la cita ✅
- ✅ Transiciones validadas en el servidor; Cancelada es definitiva.

### 11. Reportes ✅
- ✅ Hoy, semana, mes, mes anterior y rango; por barbero, servicio, método de pago y clientes frecuentes.
- ✅ **Descarga en Excel** (.xlsx con 5 hojas). Los totales coinciden con la pantalla (prueba automática).
- ✅ Tarjeta **"Hoy por barbero"** en Inicio (cierre de caja rápido).
- ⬜ **Compartir resumen por WhatsApp** (día/semana/mes).
- ⬜ Resumen automático por correo (requiere dominio y un servicio como Resend).

### 12. QA 🟡
- ✅ 143 pruebas de Flutter, 6 archivos de pruebas SQL y revisión de seguridad.
- ✅ Probado en la web real: registro, recuperar contraseña, correo, servicios.
- ⬜ Probar en **celulares reales** (Android y iPhone) y en Safari.
- ⬜ Probar el flujo completo del barbero invitado con una cuenta real.
- ⬜ Probar la subida de fotos en el celular (cámara y galería).

### 13. Lanzamiento 🟡
- ✅ Web publicada e instalable (PWA), datos demo disponibles (`supabase/seed/`).
- ⬜ **Dominio propio** (p. ej. `reservas.tunegocio.com`) y pasar el correo a Resend.
- ⬜ **Primer negocio real** usando la app una semana → observar → corregir.
- ⬜ Guía corta para el dueño: configurar el negocio en minutos.
- ⬜ Procedimiento para reportar fallos.
- ⬜ Plan Pro de Supabase cuando haya clientes (el gratis pausa el proyecto si no se usa).
- ⬜ Después de validar: Android (Google Play) e iOS (App Store).

---

## Plan de pruebas del PDF — estado

| Prueba | Estado | Nota |
|---|---|---|
| Crear negocio | ✅ | Probado en la web real (STIKING) |
| Crear empleado | ✅ | Pantalla e invitación con código; falta probar la invitación con una cuenta real |
| Crear servicio | ✅ | Manual, desde el catálogo y con foto |
| Crear cliente | ✅ | Queda en el negocio correcto |
| Reservar horario | 🟡 | Funciona; falta la prueba de oro con un cliente real |
| Intentar doble reserva | ✅ | La base la rechaza y la app lo explica |
| Apartado | ✅ | Reportar, validar, rechazar y vencimiento automático |
| Cancelar | ✅ | Libera el horario y cancela el apartado pendiente |
| No-show | ✅ | Se marca, se cuenta y avisa en la ficha del cliente |
| Responsive | 🟡 | Probado en tamaño celular en pruebas; falta en teléfonos reales |
| Seguridad | ✅ | Pruebas SQL entre negocios y roles + revisión de seguridad |
| Reportes | ✅ | Totales probados contra las citas; también en Excel |

---

## Lo que falta, en orden

**A. Para que un negocio real lo use (prioridad máxima)**
1. Prueba de oro: un cliente reserva desde su celular sin ayuda.
2. Probar en celulares reales: dueño, barbero invitado y fotos.
3. ✅ Catálogo de barbería.
4. ✅ Filtro por barbero en la agenda y tarjeta "Hoy por barbero" en Inicio.

**B. Para el lanzamiento**
5. Dominio propio y correo con Resend.
6. Guía corta para el dueño y forma de reportar fallos.
7. Primer negocio real una semana → correcciones.

**C. Mejoras después del primer negocio (V1.1)**
8. Agenda en vivo y avisos (Realtime).
9. Compartir resumen por WhatsApp y resumen automático por correo.
10. Logo y fotos de barberos como archivo; color del negocio en la reserva.
11. Vista de semana y aviso de citas fuera de horario.

**D. Después**
12. Android e iOS.
13. Pago con tarjeta.

**Pendientes de seguridad del dueño de la cuenta**
- Rotar las claves que se compartieron por el chat: token `barberia-cli` de Supabase, token de Cloudflare y contraseña de aplicación de Gmail.

---

## Comparación con apps parecidas

Referencias: Booksy, Fresha, Vagaro, Square Appointments, AgendaPro, Setmore.

| Función | Ellos | Barbería PRO |
|---|---|---|
| Reserva en línea por enlace | ✅ | ✅ |
| Horario por barbero, días libres | ✅ | ✅ |
| Apartado / depósito | ✅ con tarjeta | ✅ transferencia (tarjeta ⏸️) |
| Recordatorios | ✅ automáticos | ✅ WhatsApp con un toque |
| Agregar al calendario | ✅ | ✅ |
| Clientes sin cita (walk-in) | ✅ | ✅ "Atender ahora" |
| Ficha del cliente, faltas | ✅ | ✅ |
| Método de pago y propina | ✅ | ✅ |
| Catálogo de servicios con fotos | ✅ | ✅ (salón; barbería ⬜) |
| Exportar reportes | ✅ | ✅ Excel |
| App instalable | ✅ nativas | ✅ PWA (nativas ⬜) |
| Agenda en tiempo real | ✅ | ⬜ V1.1 |
| Reseñas, lista de espera | ✅ | ⬜ V2+ |
| Comisiones, inventario, membresías | ✅ | ⬜ V3–V4 |

**Ventajas propias:** precios en RD$, apartado por transferencia (lo normal en RD), WhatsApp como
canal principal y simplicidad.

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
6. Todo cambio de tablas, RPC, índices, restricciones, RLS o Storage va en una migración versionada en `supabase/migrations/` con su prueba en `supabase/tests/`; se aplica sola tras el CI verde.
7. Comparar cada pantalla nueva con el modelo visual (`docs/modelo-visual.png`).
