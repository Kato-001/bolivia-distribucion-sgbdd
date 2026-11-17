# Guía de pruebas y demostración para la sustentación

Guion paso a paso para demostrar **en vivo** que el sistema cumple cada punto de la rúbrica. En cada prueba encontrarás:

- 🎯 **Objetivo:** qué demuestra la prueba.
- ⌨️ **Comando:** lo que escribes.
- 🔍 **Desglose:** qué significa cada parte del comando.
- 👀 **Qué vas a ver:** el resultado esperado y cómo leerlo.
- 🗣️ **Qué decir:** cómo explicárselo al ingeniero.

---

## 0. Antes de empezar

### Preparación (el día anterior)
```powershell
.\demo.ps1 reiniciar
```
Borra todo y recrea el sistema desde cero, así empiezas con exactamente **50.000 ventas** y el stock original. Cuando pregunte `Continuar? (s/n)`, escribe `s`. Tarda unos 3 minutos.

### El día de la presentación
1. Abre **Docker Desktop** y espera a que diga **Engine running** (abajo a la izquierda).
2. Abre VS Code con el proyecto y abre la terminal (**Ctrl + Shift + P** → `Create New Terminal in Editor Area`).
3. Agranda la letra: haz clic en la terminal y presiona **Ctrl + +** varias veces.
4. Enciende los nodos con `docker compose start`.

### Consejos durante la exposición
- Escribe `cls` antes de cada prueba para limpiar la pantalla.
- Pega **un comando a la vez** y espera el resultado.
- Primero explica qué vas a hacer, luego ejecutas, luego explicas el resultado.

### Cómo funciona `demo.ps1`
`demo.ps1` es un script que escribimos para la demostración. Ahorra escribir comandos largos de Docker. Su forma general es:

```
.\demo.ps1   <acción>   <argumentos...>
```

| Parte | Significado |
|---|---|
| `.\` | "En esta carpeta". PowerShell exige poner `.\` para ejecutar un script local |
| `demo.ps1` | El script (`.ps1` = PowerShell) |
| `<acción>` | Lo que quieres hacer: `estado`, `sql`, `cortar`, `traspaso`... |
| `<argumentos>` | Datos que necesita la acción: un nodo, un producto, una cantidad... |

**Nombres de nodo** que puedes usar: `lapaz`, `santacruz`, `cochabamba`, `tarija`, `oruro`, `beni`.

**Códigos de departamento:** `LP` La Paz, `SC` Santa Cruz, `CB` Cochabamba, `TJ` Tarija, `CH` Chuquisaca, `OR` Oruro, `PO` Potosí, `BE` Beni, `PA` Pando.

### Glosario rápido (por si te preguntan)

| Término | En nuestro proyecto |
|---|---|
| **Nodo** | Un servidor de base de datos. Tenemos 6, uno por región |
| **Contenedor** | La "mini computadora" de Docker donde corre cada nodo |
| **Fragmento** | Un pedazo de una tabla guardado en un nodo (ej.: las ventas de Santa Cruz) |
| **Réplica** | Una copia completa de una tabla en otro nodo (el catálogo) |
| **postgres_fdw** | Extensión que permite a La Paz leer tablas de otros nodos como si fueran suyas |
| **Vista** | Una consulta guardada con nombre (ej.: `ventas_nacionales`) |
| **2PC** | *Two-Phase Commit*: protocolo para que una transacción en 2 nodos se haga completa en ambos o en ninguno |
| **gid** | Identificador global de una transacción distribuida (ej.: `trp_20261117_202544_bf8886`) |

---

## Resumen de las pruebas

| # | Prueba | Criterio de la rúbrica |
|---|---|---|
| 1 | Los 6 nodos funcionando en Docker | Demostración práctica (20 %) |
| 2 | Fragmentación horizontal | Diseño y fragmentación (25 %) |
| 3 | Fragmentación vertical | Diseño y fragmentación (25 %) |
| 4 | Replicación del catálogo | Diseño y fragmentación (25 %) |
| 5 | Transparencia: `SELECT * FROM ventas_nacionales` | Autonomía local y transparencia (25 %) |
| 6 | JOIN distribuido entre nodos | Autonomía local y transparencia (25 %) |
| 7 | Caída de nodo y autonomía local | Autonomía local y transparencia (25 %) |
| 8 | Consistencia eventual del catálogo | Autonomía local y transparencia (25 %) |
| 9 | Traspaso con 2PC | Transacciones y concurrencia (25 %) |
| 10 | ⭐ Beni se cae a mitad del traspaso y se hace rollback | Transacciones y concurrencia (25 %) |
| 11 | Recuperación de una transacción en duda | Transacciones y concurrencia (25 %) |
| 12 | Concurrencia: dos traspasos a la vez | Transacciones y concurrencia (25 %) |

---

## Prueba 1 — Los 6 nodos funcionando en Docker

🎯 **Objetivo:** mostrar que la infraestructura distribuida existe y está en marcha.

### Comando 1.1
```powershell
docker compose ps
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `docker compose` | Herramienta que maneja varios contenedores a la vez, según el archivo `docker-compose.yml` |
| `ps` | *process status*: lista los contenedores y su estado |

👀 **Qué vas a ver**
```
NAME               IMAGE         STATUS                    PORTS
nodo1_lapaz        postgres:16   Up 39 minutes (healthy)   0.0.0.0:5431->5432/tcp
nodo2_santacruz    postgres:16   Up 39 minutes (healthy)   0.0.0.0:5432->5432/tcp
...
nodo6_beni         postgres:16   Up 39 minutes (healthy)   0.0.0.0:5436->5432/tcp
```
- **NAME:** el nombre de cada nodo.
- **IMAGE `postgres:16`:** todos usan PostgreSQL versión 16.
- **STATUS `Up ... (healthy)`:** está encendido y responde. `healthy` significa que pasó la verificación de salud.
- **PORTS `5431->5432`:** el puerto 5431 de tu PC lleva al puerto 5432 (PostgreSQL) de ese contenedor. Cada nodo tiene su propio puerto (5431 a 5436).

### Comando 1.2
```powershell
.\demo.ps1 estado
```
🔍 **Desglose:** acción `estado`, sin argumentos. Muestra los contenedores y además le pide a **La Paz** un resumen de ventas de todos los nodos.

👀 **Qué vas a ver**
```
=== Ventas por nodo (consulta tolerante a fallos desde La Paz) ===
        nodo         |  estado  | cantidad_ventas |  total_bs
---------------------+----------+-----------------+-------------
 Nodo 1 - La Paz     | EN LINEA |           11000 | 35380203.05
 Nodo 2 - Santa Cruz | EN LINEA |           15000 | 48267787.50
 Nodo 3 - Cochabamba | EN LINEA |           10000 | 32194699.45
 Nodo 4 - Tarija     | EN LINEA |            6000 | 19307115.00
 Nodo 5 - Oruro      | EN LINEA |            5000 | 16125433.90
 Nodo 6 - Beni       | EN LINEA |            3000 |  9653557.50
```
- **estado:** `EN LINEA` significa que La Paz pudo conectarse a ese nodo.
- **cantidad_ventas:** cuántas ventas guarda físicamente ese nodo. La suma es **50.000**, el mínimo que pide el enunciado.
- **total_bs:** monto total vendido en bolivianos.

> Puedes mostrar también **Docker Desktop**, donde se ven los 6 contenedores con su punto verde.

🗣️ **Qué decir**
> "Desplegamos 6 nodos, cada uno es un contenedor Docker con su propio PostgreSQL 16, su propio disco y su propia IP dentro de la red `bolivia_red`. Representan los 6 nodos regionales del enunciado. Desde La Paz consultamos los 6 y vemos que todos están en línea, con 50.000 ventas repartidas según el volumen de cada región: Santa Cruz tiene más porque es el centro de alto volumen."

---

## Prueba 2 — Fragmentación horizontal (VENTAS por departamento)

🎯 **Objetivo:** demostrar que cada nodo guarda **solo las filas** (ventas) de sus departamentos.

### Comando 2.1 — ¿qué tiene cada nodo?
```powershell
.\demo.ps1 sql santacruz "SELECT departamento_id, count(*) FROM ventas GROUP BY 1;"
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `sql` | Acción: ejecutar una consulta SQL en un nodo |
| `santacruz` | **En qué nodo** se ejecuta |
| `"SELECT ..."` | La consulta, entre comillas |
| `SELECT departamento_id, count(*)` | Mostrar el departamento y cuántas filas hay |
| `FROM ventas` | De la tabla `ventas` **de ese nodo** (solo la local) |
| `GROUP BY 1` | Agrupar por la columna 1 (departamento_id) |

Repite cambiando el nodo:
```powershell
.\demo.ps1 sql tarija "SELECT departamento_id, count(*) FROM ventas GROUP BY 1;"
.\demo.ps1 sql beni   "SELECT departamento_id, count(*) FROM ventas GROUP BY 1;"
```

👀 **Qué vas a ver**
```
 departamento_id | count          departamento_id | count          departamento_id | count
-----------------+-------        -----------------+-------        -----------------+-------
 SC              | 15000          CH              |  3000          PA              |  1500
                                  TJ              |  3000          BE              |  1500
   (Santa Cruz)                       (Tarija)                          (Beni)
```
- Santa Cruz **solo** tiene ventas `SC`.
- Tarija tiene `TJ` y `CH` porque es el sub-nodo Sur (Tarija y Chuquisaca).
- Beni tiene `BE` y `PA` porque es el sub-nodo Amazonía (Beni y Pando).

### Comando 2.2 — intentar romper la regla
```powershell
.\demo.ps1 sql santacruz "INSERT INTO ventas (departamento_id,id_cliente,id_empleado) VALUES ('LP',20000001,1);"
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `INSERT INTO ventas` | Insertar una venta nueva |
| `(departamento_id, id_cliente, id_empleado)` | Las columnas que llenamos |
| `'LP'` | Departamento **La Paz**: es la trampa, porque estamos en Santa Cruz |
| `20000001` | Un cliente que existe en Santa Cruz |
| `1` | El empleado número 1 |

👀 **Qué vas a ver (es un error que ESPERAMOS)**
```
ERROR:  new row for relation "ventas" violates check constraint "chk_fragmento_ventas"
```
- `violates check constraint`: la fila viola una regla de validación.
- `chk_fragmento_ventas`: la regla que dice "en este nodo solo se aceptan ventas de SC".

🗣️ **Qué decir**
> "La tabla VENTAS está fragmentada horizontalmente por `departamento_id`. Cada fragmento es una selección: FV2 = σ departamento_id='SC'(VENTAS) vive en Santa Cruz, FV4 = σ departamento_id ∈ {TJ,CH} vive en Tarija, etc. No es solo una convención: cada nodo tiene un `CHECK` que hace **imposible** guardar una venta de La Paz en Santa Cruz, como acabamos de ver. Los 9 departamentos están cubiertos y ninguno se repite, así que la fragmentación es completa y disjunta. DETALLE_VENTA e INVENTARIO usan fragmentación **derivada**: cada detalle vive junto a su venta y cada inventario junto a su almacén."

---

## Prueba 3 — Fragmentación vertical (CLIENTES)

🎯 **Objetivo:** demostrar que la tabla CLIENTES está partida por **columnas**: los datos públicos están en cada nodo y los datos financieros **solo** en La Paz.

### Comando 3.1 — datos públicos en Beni
```powershell
.\demo.ps1 sql beni "SELECT * FROM clientes_datos_generales LIMIT 3;"
```
🔍 `SELECT *` significa "todas las columnas"; `LIMIT 3` muestra solo 3 filas.

👀 **Qué vas a ver**
```
 id_cliente | nit_ci  |       razon_social       | telefono |     direccion     | departamento_id
------------+---------+--------------------------+----------+-------------------+-----------------
   60000001 | 6000013 | Distribuidora Amazonía 1 | 60007919 | Calle Comercio #2 | PA
```
- Solo hay columnas **públicas/operativas**: NIT, razón social, teléfono y dirección.
- **No** hay límite de crédito ni saldo.
- El `id_cliente` empieza con **6**, porque Beni es el nodo 6. Cada nodo genera IDs en su propio rango (nodo × 10.000.000) para que nunca se repitan en el país.

### Comando 3.2 — buscar datos financieros en Beni
```powershell
.\demo.ps1 sql beni "SELECT * FROM clientes_financiero;"
```
👀 **Qué vas a ver (error ESPERADO):**
```
ERROR:  relation "clientes_financiero" does not exist
```
`relation does not exist` significa que la tabla **no existe** en Beni.

### Comando 3.3 — los datos financieros en La Paz
```powershell
.\demo.ps1 sql lapaz "SELECT * FROM clientes_financiero LIMIT 3;"
```
👀 **Qué vas a ver**
```
 id_cliente | limite_credito | saldo_pendiente | calificacion_riesgo | estado_credito
------------+----------------+-----------------+---------------------+----------------
   10000001 |       10000.00 |           37.00 | D                   | ACTIVO
```
Aquí están las columnas **sensibles**: límite de crédito, saldo, riesgo (A = bajo … D = alto) y estado.

### Comando 3.4 — reconstruir el cliente completo
```powershell
.\demo.ps1 sql lapaz "SELECT * FROM clientes_completos WHERE departamento_id='PA' LIMIT 3;"
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `clientes_completos` | **Vista** que une los dos fragmentos: datos generales (de cada nodo) + financieros (La Paz) |
| `WHERE departamento_id='PA'` | Solo clientes de **Pando**, que físicamente están en el nodo Beni |

👀 **Qué vas a ver:** una fila con **todas** las columnas: NIT, razón social, ... **y** límite de crédito, riesgo, etc. Los datos generales llegaron desde Beni y los financieros salieron de La Paz.

🗣️ **Qué decir**
> "CLIENTES está fragmentada verticalmente. FC1 es una proyección con los datos de identificación y contacto, y está en todos los nodos (además, fragmentada por departamento) para facturar rápido. FC2 es la proyección con los datos financieros y de riesgo, y está **solo** en La Paz por auditoría y seguridad: en Beni la tabla ni siquiera existe. Los dos fragmentos comparten la clave `id_cliente`, así que la vista `clientes_completos` reconstruye el cliente completo sin pérdida: CLIENTES = FC1 ⋈ FC2."

---

## Prueba 4 — Replicación total del catálogo

🎯 **Objetivo:** demostrar que PRODUCTOS_CATALOGO está **copiada entera** en los 6 nodos y que solo La Paz puede modificarla.

### Comando 4.1 — el catálogo existe en Oruro
```powershell
.\demo.ps1 sql oruro "SELECT count(*) FROM productos_catalogo;"
```
👀 Resultado: `200`. Oruro tiene los 200 productos **localmente**: una venta en Oruro valida precios sin usar la red.

### Comando 4.2 — intentar modificar la copia de Beni
```powershell
.\demo.ps1 sql beni "UPDATE productos_catalogo SET precio_unitario = 1 WHERE id_producto = 1;"
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `UPDATE productos_catalogo` | Modificar el catálogo |
| `SET precio_unitario = 1` | Poner el precio en Bs 1 |
| `WHERE id_producto = 1` | Solo al producto número 1 |

👀 **Qué vas a ver (error ESPERADO):**
```
ERROR:  El catalogo es una REPLICA de solo lectura. Las modificaciones se hacen en el Nodo 1 (La Paz).
```
Un *trigger* (regla automática) impide modificar la copia local. Así nadie en Beni puede poner precios distintos al resto del país.

### Comando 4.3 — estado de la replicación
```powershell
.\demo.ps1 sql lapaz "SELECT * FROM estado_replicacion;"
```
👀 **Qué vas a ver**
```
          suscriptor           |  estado   | sent_lsn  | replay_lsn | bytes_pendientes
-------------------------------+-----------+-----------+------------+------------------
 sub_catalogo_nodo2_santacruz  | streaming | 0/2955150 | 0/2955150  |                0
 ...
 sub_catalogo_nodo6_beni       | streaming | 0/2955150 | 0/2955150  |                0
```

| Columna | Significado |
|---|---|
| **suscriptor** | Cada nodo que recibe copia del catálogo (5 nodos) |
| **estado `streaming`** | Conectado y recibiendo cambios en tiempo real |
| **sent_lsn** | Hasta qué punto del registro de cambios **envió** La Paz (LSN = posición en el log de cambios) |
| **replay_lsn** | Hasta qué punto **aplicó** el nodo suscriptor |
| **bytes_pendientes** | Diferencia entre ambos. `0` significa que el nodo está al día |

🗣️ **Qué decir**
> "El catálogo usa **replicación total**: está completo en los 6 nodos porque se lee en cada venta y cambia poco. La Paz es la **copia primaria**: publica la tabla (PUBLICATION) y los otros 5 nodos se suscriben (SUBSCRIPTION). Es replicación **asíncrona**: La Paz no espera a los demás. Las copias son de solo lectura para evitar conflictos. Aquí vemos los 5 suscriptores en `streaming` con 0 bytes pendientes, es decir, todos al día."

---

## Prueba 5 — Transparencia de localización y fragmentación

🎯 **Objetivo:** demostrar que un analista en La Paz consulta **todo el país** con `SELECT * FROM ventas_nacionales` **sin saber** dónde están los datos. Es el requisito literal del enunciado.

### Comando 5.1 — entrar a la consola SQL de La Paz
```powershell
.\demo.ps1 psql lapaz
```
🔍 `psql` es la consola interactiva de PostgreSQL; `lapaz` indica en qué nodo. El cursor cambia a:
```
bolivia=#
```
`bolivia` es el nombre de la base de datos y `=#` indica que estás dentro, listo para escribir SQL. Cada consulta **termina con `;`**.

### Comando 5.2 — la consulta del enunciado
```sql
SELECT * FROM ventas_nacionales LIMIT 10;
```
👀 **Qué vas a ver**
```
 id_venta |     fecha_hora      | departamento_id | id_cliente | id_empleado | total_bs |   nodo_origen
----------+---------------------+-----------------+------------+-------------+----------+-----------------
 10000001 | 2026-03-14 10:22:05 | LP              |   10000033 |         102 |  1344.00 | Nodo 1 - La Paz
```
- Son las columnas de VENTAS del enunciado.
- **nodo_origen:** columna informativa que añadimos para la demo, para que se vea de dónde viene cada fila.

> Si aparece `-- More --` o `(END)`, presiona **q** para volver.

### Comando 5.3 — contar todo el país
```sql
SELECT count(*) FROM ventas_nacionales;
```
👀 Resultado: `50000`. **Una sola consulta** juntó las ventas de los **6 servidores**.

### Comando 5.4 — totales por departamento
```sql
SELECT departamento_id, count(*) AS ventas, sum(total_bs) AS total
FROM ventas_nacionales GROUP BY 1 ORDER BY 1;
```
🔍 `AS ventas` pone nombre a la columna; `sum(total_bs)` suma los montos; `ORDER BY 1` ordena por departamento.

👀 **Qué vas a ver:** 9 filas (BE, CB, CH, LP, OR, PA, PO, SC, TJ), con datos que vienen de 6 nodos distintos.

### Comando 5.5 — el optimizador sabe dónde está cada dato
```sql
EXPLAIN SELECT count(*) FROM ventas_nacionales WHERE departamento_id = 'SC';
```
🔍 `EXPLAIN` **no ejecuta** la consulta: muestra el **plan**, es decir, cómo la ejecutaría PostgreSQL.

👀 **Qué vas a ver**
```
 Aggregate
   ->  Foreign Scan on ventas v
```
- **Foreign Scan:** lectura en un nodo remoto (a través de postgres_fdw).
- Aparece **un solo** Foreign Scan: aunque la vista une 6 nodos, PostgreSQL sabe que las ventas `SC` solo están en Santa Cruz y **no molesta a los otros 5**.

Para comparar, quita el `WHERE`:
```sql
EXPLAIN SELECT count(*) FROM ventas_nacionales;
```
Ahora aparecen **5 Foreign Scan** (los 5 nodos remotos) y **1 Index Only Scan** (la tabla local de La Paz), unidos por un **Append**, que es el `UNION ALL`:
```
 Aggregate
   ->  Append
         ->  Index Only Scan using idx_ventas_cliente on ventas v    <- La Paz (local)
         ->  Foreign Scan on ventas v_1                              <- Santa Cruz
         ->  Foreign Scan on ventas v_2                              <- Cochabamba
         ->  Foreign Scan on ventas v_3                              <- Tarija
         ->  Foreign Scan on ventas v_4                              <- Oruro
         ->  Foreign Scan on ventas v_5                              <- Beni
```

### Salir de la consola
```sql
\q
```
(`\q` = *quit*)

🗣️ **Qué decir**
> "Esto es la **transparencia de localización y fragmentación**. La Paz está conectada a los otros 5 nodos con la extensión **postgres_fdw**, que hace ver las tablas remotas como si fueran locales. Encima creamos la vista `ventas_nacionales`, que reconstruye la relación global con la unión de los 6 fragmentos: VENTAS = FV1 ∪ FV2 ∪ … ∪ FV6. El analista escribe `SELECT * FROM ventas_nacionales` y no sabe que son 6 servidores. Además, como las tablas remotas tienen los mismos CHECK de fragmentación, el optimizador **poda** los nodos innecesarios: si pido solo Santa Cruz, solo consulta Santa Cruz."

---

## Prueba 6 — JOIN distribuido (ventas en Tarija + crédito en La Paz)

🎯 **Objetivo:** el enunciado (Fase 3) pide unir datos de clientes de La Paz con ventas de Tarija. Es un JOIN entre **dos nodos distintos**.

### Comando 6.1
```powershell
.\demo.ps1 psql lapaz
```
```sql
SELECT * FROM ventas_tarija_con_credito WHERE estado_credito <> 'ACTIVO' LIMIT 10;
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `ventas_tarija_con_credito` | Vista que une ventas y clientes de Tarija (nodo 4) con datos financieros (La Paz) |
| `WHERE estado_credito <> 'ACTIVO'` | Solo clientes con crédito **suspendido o bloqueado** (`<>` = distinto de) |

👀 **Qué vas a ver**
```
 id_venta | departamento_id | total_bs |  razon_social     | limite_credito | calificacion_riesgo | estado_credito
----------+-----------------+----------+-------------------+----------------+---------------------+----------------
 40000007 | TJ              |  1344.00 | Tienda Andina 218 |       50000.00 | A                   | SUSPENDIDO
```
- `id_venta` 40000007 empieza con **4**: viene del nodo 4 (Tarija).
- `limite_credito` y `estado_credito` vienen de **La Paz**.
- Caso de uso real: *"¿a qué clientes con crédito suspendido les seguimos vendiendo en Tarija?"*

### Comando 6.2 — un JOIN escrito a mano
```sql
SELECT c.razon_social, c.departamento_id, f.calificacion_riesgo,
       count(*) AS compras, sum(v.total_bs) AS total
FROM nodo4.ventas v
JOIN nodo4.clientes_datos_generales c USING (id_cliente)
JOIN clientes_financiero f USING (id_cliente)
GROUP BY 1,2,3 ORDER BY total DESC LIMIT 5;
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `nodo4.ventas v` | Tabla `ventas` **del nodo 4 (Tarija)**, vista desde La Paz. `v` es un alias corto |
| `nodo4.clientes_datos_generales c` | Clientes de Tarija |
| `clientes_financiero f` | Sin prefijo: es la tabla **local** de La Paz |
| `JOIN ... USING (id_cliente)` | Une las filas que tienen el mismo `id_cliente` |
| `GROUP BY 1,2,3` | Agrupa por cliente, departamento y riesgo |
| `ORDER BY total DESC LIMIT 5` | Los 5 que más compraron |

👀 **Qué vas a ver:** el top 5 de clientes de Tarija y Chuquisaca con su calificación de riesgo.

```sql
\q
```

🗣️ **Qué decir**
> "Esta consulta une datos de **dos nodos**: las ventas y clientes están físicamente en Tarija y la información financiera en La Paz. PostgreSQL trae los datos de Tarija por la red con postgres_fdw y hace el JOIN en La Paz. Para el usuario es una consulta normal."

---

## Prueba 7 — Caída de un nodo y autonomía local

🎯 **Objetivo:** el enunciado pide "desconectar artificialmente el nodo de Beni u Oruro y demostrar que los demás nodos siguen operando".

### Comando 7.1 — cortar la red de Beni
```powershell
.\demo.ps1 cortar beni
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `cortar` | Desconecta el contenedor de la red `bolivia_red` (por dentro ejecuta `docker network disconnect`) |
| `beni` | El nodo a aislar |

👀 Resultado: `Red cortada: nodo6_beni esta aislado del resto del pais (sigue encendido).`

> **Ojo:** no apagamos Beni. Sigue **encendido**, pero **sin red**, igual que un corte del enlace de internet en la sucursal.

### Comando 7.2 — ver el estado
```powershell
.\demo.ps1 estado
```
👀 **Qué vas a ver**
```
  nodo6_beni -> RED CORTADA (aislado)
...
 Nodo 5 - Oruro      | EN LINEA     |            5000 | 16125433.90
 Nodo 6 - Beni       | SIN CONEXION |                 |
```
La Paz intentó conectarse a Beni, no pudo y lo informó **sin fallar**. Los otros 5 siguen EN LINEA.

### Comando 7.3 — los demás siguen vendiendo
```powershell
.\demo.ps1 venta santacruz
```
🔍 `venta` registra una venta **local** en ese nodo: elige un cliente y un producto al azar, cantidad 1, descuenta el inventario y guarda la venta y el detalle.

👀 **Qué vas a ver**
```
 id_venta_nueva
----------------
       21000001          <- nueva venta guardada (el 2 indica nodo Santa Cruz)

 ventas_en_este_nodo |        ultima_venta
---------------------+----------------------------
               15001 | 2026-11-17 16:26:30        <- era 15000, ahora 15001
```

### Comando 7.4 — ¡Beni también sigue vendiendo, aislado!
```powershell
.\demo.ps1 venta beni
```
👀 Resultado: también se registra la venta (`id_venta_nueva` = 61000000…). Beni no tiene red, pero tiene **todo lo que necesita** localmente: sus clientes, su inventario y su copia del catálogo.

### Comando 7.5 — consultas globales con un nodo caído
```powershell
.\demo.ps1 sql lapaz "SELECT count(*) FROM ventas_nacionales WHERE departamento_id = 'SC';"
```
👀 Funciona (`15001`): como solo necesita Santa Cruz, no le afecta que Beni esté caído (gracias a la poda de la prueba 5).

```powershell
.\demo.ps1 sql lapaz "SELECT count(*) FROM ventas_nacionales_disponibles();"
```
👀 **Qué vas a ver**
```
NOTICE:  AVISO: Nodo 6 - Beni no disponible (...). Se devuelven los datos de los nodos en linea.
 count
-------
 47001
```
Devuelve las ventas de los 5 nodos disponibles y **avisa** cuál falta, en lugar de fallar.

> ⚠️ **No reconectes Beni todavía**: lo necesitas desconectado en la prueba 8.

🗣️ **Qué decir**
> "Simulamos un corte de red en Beni. Los otros 5 nodos siguen operando con normalidad, y Beni también, aislado: puede seguir vendiendo porque tiene todo localmente. Eso es **autonomía local**, y es la razón principal para fragmentar por departamento. Desde La Paz, las consultas que no necesitan a Beni funcionan igual, y para reportes nacionales tenemos una función tolerante a fallos que devuelve lo disponible y avisa qué nodo falta."

---

## Prueba 8 — Consistencia eventual del catálogo

🎯 **Objetivo:** el enunciado pide "pruebas de consistencia eventual o fuerte al actualizar el catálogo desde La Paz". Beni sigue **desconectado** de la prueba 7.

### Comando 8.1 — cambiar un precio en La Paz
```powershell
.\demo.ps1 catalogo 10 99.90
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `catalogo` | Acción: cambiar un precio en La Paz y mostrar cómo se propaga |
| `10` | **id del producto** a modificar (el 10 es "Agua Mineral - Unidad") |
| `99.90` | **Nuevo precio** en bolivianos |

El script hace el UPDATE en La Paz y luego lee el precio en los 6 nodos, **3 veces**, con 1 segundo entre cada lectura.

👀 **Qué vas a ver**
```
=== Precio en cada nodo (lectura 1, +1 s) ===
  lapaz              Bs 99.90     (verde)
  santacruz          Bs 99.90     (verde)
  cochabamba         Bs 99.90     (verde)
  tarija             Bs 99.90     (verde)
  oruro              Bs 99.90     (verde)
  beni               Bs 5.00      (amarillo)  <- precio VIEJO

=== Estado de la replicacion (desde La Paz) ===
 sub_catalogo_nodo6_beni       | streaming | ... |  10720   <- bytes pendientes para Beni
```
- **Verde** = ya tiene el precio nuevo. **Amarillo** = todavía tiene el viejo.
- En menos de 1 segundo los 5 nodos conectados se actualizaron.
- Beni sigue con Bs 5.00 porque está aislado.
- `bytes_pendientes` > 0: La Paz **guarda** los cambios que Beni no ha recibido.

### Comando 8.2 — reconectar Beni
```powershell
.\demo.ps1 reconectar beni
```
👀 Resultado: `Red restaurada: nodo6_beni vuelve a estar en linea.`

### Comando 8.3 — verificar que Beni se puso al día
Espera unos 5 o 10 segundos y ejecuta:
```powershell
.\demo.ps1 sql beni "SELECT id_producto, nombre, precio_unitario FROM productos_catalogo WHERE id_producto = 10;"
```
👀 **Qué vas a ver**
```
 id_producto |        nombre         | precio_unitario
-------------+-----------------------+-----------------
          10 | Agua Mineral - Unidad |           99.90     <- ¡ya llegó!
```
(Si todavía sale 5.00, espera unos segundos y repite.)

### Comando 8.4 — restaurar el precio original
```powershell
.\demo.ps1 catalogo 10 5.00
```

🗣️ **Qué decir**
> "Como la replicación es asíncrona, la consistencia es **eventual**: los nodos conectados se actualizan en menos de un segundo, pero Beni, que estaba aislado, quedó temporalmente con el precio viejo. La Paz no se bloqueó por eso: guardó el cambio en un *replication slot*. Cuando Beni volvió, recibió automáticamente lo pendiente y quedó consistente. No se pierde ninguna actualización. Elegimos esto en lugar de consistencia fuerte porque, con replicación síncrona, una caída de Beni (que tiene poco ancho de banda) impediría cambiar precios en todo el país."

---

## Prueba 9 — Transacción distribuida con 2PC (Santa Cruz → Beni)

🎯 **Objetivo:** mostrar un traspaso de inventario entre dos departamentos que se hace **completo en ambos nodos o en ninguno**.

### Comando 9.1 — ver el stock antes
```powershell
.\demo.ps1 stock 10
```
🔍 `stock` muestra el inventario de un producto en los 9 departamentos; `10` es el **id del producto**.

👀 **Qué vas a ver**
```
=== STOCK DEL PRODUCTO 10 ===
  SC  Almacén Central Santa Cruz          stock = 671
  BE  Almacén Central Beni                stock = 171
  ...
```
**Anota** los números de SC y BE para comparar después.

### Comando 9.2 — el traspaso
```powershell
.\demo.ps1 traspaso SC BE 10 5
```
🔍 **Desglose: el orden de los argumentos importa**

| Posición | Valor | Significado |
|---|---|---|
| 1 | `SC` | **Origen**: departamento de donde **sale** la mercadería |
| 2 | `BE` | **Destino**: departamento a donde **llega** |
| 3 | `10` | **Producto**: id del producto a traspasar |
| 4 | `5` | **Cantidad**: unidades a mover |
| 5 *(opcional)* | ej. `10` | **Pausa** en segundos antes de la fase 1 (se usa en la prueba 12) |

En palabras: "mueve **5** unidades del producto **10** desde **Santa Cruz** hacia **Beni**".

👀 **Qué vas a ver (y cómo leerlo)**
```
=== TRASPASO SC -> BE: 5 unidades del producto 10 ===
  -> ID global de la transaccion (gid): trp_20261117_202544_bf8886
```
**gid**: nombre único de esta transacción distribuida (`trp` = traspaso + fecha_hora + código aleatorio).

```
=== FASE 0: Conexion con los participantes ===
  [OK] Conectado a Nodo 2 - Santa Cruz
  [OK] Conectado a Nodo 6 - Beni
```
El **coordinador** (un programa en Python) se conecta a los 2 **participantes**.

```
=== EJECUCION: operaciones dentro de cada transaccion local ===
  [OK] Nodo 2 - Santa Cruz: stock 671 -> 666 (bloqueado, sin confirmar)
  [OK] Nodo 6 - Beni: stock 171 -> 176 (bloqueado, sin confirmar)
```
Cada nodo hace su parte (Santa Cruz resta 5 y Beni suma 5), pero **nada está confirmado todavía**. Las filas quedan **bloqueadas** para que nadie más las toque.

```
=== FASE 1: PREPARACION (votacion) ===
  -> Enviando PREPARE TRANSACTION a Nodo 2 - Santa Cruz ...
  [OK] Nodo 2 - Santa Cruz voto SI (transaccion preparada y guardada en disco)
  -> Enviando PREPARE TRANSACTION a Nodo 6 - Beni ...
  [OK] Nodo 6 - Beni voto SI (transaccion preparada y guardada en disco)
```
**Fase 1 (votación):** el coordinador pregunta a cada nodo "¿puedes confirmar?". Cada uno ejecuta `PREPARE TRANSACTION`: guarda los cambios en disco y **promete** que podrá confirmarlos aunque se reinicie. Eso es votar **SÍ**.

```
=== DECISION GLOBAL: CONFIRMAR (todos votaron SI) ===
  [OK] Decision registrada en la bitacora del coordinador (Nodo 1 - La Paz)
```
Como **todos** votaron SÍ, la decisión es CONFIRMAR, y se anota en una **bitácora** en La Paz (sirve para la recuperación, prueba 11).

```
=== FASE 2: CONFIRMACION (COMMIT PREPARED) ===
  [OK] COMMIT PREPARED en Nodo 2 - Santa Cruz
  [OK] COMMIT PREPARED en Nodo 6 - Beni

TRASPASO COMPLETADO en ambos nodos (ACID garantizado por 2PC).
  SC  Almacén Central Santa Cruz          stock = 666     <- bajó 5
  BE  Almacén Central Beni                stock = 176     <- subió 5
```
**Fase 2 (confirmación):** `COMMIT PREPARED` hace los cambios definitivos en ambos nodos.

### Comando 9.3 (opcional) — la bitácora
```powershell
.\demo.ps1 sql lapaz "SELECT gid, origen, destino, id_producto, cantidad, estado FROM coordinador_2pc_log ORDER BY creado DESC LIMIT 5;"
```
👀 La transacción aparece con estado `COMPLETADO`.

🗣️ **Qué decir**
> "Un traspaso modifica **dos nodos**: resta en Santa Cruz y suma en Beni. Si solo se hiciera una de las dos partes, se perdería o se duplicaría mercadería. Por eso usamos **Compromiso en Dos Fases**. En la **fase 1** el coordinador pide a cada nodo que se prepare: cada uno ejecuta `PREPARE TRANSACTION`, guarda sus cambios en disco y vota SÍ. Solo si **todos** votan SÍ, el coordinador registra la decisión en la bitácora de La Paz y en la **fase 2** ejecuta `COMMIT PREPARED` en ambos. Usamos el 2PC **nativo de PostgreSQL**, configurado con `max_prepared_transactions=50` en cada nodo."

---

## Prueba 10 — ⭐ Beni pierde conexión a mitad del traspaso → ROLLBACK automático

🎯 **Objetivo:** **es la prueba más importante.** El enunciado dice literalmente: *"Si el Nodo Beni pierde conexión a mitad del traspaso, el sistema debe realizar un Rollback automático en el Nodo Santa Cruz."*

### Comando 10.1
```powershell
.\demo.ps1 caida-traspaso
```
🔍 **Qué hace este comando (automático, no tienes que tocar nada):**
1. Muestra el stock del producto 10 **antes**.
2. Inicia un traspaso de **25 unidades** del producto **10** de **SC → BE**, con una pausa de 12 segundos antes de la fase 1.
3. A los **8 segundos** (durante la pausa) **corta la red de Beni**.
4. Espera a que el coordinador termine.
5. Muestra el stock de Santa Cruz **después**, las transacciones pendientes y la bitácora.
6. Reconecta Beni.

👀 **Qué vas a ver (y cómo leerlo)**
```
=== STOCK DEL PRODUCTO 10 ===
  SC  Almacén Central Santa Cruz          stock = 666      <- ANOTA este número
  ...
Coordinador iniciado; en 8 segundos se cortara la red de Beni...
>>> RED DE BENI CORTADA <<<
```
```
=== EJECUCION: operaciones dentro de cada transaccion local ===
  [OK] Nodo 2 - Santa Cruz: stock 666 -> 641 (bloqueado, sin confirmar)
  [OK] Nodo 6 - Beni: stock 176 -> 201 (bloqueado, sin confirmar)

  PAUSA DE DEMOSTRACION: ...
    ...continuando en  3 s
```
Los dos nodos hicieron su parte; durante la pausa **se cortó la red de Beni**.

```
=== FASE 1: PREPARACION (votacion) ===
  -> Enviando PREPARE TRANSACTION a Nodo 2 - Santa Cruz ...
  [OK] Nodo 2 - Santa Cruz voto SI (transaccion preparada y guardada en disco)
  -> Enviando PREPARE TRANSACTION a Nodo 6 - Beni ...
```
Santa Cruz alcanzó a votar SÍ. A Beni se le envía la petición, pero **no responde** (tarda unos 4 segundos en darse por perdido).

```
=== DECISION GLOBAL: ABORTAR (ROLLBACK) ===
  [X] Nodo 6 - Beni no pudo preparar / perdio conexion (OperationalError)
  [OK] ROLLBACK PREPARED ejecutado en Nodo 2 - Santa Cruz        <- ¡EL ROLLBACK AUTOMÁTICO!
  -> Nodo 6 - Beni inalcanzable: su transaccion NO fue preparada, PostgreSQL la descarta sola.

TRASPASO ABORTADO. Ningun nodo quedo modificado (atomicidad).
```
- `[X]`: Beni falló (`OperationalError` = error de conexión).
- Como **no todos votaron SÍ**, la decisión global es **ABORTAR**.
- **`ROLLBACK PREPARED` en Santa Cruz**: deshace el cambio que Santa Cruz ya había preparado. Esto es **exactamente** lo que pide el enunciado.

```
=== Comprobacion en Santa Cruz: el stock NO cambio (rollback automatico) ===
 departamento_id | id_producto | stock_actual
-----------------+-------------+--------------
 SC              |          10 |          666     <- IGUAL que antes. No se perdió nada.

 gid | prepared
-----+----------
(0 rows)                                            <- no quedaron transacciones colgadas
```
```
=== Bitacora del coordinador (La Paz) ===
            gid             | origen | destino | cantidad |   estado   |    detalle
----------------------------+--------+---------+----------+------------+-------------------------------
 trp_20261117_202553_ea9f59 | SC     | BE      |       25 | ABORTADO   | Nodo 6 - Beni no pudo preparar...
 trp_20261117_202544_bf8886 | SC     | BE      |        5 | COMPLETADO |
Red de Beni restaurada.
```
La bitácora deja constancia: el traspaso de 25 quedó **ABORTADO** con el motivo, y el de 5 (prueba 9) **COMPLETADO**.

🗣️ **Qué decir** (despacio, es la prueba clave)
> "Ahora el escenario exacto del enunciado: Beni pierde conexión a mitad del traspaso. Santa Cruz ya restó las 25 unidades y alcanzó a **prepararse**, es decir, votó SÍ. Pero cuando el coordinador pide a Beni que se prepare, Beni no responde. Por el protocolo 2PC, si **un solo** participante no vota SÍ, la decisión global es **abortar**. El coordinador ejecuta automáticamente `ROLLBACK PREPARED` en Santa Cruz y deshace su parte. El stock de Santa Cruz sigue en 666, como antes: no se perdió mercadería. La parte de Beni, que nunca llegó a prepararse, la descarta el propio PostgreSQL al perder la sesión. Así se cumple la **atomicidad**: todo o nada."

---

## Prueba 11 — Recuperación de una transacción "en duda" (punto extra)

🎯 **Objetivo:** mostrar el caso más difícil del 2PC: Beni se cae **después** de votar SÍ. Su transacción queda "en duda" (preparada, esperando la decisión). Esto demuestra que dominamos el protocolo completo.

**Necesitas DOS terminales** (VS Code: **Ctrl + Shift + P** → `Create New Terminal in Editor Area`, dos veces; puedes ponerlas lado a lado).

### Comando 11.1 — Terminal 1
```powershell
docker compose run --rm coordinador traspaso --origen SC --destino BE --producto 20 --cantidad 7 --pausa-commit 15
```
🔍 **Desglose**

| Parte | Significado |
|---|---|
| `docker compose run` | Ejecuta un contenedor temporal... |
| `--rm` | ...y lo borra al terminar |
| `coordinador` | El contenedor del coordinador 2PC (Python) |
| `traspaso` | Acción del coordinador |
| `--origen SC --destino BE` | De Santa Cruz a Beni |
| `--producto 20 --cantidad 7` | 7 unidades del producto 20 |
| `--pausa-commit 15` | Pausa de 15 segundos **entre la fase 1 y la fase 2**, es decir, cuando ambos ya votaron SÍ |

> Aquí usamos `docker compose run` directamente (y no `demo.ps1`) porque necesitamos la opción `--pausa-commit`.

### Comando 11.2 — Terminal 2, cuando la terminal 1 muestre `PAUSA DE DEMOSTRACION: ambos nodos estan PREPARADOS`
```powershell
.\demo.ps1 cortar beni
```

👀 **Qué vas a ver en la terminal 1**
```
=== DECISION GLOBAL: CONFIRMAR (todos votaron SI) ===
  [OK] Decision registrada en la bitacora del coordinador (Nodo 1 - La Paz)
  PAUSA DE DEMOSTRACION: ambos nodos estan PREPARADOS...
=== FASE 2: CONFIRMACION (COMMIT PREPARED) ===
  [OK] COMMIT PREPARED en Nodo 2 - Santa Cruz
  [X] Nodo 6 - Beni no responde (OperationalError). Su transaccion sigue PREPARADA...
TRASPASO DECIDIDO (COMMIT) - pendiente de confirmar en: Nodo 6 - Beni
```
Santa Cruz confirmó. Beni había votado SÍ pero se cayó antes de recibir la confirmación: está **en duda**.

### Comando 11.3 — la transacción sigue esperando en Beni
```powershell
.\demo.ps1 sql beni "SELECT gid, prepared FROM pg_prepared_xacts;"
```
🔍 `pg_prepared_xacts` es una tabla del sistema con las transacciones **preparadas** que esperan COMMIT o ROLLBACK.

👀 Aparece el `gid` del traspaso: Beni lo guardó en disco y lo **recuerda** aunque esté aislado.

### Comando 11.4 — reconectar y recuperar
```powershell
.\demo.ps1 reconectar beni
.\demo.ps1 recuperar
```
🔍 `recuperar` revisa los 6 nodos, busca transacciones preparadas, consulta en la **bitácora de La Paz** qué se decidió para cada una y la completa.

👀 **Qué vas a ver**
```
=== RECUPERACION DE TRANSACCIONES EN DUDA ===
  [OK] Nodo 1 - La Paz: sin transacciones pendientes
  ...
  [OK] Nodo 6 - Beni: trp_... -> COMMIT PREPARED (la bitacora dice PENDIENTE_COMMIT)
Transacciones resueltas: 1. Nodos sin conexion: 0
```

### Comando 11.5 — comprobar
```powershell
.\demo.ps1 stock 20
```
👀 Santa Cruz bajó 7 **y** Beni subió 7: el traspaso quedó completo en los dos nodos.

🗣️ **Qué decir**
> "Este es el caso crítico del 2PC: Beni votó SÍ y se cayó antes de recibir la orden final. Un nodo que votó SÍ **ya no puede decidir solo**: prometió confirmar si se lo piden. Por eso su transacción queda preparada en disco, incluso si se reinicia. Cuando vuelve, el procedimiento de recuperación consulta la decisión en la bitácora del coordinador (que dice COMMIT) y la completa. Así el sistema queda consistente incluso en el peor caso."

---

## Prueba 12 — Concurrencia: dos traspasos a la vez sobre el mismo producto

🎯 **Objetivo:** mostrar que dos transacciones simultáneas sobre el mismo stock **no se pisan** (no hay "actualización perdida").

**Necesitas DOS terminales.**

### Comando 12.1 — ver stock inicial
```powershell
.\demo.ps1 stock 30
```
Anota el stock de **SC**, **BE** y **CB**.

### Comando 12.2 — Terminal 1
```powershell
.\demo.ps1 traspaso SC BE 30 10 10
```
🔍 Origen **SC**, destino **BE**, producto **30**, cantidad **10**, y el quinto argumento **10** es una **pausa de 10 segundos** antes de la fase 1. Durante esa pausa el traspaso tiene **bloqueada** la fila del producto 30 en Santa Cruz.

### Comando 12.3 — Terminal 2, inmediatamente (mientras la 1 está en pausa)
```powershell
.\demo.ps1 traspaso SC CB 30 10
```
🔍 Otro traspaso: **10** unidades del **mismo producto 30** desde **Santa Cruz**, pero hacia **Cochabamba**.

👀 **Qué vas a ver**
- La terminal 2 se queda **esperando** después de `Conectado a ...`, sin avanzar.
- Cuando la terminal 1 termina (`TRASPASO COMPLETADO`), la terminal 2 **continúa sola** y también termina.
- En la terminal 2, el stock inicial de SC ya refleja el primer traspaso. Por ejemplo, si al principio había 511, la terminal 2 dice `stock 501 -> 491`.

### Comando 12.4 — resultado final
```powershell
.\demo.ps1 stock 30
```
👀 Santa Cruz bajó exactamente **20** (10 + 10), Beni subió **10** y Cochabamba subió **10**. Las cuentas cuadran.

🗣️ **Qué decir**
> "Dos traspasos intentan sacar el mismo producto de Santa Cruz a la vez. El coordinador usa `SELECT ... FOR UPDATE`, que **bloquea** la fila del inventario. La segunda transacción espera a que la primera termine y luego lee el stock **ya actualizado**. Así se serializan y no hay actualización perdida: Santa Cruz bajó exactamente 20. Eso es el **aislamiento** de ACID en un entorno distribuido."

---

## Preguntas que puede hacer el ingeniero

| Pregunta | Respuesta |
|---|---|
| ¿Por qué PostgreSQL y no Citus o CockroachDB? | Con PostgreSQL + `postgres_fdw` cada mecanismo (fragmentación, replicación y 2PC) se implementa **explícitamente** y se puede mostrar. CockroachDB y Citus lo automatizan y lo ocultan. Además, PostgreSQL trae 2PC nativo (`PREPARE TRANSACTION`). |
| ¿Cómo evitan que dos nodos generen el mismo ID? | Cada nodo usa un rango propio: nodo × 10.000.000. Las ventas de Santa Cruz empiezan en 20.000.001 y las de Beni en 60.000.001. |
| ¿Qué pasa si se cae La Paz? | Los nodos regionales **siguen vendiendo** con su catálogo local (autonomía). Lo que no se puede hacer: consultas nacionales, cambios de catálogo y traspasos, porque la bitácora del coordinador está en el nodo central. Es una decisión de diseño: La Paz es el nodo administrativo. |
| ¿Por qué replicación asíncrona y no síncrona? | Con replicación síncrona, si Beni (poco ancho de banda) se cae, La Paz no podría cambiar precios. Un precio desactualizado unos segundos es aceptable; bloquear las ventas no lo es. |
| ¿Dónde está el código del 2PC? | En `coordinador/coordinador_2pc.py`. Usa `PREPARE TRANSACTION`, `COMMIT PREPARED` y `ROLLBACK PREPARED`, con `max_prepared_transactions=50` en cada nodo (`docker-compose.yml`). |
| ¿Cómo simulan la caída de red? | Con `docker network disconnect`: el contenedor sigue encendido pero sale de la red, igual que un corte de enlace real. Es más realista que apagarlo. |
| ¿Dónde están los scripts DDL y DML? | En `scripts/`: `01_esquema_local.sql` y `02_nodo_central.sql` (DDL: tablas, CHECK, triggers), `03_datos_prueba.sql` (DML: carga de datos) y `04_fdw_vistas.sql` (postgres_fdw y vistas). |
| ¿Qué pasa si el coordinador se cae a mitad? | Si se cae antes de decidir, las transacciones preparadas se resuelven con `recuperar`, que aplica ROLLBACK porque no hay decisión COMMIT en la bitácora (*presunción de aborto*). Si se cae después de decidir, `recuperar` aplica COMMIT. |
| ¿Dónde se ve la fragmentación en el código? | En `scripts/01_esquema_local.sql`, en los `CONSTRAINT chk_fragmento_... CHECK (departamento_id IN (...))`. Cada nodo recibe su lista de departamentos desde `docker-compose.yml` (`NODO_DEPTOS`). |

---

## Al terminar la presentación

```powershell
.\demo.ps1 reconectar beni     # por si quedó desconectado (si ya estaba conectado, dará un aviso: no pasa nada)
docker compose stop            # apaga los 6 nodos, los datos se conservan
```

## Si algo sale mal durante la presentación

| Situación | Qué hacer |
|---|---|
| Un comando se queda "colgado" | Presiona **Ctrl + C** y vuelve a ejecutarlo |
| Te quedaste dentro de `bolivia=#` | Escribe `\q` y Enter |
| Aparece `-- More --` o `(END)` | Presiona **q** |
| `estado` dice SIN CONEXION y no debería | `.\demo.ps1 reconectar beni` (o el nodo que sea) |
| Un nodo no está *healthy* | `docker compose restart` y espera 20 segundos |
| Todo está raro | `.\demo.ps1 reiniciar` (tarda unos 3 minutos) |
