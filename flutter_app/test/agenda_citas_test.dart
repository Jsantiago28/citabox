import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/models/cliente.dart';
import 'package:barberiapro/pages/agenda_page.dart';
import 'package:barberiapro/services/agenda_repository.dart';
import 'package:barberiapro/services/citas_repository.dart';
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
      mensajeErrorCita(const PostgrestException(message: 'x', code: '23514')),
      'Ese cambio de estado no está permitido.',
    );
    expect(
      mensajeErrorCita(Exception('sin red'), porDefecto: 'Falló.'),
      'Falló.',
    );
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

    expect(agenda.completadas, [('c1', 650)]);
    expect(find.textContaining(r'RD$650'), findsOneWidget);

    // Deshacer una completada vuelve a Llegó, no a Pendiente.
    await tester.tap(find.text('Completada'));
    await tester.pumpAndSettle();
    expect(citas.cambios.last, ('c1', EstadoCita.llego));
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
    final citas = _FakeCitas([
      _cita('c1', EstadoCita.pendiente),
    ], error: const PostgrestException(message: 'x', code: '23514'));
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
}

Future<void> _abrirAgenda(
  WidgetTester tester,
  _FakeCitas citas,
  _FakeAgenda agenda, {
  String? empleadoId,
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
          fechaInicial: DateTime(2026, 9, 18),
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

Cita _cita(String id, EstadoCita estado) => Cita(
  id: id,
  fecha: '2026-09-18',
  horaInicio: '10:00:00',
  horaFin: '10:45:00',
  precio: 500,
  estado: estado,
  clienteId: 'cl1',
  servicioId: 's1',
  empleadoId: 'b1',
  notas: 'Trae su propia navaja',
  clienteNombre: 'Ana López',
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

class _FakeAgenda implements AgendaRepository {
  _FakeAgenda({this.errorAlCrear, this.apartado});

  final Object? errorAlCrear;
  final ApartadoCita? apartado;
  final creadas = <DatosCita>[];
  final intentos = <DatosCita>[];
  final editadas = <(String, DatosCita)>[];
  final completadas = <(String, num)>[];
  final clientesCreados = <String>[];

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
  }) async {
    intentos.add(datos);
    if (errorAlCrear != null) throw errorAlCrear!;
    creadas.add(datos);
  }

  @override
  Future<void> editarCita({
    required String negocioId,
    required String citaId,
    required DatosCita datos,
  }) async {
    editadas.add((citaId, datos));
  }

  @override
  Future<void> completar({
    required String negocioId,
    required String citaId,
    required num precio,
  }) async {
    completadas.add((citaId, precio));
  }

  @override
  Future<ApartadoCita?> apartadoDeCita({
    required String negocioId,
    required String citaId,
  }) async => apartado;
}
