// =========================================================================
// Citabox — Simulación de un negocio funcionando
// =========================================================================
// Llena el negocio de una cuenta de dueño con ~2 meses de movimiento para
// enseñar la app: 30 clientes, 2 profesionales más, citas pasadas cobradas
// (efectivo, transferencia, tarjeta, propinas), canceladas y "no vino",
// reservas en línea con apartado (pagado y por validar), la próxima semana
// agendada, cumpleaños del mes, clientes que no vuelven, uno a punto de la
// visita gratis y unas vacaciones en el equipo.
//
// Entra con la cuenta del dueño (mismos permisos que en la app): no toca
// otros negocios. Todo lo creado lleva "[demo]" en las notas (clientes y
// citas) o queda anotado en simulacion-ids.json, para poder borrarlo.
//
// USO (Node 18+):
//   CB_EMAIL=correo CB_PASS=clave node supabase/seed/simulacion.mjs
//   CB_EMAIL=correo CB_PASS=clave node supabase/seed/simulacion.mjs --borrar
//
// La contraseña va solo en variables de entorno: nunca en este archivo.
// =========================================================================

import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const URL_SB = 'https://ncieqndyjqwkgxrbqcee.supabase.co';
const CLAVE = 'sb_publishable_r4tXZRYpnjOHxPe4Yhs1HA_xgsxbxn-'; // pública
const IDS = fileURLToPath(new URL('./simulacion-ids.json', import.meta.url));
const ZONA = '-04:00'; // República Dominicana, sin horario de verano

// ---------------------------------------------------------------- API ----
async function entrar() {
  const r = await fetch(`${URL_SB}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: CLAVE, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: process.env.CB_EMAIL, password: process.env.CB_PASS }),
  });
  const j = await r.json();
  if (!r.ok) throw new Error(`No se pudo entrar: ${j.msg || j.error_description || r.status}`);
  return j;
}

function api(token) {
  const base = { apikey: CLAVE, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
  const llamar = async (metodo, ruta, cuerpo, extra = {}) => {
    const r = await fetch(`${URL_SB}/rest/v1/${ruta}`, {
      method: metodo,
      headers: { ...base, ...extra },
      body: cuerpo === undefined ? undefined : JSON.stringify(cuerpo),
    });
    const t = await r.text();
    if (!r.ok) throw new Error(`${metodo} ${ruta} → ${r.status}: ${t}`);
    return t ? JSON.parse(t) : null;
  };
  return {
    leer: (ruta) => llamar('GET', ruta),
    crear: (ruta, cuerpo) => llamar('POST', ruta, cuerpo, { Prefer: 'return=representation' }),
    cambiar: (ruta, cuerpo) => llamar('PATCH', ruta, cuerpo, { Prefer: 'return=representation' }),
    borrar: (ruta) => llamar('DELETE', ruta),
  };
}

// ------------------------------------------------------------ Azar fijo --
let semilla = 20261101;
function azar() {
  semilla = (semilla * 1664525 + 1013904223) % 4294967296;
  return semilla / 4294967296;
}
const entre = (a, b) => a + Math.floor(azar() * (b - a + 1));
const uno = (lista) => lista[Math.floor(azar() * lista.length)];
function ponderado(pares) {
  const total = pares.reduce((s, [, p]) => s + p, 0);
  let x = azar() * total;
  for (const [valor, p] of pares) if ((x -= p) < 0) return valor;
  return pares[pares.length - 1][0];
}

// -------------------------------------------------------------- Fechas ---
const hoyRD = () => new Date(Date.now() - 4 * 3600e3).toISOString().slice(0, 10);
function sumarDias(fecha, dias) {
  const d = new Date(`${fecha}T12:00:00Z`);
  d.setUTCDate(d.getUTCDate() + dias);
  return d.toISOString().slice(0, 10);
}
const diaSemana = (fecha) => new Date(`${fecha}T12:00:00Z`).getUTCDay();
const aMin = (h) => { const [a, b] = h.split(':').map(Number); return a * 60 + b; };
const aHora = (m) => `${String(Math.floor(m / 60)).padStart(2, '0')}:${String(m % 60).padStart(2, '0')}:00`;

// --------------------------------------------------------------- Datos ---
const EQUIPO_NUEVO = [
  { nombre: 'Rafael Núñez', telefono: '8095550201', comision_pct: 40 },
  { nombre: 'Kelvin Abreu', telefono: '8295550202', comision_pct: 35 },
];

// [nombre, cada cuántos días viene, cumple "mes-día" o null, tipo]
//   tipo: 'fiel' (viene cada semana), 'se_fue' (dejó de venir), 'nuevo'
//   (primera vez, por reserva en línea) o normal.
const CLIENTES = [
  ['Ramón Almonte', 7, '03-14', 'fiel'],
  ['Luis Miguel Tavárez', 14, '11-01', null],
  ['Yanelis Batista', 21, '11-18', null],
  ['Carlos Peralta', 14, '07-22', null],
  ['Junior De los Santos', 10, null, null],
  ['Pedro Ureña', 21, '11-27', null],
  ['Anderson Polanco', 14, '01-09', null],
  ['Wilson Castillo', 28, null, null],
  ['Héctor Mejía', 14, '05-30', null],
  ['Francis Rosario', 21, null, null],
  ['Raúl Jiménez', 10, '09-05', null],
  ['Darío Vásquez', 28, null, null],
  ['Miguel Ángel Cruz', 14, '12-12', null],
  ['Josué Fernández', 21, null, null],
  ['Starlin Guzmán', 14, '02-17', null],
  ['Manuel Encarnación', 28, null, null],
  ['Rosanna Pichardo', 21, '06-03', null],
  ['Félix Hernández', 14, null, null],
  ['Alexander Reyes', 10, '08-08', null],
  ['Jean Carlos Mota', 14, null, null],
  ['Víctor Frías', 21, '10-25', null],
  ['Eddy Santana', 28, null, null],
  ['Domingo Paulino', 30, '04-21', 'se_fue'],
  ['Nelson Báez', 21, null, 'se_fue'],
  ['Freddy Lantigua', 25, '11-09', 'se_fue'],
  ['Melvin Sosa', 14, null, 'se_fue'],
  ['Kendry Valdez', 0, null, 'nuevo'],
  ['Yoel Marte', 0, '12-30', 'nuevo'],
  ['Brayan Espinal', 0, null, 'nuevo'],
  ['Gabriel Ozuna', 0, null, 'nuevo'],
];

const NOTAS_CITA = [
  'Degradado bajo, como la vez pasada',
  'Viene con su hijo',
  'Prefiere que le quiten el volumen arriba',
  'Llega 10 minutos antes',
  'Pidió la raya marcada',
  'Alérgico a la loción con alcohol',
];

// ------------------------------------------------------------- Llenar ----
async function llenar(a, negocio) {
  if (existsSync(IDS)) {
    throw new Error('Ya hay una simulación (simulacion-ids.json). Bórrala primero con --borrar.');
  }
  const id = negocio.id;
  const hoy = hoyRD();
  const horaAhora = new Date(Date.now() - 4 * 3600e3).toISOString().slice(11, 16);

  const servicios = (await a.leer(`servicios?negocio_id=eq.${id}&activo=eq.true&select=*`));
  if (!servicios.length) throw new Error('El negocio no tiene servicios activos.');
  const horarios = await a.leer(`horarios_negocio?negocio_id=eq.${id}&select=*`);
  const horario = new Map(horarios.map((h) => [h.dia_semana, [aMin(h.hora_apertura), aMin(h.hora_cierre)]]));
  const existentes = await a.leer(
    `citas?negocio_id=eq.${id}&estado=not.in.(CANCELADA,NO_VINO)&select=empleado_id,fecha,hora_inicio,hora_fin`,
  );

  // Equipo: el que ya existe + 2 más con comisión.
  const nuevos = await a.crear('empleados', EQUIPO_NUEVO.map((e) => ({ ...e, negocio_id: id })));
  const equipo = await a.leer(`empleados?negocio_id=eq.${id}&activo=eq.true&select=id,nombre`);
  const kelvin = nuevos.find((e) => e.nombre === 'Kelvin Abreu');
  const vacaciones = [sumarDias(hoy, 4), sumarDias(hoy, 5)];
  const bloqueo = await a.crear('bloqueos_empleado', [{
    negocio_id: id, empleado_id: kelvin.id,
    fecha_inicio: vacaciones[0], fecha_fin: vacaciones[1], motivo: 'Vacaciones',
  }]);

  // Clientes.
  const filas = CLIENTES.map(([nombre, , cumple, tipo], i) => ({
    negocio_id: id,
    nombre,
    telefono: `${['809', '829', '849'][i % 3]}5550${String(100 + i).slice(-3)}`,
    notas: `[demo]${tipo === 'fiel' ? ' Cliente fijo de los sábados' : ''}`,
    cumple_mes: cumple ? Number(cumple.slice(0, 2)) : null,
    cumple_dia: cumple ? Number(cumple.slice(3)) : null,
    consentimiento_at: tipo === 'nuevo' ? new Date().toISOString() : null,
  }));
  const clientes = await a.crear('clientes', filas);
  const porNombre = new Map(clientes.map((c) => [c.nombre, c]));

  // Visitas de cada cliente: desde hace ~70 días hasta dentro de 7.
  const visitas = [];
  for (const [nombre, cada, , tipo] of CLIENTES) {
    const cliente = porNombre.get(nombre);
    const preferido = uno(equipo).id;
    if (tipo === 'nuevo') {
      visitas.push({ cliente, fecha: sumarDias(hoy, entre(-6, 6)), preferido, nuevo: true });
      continue;
    }
    if (tipo === 'fiel') {
      // 9 visitas atendidas: la próxima es la gratis (programa de 10).
      let f = sumarDias(hoy, -diaSemana(hoy) - 1); // último sábado
      for (let i = 0; i < 9; i++, f = sumarDias(f, -7)) visitas.push({ cliente, fecha: f, preferido, fiel: true });
      visitas.push({ cliente, fecha: sumarDias(hoy, 6 - diaSemana(hoy)), preferido, fiel: true });
      continue;
    }
    const hasta = tipo === 'se_fue' ? sumarDias(hoy, -entre(50, 75)) : sumarDias(hoy, 7);
    let f = sumarDias(hoy, -70 + entre(0, cada));
    while (f <= hasta) {
      visitas.push({ cliente, fecha: f, preferido });
      f = sumarDias(f, cada + entre(-2, 3));
    }
    // Los que siguen viniendo ya tienen su próxima cita en la semana.
    if (tipo !== 'se_fue' && !visitas.some((v) => v.cliente === cliente && v.fecha > hoy)) {
      visitas.push({ cliente, fecha: sumarDias(hoy, entre(1, 7)), preferido });
    }
  }

  // Agenda: cada visita con su profesional y hora, sin choques.
  const ocupado = new Map(); // `${empleado}|${fecha}` → [[ini, fin]]
  const marcar = (emp, fecha, ini, fin) => {
    const k = `${emp}|${fecha}`;
    (ocupado.get(k) || ocupado.set(k, []).get(k)).push([ini, fin]);
  };
  const libre = (emp, fecha, ini, fin) =>
    !(ocupado.get(`${emp}|${fecha}`) || []).some(([a1, b1]) => ini < b1 && a1 < fin);
  for (const c of existentes) marcar(c.empleado_id, c.fecha, aMin(c.hora_inicio), aMin(c.hora_fin));

  const citas = [];
  const apartadosPorCita = [];
  for (const v of visitas.sort((x, y) => x.fecha.localeCompare(y.fecha))) {
    const [abre, cierra] = horario.get(diaSemana(v.fecha)) || [];
    if (abre === undefined) continue;
    const servicio = v.fiel ? servicios[0] : uno(servicios);
    const dura = servicio.duracion_minutos;
    const candidatos = [v.preferido, ...equipo.map((e) => e.id)]
      .filter((e) => !(e === kelvin.id && vacaciones.includes(v.fecha)));
    let puesto = null;
    for (let intento = 0; intento < 40 && !puesto; intento++) {
      const emp = intento < 20 ? candidatos[0] : uno(candidatos);
      const ini = abre + 15 * entre(0, Math.floor((cierra - dura - abre) / 15));
      if (libre(emp, v.fecha, ini, ini + dura)) puesto = { emp, ini };
    }
    if (!puesto) continue;
    marcar(puesto.emp, v.fecha, puesto.ini, puesto.ini + dura);

    const pasada = v.fecha < hoy || (v.fecha === hoy && aHora(puesto.ini + dura) <= `${horaAhora}:00`);
    const enLinea = v.nuevo || azar() < 0.35;
    let estado;
    if (pasada) {
      estado = v.fiel ? 'COMPLETADA' : ponderado([['COMPLETADA', 84], ['NO_VINO', 7], ['CANCELADA', 9]]);
    } else {
      estado = ponderado([['PENDIENTE', 55], ['CONFIRMADA', 45]]);
    }
    const nota = azar() < 0.18 ? ` ${uno(NOTAS_CITA)}` : '';
    const cita = {
      negocio_id: id,
      cliente_id: v.cliente.id,
      empleado_id: puesto.emp,
      servicio_id: servicio.id,
      fecha: v.fecha,
      hora_inicio: aHora(puesto.ini),
      hora_fin: aHora(puesto.ini + dura),
      precio: servicio.precio,
      estado,
      notas: `[demo]${nota}`,
      origen: enLinea ? 'PUBLICA' : 'INTERNA',
      metodo_pago: null,
      propina: 0,
      cobrada_en: null,
    };
    if (estado === 'COMPLETADA') {
      cita.metodo_pago = ponderado([['EFECTIVO', 50], ['TRANSFERENCIA', 32], ['TARJETA', 18]]);
      cita.propina = ponderado([[0, 60], [50, 15], [100, 17], [200, 8]]);
      cita.cobrada_en = `${v.fecha}T${cita.hora_fin}${ZONA}`;
    }
    citas.push(cita);
    if (enLinea && negocio.apartado_requerido && estado !== 'CANCELADA') {
      // Las 2 primeras reservas en línea por venir esperan que el dueño
      // valide el apartado ("Ya pagué"); si nadie lo hace, vencen en 24 h.
      const porValidar = !pasada && apartadosPorCita.filter((x) => x.estado === 'PENDIENTE').length < 2;
      apartadosPorCita.push({
        i: citas.length - 1,
        monto: negocio.apartado_monto,
        estado: porValidar ? 'PENDIENTE' : 'PAGADO',
        metodo_pago: 'TRANSFERENCIA',
        referencia: String(entre(100000, 999999)),
        fecha_pago: porValidar ? null : `${sumarDias(v.fecha, -1)}T19:30:00${ZONA}`,
      });
    }
  }
  // Una cita en línea esperando que el dueño valide el apartado: queda
  // PENDIENTE aunque el sorteo la haya confirmado.
  for (const ap of apartadosPorCita) if (ap.estado === 'PENDIENTE') citas[ap.i].estado = 'PENDIENTE';

  const creadas = [];
  for (let i = 0; i < citas.length; i += 50) creadas.push(...await a.crear('citas', citas.slice(i, i + 50)));
  const apartados = apartadosPorCita.map(({ i, ...ap }) => ({ ...ap, negocio_id: id, cita_id: creadas[i].id }));
  if (apartados.length) await a.crear('apartados', apartados);

  // Programa "la décima gratis" (se guarda lo que había para restaurarlo).
  const antes = { fidelidad_visitas: negocio.fidelidad_visitas, fidelidad_premio: negocio.fidelidad_premio };
  await a.cambiar(`negocios?id=eq.${id}`, { fidelidad_visitas: 10, fidelidad_premio: 'Corte gratis' });

  writeFileSync(IDS, JSON.stringify({
    negocio: id,
    empleados: nuevos.map((e) => e.id),
    bloqueos: bloqueo.map((b) => b.id),
    fidelidad_antes: antes,
  }, null, 2));

  const cuenta = (f) => creadas.filter(f).length;
  console.log(`Listo en "${negocio.nombre}":`);
  console.log(`  ${clientes.length} clientes, ${nuevos.length} profesionales nuevos, vacaciones de Kelvin ${vacaciones.join(' y ')}`);
  console.log(`  ${creadas.length} citas: ${cuenta((c) => c.estado === 'COMPLETADA')} cobradas, ` +
    `${cuenta((c) => c.fecha >= hoy && ['PENDIENTE', 'CONFIRMADA'].includes(c.estado))} por venir, ` +
    `${cuenta((c) => c.estado === 'NO_VINO')} no vinieron, ${cuenta((c) => c.estado === 'CANCELADA')} canceladas`);
  console.log(`  ${apartados.length} apartados (${apartados.filter((x) => x.estado === 'PENDIENTE').length} por validar)`);
}

// ------------------------------------------------------------- Borrar ----
async function borrar(a, negocio) {
  const id = negocio.id;
  const guardado = existsSync(IDS) ? JSON.parse(readFileSync(IDS, 'utf8')) : null;
  await a.borrar(`citas?negocio_id=eq.${id}&notas=like.%5Bdemo%5D*`);
  await a.borrar(`clientes?negocio_id=eq.${id}&notas=like.%5Bdemo%5D*`);
  if (guardado) {
    if (guardado.bloqueos.length) await a.borrar(`bloqueos_empleado?id=in.(${guardado.bloqueos})`);
    if (guardado.empleados.length) await a.borrar(`empleados?id=in.(${guardado.empleados})`);
    await a.cambiar(`negocios?id=eq.${id}`, guardado.fidelidad_antes);
    writeFileSync(IDS, '');
    (await import('node:fs')).unlinkSync(IDS);
  }
  console.log(`Simulación borrada de "${negocio.nombre}".`);
}

// --------------------------------------------------------------- Inicio --
const sesion = await entrar();
const a = api(sesion.access_token);
const [perfil] = await a.leer(`perfiles?id=eq.${sesion.user.id}&select=negocio_id,rol`);
if (!perfil || perfil.rol !== 'OWNER') throw new Error('Esta cuenta no es dueña de un negocio.');
const [negocio] = await a.leer(`negocios?id=eq.${perfil.negocio_id}&select=*`);
await (process.argv.includes('--borrar') ? borrar(a, negocio) : llenar(a, negocio));
