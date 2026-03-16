# . .\http_functions.ps1

# if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
#     Write-Host "ERROR: Ejecuta como ADMINISTRADOR." -ForegroundColor Red ; exit
# }

# while ($true) {
#     Write-Host "`n=========================================" -ForegroundColor Magenta
#     Write-Host "   Aprovisionamiento Directo HTTP        " -ForegroundColor Magenta
#     Write-Host "=========================================" -ForegroundColor Magenta
#     Write-Host "1. IIS (Nativo de Windows)"
#     Write-Host "2. Apache (Standalone ZIP)"
#     Write-Host "3. Nginx (Standalone ZIP)"
#     Write-Host "4. Limpiar Entorno"
#     Write-Host "5. Salir"
#     $op = Read-Host "Opcion"
    
#     if ($op -eq "5") { break }
#     if ($op -eq "4") { Liberar-Entorno-Win; continue }

#     $p = Read-Host "Ingrese el puerto (ej. 80, 81, 8080)"

#     switch ($op) {
#         "1" { Instalar-IIS -puerto $p }
#         "2" { Instalar-Apache-Win -puerto $p }
#         "3" { Instalar-Nginx-Win -puerto $p }
#         Default { Write-Host "Opcion invalida" -ForegroundColor Yellow }
#     }
# }


# =============================================================================
# main_windows.ps1 - Aprovisionamiento HTTP en Windows Server 2022
# Uso: Ejecutar como Administrador en PowerShell
#      .\main_windows.ps1
# Arquitectura: Solo llama funciones definidas en http_functions.ps1
# =============================================================================

# Cargar funciones desde el mismo directorio que este script
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
. "$scriptDir\http_functions.ps1"

# -----------------------------------------------------------------------------
# Verificar que se ejecuta como Administrador
# -----------------------------------------------------------------------------
$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
$isAdmin = $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    Write-Host ""
    Write-Host "  [ERROR] Este script requiere privilegios de Administrador." -ForegroundColor Red
    Write-Host "  Click derecho en PowerShell -> 'Ejecutar como administrador'" -ForegroundColor Yellow
    Write-Host ""
    Read-Host "  Presiona Enter para salir"
    exit 1
}

# Configurar politica de ejecucion si es necesario
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue

# -----------------------------------------------------------------------------
# Bucle principal del menu
# -----------------------------------------------------------------------------
while ($true) {
    Write-Host ""
    Write-Host "  +=============================================+" -ForegroundColor Magenta
    Write-Host "  |    Aprovisionamiento HTTP Multi-Servidor    |" -ForegroundColor Magenta
    Write-Host "  |         Windows Server 2022                 |" -ForegroundColor Magenta
    Write-Host "  |         VM: $VM_IP                          |" -ForegroundColor Magenta
    Write-Host "  +=============================================+" -ForegroundColor Magenta
    Write-Host "  |  1) IIS  (Nativo de Windows Server)         |" -ForegroundColor White
    Write-Host "  |  2) Apache HTTP Server (ZIP desde C:\)      |" -ForegroundColor White
    Write-Host "  |  3) Nginx Web Server   (ZIP desde C:\)      |" -ForegroundColor White
    Write-Host "  |  4) Limpiar entorno                         |" -ForegroundColor White
    Write-Host "  |  5) Salir                                   |" -ForegroundColor White
    Write-Host "  +=============================================+" -ForegroundColor Magenta
    Write-Host ""

    $opcion = Read-Host "  Selecciona una opcion (1-5)"

    # Validar que no este vacia ni tenga caracteres invalidos
    if ([string]::IsNullOrWhiteSpace($opcion) -or $opcion -notmatch '^[1-5]$') {
        Write-Host "  [!] Opcion invalida. Elige entre 1 y 5." -ForegroundColor Yellow
        continue
    }

    if ($opcion -eq "5") {
        Write-Host ""
        Write-Host "  [*] Saliendo del aprovisionador. Hasta luego!" -ForegroundColor Cyan
        Write-Host ""
        break
    }

    if ($opcion -eq "4") {
        Liberar-Entorno-Win
        continue
    }

    # Determinar nombre del servicio para el prompt de puerto
    $nombreServicio = switch ($opcion) {
        "1" { "IIS"    }
        "2" { "Apache" }
        "3" { "Nginx"  }
    }

    Write-Host ""
    Write-Host "  [*] Configurando: $nombreServicio" -ForegroundColor Cyan
    Write-Host "  ---------------------------------------------" -ForegroundColor DarkGray

    # Solicitar y validar puerto
    $puerto = Solicitar-Puerto -ServicioNombre $nombreServicio

    Write-Host ""
    Write-Host "  [*] Iniciando instalacion..." -ForegroundColor Cyan
    Write-Host "      Servidor : $nombreServicio" -ForegroundColor White
    Write-Host "      Puerto   : $puerto"         -ForegroundColor White
    Write-Host "      URL      : http://${VM_IP}:${puerto}" -ForegroundColor White
    Write-Host "  ---------------------------------------------" -ForegroundColor DarkGray

    # Llamar a la funcion de instalacion correspondiente
    switch ($opcion) {
        "1" { Instalar-IIS        -Puerto $puerto }
        "2" { Instalar-Apache-Win -Puerto $puerto }
        "3" { Instalar-Nginx-Win  -Puerto $puerto }
    }

    Write-Host ""
    Write-Host "  ---------------------------------------------" -ForegroundColor DarkGray
    Write-Host "  Verificacion desde tu maquina host:" -ForegroundColor Cyan
    Write-Host "    Abrir en navegador: http://${VM_IP}:${puerto}" -ForegroundColor White
    Write-Host "    O desde PowerShell: Invoke-WebRequest http://${VM_IP}:${puerto}" -ForegroundColor White
    Write-Host "  ---------------------------------------------" -ForegroundColor DarkGray
    Write-Host ""

    $continuar = Read-Host "  Instalar otro servidor? (s/n)"

    # Validar respuesta
    if ([string]::IsNullOrWhiteSpace($continuar) -or $continuar -notmatch '^[sSnN]$') {
        $continuar = "n"
    }

    if ($continuar -ne "s" -and $continuar -ne "S") {
        Write-Host ""
        Write-Host "  [*] Aprovisionamiento completado!" -ForegroundColor Green
        Write-Host ""
        break
    }
}