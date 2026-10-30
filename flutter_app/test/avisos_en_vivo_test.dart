import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/pages/business_home_page.dart';
import 'package:barberiapro/services/apartados_repository.dart';
import 'package:barberiapro/services/avisos_en_vivo.dart';
import 'package:barberiapro/services/citas_repository.dart';

void main() {
  test('textos de los avisos según el payload', () {
    expect(
      avisoDeCitaNueva({'hora_inicio': '10:30:00', 'origen': 'PUBLICA'}).texto,
      'Nueva reserva en línea: 10:30',
    );
    expect(
      avisoDeCitaNueva({'hora_inicio': '09:00:00', 'origen': 'INTERNA'}).texto,
      'Nueva cita: 09:00',
    );
    expect(
      avisoDeCitaActualizada(
        {'estado': 'PENDIENTE'},
        {'estado': 'CANCELADA'},
      )?.texto,
      'Cita cancelada',
    );
    expect(
      avisoDeCitaActualizada({'estado': 'CANCELADA'}, {'estado': 'CANCELADA'}),
      isNull,
    );
    expect(
      avisoDeApartadoActualizado(
        {'referencia': null},
        {'referencia': 'AB12'},
      )?.tipo,
      TipoAviso.pagoReportado,
    );
    expect(
      avisoDeApartadoActualizado(
        {'referencia': 'AB12'},
        {'referencia': 'AB12'},
      ),
      isNull,
    );
  });

  testWidgets('aviso en vivo: SnackBar, contador, Ver y limpieza', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // El logo del menú desborda con la fuente de pruebas; no es lo probado.
    final previo = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflowed')) return;
      previo?.call(d);
    };
    addTearDown(() => FlutterError.onError = previo);

    final fake = _FakeAvisos();
    await tester.pumpWidget(
      MaterialApp(
        home: BusinessWorkspace(
          userId: 'u1',
          negocioId: 'n1',
          negocioNombre: 'Barbería',
          moneda: 'DOP',
          nombre: 'Juan',
          esOwner: true,
          onSignOut: () {},
          citasRepository: _Citas(),
          apartadosRepository: _Apartados(),
          avisosEnVivo: fake,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contador-agenda')), findsNothing);

    fake.emitir(
      const AvisoEnVivo(
        TipoAviso.nuevaReserva,
        'Nueva reserva en línea: 10:30',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nueva reserva en línea: 10:30'), findsOneWidget);
    expect(find.byKey(const Key('contador-agenda')), findsOneWidget);

    // "Ver" lleva a Agenda y limpia el contador.
    await tester.tap(find.text('Ver'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('contador-agenda')), findsNothing);

    // En Agenda ya no se acumulan avisos.
    fake.emitir(const AvisoEnVivo(TipoAviso.citaCancelada, 'Cita cancelada'));
    await tester.pumpAndSettle();
    expect(find.text('Cita cancelada'), findsOneWidget);
    expect(find.byKey(const Key('contador-agenda')), findsNothing);

    await tester.pumpWidget(const SizedBox());
    expect(fake.cerrado, isTrue);
  });
}

class _FakeAvisos implements AvisosEnVivo {
  final _c = StreamController<AvisoEnVivo>.broadcast();
  var cerrado = false;

  void emitir(AvisoEnVivo a) => _c.add(a);

  @override
  Stream<AvisoEnVivo> get avisos => _c.stream;

  @override
  Future<void> cerrar() async {
    cerrado = true;
    await _c.close();
  }
}

class _Citas implements CitasRepository {
  @override
  Future<String?> empleadoDelPerfil({
    required String negocioId,
    required String perfilId,
  }) async => null;

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
}

class _Apartados implements ApartadosRepository {
  @override
  Future<int> contarPorValidar({
    required String negocioId,
    String? empleadoId,
  }) async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<dynamic>.value(const <Object>[]);
}
