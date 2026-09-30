# Plan de Barbería PRO: Web, Android e iOS

## Decisión de arquitectura

Usar Flutter como cliente para Android, iOS y web, manteniendo Supabase como backend y conservando el esquema/RLS existente. La app React se mantiene temporalmente como referencia durante la migración; no se elimina ni se desarrollan nuevos módulos allí.

## Estado de partida

- Aplicación React 18 y Vite conservada como referencia.
- Supabase para autenticación y datos; la clave pública usa `VITE_SUPABASE_PUBLISHABLE_KEY`.
- Auth y CRUD de clientes, servicios y empleados existentes en React.
- Agenda, dashboard, reportes, configuración y reserva pública siguen incompletos en React.
- Documentación existente de las fases 2.1 y 2.3, y adaptación de la clave de Supabase.
- Línea base comprobada: `npm run lint` pasa y `npm run build` genera producción.
- ESLint 9 usa flat config y omite `dist/`, `_backups/` y `flutter_app/`.
- Proyecto Flutter generado en `flutter_app/` para Android, iOS y web; `supabase_flutter` añadido.
- Login, restauración de sesión, carga de perfil y navegación adaptable implementados. `flutter analyze`, `flutter test` (18 pruebas) y `flutter build web` pasan.
- Clientes implementado en Flutter: búsqueda, alta, edición y cambio de estado, con consultas siempre filtradas por `negocio_id`.
- Registro del negocio implementado en Flutter: crea la cuenta y guarda los datos del negocio en `user_metadata.registro_pendiente` (sin contraseña); al haber sesión sin perfil, el panel llama a `bootstrap_negocio_owner` automáticamente o muestra el formulario para completarlo. Funciona aunque el correo se confirme en otro dispositivo.
- Diseño alineado con el modelo visual (negro, dorado y blanco): login con marca, menú lateral oscuro (cajón en móvil) con opciones según rol, panel del dueño con indicadores del día (citas, llegaron, no-show, ventas) y agenda de hoy, agenda por día con botones Llegó/No vino ("Mi agenda" para barberos, filtrada por `empleados.perfil_id`), y Clientes con visitas, gasto acumulado y etiqueta Frecuente (10+ visitas atendidas). Servicios, Empleados, Reportes y Configuración aparecen como "Próximamente".
- El resumen de clientes se calcula en el cliente paginando citas atendidas; si el volumen crece, moverlo a una vista o RPC con migración.
- Edge está disponible para Flutter web. Falta Android SDK en este equipo; iOS requiere macOS/Xcode.

## Fases

### 0. Base Flutter y autenticación

- Inicializar Supabase con URL y publishable key fuera del código fuente.
- Portar login, restauración de sesión y consulta de perfil/negocio.
- Portar registro de negocio manteniendo `bootstrap_negocio_owner` y confirmación de correo.
- Mantener RLS como autoridad y no incluir claves secretas en el cliente.
- Registro/bootstrap del negocio portado. Pendiente: recuperación de contraseña y probar el flujo con una cuenta real (con y sin confirmación de correo).

**Salida:** app Flutter web autenticable, con sesión persistente y acceso condicionado a un perfil activo.

### 1. Módulos del negocio

- Clientes ya está implementado; no muestra aún visitas ni gasto acumulado porque se calcularán después desde las citas.
- Portar servicios y empleados como pantallas adaptables.
- Completar dashboard, agenda, reportes y configuración.
- Mantener permisos `OWNER`/`EMPLOYEE` y aislamiento multi-negocio.

**Salida:** flujo administrativo principal validado en web y móvil.

### 2. Reserva pública

- Implementar reserva por slug, consulta de disponibilidad y creación de citas.
- Impedir reservas simultáneas también en backend.
- Probar enlaces públicos en navegador y teléfono.

**Salida:** clientes pueden reservar sin entrar al panel privado.

**Pagos:** aplazados. No integrar Stripe ni marcar apartados como pagados desde el cliente hasta elegir un proveedor compatible y diseñar su confirmación segura en backend.

### 3. Web

- Completar diseño adaptable, rutas web, metadatos e instalación/PWA si aporta valor.
- Publicar y probar en Edge, Chrome y Safari.

**Salida:** versión web de producción con panel y reserva pública.

### 4. Android

- Configurar firma, permisos mínimos y canales de distribución de prueba.
- Probar en dispositivos físicos y emuladores, incluidos teclado, rotación, conectividad y reanudación de la app.
- Preparar ficha, capturas, política de privacidad y publicación gradual.

**Salida:** versión candidata validada y preparada para Google Play.

### 5. iOS

- Configurar firma, identificadores y capacidades de Apple.
- Probar en iPhone/iPad y revisar enlaces de autenticación, teclado, área segura y suspensión/reanudación.
- Distribuir por TestFlight y preparar ficha, capturas y política de privacidad.

**Requisito:** la compilación y firma final de iOS requieren macOS con Xcode y una cuenta de desarrollador de Apple.

**Salida:** versión candidata validada por TestFlight y preparada para App Store.

### 6. Publicación y mantenimiento

- Publicar web, Play Store y App Store con versiones coordinadas.
- Vigilar errores, autenticación, reservas y rendimiento.
- Mantener dependencias, plugins, permisos y políticas de privacidad actualizados.

## Forma de trabajo

1. Abordar una fase y un flujo concreto cada vez.
2. Antes de editar, confirmar el comportamiento actual y el criterio de aceptación.
3. Hacer el cambio mínimo coherente con la arquitectura existente.
4. Ejecutar la comprobación más cercana al cambio y luego el gate de la fase.
5. No marcar una fase como terminada solo porque compile: validar el flujo en navegador y, cuando corresponda, en dispositivos.
6. Todo cambio de tablas, RPC, índices, restricciones o RLS debe añadirse como migración SQL versionada en `supabase/migrations/` y validarse antes de que Flutter dependa de él. Los cambios de interfaz que usan el esquema actual no requieren una migración nueva.

## Siguiente paso

Probar registro, panel y agenda con una cuenta real de Supabase; después portar Servicios y Empleados (necesarios para crear citas) y luego la reserva pública del modelo (link público, reservar, confirmación y "Mi cita"). Mantener pagos fuera de alcance por ahora.