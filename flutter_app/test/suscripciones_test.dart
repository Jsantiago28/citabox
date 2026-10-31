import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/app.dart';
import 'package:barberiapro/pages/admin_page.dart';
import 'package:barberiapro/pages/business_home_page.dart';
import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/services/apartados_repository.dart';
import 'package:barberiapro/services/citas_repository.dart';
import 'package:barberiapro/services/plataforma_repository.dart';

class _Citas implements CitasRepository {
  @override
  Future<List<Cita>> listarDelDia({
    required String negocioId,
    required DateTime fecha,
    String? empleadoId,
  }) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Apartados implements ApartadosRepository {
  @override
  Future<int> contarPorValidar({
    required String negocioId,
    String? empleadoId,
  }) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Suscripcion implements SuscripcionRepository {
  _Suscripcion(this.s);
  final Suscripcion s;
  @override
  Future<Suscripcion?> obtener(String negocioId) async => s;
}

class _Soporte implements SoporteRepository {
  final enviados = <Map<String, Object?>>[];
  @override
  Future<void> enviar({
    required String negocioId,
    required String mensaje,
    required Map<String, Object?> contexto,
  }) async {
    enviados.add({'negocio': negocioId, 'mensaje': mensaje, ...contexto});
  }
}

class _Admin implements AdminRepository {
  _Admin({this.admin = true});

  @override
  Future<ResumenUso> resumenUso() async => const ResumenUso(
    negocios: 4,
    activos7d: 3,
    enPrueba: 2,
    pagando: 1,
    pausados: 1,
    nuevos30d: 2,
    citas30d: 57,
    citasEnLinea30d: 21,
  );
  final bool admin;
  final activados = <String>[];
  final suspendidos = <String>[];

  @override
  Future<bool> esAdmin() async => admin;

  final cuentas = <CuentaPago>[];

  @override
  Future<List<CuentaPago>> listarCuentas() async => List.of(cuentas);

  @override
  Future<void> guardarCuenta({
    String? id,
    required String banco,
    required String tipo,
    required String numero,
    required String titular,
  }) async => cuentas.add(
    CuentaPago(
      id: 'c${cuentas.length}',
      banco: banco,
      tipo: tipo,
      numero: numero,
      titular: titular,
    ),
  );

  @override
  Future<void> borrarCuenta(String id) async =>
      cuentas.removeWhere((c) => c.id == id);

  @override
  Future<List<NegocioAdmin>> listarNegocios() async => const [
    NegocioAdmin(
      id: 'n1',
      nombre: 'Barbería Uno',
      slug: 'uno',
      plan: 'prueba',
      estado: 'PRUEBA',
      duenoCorreo: 'uno@ejemplo.com',
      barberos: 2,
      citas30d: 17,
      citasEnLinea30d: 9,
      clientes: 40,
    ),
  ];

  @override
  Future<void> activar({
    required String negocioId,
    required String plan,
    required DateTime hasta,
  }) async => activados.add('$negocioId/$plan');

  @override
  Future<void> suspender({required String negocioId, String? motivo}) async =>
      suspendidos.add('$negocioId/$motivo');

  final recordatorios = <String>[];

  @override
  Future<void> configurarRecordatorios({
    required String negocioId,
    required bool activo,
    int cupo = 0,
    num precioMensual = 0,
    num precioExtra = 0,
  }) async =>
      recordatorios.add('$negocioId/$activo/$cupo/$precioMensual/$precioExtra');

  @override
  Future<List<MensajeSoporte>> listarSoporte() async => [
    MensajeSoporte(
      negocio: 'Barbería Uno',
      mensaje: 'No carga la agenda',
      creado: DateTime(2026, 10, 29),
    ),
  ];
}

/// El logo del menú lateral desborda con la fuente de pruebas (Ahem).
void _ignorarDesbordes() {
  final original = FlutterError.onError;
  FlutterError.onError = (detalles) {
    if (detalles.exceptionAsString().contains('overflowed')) return;
    original?.call(detalles);
  };
  addTearDown(() => FlutterError.onError = original);
}

void main() {
  test('haceCuanto describe el último acceso', () {
    final ahora = DateTime(2026, 10, 31, 12);
    expect(haceCuanto(null, ahora), 'Nunca');
    expect(
      haceCuanto(ahora.subtract(const Duration(seconds: 20)), ahora),
      'Ahora',
    );
    expect(
      haceCuanto(ahora.subtract(const Duration(minutes: 5)), ahora),
      'hace 5 min',
    );
    expect(
      haceCuanto(ahora.subtract(const Duration(hours: 3)), ahora),
      'hace 3 h',
    );
    expect(
      haceCuanto(ahora.subtract(const Duration(days: 1)), ahora),
      'hace 1 día',
    );
    expect(
      haceCuanto(ahora.subtract(const Duration(days: 9)), ahora),
      'hace 9 días',
    );
  });

  test('ResumenUso y NegocioAdmin leen las métricas de uso', () {
    final r = ResumenUso.fromMap({
      'negocios': 5,
      'activos_7d': 2,
      'citas_en_linea_30d': 7,
    });
    expect(
      (r.negocios, r.activos7d, r.citasEnLinea30d, r.pagando),
      (5, 2, 7, 0),
    );
    final n = NegocioAdmin.fromMap({
      'negocio_id': 'n1',
      'tipo': 'spa',
      'clientes': 12,
      'citas_en_linea_30d': 4,
      'ultimo_acceso': '2026-10-30T10:00:00Z',
      'ultima_cita': null,
    });
    expect((n.tipo, n.clientes, n.citasEnLinea30d), ('spa', 12, 4));
    expect(n.ultimoAcceso, DateTime.utc(2026, 10, 30, 10).toLocal());
    expect(n.ultimaCita, isNull);
  });

  testWidgets('#/admin muestra el resumen de uso y las columnas nuevas', (
    tester,
  ) async {
    _ignorarDesbordes();
    tester.view.physicalSize = const Size(2200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(MaterialApp(home: AdminPage(repository: _Admin())));
    await tester.pumpAndSettle();

    expect(find.text('Uso'), findsOneWidget);
    expect(find.text('57'), findsOneWidget);
    expect(find.text('21 en línea'), findsOneWidget);
    expect(find.text('2 en prueba'), findsOneWidget);
    expect(find.text('En línea 30d'), findsOneWidget);
    expect(find.text('Último acceso'), findsOneWidget);
    expect(find.text('40'), findsOneWidget);
    expect(find.text('Nunca'), findsNWidgets(2));
  });

  final hoy = DateTime(2026, 10, 29);

  test('avisoSuscripcion cubre prueba, gracia y pausa', () {
    expect(
      avisoSuscripcion(
        Suscripcion(
          plan: 'prueba',
          estado: 'PRUEBA',
          pruebaHasta: DateTime(2026, 11, 8),
        ),
        hoy,
      )?.texto,
      'Te quedan 10 días de prueba.',
    );
    expect(
      avisoSuscripcion(
        Suscripcion(
          plan: 'solo',
          estado: 'ACTIVA',
          pagadoHasta: DateTime(2026, 12, 30),
        ),
        hoy,
      ),
      isNull,
    );
    expect(
      avisoSuscripcion(
        Suscripcion(
          plan: 'solo',
          estado: 'ACTIVA',
          pagadoHasta: DateTime(2026, 11, 1),
        ),
        hoy,
      )?.texto,
      'Tu suscripción vence en 3 días.',
    );
    expect(
      avisoSuscripcion(
        Suscripcion(
          plan: 'solo',
          estado: 'ACTIVA',
          pagadoHasta: DateTime(2026, 10, 27),
        ),
        hoy,
      )?.texto,
      contains('Paga en los próximos 5 días'),
    );
    expect(
      avisoSuscripcion(
        const Suscripcion(plan: 'solo', estado: 'SUSPENDIDA'),
        hoy,
      )?.texto,
      contains('pausado'),
    );
  });

  testWidgets('el dueño ve el aviso y reporta un problema', (tester) async {
    _ignorarDesbordes();
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final soporte = _Soporte();
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessWorkspace(
          userId: 'u1',
          negocioId: 'n1',
          negocioNombre: 'Barbería',
          moneda: 'DOP',
          nombre: 'Luis',
          esOwner: true,
          onSignOut: () {},
          suscripcionRepository: _Suscripcion(
            const Suscripcion(plan: 'solo', estado: 'VENCIDA'),
          ),
          soporteRepository: soporte,
          citasRepository: _Citas(),
          apartadosRepository: _Apartados(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('está pausado'), findsOneWidget);

    await tester.tap(find.text('Reportar un problema'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'No puedo cobrar');
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();

    expect(soporte.enviados, hasLength(1));
    expect(soporte.enviados.single['mensaje'], 'No puedo cobrar');
    expect(soporte.enviados.single['negocio'], 'n1');
    expect(soporte.enviados.single['pantalla'], 'Inicio');
    expect(soporte.enviados.single.containsKey('version'), isTrue);
  });

  testWidgets('#/admin: no admin ve No autorizado', (tester) async {
    await tester.pumpWidget(
      BarberiaApp(rutaInicial: '/admin', adminRepository: _Admin(admin: false)),
    );
    await tester.pumpAndSettle();
    expect(find.text('No autorizado'), findsOneWidget);
  });

  testWidgets('#/admin: el admin activa, suspende y ve soporte', (
    tester,
  ) async {
    _ignorarDesbordes();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _Admin();
    await tester.pumpWidget(
      BarberiaApp(rutaInicial: '/admin', adminRepository: repo),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Barbería Uno'), findsWidgets);
    expect(find.text('uno@ejemplo.com'), findsOneWidget);
    expect(find.text('No carga la agenda'), findsOneWidget);

    await tester.ensureVisible(find.text('Activar'));
    await tester.tap(find.text('Activar'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Activar'));
    await tester.pumpAndSettle();
    expect(repo.activados, ['n1/barberia']);

    await tester.ensureVisible(find.text('Suspender'));
    await tester.tap(find.text('Suspender'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Sin pago');
    await tester.tap(find.widgetWithText(FilledButton, 'Suspender'));
    await tester.pumpAndSettle();
    expect(repo.suspendidos, ['n1/Sin pago']);
  });

  testWidgets('#/admin: el admin contrata los recordatorios automáticos', (
    tester,
  ) async {
    _ignorarDesbordes();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _Admin();
    await tester.pumpWidget(MaterialApp(home: AdminPage(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('No'), findsOneWidget);

    await tester.ensureVisible(find.text('Recordatorios'));
    await tester.tap(find.text('Recordatorios'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('admin-recordatorios-activo')));
    await tester.enterText(
      find.byKey(const Key('admin-recordatorios-cupo')),
      '-3',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(find.text('Escribe 0 o más.'), findsOneWidget);
    expect(repo.recordatorios, isEmpty);

    await tester.enterText(
      find.byKey(const Key('admin-recordatorios-cupo')),
      '300',
    );
    await tester.enterText(
      find.byKey(const Key('admin-recordatorios-mensual')),
      '350',
    );
    await tester.enterText(
      find.byKey(const Key('admin-recordatorios-extra')),
      '2.5',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
    expect(repo.recordatorios, ['n1/true/300/350/2.5']);
  });

  test('textoRecordatoriosAdmin resume lo contratado', () {
    const base = NegocioAdmin(
      id: 'n1',
      nombre: 'Uno',
      slug: 'uno',
      plan: 'solo',
      estado: 'ACTIVA',
    );
    expect(textoRecordatoriosAdmin(base), 'No');
    expect(
      textoRecordatoriosAdmin(
        const NegocioAdmin(
          id: 'n1',
          nombre: 'Uno',
          slug: 'uno',
          plan: 'solo',
          estado: 'ACTIVA',
          recordatoriosAuto: true,
          whatsappMes: 305,
          whatsappExtra: 5,
          whatsappCupo: 300,
          whatsappPrecioMensual: 350,
          whatsappPrecioExtra: 2.5,
        ),
      ),
      'Sí · 305/300 (5 extra) · RD\$350 + RD\$2.5',
    );
  });

  testWidgets('#/admin: el admin agrega y borra una cuenta para cobrar', (
    tester,
  ) async {
    _ignorarDesbordes();
    tester.view.physicalSize = const Size(1600, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _Admin();
    await tester.pumpWidget(MaterialApp(home: AdminPage(repository: repo)));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('agregar-cuenta')));
    await tester.tap(find.byKey(const Key('agregar-cuenta')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cuenta-banco')), 'Banco X');
    await tester.enterText(find.byKey(const Key('cuenta-numero')), 'abc');
    await tester.enterText(find.byKey(const Key('cuenta-titular')), 'Juan');
    await tester.tap(find.byKey(const Key('cuenta-guardar')));
    await tester.pumpAndSettle();
    expect(find.text('Solo números y guiones.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('cuenta-numero')), '123-45');
    await tester.tap(find.byKey(const Key('cuenta-guardar')));
    await tester.pumpAndSettle();
    expect(repo.cuentas.single.numero, '123-45');
    expect(find.text('Banco X · Corriente'), findsOneWidget);

    await tester.ensureVisible(find.byTooltip('Borrar'));
    await tester.tap(find.byTooltip('Borrar'));
    await tester.pumpAndSettle();
    expect(repo.cuentas, isEmpty);
  });
}
