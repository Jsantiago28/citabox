import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/app.dart';
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
  final bool admin;
  final activados = <String>[];
  final suspendidos = <String>[];

  @override
  Future<bool> esAdmin() async => admin;

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
}
