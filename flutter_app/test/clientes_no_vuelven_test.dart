import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/models/cliente.dart';
import 'package:barberiapro/pages/clientes_page.dart';
import 'package:barberiapro/services/clientes_repository.dart';
import 'package:barberiapro/utils/whatsapp.dart';

final _hoy = DateTime(2026, 10, 30);

void main() {
  test('noVuelve: 45 días o más, sin cita reservada', () {
    ResumenCliente vino(int diasAtras, {bool proxima = false}) =>
        ResumenCliente(
          visitas: 3,
          ultimaVisita: _hoy.subtract(Duration(days: diasAtras)),
          tieneProxima: proxima,
        );

    expect(vino(44).noVuelve(_hoy), isFalse);
    expect(vino(45).noVuelve(_hoy), isTrue);
    expect(vino(90, proxima: true).noVuelve(_hoy), isFalse);
    expect(vino(60).diasSinVenir(_hoy), 60);
    // Nunca vino: no es "no vuelve".
    expect(const ResumenCliente(faltas: 2).noVuelve(_hoy), isFalse);
  });

  test('mensaje para invitar a volver', () {
    expect(
      mensajeVuelve(
        cliente: 'Ana Pérez',
        negocio: 'STIKING',
        enlace: 'https://citabox.pages.dev/r/stiking',
      ),
      'Hola Ana, ¡hace tiempo que no te vemos en STIKING! '
      'Reserva cuando quieras aquí: https://citabox.pages.dev/r/stiking',
    );
    expect(
      mensajeVuelve(cliente: 'Luis', negocio: 'STIKING'),
      endsWith('¿Te apartamos un turno?'),
    );
  });

  testWidgets('el filtro muestra a los que no vuelven y los invita', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    Uri? abierto;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientesPage(
            negocioId: 'n1',
            repository: _Repo(),
            hoy: _hoy,
            negocioNombre: 'STIKING',
            enlaceReservas: 'https://citabox.pages.dev/r/stiking',
            abrirEnlace: (uri) async {
              abierto = uri;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No vuelven (2)'), findsOneWidget);
    expect(find.text('Reciente'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filtro-no-vuelven')));
    await tester.pumpAndSettle();

    // Solo los dos que no vuelven, el de más días primero.
    expect(find.text('Reciente'), findsNothing);
    expect(find.text('Con cita'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Antiguo')).dy,
      lessThan(tester.getTopLeft(find.text('Olvidado')).dy),
    );
    expect(find.text('Hace 120 días'), findsOneWidget);

    await tester.tap(find.byKey(const Key('invitar-c2')));
    await tester.pumpAndSettle();
    expect(abierto?.host, 'wa.me');
    expect(abierto?.path, '/18095550002');
    expect(abierto?.queryParameters['text'], startsWith('Hola Olvidado'));
  });
}

class _Repo implements ClientesRepository {
  @override
  Future<List<Cliente>> listar(String negocioId) async => const [
    Cliente(id: 'c1', nombre: 'Reciente', telefono: '8095550001'),
    Cliente(id: 'c2', nombre: 'Olvidado', telefono: '8095550002'),
    Cliente(id: 'c3', nombre: 'Antiguo', telefono: '8095550003'),
    Cliente(id: 'c4', nombre: 'Con cita', telefono: '8095550004'),
  ];

  @override
  Future<Map<String, ResumenCliente>> resumen(String negocioId) async => {
    'c1': ResumenCliente(
      visitas: 2,
      ultimaVisita: _hoy.subtract(const Duration(days: 10)),
    ),
    'c2': ResumenCliente(
      visitas: 4,
      ultimaVisita: _hoy.subtract(const Duration(days: 50)),
    ),
    'c3': ResumenCliente(
      visitas: 1,
      ultimaVisita: _hoy.subtract(const Duration(days: 120)),
    ),
    'c4': ResumenCliente(
      visitas: 5,
      ultimaVisita: _hoy.subtract(const Duration(days: 80)),
      tieneProxima: true,
    ),
  };

  @override
  Future<List<Cita>> historial({
    required String negocioId,
    required String clienteId,
  }) async => const [];

  @override
  Future<void> guardar({
    required String negocioId,
    required Map<String, Object?> datos,
    String? clienteId,
  }) async {}

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String clienteId,
    required bool activo,
  }) async {}

  @override
  Future<void> anonimizar(String clienteId) async {}
}
