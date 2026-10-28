import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:barberiapro/models/apartado.dart';
import 'package:barberiapro/models/cita.dart';
import 'package:barberiapro/models/configuracion_negocio.dart' as conf;
import 'package:barberiapro/services/agenda_repository.dart';
import 'package:barberiapro/services/apartados_repository.dart';
import 'package:barberiapro/services/citas_repository.dart';
import 'package:barberiapro/services/clientes_repository.dart';
import 'package:barberiapro/services/configuracion_repository.dart';
import 'package:barberiapro/services/empleados_repository.dart';
import 'package:barberiapro/services/paginacion.dart';
import 'package:barberiapro/services/servicios_repository.dart';
import 'package:barberiapro/services/sin_permiso.dart';

/// PostgREST falso: cada petición se anota y se responde con [responder].
class _Servidor {
  _Servidor(this.responder);

  final List<Map<String, dynamic>> Function(http.Request request) responder;
  final peticiones = <http.Request>[];

  late final SupabaseClient client = SupabaseClient(
    'http://localhost',
    'anon',
    authOptions: const AuthClientOptions(autoRefreshToken: false),
    httpClient: MockClient((request) async {
      peticiones.add(request);
      final filas = responder(request);
      return http.Response(
        jsonEncode(filas),
        200,
        headers: {'content-type': 'application/json'},
        request: request,
      );
    }),
  );

  Future<void> cerrar() => client.dispose();
}

/// Lo que devuelve un UPDATE/DELETE que RLS bloqueó: nada.
List<Map<String, dynamic>> _sinFilas(http.Request _) => const [];

List<Map<String, dynamic>> _unaFila(http.Request _) => const [
  {'id': 'x'},
];

void main() {
  test('exigirFilas only fails when nothing was affected', () {
    expect(() => exigirFilas(const []), throwsA(isA<SinPermisoException>()));
    exigirFilas(const [
      {'id': 'x'},
    ]);
    expect(
      const SinPermisoException().toString(),
      'No tienes permiso o el registro ya no existe.',
    );
    expect(
      mensajeDeError(const SinPermisoException(), 'Falló.'),
      mensajeSinPermiso,
    );
    expect(mensajeDeError(Exception('red'), 'Falló.'), 'Falló.');
  });

  group('updates and deletes blocked by RLS are errors', () {
    // Cada caso: (nombre, acción que hace un solo UPDATE/DELETE).
    final casos = <(String, Future<void> Function(SupabaseClient))>[
      (
        'citas.cambiarEstado',
        (c) => SupabaseCitasRepository(c).cambiarEstado(
          negocioId: 'n1',
          citaId: 'c1',
          estado: EstadoCita.llego,
        ),
      ),
      (
        'agenda.editarCita',
        (c) => SupabaseAgendaRepository(c).editarCita(
          negocioId: 'n1',
          citaId: 'c1',
          datos: DatosCita(
            clienteId: 'cl1',
            empleadoId: 'e1',
            servicioId: 's1',
            fecha: DateTime(2026, 9, 18),
            horaInicio: '10:00:00',
            horaFin: '10:45:00',
            precio: 500,
          ),
        ),
      ),
      (
        'agenda.completar',
        (c) =>
            SupabaseAgendaRepository(c)
                .completar(negocioId: 'n1', citaId: 'c1', precio: 500),
      ),
      (
        'servicios.guardar',
        (c) => SupabaseServiciosRepository(c).guardar(
          negocioId: 'n1',
          servicioId: 's1',
          datos: {'nombre': 'Corte'},
        ),
      ),
      (
        'servicios.cambiarEstado',
        (c) => SupabaseServiciosRepository(c)
            .cambiarEstado(negocioId: 'n1', servicioId: 's1', activo: false),
      ),
      (
        'empleados.guardar',
        (c) => SupabaseEmpleadosRepository(
          c,
        ).guardar(negocioId: 'n1', empleadoId: 'e1', datos: {'nombre': 'Luis'}),
      ),
      (
        'empleados.cambiarEstado',
        (c) => SupabaseEmpleadosRepository(c)
            .cambiarEstado(negocioId: 'n1', empleadoId: 'e1', activo: false),
      ),
      (
        'empleados.eliminarBloqueo',
        (c) =>
            SupabaseEmpleadosRepository(c)
                .eliminarBloqueo(negocioId: 'n1', bloqueoId: 'b1'),
      ),
      (
        'clientes.guardar',
        (c) => SupabaseClientesRepository(
          c,
        ).guardar(negocioId: 'n1', clienteId: 'cl1', datos: {'notas': 'fade'}),
      ),
      (
        'clientes.cambiarEstado',
        (c) => SupabaseClientesRepository(c)
            .cambiarEstado(negocioId: 'n1', clienteId: 'cl1', activo: false),
      ),
      (
        'configuracion.guardarNegocio',
        (c) => SupabaseConfiguracionRepository(c)
            .guardarNegocio(negocioId: 'n1', datos: {'nombre': 'La Barbería'}),
      ),
      (
        'apartados.validar',
        (c) => SupabaseApartadosRepository(c).validar(
          negocioId: 'n1',
          apartadoId: 'a1',
          monto: 100,
          metodo: MetodoPagoApartado.transferencia,
        ),
      ),
      (
        'apartados.cancelar',
        (c) =>
            SupabaseApartadosRepository(c)
                .cancelar(negocioId: 'n1', apartadoId: 'a1'),
      ),
    ];

    for (final (nombre, accion) in casos) {
      test('$nombre throws with 0 rows and passes with 1', () async {
        final bloqueado = _Servidor(_sinFilas);
        addTearDown(bloqueado.cerrar);
        await expectLater(
          accion(bloqueado.client),
          throwsA(isA<SinPermisoException>()),
        );
        final peticion = bloqueado.peticiones.single;
        expect(peticion.method, anyOf('PATCH', 'DELETE'));
        expect(peticion.url.queryParameters['select'], 'id');

        final permitido = _Servidor(_unaFila);
        addTearDown(permitido.cerrar);
        await accion(permitido.client);
      });
    }
  });

  test('replacing schedules and services tolerates deleting nothing', () async {
    final servidor = _Servidor(_sinFilas);
    addTearDown(servidor.cerrar);
    final empleados = SupabaseEmpleadosRepository(servidor.client);
    final configuracion = SupabaseConfiguracionRepository(servidor.client);

    await empleados.guardarHorario(
      negocioId: 'n1',
      empleadoId: 'e1',
      dias: const [],
    );
    await empleados.guardarServicios(
      negocioId: 'n1',
      empleadoId: 'e1',
      servicioIds: {'s1'},
    );
    await configuracion.guardarHorarios(
      negocioId: 'n1',
      abiertos: const [
        conf.HorarioDia(diaSemana: 1, apertura: 540, cierre: 1080),
      ],
    );
    expect(servidor.peticiones.map((r) => r.method), contains('DELETE'));
  });

  test('leerTodasLasPaginas keeps asking until a short page', () async {
    final rangos = <(int, int)>[];
    final filas = await leerTodasLasPaginas((desde, hasta) async {
      rangos.add((desde, hasta));
      final total = 5;
      return [
        for (var i = desde; i <= hasta && i < total; i++) {'id': '$i'},
      ];
    }, tamano: 2);
    expect(rangos, [(0, 1), (2, 3), (4, 5)]);
    expect(filas.map((f) => f['id']), ['0', '1', '2', '3', '4']);
  });

  List<Map<String, dynamic>> clientesPaginados(http.Request request) {
    if (!request.url.path.endsWith('/clientes')) return const [];
    const total = 1003;
    final desde = int.parse(request.url.queryParameters['offset'] ?? '0');
    final cuantos = int.parse(request.url.queryParameters['limit'] ?? '1000');
    return [
      for (var i = desde; i < desde + cuantos && i < total; i++)
        {'id': 'c$i', 'nombre': 'Cliente $i', 'activo': true},
    ];
  }

  test('clientes.listar reads past the 1000-row limit', () async {
    final servidor = _Servidor(clientesPaginados);
    addTearDown(servidor.cerrar);

    final clientes = await SupabaseClientesRepository(servidor.client)
        .listar('n1');

    expect(clientes, hasLength(1003));
    expect(clientes.last.id, 'c1002');
    expect(servidor.peticiones, hasLength(2));
  });

  test('the appointment catalog reads every client', () async {
    final servidor = _Servidor(clientesPaginados);
    addTearDown(servidor.cerrar);

    final catalogo = await SupabaseAgendaRepository(servidor.client)
        .catalogo('n1');

    expect(catalogo.clientes, hasLength(1003));
    expect(
      servidor.peticiones.where((r) => r.url.path.endsWith('/clientes')),
      hasLength(2),
    );
  });
}
