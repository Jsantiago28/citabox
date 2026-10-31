import '../utils/formato.dart';

/// Tablas auditadas, en el orden en que se ofrecen como filtro.
const tablasAuditadas = [
  'citas',
  'apartados',
  'clientes',
  'servicios',
  'empleados',
  'perfiles',
];

/// Una fila de `auditoria` con el nombre de quien hizo el cambio resuelto.
class RegistroAuditoria {
  const RegistroAuditoria({
    required this.id,
    required this.tabla,
    required this.filaId,
    required this.accion,
    required this.fecha,
    this.antes,
    this.despues,
    this.usuarioId,
    this.usuarioNombre,
  });

  factory RegistroAuditoria.fromMap(
    Map<String, dynamic> map, {
    String? usuarioNombre,
  }) {
    return RegistroAuditoria(
      id: '${map['id']}',
      tabla: map['tabla'] as String,
      filaId: '${map['fila_id']}',
      accion: map['accion'] as String,
      antes: (map['antes'] as Map?)?.cast<String, dynamic>(),
      despues: (map['despues'] as Map?)?.cast<String, dynamic>(),
      usuarioId: map['usuario_id'] as String?,
      usuarioNombre: usuarioNombre,
      fecha: DateTime.parse(map['fecha'] as String).toLocal(),
    );
  }

  final String id;
  final String tabla;
  final String filaId;

  /// INSERT, UPDATE o DELETE.
  final String accion;
  final DateTime fecha;
  final Map<String, dynamic>? antes;
  final Map<String, dynamic>? despues;
  final String? usuarioId;

  /// null cuando no hay usuario (reserva en línea o proceso automático).
  final String? usuarioNombre;

  String get quien => usuarioNombre ?? 'Sistema / reserva en línea';
}

/// Una página del historial, más los nombres de empleados para describirla.
class PaginaHistorial {
  const PaginaHistorial({
    required this.registros,
    required this.hayMas,
    this.empleados = const {},
  });

  final List<RegistroAuditoria> registros;
  final bool hayMas;

  /// id de empleado → nombre.
  final Map<String, String> empleados;
}

const _estadosCita = {
  'PENDIENTE': 'pendiente',
  'CONFIRMADA': 'confirmada',
  'LLEGO': 'llegó',
  'COMPLETADA': 'completada',
  'NO_VINO': 'no vino',
  'CANCELADA': 'cancelada',
};

const _metodos = {
  'EFECTIVO': 'efectivo',
  'TRANSFERENCIA': 'transferencia',
  'TARJETA': 'tarjeta',
  'OTRO': 'otro',
};

/// Campos que se comparan para listar qué cambió (updated_at se ignora).
const camposRelevantes = [
  'estado',
  'precio',
  'propina',
  'metodo_pago',
  'fecha',
  'hora_inicio',
  'empleado_id',
  'activo',
  'nombre',
  'rol',
  'monto',
];

/// Campos relevantes que cambiaron entre [antes] y [despues].
List<String> camposCambiados(
  Map<String, dynamic>? antes,
  Map<String, dynamic>? despues,
) {
  if (antes == null || despues == null) return const [];
  return [
    for (final campo in camposRelevantes)
      if (_valor(antes[campo]) != _valor(despues[campo])) campo,
  ];
}

/// Postgres puede devolver numeric como número o como texto.
Object? _valor(Object? v) {
  if (v is num) return v.toDouble();
  if (v is String && RegExp(r'^-?\d+(\.\d+)?$').hasMatch(v)) {
    return double.parse(v);
  }
  return v;
}

String _hora(Object? v) => v == null ? '' : formatoHora('$v');

/// '2026-10-31' → '31/10'
String _dia(Object? v) {
  final f = DateTime.tryParse('$v');
  return f == null ? '$v' : formatoDiaMes(f);
}

String _dinero(Object? v) {
  final n = v is num ? v : num.tryParse('$v');
  return n == null ? '$v' : formatoMoneda(n);
}

/// Convierte una fila de auditoría en una frase en español.
/// [empleados] (id → nombre) permite nombrar al barbero de una cita.
String describirCambio(
  RegistroAuditoria r, {
  Map<String, String> empleados = const {},
}) {
  final fila = r.despues ?? r.antes ?? const <String, dynamic>{};
  final actor = r.usuarioNombre ?? 'Sistema';
  return switch (r.tabla) {
    'citas' => _cita(r, fila, actor, empleados),
    'apartados' => _apartado(r, fila, actor),
    'clientes' => _entidad(r, fila, actor, 'cliente'),
    'servicios' => _servicio(r, fila, actor),
    'empleados' => _entidad(r, fila, actor, 'empleado'),
    'perfiles' => _perfil(r, fila, actor),
    _ => '$actor modificó ${r.tabla}',
  };
}

String _cuando(Map<String, dynamic> fila) =>
    '${_dia(fila['fecha'])} ${_hora(fila['hora_inicio'])}'.trim();

String _cita(
  RegistroAuditoria r,
  Map<String, dynamic> fila,
  String actor,
  Map<String, String> empleados,
) {
  if (r.accion == 'INSERT') {
    final cuando = _cuando(fila);
    if (fila['origen'] == 'PUBLICA') {
      return 'Reserva en línea creada para el $cuando';
    }
    return '$actor creó una cita para el $cuando';
  }
  if (r.accion == 'DELETE') {
    return '$actor eliminó la cita del ${_cuando(fila)}';
  }

  final antes = r.antes, despues = r.despues;
  final cambios = camposCambiados(antes, despues);
  final detalles = <String>[];
  for (final campo in cambios) {
    switch (campo) {
      case 'precio':
        detalles.add(
          'precio ${_dinero(antes?['precio'])} → ${_dinero(despues?['precio'])}',
        );
      case 'propina':
        detalles.add('propina ${_dinero(despues?['propina'])}');
      case 'metodo_pago':
        final m = despues?['metodo_pago'];
        detalles.add('pago ${_metodos['$m'] ?? m ?? 'sin método'}');
      case 'fecha':
        detalles.add(
          'fecha ${_dia(antes?['fecha'])} → ${_dia(despues?['fecha'])}',
        );
      case 'hora_inicio':
        detalles.add(
          'hora ${_hora(antes?['hora_inicio'])} → '
          '${_hora(despues?['hora_inicio'])}',
        );
      case 'empleado_id':
        detalles.add(
          'con ${empleados['${despues?['empleado_id']}'] ?? 'otra persona'}',
        );
    }
  }
  final extra = detalles.isEmpty ? '' : ' (${detalles.join(', ')})';

  if (cambios.contains('estado')) {
    final estado = despues?['estado'];
    final hora = _hora(fila['hora_inicio']);
    final accion = switch (estado) {
      'COMPLETADA' => 'completó la cita de las $hora',
      'CANCELADA' => 'canceló la cita del ${_cuando(fila)}',
      'CONFIRMADA' => 'confirmó la cita del ${_cuando(fila)}',
      'LLEGO' => 'marcó la llegada del cliente de la cita de las $hora',
      'NO_VINO' =>
        'marcó que el cliente no vino a la cita del ${_cuando(fila)}',
      _ =>
        'cambió a ${_estadosCita['$estado'] ?? estado} la cita del '
            '${_cuando(fila)}',
    };
    return '$actor $accion$extra';
  }
  return '$actor modificó la cita del ${_cuando(fila)}$extra';
}

String _apartado(RegistroAuditoria r, Map<String, dynamic> fila, String actor) {
  final monto = _dinero(fila['monto']);
  if (r.accion == 'INSERT') return 'Apartado de $monto registrado';
  if (r.accion == 'DELETE') return '$actor eliminó un apartado de $monto';
  final estado = r.despues?['estado'];
  if (r.antes?['estado'] != estado) {
    return switch (estado) {
      'PAGADO' => 'Apartado validado: $monto',
      'CANCELADO' => 'Apartado cancelado: $monto',
      _ => 'Apartado de $monto vuelto a pendiente',
    };
  }
  return '$actor modificó un apartado de $monto';
}

String _nombre(Map<String, dynamic> fila) => '${fila['nombre'] ?? ''}'.trim();

/// Clientes y empleados: [tipo] es 'cliente' o 'empleado'.
String _entidad(
  RegistroAuditoria r,
  Map<String, dynamic> fila,
  String actor,
  String tipo,
) {
  final nombre = _nombre(fila);
  if (r.accion == 'INSERT') return '$actor agregó al $tipo $nombre';
  if (r.accion == 'DELETE') return '$actor eliminó al $tipo $nombre';
  final cambios = camposCambiados(r.antes, r.despues);
  if (cambios.contains('activo')) {
    final verbo = r.despues?['activo'] == true ? 'activó' : 'desactivó';
    return '$actor $verbo al $tipo $nombre';
  }
  if (cambios.contains('nombre')) {
    return '$actor cambió el nombre del $tipo ${r.antes?['nombre']} → $nombre';
  }
  return '$actor actualizó al $tipo $nombre';
}

String _servicio(RegistroAuditoria r, Map<String, dynamic> fila, String actor) {
  final nombre = _nombre(fila);
  if (r.accion == 'INSERT') {
    return '$actor creó el servicio $nombre (${_dinero(fila['precio'])})';
  }
  if (r.accion == 'DELETE') return '$actor eliminó el servicio $nombre';
  final cambios = camposCambiados(r.antes, r.despues);
  final partes = <String>[];
  if (cambios.contains('precio')) {
    partes.add(
      'precio ${_dinero(r.antes?['precio'])} → ${_dinero(r.despues?['precio'])}',
    );
  }
  if (cambios.contains('nombre')) {
    partes.add('nombre ${r.antes?['nombre']} → $nombre');
  }
  if (cambios.contains('activo')) {
    partes.add(r.despues?['activo'] == true ? 'activado' : 'desactivado');
  }
  if (partes.isEmpty) return '$actor actualizó el servicio $nombre';
  return '$actor cambió el servicio $nombre (${partes.join(', ')})';
}

String _perfil(RegistroAuditoria r, Map<String, dynamic> fila, String actor) {
  final nombre = _nombre(fila);
  if (r.accion == 'INSERT') return '$actor agregó al usuario $nombre';
  if (r.accion == 'DELETE') return '$actor eliminó al usuario $nombre';
  final cambios = camposCambiados(r.antes, r.despues);
  if (cambios.contains('rol')) {
    return '$actor cambió el rol de $nombre: '
        '${r.antes?['rol']} → ${r.despues?['rol']}';
  }
  if (cambios.contains('activo')) {
    final verbo = r.despues?['activo'] == true ? 'activó' : 'desactivó';
    return '$actor $verbo al usuario $nombre';
  }
  return '$actor actualizó al usuario $nombre';
}
