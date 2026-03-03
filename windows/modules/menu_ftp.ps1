# =========================================================
# MENÚ DE ADMINISTRACIÓN FTP - WINDOWS SERVER 2022
# =========================================================

# Importar el módulo de funciones (Asegúrate que ambos archivos estén en la misma carpeta)
. "$PSScriptRoot\FTP_Functions.ps1"

function Mostrar-Menu {
    do {
        Clear-Host
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host "   ADMINISTRADOR FTP - WINDOWS SERVER" -ForegroundColor White
        Write-Host "=======================================" -ForegroundColor Yellow
        Write-Host "1) Alta masiva de usuarios"
        Write-Host "2) Modificar grupo de usuario"
        Write-Host "3) LISTAR USUARIOS REGISTRADOS"
        Write-Host "4) Verificar estado/IP del servicio"
        Write-Host "5) PASO 1: INSTALAR ROL FTP"
        Write-Host "6) PASO 2: CONFIGURAR ENTORNO (Estructuras/ACLs)"
        Write-Host "0) Salir"
        Write-Host "---------------------------------------"
        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {
            "1" {
                $n = Read-Host "Número de usuarios a crear"
                for ($i=1; $i -le $n; $i++) {
                    Write-Host "`n--- Datos del usuario $i ---" -ForegroundColor Cyan
                    $uname = Read-Host "Username"
                    $upass = Read-Host "Password"
                    $g_op = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                    $ugroup = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                    
                    # Llamada a la función del módulo
                    Crear-UsuarioFTP -user $uname -pass $upass -group $ugroup
                }
                Pause
            }

            "2" {
                $uname = Read-Host "Ingrese el nombre del usuario"
                if (Get-LocalUser -Name $uname -ErrorAction SilentlyContinue) {
                    $g_op = Read-Host "Nuevo Grupo (1:reprobados, 2:recursadores)"
                    $newGroup = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                    
                    # Lógica de cambio de grupo y actualización de enlaces
                    Remove-LocalGroupMember -Group "reprobados", "recursadores" -Member $uname -ErrorAction SilentlyContinue
                    Add-LocalGroupMember -Group $newGroup -Member $uname
                    
                    $userHome = "C:\inetpub\ftproot\LocalUser\$uname"
                    Remove-Item "$userHome\reprobados", "$userHome\recursadores" -ErrorAction SilentlyContinue
                    cmd /c mklink /D "$userHome\$newGroup" "C:\inetpub\ftproot\LocalUser\$newGroup"
                    
                    Write-Host "[✓] Grupo y enlaces actualizados para $uname." -ForegroundColor Green
                } else {
                    Write-Host "[!] El usuario no existe." -ForegroundColor Red
                }
                Pause
            }

            "3" {
                Write-Host "`n--- [ USUARIOS REGISTRADOS EN FTP ] ---" -ForegroundColor Cyan
                if (Get-LocalGroup -Name "ftp-users" -ErrorAction SilentlyContinue) {
                    Get-LocalGroupMember -Group "ftp-users" | Select-Object Name, PrincipalSource
                } else {
                    Write-Host "[!] El sistema no ha sido configurado (Falta grupo ftp-users)." -ForegroundColor Yellow
                }
                Pause
            }

            "4" {
                Write-Host "`n--- [ DIAGNÓSTICO ] ---" -ForegroundColor Cyan
                try {
                    $svc = Get-Service ftpsvc -ErrorAction Stop
                    Write-Host "Servicio FTP: $($svc.Status)" -ForegroundColor Green
                } catch {
                    Write-Host "Servicio FTP: [ NO INSTALADO ]" -ForegroundColor Red
                }
                Write-Host "IPs para FileZilla:"
                Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127*" } | Select-Object InterfaceAlias, IPAddress
                Pause
            }

            "5" { 
                Instalar-ServicioFTP 
                Pause 
            }

            "6" { 
                Configurar-EntornoFTP 
                Pause 
            }

            "0" { break }
            
            default { 
                Write-Host "Opción no válida." -ForegroundColor Red 
                Pause 
            }
        }
    } while ($true)
}

# Verificación de Privilegios antes de lanzar el menú
if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Write-Host "ERROR: DEBES EJECUTAR ESTE SCRIPT COMO ADMINISTRADOR" -ForegroundColor Red
    Write-Host "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" -ForegroundColor Red
    Pause
} else {
    Mostrar-Menu
}