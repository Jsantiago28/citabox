import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/registro_negocio.dart';
import 'package:barberiapro/pages/login_page.dart';
import 'package:barberiapro/pages/registro_page.dart';
import 'package:barberiapro/services/registro_repository.dart';
import 'package:barberiapro/utils/slug.dart';

void main() {
  test('slugify matches the database slug format', () {
    expect(slugify('  Barbería Ñandú & Co.  '), 'barberia-nandu-co');
    expect(slugify('Salón -- Élite'), 'salon-elite');
    expect(slugValido('barberia-nandu-co'), isTrue);
    expect(slugValido('Barberia'), isFalse);
    expect(slugValido('barberia-'), isFalse);
  });

  test('pending registration survives a metadata round trip', () {
    const datos = RegistroNegocio(
      negocioNombre: 'Barbería Sol',
      slug: 'barberia-sol',
      negocioTelefono: '555',
      ownerNombre: 'Ana',
    );

    final leido = RegistroNegocio.fromMetadata(
      Map<String, dynamic>.from(datos.toMetadata()),
    );

    expect(leido?.slug, 'barberia-sol');
    expect(leido?.negocioTelefono, '555');
    expect(RegistroNegocio.fromMetadata({}), isNull);
    expect(RegistroNegocio.fromMetadata(null), isNull);
  });

  testWidgets('login opens the business registration form', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: LoginPage(registroRepository: _FakeRegistroRepository()),
      ),
    );
    await tester.tap(find.text('Registrar mi negocio'));
    await tester.pumpAndSettle();

    expect(find.text('Registra tu negocio'), findsOneWidget);
  });

  testWidgets('registration validates required fields', (tester) async {
    final repository = _FakeRegistroRepository();
    await _pumpRegistro(tester, RegistroPage(repository: repository));

    await _tapCrear(tester);

    expect(find.text('El nombre del negocio es obligatorio.'), findsOneWidget);
    expect(find.text('Tu nombre es obligatorio.'), findsOneWidget);
    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(repository.cuentaCreada, isFalse);
  });

  testWidgets(
    'new account keeps business data pending until email confirmation',
    (tester) async {
      final repository = _FakeRegistroRepository();
      await _pumpRegistro(tester, RegistroPage(repository: repository));

      await _llenarFormulario(tester);
      expect(find.text('reservar/barberia-el-sol'), findsOneWidget);
      await _tapCrear(tester);

      expect(find.text('Revisa tu correo'), findsOneWidget);
      expect(repository.email, 'ana@example.com');
      expect(repository.datosCuenta?.slug, 'barberia-el-sol');
      expect(repository.datosCuenta?.ownerNombre, 'Ana López');
      expect(repository.negocioCreado, isNull);
    },
  );

  testWidgets('taken slug is rejected before creating the account', (
    tester,
  ) async {
    final repository = _FakeRegistroRepository(slugLibre: false);
    await _pumpRegistro(tester, RegistroPage(repository: repository));

    await _llenarFormulario(tester);
    await _tapCrear(tester);

    expect(find.text('Ese slug ya está en uso. Elige otro.'), findsOneWidget);
    expect(repository.cuentaCreada, isFalse);
  });

  testWidgets('pending registration is completed automatically after login', (
    tester,
  ) async {
    final repository = _FakeRegistroRepository();
    var creado = false;

    await _pumpRegistro(
      tester,
      RegistroPage.completar(
        repository: repository,
        pendiente: const RegistroNegocio(
          negocioNombre: 'Barbería Sol',
          slug: 'barberia-sol',
          ownerNombre: 'Ana',
        ),
        onNegocioCreado: () => creado = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.negocioCreado?.slug, 'barberia-sol');
    expect(creado, isTrue);
  });

  testWidgets('completing registration shows backend errors and allows retry', (
    tester,
  ) async {
    final repository = _FakeRegistroRepository(
      errorNegocio: const RegistroException(
        'Ese slug ya está en uso. Elige otro.',
      ),
    );
    var creado = false;

    await _pumpRegistro(
      tester,
      RegistroPage.completar(
        repository: repository,
        pendiente: const RegistroNegocio(
          negocioNombre: 'Barbería Sol',
          slug: 'barberia-sol',
          ownerNombre: 'Ana',
        ),
        onNegocioCreado: () => creado = true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ese slug ya está en uso. Elige otro.'), findsOneWidget);
    expect(find.byKey(const Key('registro-email')), findsNothing);
    expect(creado, isFalse);

    repository.errorNegocio = null;
    await tester.enterText(find.byKey(const Key('registro-slug')), 'sol-2');
    await _tapCrear(tester);

    expect(repository.negocioCreado?.slug, 'sol-2');
    expect(creado, isTrue);
  });
}

Future<void> _pumpRegistro(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
}

Future<void> _llenarFormulario(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const Key('registro-negocio-nombre')),
    'Barbería El Sol',
  );
  await tester.enterText(
    find.byKey(const Key('registro-owner-nombre')),
    'Ana López',
  );
  await tester.enterText(
    find.byKey(const Key('registro-email')),
    'ana@example.com',
  );
  await tester.enterText(
    find.byKey(const Key('registro-password')),
    'secreto123',
  );
  await tester.pump();
}

Future<void> _tapCrear(WidgetTester tester) async {
  await tester.tap(find.text('Crear mi negocio'));
  await tester.pumpAndSettle();
}

class _FakeRegistroRepository implements RegistroRepository {
  _FakeRegistroRepository({this.slugLibre = true, this.errorNegocio});

  final bool slugLibre;
  RegistroException? errorNegocio;
  String? email;
  RegistroNegocio? datosCuenta;
  RegistroNegocio? negocioCreado;

  bool get cuentaCreada => email != null;

  @override
  Future<bool?> slugDisponible(String slug) async => slugLibre;

  @override
  Future<bool> crearCuenta({
    required String email,
    required String password,
    required RegistroNegocio datos,
  }) async {
    this.email = email;
    datosCuenta = datos;
    return false;
  }

  @override
  Future<void> crearNegocio(RegistroNegocio datos) async {
    final error = errorNegocio;
    if (error != null) throw error;
    negocioCreado = datos;
  }
}
