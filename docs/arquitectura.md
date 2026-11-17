# Documento de Arquitectura de Datos Distribuidos
## Sistema de Gestión Logística Nacional "BoliviaDistribución"

## 1. Plataforma elegida

| Componente | Tecnología | Motivo |
|---|---|---|
| Motor de cada nodo | PostgreSQL 16 | Libre, robusto y con soporte nativo de 2PC (`PREPARE TRANSACTION`) |
| Infraestructura | Docker + Docker Compose | Seis servidores aislados en un solo equipo, cada uno con su IP, su disco y su configuración |
| Transparencia | `postgres_fdw` + vistas | La Paz accede a las tablas remotas como si fueran locales |
| Replicación | Replicación lógica (PUBLICATION / SUBSCRIPTION) | Asíncrona, de La Paz hacia los demás nodos, y tolera desconexiones |
| Transacciones distribuidas | Coordinador 2PC en Python | Usa `PREPARE TRANSACTION`, `COMMIT PREPARED` y `ROLLBACK PREPARED` |
| Red | Red Docker `bolivia_red` | Desconectar un contenedor de esta red simula un corte de enlace |

## 2. Topología

```
                        ┌──────────────────────────────┐
                        │  NODO 1 - LA PAZ (central)   │
                        │  · ventas LP                 │
                        │  · CLIENTES_FINANCIERO (FC2) │
                        │  · catálogo MAESTRO ──┐      │
                        │  · vistas globales    │ pub  │
                        │  · bitácora 2PC       │      │
                        └───────┬───────────────┼──────┘
                  postgres_fdw  │  (consultas)  │ replicación lógica
      ┌───────────────┬─────────┼──────┬────────┴──────┬───────────────┐
      ▼               ▼         ▼      ▼               ▼               ▼
 ┌─────────┐   ┌────────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐
 │ NODO 2  │   │  NODO 3    │   │ NODO 4   │   │ NODO 5   │   │ NODO 6   │
 │ S. Cruz │   │ Cochabamba │   │ Tarija   │   │ Oruro    │   │ Beni     │
 │  SC     │   │  CB        │   │ TJ, CH   │   │ OR, PO   │   │ BE, PA   │
 └─────────┘   └────────────┘   └──────────┘   └──────────┘   └──────────┘
        ▲                                                          ▲
        └──────────── Coordinador 2PC (traspasos SC → BE) ─────────┘
```

## 3. Esquema global (modelo entidad-relación)

```
[PRODUCTOS_CATALOGO] 1 ── * [INVENTARIO] * ── 1 [ALMACENES]
        1│                                            
         │*                                           
 [DETALLE_VENTA] * ──────── 1 [VENTAS] * ── 1 [CLIENTES_DATOS_GENERALES]
                                                     1│
                                                     1│
                                             [CLIENTES_FINANCIERO]
```

- PRODUCTOS_CATALOGO(**id_producto**, codigo_barras, nombre, descripcion, precio_unitario, categoria)
- CLIENTES_DATOS_GENERALES(**id_cliente**, nit_ci, razon_social, telefono, direccion, departamento_id)
- CLIENTES_FINANCIERO(**id_cliente**, limite_credito, saldo_pendiente, calificacion_riesgo, estado_credito)
- VENTAS(**id_venta**, fecha_hora, departamento_id, id_cliente, id_empleado, total_bs)
- DETALLE_VENTA(**id_detalle**, id_venta, id_producto, cantidad, precio_aplicado, subtotal)
- ALMACENES(**id_almacen**, nombre_almacen, departamento_id, direccion)
- INVENTARIO(**id_almacen, id_producto**, stock_actual, stock_minimo)

Tablas auxiliares: `departamentos` (referencia), `nodo_info` (identidad del nodo), `traspasos` (registro local de los movimientos 2PC) y `coordinador_2pc_log` (bitácora del coordinador, solo en La Paz).

**Unicidad global de claves:** cada nodo genera sus IDs en un rango propio (nodo × 10.000.000). Por ejemplo, las ventas de Beni empiezan en 60.000.001. Así no hay choques de claves sin necesidad de coordinar entre nodos.

## 4. Fragmentación horizontal

### VENTAS (fragmentación primaria por `departamento_id`)

| Fragmento | Predicado | Nodo |
|---|---|---|
| FV1 | σ departamento_id = 'LP' (VENTAS) | Nodo 1 — La Paz |
| FV2 | σ departamento_id = 'SC' (VENTAS) | Nodo 2 — Santa Cruz |
| FV3 | σ departamento_id = 'CB' (VENTAS) | Nodo 3 — Cochabamba |
| FV4 | σ departamento_id ∈ {'TJ','CH'} (VENTAS) | Nodo 4 — Tarija |
| FV5 | σ departamento_id ∈ {'OR','PO'} (VENTAS) | Nodo 5 — Oruro |
| FV6 | σ departamento_id ∈ {'BE','PA'} (VENTAS) | Nodo 6 — Beni |

**Corrección de la fragmentación:**
- *Completitud:* los 9 departamentos están cubiertos por algún predicado.
- *Disyunción:* ningún departamento aparece en dos predicados.
- *Reconstrucción:* VENTAS = FV1 ∪ FV2 ∪ … ∪ FV6, implementada con la vista `ventas_nacionales` (`UNION ALL`).

**Implementación:** cada nodo tiene la restricción `CHECK (departamento_id IN (...))` (`chk_fragmento_ventas`), así que es imposible guardar una venta en el nodo equivocado. En La Paz, las tablas foráneas llevan el mismo `CHECK`, lo que permite al optimizador descartar los nodos que no hacen falta. Por ejemplo, `WHERE departamento_id='SC'` solo consulta el Nodo 2.

### DETALLE_VENTA, INVENTARIO y ALMACENES (fragmentación derivada)
- DETALLE_VENTA_i = DETALLE_VENTA ⋉ FV_i: cada detalle vive en el nodo de su venta (FK local).
- ALMACENES: fragmentada por `departamento_id` con los mismos predicados.
- INVENTARIO_i = INVENTARIO ⋉ ALMACENES_i: cada nodo gestiona solo el stock de sus almacenes.

## 5. Fragmentación vertical (CLIENTES)

| Fragmento | Proyección | Ubicación |
|---|---|---|
| FC1 (operativo) | π id_cliente, nit_ci, razon_social, telefono, direccion, departamento_id | Nodos 1 a 6, además fragmentado horizontalmente por departamento (fragmentación mixta) |
| FC2 (financiero) | π id_cliente, limite_credito, saldo_pendiente, calificacion_riesgo, estado_credito | **Solo en el Nodo 1 (La Paz)** |

- La clave `id_cliente` se repite en ambos fragmentos, lo que permite la reconstrucción sin pérdida: CLIENTES = FC1 ⋈ FC2 (vista `clientes_completos`).
- La tabla `clientes_financiero` **no existe** en los nodos 2 a 6, de modo que esos nodos no pueden filtrar los datos de crédito (requisito de auditoría y seguridad).

## 6. Replicación

| Tabla | Estrategia | Mecanismo |
|---|---|---|
| PRODUCTOS_CATALOGO | **Replicación total** en los 6 nodos | `CREATE PUBLICATION pub_catalogo` en La Paz y `CREATE SUBSCRIPTION` en los nodos 2 a 6 |
| DEPARTAMENTOS | Replicada (estática) | Se carga igual en todos los nodos al crearlos |

- **Copia primaria (maestro único):** solo La Paz modifica el catálogo. En los nodos 2 a 6, un trigger (`trg_catalogo_solo_lectura`) impide modificarlo localmente. El proceso de replicación no activa ese trigger.
- **Asíncrona y consistencia eventual:** si un nodo está desconectado, La Paz guarda los cambios en su *replication slot* y se los envía cuando el nodo vuelve. La vista `estado_replicacion` muestra cuántos bytes tiene pendientes cada nodo.

## 7. Transparencia

| Nivel | Cómo se logra |
|---|---|
| Localización | El analista escribe `SELECT * FROM ventas_nacionales` sin saber en qué nodo está cada venta |
| Fragmentación | Las vistas `ventas_nacionales`, `detalle_venta_nacional`, `clientes_nacionales`, `clientes_completos` e `inventario_nacional` reconstruyen las relaciones globales |
| Replicación | Cada nodo consulta `productos_catalogo` localmente, sin saber que es una copia |
| Tolerancia a fallos | `resumen_ventas_por_nodo()` y `ventas_nacionales_disponibles()` devuelven los datos de los nodos disponibles y avisan cuáles no responden |

## 8. Transacciones distribuidas: Compromiso en Dos Fases (2PC)

Caso: traspaso de inventario de **Santa Cruz → Beni**.

```
 Coordinador                 Santa Cruz (origen)            Beni (destino)
     │── BEGIN ──────────────────►│                               │
     │   UPDATE inventario -N     │ (bloquea la fila)             │
     │── BEGIN ────────────────────────────────────────────────── ►│
     │   UPSERT inventario +N     │                               │ (bloquea la fila)
     │                                                            │
     │══ FASE 1: PREPARE TRANSACTION 'gid' ═══►│ voto SÍ (guardado en disco)
     │══ FASE 1: PREPARE TRANSACTION 'gid' ════════════════════ ═►│ voto SÍ
     │                                                            │
     │   bitácora La Paz: DECISION_COMMIT                         │
     │══ FASE 2: COMMIT PREPARED 'gid' ═══════►│                  │
     │══ FASE 2: COMMIT PREPARED 'gid' ═══════════════════════════►│
```

**Manejo de fallos:**

| Momento de la falla | Qué hace el sistema |
|---|---|
| Beni no responde al conectar | No se modifica nada (ABORTADO) |
| Beni se cae antes o durante la FASE 1 | El coordinador decide ABORTAR y ejecuta **`ROLLBACK PREPARED` en Santa Cruz** (rollback automático, requisito del enunciado). La transacción de Beni, que nunca llegó a prepararse, la descarta PostgreSQL |
| Beni se cae después de votar SÍ (FASE 2) | La decisión COMMIT ya está en la bitácora. Santa Cruz confirma y Beni queda "en duda" (`pg_prepared_xacts`). Al volver, `recuperar` consulta la bitácora y ejecuta `COMMIT PREPARED` |
| Stock insuficiente en el origen | ABORTAR antes de la FASE 1 |

**Propiedades ACID:** la atomicidad la da 2PC; la consistencia, `CHECK (stock_actual >= 0)` junto con las FK; el aislamiento, `SELECT … FOR UPDATE`; y la durabilidad, que una transacción preparada sobrevive incluso a que el nodo se reinicie.

**Concurrencia:** dos traspasos sobre el mismo producto y almacén se serializan por el bloqueo de fila (`FOR UPDATE`). Las sesiones abandonadas se liberan gracias a `tcp_keepalives_*` e `idle_in_transaction_session_timeout`.

## 9. Matriz de distribución de datos (CRUD por nodo)

C = crear, R = leer, U = actualizar, D = eliminar. "R (fdw)" indica lectura remota a través de las vistas distribuidas.

| Tabla | N1 La Paz | N2 Santa Cruz | N3 Cochabamba | N4 Tarija | N5 Oruro | N6 Beni |
|---|---|---|---|---|---|---|
| PRODUCTOS_CATALOGO | **CRUD** (maestro) | R (réplica) | R (réplica) | R (réplica) | R (réplica) | R (réplica) |
| CLIENTES_DATOS_GENERALES | CRUD (LP) + R (fdw) de todos | CRUD (SC) | CRUD (CB) | CRUD (TJ, CH) | CRUD (OR, PO) | CRUD (BE, PA) |
| CLIENTES_FINANCIERO | **CRUD** (exclusivo) | — | — | — | — | — |
| VENTAS | CRUD (LP) + R (fdw) de todos | CRUD (SC) | CRUD (CB) | CRUD (TJ, CH) | CRUD (OR, PO) | CRUD (BE, PA) |
| DETALLE_VENTA | CRUD (LP) + R (fdw) de todos | CRUD (SC) | CRUD (CB) | CRUD (TJ, CH) | CRUD (OR, PO) | CRUD (BE, PA) |
| ALMACENES | CRUD (LP) + R (fdw) de todos | CRUD (SC) | CRUD (CB) | CRUD (TJ, CH) | CRUD (OR, PO) | CRUD (BE, PA) |
| INVENTARIO | CRUD (LP) + R (fdw) de todos | CRUD + U por 2PC | CRUD + U por 2PC | CRUD + U por 2PC | CRUD + U por 2PC | CRUD + U por 2PC |
| COORDINADOR_2PC_LOG | **CRUD** (exclusivo) | — | — | — | — | — |

## 10. Justificación de las decisiones

1. **Ventas fragmentadas por departamento:** el 95 % de las operaciones (registrar ventas, facturar) son locales. Tener los datos en el nodo donde se generan elimina la latencia de red y permite que cada región siga operando aunque se corte su enlace (autonomía local).
2. **Sub-nodos regionales (TJ+CH, OR+PO, BE+PA):** agrupar departamentos de bajo volumen reduce costos de infraestructura sin perder cercanía geográfica.
3. **Datos financieros solo en La Paz:** concentrar la información crediticia en un único nodo controlado facilita la auditoría y el cumplimiento regulatorio, y reduce la superficie de exposición. La consulta de crédito, que es poco frecuente, sí requiere red, pero es una operación administrativa central.
4. **Catálogo con replicación total:** es una tabla pequeña (200 productos), con muchas lecturas (cada venta la consulta) y pocas escrituras. Replicarla hace que validar precios sea 100 % local. Se eligió replicación asíncrona porque un precio desactualizado unos segundos es aceptable, mientras que bloquear las ventas por esperar a La Paz no lo es. Esto es especialmente importante en Beni, que tiene poco ancho de banda.
5. **2PC solo para traspasos:** es la única operación que modifica dos nodos a la vez y donde la inconsistencia (mercadería duplicada o perdida) es inaceptable, así que su costo extra se justifica.
