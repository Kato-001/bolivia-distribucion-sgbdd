<#
  BoliviaDistribucion S.A. - Herramienta de demostracion del SGBDD
  Uso:  .\demo.ps1 <comando> [argumentos]

  .\demo.ps1 iniciar                      Enciende los 6 nodos y configura todo
  .\demo.ps1 estado                       Contenedores + ventas por nodo (desde La Paz)
  .\demo.ps1 psql <nodo>                  Abre la consola SQL de un nodo
  .\demo.ps1 sql <nodo> "<consulta>"      Ejecuta una consulta en un nodo
  .\demo.ps1 cortar <nodo>                Simula corte de red del nodo
  .\demo.ps1 reconectar <nodo>            Restaura la red del nodo
  .\demo.ps1 venta <nodo>                 Registra una venta LOCAL en ese nodo
  .\demo.ps1 traspaso SC BE 10 5 [pausa]  Traspaso 2PC (origen destino producto cantidad)
  .\demo.ps1 caida-traspaso               Demo automatica: Beni se cae a mitad del 2PC
  .\demo.ps1 stock <producto>             Stock de un producto en los 9 departamentos
  .\demo.ps1 recuperar                    Resuelve transacciones 2PC pendientes
  .\demo.ps1 catalogo <producto> <precio> Cambia un precio en La Paz y muestra la replicacion
  .\demo.ps1 reiniciar                    BORRA todo y vuelve a crear el sistema desde cero

  Nodos: lapaz, santacruz, cochabamba, tarija, oruro, beni
#>
param(
    [Parameter(Position = 0)][string]$Comando = "ayuda",
    [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Args2
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
Set-Location $PSScriptRoot

# Docker Desktop instalado "por usuario" puede no estar en el PATH
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    $env:Path += ";$env:LOCALAPPDATA\Programs\DockerDesktop\resources\bin;C:\Program Files\Docker\Docker\resources\bin"
}

$NODOS = [ordered]@{
    lapaz      = "nodo1_lapaz"
    santacruz  = "nodo2_santacruz"
    cochabamba = "nodo3_cochabamba"
    tarija     = "nodo4_tarija"
    oruro      = "nodo5_oruro"
    beni       = "nodo6_beni"
}

function Get-Contenedor([string]$n) {
    if (-not $n) { Write-Host "Falta el nombre del nodo: $($NODOS.Keys -join ', ')" -ForegroundColor Red; exit 1 }
    $k = $n.ToLower()
    if ($NODOS.Contains($k)) { return $NODOS[$k] }
    if ($NODOS.Values -contains $k) { return $k }
    Write-Host "Nodo desconocido '$n'. Usa: $($NODOS.Keys -join ', ')" -ForegroundColor Red; exit 1
}

function Invoke-Sql([string]$contenedor, [string]$consulta) {
    docker exec -i $contenedor psql -U postgres -d bolivia -c $consulta
}

function Write-Titulo([string]$t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }

switch ($Comando.ToLower()) {

    "iniciar" {
        Write-Titulo "Encendiendo los 6 nodos (la primera vez tarda unos minutos)"
        docker rm -f configurador *> $null    # borra el registro de ejecuciones anteriores
        docker compose up -d
        Write-Titulo "Esperando al configurador (replicacion, datos, vistas)..."
        docker wait configurador | Out-Null
        docker logs configurador
    }

    "estado" {
        Write-Titulo "Contenedores"
        docker ps -a --filter "network=bolivia_red" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        foreach ($c in $NODOS.Values) {
            $redes = docker inspect -f "{{range `$k, `$v := .NetworkSettings.Networks}}{{`$k}} {{end}}" $c 2>$null
            if ($redes -notmatch "bolivia_red") { Write-Host "  $c -> RED CORTADA (aislado)" -ForegroundColor Yellow }
        }
        Write-Titulo "Ventas por nodo (consulta tolerante a fallos desde La Paz)"
        Invoke-Sql "nodo1_lapaz" "SELECT * FROM resumen_ventas_por_nodo();"
    }

    "psql" {
        $c = Get-Contenedor $Args2[0]
        docker exec -it $c psql -U postgres -d bolivia
    }

    "sql" {
        $c = Get-Contenedor $Args2[0]
        Invoke-Sql $c ($Args2[1..($Args2.Count - 1)] -join " ")
    }

    "cortar" {
        $c = Get-Contenedor $Args2[0]
        docker network disconnect bolivia_red $c
        Write-Host "Red cortada: $c esta aislado del resto del pais (sigue encendido)." -ForegroundColor Yellow
    }

    "reconectar" {
        $c = Get-Contenedor $Args2[0]
        docker network connect bolivia_red $c
        Write-Host "Red restaurada: $c vuelve a estar en linea." -ForegroundColor Green
    }

    "venta" {
        $c = Get-Contenedor $Args2[0]
        Write-Titulo "Venta LOCAL en $c (usa solo datos del propio nodo)"
        Invoke-Sql $c @"
SELECT registrar_venta(
         (SELECT id_cliente FROM clientes_datos_generales ORDER BY random() LIMIT 1),
         (1 + floor(random()*200))::int, 1) AS id_venta_nueva;
SELECT count(*) AS ventas_en_este_nodo, max(fecha_hora) AS ultima_venta FROM ventas;
"@
    }

    "traspaso" {
        if ($Args2.Count -lt 4) { Write-Host "Uso: .\demo.ps1 traspaso SC BE 10 5 [pausa_segundos]"; exit 1 }
        $extra = @()
        if ($Args2.Count -ge 5) { $extra = @("--pausa", $Args2[4]) }
        docker compose --progress quiet run --rm coordinador traspaso --origen $Args2[0] --destino $Args2[1] `
            --producto $Args2[2] --cantidad $Args2[3] @extra
    }

    "caida-traspaso" {
        Write-Titulo "DEMO: Beni pierde la conexion a mitad del traspaso Santa Cruz -> Beni"
        docker compose --progress quiet run --rm coordinador stock --producto 10
        $job = Start-Job -ScriptBlock {
            param($dir, $path)
            Set-Location $dir; $env:Path = $path; [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            docker compose --progress quiet run --rm -T coordinador traspaso --origen SC --destino BE --producto 10 --cantidad 25 --pausa 12 2>&1
        } -ArgumentList $PSScriptRoot, $env:Path
        Write-Host "Coordinador iniciado; en 8 segundos se cortara la red de Beni..." -ForegroundColor Yellow
        Start-Sleep -Seconds 8
        docker network disconnect bolivia_red nodo6_beni
        Write-Host ">>> RED DE BENI CORTADA <<<" -ForegroundColor Red
        Receive-Job $job -Wait -AutoRemoveJob
        Write-Titulo "Comprobacion en Santa Cruz: el stock NO cambio (rollback automatico)"
        Invoke-Sql "nodo2_santacruz" "SELECT a.departamento_id, i.id_producto, i.stock_actual FROM inventario i JOIN almacenes a USING (id_almacen) WHERE i.id_producto = 10; SELECT gid, prepared FROM pg_prepared_xacts;"
        Write-Titulo "Bitacora del coordinador (La Paz)"
        Invoke-Sql "nodo1_lapaz" "SELECT gid, origen, destino, cantidad, estado, detalle FROM coordinador_2pc_log ORDER BY creado DESC LIMIT 3;"
        docker network connect bolivia_red nodo6_beni
        Write-Host "Red de Beni restaurada." -ForegroundColor Green
    }

    "stock" {
        docker compose --progress quiet run --rm coordinador stock --producto $Args2[0]
    }

    "recuperar" {
        docker compose --progress quiet run --rm coordinador recuperar
    }

    "catalogo" {
        if ($Args2.Count -lt 2) { Write-Host "Uso: .\demo.ps1 catalogo <id_producto> <nuevo_precio>"; exit 1 }
        $id = [int]$Args2[0]; $precio = $Args2[1]
        Write-Titulo "Actualizando precio del producto $id a Bs $precio en LA PAZ (maestro)"
        Invoke-Sql "nodo1_lapaz" "UPDATE productos_catalogo SET precio_unitario = $precio WHERE id_producto = $id RETURNING id_producto, nombre, precio_unitario;"
        for ($i = 1; $i -le 3; $i++) {
            Start-Sleep -Seconds 1
            Write-Titulo "Precio en cada nodo (lectura $i, +$i s)"
            foreach ($k in $NODOS.Keys) {
                $c = $NODOS[$k]
                $p = docker exec $c psql -U postgres -d bolivia -tAc "SELECT precio_unitario FROM productos_catalogo WHERE id_producto = $id" 2>$null
                if (-not $p) { $p = "(sin respuesta)" }
                $color = if ($p.Trim() -eq ([decimal]$precio).ToString("0.00", [Globalization.CultureInfo]::InvariantCulture)) { "Green" } else { "Yellow" }
                Write-Host ("  {0,-18} Bs {1}" -f $k, $p.Trim()) -ForegroundColor $color
            }
        }
        Write-Titulo "Estado de la replicacion (desde La Paz)"
        Invoke-Sql "nodo1_lapaz" "SELECT * FROM estado_replicacion;"
    }

    "reiniciar" {
        Write-Host "Esto BORRA todos los datos y recrea el sistema. Continuar? (s/n)" -ForegroundColor Yellow
        if ((Read-Host) -ne "s") { exit 0 }
        docker compose down -v
        & $PSCommandPath iniciar
    }

    default {
        Get-Content $PSCommandPath -TotalCount 20 | Select-Object -Skip 1 | ForEach-Object { Write-Host $_ }
    }
}
