-- =====================================================================
--  ESQUEMA LOCAL (se crea igual en los 6 nodos)
--  Cada nodo solo acepta filas de SUS departamentos (CHECK), lo que
--  materializa la fragmentacion horizontal por departamento_id.
--  Variables psql: :nodo :nombre :deptos_in :id_base :seq_start :n_ventas :es_central
-- =====================================================================

-- ---------- Identidad del nodo ----------
CREATE TABLE nodo_info (
    nodo_id           int PRIMARY KEY,
    nombre            text NOT NULL,
    departamentos     text[] NOT NULL,
    id_base           bigint NOT NULL,
    ventas_a_generar  int NOT NULL
);
INSERT INTO nodo_info VALUES (:nodo, :'nombre', ARRAY[:deptos_in], :id_base, :n_ventas);

-- ---------- Departamentos (tabla de referencia, igual en todos) ----------
CREATE TABLE departamentos (
    departamento_id varchar(2) PRIMARY KEY,
    nombre          varchar(30) NOT NULL,
    nodo_id         int NOT NULL
);
INSERT INTO departamentos VALUES
  ('LP','La Paz',1), ('SC','Santa Cruz',2), ('CB','Cochabamba',3),
  ('TJ','Tarija',4), ('CH','Chuquisaca',4),
  ('OR','Oruro',5),  ('PO','Potosí',5),
  ('BE','Beni',6),   ('PA','Pando',6);

-- ---------- Secuencias: cada nodo genera IDs en su propio rango ----------
-- Nodo 2 -> 20.000.000..., Nodo 6 -> 60.000.000...  => IDs unicos a nivel nacional
CREATE SEQUENCE seq_clientes  START :seq_start;
CREATE SEQUENCE seq_almacenes START :seq_start;
CREATE SEQUENCE seq_ventas    START :seq_start;
CREATE SEQUENCE seq_detalle   START :seq_start;

-- ---------- PRODUCTOS_CATALOGO (replicacion total) ----------
-- Maestro en La Paz; en los nodos 2-6 es una copia de solo lectura.
CREATE TABLE productos_catalogo (
    id_producto     int PRIMARY KEY,
    codigo_barras   varchar(20)   NOT NULL UNIQUE,
    nombre          varchar(120)  NOT NULL,
    descripcion     text,
    precio_unitario numeric(12,2) NOT NULL CHECK (precio_unitario > 0),
    categoria       varchar(50)   NOT NULL
);

-- ---------- CLIENTES_DATOS_GENERALES (fragmento vertical FC1) ----------
-- Ademas fragmentado horizontalmente por departamento.
CREATE TABLE clientes_datos_generales (
    id_cliente      bigint PRIMARY KEY DEFAULT nextval('seq_clientes'),
    nit_ci          varchar(20)  NOT NULL,
    razon_social    varchar(150) NOT NULL,
    telefono        varchar(20),
    direccion       varchar(200),
    departamento_id varchar(2)   NOT NULL REFERENCES departamentos,
    CONSTRAINT chk_fragmento_clientes CHECK (departamento_id IN (:deptos_in))
);

-- ---------- ALMACENES ----------
CREATE TABLE almacenes (
    id_almacen      bigint PRIMARY KEY DEFAULT nextval('seq_almacenes'),
    nombre_almacen  varchar(100) NOT NULL,
    departamento_id varchar(2)   NOT NULL REFERENCES departamentos,
    direccion       varchar(200),
    CONSTRAINT chk_fragmento_almacenes CHECK (departamento_id IN (:deptos_in))
);

-- ---------- INVENTARIO (fragmentacion derivada de ALMACENES) ----------
CREATE TABLE inventario (
    id_almacen   bigint NOT NULL REFERENCES almacenes,
    id_producto  int    NOT NULL REFERENCES productos_catalogo,
    stock_actual int    NOT NULL CHECK (stock_actual >= 0),
    stock_minimo int    NOT NULL DEFAULT 10,
    PRIMARY KEY (id_almacen, id_producto)
);

-- ---------- VENTAS (fragmentacion horizontal FVi) ----------
CREATE TABLE ventas (
    id_venta        bigint PRIMARY KEY DEFAULT nextval('seq_ventas'),
    fecha_hora      timestamp     NOT NULL DEFAULT now(),
    departamento_id varchar(2)    NOT NULL REFERENCES departamentos,
    id_cliente      bigint        NOT NULL REFERENCES clientes_datos_generales,
    id_empleado     int           NOT NULL,
    total_bs        numeric(14,2) NOT NULL DEFAULT 0,
    CONSTRAINT chk_fragmento_ventas CHECK (departamento_id IN (:deptos_in))
);
CREATE INDEX idx_ventas_fecha   ON ventas (fecha_hora);
CREATE INDEX idx_ventas_cliente ON ventas (id_cliente);

-- ---------- DETALLE_VENTA (fragmentacion derivada de VENTAS) ----------
CREATE TABLE detalle_venta (
    id_detalle      bigint PRIMARY KEY DEFAULT nextval('seq_detalle'),
    id_venta        bigint        NOT NULL REFERENCES ventas ON DELETE CASCADE,
    id_producto     int           NOT NULL REFERENCES productos_catalogo,
    cantidad        int           NOT NULL CHECK (cantidad > 0),
    precio_aplicado numeric(12,2) NOT NULL,
    subtotal        numeric(14,2) NOT NULL
);
CREATE INDEX idx_detalle_venta ON detalle_venta (id_venta);

-- ---------- TRASPASOS (registro local de cada movimiento 2PC) ----------
CREATE TABLE traspasos (
    id_traspaso      bigserial PRIMARY KEY,
    gid              varchar(100) NOT NULL,
    tipo             varchar(10)  NOT NULL CHECK (tipo IN ('SALIDA','ENTRADA')),
    id_almacen       bigint       NOT NULL REFERENCES almacenes,
    id_producto      int          NOT NULL,
    cantidad         int          NOT NULL,
    nodo_contraparte text         NOT NULL,
    fecha_hora       timestamp    NOT NULL DEFAULT now()
);

-- =====================================================================
--  Funcion de operacion LOCAL: registrar una venta usando solo datos
--  del propio nodo (catalogo replicado + inventario local).
--  Sirve para demostrar AUTONOMIA LOCAL aunque el nodo este aislado.
-- =====================================================================
CREATE FUNCTION registrar_venta(p_id_cliente bigint, p_id_producto int,
                                p_cantidad int, p_id_empleado int DEFAULT 1)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE
    v_dep     varchar(2);
    v_precio  numeric(12,2);
    v_almacen bigint;
    v_stock   int;
    v_id      bigint;
BEGIN
    SELECT departamento_id INTO v_dep FROM clientes_datos_generales WHERE id_cliente = p_id_cliente;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El cliente % no pertenece a este nodo', p_id_cliente;
    END IF;

    SELECT precio_unitario INTO v_precio FROM productos_catalogo WHERE id_producto = p_id_producto;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'El producto % no existe en el catalogo', p_id_producto;
    END IF;

    SELECT i.id_almacen, i.stock_actual INTO v_almacen, v_stock
      FROM inventario i JOIN almacenes a USING (id_almacen)
     WHERE a.departamento_id = v_dep AND i.id_producto = p_id_producto
     ORDER BY i.id_almacen LIMIT 1
       FOR UPDATE OF i;
    IF NOT FOUND OR v_stock < p_cantidad THEN
        RAISE EXCEPTION 'Stock insuficiente del producto % (disponible: %)', p_id_producto, coalesce(v_stock, 0);
    END IF;

    UPDATE inventario SET stock_actual = stock_actual - p_cantidad
     WHERE id_almacen = v_almacen AND id_producto = p_id_producto;

    INSERT INTO ventas (departamento_id, id_cliente, id_empleado, total_bs)
    VALUES (v_dep, p_id_cliente, p_id_empleado, v_precio * p_cantidad)
    RETURNING id_venta INTO v_id;

    INSERT INTO detalle_venta (id_venta, id_producto, cantidad, precio_aplicado, subtotal)
    VALUES (v_id, p_id_producto, p_cantidad, v_precio, v_precio * p_cantidad);

    RETURN v_id;
END $$;

-- =====================================================================
--  En los nodos 2-6 el catalogo es de SOLO LECTURA: solo La Paz lo
--  modifica y los cambios llegan por replicacion. (El proceso de
--  replicacion no dispara este trigger, los usuarios locales si.)
-- =====================================================================
\if :es_central
\else
CREATE FUNCTION bloquear_catalogo_local() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    RAISE EXCEPTION 'El catalogo es una REPLICA de solo lectura. Las modificaciones se hacen en el Nodo 1 (La Paz).';
END $$;

CREATE TRIGGER trg_catalogo_solo_lectura
BEFORE INSERT OR UPDATE OR DELETE ON productos_catalogo
FOR EACH ROW EXECUTE FUNCTION bloquear_catalogo_local();
\endif
