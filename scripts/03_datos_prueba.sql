-- =====================================================================
--  CARGA DE DATOS DE PRUEBA (se ejecuta en CADA nodo, sobre sus datos)
--  Total nacional: 50.000 ventas  (LP 11000, SC 15000, CB 10000,
--                                   TJ+CH 6000, OR+PO 5000, BE+PA 3000)
--  Cada nodo lee su configuracion de la tabla nodo_info.
-- =====================================================================
SELECT nodo_id AS nodo, id_base AS base, ventas_a_generar AS n_ventas,
       400 * cardinality(departamentos) AS n_clientes
FROM nodo_info \gset

\echo '   - Clientes (' :n_clientes ')'
INSERT INTO clientes_datos_generales (id_cliente, nit_ci, razon_social, telefono, direccion, departamento_id)
SELECT :base + g,
       (:nodo * 1000000 + g * 13)::text,
       (ARRAY['Comercial','Distribuidora','Tienda','Minimarket','Importadora','Almacén','Farmacia','Restaurante'])[1 + g % 8]
         || ' ' ||
       (ARRAY['El Sol','Illimani','Andina','Oriental','San Miguel','La Esperanza','Los Andes',
              'Amazonía','Tupac','Del Valle','Santa Rosa','El Progreso'])[1 + (g * 7) % 12]
         || ' ' || g,
       (CASE WHEN g % 2 = 0 THEN '7' ELSE '6' END) || lpad(((g * 7919) % 10000000)::text, 7, '0'),
       (ARRAY['Av. Busch','Calle Comercio','Av. América','Calle Bolívar','Av. Blanco Galindo','Calle Junín'])[1 + g % 6]
         || ' #' || (g % 900 + 1),
       ni.departamentos[1 + g % cardinality(ni.departamentos)]
FROM generate_series(1, :n_clientes) AS g, nodo_info ni;

\echo '   - Almacenes'
INSERT INTO almacenes (id_almacen, nombre_almacen, departamento_id, direccion)
SELECT :base + row_number() OVER (ORDER BY d.departamento_id),
       'Almacén Central ' || d.nombre, d.departamento_id, 'Parque Industrial, ' || d.nombre
FROM departamentos d, nodo_info ni
WHERE d.departamento_id = ANY (ni.departamentos);

\echo '   - Inventario'
INSERT INTO inventario (id_almacen, id_producto, stock_actual, stock_minimo)
SELECT a.id_almacen, p.id_producto, 100 + (a.id_almacen + p.id_producto * 37) % 900, 20
FROM almacenes a CROSS JOIN productos_catalogo p;

\echo '   - Ventas (' :n_ventas ')'
INSERT INTO ventas (id_venta, fecha_hora, departamento_id, id_cliente, id_empleado, total_bs)
SELECT :base + g,
       timestamp '2026-01-01 08:00' + (random() * 320) * interval '1 day',
       c.departamento_id, c.id_cliente, :nodo * 100 + 1 + g % 25, 0
FROM generate_series(1, :n_ventas) AS g
JOIN clientes_datos_generales c ON c.id_cliente = :base + 1 + (g * 31) % :n_clientes;

\echo '   - Detalle de ventas'
INSERT INTO detalle_venta (id_detalle, id_venta, id_producto, cantidad, precio_aplicado, subtotal)
SELECT :base + row_number() OVER (ORDER BY v.id_venta, k),
       v.id_venta, p.id_producto, q.cantidad, p.precio_unitario, q.cantidad * p.precio_unitario
FROM ventas v
CROSS JOIN LATERAL generate_series(1, 1 + (v.id_venta % 3)::int) AS k
JOIN productos_catalogo p ON p.id_producto = 1 + ((v.id_venta * 7 + k * 53) % 200)
CROSS JOIN LATERAL (SELECT 1 + ((v.id_venta + k) % 6)::int AS cantidad) AS q;

UPDATE ventas v SET total_bs = s.total
FROM (SELECT id_venta, sum(subtotal) AS total FROM detalle_venta GROUP BY id_venta) s
WHERE s.id_venta = v.id_venta;

ANALYZE;
