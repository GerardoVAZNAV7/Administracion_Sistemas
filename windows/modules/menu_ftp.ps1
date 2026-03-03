# =========================================================
# MENÚ DE ADMINISTRACIÓN FTP - PRACTICA 5
# =========================================================

# Cargar las funciones usando la ruta absoluta del módulo
$FuncPath = Join-Path $PSScriptRoot "ftp_functions.ps1"
if (Test-Path $FuncPath) {
    . $FuncPath
}

function menu-ftp {
    do {
        Clear-Host
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host "    ADMINISTRADOR DE SERVIDOR FTP" -ForegroundColor White
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host "1) Alta masiva de usuarios"
        Write-Host "2) Modificar grupo de usuario"
        Write-Host "3) LISTAR USUARIOS REGISTRADOS"
        Write-Host "4) Verificar estado del servicio"
        Write-Host "5) INSTALAR SERVICIO FTP"
        Write-Host "6) CONFIGURAR ENTORNO"
        Write-Host "0) Regresar al Menú Principal"
        Write-Host "---------------------------------------"
        $op = Read-Host "Seleccione una opción"

        switch ($op) {
            "1" { 
                $num = Read-Host "Cantidad de usuarios"
                for ($i=1; $i -le $num; $i++) {
                    $u = Read-Host "User $i"; $p = Read-Host "Pass"; $g = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                    $grp = if($g -eq "1"){"reprobados"}else{"recursadores"}
                    if(Get-Command Crear-UsuarioFTP -EA 0){
                        Crear-UsuarioFTP -user $u -pass $p -group $grp
                    }
                }
                Pause 
            }
            "2" {
                $u = Read-Host "Usuario"
                $g = Read-Host "Nuevo Grupo (1:reprobados, 2:recursadores)"
                $grp = if($g -eq "1"){"reprobados"}else{"recursadores"}
                Remove-LocalGroupMember -Group "reprobados","recursadores" -Member $u -EA 0
                Add-LocalGroupMember -Group $grp -Member $u -EA 0
                Write-Host "Grupo actualizado." -ForegroundColor Green
                Pause
            }
            "3" {
                Write-Host "`n--- [ USUARIOS REGISTRADOS ] ---" -ForegroundColor Cyan
                Get-LocalGroupMember -Group "ftp-users" -ErrorAction SilentlyContinue | Select Name
                Pause
            }
            "4" {
                $svc = Get-Service ftpsvc -ErrorAction SilentlyContinue
                if($svc){ 
                    Write-Host "Servicio: $($svc.Name) [$($svc.Status)]" -ForegroundColor Green 
                } else {
                    Write-Host "[!] Servicio FTP (ftpsvc) no encontrado." -ForegroundColor Red
                }
                Pause
            }
            "5" { if(Get-Command Instalar-ServicioFTP -EA 0){Instalar-ServicioFTP}else{Write-Host "Error: Funcion no cargada"}; Pause }
            "6" { if(Get-Command Configurar-EntornoFTP -EA 0){Configurar-EntornoFTP}else{Write-Host "Error: Funcion no cargada"}; Pause }
            "0" { return }
        }
    } while ($true)
}