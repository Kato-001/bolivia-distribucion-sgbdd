-- =====================================================================
--  SOLO NODO 1 (LA PAZ): catalogo maestro, datos financieros,
--  publicacion de replicacion y bitacora del coordinador 2PC.
-- =====================================================================

-- ---------- Catalogo maestro: 200 productos ----------
INSERT INTO productos_catalogo (id_producto, codigo_barras, nombre, descripcion, precio_unitario, categoria)
SELECT g,
       '777' || lpad(g::text, 10, '0'),
       b.nombres[1 + (g - 1) % 20] || ' - ' || p.pres[1 + (g - 1) / 20],
       'Linea ' || b.cats[1 + (g - 1) % 20] || ', presentacion ' || p.pres[1 + (g - 1) / 20],
       round(b.precios[1 + (g - 1) % 20] * p.factor[1 + (g - 1) / 20], 2),
       b.cats[1 + (g - 1) % 20]
FROM generate_series(1, 200) AS g,
     (SELECT ARRAY['Arroz Estrella','Azúcar Blanca','Aceite Vegetal','Fideo Tallarín','Harina de Trigo',
                   'Leche Entera','Yogurt Frutilla','Queso Fresco','Gaseosa Cola','Agua Mineral',
                   'Cerveza Rubia','Café Yungueño','Quinua Real','Detergente en Polvo','Jabón de Tocador',
                   'Shampoo Familiar','Papel Higiénico','Soya en Grano','Cemento Portland','Casco Minero'] AS nombres,
             ARRAY['Abarrotes','Abarrotes','Abarrotes','Abarrotes','Abarrotes',
                   'Lácteos','Lácteos','Lácteos','Bebidas','Bebidas',
                   'Bebidas','Abarrotes','Agroindustria','Limpieza','Cuidado Personal',
                   'Cuidado Personal','Limpieza','Agroindustria','Construcción','Minería'] AS cats,
             ARRAY[9.5, 7.0, 14.0, 6.5, 8.0, 6.0, 9.0, 18.0, 10.0, 5.0,
                   12.0, 25.0, 22.0, 15.0, 4.5, 20.0, 3.5, 30.0, 58.0, 85.0]::numeric[] AS precios) AS b,
     (SELECT ARRAY['Unidad','Pack x3','Pack x6','Caja x12','Caja x24',
                   'Caja x48','Fardo x10','Fardo x20','Mayorista x50','Mayorista x100'] AS pres,
             ARRAY[1, 2.9, 5.6, 11, 21, 41, 9.5, 18.5, 45, 88]::numeric[] AS factor) AS p;

-- ---------- Publicacion: La Paz publica el catalogo a todos los nodos ----------
CREATE PUBLICATION pub_catalogo FOR TABLE productos_catalogo;

-- ---------- CLIENTES_FINANCIERO (fragmento vertical FC2) ----------
-- Existe UNICAMENTE en La Paz (seguridad y auditoria).
CREATE TABLE clientes_financiero (
    id_cliente          bigint PRIMARY KEY,
    limite_credito      numeric(14,2) NOT NULL,
    saldo_pendiente     numeric(14,2) NOT NULL DEFAULT 0,
    calificacion_riesgo varchar(1)    NOT NULL CHECK (calificacion_riesgo IN ('A','B','C','D')),
    estado_credito      varchar(15)   NOT NULL CHECK (estado_credito IN ('ACTIVO','SUSPENDIDO','BLOQUEADO'))
);

-- ---------- Bitacora del coordinador de transacciones distribuidas ----------
CREATE TABLE coordinador_2pc_log (
    gid          varchar(100) PRIMARY KEY,
    origen       varchar(2)   NOT NULL,
    destino      varchar(2)   NOT NULL,
    id_producto  int          NOT NULL,
    cantidad     int          NOT NULL,
    estado       varchar(30)  NOT NULL,
    detalle      text,
    creado       timestamp    NOT NULL DEFAULT now(),
    actualizado  timestamp    NOT NULL DEFAULT now()
);

-- ---------- Marca de configuracion (la usa configurar.sh) ----------
CREATE TABLE configuracion_global (
    clave varchar(50) PRIMARY KEY,
    valor text,
    fecha timestamp DEFAULT now()
);
