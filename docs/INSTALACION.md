# Guía de instalación (desde cero)

Esta guía es para cualquier integrante del equipo que **nunca usó Docker**. Sigue los pasos en orden. La primera vez tarda entre 20 y 30 minutos, sobre todo por las descargas.

> Requisitos de la PC: Windows 10 u 11 de 64 bits, al menos 8 GB de RAM y unos 5 GB libres en disco.

---

## Paso 1 — Instalar WSL 2 (el "Linux" que usa Docker)

1. Aprieta la tecla **Windows**, escribe `powershell`, haz **clic derecho → Ejecutar como administrador** y acepta el aviso.
2. Escribe y presiona Enter:
   ```powershell
   wsl --install
   ```
3. Cuando termine, **reinicia la PC** (es obligatorio).
4. Si después del reinicio se abre una ventana de Ubuntu que pide usuario y contraseña, pon unos sencillos (por ejemplo `equipo` / `1234`). Si no se abre, no pasa nada.

> Si aparece un error sobre **virtualización** o **BIOS**: entra a la BIOS de la laptop (normalmente con F2, F10 o Supr al encender) y activa **Intel VT-x** o **AMD-V / SVM**.

## Paso 2 — Instalar Docker Desktop

1. Descárgalo de <https://www.docker.com/products/docker-desktop/>.
   - Elige **AMD64** si tu procesador es Intel o AMD (casi todas las laptops).
   - Elige **ARM64** solo si es Snapdragon o Qualcomm.
2. Ejecuta el instalador y deja las opciones por defecto: **Per-user installation** y **WSL 2**. Luego presiona **OK**.
3. Abre **Docker Desktop** desde el escritorio, acepta los términos (puedes saltarte el inicio de sesión) y espera a que abajo a la izquierda diga **Engine running**.

Comprueba que funciona. Abre una PowerShell **nueva** (normal, no como administrador):
```powershell
docker --version
docker compose version
```
Si los dos comandos muestran una versión, Docker está listo.

## Paso 3 — Instalar Git y descargar el proyecto

1. Si no tienes Git, instálalo desde <https://git-scm.com/download/win> con las opciones por defecto.
2. En PowerShell, ve a la carpeta donde quieras guardar el proyecto (por ejemplo, el Escritorio) y clónalo:
   ```powershell
   cd $HOME\Desktop
   git clone <URL-DEL-REPOSITORIO>
   cd <nombre-de-la-carpeta>
   ```

## Paso 4 — Permitir los scripts de PowerShell (solo una vez)

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```
Responde **S** si te lo pide.

## Paso 5 — Levantar el sistema

Con **Docker Desktop abierto** y dentro de la carpeta del proyecto:
```powershell
.\demo.ps1 iniciar
```

La primera vez descarga PostgreSQL y carga los datos, lo que toma unos 2 o 3 minutos. Al final debe aparecer:

```
     nodo_origen     | ventas |  total_bs
---------------------+--------+-------------
 Nodo 1 - La Paz     |  11000 | ...
 Nodo 2 - Santa Cruz |  15000 | ...
 Nodo 3 - Cochabamba |  10000 | ...
 Nodo 4 - Tarija     |   6000 | ...
 Nodo 5 - Oruro      |   5000 | ...
 Nodo 6 - Beni       |   3000 | ...

 total_ventas_nacionales
-------------------------
                   50000
SISTEMA DISTRIBUIDO LISTO.
```

**Ya está instalado.** Ahora sigue la [guía de pruebas](GUIA_PRUEBAS.md).

---

## Uso diario

| Quiero... | Comando |
|---|---|
| Encender los nodos (después de reiniciar la PC) | Abre Docker Desktop y ejecuta `docker compose start` |
| Ver si todo está bien | `.\demo.ps1 estado` |
| Apagar los nodos (los datos se conservan) | `docker compose stop` |
| Empezar de cero (borra los datos) | `.\demo.ps1 reiniciar` |
| Entrar a la consola SQL de un nodo | `.\demo.ps1 psql lapaz` (o `santacruz`, `cochabamba`, `tarija`, `oruro`, `beni`) |

## Conectarse con una interfaz gráfica (opcional)

Puedes usar **DBeaver** (<https://dbeaver.io>) o pgAdmin. Crea una conexión PostgreSQL por cada nodo:

| Nodo | Host | Puerto | Base de datos | Usuario | Contraseña |
|---|---|---|---|---|---|
| La Paz | localhost | 5431 | bolivia | postgres | bolivia123 |
| Santa Cruz | localhost | 5432 | bolivia | postgres | bolivia123 |
| Cochabamba | localhost | 5433 | bolivia | postgres | bolivia123 |
| Tarija | localhost | 5434 | bolivia | postgres | bolivia123 |
| Oruro | localhost | 5435 | bolivia | postgres | bolivia123 |
| Beni | localhost | 5436 | bolivia | postgres | bolivia123 |

## Problemas frecuentes

| Problema | Solución |
|---|---|
| `docker` no se reconoce como comando | Abre Docker Desktop, espera a que diga *Engine running* y abre una PowerShell **nueva** |
| `.\demo.ps1 no se puede cargar porque la ejecución de scripts está deshabilitada` | Repite el Paso 4 |
| `Virtual Machine Platform is not enabled` al instalar Docker | No hiciste el Paso 1: ejecuta `wsl --install` como administrador y reinicia |
| `port is already allocated` en el puerto 5432 | Tienes PostgreSQL instalado en Windows. En `docker-compose.yml` cambia `"5432:5432"` por `"5442:5432"` |
| Algo salió mal en la carga de datos | Revisa con `docker logs configurador` y luego ejecuta `.\demo.ps1 reiniciar` |
| La PC va lenta | Apaga los nodos con `docker compose stop` cuando no los uses |
