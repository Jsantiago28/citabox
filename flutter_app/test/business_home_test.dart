import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/pages/business_home_page.dart';
import 'package:barberiapro/services/citas_repository.dart';

void main() {
  testWidgets(
    'a network error loading the barber is not "profile not linked"',
    (tester) async {
      // En celular el menú va en el cajón (el lateral no cabe con la fuente
      // de pruebas).
      tester.view.physicalSize = const Size(500, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      // Primero falla la red; al reintentar, el perfil no tiene empleado.
      final citas = _CitasPerfil([Exception('sin conexión'), null]);
      await tester.pumpWidget(
        MaterialApp(
          home: BusinessWorkspace(
            userId: 'u1',
            negocioId: 'n1',
            negocioNombre: 'Barbería',
            moneda: 'DOP',
            nombre: 'Luis',
            esOwner: false,
            onSignOut: () {},
            citasRepository: citas,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No se pudo cargar tu agenda.'), findsOneWidget);
      expect(find.textContaining('no está vinculado'), findsNothing);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();

      expect(citas.consultas, 2);
      expect(find.text('No se pudo cargar tu agenda.'), findsNothing);
      expect(find.textContaining('no está vinculado'), findsOneWidget);
    },
  );
}

/// empleadoDelPerfil devuelve (o lanza) las respuestas en orden.
class _CitasPerfil implements CitasRepository {
  _CitasPerfil(this.respuestas);

  final List<Object?> respuestas;
  var consultas = 0;

  @override
  Future<String?> empleadoDelPerfil({
    required String negocioId,
    required String perfilId,
  }) async {
    final respuesta = respuestas[consultas++];
    if (respuesta is Exception) throw respuesta;
    return respuesta as String?;
  }

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
