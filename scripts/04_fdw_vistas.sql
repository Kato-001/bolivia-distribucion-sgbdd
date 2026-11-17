-- =====================================================================
--  SOLO NODO 1 (LA PAZ): TRANSPARENCIA DE LOCALIZACION
--  postgres_fdw conecta La Paz con los otros 5 nodos. Cada nodo remoto
--  aparece como un esquema (nodo2 ... nodo6) con "tablas foraneas".
--  Luego unas VISTAS unen todo, de modo que el analista solo escribe:
--        SELECT * FROM ventas_nacionales;
-- =====================================================================
CREATE EXTENSION IF NOT EXISTS postgres_fdw;

-- ---------- Servidores remotos ----------
CREATE SERVER srv_nodo2 FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host 'nodo2_santacruz',  port '5432', dbname 'bolivia', connect_timeout '3', fetch_size '10000');
CREATE SERVER srv_nodo3 FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host 'nodo3_cochabamba', port '5432', dbname 'bolivia', connect_timeout '3', fetch_size '10000');
CREATE SERVER srv_nodo4 FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host 'nodo4_tarija',     port '5432', dbname 'bolivia', connect_timeout '3', fetch_size '10000');
CREATE SERVER srv_nodo5 FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host 'nodo5_oruro',      port '5432', dbname 'bolivia', connect_timeout '3', fetch_size '10000');
CREATE SERVER srv_nodo6 FOREIGN DATA WRAPPER postgres_fdw
  OPTIONS (host 'nodo6_beni',       port '5432', dbname 'bolivia', connect_timeout '3', fetch_size '10000');

CREATE USER MAPPING FOR postgres SERVER srv_nodo2 OPTIONS (user 'postgres', password :'pg_password');
CREATE USER MAPPING FOR postgres SERVER srv_nodo3 OPTIONS (user 'postgres', password :'pg_password');
CREATE USER MAPPING FOR postgres SERVER srv_nodo4 OPTIONS (user 'postgres', password :'pg_password');
CREATE USER MAPPING FOR postgres SERVER srv_nodo5 OPTIONS (user 'postgres', password :'pg_password');
CREATE USER MAPPING FOR postgres SERVER srv_nodo6 OPTIONS (user 'postgres', password :'pg_password');

-- ---------- Importar las tablas de cada nodo como tablas foraneas ----------
CREATE SCHEMA nodo2; CREATE SCHEMA nodo3; CREATE SCHEMA nodo4; CREATE SCHEMA nodo5; CREATE SCHEMA nodo6;

IMPORT FOREIGN SCHEMA public LIMIT TO (ventas, detalle_venta, clientes_datos_generales, almacenes, inventario, traspasos, productos_catalogo)
  FROM SERVER srv_nodo2 INTO nodo2;
IMPORT FOREIGN SCHEMA public LIMIT TO (ventas, detalle_venta, clientes_datos_generales, almacenes, inventario, traspasos, productos_catalogo)
  FROM SERVER srv_nodo3 INTO nodo3;
IMPORT FOREIGN SCHEMA public LIMIT TO (ventas, detalle_venta, clientes_datos_generales, almacenes, inventario, traspasos, productos_catalogo)
  FROM SERVER srv_nodo4 INTO nodo4;
IMPORT FOREIGN SCHEMA public LIMIT TO (ventas, detalle_venta, clientes_datos_generales, almacenes, inventario, traspasos, productos_catalogo)
  FROM SERVER srv_nodo5 INTO nodo5;
IMPORT FOREIGN SCHEMA public LIMIT TO (ventas, detalle_venta, clientes_datos_generales, almacenes, inventario, traspasos, productos_catalogo)
  FROM SERVER srv_nodo6 INTO nodo6;

-- ---------- Predicados de fragmentacion en las tablas foraneas ----------
-- Le dicen al optimizador que datos tiene cada nodo. Asi, una consulta
-- con WHERE departamento_id = 'SC' SOLO va al nodo de Santa Cruz
-- (y funciona aunque Beni este caido).
ALTER FOREIGN TABLE nodo2.ventas ADD CONSTRAINT chk_fv2 CHECK (departamento_id IN ('SC'));
ALTER FOREIGN TABLE nodo3.ventas ADD CONSTRAINT chk_fv3 CHECK (departamento_id IN ('CB'));
ALTER FOREIGN TABLE nodo4.ventas ADD CONSTRAINT chk_fv4 CHECK (departamento_id IN ('TJ','CH'));
ALTER FOREIGN TABLE nodo5.ventas ADD CONSTRAINT chk_fv5 CHECK (departamento_id IN ('OR','PO'));
ALTER FOREIGN TABLE nodo6.ventas ADD CONSTRAINT chk_fv6 CHECK (departamento_id IN ('BE','PA'));

ALTER FOREIGN TABLE nodo2.clientes_datos_generales ADD CONSTRAINT chk_fc2 CHECK (departamento_id IN ('SC'));
ALTER FOREIGN TABLE nodo3.clientes_datos_generales ADD CONSTRAINT chk_fc3 CHECK (departamento_id IN ('CB'));
ALTER FOREIGN TABLE nodo4.clientes_datos_generales ADD CONSTRAINT chk_fc4 CHECK (departamento_id IN ('TJ','CH'));
ALTER FOREIGN TABLE nodo5.clientes_datos_generales ADD CONSTRAINT chk_fc5 CHECK (departamento_id IN ('OR','PO'));
ALTER FOREIGN TABLE nodo6.clientes_datos_generales ADD CONSTRAINT chk_fc6 CHECK (departamento_id IN ('BE','PA'));

-- =====================================================================
--  VISTAS DISTRIBUIDAS (reconstruccion de las relaciones globales)
--  VENTAS = FV1 U FV2 U FV3 U FV4 U FV5 U FV6
-- =====================================================================
CREATE VIEW ventas_nacionales AS
          SELECT v.*, 'Nodo 1 - La Paz'::text     AS nodo_origen FROM public.ventas v
UNION ALL SELECT v.*, 'Nodo 2 - Santa Cruz'::text AS nodo_origen FROM nodo2.ventas  v
UNION ALL SELECT v.*, 'Nodo 3 - Cochabamba'::text AS nodo_origen FROM nodo3.ventas  v
UNION ALL SELECT v.*, 'Nodo 4 - Tarija'::text     AS nodo_origen FROM nodo4.ventas  v
UNION ALL SELECT v.*, 'Nodo 5 - Oruro'::text      AS nodo_origen FROM nodo5.ventas  v
UNION ALL SELECT v.*, 'Nodo 6 - Beni'::text       AS nodo_origen FROM nodo6.ventas  v;

CREATE VIEW detalle_venta_nacional AS
          SELECT * FROM public.detalle_venta
UNION ALL SELECT * FROM nodo2.detalle_venta
UNION ALL SELECT * FROM nodo3.detalle_venta
UNION ALL SELECT * FROM nodo4.detalle_venta
UNION ALL SELECT * FROM nodo5.detalle_venta
UNION ALL SELECT * FROM nodo6.detalle_venta;

-- Fragmento vertical FC1 (todos los nodos)
CREATE VIEW clientes_nacionales AS
          SELECT * FROM public.clientes_datos_generales
UNION ALL SELECT * FROM nodo2.clientes_datos_generales
UNION ALL SELECT * FROM nodo3.clientes_datos_generales
UNION ALL SELECT * FROM nodo4.clientes_datos_generales
UNION ALL SELECT * FROM nodo5.clientes_datos_generales
UNION ALL SELECT * FROM nodo6.clientes_datos_generales;

-- Reconstruccion de la fragmentacion VERTICAL: CLIENTES = FC1 |X| FC2
CREATE VIEW clientes_completos AS
SELECT c.id_cliente, c.nit_ci, c.razon_social, c.telefono, c.direccion, c.departamento_id,
       f.limite_credito, f.saldo_pendiente, f.calificacion_riesgo, f.estado_credito
FROM clientes_nacionales c
LEFT JOIN clientes_financiero f USING (id_cliente);

CREATE VIEW inventario_nacional AS
SELECT a.departamento_id, a.nombre_almacen, i.*
FROM (          SELECT * FROM public.almacenes
      UNION ALL SELECT * FROM nodo2.almacenes
      UNION ALL SELECT * FROM nodo3.almacenes
      UNION ALL SELECT * FROM nodo4.almacenes
      UNION ALL SELECT * FROM nodo5.almacenes
      UNION ALL SELECT * FROM nodo6.almacenes) a
JOIN (          SELECT * FROM public.inventario
      UNION ALL SELECT * FROM nodo2.inventario
      UNION ALL SELECT * FROM nodo3.inventario
      UNION ALL SELECT * FROM nodo4.inventario
      UNION ALL SELECT * FROM nodo5.inventario
      UNION ALL SELECT * FROM nodo6.inventario) i USING (id_almacen);

-- Ejemplo de JOIN distribuido (Fase 3): ventas de Tarija + credito en La Paz
CREATE VIEW ventas_tarija_con_credito AS
SELECT v.id_venta, v.fecha_hora, v.departamento_id, v.total_bs,
       c.razon_social, c.nit_ci, f.limite_credito, f.saldo_pendiente,
       f.calificacion_riesgo, f.estado_credito
FROM nodo4.ventas v
JOIN nodo4.clientes_datos_generales c USING (id_cliente)
JOIN clientes_financiero f USING (id_cliente);    -- este fragmento esta en La Paz

-- =====================================================================
--  Consultas globales TOLERANTES A FALLOS: si un nodo esta caido,
--  devuelven lo disponible y avisan cual nodo no respondio.
-- =====================================================================
CREATE FUNCTION resumen_ventas_por_nodo()
RETURNS TABLE (nodo text, estado text, cantidad_ventas bigint, total_bs numeric)
LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES ('public','Nodo 1 - La Paz'), ('nodo2','Nodo 2 - Santa Cruz'),
                                   ('nodo3','Nodo 3 - Cochabamba'), ('nodo4','Nodo 4 - Tarija'),
                                   ('nodo5','Nodo 5 - Oruro'), ('nodo6','Nodo 6 - Beni')) AS t(esquema, nombre)
    LOOP
        nodo := r.nombre;
        BEGIN
            EXECUTE format('SELECT count(*), coalesce(sum(total_bs),0) FROM %I.ventas', r.esquema)
               INTO cantidad_ventas, total_bs;
            estado := 'EN LINEA';
        EXCEPTION WHEN OTHERS THEN
            estado := 'SIN CONEXION';
            cantidad_ventas := NULL; total_bs := NULL;
        END;
        RETURN NEXT;
    END LOOP;
END $$;

CREATE FUNCTION ventas_nacionales_disponibles()
RETURNS SETOF ventas_nacionales LANGUAGE plpgsql AS $$
DECLARE r record;
BEGIN
    FOR r IN SELECT * FROM (VALUES ('public','Nodo 1 - La Paz'), ('nodo2','Nodo 2 - Santa Cruz'),
                                   ('nodo3','Nodo 3 - Cochabamba'), ('nodo4','Nodo 4 - Tarija'),
                                   ('nodo5','Nodo 5 - Oruro'), ('nodo6','Nodo 6 - Beni')) AS t(esquema, nombre)
    LOOP
        BEGIN
            RETURN QUERY EXECUTE format('SELECT v.*, %L::text FROM %I.ventas v', r.nombre, r.esquema);
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'AVISO: % no disponible (%). Se devuelven los datos de los nodos en linea.', r.nombre, SQLERRM;
        END;
    END LOOP;
END $$;

-- Estado de la replicacion del catalogo vista desde La Paz
CREATE VIEW estado_replicacion AS
SELECT application_name AS suscriptor, state AS estado, sent_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS bytes_pendientes
FROM pg_stat_replication;
