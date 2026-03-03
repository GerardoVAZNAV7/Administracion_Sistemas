# Validar privilegios de Administrador
$currentPrincipal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Debes ejecutar PowerShell como ADMINISTRADOR." -ForegroundColor Red
    Pause
    exit
}

# Cargar funciones tecnicas
$FuncPath = Join-Path $PSScriptRoot "ftp_functions.ps1"
if (Test-Path $FuncPath) { . $FuncPath }

function menu-ftp {
    do {
        Clear-Host
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "   PRACTICA 5: AUTOMATIZACION FTP" -ForegroundColor White
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "1) Instalar Servicio FTP (IIS)"
        Write-Host "2) Configurar Servicio y Carpetas"
        Write-Host "3) Alta Masiva de Usuarios"
        Write-Host "4) Ver Usuarios del Sistema"
        Write-Host "5) Cambiar Usuario de Grupo"
        Write-Host "0) Salir"
        Write-Host ""

        $opcionFtp = Read-Host "Seleccione una opcion"

        switch ($opcionFtp) {
            "1" { Install-FTPService; Pause }
            "2" { Configure-FTPEnvironment; Pause }
            "3" { Add-MassiveUsers; Pause }
            "4" { 
                Write-Host "--- Usuarios Locales ---" -ForegroundColor Yellow
                Get-LocalUser | Select-Object Name, Enabled | Out-String | Write-Host
                Pause 
            }
            "5" { Update-UserGroup; Pause }
            "0" { return }
            default { Write-Host "Opcion no valida"; Pause }
        }
    } while ($opcionFtp -ne "0")
}

