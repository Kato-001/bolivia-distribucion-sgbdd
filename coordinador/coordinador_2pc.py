"""
Coordinador de Transacciones Distribuidas - BoliviaDistribucion S.A.
====================================================================
Implementa el protocolo de COMPROMISO EN DOS FASES (2PC) usando los
mecanismos nativos de PostgreSQL:

    PREPARE TRANSACTION 'gid'   -> Fase 1: cada participante "vota SI"
    COMMIT PREPARED 'gid'       -> Fase 2: decision global = CONFIRMAR
    ROLLBACK PREPARED 'gid'     -> Fase 2: decision global = ABORTAR

Uso (desde la carpeta del proyecto):
    docker compose run --rm coordinador traspaso --origen SC --destino BE --producto 10 --cantidad 5
    docker compose run --rm coordinador traspaso ... --pausa 20          (pausa antes de la Fase 1)
    docker compose run --rm coordinador traspaso ... --pausa-commit 20   (pausa entre Fase 1 y Fase 2)
    docker compose run --rm coordinador stock --producto 10
    docker compose run --rm coordinador recuperar
"""
import argparse
import os
import sys
import time
import uuid

import psycopg
from psycopg import sql

PASSWORD = os.environ.get("PGPASSWORD", "bolivia123")

NODOS = {
    1: ("Nodo 1 - La Paz", "nodo1_lapaz"),
    2: ("Nodo 2 - Santa Cruz", "nodo2_santacruz"),
    3: ("Nodo 3 - Cochabamba", "nodo3_cochabamba"),
    4: ("Nodo 4 - Tarija", "nodo4_tarija"),
    5: ("Nodo 5 - Oruro", "nodo5_oruro"),
    6: ("Nodo 6 - Beni", "nodo6_beni"),
}
DEPTO_A_NODO = {"LP": 1, "SC": 2, "CB": 3, "TJ": 4, "CH": 4,
                "OR": 5, "PO": 5, "BE": 6, "PA": 6}
NODO_CENTRAL = 1

# ---------- salida con colores ----------
VERDE, ROJO, AMARILLO, AZUL, NEGRITA, FIN = "\033[92m", "\033[91m", "\033[93m", "\033[96m", "\033[1m", "\033[0m"


def titulo(t):
    print(f"\n{NEGRITA}{AZUL}=== {t} ==={FIN}")


def ok(t):
    print(f"  {VERDE}[OK]{FIN} {t}")


def mal(t):
    print(f"  {ROJO}[X]{FIN} {t}")


def info(t):
    print(f"  {AMARILLO}->{FIN} {t}")


class ErrorTraspaso(Exception):
    pass


def conectar(nodo_id):
    """Conexion con tiempos cortos para detectar rapido un nodo caido."""
    _, host = NODOS[nodo_id]
    return psycopg.connect(
        host=host, port=5432, dbname="bolivia", user="postgres", password=PASSWORD,
        autocommit=True,              # controlamos BEGIN / PREPARE a mano
        connect_timeout=3,
        keepalives=1, keepalives_idle=2, keepalives_interval=1, keepalives_count=2,
        tcp_user_timeout=4000,        # si el nodo no responde en 4 s -> error
        application_name="coordinador_2pc",
    )


def cuenta_regresiva(segundos, mensaje):
    print(f"\n  {AMARILLO}{NEGRITA}{mensaje}{FIN}")
    for s in range(segundos, 0, -1):
        print(f"    ...continuando en {s:2d} s", end="\r", flush=True)
        time.sleep(1)
    print(" " * 40)


# =====================================================================
#  Bitacora del coordinador (en La Paz, nodo central de auditoria)
# =====================================================================
class Bitacora:
    def __init__(self):
        self.conn = conectar(NODO_CENTRAL)

    def nuevo(self, gid, origen, destino, producto, cantidad):
        self.conn.execute(
            "INSERT INTO coordinador_2pc_log (gid, origen, destino, id_producto, cantidad, estado) "
            "VALUES (%s, %s, %s, %s, %s, 'INICIADO')", (gid, origen, destino, producto, cantidad))

    def estado(self, gid, estado, detalle=None):
        self.conn.execute(
            "UPDATE coordinador_2pc_log SET estado = %s, detalle = coalesce(%s, detalle), actualizado = now() "
            "WHERE gid = %s", (estado, detalle, gid))

    def consultar(self, gid):
        fila = self.conn.execute("SELECT estado FROM coordinador_2pc_log WHERE gid = %s", (gid,)).fetchone()
        return fila[0] if fila else None


# =====================================================================
#  TRASPASO INTERDEPARTAMENTAL CON 2PC
# =====================================================================
def traspaso(origen, destino, producto, cantidad, pausa=0, pausa_commit=0):
    origen, destino = origen.upper(), destino.upper()
    n_ori, n_des = DEPTO_A_NODO[origen], DEPTO_A_NODO[destino]
    if n_ori == n_des:
        print("Origen y destino estan en el mismo nodo: eso es una transaccion LOCAL, no distribuida.")
        return 1

    nom_ori, nom_des = NODOS[n_ori][0], NODOS[n_des][0]
    gid = f"trp_{time.strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"

    titulo(f"TRASPASO {origen} -> {destino}: {cantidad} unidades del producto {producto}")
    info(f"ID global de la transaccion (gid): {gid}")

    try:
        bitacora = Bitacora()
    except Exception as e:
        mal(f"No hay conexion con el nodo central (bitacora del coordinador): {e}")
        return 1
    bitacora.nuevo(gid, origen, destino, producto, cantidad)

    participantes = {}            # nodo_id -> conexion
    preparados = []               # nodos que ya votaron SI (PREPARE TRANSACTION)

    try:
        # ---------------- Conexion ----------------
        titulo("FASE 0: Conexion con los participantes")
        for n in (n_ori, n_des):
            try:
                participantes[n] = conectar(n)
                ok(f"Conectado a {NODOS[n][0]}")
            except Exception as e:
                raise ErrorTraspaso(f"{NODOS[n][0]} no responde ({type(e).__name__})")

        co, cd = participantes[n_ori], participantes[n_des]

        # ---------------- Operaciones locales ----------------
        titulo("EJECUCION: operaciones dentro de cada transaccion local")
        co.execute("BEGIN")
        fila = co.execute(
            """SELECT i.id_almacen, i.stock_actual
                 FROM inventario i JOIN almacenes a USING (id_almacen)
                WHERE a.departamento_id = %s AND i.id_producto = %s
                ORDER BY i.id_almacen LIMIT 1
                  FOR UPDATE OF i""", (origen, producto)).fetchone()
        if not fila:
            raise ErrorTraspaso(f"El producto {producto} no tiene inventario en {origen}")
        alm_ori, stock = fila
        if stock < cantidad:
            raise ErrorTraspaso(f"Stock insuficiente en {origen}: hay {stock}, se piden {cantidad}")
        co.execute("UPDATE inventario SET stock_actual = stock_actual - %s "
                   "WHERE id_almacen = %s AND id_producto = %s", (cantidad, alm_ori, producto))
        co.execute("INSERT INTO traspasos (gid, tipo, id_almacen, id_producto, cantidad, nodo_contraparte) "
                   "VALUES (%s, 'SALIDA', %s, %s, %s, %s)", (gid, alm_ori, producto, cantidad, nom_des))
        ok(f"{nom_ori}: stock {stock} -> {stock - cantidad} (bloqueado, sin confirmar)")

        cd.execute("BEGIN")
        fila = cd.execute("SELECT id_almacen FROM almacenes WHERE departamento_id = %s "
                          "ORDER BY id_almacen LIMIT 1", (destino,)).fetchone()
        if not fila:
            raise ErrorTraspaso(f"No existe almacen en {destino}")
        alm_des = fila[0]
        nuevo = cd.execute(
            """INSERT INTO inventario (id_almacen, id_producto, stock_actual, stock_minimo)
               VALUES (%s, %s, %s, 10)
               ON CONFLICT (id_almacen, id_producto)
               DO UPDATE SET stock_actual = inventario.stock_actual + EXCLUDED.stock_actual
               RETURNING stock_actual""", (alm_des, producto, cantidad)).fetchone()[0]
        cd.execute("INSERT INTO traspasos (gid, tipo, id_almacen, id_producto, cantidad, nodo_contraparte) "
                   "VALUES (%s, 'ENTRADA', %s, %s, %s, %s)", (gid, alm_des, producto, cantidad, nom_ori))
        ok(f"{nom_des}: stock {nuevo - cantidad} -> {nuevo} (bloqueado, sin confirmar)")

        if pausa:
            cuenta_regresiva(pausa, f"PAUSA DE DEMOSTRACION: ahora puedes desconectar {nom_des} "
                                    f"(.\\demo.ps1 cortar {NODOS[n_des][1].split('_')[1]})")

        # ---------------- FASE 1 ----------------
        titulo("FASE 1: PREPARACION (votacion)")
        bitacora.estado(gid, "PREPARANDO")
        for n in (n_ori, n_des):
            info(f"Enviando PREPARE TRANSACTION a {NODOS[n][0]} ...")
            try:
                participantes[n].execute(sql.SQL("PREPARE TRANSACTION {}").format(sql.Literal(gid)))
            except Exception as e:
                raise ErrorTraspaso(f"{NODOS[n][0]} no pudo preparar / perdio conexion ({type(e).__name__})")
            preparados.append(n)
            ok(f"{NODOS[n][0]} voto SI (transaccion preparada y guardada en disco)")

    except Exception as e:
        # ---------------- ABORTAR ----------------
        motivo = str(e) if isinstance(e, ErrorTraspaso) else f"{type(e).__name__}: {e}"
        titulo("DECISION GLOBAL: ABORTAR (ROLLBACK)")
        mal(motivo)
        bitacora.estado(gid, "ABORTANDO", motivo)
        for n, conn in participantes.items():
            try:
                if n in preparados:
                    conn.execute(sql.SQL("ROLLBACK PREPARED {}").format(sql.Literal(gid)))
                    ok(f"ROLLBACK PREPARED ejecutado en {NODOS[n][0]}")
                else:
                    conn.execute("ROLLBACK")
                    ok(f"ROLLBACK ejecutado en {NODOS[n][0]}")
            except Exception:
                info(f"{NODOS[n][0]} inalcanzable: su transaccion NO fue preparada, "
                     f"PostgreSQL la descarta sola al perder la sesion.")
        bitacora.estado(gid, "ABORTADO")
        print(f"\n{ROJO}{NEGRITA}TRASPASO ABORTADO. Ningun nodo quedo modificado (atomicidad).{FIN}")
        mostrar_stock(producto, [origen, destino])
        return 1

    # ---------------- DECISION ----------------
    titulo("DECISION GLOBAL: CONFIRMAR (todos votaron SI)")
    bitacora.estado(gid, "DECISION_COMMIT")
    ok("Decision registrada en la bitacora del coordinador (Nodo 1 - La Paz)")

    if pausa_commit:
        cuenta_regresiva(pausa_commit, f"PAUSA DE DEMOSTRACION: ambos nodos estan PREPARADOS. "
                                       f"Puedes desconectar {nom_des} para probar la recuperacion.")

    # ---------------- FASE 2 ----------------
    titulo("FASE 2: CONFIRMACION (COMMIT PREPARED)")
    pendientes = []
    for n in (n_ori, n_des):
        try:
            participantes[n].execute(sql.SQL("COMMIT PREPARED {}").format(sql.Literal(gid)))
            ok(f"COMMIT PREPARED en {NODOS[n][0]}")
        except Exception as e:
            pendientes.append(NODOS[n][0])
            mal(f"{NODOS[n][0]} no responde ({type(e).__name__}). Su transaccion sigue PREPARADA y "
                f"se confirmara con 'recuperar' cuando vuelva.")

    if pendientes:
        bitacora.estado(gid, "PENDIENTE_COMMIT", "Pendiente en: " + ", ".join(pendientes))
        print(f"\n{AMARILLO}{NEGRITA}TRASPASO DECIDIDO (COMMIT) - pendiente de confirmar en: "
              f"{', '.join(pendientes)}{FIN}")
        print("Cuando el nodo vuelva ejecuta:  docker compose run --rm coordinador recuperar")
        return 2

    bitacora.estado(gid, "COMPLETADO")
    print(f"\n{VERDE}{NEGRITA}TRASPASO COMPLETADO en ambos nodos (ACID garantizado por 2PC).{FIN}")
    mostrar_stock(producto, [origen, destino])
    return 0


# =====================================================================
#  RECUPERACION: resuelve transacciones "en duda" tras una caida
# =====================================================================
def recuperar():
    titulo("RECUPERACION DE TRANSACCIONES EN DUDA")
    bitacora = Bitacora()
    inalcanzables, resueltas = [], []
    for n, (nombre, _) in NODOS.items():
        try:
            conn = conectar(n)
        except Exception:
            mal(f"{nombre}: sin conexion")
            inalcanzables.append(nombre)
            continue
        gids = [r[0] for r in conn.execute(
            "SELECT gid FROM pg_prepared_xacts WHERE gid LIKE 'trp_%%' ORDER BY prepared").fetchall()]
        if not gids:
            ok(f"{nombre}: sin transacciones pendientes")
        for gid in gids:
            decision = bitacora.consultar(gid)
            if decision in ("DECISION_COMMIT", "PENDIENTE_COMMIT", "COMPLETADO"):
                conn.execute(sql.SQL("COMMIT PREPARED {}").format(sql.Literal(gid)))
                ok(f"{nombre}: {gid} -> COMMIT PREPARED (la bitacora dice {decision})")
                resueltas.append((gid, "commit"))
            else:
                conn.execute(sql.SQL("ROLLBACK PREPARED {}").format(sql.Literal(gid)))
                ok(f"{nombre}: {gid} -> ROLLBACK PREPARED (la bitacora dice {decision})")
                resueltas.append((gid, "rollback"))
        conn.close()

    if not inalcanzables:
        for gid, accion in resueltas:
            bitacora.estado(gid, "COMPLETADO" if accion == "commit" else "ABORTADO", "Resuelta por recuperacion")
    print(f"\nTransacciones resueltas: {len(resueltas)}. Nodos sin conexion: {len(inalcanzables)}")
    return 0


# =====================================================================
#  CONSULTA DE STOCK EN TODOS LOS NODOS
# =====================================================================
def mostrar_stock(producto, deptos=None):
    titulo(f"STOCK DEL PRODUCTO {producto}")
    deptos = deptos or list(DEPTO_A_NODO)
    for d in deptos:
        n = DEPTO_A_NODO[d]
        try:
            conn = conectar(n)
            fila = conn.execute(
                """SELECT a.nombre_almacen, i.stock_actual
                     FROM inventario i JOIN almacenes a USING (id_almacen)
                    WHERE a.departamento_id = %s AND i.id_producto = %s""", (d, producto)).fetchone()
            conn.close()
            if fila:
                print(f"  {d}  {fila[0]:<35} stock = {NEGRITA}{fila[1]}{FIN}")
            else:
                print(f"  {d}  (sin registro)")
        except Exception:
            print(f"  {d}  {ROJO}{NODOS[n][0]} SIN CONEXION{FIN}")


def main():
    p = argparse.ArgumentParser(description="Coordinador 2PC - BoliviaDistribucion")
    sub = p.add_subparsers(dest="cmd", required=True)

    t = sub.add_parser("traspaso", help="Traspaso de inventario entre departamentos (2PC)")
    t.add_argument("--origen", required=True, choices=list(DEPTO_A_NODO))
    t.add_argument("--destino", required=True, choices=list(DEPTO_A_NODO))
    t.add_argument("--producto", type=int, required=True)
    t.add_argument("--cantidad", type=int, required=True)
    t.add_argument("--pausa", type=int, default=0, help="segundos de pausa antes de la Fase 1")
    t.add_argument("--pausa-commit", type=int, default=0, help="segundos de pausa entre Fase 1 y Fase 2")

    s = sub.add_parser("stock", help="Ver stock de un producto en todos los departamentos")
    s.add_argument("--producto", type=int, required=True)

    sub.add_parser("recuperar", help="Resolver transacciones preparadas pendientes")

    a = p.parse_args()
    if a.cmd == "traspaso":
        if a.cantidad <= 0:
            p.error("--cantidad debe ser mayor que 0")
        return traspaso(a.origen, a.destino, a.producto, a.cantidad, a.pausa, a.pausa_commit)
    if a.cmd == "stock":
        mostrar_stock(a.producto)
        return 0
    return recuperar()


if __name__ == "__main__":
    sys.exit(main())
