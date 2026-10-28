import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/models/cliente.dart';
import 'package:barberiapro/pages/agenda_page.dart';
import 'package:barberiapro/services/agenda_repository.dart';
import 'package:barberiapro/services/citas_repository.dart';
import 'package:barberiapro/services/sin_permiso.dart';
import 'package:barberiapro/utils/citas_reglas.dart';

void main() {
  test('hora_fin is the start plus the service duration', () {
    expect(calcularHoraFin('10:00', 45), '10:45:00');
    expect(calcularHoraFin('9:30', 30), '10:00:00');
    expect(calcularHoraFin('14:30:00', 90), '16:00:00');
    // No puede pasar de medianoche (hora_fin > hora_inicio en la base).
    expect(calcularHoraFin('23:30', 45), isNull);
    expect(calcularHoraFin('25:00', 30), isNull);
    expect(calcularHoraFin('10:5', 30), isNull);
    expect(calcularHoraFin('abc', 30), isNull);
  });

  test('Postgres errors become clear messages', () {
    expect(
      mensajeErrorCita(const PostgrestException(message: 'x', code: '23P01')),
      'Ese barbero ya tiene una cita en ese horario.',
    );
    expect(
      mensajeErrorCita(
        const PostgrestException(
          message: 'No se puede pasar una cita de COMPLETADA a PENDIENTE.',
          code: '23514',
        ),
      ),
      'Ese cambio de estado no está permitido.',
    );
    // Otros check: precio negativo, hora_fin <= hora_inicio...
    expect(
      mensajeErrorCita(
        const PostgrestException(
          message:
              'new row for relation "citas" violates check constraint '
              '"citas_precio_check"',
          code: '23514',
        ),
      ),
      'Revisa el precio y el horario de la cita.',
    );
    expect(
      mensajeErrorCita(Exception('sin red'), porDefecto: 'Falló.'),
      'Falló.',
    );
  });

  test('42501 uses the Spanish server message or a generic one', () {
    for (final mensaje in [
      'Solo puedes modificar tus propias citas.',
      'Solo puedes crear citas en tu propia agenda.',
      'Solo el dueño puede cambiar el precio de una cita.',
      'No se puede cambiar este dato de la cita.',
    ]) {
      expect(
        mensajeErrorCita(PostgrestException(message: mensaje, code: '42501')),
        mensaje,
      );
    }
    expect(
      mensajeErrorCita(
        const PostgrestException(
          message:
              'new row violates row-level security policy for table '
              '"citas"',
          code: '42501',
        ),
      ),
      'No tienes permiso para esta acción.',
    );
    expect(
      mensajeErrorCita(
        const PostgrestException(
          message: 'permission denied for table citas',
          code: '42501',
        ),
      ),
      'No tienes permiso para esta acción.',
    );
    expect(
      mensajeErrorCita(const SinPermisoException()),
      'No tienes permiso o el registro ya no existe.',
    );
  });

  testWidgets('a stale day response does not overwrite the newer one', (
    tester,
  ) async {
    final citas = _CitasControladas();
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaPage(
            negocioId: 'n1',
            repository: citas,
            agendaRepository: _FakeAgenda(),
            fechaInicial: DateTime(2026, 9, 18),
          ),
        ),
      ),
    );
    citas.responder(DateTime(2026, 9, 18), const []);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Día siguiente'));
    await tester.pump();
    await tester.tap(find.byTooltip('Día siguiente'));
    await tester.pump();
    expect(citas.pedidas, [
      DateTime(2026, 9, 18),
      DateTime(2026, 9, 19),
      DateTime(2026, 9, 20),
    ]);

    // Llega primero la respuesta del 20 y después la (vieja) del 19.
    citas.responder(DateTime(2026, 9, 20), [
      _cita('c20', EstadoCita.pendiente, cliente: 'Cliente del 20'),
    ]);
    await tester.pump();
    citas.responder(DateTime(2026, 9, 19), [
      _cita('c19', EstadoCita.pendiente, cliente: 'Cliente del 19'),
    ]);
    await tester.pumpAndSettle();

    expect(find.text('Cliente del 20'), findsOneWidget);
    expect(find.text('Cliente del 19'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('moving days keeps local midnight across DST changes', (
    tester,
  ) async {
    final citas = _FakeCitas([]);
    tester.view.physicalSize = const Size(1280, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final pedidas = <DateTime>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgendaPage(
            negocioId: 'n1',
            repository: _Registro(citas, pedidas),
            agendaRepository: _FakeAgenda(),
            // Cambios de horario de EE. UU. y Europa.
            fechaInicial: DateTime(2026, 3, 7),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (var i = 0; i < 25; i++) {
      await tester.tap(find.byTooltip('Día siguiente'));
      await tester.pumpAndSettle();
    }
    for (final fecha in pedidas) {
      expect((fecha.hour, fecha.minute), (0, 0));
    }
    expect(pedidas.last, DateTime(2026, 4, 1));

    await tester.tap(find.byTooltip('Día anterior'));
    await tester.pumpAndSettle();
    expect(pedidas.last, DateTime(2026, 3, 31));
  });

  test('state transitions mirror 006 rules', () {
    expect(EstadoCita.llego.deshacer, EstadoCita.pendiente);
    expect(EstadoCita.noVino.deshacer, EstadoCita.pendiente);
    expect(EstadoCita.completada.deshacer, EstadoCita.llego);
    expect(EstadoCita.pendiente.deshacer, isNull);
    expect(EstadoCita.llego.puedePasarA(EstadoCita.completada), isTrue);
    expect(EstadoCita.llego.puedePasarA(EstadoCita.noVino), isFalse);
    expect(EstadoCita.noVino.puedePasarA(EstadoCita.llego), isFalse);
    expect(EstadoCita.completada.puedePasarA(EstadoCita.pendiente), isFalse);
    for (final estado in EstadoCita.values) {
      if (estado == EstadoCita.cancelada) continue;
      expect(EstadoCita.cancelada.puedePasarA(estado), isFalse);
    }
  });

  testWidgets('owner creates an appointment with filtered barbers', (
    tester,
  ) async {
    final citas = _FakeCitas([]);
    final agenda = _FakeAgenda();
    await _abrirAgenda(tester, citas, agenda);

    await tester.tap(find.text('Nueva cita'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar cliente'),
      'ana',
    );
    await tester.pumpAndSettle();
    expect(find.text('Pedro Gómez'), findsNothing);
    await tester.tap(find.text('Ana López'));
    await tester.pumpAndSettle();

    await _elegir(tester, 'Servicio', 'Barba · 20 min');
    // Luis solo hace cortes (empleado_servicios); no se ofrece para barba.
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Barbero'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Luis'), findsNothing);
    await tester.tap(find.text('Miguel').last);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hora de inicio'),
      '10:00',
    );
    await tester.pumpAndSettle();
    expect(find.text('Termina a las 10:20 AM'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Precio'), '300');
    await tester.tap(find.text('Guardar cita'));
    await tester.pumpAndSettle();

    final datos = agenda.creadas.single;
    expect(datos.clienteId, 'cl1');
    expect(datos.servicioId, 's2');
    expect(datos.empleadoId, 'b2');
    expect(datos.horaInicio, '10:00:00');
    expect(datos.horaFin, '10:20:00');
    expect(datos.precio, 300);
    expect(datos.toMap()['fecha'], '2026-09-18');
    expect(find.text('Cita creada.'), findsOneWidget);
  });

  testWidgets('barber agenda fixes the barber, adds a quick client and '
      'explains overlaps', (tester) async {
    final citas = _FakeCitas([]);
    final agenda = _FakeAgenda(
      errorAlCrear: const PostgrestException(message: 'x', code: '23P01'),
    );
    await _abrirAgenda(tester, citas, agenda, empleadoId: 'b1');

    await tester.tap(find.text('Nueva cita'));
    await tester.pumpAndSettle();

    // El barbero no se elige: es el usuario.
    expect(find.text('Luis'), findsOneWidget);
    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Barbero'),
      findsNothing,
    );

    await tester.tap(find.text('Nuevo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre del cliente'),
      'Rafael Núñez',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Teléfono'),
      '809-555-0000',
    );

    // Luis solo hace "Corte".
    await tester.tap(
      find.widgetWithText(DropdownButtonFormField<String>, 'Servicio'),
    );
    await tester.pumpAndSettle();
    expect(find.text('Barba · 20 min'), findsNothing);
    await tester.tap(find.text('Corte · 45 min').last);
    await tester.pumpAndSettle();
    expect(find.text('500'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hora de inicio'),
      '11:00',
    );
    await tester.tap(find.text('Guardar cita'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ese barbero ya tiene una cita en ese horario.'),
      findsOneWidget,
    );
    expect(agenda.clientesCreados, ['Rafael Núñez|809-555-0000']);

    // Reintentar no vuelve a crear el cliente.
    await tester.tap(find.text('Guardar cita'));
    await tester.pumpAndSettle();
    expect(agenda.clientesCreados, hasLength(1));
    expect(agenda.intentos.last.empleadoId, 'b1');
    expect(agenda.intentos.last.horaFin, '11:45:00');
  });

  testWidgets('completing records the final price and can be undone', (
    tester,
  ) async {
    final citas = _FakeCitas([_cita('c1', EstadoCita.llego)]);
    final agenda = _FakeAgenda();
    await _abrirAgenda(tester, citas, agenda);

    expect(find.text('10:45 AM'), findsOneWidget);
    // Desde Llegó no se puede pasar a No vino.
    expect(_habilitado(tester, 'No vino'), isFalse);

    await tester.tap(find.text('Completada'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Precio final cobrado'),
      '650',
    );
    await tester.tap(find.text('Completar'));
    await tester.pumpAndSettle();

    // Por defecto: efectivo y sin propina.
    expect(agenda.completadas, [('c1', 650, MetodoPago.efectivo, 0)]);
    expect(find.textContaining(r'RD$650'), findsOneWidget);

    // Deshacer una completada vuelve a Llegó, no a Pendiente.
    await tester.tap(find.text('Completada'));
    await tester.pumpAndSettle();
    expect(citas.cambios.last, ('c1', EstadoCita.llego));
  });

  testWidgets('completing asks for payment method and tip, and undoing '
      'keeps the payment', (tester) async {
    final citas = _FakeCitas([_cita('c1', EstadoCita.llego)]);
    final agenda = _FakeAgenda();
    await _abrirAgenda(tester, citas, agenda);

    await tester.tap(find.text('Completada'));
    await tester.pumpAndSettle();
    for (final metodo in ['Efectivo', 'Transferencia', 'Tarjeta', 'Otro']) {
      expect(find.widgetWithText(ChoiceChip, metodo), findsOneWidget);
    }
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Efectivo'))
          .selected,
      isTrue,
    );

    await tester.tap(find.text('Tarjeta'));
    final propina = find.widgetWithText(TextField, 'Propina (opcional)');
    await tester.enterText(propina, '-5');
    await tester.tap(find.text('Completar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Escribe una propina válida (o déjala vacía).'),
      findsOneWidget,
    );
    expect(agenda.completadas, isEmpty);

    await tester.enterText(propina, '100');
    await tester.tap(find.text('Completar'));
    await tester.pumpAndSettle();
    expect(agenda.completadas, [('c1', 500, MetodoPago.tarjeta, 100)]);

    // Deshacer no borra el cobro: solo cambia el estado.
    await tester.tap(find.text('Completada'));
    await tester.pumpAndSettle();
    expect(citas.cambios, [('c1', EstadoCita.llego)]);

    await tester.tap(find.text('Ana López'));
    await tester.pumpAndSettle();
    expect(find.text('Tarjeta'), findsOneWidget);
    expect(find.text(r'RD$100'), findsOneWidget);
  });

  testWidgets('"Atender ahora" only shows today and creates an arrived '
      'appointment for a walk-in client', (tester) async {
    final citas = _FakeCitas([]);
    final agenda = _FakeAgenda();
    await _abrirAgenda(
      tester,
      citas,
      agenda,
      reloj: () => DateTime(2026, 9, 18, 14, 37),
    );

    expect(find.text('Atender ahora'), findsOneWidget);
    await tester.tap(find.byTooltip('Día siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Atender ahora'), findsNothing);
    await tester.tap(find.text('Hoy'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Atender ahora'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cliente sin registrar'));
    await tester.pumpAndSettle();
    expect(find.text('Cliente de paso'), findsOneWidget);

    await _elegir(tester, 'Servicio', r'Barba · 20 min · RD$250');
    await _elegir(tester, 'Barbero', 'Miguel');
    expect(find.text('De 2:35 PM a 2:55 PM'), findsOneWidget);

    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();

    expect(agenda.pedidosDePaso, 1);
    final (datos, estado) = agenda.creadasConEstado.single;
    expect(estado, EstadoCita.llego);
    expect(datos.clienteId, 'paso');
    expect(datos.empleadoId, 'b2');
    expect(datos.servicioId, 's2');
    expect(datos.toMap()['fecha'], '2026-09-18');
    expect(datos.horaInicio, '14:35:00');
    expect(datos.horaFin, '14:55:00');
    expect(datos.precio, 250);
    expect(find.text('Cliente en atención.'), findsOneWidget);
  });

  testWidgets('"Atender ahora" offers to start when the barber finishes', (
    tester,
  ) async {
    // Luis está ocupado de 14:00 a 14:45 y otra vez de 14:45 a 15:00.
    final citas = _FakeCitas([
      _cita('c1', EstadoCita.llego, inicio: '14:00:00', fin: '14:45:00'),
      _cita('c2', EstadoCita.confirmada, inicio: '14:45:00', fin: '15:00:00'),
      _cita('c3', EstadoCita.cancelada, inicio: '15:00:00', fin: '15:45:00'),
    ]);
    final agenda = _FakeAgenda(
      errorAlCrear: const PostgrestException(message: 'x', code: '23P01'),
      fallosAlCrear: 1,
    );
    await _abrirAgenda(
      tester,
      citas,
      agenda,
      empleadoId: 'b1',
      reloj: () => DateTime(2026, 9, 18, 14, 22),
    );

    await tester.tap(find.text('Atender ahora'));
    await tester.pumpAndSettle();
    // En "Mi agenda" el barbero es fijo.
    expect(
      find.widgetWithText(DropdownButtonFormField<String>, 'Barbero'),
      findsNothing,
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Buscar cliente'),
      'pedro',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pedro Gómez'));
    await tester.pumpAndSettle();
    await _elegir(tester, 'Servicio', r'Corte · 45 min · RD$500');

    await tester.tap(find.text('Empezar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Ese barbero ya tiene una cita en ese horario.'),
      findsOneWidget,
    );
    expect(agenda.intentos.single.horaInicio, '14:20:00');

    // La cancelada no ocupa: la siguiente hora libre es las 3:00 PM.
    await tester.tap(find.text('Empezar a las 3:00 PM, al terminar su cita'));
    await tester.pumpAndSettle();

    final (datos, estado) = agenda.creadasConEstado.single;
    expect(estado, EstadoCita.llego);
    expect(datos.clienteId, 'cl2');
    expect(datos.empleadoId, 'b1');
    expect(datos.horaInicio, '15:00:00');
    expect(datos.horaFin, '15:45:00');
    expect(find.text('Cliente en atención.'), findsOneWidget);
  });

  testWidgets('WhatsApp reminder opens a ready message, or is disabled '
      'without phone', (tester) async {
    final abiertos = <Uri>[];
    final citas = _FakeCitas([
      _cita('c1', EstadoCita.confirmada),
      _cita(
        'c2',
        EstadoCita.pendiente,
        inicio: '11:00:00',
        fin: '11:45:00',
        cliente: 'Pedro Gómez',
        telefono: '',
      ),
      _cita('c3', EstadoCita.llego, inicio: '12:00:00', fin: '12:45:00'),
    ]);
    await _abrirAgenda(
      tester,
      citas,
      _FakeAgenda(),
      negocioNombre: 'Barbería Central',
      abrirEnlace: (uri) async {
        abiertos.add(uri);
        return true;
      },
    );

    await tester.tap(find.byTooltip('Más acciones').at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Recordar por WhatsApp'));
    await tester.pumpAndSettle();

    final enlace = abiertos.single;
    expect(enlace.host, 'wa.me');
    expect(enlace.path, '/18095551111');
    expect(
      enlace.queryParameters['text'],
      'Hola Ana López, te recordamos tu cita en Barbería Central el viernes '
      '18 de septiembre a las 10:00 AM para Corte con Luis. ¡Te esperamos!',
    );

    // Sin teléfono: aparece deshabilitada y explica por qué.
    await tester.tap(find.byTooltip('Más acciones').at(1));
    await tester.pumpAndSettle();
    expect(
      find.text('El cliente no tiene teléfono registrado.'),
      findsOneWidget,
    );
    final item = tester.widget<PopupMenuItem<Object?>>(
      find.ancestor(
        of: find.text('Recordar por WhatsApp'),
        matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
      ),
    );
    expect(item.enabled, isFalse);
    await tester.tap(find.text('Recordar por WhatsApp'));
    await tester.pumpAndSettle();
    expect(abiertos, hasLength(1));
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    // Una cita que ya llegó no ofrece recordatorio.
    await tester.tap(find.byTooltip('Más acciones').at(2));
    await tester.pumpAndSettle();
    expect(find.text('Recordar por WhatsApp'), findsNothing);
  });

  testWidgets('cancelling asks for confirmation and locks the appointment', (
    tester,
  ) async {
    final citas = _FakeCitas([_cita('c1', EstadoCita.pendiente)]);
    await _abrirAgenda(tester, citas, _FakeAgenda());

    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar cita'));
    await tester.pumpAndSettle();
    expect(find.text('¿Cancelar la cita?'), findsOneWidget);

    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(citas.cambios, isEmpty);

    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar cita'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar cita').last);
    await tester.pumpAndSettle();

    expect(citas.cambios, [('c1', EstadoCita.cancelada)]);
    expect(find.text('Cancelada'), findsOneWidget);
    expect(find.text('Llegó'), findsNothing);

    await tester.tap(find.byTooltip('Más acciones'));
    await tester.pumpAndSettle();
    expect(find.text('Ver detalle'), findsOneWidget);
    expect(find.text('Editar'), findsNothing);
    expect(find.text('Cancelar cita'), findsNothing);
  });

  testWidgets('rejected state changes show a clear message', (tester) async {
    final citas = _FakeCitas(
      [_cita('c1', EstadoCita.pendiente)],
      error: const PostgrestException(
        message: 'No se puede pasar una cita de PENDIENTE a LLEGO.',
        code: '23514',
      ),
    );
    await _abrirAgenda(tester, citas, _FakeAgenda());

    await tester.tap(find.text('Llegó'));
    await tester.pumpAndSettle();

    expect(
      find.text('Ese cambio de estado no está permitido.'),
      findsOneWidget,
    );
  });

  testWidgets('detail shows notes and deposit, and edits the appointment', (
    tester,
  ) async {
    final citas = _FakeCitas([_cita('c1', EstadoCita.pendiente)]);
    final agenda = _FakeAgenda(
      apartado: const ApartadoCita(
        monto: 100,
        estado: 'PAGADO',
        metodoPago: 'Transferencia',
      ),
    );
    await _abrirAgenda(tester, citas, agenda);

    await tester.tap(find.text('Ana López'));
    await tester.pumpAndSettle();
    expect(find.text('Trae su propia navaja'), findsOneWidget);
    expect(find.text(r'RD$100 · Pagado · Transferencia'), findsOneWidget);

    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.text('Editar cita'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hora de inicio'),
      '15:00',
    );
    await tester.tap(find.text('Guardar cita'));
    await tester.pumpAndSettle();

    final (citaId, datos) = agenda.editadas.single;
    expect(citaId, 'c1');
    expect(datos.horaInicio, '15:00:00');
    expect(datos.horaFin, '15:45:00');
    expect(datos.empleadoId, 'b1');
    expect(datos.notas, 'Trae su propia navaja');
    expect(find.text('Cita actualizada.'), findsOneWidget);
  });

  testWidgets('a barber edits an appointment but not its price', (
    tester,
  ) async {
    final citas = _FakeCitas([_cita('c1', EstadoCita.pendiente)]);
    final agenda = _FakeAgenda();
    await _abrirAgenda(tester, citas, agenda, empleadoId: 'b1', esOwner: false);

    await tester.tap(find.text('Ana López'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    final precio = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('precio-cita')),
        matching: find.byType(TextField),
      ),
    );
    expect(precio.readOnly, isTrue);
    expect(find.text('Solo el dueño cambia el precio.'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Hora de inicio'),
      '16:00',
    );
    await tester.tap(find.text('Guardar cita'));
    await tester.pumpAndSettle();

    final (_, datos) = agenda.editadas.single;
    expect(datos.precio, 500);
    expect(datos.horaInicio, '16:00:00');
  });

  testWidgets('the owner can still change the price when editing', (
    tester,
  ) async {
    final citas = _FakeCitas([_cita('c1', EstadoCita.pendiente)]);
    final agenda = _FakeAgenda();
    await _abrirAgenda(tester, citas, agenda);

    await tester.tap(find.text('Ana López'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();

    final precio = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const ValueKey('precio-cita')),
        matching: find.byType(TextField),
      ),
    );
    expect(precio.readOnly, isFalse);
    expect(find.text('Solo el dueño cambia el precio.'), findsNothing);
  });

  testWidgets('edits rejected by the server explain why', (tester) async {
    final citas = _FakeCitas([_cita('c1', EstadoCita.pendiente)]);
    final agenda = _FakeAgenda(
      errorAlEditar: const PostgrestException(
        message: 'Solo puedes modificar tus propias citas.',
        code: '42501',
      ),
    );
    await _abrirAgenda(tester, citas, agenda, empleadoId: 'b1', esOwner: false);

    await tester.tap(find.text('Ana López'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar cita'));
    await tester.pumpAndSettle();

    expect(
      find.text('Solo puedes modificar tus propias citas.'),
      findsOneWidget,
    );
  });

  testWidgets('a state change blocked by RLS restores the state and says so', (
    tester,
  ) async {
    final citas = _FakeCitas([
      _cita('c1', EstadoCita.pendiente),
    ], error: const SinPermisoException());
    await _abrirAgenda(tester, citas, _FakeAgenda());

    await tester.tap(find.text('Llegó'));
    await tester.pumpAndSettle();

    expect(
      find.text('No tienes permiso o el registro ya no existe.'),
      findsOneWidget,
    );
    expect(citas.cambios, isEmpty);
  });
}

Future<void> _abrirAgenda(
  WidgetTester tester,
  _FakeCitas citas,
  _FakeAgenda agenda, {
  String? empleadoId,
  bool esOwner = true,
  DateTime Function()? reloj,
  String negocioNombre = 'la barbería',
  AbrirEnlace? abrirEnlace,
}) async {
  tester.view.physicalSize = const Size(1280, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AgendaPage(
          negocioId: 'n1',
          repository: citas,
          agendaRepository: agenda,
          empleadoId: empleadoId,
          esOwner: esOwner,
          fechaInicial: DateTime(2026, 9, 18),
          negocioNombre: negocioNombre,
          reloj: reloj,
          abrirEnlace: abrirEnlace,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _elegir(WidgetTester tester, String campo, String opcion) async {
  await tester.tap(find.widgetWithText(DropdownButtonFormField<String>, campo));
  await tester.pumpAndSettle();
  await tester.tap(find.text(opcion).last);
  await tester.pumpAndSettle();
}

bool _habilitado(WidgetTester tester, String etiqueta) {
  final boton = tester.widget<OutlinedButton>(
    find.widgetWithText(OutlinedButton, etiqueta),
  );
  return boton.onPressed != null;
}

Cita _cita(
  String id,
  EstadoCita estado, {
  String inicio = '10:00:00',
  String fin = '10:45:00',
  String cliente = 'Ana López',
  String telefono = '809-555-1111',
}) => Cita(
  id: id,
  fecha: '2026-09-18',
  horaInicio: inicio,
  horaFin: fin,
  precio: 500,
  estado: estado,
  clienteId: 'cl1',
  servicioId: 's1',
  empleadoId: 'b1',
  notas: 'Trae su propia navaja',
  clienteNombre: cliente,
  clienteTelefono: telefono,
  servicioNombre: 'Corte',
  empleadoNombre: 'Luis',
);

class _FakeCitas implements CitasRepository {
  _FakeCitas(this.citas, {this.error});

  final List<Cita> citas;
  final Object? error;
  final cambios = <(String, EstadoCita)>[];

  @override
  Future<List<Cita>> listarDelDia({
    required String negocioId,
    required DateTime fecha,
    String? empleadoId,
  }) async => fecha.day == 18 ? citas : const [];

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String citaId,
    required EstadoCita estado,
  }) async {
    if (error != null) throw error!;
    cambios.add((citaId, estado));
  }

  @override
  Future<String?> empleadoDelPerfil({
    required String negocioId,
    required String perfilId,
  }) async => 'b1';
}

/// Responde cada día solo cuando la prueba lo indica.
class _CitasControladas implements CitasRepository {
  final pedidas = <DateTime>[];
  final _pendientes = <DateTime, Completer<List<Cita>>>{};

  void responder(DateTime fecha, List<Cita> citas) =>
      _pendientes[fecha]!.complete(citas);

  @override
  Future<List<Cita>> listarDelDia({
    required String negocioId,
    required DateTime fecha,
    String? empleadoId,
  }) {
    pedidas.add(fecha);
    return (_pendientes[fecha] = Completer<List<Cita>>()).future;
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String citaId,
    required EstadoCita estado,
  }) async {}

  @override
  Future<String?> empleadoDelPerfil({
    required String negocioId,
    required String perfilId,
  }) async => null;
}

/// Anota las fechas pedidas.
class _Registro implements CitasRepository {
  _Registro(this._base, this.pedidas);

  final CitasRepository _base;
  final List<DateTime> pedidas;

  @override
  Future<List<Cita>> listarDelDia({
    required String negocioId,
    required DateTime fecha,
    String? empleadoId,
  }) {
    pedidas.add(fecha);
    return _base.listarDelDia(
      negocioId: negocioId,
      fecha: fecha,
      empleadoId: empleadoId,
    );
  }

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String citaId,
    required EstadoCita estado,
  }) =>
      _base.cambiarEstado(negocioId: negocioId, citaId: citaId, estado: estado);

  @override
  Future<String?> empleadoDelPerfil({
    required String negocioId,
    required String perfilId,
  }) => _base.empleadoDelPerfil(negocioId: negocioId, perfilId: perfilId);
}

class _FakeAgenda implements AgendaRepository {
  _FakeAgenda({
    this.errorAlCrear,
    this.fallosAlCrear,
    this.apartado,
    this.errorAlEditar,
  });

  final Object? errorAlCrear;
  final Object? errorAlEditar;

  /// Cuántas veces falla crearCita con [errorAlCrear]; null = siempre.
  final int? fallosAlCrear;
  final ApartadoCita? apartado;
  final creadas = <DatosCita>[];
  final creadasConEstado = <(DatosCita, EstadoCita)>[];
  final intentos = <DatosCita>[];
  final editadas = <(String, DatosCita)>[];
  final completadas = <(String, num, MetodoPago, num)>[];
  final clientesCreados = <String>[];
  var pedidosDePaso = 0;

  @override
  Future<Cliente> clienteDePaso(String negocioId) async {
    pedidosDePaso++;
    return const Cliente(id: 'paso', nombre: nombreClienteDePaso);
  }

  @override
  Future<CatalogoAgenda> catalogo(String negocioId) async =>
      const CatalogoAgenda(
        clientes: [
          Cliente(id: 'cl1', nombre: 'Ana López', telefono: '809-555-1111'),
          Cliente(id: 'cl2', nombre: 'Pedro Gómez'),
        ],
        servicios: [
          ServicioAgenda(
            id: 's1',
            nombre: 'Corte',
            precio: 500,
            duracionMinutos: 45,
          ),
          ServicioAgenda(
            id: 's2',
            nombre: 'Barba',
            precio: 250,
            duracionMinutos: 20,
          ),
        ],
        barberos: [
          BarberoAgenda(id: 'b1', nombre: 'Luis'),
          BarberoAgenda(id: 'b2', nombre: 'Miguel'),
        ],
        serviciosPorBarbero: {
          'b1': {'s1'},
        },
      );

  @override
  Future<Cliente> crearCliente({
    required String negocioId,
    required String nombre,
    String telefono = '',
  }) async {
    clientesCreados.add('$nombre|$telefono');
    return Cliente(id: 'nuevo', nombre: nombre, telefono: telefono);
  }

  @override
  Future<void> crearCita({
    required String negocioId,
    required DatosCita datos,
    EstadoCita estado = EstadoCita.pendiente,
  }) async {
    intentos.add(datos);
    final fallos = fallosAlCrear;
    if (errorAlCrear != null && (fallos == null || intentos.length <= fallos)) {
      throw errorAlCrear!;
    }
    creadas.add(datos);
    creadasConEstado.add((datos, estado));
  }

  @override
  Future<void> editarCita({
    required String negocioId,
    required String citaId,
    required DatosCita datos,
  }) async {
    if (errorAlEditar != null) throw errorAlEditar!;
    editadas.add((citaId, datos));
  }

  @override
  Future<void> completar({
    required String negocioId,
    required String citaId,
    required num precio,
    MetodoPago metodoPago = MetodoPago.efectivo,
    num propina = 0,
  }) async {
    completadas.add((citaId, precio, metodoPago, propina));
  }

  @override
  Future<ApartadoCita?> apartadoDeCita({
    required String negocioId,
    required String citaId,
  }) async => apartado;
}
