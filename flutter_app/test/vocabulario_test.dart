import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/configuracion_negocio.dart';
import 'package:barberiapro/models/registro_negocio.dart';
import 'package:barberiapro/pages/configuracion_page.dart';
import 'package:barberiapro/services/configuracion_repository.dart';
import 'package:barberiapro/utils/fotos.dart';
import 'package:barberiapro/utils/vocabulario.dart';

void main() {
  test('cada tipo de negocio tiene sus palabras', () {
    expect(TipoNegocio.desdeCodigo('spa').profesional, 'Terapeuta');
    expect(TipoNegocio.desdeCodigo('salon').profesionalesMin, 'estilistas');
    expect(TipoNegocio.desdeCodigo('unas').catalogoSalon, isTrue);
    expect(TipoNegocio.desdeCodigo('consultorio').negocio, 'consultorio');
    // Desconocido o vacío: barbería, el tipo de los negocios que ya existían.
    expect(TipoNegocio.desdeCodigo(null), TipoNegocio.barberia);
    expect(TipoNegocio.desdeCodigo('taller'), TipoNegocio.barberia);
    expect(TipoNegocio.barberia.catalogoSalon, isFalse);
  });

  test('el registro pendiente guarda el tipo de negocio', () {
    const datos = RegistroNegocio(
      negocioNombre: 'Spa Luz',
      slug: 'spa-luz',
      ownerNombre: 'Ana',
      tipo: 'spa',
    );
    final leido = RegistroNegocio.fromMetadata(
      Map<String, dynamic>.from(datos.toMetadata()),
    );
    expect(leido?.tipo, 'spa');
    // Registros pendientes de antes no traían tipo.
    expect(
      RegistroNegocio.fromMetadata({
        RegistroNegocio.metadataKey: {
          'negocio_nombre': 'X',
          'slug': 'x',
          'owner_nombre': 'Y',
        },
      })?.tipo,
      'barberia',
    );
  });

  testWidgets('el host cambia las palabras también en diálogos', (
    tester,
  ) async {
    late BuildContext pagina;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TipoNegocioHost(child: child!),
        home: Builder(
          builder: (context) {
            pagina = context;
            return Text('Elige tu ${Vocabulario.of(context).profesionalMin}');
          },
        ),
      ),
    );
    expect(find.text('Elige tu barbero'), findsOneWidget);

    TipoNegocioHost.fijar(pagina, TipoNegocio.spa);
    await tester.pump();
    expect(find.text('Elige tu terapeuta'), findsOneWidget);

    showDialog<void>(
      context: pagina,
      builder: (context) => Text(Vocabulario.of(context).profesionales),
    );
    await tester.pumpAndSettle();
    expect(find.text('Terapeutas'), findsOneWidget);
  });

  testWidgets('Configuración guarda el tipo de negocio y lo avisa', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final repository = _Repo();
    TipoNegocio? avisado;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfiguracionPage(
            negocioId: 'n1',
            repository: repository,
            elegirFoto: () async => FotoElegida(Uint8List(4), 'image/png'),
            onTipoCambiado: (tipo) => avisado = tipo,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selector = find.byKey(const Key('config-tipo'));
    await tester.ensureVisible(selector);
    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spa').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();

    expect(repository.datos?['tipo'], 'spa');
    expect(avisado, TipoNegocio.spa);
  });
}

class _Repo implements ConfiguracionRepository {
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
