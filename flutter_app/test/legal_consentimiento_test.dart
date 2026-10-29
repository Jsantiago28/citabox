import 'package:barberiapro/app.dart';
import 'package:barberiapro/legal/textos_legales.dart';
import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/models/cliente.dart';
import 'package:barberiapro/pages/cliente_ficha.dart';
import 'package:barberiapro/services/clientes_repository.dart';
import 'package:barberiapro/utils/enlace_publico.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('las rutas legales se reconocen sin repositorio', () {
    expect(RutaPublica.desde('#/terminos'), isA<RutaLegal>());
    expect(
      (RutaPublica.desde('/privacidad') as RutaLegal).pagina,
      RutaLegal.privacidad,
    );
    expect(RutaPublica.desde('/otra'), isNull);
  });

  testWidgets('#/privacidad muestra el borrador de la política', (
    tester,
  ) async {
    await tester.pumpWidget(
      const BarberiaApp(supabaseConfigured: false, rutaInicial: '/privacidad'),
    );
    await tester.pumpAndSettle();

    expect(find.text(avisoBorradorLegal), findsOneWidget);
    expect(find.text(tituloPrivacidad), findsWidgets);
    expect(find.text('Quién es responsable de tus datos'), findsOneWidget);
  });

  testWidgets('#/terminos muestra el borrador de los términos', (tester) async {
    await tester.pumpWidget(
      const BarberiaApp(supabaseConfigured: false, rutaInicial: '/terminos'),
    );
    await tester.pumpAndSettle();

    expect(find.text(avisoBorradorLegal), findsOneWidget);
    expect(find.text(tituloTerminos), findsWidgets);
    expect(find.text('El servicio'), findsOneWidget);
  });

  testWidgets('la ficha anonimiza al cliente tras confirmar', (tester) async {
    final repo = _Repo();
    var volvio = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClienteFicha(
            negocioId: 'n1',
            cliente: const Cliente(id: 'c1', nombre: 'Ana', telefono: '809'),
            repository: repo,
            onVolver: () => volvio = true,
            onEditar: () {},
            onCambio: () async {},
            abrirEnlace: (_) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('ficha-menu-datos')));
    await tester.pumpAndSettle();
    expect(find.text('Exportar datos'), findsOneWidget);
    await tester.tap(find.text('Anonimizar cliente'));
    await tester.pumpAndSettle();

    // Cancelar no hace nada.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(repo.anonimizados, isEmpty);

    await tester.tap(find.byKey(const Key('ficha-menu-datos')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anonimizar cliente'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirmar-anonimizar')));
    await tester.pumpAndSettle();

    expect(repo.anonimizados, ['c1']);
    expect(volvio, isTrue);
  });
}

class _Repo implements ClientesRepository {
  final anonimizados = <String>[];

  @override
  Future<void> anonimizar(String clienteId) async =>
      anonimizados.add(clienteId);

  @override
  Future<List<Cita>> historial({
    required String negocioId,
    required String clienteId,
  }) async => const [];

  @override
  Future<List<Cliente>> listar(String negocioId) async => const [];

  @override
  Future<Map<String, ResumenCliente>> resumen(String negocioId) async =>
      const {};

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
}
