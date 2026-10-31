import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/utils/navegador.dart';
import 'package:barberiapro/widgets/instalar_app.dart';

Future<void> _abrir(WidgetTester tester, TarjetaInstalar tarjeta) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ListView(children: [tarjeta])),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('con Chrome o Brave: un botón instala la app', (tester) async {
    var estado = Instalacion.conBoton;
    var pedidos = 0;
    await _abrir(
      tester,
      TarjetaInstalar(
        estado: () => estado,
        instalar: () async {
          pedidos++;
          estado = Instalacion.instalada;
          return true;
        },
        alCambiar: (_) {},
        leer: (_) => null,
        guardar: (_, _) {},
      ),
    );

    expect(find.text('Instala Citabox en tu celular'), findsOneWidget);
    await tester.tap(find.text('Instalar Citabox'));
    await tester.pumpAndSettle();

    expect(pedidos, 1);
    expect(find.byKey(const Key('tarjeta-instalar')), findsNothing);
    expect(
      find.text('Listo: Citabox quedó en tu pantalla de inicio.'),
      findsOneWidget,
    );
  });

  testWidgets('en iPhone muestra los dos pasos', (tester) async {
    await _abrir(
      tester,
      TarjetaInstalar(
        estado: () => Instalacion.iphone,
        alCambiar: (_) {},
        leer: (_) => null,
        guardar: (_, _) {},
      ),
    );
    expect(find.text('Agrega Citabox a tu pantalla de inicio'), findsOneWidget);
    expect(find.text('Toca Compartir, abajo en la pantalla.'), findsOneWidget);
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
    expect(find.text('Instalar Citabox'), findsNothing);
  });

  testWidgets('otros navegadores de Android: desde el menú', (tester) async {
    await _abrir(
      tester,
      TarjetaInstalar(
        estado: () => Instalacion.menuDelNavegador,
        alCambiar: (_) {},
        leer: (_) => null,
        guardar: (_, _) {},
      ),
    );
    expect(find.text('Toca el menú ⋮ del navegador.'), findsOneWidget);
  });

  testWidgets('el botón aparece cuando el navegador avisa tarde', (
    tester,
  ) async {
    var estado = Instalacion.instalada;
    late void Function() avisar;
    await _abrir(
      tester,
      TarjetaInstalar(
        estado: () => estado,
        alCambiar: (f) => avisar = f,
        leer: (_) => null,
        guardar: (_, _) {},
      ),
    );
    expect(find.byKey(const Key('tarjeta-instalar')), findsNothing);

    estado = Instalacion.conBoton;
    avisar();
    await tester.pump();
    expect(find.text('Instalar Citabox'), findsOneWidget);
  });

  testWidgets('"No ahora" la oculta y lo recuerda', (tester) async {
    final guardado = <String, String>{};
    await _abrir(
      tester,
      TarjetaInstalar(
        estado: () => Instalacion.iphone,
        alCambiar: (_) {},
        leer: (clave) => guardado[clave],
        guardar: (clave, valor) => guardado[clave] = valor,
      ),
    );
    await tester.tap(find.byKey(const Key('instalar-cerrar')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tarjeta-instalar')), findsNothing);
    expect(guardado[TarjetaInstalar.claveOculta], '1');

    // Al volver a entrar sigue oculta.
    await _abrir(
      tester,
      TarjetaInstalar(
        key: const Key('otra'),
        estado: () => Instalacion.iphone,
        alCambiar: (_) {},
        leer: (clave) => guardado[clave],
        guardar: (clave, valor) => guardado[clave] = valor,
      ),
    );
    expect(find.byKey(const Key('tarjeta-instalar')), findsNothing);
  });

  testWidgets('ya instalada (o fuera de la web): no aparece', (tester) async {
    await _abrir(tester, const TarjetaInstalar());
    expect(find.byKey(const Key('tarjeta-instalar')), findsNothing);
  });
}
