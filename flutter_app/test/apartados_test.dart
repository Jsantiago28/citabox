import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/apartado.dart';
import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/pages/apartados_page.dart';
import 'package:barberiapro/pages/dashboard_page.dart';
import 'package:barberiapro/services/apartados_repository.dart';
import 'package:barberiapro/services/citas_repository.dart';
import 'package:barberiapro/utils/whatsapp.dart';

void main() {
  test('builds WhatsApp links with country code for local numbers', () {
    expect(
      enlaceWhatsApp('(809) 555-1234', 'Hola Ana').toString(),
      'https://wa.me/18095551234?text=Hola%20Ana',
    );
    expect(
      enlaceWhatsApp('+1 829 555 0000', 'x').toString(),
      'https://wa.me/18295550000?text=x',
    );
    expect(enlaceWhatsApp('', 'x'), isNull);
  });

  test('reads an apartado with its appointment', () {
    final apartado = Apartado.fromMap({
      'id': 'a1',
      'cita_id': 'c1',
      'monto': '100.00',
      'estado': 'PAGADO',
      'metodo_pago': 'TRANSFERENCIA',
      'referencia': '123',
      'citas': {
        'fecha': '2026-10-28',
        'hora_inicio': '15:00:00',
        'estado': 'CONFIRMADA',
        'empleado_id': 'e1',
        'clientes': {'nombre': 'Ana', 'telefono': '8095551234'},
        'servicios': {'nombre': 'Corte'},
        'empleados': {'nombre': 'Luis'},
      },
    });
    expect(apartado.monto, 100);
    expect(apartado.estado, EstadoApartado.pagado);
    expect(apartado.estadoCita, EstadoCita.confirmada);
    expect(apartado.clienteTelefono, '8095551234');
    expect(apartado.empleadoNombre, 'Luis');
  });

  testWidgets('lists pending first with reported reference and filters', (
    tester,
  ) async {
    final repo = _FakeApartadosRepository(_ejemplo());
    await _montar(tester, repo);

    // Por validar: primero el que ya reportó la referencia.
    final ana = tester.getTopLeft(find.byKey(const Key('apartado-a2')));
    final pedro = tester.getTopLeft(find.byKey(const Key('apartado-a1')));
    expect(ana.dy, lessThan(pedro.dy));
    expect(find.textContaining('Ref. TRX-889'), findsOneWidget);
    expect(find.text('Carla Gómez'), findsNothing);

    await tester.tap(find.byKey(const Key('filtro-PAGADO')));
    await tester.pumpAndSettle();
    expect(find.text('Carla Gómez'), findsOneWidget);
    expect(find.text('Ana López'), findsNothing);

    await tester.tap(find.byKey(const Key('filtro-PENDIENTE')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('apartados-buscar')), 'pedro');
    await tester.pumpAndSettle();
    expect(find.text('Pedro Marte'), findsOneWidget);
    expect(find.text('Ana López'), findsNothing);
  });

  testWidgets('validates a payment with amount, method and reference', (
    tester,
  ) async {
    final repo = _FakeApartadosRepository(_ejemplo());
    await _montar(tester, repo);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('apartado-a2')),
        matching: find.text('Validar pago'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Confirmar pago'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('validar-monto')), '150');
    await tester.tap(find.text('Efectivo'));
    await tester.enterText(find.byKey(const Key('validar-referencia')), '');
    await tester.tap(find.text('Confirmar pago'));
    await tester.pumpAndSettle();

    expect(repo.validados, [('a2', 150, MetodoPago.efectivo, '')]);
    expect(find.text('Ana López'), findsNothing);
    expect(
      find.text('Pago validado. La cita quedó confirmada.'),
      findsOneWidget,
    );
  });

  testWidgets('rejects a pending apartado after confirming', (tester) async {
    final repo = _FakeApartadosRepository(_ejemplo());
    await _montar(tester, repo);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('apartado-a1')),
        matching: find.text('Rechazar'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(repo.cancelados, isEmpty);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('apartado-a1')),
        matching: find.text('Rechazar'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, cancelar apartado'));
    await tester.pumpAndSettle();

    expect(repo.cancelados, ['a1']);
    await tester.tap(find.byKey(const Key('filtro-CANCELADO')));
    await tester.pumpAndSettle();
    expect(find.text('Pedro Marte'), findsOneWidget);
  });

  testWidgets('registers an apartado for an upcoming appointment', (
    tester,
  ) async {
    final repo = _FakeApartadosRepository(_ejemplo());
    await _montar(tester, repo);

    await tester.tap(find.text('Registrar apartado'));
    await tester.pumpAndSettle();

    expect(repo.desde, DateTime(2026, 10, 28));
    expect(find.text('Luis Peña'), findsOneWidget);
    final monto = tester.widget<EditableText>(
      find.descendant(
        of: find.byKey(const Key('registrar-monto')),
        matching: find.byType(EditableText),
      ),
    );
    expect(monto.controller.text, '250');

    await tester.tap(find.byKey(const Key('registrar-cita-c9')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(FilledButton, 'Registrar apartado'),
      ),
    );
    await tester.pumpAndSettle();

    expect(repo.registrados, [('c9', 250)]);
    expect(find.text('Luis Peña'), findsOneWidget);
    expect(find.text('Apartado registrado.'), findsOneWidget);
  });

  testWidgets('opens WhatsApp with the appointment and amount', (tester) async {
    final repo = _FakeApartadosRepository(_ejemplo());
    final abiertos = <Uri>[];
    await _montar(tester, repo, abiertos: abiertos);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('apartado-a2')),
        matching: find.byTooltip('Escribir por WhatsApp'),
      ),
    );
    await tester.pumpAndSettle();

    expect(abiertos, hasLength(1));
    final enlace = abiertos.single;
    expect(enlace.host, 'wa.me');
    expect(enlace.path, '/18095551234');
    final texto = enlace.queryParameters['text']!;
    expect(texto, contains('Ana'));
    expect(texto, contains(r'RD$100'));
    expect(texto, contains('3:00 PM'));
  });

  testWidgets('dashboard shows pending apartados and opens the section', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var abierto = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DashboardPage(
            negocioId: 'n1',
            negocioNombre: 'Barbería',
            nombre: 'Juan',
            repository: _CitasVacias(),
            onVerAgenda: () {},
            apartadosRepository: _FakeApartadosRepository(_ejemplo()),
            onVerApartados: () => abierto = true,
            hoy: DateTime(2026, 10, 28),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2 apartados por validar'), findsOneWidget);
    await tester.tap(find.text('Revisar'));
    expect(abierto, isTrue);
  });
}

Future<void> _montar(
  WidgetTester tester,
  _FakeApartadosRepository repo, {
  List<Uri>? abiertos,
}) async {
  tester.view.physicalSize = const Size(1280, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ApartadosPage(
          negocioId: 'n1',
          negocioNombre: 'Barbería El Jefe',
          repository: repo,
          hoy: DateTime(2026, 10, 28, 9, 30),
          abrirEnlace: (uri) async => abiertos?.add(uri),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

List<Apartado> _ejemplo() => [
  const Apartado(
    id: 'a1',
    citaId: 'c1',
    monto: 100,
    estado: EstadoApartado.pendiente,
    fecha: '2026-10-28',
    horaInicio: '10:00:00',
    clienteNombre: 'Pedro Marte',
    clienteTelefono: '8295550000',
    servicioNombre: 'Corte',
    empleadoNombre: 'Luis',
  ),
  const Apartado(
    id: 'a2',
    citaId: 'c2',
    monto: 100,
    estado: EstadoApartado.pendiente,
    metodoPago: 'TRANSFERENCIA',
    referencia: 'TRX-889',
    fecha: '2026-10-29',
    horaInicio: '15:00:00',
    clienteNombre: 'Ana López',
    clienteTelefono: '809-555-1234',
    servicioNombre: 'Corte + Barba',
    empleadoNombre: 'Luis',
  ),
  const Apartado(
    id: 'a3',
    citaId: 'c3',
    monto: 100,
    estado: EstadoApartado.pagado,
    metodoPago: 'EFECTIVO',
    fechaPago: '2026-10-27T10:00:00Z',
    fecha: '2026-10-27',
    horaInicio: '11:00:00',
    estadoCita: EstadoCita.confirmada,
    clienteNombre: 'Carla Gómez',
  ),
];

class _FakeApartadosRepository implements ApartadosRepository {
  _FakeApartadosRepository(this.apartados);

  final List<Apartado> apartados;
  final validados = <(String, num, MetodoPago, String?)>[];
  final cancelados = <String>[];
  final registrados = <(String, num)>[];
  DateTime? desde;

  final _citas = const [
    Cita(
      id: 'c9',
      fecha: '2026-10-30',
      horaInicio: '09:00:00',
      precio: 500,
      estado: EstadoCita.pendiente,
      clienteNombre: 'Luis Peña',
      servicioNombre: 'Corte',
      empleadoNombre: 'Luis',
    ),
  ];

  void _reemplazar(String id, Apartado Function(Apartado) cambio) {
    final i = apartados.indexWhere((a) => a.id == id);
    apartados[i] = cambio(apartados[i]);
  }

  Apartado _con(Apartado a, EstadoApartado estado, {num? monto}) => Apartado(
    id: a.id,
    citaId: a.citaId,
    monto: monto ?? a.monto,
    estado: estado,
    referencia: a.referencia,
    fecha: a.fecha,
    horaInicio: a.horaInicio,
    clienteNombre: a.clienteNombre,
    clienteTelefono: a.clienteTelefono,
  );

  @override
  Future<List<Apartado>> listar({
    required String negocioId,
    String? empleadoId,
  }) async => List.of(apartados);

  @override
  Future<int> contarPorValidar({
    required String negocioId,
    String? empleadoId,
  }) async =>
      apartados.where((a) => a.estado == EstadoApartado.pendiente).length;

  @override
  Future<num> montoPorDefecto(String negocioId) async => 250;

  @override
  Future<List<Cita>> citasSinApartado({
    required String negocioId,
    required DateTime desde,
    String? empleadoId,
  }) async {
    this.desde = desde;
    return _citas;
  }

  @override
  Future<void> validar({
    required String negocioId,
    required String apartadoId,
    required num monto,
    required MetodoPago metodo,
    String? referencia,
  }) async {
    validados.add((apartadoId, monto, metodo, referencia));
    _reemplazar(
      apartadoId,
      (a) => _con(a, EstadoApartado.pagado, monto: monto),
    );
  }

  @override
  Future<void> cancelar({
    required String negocioId,
    required String apartadoId,
  }) async {
    cancelados.add(apartadoId);
    _reemplazar(apartadoId, (a) => _con(a, EstadoApartado.cancelado));
  }

  @override
  Future<void> registrar({
    required String negocioId,
    required String citaId,
    required num monto,
  }) async {
    registrados.add((citaId, monto));
    final cita = _citas.firstWhere((c) => c.id == citaId);
    apartados.add(
      Apartado(
        id: 'nuevo',
        citaId: citaId,
        monto: monto,
        estado: EstadoApartado.pendiente,
        fecha: cita.fecha,
        horaInicio: cita.horaInicio,
        clienteNombre: cita.clienteNombre,
      ),
    );
  }
}

class _CitasVacias implements CitasRepository {
  @override
  Future<List<Cita>> listarDelDia({
    required String negocioId,
    required DateTime fecha,
    String? empleadoId,
  }) async => const [];

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
