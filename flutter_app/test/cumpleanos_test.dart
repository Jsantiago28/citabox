import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/models/cliente.dart';
import 'package:barberiapro/pages/clientes_page.dart';
import 'package:barberiapro/services/clientes_repository.dart';
import 'package:barberiapro/utils/whatsapp.dart';

final _hoy = DateTime(2026, 10, 31);

void main() {
  test('el cliente sabe cuándo cumple', () {
    const ana = Cliente(id: 'a', nombre: 'Ana', cumpleMes: 10, cumpleDia: 31);
    expect(ana.textoCumple, '31 de octubre');
    expect(ana.cumpleHoy(_hoy), isTrue);
    expect(ana.cumpleEnMes(DateTime(2026, 11, 1)), isFalse);
    expect(const Cliente(id: 'b', nombre: 'B').tieneCumple, isFalse);
    expect(
      Cliente.fromMap({
        'id': 'c',
        'nombre': 'C',
        'cumple_mes': 2,
        'cumple_dia': 29,
      }).textoCumple,
      '29 de febrero',
    );
  });

  test('mensaje de cumpleaños', () {
    expect(
      mensajeCumpleanos(cliente: 'Ana Pérez', negocio: 'STIKING'),
      '¡Feliz cumpleaños, Ana! Todo el equipo de STIKING te desea un gran '
      'día. ¡Te esperamos pronto!',
    );
  });

  testWidgets('filtro de cumpleaños del mes y felicitar por WhatsApp', (
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
            abrirEnlace: (uri) async {
              abierto = uri;
              return true;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cumpleaños del mes (2)'), findsOneWidget);
    expect(find.text('Cumple hoy'), findsOneWidget);
    expect(find.text('Cumple el 5'), findsOneWidget);

    await tester.tap(find.byKey(const Key('filtro-cumple')));
    await tester.pumpAndSettle();
    expect(find.text('Noviembre'), findsNothing);
    // Ordenados por día: el 5 antes que el 31.
    expect(
      tester.getTopLeft(find.text('Luis')).dy,
      lessThan(tester.getTopLeft(find.text('Ana')).dy),
    );

    await tester.tap(find.byKey(const Key('felicitar-c1')));
    await tester.pumpAndSettle();
    expect(abierto?.path, '/18095550001');
    expect(
      abierto?.queryParameters['text'],
      startsWith('¡Feliz cumpleaños, Ana!'),
    );
  });

  testWidgets('el formulario guarda y valida el cumpleaños', (tester) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _Repo();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientesPage(negocioId: 'n1', repository: repo, hoy: _hoy),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Nuevo cliente'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cliente-nombre')), 'Pedro');

    Future<void> elegir(String clave, String opcion) async {
      await tester.tap(find.byKey(Key(clave)));
      await tester.pumpAndSettle();
      await tester.tap(find.text(opcion).last);
      await tester.pumpAndSettle();
    }

    // 31 de abril no existe.
    await elegir('cliente-cumple-dia', '31');
    await elegir('cliente-cumple-mes', 'abril');
    await tester.tap(find.text('Crear cliente'));
    await tester.pumpAndSettle();
    expect(find.text('Ese mes no tiene 31 días.'), findsOneWidget);
    expect(repo.guardados, isEmpty);

    await elegir('cliente-cumple-dia', '30');
    await tester.tap(find.text('Crear cliente'));
    await tester.pumpAndSettle();
    expect(repo.guardados.single['cumple_mes'], 4);
    expect(repo.guardados.single['cumple_dia'], 30);
  });
}

class _Repo implements ClientesRepository {
  final guardados = <Map<String, Object?>>[];

  @override
  Future<List<Cliente>> listar(String negocioId) async => const [
    Cliente(
      id: 'c1',
      nombre: 'Ana',
      telefono: '8095550001',
      cumpleMes: 10,
      cumpleDia: 31,
    ),
    Cliente(
      id: 'c2',
      nombre: 'Luis',
      telefono: '8095550002',
      cumpleMes: 10,
      cumpleDia: 5,
    ),
    Cliente(id: 'c3', nombre: 'Noviembre', cumpleMes: 11, cumpleDia: 2),
    Cliente(id: 'c4', nombre: 'Sin cumple'),
  ];

  @override
  Future<Map<String, ResumenCliente>> resumen(String negocioId) async => {};

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
  }) async => guardados.add(datos);

  @override
  Future<void> cambiarEstado({
    required String negocioId,
    required String clienteId,
    required bool activo,
  }) async {}

  @override
  Future<void> anonimizar(String clienteId) async {}
}
