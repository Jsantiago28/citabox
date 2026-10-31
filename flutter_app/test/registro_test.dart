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
    await tester.ensureVisible(find.text('Registrar mi negocio'));
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

  testWidgets('registration requires accepting terms and privacy', (
    tester,
  ) async {
    final repository = _FakeRegistroRepository();
    await _pumpRegistro(tester, RegistroPage(repository: repository));
    await _llenarFormulario(tester);
    await _aceptarTerminos(tester); // la desmarca

    await _tapCrear(tester);

    expect(
      find.text('Debes aceptar los términos y la privacidad.'),
      findsOneWidget,
    );
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

  testWidgets('email code confirms the account and closes registration', (
    tester,
  ) async {
    final repository = _FakeRegistroRepository();
    await _pumpRegistro(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => RegistroPage(repository: repository),
            ),
          ),
          child: const Text('abrir'),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
    await _llenarFormulario(tester);
    await _tapCrear(tester);

    await tester.enterText(find.byKey(const Key('registro-codigo')), '12');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(
      find.text('Escribe el código que te enviamos por correo.'),
      findsOneWidget,
    );
    expect(repository.codigoVerificado, isNull);

    await tester.tap(find.text('Reenviar código'));
    await tester.pumpAndSettle();
    expect(repository.reenvios, 1);
    expect(find.text('Te enviamos un código nuevo.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('registro-codigo')), '123456');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(repository.codigoVerificado, '123456');
    expect(find.text('abrir'), findsOneWidget);
  });

  testWidgets('wrong email code shows the backend error', (tester) async {
    final repository = _FakeRegistroRepository(
      errorCodigo: const RegistroException(
        'El código no es válido o ya venció. Pide uno nuevo.',
      ),
    );
    await _pumpRegistro(tester, RegistroPage(repository: repository));
    await _llenarFormulario(tester);
    await _tapCrear(tester);

    await tester.enterText(find.byKey(const Key('registro-codigo')), '000000');
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();

    expect(
      find.text('El código no es válido o ya venció. Pide uno nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Revisa tu correo'), findsOneWidget);
  });

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
  await _aceptarTerminos(tester);
  await tester.pump();
}

Future<void> _aceptarTerminos(WidgetTester tester) async {
  final casilla = find.descendant(
    of: find.byKey(const Key('registro-consentimiento')),
    matching: find.byType(Checkbox),
  );
  await tester.ensureVisible(casilla);
  await tester.tap(casilla);
  await tester.pump();
}

Future<void> _tapCrear(WidgetTester tester) async {
  await tester.tap(find.text('Crear mi negocio'));
  await tester.pumpAndSettle();
}

class _FakeRegistroRepository implements RegistroRepository {
  _FakeRegistroRepository({
    this.slugLibre = true,
    this.errorNegocio,
    this.errorCodigo,
  });

  final bool slugLibre;
  RegistroException? errorNegocio;
  final RegistroException? errorCodigo;
  String? codigoVerificado;
  int reenvios = 0;
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
  Future<void> verificarCodigo({
    required String email,
    required String codigo,
  }) async {
    final error = errorCodigo;
    if (error != null) throw error;
    codigoVerificado = codigo;
  }

  @override
  Future<void> reenviarCodigo(String email) async => reenvios++;

  @override
  Future<void> crearNegocio(RegistroNegocio datos) async {
    final error = errorNegocio;
    if (error != null) throw error;
    negocioCreado = datos;
  }
}
