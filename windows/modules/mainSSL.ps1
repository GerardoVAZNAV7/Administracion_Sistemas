# =============================================================================
# mainSSL.ps1
# Orquestador de instalacion hibrida SSL/TLS para Windows Server 2022
# Practica 7: Infraestructura de Despliegue Seguro
# =============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

# =============================================================================
# CARGAR FUNCIONES
# ─────────────────────────────────────────────────────────────────────────────
# LECCION: $PSScriptRoot es la variable correcta para referenciar archivos
# que están junto al script actual.
#
# $MyInvocation.MyCommand.Definition puede devolver vacío o incorrecto
# dependiendo de cómo PowerShell cargó el script (dot-source, llamada directa,
# ISE, etc.). $PSScriptRoot SIEMPRE contiene la carpeta del .ps1 en ejecución.
# =============================================================================
$funcionesPath = Join-Path $PSScriptRoot "funciones_SSL.ps1"

if (-not (Test-Path $funcionesPath)) {
    Write-Host "[ERROR] No se encontro funciones_SSL.ps1 en: $PSScriptRoot" -ForegroundColor Red
    Write-Host "        Ambos archivos deben estar en la misma carpeta." -ForegroundColor Yellow
    Read-Host "Presiona Enter para salir"
    exit 1
}

# Dot-source: carga todas las funciones en el scope actual
. $funcionesPath

# Verificar que las funciones quedaron cargadas (diagnóstico temprano)
$funcionesRequeridas = @("Instalar-Apache", "Instalar-Nginx", "Instalar-IIS-Web", "Instalar-IIS-FTP")
$faltantes = $funcionesRequeridas | Where-Object {
    -not (Get-Command $_ -ErrorAction SilentlyContinue)
}
if ($faltantes) {
    Write-Host "[ERROR] Las siguientes funciones no se cargaron desde funciones_SSL.ps1:" -ForegroundColor Red
    $faltantes | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "  Verifica que funciones_SSL.ps1 no tenga errores de sintaxis." -ForegroundColor Yellow
    Read-Host "Presiona Enter para salir"
    exit 1
}

# =============================================================================
# VERIFICAR PRIVILEGIOS
# =============================================================================
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)
if (-not $esAdmin) {
    Write-Host "[ERROR] Ejecuta PowerShell como Administrador." -ForegroundColor Red
    Read-Host "Presiona Enter para salir"
    exit 1
}

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue

# =============================================================================
# MENU
# =============================================================================
function Mostrar-MenuSSL {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host "  |   PRACTICA 7 - DESPLIEGUE SEGURO SSL/TLS (WINDOWS)         |" -ForegroundColor Cyan
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host "  |  Instalar con opcion de SSL/TLS:                           |" -ForegroundColor White
    Write-Host "  |    1) Apache HTTP Server  - HTTP/HTTPS                     |" -ForegroundColor White
    Write-Host "  |    2) Nginx Web Server    - HTTP/HTTPS                     |" -ForegroundColor White
    Write-Host "  |    3) IIS Web Server      - HTTP/HTTPS                     |" -ForegroundColor White
    Write-Host "  |    4) IIS FTP Server      - FTP/FTPS                       |" -ForegroundColor White
    Write-Host "  |    5) Ver resumen de instalaciones                         |" -ForegroundColor White
    Write-Host "  |    0) Salir                                                |" -ForegroundColor White
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host ""
}

# =============================================================================
# BUCLE PRINCIPAL
# =============================================================================
do {
    Mostrar-MenuSSL
    $opcion = Read-Host "  Selecciona una opcion (0-5)"

    switch ($opcion) {

        "1" {
            Write-Host ""
            Write-Host "  [ APACHE HTTP SERVER ]" -ForegroundColor Cyan
            Instalar-Apache
            Write-Host ""
            Read-Host "  Presiona Enter para continuar..."
        }

        "2" {
            Write-Host ""
            Write-Host "  [ NGINX WEB SERVER ]" -ForegroundColor Cyan
            Instalar-Nginx
            Write-Host ""
            Read-Host "  Presiona Enter para continuar..."
        }

        "3" {
            Write-Host ""
            Write-Host "  [ IIS WEB SERVER ]" -ForegroundColor Cyan
            Instalar-IIS-Web
            Write-Host ""
            Read-Host "  Presiona Enter para continuar..."
        }

        "4" {
            Write-Host ""
            Write-Host "  [ IIS FTP SERVER ]" -ForegroundColor Cyan
            Instalar-IIS-FTP
            Write-Host ""
            Read-Host "  Presiona Enter para continuar..."
        }

        "5" {
            Write-Host ""
            Write-Host "  +============================================+" -ForegroundColor Green
            Write-Host "  |       RESUMEN DE INSTALACIONES             |" -ForegroundColor Green
            Write-Host "  +============================================+" -ForegroundColor Green

            if ($global:resumenInstalaciones.Count -eq 0) {
                Write-Host "  (Sin instalaciones en esta sesion)" -ForegroundColor Yellow
            } else {
                foreach ($r in $global:resumenInstalaciones) {
                    Write-Host "    $r" -ForegroundColor White
                }
            }

            Write-Host ""
            Write-Host "  Estado de servicios:" -ForegroundColor Cyan

            foreach ($svc in @("W3SVC", "ftpsvc")) {
                $s      = Get-Service $svc -ErrorAction SilentlyContinue
                $estado = if ($s) { $s.Status.ToString() } else { "No instalado" }
                $color  = if ($s -and $s.Status -eq "Running") { "Green" } else { "Yellow" }
                Write-Host ("    {0,-10} -> {1}" -f $svc, $estado) -ForegroundColor $color
            }

            foreach ($proc in @("httpd", "nginx")) {
                $p      = Get-Process $proc -ErrorAction SilentlyContinue
                $estado = if ($p) { "Corriendo (PID: $($p.Id))" } else { "No activo" }
                $color  = if ($p) { "Green" } else { "DarkGray" }
                Write-Host ("    {0,-10} -> {1}" -f $proc, $estado) -ForegroundColor $color
            }

            Write-Host ""
            Write-Host "  Puertos HTTP/HTTPS activos:" -ForegroundColor Cyan
            netstat -ano 2>$null | Select-String "LISTENING" |
                Where-Object { $_ -match ":80 |:443 |:8080 |:8443 |:21 |:990 " } |
                ForEach-Object { Write-Host ("    " + $_.Line.Trim()) -ForegroundColor Gray }

            Write-Host "  +============================================+" -ForegroundColor Green
            Write-Host ""
            Read-Host "  Presiona Enter para continuar..."
        }

        "0" {
            if ($global:resumenInstalaciones.Count -gt 0) {
                Write-Host ""
                Write-Host "  Resumen final:" -ForegroundColor Green
                foreach ($r in $global:resumenInstalaciones) {
                    Write-Host "    $r" -ForegroundColor White
                }
            }
            Write-Host ""
            Write-Host "  [*] Saliendo. Hasta luego." -ForegroundColor Cyan
        }

        default {
            Write-Host "  [!] Opcion invalida. Elige entre 0 y 5." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }

} while ($opcion -ne "0")