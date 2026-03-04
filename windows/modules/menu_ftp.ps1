# =====================================================
# menu_ftp.ps1 - Menu Practica 5: FTP
# Llama funciones definidas en ftp_functions.ps1
# El orquestador main.ps1 hace dot-source de este archivo
# y llama la funcion: menu-ftp
# =====================================================

# Cargar ftp_functions.ps1 desde la misma carpeta que este archivo
# $PSScriptRoot apunta a donde está menu_ftp.ps1 (carpeta modules\)
$_ftpFunc = Join-Path $PSScriptRoot "ftp_functions.ps1"
if (Test-Path $_ftpFunc) {
    . $_ftpFunc
} else {
    Write-Host "[ERROR] No se encontro ftp_functions.ps1 en: $_ftpFunc" -ForegroundColor Red
}

# ─────────────────────────────────────────────────────
# menu-ftp  ← nombre exacto que llama main.ps1
# ─────────────────────────────────────────────────────
function menu-ftp {
    do {
        Clear-Host
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "   PRACTICA 5: AUTOMATIZACION FTP"      -ForegroundColor White
        Write-Host "       Windows Server 2022 / IIS"       -ForegroundColor DarkCyan
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "  1) Instalar Servicio FTP (IIS)"
        Write-Host "  2) Configurar Servicio y Carpetas"
        Write-Host "  3) Alta Masiva de Usuarios"
        Write-Host "  4) Ver Usuarios del Sistema"
        Write-Host "  5) Cambiar Usuario de Grupo"
        Write-Host "  0) Regresar al Menu Principal"
        Write-Host ""
        $opcionFtp = Read-Host "Seleccione una opcion"

        switch ($opcionFtp) {
            "1" { Install-FTPService;     Pause }
            "2" { Configure-FTPEnvironment; Pause }
            "3" { Add-MassiveUsers;       Pause }
            "4" { Show-FTPUsers;          Pause }
            "5" { Update-UserGroup;       Pause }
            "0" { return }
            default { Write-Host "Opcion no valida" -ForegroundColor Red; Pause }
        }
    } while ($opcionFtp -ne "0")
}
