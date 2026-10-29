import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/cita.dart';
import '../models/cliente.dart';
import '../utils/formato.dart';
import 'paginacion.dart';
import 'sin_permiso.dart';

/// Cliente genérico para quien se atiende sin registrarse ("Atender ahora").
const nombreClienteDePaso = 'Cliente de paso';

/// Servicio tal como lo necesita el formulario de citas.
class ServicioAgenda {
  const ServicioAgenda({
    required this.id,
    required this.nombre,
    required this.precio,
    required this.duracionMinutos,
  });

  final String id;
  final String nombre;
  final num precio;
  final int duracionMinutos;

  factory ServicioAgenda.fromMap(Map<String, dynamic> map) => ServicioAgenda(
    id: map['id'].toString(),
    nombre: map['nombre']?.toString() ?? '',
    precio: num.tryParse(map['precio']?.toString() ?? '') ?? 0,
    duracionMinutos:
        int.tryParse(map['duracion_minutos']?.toString() ?? '') ?? 0,
  );
}

/// Barbero (fila de `empleados`) para elegir en una cita.
class BarberoAgenda {
  const BarberoAgenda({required this.id, required this.nombre});

  final String id;
  final String nombre;
}

/// Lo que hace falta para crear o editar una cita.
class CatalogoAgenda {
  const CatalogoAgenda({
    this.clientes = const [],
    this.servicios = const [],
    this.barberos = const [],
    this.serviciosPorBarbero = const {},
  });

  final List<Cliente> clientes;
  final List<ServicioAgenda> servicios;
  final List<BarberoAgenda> barberos;

  /// Filas de `empleado_servicios`. Un barbero sin filas hace todos.
  final Map<String, Set<String>> serviciosPorBarbero;

  bool barberoHace(String empleadoId, String servicioId) {
    final servicios = serviciosPorBarbero[empleadoId];
    return servicios == null || servicios.isEmpty
        ? true
        : servicios.contains(servicioId);
  }
}

/// Apartado (depósito) registrado para una cita.
class ApartadoCita {
  const ApartadoCita({
    required this.monto,
    required this.estado,
    this.metodoPago = '',
    this.referencia = '',
  });

  final num monto;
  final String estado;
  final String metodoPago;
  final String referencia;

  String get estadoEtiqueta => switch (estado) {
    'PAGADO' => 'Pagado',
    'CANCELADO' => 'Cancelado',
    _ => 'Pendiente',
  };

  factory ApartadoCita.fromMap(Map<String, dynamic> map) => ApartadoCita(
    monto: num.tryParse(map['monto']?.toString() ?? '') ?? 0,
    estado: map['estado']?.toString() ?? 'PENDIENTE',
    metodoPago: map['metodo_pago']?.toString() ?? '',
    referencia: map['referencia']?.toString() ?? '',
  );
}

/// Datos editables de una cita.
class DatosCita {
  const DatosCita({
    required this.clienteId,
    required this.empleadoId,
    required this.servicioId,
    required this.fecha,
    required this.horaInicio,
    required this.horaFin,
    required this.precio,
    this.notas = '',
  });

  final String clienteId;
  final String empleadoId;
  final String servicioId;
  final DateTime fecha;

  /// 'HH:MM:SS'
  final String horaInicio;
  final String horaFin;
  final num precio;
  final String notas;

  Map<String, Object?> toMap() => {
    'cliente_id': clienteId,
    'empleado_id': empleadoId,
    'servicio_id': servicioId,
    'fecha': formatoFechaIso(fecha),
    'hora_inicio': horaInicio,
    'hora_fin': horaFin,
    'precio': precio,
    'notas': notas.trim().isEmpty ? null : notas.trim(),
  };
}

abstract interface class AgendaRepository {
  /// Clientes, servicios y barberos activos del negocio.
  Future<CatalogoAgenda> catalogo(String negocioId);

  Future<Cliente> crearCliente({
    required String negocioId,
    required String nombre,
    String telefono = '',
  });

  /// Cliente "Cliente de paso" del negocio (por nombre exacto); lo crea si
  /// no existe.
  Future<Cliente> clienteDePaso(String negocioId);

  /// El dueño que trabaja solo se registra como barbero: crea (o reactiva)
  /// la ficha de empleado ligada a su perfil.
  Future<BarberoAgenda> registrarDuenoComoBarbero(String negocioId);

  /// Crea la cita, por defecto en estado PENDIENTE. "Atender ahora" la crea
  /// en LLEGO (el trigger de 006 solo valida los UPDATE de estado).
  Future<void> crearCita({
    required String negocioId,
    required DatosCita datos,
    EstadoCita estado = EstadoCita.pendiente,
  });

  Future<void> editarCita({
    required String negocioId,
    required String citaId,
    required DatosCita datos,
  });

  /// Marca la cita como COMPLETADA y guarda el cobro (precio final, método
  /// de pago y propina) en un solo update.
  Future<void> completar({
    required String negocioId,
    required String citaId,
    required num precio,
    MetodoPago metodoPago = MetodoPago.efectivo,
    num propina = 0,
  });

  /// Apartado activo de la cita (o el último, si todos están cancelados).
  Future<ApartadoCita?> apartadoDeCita({
    required String negocioId,
    required String citaId,
  });
}

class SupabaseAgendaRepository implements AgendaRepository {
  const SupabaseAgendaRepository(this._client);

  final SupabaseClient _client;

  @override
  Future<CatalogoAgenda> catalogo(String negocioId) async {
    final resultados = await Future.wait([
      // Los clientes pueden pasar del límite de filas de PostgREST.
      leerTodasLasPaginas(
        (desde, hasta) => _client
            .from('clientes')
            .select('id, nombre, telefono, email, notas, activo')
            .eq('negocio_id', negocioId)
            .eq('activo', true)
            .order('nombre')
            .order('id')
            .range(desde, hasta),
      ),
      _client
          .from('servicios')
          .select('id, nombre, precio, duracion_minutos')
          .eq('negocio_id', negocioId)
          .eq('activo', true)
          .order('nombre'),
      _client
          .from('empleados')
          .select('id, nombre')
          .eq('negocio_id', negocioId)
          .eq('activo', true)
          .order('nombre'),
      _client
          .from('empleado_servicios')
          .select('empleado_id, servicio_id')
          .eq('negocio_id', negocioId),
    ]);

    final serviciosPorBarbero = <String, Set<String>>{};
    for (final row in resultados[3]) {
      serviciosPorBarbero
          .putIfAbsent(row['empleado_id'].toString(), () => <String>{})
          .add(row['servicio_id'].toString());
    }

    return CatalogoAgenda(
      clientes: resultados[0].map(Cliente.fromMap).toList(growable: false),
      servicios: resultados[1]
          .map(ServicioAgenda.fromMap)
          .toList(growable: false),
      barberos: resultados[2]
          .map(
            (row) => BarberoAgenda(
              id: row['id'].toString(),
              nombre: row['nombre']?.toString() ?? '',
            ),
          )
          .toList(growable: false),
      serviciosPorBarbero: serviciosPorBarbero,
    );
  }

  @override
  Future<Cliente> crearCliente({
    required String negocioId,
    required String nombre,
    String telefono = '',
  }) async {
    final row = await _client
        .from('clientes')
        .insert({
          'negocio_id': negocioId,
          'nombre': nombre.trim(),
          'telefono': telefono.trim().isEmpty ? null : telefono.trim(),
        })
        .select('id, nombre, telefono, email, notas, activo')
        .single();
    return Cliente.fromMap(row);
  }

  @override
  Future<BarberoAgenda> registrarDuenoComoBarbero(String negocioId) async {
    final perfilId = _client.auth.currentUser?.id;
    if (perfilId == null) throw StateError('Inicia sesión de nuevo.');

    final existente = await _client
        .from('empleados')
        .select('id, nombre')
        .eq('negocio_id', negocioId)
        .eq('perfil_id', perfilId)
        .maybeSingle();
    if (existente != null) {
      await _client
          .from('empleados')
          .update({'activo': true})
          .eq('negocio_id', negocioId)
          .eq('id', existente['id']);
      return BarberoAgenda(
        id: existente['id'].toString(),
        nombre: existente['nombre'].toString(),
      );
    }

    final perfil = await _client
        .from('perfiles')
        .select('nombre, telefono')
        .eq('id', perfilId)
        .single();
    final creado = await _client
        .from('empleados')
        .insert({
          'negocio_id': negocioId,
          'perfil_id': perfilId,
          'nombre': perfil['nombre'],
          'telefono': perfil['telefono'],
        })
        .select('id, nombre')
        .single();
    return BarberoAgenda(
      id: creado['id'].toString(),
      nombre: creado['nombre'].toString(),
    );
  }

  @override
  Future<Cliente> clienteDePaso(String negocioId) async {
    final rows = await _client
        .from('clientes')
        .select('id, nombre, telefono, email, notas, activo')
        .eq('negocio_id', negocioId)
        .eq('nombre', nombreClienteDePaso)
        .order('created_at')
        .limit(1);
    if (rows.isNotEmpty) return Cliente.fromMap(rows.first);
    return crearCliente(negocioId: negocioId, nombre: nombreClienteDePaso);
  }

  @override
  Future<void> crearCita({
    required String negocioId,
    required DatosCita datos,
    EstadoCita estado = EstadoCita.pendiente,
  }) async {
    await _client.from('citas').insert({
      ...datos.toMap(),
      'negocio_id': negocioId,
      'estado': estado.valor,
    });
  }

  @override
  Future<void> editarCita({
    required String negocioId,
    required String citaId,
    required DatosCita datos,
  }) async {
    // El cliente de una cita no cambia al editarla.
    final cambios = datos.toMap()..remove('cliente_id');
    final filas = await _client
        .from('citas')
        .update(cambios)
        .eq('negocio_id', negocioId)
        .eq('id', citaId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<void> completar({
    required String negocioId,
    required String citaId,
    required num precio,
    MetodoPago metodoPago = MetodoPago.efectivo,
    num propina = 0,
  }) async {
    final filas = await _client
        .from('citas')
        .update({
          'estado': EstadoCita.completada.valor,
          'precio': precio,
          'metodo_pago': metodoPago.valor,
          'propina': propina,
        })
        .eq('negocio_id', negocioId)
        .eq('id', citaId)
        .select('id');
    exigirFilas(filas);
  }

  @override
  Future<ApartadoCita?> apartadoDeCita({
    required String negocioId,
    required String citaId,
  }) async {
    final rows = await _client
        .from('apartados')
        .select('monto, estado, metodo_pago, referencia, created_at')
        .eq('negocio_id', negocioId)
        .eq('cita_id', citaId)
        .order('created_at', ascending: false);
    if (rows.isEmpty) return null;
    final activo = rows.firstWhere(
      (row) => row['estado'] != 'CANCELADO',
      orElse: () => rows.first,
    );
    return ApartadoCita.fromMap(activo);
  }
}
