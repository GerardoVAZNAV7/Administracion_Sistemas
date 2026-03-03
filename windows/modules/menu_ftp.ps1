# =========================================================
# MENÚ DE ADMINISTRACIÓN FTP
# =========================================================

# Localizar y cargar el archivo de funciones de forma segura
$currentDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$functionsFile = Join-Path $currentDir "ftp_functions.ps1"

if (Test-Path $functionsFile) {
    . $functionsFile
} else {
    Write-Host "[!] ERROR: No se encontro $functionsFile" -ForegroundColor Red
    Pause
    return
}

function menu-ftp {
    do {
        Clear-Host
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host "     SISTEMA DE GESTION FTP - P5" -ForegroundColor White
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host "1) Alta masiva de usuarios"
        Write-Host "2) Modificar grupo de usuario"
        Write-Host "3) LISTAR USUARIOS REGISTRADOS"
        Write-Host "4) Verificar estado del servicio"
        Write-Host "5) PASO 1: INSTALAR ROL FTP"
        Write-Host "6) PASO 2: CONFIGURAR ENTORNO"
        Write-Host "0) Regresar al Menú Principal"
        Write-Host "---------------------------------------"
        $opc = Read-Host "Seleccione una opcion"

        switch ($opc) {
            "1" {
                $n = Read-Host "Cantidad de usuarios"
                for ($i=1; $i -le $n; $i++) {
                    $u = Read-Host "Nombre de usuario $i"
                    $p = Read-Host "Contraseña"
                    $g = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                    $selectedGroup = if ($g -eq "1") { "reprobados" } else { "recursadores" }
                    Crear-UsuarioFTP -user $u -pass $p -group $selectedGroup
                }
                Pause
            }
            "2" {
                $u = Read-Host "Nombre del usuario"
                if (Get-LocalUser -Name $u -ErrorAction SilentlyContinue) {
                    $g = Read-Host "Nuevo Grupo (1:reprobados, 2:recursadores)"
                    $newGroup = if ($g -eq "1") { "reprobados" } else { "recursadores" }
                    # Limpiar grupos anteriores y asignar nuevo
                    Remove-LocalGroupMember -Group "reprobados","recursadores" -Member $u -ErrorAction SilentlyContinue
                    Add-LocalGroupMember -Group $newGroup -Member $u
                    Write-Host "[✓] Grupo actualizado." -ForegroundColor Green
                } else { Write-Host "[!] Usuario no existe." -ForegroundColor Red }
                Pause
            }
            "3" {
                Write-Host "`n--- Usuarios en ftp-users ---" -ForegroundColor Cyan
                Get-LocalGroupMember -Group "ftp-users" | Select-Object Name
                Pause
            }
            "4" {
                $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
                if ($svc) { Write-Host "Estado del servicio FTP: $($svc.Status)" -ForegroundColor Green }
                else { Write-Host "Servicio no instalado." -ForegroundColor Red }
                Pause
            }
            "5" { Instalar-ServicioFTP; Pause }
            "6" { Configurar-EntornoFTP; Pause }
            "0" { return }
            default { Write-Host "Opcion invalida."; Pause }
        }
    } while ($true)
}