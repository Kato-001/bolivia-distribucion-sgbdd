#!/bin/bash
# =====================================================================
#  Se ejecuta automaticamente la PRIMERA vez que arranca cada nodo.
#  Crea el esquema local del nodo usando sus variables de entorno
#  (NODO_ID, NODO_NOMBRE, NODO_DEPTOS, NODO_VENTAS) del docker-compose.yml
# =====================================================================
set -e

# "TJ,CH"  ->  'TJ','CH'   (lista para usar en CHECK ... IN (...))
DEPTOS_IN=$(echo "$NODO_DEPTOS" | sed "s/[^,][^,]*/'&'/g")
ID_BASE=$((NODO_ID * 10000000))          # rango de IDs propio de cada nodo
SEQ_START=$((ID_BASE + 1000000))         # IDs para registros nuevos
if [ "$NODO_ID" = "1" ]; then ES_CENTRAL=true; else ES_CENTRAL=false; fi

echo ">>> Inicializando nodo $NODO_ID ($NODO_NOMBRE) - departamentos: $DEPTOS_IN"

psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
     -v nodo="$NODO_ID" \
     -v nombre="$NODO_NOMBRE" \
     -v deptos_in="$DEPTOS_IN" \
     -v id_base="$ID_BASE" \
     -v seq_start="$SEQ_START" \
     -v n_ventas="$NODO_VENTAS" \
     -v es_central="$ES_CENTRAL" \
     -f /scripts/01_esquema_local.sql

if [ "$ES_CENTRAL" = "true" ]; then
  psql -v ON_ERROR_STOP=1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
       -f /scripts/02_nodo_central.sql
fi

echo ">>> Nodo $NODO_ID listo."
