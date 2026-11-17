#!/bin/bash
# =====================================================================
#  CONFIGURADOR: se ejecuta una sola vez cuando los 6 nodos estan listos.
#   1) Suscribe los nodos 2-6 al catalogo de La Paz (replicacion)
#   2) Espera a que el catalogo llegue a todos los nodos
#   3) Carga datos de prueba en cada nodo (50.000 ventas en total)
#   4) Conecta La Paz con los demas nodos (postgres_fdw) y crea vistas
#   5) Carga el fragmento financiero de clientes en La Paz
# =====================================================================
set -e

CENTRAL=nodo1_lapaz
NODOS=(nodo1_lapaz nodo2_santacruz nodo3_cochabamba nodo4_tarija nodo5_oruro nodo6_beni)
REMOTOS=(nodo2_santacruz nodo3_cochabamba nodo4_tarija nodo5_oruro nodo6_beni)

ejecutar() {   # ejecutar <host> [opciones psql...]
  local host=$1; shift
  psql -h "$host" -v ON_ERROR_STOP=1 -q "$@"
}

YA=$(psql -h $CENTRAL -tAc "SELECT 1 FROM configuracion_global WHERE clave='configurado'")
if [ "$YA" = "1" ]; then
  echo "El sistema ya estaba configurado. Nada que hacer."
  exit 0
fi

echo "=========================================================="
echo " 1) Replicacion del catalogo: La Paz -> nodos 2..6"
echo "=========================================================="
for n in "${REMOTOS[@]}"; do
  EXISTE=$(psql -h "$n" -tAc "SELECT 1 FROM pg_subscription WHERE subname='sub_catalogo_$n'")
  if [ "$EXISTE" != "1" ]; then
    psql -h "$n" -v ON_ERROR_STOP=1 -q -c \
      "CREATE SUBSCRIPTION sub_catalogo_$n
         CONNECTION 'host=$CENTRAL port=5432 dbname=bolivia user=postgres password=$PGPASSWORD'
         PUBLICATION pub_catalogo;"
  fi
  echo "   $n suscrito a pub_catalogo"
done

echo "=========================================================="
echo " 2) Esperando sincronizacion inicial del catalogo..."
echo "=========================================================="
for n in "${REMOTOS[@]}"; do
  for i in $(seq 1 60); do
    C=$(psql -h "$n" -tAc "SELECT count(*) FROM productos_catalogo")
    [ "$C" = "200" ] && break
    sleep 2
  done
  echo "   $n: $C productos"
  [ "$C" = "200" ] || { echo "ERROR: el catalogo no llego a $n"; exit 1; }
done

echo "=========================================================="
echo " 3) Cargando datos de prueba en cada nodo"
echo "=========================================================="
for n in "${NODOS[@]}"; do
  echo " -> $n"
  ejecutar "$n" -f /scripts/03_datos_prueba.sql
done

echo "=========================================================="
echo " 4) Transparencia: postgres_fdw + vistas distribuidas en La Paz"
echo "=========================================================="
ejecutar $CENTRAL -v pg_password="$PGPASSWORD" -f /scripts/04_fdw_vistas.sql

echo "=========================================================="
echo " 5) Fragmento financiero de clientes (solo La Paz)"
echo "=========================================================="
ejecutar $CENTRAL -f /scripts/05_clientes_financiero.sql

psql -h $CENTRAL -q -c "INSERT INTO configuracion_global VALUES ('configurado','si')"

echo "=========================================================="
echo " RESUMEN (consultado desde La Paz con la vista distribuida)"
echo "=========================================================="
psql -h $CENTRAL -c "SELECT nodo_origen, count(*) AS ventas, sum(total_bs) AS total_bs
                     FROM ventas_nacionales GROUP BY nodo_origen ORDER BY nodo_origen;"
psql -h $CENTRAL -c "SELECT count(*) AS total_ventas_nacionales FROM ventas_nacionales;"
echo "SISTEMA DISTRIBUIDO LISTO."
