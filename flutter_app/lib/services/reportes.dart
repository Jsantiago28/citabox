// Cálculo puro de los reportes por período (sin Flutter ni Supabase).
//
// Reglas:
// - Ingresos: suma de `citas.precio` con estado LLEGO o COMPLETADA.
// - No-show: NO_VINO / (atendidas + NO_VINO).
// - Apartados cobrados: suma de `apartados.monto` PAGADO, según la fecha
//   de la cita (sin importar el estado de la cita).
// - Ticket promedio: ingresos / citas atendidas.
// Los montos se suman en centavos enteros para que los totales cuadren
// exactamente con las citas de entrada.

import '../models/cita.dart';

/// Cita con los datos que necesita el reporte.
class CitaReporte {
  const CitaReporte({
    required this.id,
    required this.fecha,
    required this.precio,
    required this.estado,
    this.clienteId = '',
    this.clienteNombre = '',
    this.empleadoId = '',
    this.empleadoNombre = '',
    this.servicioId = '',
    this.servicioNombre = '',
    this.apartadoPagado = 0,
  });

  final String id;

  /// Solo se usa la parte de fecha (año, mes, día).
  final DateTime fecha;
  final num precio;
  final EstadoCita estado;
  final String clienteId;
  final String clienteNombre;
  final String empleadoId;
  final String empleadoNombre;
  final String servicioId;
  final String servicioNombre;

  /// Suma de los apartados en estado PAGADO de esta cita.
  final num apartadoPagado;

  factory CitaReporte.fromMap(Map<String, dynamic> map) {
    String nombreDe(String relacion) =>
        (map[relacion] as Map<String, dynamic>?)?['nombre']?.toString() ?? '';
    num numero(Object? valor) => num.tryParse(valor?.toString() ?? '') ?? 0;

    final apartados = (map['apartados'] as List<dynamic>?) ?? const [];
    final pagado = apartados
        .whereType<Map<String, dynamic>>()
        .where((apartado) => apartado['estado'] == 'PAGADO')
        .fold<num>(0, (total, apartado) => total + numero(apartado['monto']));

    return CitaReporte(
      id: map['id'].toString(),
      fecha: DateTime.tryParse(map['fecha']?.toString() ?? '') ?? DateTime(0),
      precio: numero(map['precio']),
      estado: EstadoCita.desde(map['estado']?.toString()),
      clienteId: map['cliente_id']?.toString() ?? '',
      clienteNombre: nombreDe('clientes'),
      empleadoId: map['empleado_id']?.toString() ?? '',
      empleadoNombre: nombreDe('empleados'),
      servicioId: map['servicio_id']?.toString() ?? '',
      servicioNombre: nombreDe('servicios'),
      apartadoPagado: pagado,
    );
  }
}

enum TipoPeriodo {
  hoy('Hoy'),
  semana('Esta semana'),
  mes('Este mes'),
  mesAnterior('Mes anterior'),
  personalizado('Personalizado');

  const TipoPeriodo(this.etiqueta);

  final String etiqueta;
}

/// Rango de fechas inclusivo (solo días, sin horas).
class Periodo {
  Periodo(DateTime desde, DateTime hasta)
    : desde = _dia(desde),
      hasta = _dia(hasta) {
    if (this.hasta.isBefore(this.desde)) {
      throw ArgumentError('El período termina antes de empezar.');
    }
  }

  final DateTime desde;
  final DateTime hasta;

  /// Período predefinido relativo a [hoy]. La semana empieza el lunes.
  /// Para [TipoPeriodo.personalizado] devuelve solo el día de hoy.
  factory Periodo.de(TipoPeriodo tipo, DateTime hoy) {
    final dia = _dia(hoy);
    return switch (tipo) {
      TipoPeriodo.hoy || TipoPeriodo.personalizado => Periodo(dia, dia),
      TipoPeriodo.semana => Periodo(
        DateTime(dia.year, dia.month, dia.day - (dia.weekday - 1)),
        DateTime(dia.year, dia.month, dia.day + (7 - dia.weekday)),
      ),
      TipoPeriodo.mes => Periodo(
        DateTime(dia.year, dia.month),
        DateTime(dia.year, dia.month + 1, 0),
      ),
      TipoPeriodo.mesAnterior => Periodo(
        DateTime(dia.year, dia.month - 1),
        DateTime(dia.year, dia.month, 0),
      ),
    };
  }

  /// Días del período, en orden.
  List<DateTime> get dias => [
    for (
      var d = desde;
      !d.isAfter(hasta);
      d = DateTime(d.year, d.month, d.day + 1)
    )
      d,
  ];

  bool contiene(DateTime fecha) {
    final dia = _dia(fecha);
    return !dia.isBefore(desde) && !dia.isAfter(hasta);
  }

  @override
  bool operator ==(Object other) =>
      other is Periodo && other.desde == desde && other.hasta == hasta;

  @override
  int get hashCode => Object.hash(desde, hasta);

  @override
  String toString() => 'Periodo($desde – $hasta)';
}

DateTime _dia(DateTime fecha) => DateTime(fecha.year, fecha.month, fecha.day);

int _centavos(num monto) => (monto * 100).round();

num _monto(int centavos) =>
    centavos % 100 == 0 ? centavos ~/ 100 : centavos / 100;

class FilaBarbero {
  const FilaBarbero({
    required this.empleadoId,
    required this.nombre,
    required this.atendidas,
    required this.ingresos,
  });

  final String empleadoId;
  final String nombre;
  final int atendidas;
  final num ingresos;
}

class FilaServicio {
  const FilaServicio({
    required this.nombre,
    required this.cantidad,
    required this.ingresos,
  });

  final String nombre;
  final int cantidad;
  final num ingresos;
}

class FilaCliente {
  const FilaCliente({
    required this.clienteId,
    required this.nombre,
    required this.visitas,
    required this.gastado,
  });

  final String clienteId;
  final String nombre;
  final int visitas;
  final num gastado;
}

class IngresoDia {
  const IngresoDia(this.dia, this.ingresos);

  final DateTime dia;
  final num ingresos;
}

class Reporte {
  const Reporte._({
    required this.periodo,
    required this.totalCitas,
    required this.porEstado,
    required this.ingresos,
    required this.apartadosCobrados,
    required this.porBarbero,
    required this.porServicio,
    required this.topClientes,
    required this.ingresosPorDia,
  });

  /// Calcula el reporte con las citas de [periodo]; ignora las de fuera.
  factory Reporte.calcular(Iterable<CitaReporte> todas, Periodo periodo) {
    final citas = todas.where((cita) => periodo.contiene(cita.fecha)).toList();

    final porEstado = {for (final estado in EstadoCita.values) estado: 0};
    var ingresos = 0;
    var apartados = 0;
    final barberos = <String, _Acumulado>{};
    final servicios = <String, _Acumulado>{};
    final clientes = <String, _Acumulado>{};
    final porDia = {for (final dia in periodo.dias) dia: 0};

    for (final cita in citas) {
      porEstado[cita.estado] = porEstado[cita.estado]! + 1;
      apartados += _centavos(cita.apartadoPagado);
      if (!cita.estado.atendida) continue;

      final precio = _centavos(cita.precio);
      ingresos += precio;
      porDia[_dia(cita.fecha)] = porDia[_dia(cita.fecha)]! + precio;

      String clave(String id, String nombre) => id.isNotEmpty ? id : nombre;
      barberos
          .putIfAbsent(
            clave(cita.empleadoId, cita.empleadoNombre),
            () => _Acumulado(cita.empleadoNombre),
          )
          .sumar(precio);
      servicios
          .putIfAbsent(
            clave(cita.servicioId, cita.servicioNombre),
            () => _Acumulado(cita.servicioNombre),
          )
          .sumar(precio);
      clientes
          .putIfAbsent(
            clave(cita.clienteId, cita.clienteNombre),
            () => _Acumulado(cita.clienteNombre),
          )
          .sumar(precio);
    }

    List<MapEntry<String, _Acumulado>> ordenar(
      Map<String, _Acumulado> grupos,
      int Function(_Acumulado a, _Acumulado b) criterio,
    ) => grupos.entries.toList()
      ..sort((a, b) {
        final orden = criterio(a.value, b.value);
        return orden != 0 ? orden : a.value.nombre.compareTo(b.value.nombre);
      });

    int porIngresos(_Acumulado a, _Acumulado b) =>
        b.centavos.compareTo(a.centavos);
    int porCantidad(_Acumulado a, _Acumulado b) {
      final orden = b.cantidad.compareTo(a.cantidad);
      return orden != 0 ? orden : porIngresos(a, b);
    }

    return Reporte._(
      periodo: periodo,
      totalCitas: citas.length,
      porEstado: Map.unmodifiable(porEstado),
      ingresos: _monto(ingresos),
      apartadosCobrados: _monto(apartados),
      porBarbero: [
        for (final e in ordenar(barberos, porIngresos))
          FilaBarbero(
            empleadoId: e.key,
            nombre: e.value.nombre,
            atendidas: e.value.cantidad,
            ingresos: _monto(e.value.centavos),
          ),
      ],
      porServicio: [
        for (final e in ordenar(servicios, porIngresos))
          FilaServicio(
            nombre: e.value.nombre,
            cantidad: e.value.cantidad,
            ingresos: _monto(e.value.centavos),
          ),
      ],
      topClientes: [
        for (final e in ordenar(clientes, porCantidad).take(10))
          FilaCliente(
            clienteId: e.key,
            nombre: e.value.nombre,
            visitas: e.value.cantidad,
            gastado: _monto(e.value.centavos),
          ),
      ],
      ingresosPorDia: [
        for (final e in porDia.entries) IngresoDia(e.key, _monto(e.value)),
      ],
    );
  }

  final Periodo periodo;

  /// Todas las citas del período, incluidas las canceladas.
  final int totalCitas;
  final Map<EstadoCita, int> porEstado;
  final num ingresos;
  final num apartadosCobrados;
  final List<FilaBarbero> porBarbero;
  final List<FilaServicio> porServicio;

  /// Hasta 10 clientes con más visitas atendidas.
  final List<FilaCliente> topClientes;

  /// Un valor por cada día del período (0 si no hubo ingresos).
  final List<IngresoDia> ingresosPorDia;

  int get atendidas =>
      porEstado[EstadoCita.llego]! + porEstado[EstadoCita.completada]!;
  int get noShows => porEstado[EstadoCita.noVino]!;
  int get cancelaciones => porEstado[EstadoCita.cancelada]!;

  /// Entre 0 y 1; `null` si nadie llegó ni faltó.
  double? get tasaNoShow {
    final base = atendidas + noShows;
    return base == 0 ? null : noShows / base;
  }

  /// `null` si no hubo citas atendidas.
  num? get ticketPromedio {
    if (atendidas == 0) return null;
    return _monto((_centavos(ingresos) / atendidas).round());
  }
}

class _Acumulado {
  _Acumulado(this.nombre);

  final String nombre;
  int cantidad = 0;
  int centavos = 0;

  void sumar(int monto) {
    cantidad++;
    centavos += monto;
  }
}
