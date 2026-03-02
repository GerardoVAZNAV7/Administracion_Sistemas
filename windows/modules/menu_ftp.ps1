function Menu-FTP {
    # Importamos las funciones si no están cargadas
. "$PSScriptRoot\FTP_Functions.ps1"


    do {
        Clear-Host
        Write-Host "======================================="
        Write-Host "   ADMINISTRADOR FTP - WINDOWS SERVER"
        Write-Host "======================================="
        Write-Host "1) Alta masiva de usuarios"
        Write-Host "2) Modificar grupo de usuario"
        Write-Host "3) LISTAR USUARIOS REGISTRADOS"
        Write-Host "4) Verificar estado del servicio"
        Write-Host "5) RECONFIGURAR SERVICIO (Reset)"
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
            }
            "2" {
                $uname = Read-Host "Usuario"
                $g_op = Read-Host "Nuevo Grupo (1:reprobados, 2:recursadores)"
                $newGroup = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                # Lógica simplificada de cambio de grupo
                Remove-LocalGroupMember -Group "reprobados", "recursadores" -Member $uname -ErrorAction SilentlyContinue
                Add-LocalGroupMember -Group $newGroup -Member $uname
                Write-Host "Grupo actualizado." -ForegroundColor Green
            }
            "3" {
                Get-LocalGroupMember -Group "ftp-users" | Select-Object Name, PrincipalSource
                Pause
            }
            "4" {
                Get-Service ftpsvc | Select-Object Name, Status, DisplayName
                Get-NetIPAddress -AddressFamily IPv4 | Where-Object InterfaceAlias -like "*Ethernet 3*" | Select-Object IPAddress
                Pause
            }
            "5" { Inicializar-SistemaFTP }
            "0" { return }
        }
    } while ($true)
}

Mostrar-Menu