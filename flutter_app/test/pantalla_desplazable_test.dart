import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/widgets/pantalla_desplazable.dart';
import 'package:barberiapro/pages/login_page.dart';

void main() {
  testWidgets('la rueda sobre el fondo (fuera de la tarjeta) desplaza', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PantallaDesplazable(
            child: SizedBox(
              width: 400,
              child: Column(
                children: [
                  for (var i = 0; i < 30; i++) Text('Campo $i'),
                  const Text('Último campo'),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final posicion = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position;
    expect(posicion.pixels, 0);

    // Borde izquierdo: fondo, lejos de la columna de 400 px centrada.
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        position: Offset(20, 250),
        scrollDelta: Offset(0, 300),
      ),
    );
    await tester.pumpAndSettle();
    expect(posicion.pixels, greaterThan(0));
  });

  testWidgets('si el contenido cabe, queda centrado', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: PantallaDesplazable(child: Text('Entrar'))),
      ),
    );
    final centro = tester.getCenter(find.text('Entrar'));
    expect(centro.dx, closeTo(600, 1));
    expect(centro.dy, closeTo(400, 1));
  });

  testWidgets('el inicio de sesión cabe en un celular de 360 px', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: LoginPage()));
    await tester.pumpAndSettle();

    // Sin desbordes (fallarían la prueba) y la tarjeta dentro de la pantalla.
    final ingresar = tester.getRect(find.text('Ingresar'));
    expect(ingresar.left, greaterThanOrEqualTo(0));
    expect(ingresar.right, lessThanOrEqualTo(360));
    expect(tester.takeException(), isNull);
  });
}
