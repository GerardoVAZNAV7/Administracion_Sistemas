function Menu-FTP {
    # Intentamos cargar las funciones. Si falla, el script sigue pero avisará.
    try { . "$PSScriptRoot\FTP_Functions.ps1" } catch { }

    do {
        Clear-Host
        Write-Host "======================================="
        Write-Host "   ADMINISTRADOR FTP - WINDOWS SERVER"
        Write-Host "======================================="
        Write-Host "1) Alta masiva de usuarios"
        Write-Host "2) Modificar grupo de usuario"
        Write-Host "3) LISTAR USUARIOS REGISTRADOS"
        Write-Host "4) Verificar estado/IP del servicio"
        Write-Host "5) RECONFIGURAR E INSTALAR SERVICIO"
        Write-Host "0) Salir"
        Write-Host "---------------------------------------"
        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {
            "1" {
                $n = Read-Host "Número de usuarios"
                for ($i=1; $i -le $n; $i++) {
                    $uname = Read-Host "Username"
                    $upass = Read-Host "Password"
                    $g_op = Read-Host "Grupo (1:reprobados, 2:recursadores)"
                    $ugroup = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                    Crear-UsuarioFTP $uname $upass $ugroup
                }
                Pause
            }
            "2" {
                $uname = Read-Host "Usuario"
                $g_op = Read-Host "Nuevo Grupo (1:reprobados, 2:recursadores)"
                $newGroup = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                Remove-LocalGroupMember -Group "reprobados", "recursadores" -Member $uname -ErrorAction SilentlyContinue
                Add-LocalGroupMember -Group $newGroup -Member $uname
                Write-Host "Grupo actualizado." -ForegroundColor Green
                Pause
            }
            "3" {
                if (Get-LocalGroup -Name "ftp-users" -ErrorAction SilentlyContinue) {
                    Get-LocalGroupMember -Group "ftp-users" | Select-Object Name, PrincipalSource
                } else {
                    Write-Host "[!] El sistema no ha sido inicializado (Falta grupo ftp-users)." -ForegroundColor Yellow
                }
                Pause
            }
            "4" {
                Write-Host "`n--- [ DIAGNÓSTICO DEL SERVICIO ] ---" -ForegroundColor Cyan
                # El bloque Try/Catch evita el error rojo de la imagen
                try {
                    $svc = Get-Service ftpsvc -ErrorAction Stop
                    Write-Host "Estado del Servicio: $($svc.Status)" -ForegroundColor Green
                } catch {
                    Write-Host "Estado del Servicio: [ NO INSTALADO ]" -ForegroundColor Red
                    Write-Host "Tip: Ejecuta la opción 5 para instalar los componentes." -ForegroundColor Gray
                }

                Write-Host "IPs Disponibles:"
                Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.IPAddress -notlike "127*" } | Select-Object InterfaceAlias, IPAddress
                Pause
            }
            "5" { 
                Write-Host "[+] Iniciando proceso de instalación e inicialización..." -ForegroundColor Cyan
                Inicializar-SistemaFTP 
                Pause
            }
            "0" { return }
        }
    } while ($true)
}

# Llamada a la función
Menu-FTP