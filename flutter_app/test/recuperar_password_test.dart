import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

import 'package:barberiapro/pages/login_page.dart';
import 'package:barberiapro/pages/recuperar_password_page.dart';
import 'package:barberiapro/services/password_repository.dart';

void main() {
  test('invited accounts must set a password until the flag is cleared', () {
    expect(debeFijarPassword({debeFijarPasswordKey: true}), isTrue);
    expect(debeFijarPassword({debeFijarPasswordKey: null}), isFalse);
    expect(debeFijarPassword({}), isFalse);
    expect(debeFijarPassword(null), isFalse);
  });

  test('email rate limits tell how many seconds to wait', () {
    expect(
      mensajeEsperaCorreo(
        const AuthException(
          'For security purposes, you can only request this after 14 seconds.',
          statusCode: '429',
        ),
      ),
      'Espera 14 segundos antes de pedir otro código.',
    );
    expect(
      mensajeEsperaCorreo(const AuthException('Error sending recovery email')),
      isNull,
    );
  });

  testWidgets('login opens password recovery with the typed email', (
    tester,
  ) async {
    await _pump(
      tester,
      LoginPage(passwordRepository: _FakePasswordRepository()),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Correo'),
      'ana@example.com',
    );
    await tester.tap(find.text('¿Olvidaste tu contraseña?'));
    await tester.pumpAndSettle();

    expect(find.text('Recuperar contraseña'), findsOneWidget);
    expect(find.text('ana@example.com'), findsOneWidget);
  });

  testWidgets('recovery validates the email before sending a code', (
    tester,
  ) async {
    final repository = _FakePasswordRepository();
    await _pump(tester, RecuperarPasswordPage(repository: repository));

    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa un correo válido.'), findsOneWidget);
    expect(repository.codigosEnviados, isEmpty);
  });

  testWidgets('code and new password reset the account and close the page', (
    tester,
  ) async {
    final repository = _FakePasswordRepository();
    await _pump(
      tester,
      Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => RecuperarPasswordPage(repository: repository),
              ),
            ),
            child: const Text('abrir'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('recuperar-email')),
      ' ana@example.com ',
    );
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    expect(repository.codigosEnviados, ['ana@example.com']);
    expect(find.text('Revisa tu correo'), findsOneWidget);

    await tester.tap(find.text('Reenviar código'));
    await tester.pumpAndSettle();
    expect(repository.codigosEnviados, hasLength(2));
    expect(find.text('Te enviamos un código nuevo.'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('recuperar-codigo')), '12');
    await tester.enterText(
      find.byKey(const Key('recuperar-password')),
      'nueva1234',
    );
    await tester.enterText(
      find.byKey(const Key('recuperar-confirmacion')),
      'otra1234',
    );
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();
    expect(
      find.text('Escribe el código de 6 dígitos que te enviamos.'),
      findsOneWidget,
    );
    expect(find.text('Las contraseñas no coinciden.'), findsOneWidget);
    expect(repository.codigoVerificado, isNull);

    await tester.enterText(find.byKey(const Key('recuperar-codigo')), '123456');
    await tester.enterText(
      find.byKey(const Key('recuperar-confirmacion')),
      'nueva1234',
    );
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();

    expect(repository.emailVerificado, 'ana@example.com');
    expect(repository.codigoVerificado, '123456');
    expect(repository.passwordNueva, 'nueva1234');
    expect(find.text('abrir'), findsOneWidget);
    expect(find.text('Contraseña actualizada.'), findsOneWidget);
  });

  testWidgets('wrong recovery code shows the backend error', (tester) async {
    final repository = _FakePasswordRepository(
      errorCodigo: const PasswordException(
        'El código no es válido o ya venció. Pide uno nuevo.',
      ),
    );
    await _pump(
      tester,
      RecuperarPasswordPage(
        repository: repository,
        emailInicial: 'ana@example.com',
      ),
    );
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();

    await _llenarPassword(tester, codigo: '000000');
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();

    expect(
      find.text('El código no es válido o ya venció. Pide uno nuevo.'),
      findsOneWidget,
    );
    expect(repository.passwordNueva, isNull);
  });

  testWidgets('a used code is not sent again when saving the password fails', (
    tester,
  ) async {
    final repository = _FakePasswordRepository(
      errorPassword: const PasswordException(
        'La contraseña no cumple los requisitos de seguridad.',
      ),
    );
    await _pump(
      tester,
      RecuperarPasswordPage(
        repository: repository,
        emailInicial: 'ana@example.com',
      ),
    );
    await tester.tap(find.text('Enviar código'));
    await tester.pumpAndSettle();
    await _llenarPassword(tester, codigo: '123456');
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();

    expect(
      find.text('La contraseña no cumple los requisitos de seguridad.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('recuperar-codigo')), findsNothing);

    repository.errorPassword = null;
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();

    expect(repository.verificaciones, 1);
    expect(repository.passwordNueva, 'nueva1234');
  });

  testWidgets('invited barber sets a password without a code', (tester) async {
    final repository = _FakePasswordRepository();
    var listo = false;
    var salio = false;
    await _pump(
      tester,
      RecuperarPasswordPage.fijar(
        repository: repository,
        onListo: () => listo = true,
        onSalir: () => salio = true,
      ),
    );

    expect(find.text('Crea tu contraseña'), findsOneWidget);
    expect(find.byKey(const Key('recuperar-codigo')), findsNothing);
    expect(find.text('Reenviar código'), findsNothing);

    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();
    expect(
      find.text('La contraseña debe tener al menos 8 caracteres.'),
      findsOneWidget,
    );

    await _llenarPassword(tester);
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();

    expect(repository.verificaciones, 0);
    expect(repository.passwordNueva, 'nueva1234');
    expect(listo, isTrue);

    await tester.tap(find.text('Cerrar sesión'));
    expect(salio, isTrue);
  });

  testWidgets('invited barber activates the account with the invite code', (
    tester,
  ) async {
    final repository = _FakePasswordRepository();
    await _pump(tester, LoginPage(passwordRepository: repository));

    await tester.tap(find.byKey(const Key('login-invitacion')));
    await tester.pumpAndSettle();
    expect(find.text('Activar invitación'), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('recuperar-email')),
      'barbero@example.com',
    );
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();

    // La invitación ya trae el código: no se envía otro.
    expect(repository.codigosEnviados, isEmpty);
    expect(find.text('Reenviar código'), findsNothing);

    await _llenarPassword(tester, codigo: '123456');
    await tester.tap(find.text('Guardar contraseña'));
    await tester.pumpAndSettle();

    expect(repository.invitacionesVerificadas, 1);
    expect(repository.emailVerificado, 'barbero@example.com');
    expect(repository.codigoVerificado, '123456');
    expect(repository.passwordNueva, 'nueva1234');
  });
}

Future<void> _pump(WidgetTester tester, Widget page) async {
  tester.view.physicalSize = const Size(1000, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: page));
}

Future<void> _llenarPassword(WidgetTester tester, {String? codigo}) async {
  if (codigo != null) {
    await tester.enterText(find.byKey(const Key('recuperar-codigo')), codigo);
  }
  await tester.enterText(
    find.byKey(const Key('recuperar-password')),
    'nueva1234',
  );
  await tester.enterText(
    find.byKey(const Key('recuperar-confirmacion')),
    'nueva1234',
  );
  await tester.pump();
}

class _FakePasswordRepository implements PasswordRepository {
  _FakePasswordRepository({this.errorCodigo, this.errorPassword});

  final PasswordException? errorCodigo;
  PasswordException? errorPassword;
  final List<String> codigosEnviados = [];
  int verificaciones = 0;
  int invitacionesVerificadas = 0;
  String? emailVerificado;
  String? codigoVerificado;
  String? passwordNueva;

  @override
  Future<void> enviarCodigo(String email) async => codigosEnviados.add(email);

  @override
  Future<void> verificarCodigo({
    required String email,
    required String codigo,
  }) async {
    verificaciones++;
    final error = errorCodigo;
    if (error != null) throw error;
    emailVerificado = email;
    codigoVerificado = codigo;
  }

  @override
  Future<void> verificarInvitacion({
    required String email,
    required String codigo,
  }) async {
    invitacionesVerificadas++;
    await verificarCodigo(email: email, codigo: codigo);
  }

  @override
  Future<void> cambiarPassword(String password) async {
    final error = errorPassword;
    if (error != null) throw error;
    passwordNueva = password;
  }
}
