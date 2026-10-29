import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/pages/verificacion_mfa_page.dart';
import 'package:barberiapro/services/mfa_repository.dart';
import 'package:barberiapro/widgets/seguridad_cuenta_card.dart';

void main() {
  testWidgets('activar: muestra el secreto en grupos y verifica el código', (
    tester,
  ) async {
    final repo = _FakeMfa();
    await _pump(tester, SeguridadCuentaCard(repository: repo));

    await tester.tap(find.text('Activar verificación en dos pasos'));
    await tester.pumpAndSettle();
    expect(find.text('ABCD EFGH IJ'), findsOneWidget);
    expect(find.textContaining('Ingresar clave'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('mfa-codigo')), '123456');
    await tester.tap(find.text('Activar'));
    await tester.pumpAndSettle();

    expect(repo.verificados, [('nuevo', '123456')]);
    expect(find.text('Activa'), findsOneWidget);
  });

  testWidgets('desactivar: pide un código válido y luego quita el factor', (
    tester,
  ) async {
    final repo = _FakeMfa(activo: 'f1');
    await _pump(tester, SeguridadCuentaCard(repository: repo));
    expect(find.text('Activa'), findsOneWidget);

    await tester.tap(find.text('Desactivar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('mfa-codigo')), '654321');
    await tester.tap(find.text('Confirmar y desactivar'));
    await tester.pumpAndSettle();

    expect(repo.verificados, [('f1', '654321')]);
    expect(repo.desactivados, ['f1']);
    expect(find.text('Activar verificación en dos pasos'), findsOneWidget);
  });

  testWidgets('desactivar con código erróneo no quita el factor', (
    tester,
  ) async {
    final repo = _FakeMfa(activo: 'f1', codigoCorrecto: '111111');
    await _pump(tester, SeguridadCuentaCard(repository: repo));

    await tester.tap(find.text('Desactivar'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('mfa-codigo')), '222222');
    await tester.tap(find.text('Confirmar y desactivar'));
    await tester.pumpAndSettle();

    expect(repo.desactivados, isEmpty);
    expect(find.textContaining('no es correcto'), findsOneWidget);
  });

  testWidgets('login: pide el código antes del panel y luego lo muestra', (
    tester,
  ) async {
    final repo = _FakeMfa(pendiente: 'f1', codigoCorrecto: '123456');
    await _pump(
      tester,
      MfaGate(repository: repo, onSalir: () {}, child: const Text('Panel')),
    );
    expect(
      find.text('Escribe el código de tu app de autenticación'),
      findsOneWidget,
    );
    expect(find.text('Cerrar sesión'), findsOneWidget);
    expect(find.text('Panel'), findsNothing);

    await tester.enterText(find.byType(TextField), '123456');
    await tester.tap(find.text('Verificar'));
    await tester.pumpAndSettle();
    expect(find.text('Panel'), findsOneWidget);
  });

  testWidgets('login: código erróneo muestra el mensaje y no deja pasar', (
    tester,
  ) async {
    final repo = _FakeMfa(pendiente: 'f1', codigoCorrecto: '123456');
    await _pump(
      tester,
      MfaGate(repository: repo, onSalir: () {}, child: const Text('Panel')),
    );
    await tester.enterText(find.byType(TextField), '000000');
    await tester.tap(find.text('Verificar'));
    await tester.pumpAndSettle();

    expect(find.textContaining('no es correcto'), findsOneWidget);
    expect(find.text('Panel'), findsNothing);
  });

  testWidgets('sin factor pendiente entra directo al panel', (tester) async {
    await _pump(
      tester,
      MfaGate(
        repository: _FakeMfa(),
        onSalir: () {},
        child: const Text('Panel'),
      ),
    );
    expect(find.text('Panel'), findsOneWidget);
  });
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(900, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: child is SeguridadCuentaCard
          ? Scaffold(body: SingleChildScrollView(child: child))
          : child,
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeMfa implements MfaRepository {
  _FakeMfa({this.activo, this.pendiente, this.codigoCorrecto});

  String? activo;
  final String? pendiente;
  final String? codigoCorrecto;
  final verificados = <(String, String)>[];
  final desactivados = <String>[];

  @override
  Future<String?> factorActivo() async => activo;

  @override
  String? factorPendiente() => pendiente;

  @override
  Future<MfaEnrolamiento> iniciarActivacion() async =>
      const MfaEnrolamiento(factorId: 'nuevo', secreto: 'ABCDEFGHIJ');

  @override
  Future<void> verificar({
    required String factorId,
    required String codigo,
  }) async {
    if (codigoCorrecto != null && codigo != codigoCorrecto) {
      throw const MfaException('El código no es correcto.');
    }
    verificados.add((factorId, codigo));
  }

  @override
  Future<void> desactivar(String factorId) async => desactivados.add(factorId);
}
