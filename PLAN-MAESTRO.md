# Plan Maestro — Citabox (antes Barbería PRO; estado al 30-oct-2026)

Este documento sigue el orden del **Plan Maestro** en PDF
(`Plan_Maestro_Barberia_Salones_Agenda_Apartados.pdf`) y marca qué está hecho y qué falta.
El modelo visual de referencia está en [docs/modelo-visual.png](docs/modelo-visual.png).

**Objetivo de la V1:** organizar citas, reducir no-shows, cobrar un apartado y darle al dueño visibilidad del negocio.
**Primer objetivo:** que una barbería o salón real use la V1.
**Nombre (30-oct):** la app pasa a llamarse **Citabox** para servir a cualquier negocio con citas (barberías, salones, spas, consultorios…). Logo: calendario dorado con visto sobre negro. ✅ Nombre, logo e íconos en la app y la web. ✅ Tipo de negocio (barbería, salón, uñas, spa, consultorio, otro) al registrarse y en Configuración; la app y la reserva usan sus palabras (barbero, estilista, manicurista, terapeuta, profesional) (025). Plan intermedio renombrado a "Equipo". ✅ Dirección nueva `citabox.pages.dev`; la vieja redirige con la misma ruta. ⬜ Revisar la marca en ONAPI y el dominio `citabox.do` / `.app`.

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
| 1 | Base (datos + seguridad multi-negocio) | ✅ | Migraciones 001–017 en Supabase real; RLS, límites por rol, auditoría, consentimiento, suscripciones y pruebas SQL en CI |
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
| 12 | QA | 🟡 | 205 pruebas Flutter + 10 archivos SQL en CI y revisión de seguridad. Falta probar en celulares reales |
| 13 | Lanzamiento | 🟡 | Publicada en https://citabox.pages.dev (la dirección anterior redirige). Falta dominio propio y primer negocio real |

**Avance de la V1:** 11 fases completas y 3 parciales. Lo que falta de la V1 es sobre todo **probar con un negocio real**.

---

## Cómo está montado (operación)

| Pieza | Dónde | Cómo se actualiza |
|---|---|---|
| App web (Flutter) | Cloudflare Pages: https://citabox.pages.dev (barberia-pro.pages.dev redirige) | Sola, tras cada push a `master` con CI en verde (`deploy-web.yml`) |
| Base de datos y Edge Functions | Supabase `ncieqndyjqwkgxrbqcee` | Sola, tras CI verde (`deploy-supabase.yml`: `db push` + `functions deploy`) |
| Pruebas | GitHub Actions (`ci.yml`) | En cada push: SQL en PostgreSQL, `flutter analyze` + `flutter test`, React |
| Correo (códigos e invitaciones) | SMTP de Gmail (contraseña de aplicación) | Configurado en Supabase → Emails |
| Fotos de servicios | Supabase Storage, bucket público `servicios` | Desde la app (solo el dueño) |
| Tareas programadas | `pg_cron`: vence reservas sin pago cada 15 min | Automático |

Secretos en GitHub: `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_ACCESS_TOKEN`,
`CLOUDFLARE_ACCOUNT_ID`, `CLOUDFLARE_API_TOKEN`. Guía: [docs/PUBLICAR.md](docs/PUBLICAR.md).

---

## Decisión de arquitectura (aprobada)

El PDF propone **React + Supabase** como web app y deja la **app móvil nativa fuera de la V1**.
Se decidió usar **Flutter** para web, Android e iOS desde un solo código, manteniendo Supabase.
La app React queda solo como referencia (`src/`).

- La V1 es **web responsive e instalable (PWA)**: Flutter web cubre lo que pide el PDF.
- Android e iOS se publican después de validar con el primer negocio.
- ✅ Aprobado por el dueño del proyecto (31-oct-2026), que actúa como arquitecto: la regla del PDF queda cumplida.

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
- ✅ Logo y portada del negocio se suben como archivo (Configuración → Cambiar).
- ✅ El **color principal** del negocio se usa en su página de reservas (dorado si no eligió o si es demasiado claro).

### 4. Servicios ✅
- ✅ CRUD, "Visible en reservas", catálogo de 20 servicios de salón con precio del dueño.
- ✅ Íconos por servicio y **foto subida por el dueño** (ícono como respaldo).
- ✅ **Catálogo de barbería** (15 servicios) junto al de salón, con selector Barbería / Salón.
- ✅ Elegir el tipo de negocio al registrarse; el catálogo sugerido abre en el que le toca (025).

### 5. Empleados ✅
- ✅ CRUD, servicios por barbero, horario, días libres, invitación a la app.
- ✅ "Atiendo yo": el dueño se registra como barbero si trabaja solo.
- ✅ Foto de cada persona del equipo subida como archivo (ficha en Empleados); se ve en la lista y en la reserva.

### 6. Clientes ✅
- ✅ Ficha con historial, preferencias, faltas (aviso a partir de 2) y favoritos.
- ⬜ Deuda técnica: el resumen de clientes se calcula en la app; pasarlo a la base si el volumen crece.

### 7. Agenda ✅
- ✅ Crear/editar, Completada con cobro (método y propina), Cancelar, "Atender ahora", WhatsApp.
- ✅ **Filtro por barbero** en la agenda del dueño (chips "Todos · Luis 4…").
- ✅ Vista de semana (lunes a domingo, con total por día; tocar un día lo abre).
- ✅ Aviso al crear o editar una cita fuera del horario del negocio, del horario de quien atiende o en su día libre (solo avisa, se puede guardar).
- ✅ **Actualización en vivo** (Supabase Realtime): avisos de reservas, cancelaciones y pagos reportados, con contador (021).

### 8. Reserva pública 🟡
- ✅ Pasos: servicio (con foto o ícono) → barbero → fecha y hora → datos → apartado → confirmación.
- ✅ "Mi cita": consultar, reprogramar, cancelar, reportar la transferencia, calendario y WhatsApp.
- ⬜ **Prueba de oro del PDF:** una persona que nunca usó el sistema reserva desde su celular sin ayuda.
- ⏸️ Captcha: decisión (30-oct) de no ponerlo por ahora para no frenar al cliente; basta con los límites (3 citas por teléfono, freno de reservas en masa, vencimiento de apartados). Turnstile invisible solo si aparecen reservas falsas.

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
- ✅ **Compartir resumen por WhatsApp** del período elegido (ingresos, citas, métodos de pago, equipo y servicio más pedido).
- ⬜ Resumen automático por correo (requiere dominio y un servicio como Resend).

### 12. QA 🟡
- ✅ 205 pruebas de Flutter, 10 archivos de pruebas SQL y revisión de seguridad.
- ✅ Probado en la web real: registro, recuperar contraseña, correo, servicios.
- ⬜ Probar en **celulares reales** (Android y iPhone) y en Safari.
- ⬜ Probar el flujo completo del barbero invitado con una cuenta real.
- ⬜ Probar la subida de fotos en el celular (cámara y galería).

### 13. Lanzamiento 🟡
- ✅ Web publicada e instalable (PWA), datos demo disponibles (`supabase/seed/`).
- ⬜ **Dominio propio** (p. ej. `reservas.tunegocio.com`) y pasar el correo a Resend.
- ⬜ **Primer negocio real** usando la app una semana → observar → corregir.
- ✅ Guía corta para el dueño: [docs/GUIA-DUENO.md](docs/GUIA-DUENO.md).
- ✅ Procedimiento ante fallos (gravedad, arreglo, deshacer publicación, aviso a negocios): [docs/REPORTAR-FALLOS.md](docs/REPORTAR-FALLOS.md).
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

## Verificación del 29-oct-2026 (5 agentes: competencia, RD, seguridad BD, seguridad app, producto)

### Seguridad — lo primero
**Resultado:** ningún hallazgo crítico. No hay fugas entre negocios ni forma de que un barbero se haga dueño.

| Hallazgo | Estado |
|---|---|
| El barbero podía deshacer una cita cobrada y cambiar precio/propina | ✅ Corregido (015) |
| No había registro de quién cambió o borró qué | ✅ Tabla `auditoria` (015), solo la lee el dueño |
| Reservas falsas con "pago reportado" nunca vencían | ✅ Vencen a las 24 h sin validar (015) |
| Mensajes que revelaban si un teléfono tenía citas o estaba bloqueado | ✅ Mensaje único (015) |
| El barbero podía desactivar clientes; el dueño podía borrar su perfil | ✅ Bloqueado (015) |
| Logo/portada aceptaban cualquier texto | ✅ Solo `https://` (015) |
| `TRUNCATE` concedido a los roles de la API | ✅ Retirado (015) |
| Web sin CSP, HSTS ni COOP | ✅ Publicadas en `_headers` |
| Función de invitar aceptaba cualquier origen | ✅ Solo `citabox.pages.dev` |
| CI sin permisos mínimos ni versión fija de Flutter | ✅ Corregido |
| Supabase aceptaba contraseñas de 6 | ✅ Mínimo 8 |
| **Sin CAPTCHA** en registro y reserva pública | ⏸️ Pospuesto (30-oct): cubren los límites por teléfono y el vencimiento; Turnstile invisible si aparecen reservas falsas |
| Sin 2FA para dueños | ✅ Verificación en dos pasos opcional (Configuración → Seguridad) |
| **Sin copias de seguridad utilizables** (plan gratis) | 🟡 Workflow semanal cifrado listo (`respaldo-db.yml`, falta crear 2 secretos); falta Supabase Pro y ensayo de restauración |
| Contraseñas filtradas (HaveIBeenPwned), caducidad de sesión | ⬜ Requieren Supabase Pro |
| Límite de invitaciones por negocio y día | ✅ 10 por día |
| Aprobación manual para aplicar migraciones a producción | ⬜ Entorno con revisor en GitHub |
| Configuración de Supabase sin versionar (`config.toml`) | ⬜ |
| Rotar claves compartidas por el chat (Supabase, Cloudflare, Gmail) | ⬜ El dueño de la cuenta |

### Mercado (resumen)
- Internacionales: **USD 20–50/mes por negocio**; Booksy y Fresha además cobran comisión por cliente nuevo.
- Latinoamérica: el rival real es **AgendaPro** (desde ~USD 8/mes, 50 recordatorios WhatsApp incluidos).
- **En RD no se encontró software local** para barberías/salones: el competidor real es la libreta y el WhatsApp a mano.
- Pagos en RD: Stripe no parece operar; **Azul / CardNET** son la vía local. Seguir con transferencia como base.
- **Ley 172-13** (datos personales): consentimiento, política de privacidad y derecho a borrar/exportar datos.
- **e-CF (DGII):** la obligación es del negocio, no de la app; plazo para pequeños según fuentes: 15-nov-2026 (confirmar con contador).

### Modelo de precios propuesto (validar con dueños dominicanos)
- Plan **por negocio**, no por barbero: **Solo** (1 barbero) · **Barbería** (hasta ~5, recordatorios y comisiones) · **Pro** (varias sedes, reseñas, marketing).
- Prueba gratis de 14–30 días sin tarjeta; precio congelado para los 10 primeros; anual con 2 meses de regalo.
- **Sin comisión por cita** (ventaja frente a Booksy/Fresha). Cobrar aparte los mensajes de WhatsApp automáticos.

---

## Lo que falta, en orden

**A. Antes de cobrar al primer negocio**
1. Prueba de oro y pruebas en celulares reales (dueño, barbero invitado, fotos).
2. 🟡 **Legal:** ✅ términos, privacidad, consentimiento al reservar y registrar, exportar/anonimizar cliente (016). ⬜ Revisión de un abogado.
3. ✅ **Cobro del servicio:** planes (Solo RD$400, Barbería RD$900, Pro RD$1,600), prueba de 30 días, pausa con 7 días de gracia, límite de barberos, panel `#/admin` (admin: humanogestion@gmail.com), cuentas para cobrar, botón "Ya pagué" con recibo y aviso por WhatsApp (017–019). Sin pasarela por ahora (no hay RNC): transferencia.
4. ⬜ **Supabase Pro** (copias diarias de 7 días, no se pausa). Decisión (29-oct): el respaldo semanal externo queda listo pero sin activar; se activa creando sus 2 secretos si hiciera falta (`docs/RESPALDOS.md`).
5. **Dominio propio** + correo con **Resend** (SPF/DKIM).
6. 🟡 ✅ 2FA para dueños. ⏸️ CAPTCHA pospuesto: solo si aparecen reservas falsas.
7. ✅ Botón "Reportar un problema" y monitoreo de errores con **Sentry** (org `barberia-pro`, sin datos personales).
8. ✅ Enlace `/r/<slug>` con vista previa (nombre y portada) en WhatsApp.
9. **Rendimiento** en celulares de gama baja (primera carga de Flutter web).
10. ✅ Tarjeta "Configura tu negocio" con los primeros pasos en Inicio.

**B. Primeros 3 meses (lo que más pagan los dueños)**
11. 🟡 **Recordatorios por WhatsApp**: ✅ por defecto los envía el dueño o el barbero desde la Agenda (botón de WhatsApp). ✅ El envío automático es un **servicio adicional**: el admin lo activa por negocio en `#/admin` con cupo, precio al mes y precio por extra (022–023); el dueño elige las horas y ve su uso. ⬜ Decisión (30-oct): se activa más adelante, cuando haya varios clientes. Entonces: cuenta de Meta, plantilla `recordatorio_cita`, secretos y programar el envío con pg_cron (`supabase/functions/README.md`).
12. ✅ **Comisiones por barbero**: % en Empleados; comisión y total a pagar en Reportes y Excel (020).
13. ✅ **Avisos en vivo** de reservas, cancelaciones y pagos reportados, con contador en la Agenda (021). ⬜ Push y correo.
14. ✅ **Historial de cambios** para el dueño (Configuración → Historial de cambios).
15. ✅ Métricas de uso en `#/admin` (resumen de la plataforma; por negocio: último acceso, citas en línea, clientes y última cita) (026). ⬜ Transferir el negocio a otro dueño; correos de bienvenida y fin de prueba (requieren dominio).

**C. Diferenciadores después**
16. Reseñas, lista de espera y fidelización ("la décima gratis"). ✅ Cumpleaños del cliente: día y mes en su ficha, filtro "Cumpleaños del mes" y felicitación por WhatsApp (027). ✅ Clientes que no vuelven (45 días sin venir y sin cita): filtro en Clientes con invitación por WhatsApp y enlace de reservas.
17. ✅ Vista de semana, foto del equipo como archivo y color del negocio en la reserva.
18. Pago con tarjeta del apartado (Azul/CardNET); comprobantes e-CF vía proveedor certificado.

**D. Más adelante**
19. Apps nativas, multi-sucursal, inventario, marketplace.

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
| Catálogo de servicios con fotos | ✅ | ✅ foto por servicio (013) e íconos en los catálogos sugeridos |
| Exportar reportes | ✅ | ✅ Excel |
| App instalable | ✅ nativas | ✅ PWA (nativas ⬜) |
| Agenda en tiempo real | ✅ | ✅ avisos en vivo (021) |
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
