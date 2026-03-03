. "$PSScriptRoot\ftp_functions.ps1"
function Menu-FTP {
    do {
        Clear-Host
        Write-Host "======================================="
        Write-Host "   ADMINISTRADOR FTP - WINDOWS SERVER 2022"
        Write-Host "======================================="
        Write-Host "1) Alta masiva de usuarios"
        Write-Host "2) Modificar grupo de usuario"
        Write-Host "3) LISTAR USUARIOS REGISTRADOS"
        Write-Host "4) Verificar estado/IP del servicio"
        Write-Host "5) INSTALAR ROL FTP (Silencioso)"
        Write-Host "6) CONFIGURAR ESTRUCTURAS Y PERMISOS"
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
                
                # Remover de ambos grupos académicos y agregar al nuevo
                Remove-LocalGroupMember -Group "reprobados", "recursadores" -Member $uname -ErrorAction SilentlyContinue
                Add-LocalGroupMember -Group $newGroup -Member $uname
                
                # Actualizar enlace simbólico
                $userHome = "C:\inetpub\ftproot\LocalUser\$uname"
                Remove-Item "$userHome\reprobados", "$userHome\recursadores" -ErrorAction SilentlyContinue
                cmd /c mklink /D "$userHome\$newGroup" "C:\inetpub\ftproot\LocalUser\$newGroup"
                
                Write-Host "Usuario movido a $newGroup con éxito." -ForegroundColor Green
                Pause
            }
            "3" {
                Get-LocalGroupMember -Group "ftp-users" | Select-Object Name, PrincipalSource
                Pause
            }
            "4" {
                try {
                    $svc = Get-Service ftpsvc -ErrorAction Stop
                    Write-Host "Estado: $($svc.Status)" -ForegroundColor Green
                } catch { Write-Host "Estado: NO INSTALADO" -ForegroundColor Red }
                
                Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -like "*Ethernet*" | Select-Object InterfaceAlias, IPAddress
                Pause
            }
            "5" { Instalar-ServicioFTP; Pause }
            "6" { Configurar-EntornoFTP; Pause }
            "0" { return }
        }
    } while ($true)
}

Menu-FTP