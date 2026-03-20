# =============================================================================
# mainSSL.ps1 — Orquestador de instalación híbrida SSL/TLS para Windows Server
# Práctica 7: Infraestructura de Despliegue Seguro
#
# USO:
#   1. Abrir PowerShell como Administrador
#   2. Set-ExecutionPolicy Bypass -Scope Process
#   3. .\windows\modules\mainSSL.ps1
#
# REQUIERE:
#   - PowerShell como Administrador
#   - funciones_SSL.ps1 en el mismo directorio
#   - Chocolatey instalado (o ZIPs en C:\)
#   - Usuario FTP "repositorio" activo (Práctica 5)
# =============================================================================

# ── Cargar funciones desde el mismo directorio ───────────────────────────────
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$funcionesPath = Join-Path $ScriptDir "funciones_SSL.ps1"

if (-not (Test-Path $funcionesPath)) {
    Write-Host "[ERROR] No se encontró funciones_SSL.ps1 en: $ScriptDir" -ForegroundColor Red
    Write-Host "        Asegúrate de que ambos archivos estén en la misma carpeta." -ForegroundColor Yellow
    Read-Host "Presiona Enter para salir"
    exit 1
}

. $funcionesPath

# ── Verificar privilegios de Administrador ───────────────────────────────────
$esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

if (-not $esAdmin) {
    Write-Host ""
    Write-Host "[ERROR] Ejecuta PowerShell como Administrador." -ForegroundColor Red
    Write-Host "        Click derecho → 'Ejecutar como administrador'" -ForegroundColor Yellow
    Read-Host "Presiona Enter para salir"
    exit 1
}

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue

# =============================================================================
# MENÚ PRINCIPAL
# =============================================================================

function Mostrar-MenuSSL {
    Clear-Host
    Write-Host ""
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host "  |      PRÁCTICA 7 — DESPLIEGUE SEGURO SSL/TLS (WINDOWS)      |" -ForegroundColor Cyan
    Write-Host "  +============================================================+" -ForegroundColor Cyan
    Write-Host "  |  Instalar con opción de SSL/TLS:                           |" -ForegroundColor White
    Write-Host "  |    1) Apache HTTP Server  — HTTP/HTTPS                     |" -ForegroundColor White
    Write-Host "  |    2) Nginx Web Server    — HTTP/HTTPS                     |" -ForegroundColor White
    Write-Host "  |    3) IIS Web Server      — HTTP/HTTPS                     |" -ForegroundColor White
    Write-Host "  |    4) IIS FTP Server      — FTP/FTPS                       |" -ForegroundColor White
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
    $opcion = Read-Host "  Selecciona una opción (0-5)"

    switch ($opcion) {

        "1" {
            Write-Host ""
            Write-Host "  ── APACHE HTTP SERVER ──" -ForegroundColor Cyan
            Instalar-Apache
        }

        "2" {
            Write-Host ""
            Write-Host "  ── NGINX WEB SERVER ──" -ForegroundColor Cyan
            Instalar-Nginx
        }

        "3" {
            Write-Host ""
            Write-Host "  ── IIS WEB SERVER ──" -ForegroundColor Cyan
            Instalar-IIS-Web
        }

        "4" {
            Write-Host ""
            Write-Host "  ── IIS FTP SERVER ──" -ForegroundColor Cyan
            Instalar-IIS-FTP
        }

        "5" {
            Write-Host ""
            Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
            Write-Host "     RESUMEN DE INSTALACIONES              " -ForegroundColor Green
            Write-Host "  ════════════════════════════════════════" -ForegroundColor Green

            if ($global:resumenInstalaciones.Count -eq 0) {
                Write-Host "  (Sin instalaciones registradas en esta sesión)" -ForegroundColor Yellow
            } else {
                foreach ($r in $global:resumenInstalaciones) {
                    Write-Host "    $r" -ForegroundColor White
                }
            }

            Write-Host ""
            Write-Host "  Estado de servicios:" -ForegroundColor Cyan
            @("W3SVC", "ftpsvc") | ForEach-Object {
                $svc = Get-Service $_ -ErrorAction SilentlyContinue
                $estado = if ($svc) { $svc.Status } else { "No instalado" }
                Write-Host ("    {0,-10} → {1}" -f $_, $estado)
            }
            foreach ($proc in @("httpd", "nginx")) {
                $p = Get-Process $proc -ErrorAction SilentlyContinue
                $estado = if ($p) { "Corriendo" } else { "Detenido / No instalado" }
                Write-Host ("    {0,-10} → {1}" -f $proc, $estado)
            }

            Write-Host "  ════════════════════════════════════════" -ForegroundColor Green
            Write-Host ""
            Read-Host "  Presiona Enter para continuar..."
        }

        "0" {
            # Mostrar resumen antes de salir
            if ($global:resumenInstalaciones.Count -gt 0) {
                Write-Host ""
                Write-Host "  ── Resumen final ──" -ForegroundColor Green
                foreach ($r in $global:resumenInstalaciones) {
                    Write-Host "    $r" -ForegroundColor White
                }
            }
            Write-Host ""
            Write-Host "  [*] Saliendo del orquestador SSL." -ForegroundColor Cyan
        }

        default {
            Write-Host "  [!] Opción inválida. Elige entre 0 y 5." -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
    }

} while ($opcion -ne "0")