import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/models/cliente.dart';
import 'package:barberiapro/models/configuracion_negocio.dart';
import 'package:barberiapro/models/reserva.dart' show NegocioPublico;
import 'package:barberiapro/pages/clientes_page.dart';
import 'package:barberiapro/pages/configuracion_page.dart';
import 'package:barberiapro/services/clientes_repository.dart';
import 'package:barberiapro/services/configuracion_repository.dart';
import 'package:barberiapro/utils/fidelidad.dart';
import 'package:barberiapro/utils/fotos.dart';

void main() {
  const decima = Fidelidad(visitas: 10, premio: 'Corte gratis');

  test('progreso de la ronda y visita del premio', () {
    expect(decima.progreso(0), '0 de 10 · faltan 9 para Corte gratis');
    expect(decima.progreso(7), '7 de 10 · faltan 2 para Corte gratis');
    expect(decima.progreso(8), '8 de 10 · falta 1 para Corte gratis');
    expect(decima.proximaEsPremio(9), isTrue);
    expect(decima.progreso(9), '¡La próxima visita: Corte gratis!');
    // Tras la visita del premio empieza otra ronda.
    expect(decima.progreso(10), '0 de 10 · faltan 9 para Corte gratis');
    expect(decima.proximaEsPremio(19), isTrue);
    expect(decima.invitacion, 'En tu visita 10: Corte gratis.');
  });

  test('se lee de la base: sin número no hay programa', () {
    expect(Fidelidad.desde(null, 'Corte gratis'), isNull);
    expect(Fidelidad.desde(1, 'x'), isNull);
    expect(Fidelidad.desde(5, '  ')?.premio, 'Servicio gratis');
    final negocio = NegocioPublico.fromMap({
      'nombre': 'N',
      'slug': 'n',
      'fidelidad_visitas': 6,
      'fidelidad_premio': 'Uñas gratis',
    });
    expect(negocio.fidelidad?.invitacion, 'En tu visita 6: Uñas gratis.');
    expect(
      ConfiguracionNegocio.fromMap({'id': 'n', 'nombre': 'N', 'slug': 'n'})
          .fidelidad,
      isNull,
    );
  });

  testWidgets('Configuración activa y guarda el programa', (tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repo = _ConfigRepo();
    Fidelidad? avisada;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfiguracionPage(
            negocioId: 'n1',
            repository: repo,
            elegirFoto: () async => FotoElegida(Uint8List(4), 'image/png'),
            onFidelidadCambiada: (f) => avisada = f,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('config-fidelidad')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('config-fidelidad-visitas')),
      '1',
    );
    await tester.tap(find.text('Guardar programa'));
    await tester.pumpAndSettle();
    expect(find.text('Entre 2 y 50 visitas.'), findsOneWidget);
    expect(repo.datos, isNull);

    await tester.enterText(
      find.byKey(const Key('config-fidelidad-visitas')),
      '8',
    );
    await tester.enterText(
      find.byKey(const Key('config-fidelidad-premio')),
      'Barba gratis',
    );
    await tester.tap(find.text('Guardar programa'));
    await tester.pumpAndSettle();
    expect(repo.datos, {
      'fidelidad_visitas': 8,
      'fidelidad_premio': 'Barba gratis',
    });
    expect(avisada?.visitas, 8);
  });

  testWidgets('Clientes marca a quien le toca el premio', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ClientesPage(
            negocioId: 'n1',
            repository: _ClientesRepo(),
            fidelidad: decima,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Próxima gratis'), findsOneWidget);

    await tester.tap(find.text('Nueve visitas'));
    await tester.pumpAndSettle();
    expect(find.text('¡La próxima visita: Corte gratis!'), findsOneWidget);
  });
}

class _ConfigRepo implements ConfiguracionRepository {
  Map<String, Object?>? datos;

  @override
  Future<ConfiguracionNegocio> cargar(String negocioId) async =>
      const ConfiguracionNegocio(id: 'n1', nombre: 'Luz', slug: 'luz');

  @override
  Future<List<HorarioDia>> horarios(String negocioId) async => const [];

  @override
  Future<void> guardarNegocio({
    required String negocioId,
    required Map<String, Object?> datos,
  }) async => this.datos = datos;

  @override
  Future<void> guardarHorarios({
    required String negocioId,
    required List<HorarioDia> abiertos,
  }) async {}

  @override
  Future<String> subirImagen({
    required String negocioId,
    required String campo,
    required Uint8List bytes,
    required String tipo,
  }) async => '';

  @override
  Future<UsoWhatsapp> usoWhatsapp(String negocioId) async =>
      const UsoWhatsapp(activo: false);
}

class _ClientesRepo implements ClientesRepository {
  @override
  Future<List<Cliente>> listar(String negocioId) async => const [
    Cliente(id: 'c1', nombre: 'Nueve visitas'),
    Cliente(id: 'c2', nombre: 'Tres visitas'),
  ];

  @override
  Future<Map<String, ResumenCliente>> resumen(String negocioId) async => const {
    'c1': ResumenCliente(visitas: 9),
    'c2': ResumenCliente(visitas: 3),
  };

  @override
  Future<List<Cita>> historial({
    required String negocioId,
    required String clienteId,
  }) async => [
    for (var i = 0; i < 9; i++)
      Cita(
        id: 'h$i',
        fecha: '2026-10-0${i + 1}',
        horaInicio: '10:00:00',
        horaFin: '10:30:00',
        precio: 500,
        estado: EstadoCita.completada,
        clienteId: 'c1',
        servicioId: 's1',
        empleadoId: 'e1',
      ),
  ];

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
