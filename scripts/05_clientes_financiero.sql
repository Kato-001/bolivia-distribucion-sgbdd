-- =====================================================================
--  SOLO NODO 1 (LA PAZ): carga el fragmento vertical FC2 (financiero)
--  para todos los clientes del pais (se leen via la vista distribuida).
-- =====================================================================
INSERT INTO clientes_financiero (id_cliente, limite_credito, saldo_pendiente, calificacion_riesgo, estado_credito)
SELECT id_cliente,
       (ARRAY[5000, 10000, 20000, 50000, 100000])[1 + id_cliente % 5],
       round(((id_cliente * 37) % 5000)::numeric, 2),
       (ARRAY['A','A','B','B','C','D'])[1 + id_cliente % 6],
       CASE WHEN id_cliente % 17 = 0 THEN 'SUSPENDIDO'
            WHEN id_cliente % 41 = 0 THEN 'BLOQUEADO'
            ELSE 'ACTIVO' END
FROM clientes_nacionales
ON CONFLICT (id_cliente) DO NOTHING;

ANALYZE clientes_financiero;
