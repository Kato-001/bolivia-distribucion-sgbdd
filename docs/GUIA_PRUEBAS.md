# Guía de pruebas y demostración para la sustentación

Este es el guion para demostrar **en vivo** que el sistema cumple cada punto de la rúbrica. Cada prueba indica el comando, **qué se debe ver** y **qué decir**.

> **Antes de la presentación**
> 1. Abre Docker Desktop y espera a que diga *Engine running*.
> 2. En la carpeta del proyecto, ejecuta `docker compose start` (o `.\demo.ps1 iniciar` si es la primera vez).
> 3. Ejecuta `.\demo.ps1 estado` y comprueba que los 6 nodos dicen **EN LINEA**.
> 4. Ten abiertas **dos ventanas de PowerShell** en la carpeta del proyecto.
> 5. Haz un ensayo completo el día anterior. Si algo quedó raro, `.\demo.ps1 reiniciar` lo deja como nuevo.

| # | Prueba | Criterio de la rúbrica | Peso |
|---|---|---|---|
| 1 | Los 6 nodos funcionando en Docker | Demostración práctica | 20 % |
| 2 | Fragmentación horizontal | Diseño y fragmentación | 25 % |
| 3 | Fragmentación vertical | Diseño y fragmentación | 25 % |
| 4 | Replicación del catálogo | Diseño y fragmentación | 25 % |
| 5 | Transparencia: `SELECT * FROM ventas_nacionales` | Autonomía local y transparencia | 25 % |
| 6 | JOIN distribuido entre nodos | Autonomía local y transparencia | 25 % |
| 7 | Caída de nodo y autonomía local | Autonomía local y transparencia | 25 % |
| 8 | Consistencia eventual del catálogo | Autonomía local y transparencia | 25 % |
| 9 | Traspaso con 2PC | Transacciones y concurrencia | 25 % |
| 10 | Beni se cae a mitad del traspaso y se hace rollback | Transacciones y concurrencia | 25 % |
| 11 | Recuperación de una transacción en duda | Transacciones y concurrencia | 25 % |
| 12 | Concurrencia: dos traspasos a la vez | Transacciones y concurrencia | 25 % |
| — | Documentación (README, arquitectura, scripts DDL/DML) | Documentación técnica | 5 % |

---

## Prueba 1 — La infraestructura: 6 nodos en Docker

```powershell
docker compose ps
.\demo.ps1 estado
```
**Se debe ver:** 6 contenedores `nodo1_lapaz` … `nodo6_beni` con estado *healthy*, y la tabla de ventas por nodo con todos **EN LINEA**. Entre todos suman 50.000 ventas.

**Qué decir:** "Cada contenedor es un servidor PostgreSQL 16 independiente, con su propio disco y su propia IP dentro de la red `bolivia_red`. Representan los 6 nodos regionales del enunciado."

---

## Prueba 2 — Fragmentación horizontal (VENTAS por departamento)

```powershell
.\demo.ps1 sql santacruz "SELECT departamento_id, count(*) FROM ventas GROUP BY 1;"
.\demo.ps1 sql tarija    "SELECT departamento_id, count(*) FROM ventas GROUP BY 1;"
.\demo.ps1 sql beni      "SELECT departamento_id, count(*) FROM ventas GROUP BY 1;"
```
**Se debe ver:** Santa Cruz solo tiene `SC`, Tarija tiene `TJ` y `CH`, y Beni tiene `BE` y `PA`.

Ahora intenta guardar una venta en el nodo equivocado:
```powershell
.\demo.ps1 sql santacruz "INSERT INTO ventas (departamento_id,id_cliente,id_empleado) VALUES ('LP',20000001,1);"
```
**Se debe ver:** `ERROR: ... violates check constraint "chk_fragmento_ventas"`.

**Qué decir:** "Cada fragmento FVi = σ departamento_id ∈ {...}(VENTAS) se implementa con un `CHECK`, así que físicamente es imposible guardar una venta de La Paz en Santa Cruz. DETALLE_VENTA e INVENTARIO usan fragmentación derivada."

---

## Prueba 3 — Fragmentación vertical (CLIENTES)

```powershell
.\demo.ps1 sql beni  "SELECT * FROM clientes_datos_generales LIMIT 3;"
.\demo.ps1 sql beni  "SELECT * FROM clientes_financiero;"
.\demo.ps1 sql lapaz "SELECT * FROM clientes_financiero LIMIT 3;"
.\demo.ps1 sql lapaz "SELECT * FROM clientes_completos WHERE departamento_id='PA' LIMIT 3;"
```
**Se debe ver:**
- Beni tiene los datos generales de sus clientes.
- En Beni, `clientes_financiero` **no existe** (ERROR).
- En La Paz están los datos financieros de **todos** los clientes del país.
- `clientes_completos` une los dos fragmentos (FC1 ⋈ FC2).

**Qué decir:** "Los datos de crédito están solo en La Paz por auditoría y seguridad. Si un nodo regional se ve comprometido, no expone información financiera."

---

## Prueba 4 — Replicación total del catálogo

```powershell
.\demo.ps1 sql oruro "SELECT count(*) FROM productos_catalogo;"
.\demo.ps1 sql beni  "UPDATE productos_catalogo SET precio_unitario = 1 WHERE id_producto = 1;"
.\demo.ps1 sql lapaz "SELECT * FROM estado_replicacion;"
```
**Se debe ver:**
- Oruro tiene los 200 productos (copia local).
- En Beni no se puede modificar: `El catalogo es una REPLICA de solo lectura...`.
- La Paz muestra 5 suscriptores en estado `streaming`.

**Qué decir:** "La Paz publica el catálogo con replicación lógica (PUBLICATION/SUBSCRIPTION), de forma asíncrona. Cada venta valida el precio localmente, sin usar la red."

---

## Prueba 5 — Transparencia de localización y fragmentación

```powershell
.\demo.ps1 psql lapaz
```
```sql
SELECT * FROM ventas_nacionales LIMIT 10;
SELECT count(*) FROM ventas_nacionales;
SELECT departamento_id, count(*) AS ventas, sum(total_bs) AS total
FROM ventas_nacionales GROUP BY 1 ORDER BY 1;
```
**Se debe ver:** 50.000 ventas de los 9 departamentos en una sola consulta.

Para mostrar que el optimizador sabe dónde está cada dato:
```sql
EXPLAIN SELECT count(*) FROM ventas_nacionales WHERE departamento_id = 'SC';
```
**Se debe ver:** un solo `Foreign Scan`, es decir, solo consulta Santa Cruz y no los 6 nodos.

**Qué decir:** "El analista no sabe dónde están los datos. `postgres_fdw` conecta La Paz con los demás nodos, y la vista reconstruye VENTAS = FV1 ∪ … ∪ FV6. Los CHECK de las tablas foráneas permiten descartar los nodos que no hacen falta."

---

## Prueba 6 — JOIN distribuido (cliente en La Paz + ventas en Tarija)

Sigue en la consola de La Paz:
```sql
SELECT * FROM ventas_tarija_con_credito WHERE estado_credito <> 'ACTIVO' LIMIT 10;

-- Top 5 clientes de Tarija y Chuquisaca con su riesgo crediticio
SELECT c.razon_social, c.departamento_id, f.calificacion_riesgo,
       count(*) AS compras, sum(v.total_bs) AS total
FROM nodo4.ventas v
JOIN nodo4.clientes_datos_generales c USING (id_cliente)
JOIN clientes_financiero f USING (id_cliente)
GROUP BY 1,2,3 ORDER BY total DESC LIMIT 5;
\q
```
**Qué decir:** "Esta consulta une datos de dos nodos distintos: ventas y clientes de Tarija con el fragmento financiero de La Paz."

---

## Prueba 7 — Caída de un nodo y autonomía local

```powershell
.\demo.ps1 cortar beni
.\demo.ps1 estado
```
**Se debe ver:** Beni aparece como **RED CORTADA** y en la tabla como **SIN CONEXION**; los otros 5 nodos siguen **EN LINEA**.

```powershell
.\demo.ps1 venta santacruz
.\demo.ps1 venta beni
```
**Se debe ver:** las dos ventas se registran. Beni sigue vendiendo aunque está aislado del país.

```powershell
.\demo.ps1 sql lapaz "SELECT count(*) FROM ventas_nacionales WHERE departamento_id = 'SC';"
.\demo.ps1 sql lapaz "SELECT count(*) FROM ventas_nacionales_disponibles();"
```
**Se debe ver:** la primera consulta funciona aunque Beni esté caído, porque no lo necesita. La segunda devuelve las ventas de los nodos en línea con el aviso `Nodo 6 - Beni no disponible`.

**Qué decir:** "Cada nodo tiene todo lo que necesita para vender (clientes, inventario y una copia del catálogo), así que opera con autonomía local. Las consultas globales siguen funcionando con los nodos disponibles."

**No reconectes Beni todavía**: se usa en la prueba siguiente.

---

## Prueba 8 — Consistencia eventual del catálogo

Con Beni todavía desconectado:
```powershell
.\demo.ps1 catalogo 10 99.90
```
**Se debe ver:** en 1 segundo, La Paz, Santa Cruz, Cochabamba, Tarija y Oruro tienen **Bs 99.90**, pero Beni sigue con **Bs 5.00** (en amarillo). La tabla de replicación muestra `bytes_pendientes` > 0 para Beni.

```powershell
.\demo.ps1 reconectar beni
.\demo.ps1 sql beni "SELECT id_producto, nombre, precio_unitario FROM productos_catalogo WHERE id_producto = 10;"
```
**Se debe ver:** unos segundos después, Beni muestra **99.90**: recibió el cambio que tenía pendiente.

```powershell
.\demo.ps1 catalogo 10 5.00
```
(restaura el precio)

**Qué decir:** "La replicación es asíncrona, por eso la consistencia es eventual. La Paz guarda los cambios de Beni en un *replication slot* y se los entrega cuando vuelve. No se pierde ninguna actualización."

---

## Prueba 9 — Transacción distribuida con 2PC (Santa Cruz → Beni)

```powershell
.\demo.ps1 stock 10
.\demo.ps1 traspaso SC BE 10 5
```
**Se debe ver:**
```
=== FASE 1: PREPARACION (votacion) ===
  [OK] Nodo 2 - Santa Cruz voto SI
  [OK] Nodo 6 - Beni voto SI
=== DECISION GLOBAL: CONFIRMAR ===
=== FASE 2: CONFIRMACION (COMMIT PREPARED) ===
TRASPASO COMPLETADO en ambos nodos
  SC ... stock = (bajó 5)
  BE ... stock = (subió 5)
```
**Qué decir:** "En la fase 1, cada nodo ejecuta `PREPARE TRANSACTION`: guarda los cambios en disco y vota SÍ. Solo si los dos votan SÍ, el coordinador registra la decisión en la bitácora de La Paz y ejecuta `COMMIT PREPARED` en ambos."

---

## Prueba 10 — Beni pierde conexión a mitad del traspaso → ROLLBACK automático ⭐

**Es la prueba más importante del enunciado.**

```powershell
.\demo.ps1 caida-traspaso
```
El script hace todo solo. Inicia un traspaso de 25 unidades de Santa Cruz a Beni, y a los 8 segundos **corta la red de Beni**.

**Se debe ver:**
```
  [OK] Nodo 2 - Santa Cruz voto SI (transaccion preparada)
  -> Enviando PREPARE TRANSACTION a Nodo 6 - Beni ...
=== DECISION GLOBAL: ABORTAR (ROLLBACK) ===
  [X] Nodo 6 - Beni no pudo preparar / perdio conexion
  [OK] ROLLBACK PREPARED ejecutado en Nodo 2 - Santa Cruz
TRASPASO ABORTADO. Ningun nodo quedo modificado (atomicidad).
```
Luego muestra que el stock de Santa Cruz **no cambió**, que no quedan transacciones colgadas (`pg_prepared_xacts` vacío) y que la bitácora dice **ABORTADO**.

**Qué decir:** "Santa Cruz ya había preparado su parte, pero Beni no respondió. El coordinador decidió abortar y deshizo automáticamente la transacción en Santa Cruz. No se pierde mercadería ni aparece duplicada: se cumple la atomicidad."

---

## Prueba 11 — Recuperación de una transacción "en duda" (punto extra)

Esta prueba usa **dos ventanas** de PowerShell.

**Ventana 1:**
```powershell
docker compose run --rm coordinador traspaso --origen SC --destino BE --producto 20 --cantidad 7 --pausa-commit 15
```
**Ventana 2**, cuando aparezca `PAUSA DE DEMOSTRACION: ambos nodos estan PREPARADOS`:
```powershell
.\demo.ps1 cortar beni
```
**Se debe ver en la ventana 1:** Santa Cruz confirma y Beni queda `PENDIENTE_COMMIT`.

```powershell
.\demo.ps1 sql beni "SELECT gid, prepared FROM pg_prepared_xacts;"   # sigue ahí, aunque Beni estuvo aislado
.\demo.ps1 reconectar beni
.\demo.ps1 recuperar
```
**Se debe ver:** `Nodo 6 - Beni: trp_... -> COMMIT PREPARED (la bitacora dice PENDIENTE_COMMIT)`.

**Qué decir:** "Si un nodo falla después de votar SÍ, su transacción queda preparada y guardada en disco. Al volver, el procedimiento de recuperación consulta la decisión en la bitácora del coordinador y la completa. Así se garantiza la consistencia incluso en el peor caso de 2PC."

---

## Prueba 12 — Concurrencia: dos traspasos a la vez sobre el mismo producto

Abre **dos ventanas** y ejecuta casi al mismo tiempo:

**Ventana 1:**
```powershell
.\demo.ps1 traspaso SC BE 30 10 10
```
**Ventana 2** (mientras la 1 está en pausa):
```powershell
.\demo.ps1 traspaso SC CB 30 10
```
**Se debe ver:** la ventana 2 **espera** hasta que la 1 termina, porque la fila de inventario está bloqueada. Después continúa. Al final:
```powershell
.\demo.ps1 stock 30
```
Santa Cruz bajó exactamente 20 unidades, Beni subió 10 y Cochabamba subió 10.

**Qué decir:** "El `SELECT ... FOR UPDATE` bloquea la fila de inventario en el origen, así que las dos transacciones se serializan y no hay pérdida de actualizaciones."

---

## Preguntas que puede hacer el ingeniero

| Pregunta | Respuesta |
|---|---|
| ¿Por qué PostgreSQL y no Citus o CockroachDB? | Con PostgreSQL + `postgres_fdw` cada mecanismo (fragmentación, replicación y 2PC) se implementa y se ve de forma explícita. CockroachDB y Citus lo hacen automáticamente y lo ocultan. Además, PostgreSQL trae 2PC nativo. |
| ¿Cómo evitan que dos nodos generen el mismo ID? | Cada nodo usa un rango propio: nodo × 10.000.000. Por ejemplo, las ventas de Beni empiezan en 60.000.001. |
| ¿Qué pasa si se cae La Paz? | Los nodos regionales siguen vendiendo con su catálogo local (autonomía). No se pueden hacer consultas nacionales, cambios de catálogo ni traspasos, porque la bitácora del coordinador está en el nodo central. Es una decisión de diseño: La Paz es el nodo administrativo. |
| ¿Por qué replicación asíncrona y no síncrona? | Con replicación síncrona, si Beni (que tiene poco ancho de banda) se cae, La Paz no podría cambiar precios. Un precio desactualizado unos segundos es aceptable; bloquear las ventas no lo es. |
| ¿Dónde está el 2PC? | En `coordinador/coordinador_2pc.py`. Usa `PREPARE TRANSACTION`, `COMMIT PREPARED` y `ROLLBACK PREPARED` de PostgreSQL, y el parámetro `max_prepared_transactions=50` en cada nodo. |
| ¿Cómo simulan la caída de red? | `docker network disconnect` saca el contenedor de la red: el nodo sigue encendido pero queda aislado, igual que un corte de enlace real. |
| ¿Dónde están los scripts DDL y DML? | En `scripts/`: `01_esquema_local.sql` y `02_nodo_central.sql` (DDL), `03_datos_prueba.sql` (DML) y `04_fdw_vistas.sql` (vistas). |

## Al terminar

```powershell
.\demo.ps1 reconectar beni   # por si quedó desconectado
docker compose stop
```
