import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/configuracion_negocio.dart';
import 'package:barberiapro/pages/configuracion_page.dart';
import 'package:barberiapro/services/configuracion_repository.dart';
import 'package:barberiapro/utils/enlace_publico.dart';

void main() {
  group('enlaceReserva', () {
    test('uses the web origin when a base is given', () {
      expect(
        enlaceReserva(
          'el-jefe',
          base: Uri.parse('https://app.barberia.pro/#/inicio'),
        ),
        'https://app.barberia.pro/#/reservar/el-jefe',
      );
      expect(
        enlaceReserva(
          'el-jefe',
          base: Uri.parse('http://localhost:8080/index.html'),
        ),
        'http://localhost:8080/#/reservar/el-jefe',
      );
    });

    test('keeps the folder where the app is published', () {
      expect(
        enlaceReserva(
          'el-jefe',
          base: Uri.parse('https://usuario.github.io/barberia/'),
        ),
        'https://usuario.github.io/barberia/#/reservar/el-jefe',
      );
    });

    test('returns only the path outside the web', () {
      expect(enlaceReserva('el-jefe'), '/#/reservar/el-jefe');
      expect(
        enlaceReserva('el-jefe', base: Uri.parse('file:///C:/app/')),
        '/#/reservar/el-jefe',
      );
    });
  });

  test('parses and formats opening hours', () {
    expect(minutosDesdeTexto('09:30:00'), 570);
    expect(minutosDesdeTexto('9:05'), 545);
    expect(minutosDesdeTexto('24:00'), isNull);
    expect(minutosDesdeTexto('abc'), isNull);
    expect(textoDesdeMinutos(570), '09:30');
    expect(
      const HorarioDia(diaSemana: 1, apertura: 540, cierre: 1080).toMap('n1'),
      {
        'negocio_id': 'n1',
        'dia_semana': 1,
        'hora_apertura': '09:00:00',
        'hora_cierre': '18:00:00',
      },
    );
  });

  testWidgets('shows the public booking link and copies it', (tester) async {
    final repository = _FakeConfiguracionRepository();
    final copiado = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiado.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await _abrir(
      tester,
      repository,
      base: Uri.parse('https://app.barberia.pro/'),
    );

    const enlace = 'https://app.barberia.pro/#/reservar/el-jefe';
    expect(find.text(enlace), findsOneWidget);
    await tester.tap(find.text('Copiar'));
    await tester.pumpAndSettle();

    expect(copiado, [enlace]);
    expect(find.text('Enlace copiado.'), findsOneWidget);
  });

  testWidgets('saves the business profile', (tester) async {
    final repository = _FakeConfiguracionRepository();
    await _abrir(tester, repository);

    expect(find.text('el-jefe'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('config-nombre')),
      'Barbería El Jefe 2',
    );
    await tester.enterText(
      find.byKey(const Key('config-telefono')),
      '809-555-0000',
    );
    await tester.enterText(find.byKey(const Key('config-color')), '#112233');
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();

    expect(repository.ultimoNegocioId, 'n1');
    expect(repository.datosGuardados, {
      'nombre': 'Barbería El Jefe 2',
      'telefono': '809-555-0000',
      'direccion': 'Calle 1',
      'logo': null,
      'imagen': null,
      'color_principal': '#112233',
    });
    expect(find.text('Perfil guardado.'), findsOneWidget);
  });

  testWidgets('profile requires a name and a valid color', (tester) async {
    final repository = _FakeConfiguracionRepository();
    await _abrir(tester, repository);

    await tester.enterText(find.byKey(const Key('config-nombre')), ' ');
    await tester.enterText(find.byKey(const Key('config-color')), 'rojo');
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();

    expect(find.text('El nombre es obligatorio.'), findsOneWidget);
    expect(find.text('Usa el formato #RRGGBB.'), findsOneWidget);
    expect(repository.datosGuardados, isNull);
  });

  testWidgets('opening hours require closing after opening', (tester) async {
    final repository = _FakeConfiguracionRepository();
    await _abrir(tester, repository);

    // Lunes abierto de 09:00 a 18:00; se pone el cierre antes de abrir.
    await tester.enterText(find.byKey(const Key('dia-1-cierre')), '08:00');
    await tester.tap(find.text('Guardar horario'));
    await tester.pumpAndSettle();

    expect(find.text('Debe ser después de la apertura.'), findsOneWidget);
    expect(repository.horariosGuardados, isNull);

    await tester.enterText(find.byKey(const Key('dia-1-cierre')), 'tarde');
    await tester.tap(find.text('Guardar horario'));
    await tester.pumpAndSettle();

    expect(find.text('Hora inválida (HH:MM).'), findsOneWidget);
    expect(repository.horariosGuardados, isNull);
  });

  testWidgets('saves only the open days of the week', (tester) async {
    final repository = _FakeConfiguracionRepository();
    await _abrir(tester, repository);

    expect(find.text('Cerrado'), findsNWidgets(6));
    // Se abre el sábado (09:00-18:00 por defecto) y se ajusta el cierre.
    await tester.tap(find.byKey(const Key('dia-6-abierto')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('dia-6-cierre')), '14:30');
    await tester.tap(find.text('Guardar horario'));
    await tester.pumpAndSettle();

    expect(repository.horariosGuardados, const [
      HorarioDia(diaSemana: 1, apertura: 540, cierre: 1080),
      HorarioDia(diaSemana: 6, apertura: 540, cierre: 870),
    ]);
    expect(find.text('Horario guardado.'), findsOneWidget);
  });

  testWidgets('validates and saves the booking rules', (tester) async {
    final repository = _FakeConfiguracionRepository();
    await _abrir(tester, repository);

    await tester.enterText(find.byKey(const Key('config-monto')), '-5');
    await tester.enterText(find.byKey(const Key('config-intervalo')), '200');
    await tester.tap(find.text('Guardar reservas'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa un monto de 0 o más.'), findsOneWidget);
    expect(find.text('Entre 5 y 120 minutos.'), findsOneWidget);
    expect(repository.datosGuardados, isNull);

    await tester.enterText(find.byKey(const Key('config-monto')), '250');
    await tester.enterText(find.byKey(const Key('config-intervalo')), '30');
    await tester.enterText(
      find.byKey(const Key('config-instrucciones')),
      'Banco Popular\nCuenta 123\nA nombre de Juan',
    );
    await tester.tap(find.byKey(const Key('config-apartado-requerido')));
    await tester.tap(find.text('Guardar reservas'));
    await tester.pumpAndSettle();

    expect(repository.datosGuardados, {
      'apartado_requerido': false,
      'apartado_monto': 250,
      'apartado_politica': 'No se devuelve.',
      'apartado_instrucciones': 'Banco Popular\nCuenta 123\nA nombre de Juan',
      'cancelacion_horas_minimas': 24,
      'intervalo_reserva_minutos': 30,
    });
  });
}

Future<void> _abrir(
  WidgetTester tester,
  ConfiguracionRepository repository, {
  Uri? base,
}) async {
  tester.view.physicalSize = const Size(1200, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ConfiguracionPage(
          negocioId: 'n1',
          repository: repository,
          baseEnlace: base,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeConfiguracionRepository implements ConfiguracionRepository {
  String? ultimoNegocioId;
  Map<String, Object?>? datosGuardados;
  List<HorarioDia>? horariosGuardados;

  @override
  Future<ConfiguracionNegocio> cargar(String negocioId) async {
    ultimoNegocioId = negocioId;
    return const ConfiguracionNegocio(
      id: 'n1',
      nombre: 'Barbería El Jefe',
      slug: 'el-jefe',
      direccion: 'Calle 1',
      apartadoMonto: 100,
      apartadoPolitica: 'No se devuelve.',
    );
  }

  @override
  Future<List<HorarioDia>> horarios(String negocioId) async => const [
    HorarioDia(diaSemana: 1, apertura: 540, cierre: 1080),
  ];

  @override
  Future<void> guardarNegocio({
    required String negocioId,
    required Map<String, Object?> datos,
  }) async {
    ultimoNegocioId = negocioId;
    datosGuardados = datos;
  }

  @override
  Future<void> guardarHorarios({
    required String negocioId,
    required List<HorarioDia> abiertos,
  }) async {
    ultimoNegocioId = negocioId;
    horariosGuardados = abiertos;
  }
}
