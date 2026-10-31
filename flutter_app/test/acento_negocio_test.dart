import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barberiapro/models/reserva.dart';
import 'package:barberiapro/theme.dart';
import 'package:barberiapro/widgets/reserva_publica.dart';

void main() {
  test('el color del negocio se lee del catálogo', () {
    final negocio = NegocioPublico.fromMap({
      'nombre': 'Spa Luz',
      'slug': 'spa-luz',
      'color_principal': '#1E88E5',
    });
    expect(negocio.colorPrincipal, '#1E88E5');
  });

  test('desdeHex: válido, vacío, inválido o demasiado claro', () {
    expect(AcentoNegocio.desdeHex('#1E88E5'), const Color(0xFF1E88E5));
    expect(AcentoNegocio.desdeHex('1e88e5'), const Color(0xFF1E88E5));
    expect(AcentoNegocio.desdeHex(''), Marca.dorado);
    expect(AcentoNegocio.desdeHex('azul'), Marca.dorado);
    // Casi blanco no se vería sobre las tarjetas blancas.
    expect(AcentoNegocio.desdeHex('#FAFAFA'), Marca.dorado);
  });

  testWidgets('las piezas de la reserva usan el acento del negocio', (
    tester,
  ) async {
    late Color acento;
    late Color claro;
    Widget probar() => Builder(
      builder: (context) {
        acento = acentoDe(context);
        claro = acentoClaroDe(context);
        return const SizedBox.shrink();
      },
    );

    await tester.pumpWidget(probar());
    expect(acento, Marca.dorado);
    expect(claro, Marca.doradoClaro);

    await tester.pumpWidget(
      AcentoNegocio(color: const Color(0xFF1E88E5), child: probar()),
    );
    expect(acento, const Color(0xFF1E88E5));
    expect(claro, Color.lerp(const Color(0xFF1E88E5), Colors.white, 0.35));
  });
}
