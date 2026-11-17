# BoliviaDistribución S.A. — Sistema de Base de Datos Distribuida

Prototipo de un SGBDD con **6 nodos PostgreSQL 16** que corren en contenedores **Docker**, uno por región:

| Nodo | Contenedor | Departamentos | Puerto (en tu PC) | Ventas de prueba |
|---|---|---|---|---|
| 1 | `nodo1_lapaz` | LP (central) | 5431 | 11.000 |
| 2 | `nodo2_santacruz` | SC | 5432 | 15.000 |
| 3 | `nodo3_cochabamba` | CB | 5433 | 10.000 |
| 4 | `nodo4_tarija` | TJ, CH | 5434 | 6.000 |
| 5 | `nodo5_oruro` | OR, PO | 5435 | 5.000 |
| 6 | `nodo6_beni` | BE, PA | 5436 | 3.000 |
| | | | **Total** | **50.000** |

Usuario: `postgres` · Contraseña: `bolivia123` · Base de datos: `bolivia`

## 📚 Documentación

| Documento | Para qué sirve |
|---|---|
| [docs/INSTALACION.md](docs/INSTALACION.md) | **Empieza aquí.** Instalación desde cero (WSL, Docker, Git) y cómo levantar el sistema |
| [docs/GUIA_PRUEBAS.md](docs/GUIA_PRUEBAS.md) | Guion de la sustentación: 12 pruebas, qué se debe ver y qué decir |
| [docs/arquitectura.md](docs/arquitectura.md) | Diseño: fragmentación, replicación, 2PC, matriz CRUD y justificación |

**Inicio rápido** (si ya tienes Docker Desktop abierto):
```powershell
git clone https://github.com/Kato-001/bolivia-distribucion-sgbdd.git
cd bolivia-distribucion-sgbdd
.\demo.ps1 iniciar
```

---

## 1. Requisitos

- Windows 10/11 con **WSL 2** (`wsl --install` en PowerShell como administrador).
- **Docker Desktop** abierto, con el mensaje *Engine running*.
- La primera vez, permitir scripts de PowerShell (solo una vez):
  ```powershell
  Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
  ```

## 2. Despliegue

Abre PowerShell **en la carpeta del proyecto** y ejecuta:

```powershell
.\demo.ps1 iniciar
```

Este comando:
1. Descarga PostgreSQL 16 (solo la primera vez) y crea los 6 contenedores.
2. Crea en cada nodo su esquema local, con los fragmentos restringidos por `CHECK`.
3. Suscribe los nodos 2 a 6 al catálogo publicado por La Paz (replicación lógica).
4. Carga los datos de prueba: 50.000 ventas, unos 100.000 detalles, 4.000 clientes e inventario.
5. Conecta La Paz con los demás nodos mediante `postgres_fdw` y crea las vistas distribuidas.

Al final muestra un resumen de las ventas por nodo, consultado desde La Paz.

Otros comandos útiles:

```powershell
docker compose ps          # ver los nodos
docker compose stop        # apagar (conserva los datos)
docker compose start       # volver a encender
.\demo.ps1 reiniciar       # BORRAR todo y recrear desde cero
```

Para usar una interfaz gráfica, conecta **DBeaver** o **pgAdmin** a `localhost`, al puerto del nodo (5431 a 5436), con usuario `postgres` y contraseña `bolivia123`.

---

## 3. Guion para la demostración en vivo

### Paso 1 — Los 6 nodos funcionando
```powershell
.\demo.ps1 estado
```
Muestra los contenedores y las ventas de cada nodo, consultadas desde La Paz.

### Paso 2 — Transparencia de localización
```powershell
.\demo.ps1 psql lapaz
```
```sql
SELECT * FROM ventas_nacionales LIMIT 10;               -- el analista no sabe dónde están los datos
SELECT count(*) FROM ventas_nacionales;                 -- 50000
SELECT departamento_id, count(*), sum(total_bs)
FROM ventas_nacionales GROUP BY 1 ORDER BY 1;

-- El optimizador solo consulta el nodo necesario:
EXPLAIN SELECT count(*) FROM ventas_nacionales WHERE departamento_id = 'SC';

-- Fragmentación vertical reconstruida (datos generales en cada nodo + financiero en La Paz)
SELECT * FROM clientes_completos WHERE departamento_id = 'PA' LIMIT 5;

-- JOIN distribuido: ventas que están en Tarija + crédito que está en La Paz
SELECT * FROM ventas_tarija_con_credito WHERE estado_credito <> 'ACTIVO' LIMIT 10;
\q
```

### Paso 3 — La fragmentación se respeta
```powershell
.\demo.ps1 sql santacruz "INSERT INTO ventas (departamento_id,id_cliente,id_empleado) VALUES ('LP',20000001,1);"
#  -> ERROR: check constraint "chk_fragmento_ventas"  (Santa Cruz no acepta ventas de La Paz)

.\demo.ps1 sql beni "SELECT * FROM clientes_financiero;"
#  -> ERROR: no existe  (los datos financieros solo están en La Paz)
```

### Paso 4 — Caída de un nodo y autonomía local
```powershell
.\demo.ps1 cortar beni        # corta la red de Beni (sigue encendido, pero aislado)
.\demo.ps1 estado             # La Paz informa: Beni SIN CONEXION, el resto EN LINEA
.\demo.ps1 venta santacruz    # Santa Cruz sigue vendiendo
.\demo.ps1 venta beni         # Beni también sigue vendiendo localmente (autonomía local)
```
En La Paz, la consulta tolerante a fallos devuelve los datos disponibles:
```sql
SELECT count(*) FROM ventas_nacionales_disponibles();   -- avisa que Beni no responde
SELECT count(*) FROM ventas_nacionales WHERE departamento_id = 'SC';  -- funciona aunque Beni esté caído
```

### Paso 5 — Consistencia eventual del catálogo (Beni sigue cortado)
```powershell
.\demo.ps1 catalogo 10 99.90  # cambia el precio en La Paz: 5 nodos lo ven al instante y Beni NO
.\demo.ps1 reconectar beni
.\demo.ps1 sql beni "SELECT id_producto, nombre, precio_unitario FROM productos_catalogo WHERE id_producto = 10;"
#  -> Beni recibe el cambio pendiente al reconectarse (consistencia eventual)
.\demo.ps1 catalogo 10 5.00   # restaura el precio
```

### Paso 6 — Transacción distribuida con 2PC (Santa Cruz → Beni)
```powershell
.\demo.ps1 stock 10
.\demo.ps1 traspaso SC BE 10 5      # traspaso normal: FASE 1 (PREPARE) + FASE 2 (COMMIT)
```

### Paso 7 — Beni pierde conexión a mitad del traspaso: ROLLBACK automático
```powershell
.\demo.ps1 caida-traspaso
```
El script inicia un traspaso Santa Cruz → Beni y corta la red de Beni a mitad. Santa Cruz alcanza a votar SÍ (`PREPARE TRANSACTION`) pero Beni no responde, así que el coordinador ejecuta **`ROLLBACK PREPARED` en Santa Cruz**. El stock no cambia en ningún nodo. Al terminar, el script reconecta Beni.

### Paso 8 (opcional) — Caída después de votar: recuperación
```powershell
docker compose run --rm coordinador traspaso --origen SC --destino BE --producto 20 --cantidad 7 --pausa-commit 15
#   en OTRA ventana, durante la pausa:   .\demo.ps1 cortar beni
#   Santa Cruz confirma; Beni queda con la transacción PREPARADA ("en duda")
.\demo.ps1 reconectar beni
.\demo.ps1 recuperar        # consulta la bitácora en La Paz y ejecuta COMMIT PREPARED en Beni
```

---

## 4. Estructura del proyecto

```
docker-compose.yml            6 nodos + configurador + coordinador 2PC
demo.ps1                      comandos para la demostración
scripts/
  00_init_nodo.sh             arranque de cada nodo (lee NODO_ID, NODO_DEPTOS...)
  01_esquema_local.sql        DDL de cada nodo: fragmentos con CHECK, réplica del catálogo de solo lectura
  02_nodo_central.sql         solo La Paz: catálogo maestro, publicación, clientes_financiero, bitácora 2PC
  03_datos_prueba.sql         carga de datos de prueba (DML)
  04_fdw_vistas.sql           solo La Paz: postgres_fdw, vistas distribuidas, consultas tolerantes a fallos
  05_clientes_financiero.sql  solo La Paz: fragmento vertical FC2
  configurar.sh               orquesta la configuración inicial
coordinador/
  coordinador_2pc.py          coordinador del Compromiso en Dos Fases (Python + psycopg)
  Dockerfile
docs/arquitectura.md          documento de arquitectura (Fase 1)
```

## 5. Solución de problemas

| Problema | Solución |
|---|---|
| `docker` no se reconoce | Abre Docker Desktop y una terminal **nueva** |
| `.\demo.ps1` no se puede cargar | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| Puerto 5432 ocupado | Tienes PostgreSQL instalado en Windows: cambia `"5432:5432"` por `"5442:5432"` en `docker-compose.yml` |
| Algo quedó mal | `.\demo.ps1 reiniciar` |
| Ver qué pasó al configurar | `docker logs configurador` |
