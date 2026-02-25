function Show-SSHMenu {
    do {
        Clear-Host
        Write-Host "================================="
        Write-Host " PRACTICA 4 - SSH WINDOWS SERVER"
        Write-Host "================================="
        Write-Host "1) Instalar OpenSSH Server"
        Write-Host "2) Configuracion automatica completa"
        Write-Host "3) Verificar servicio"
        Write-Host "4) Mostrar datos de conexion"
        Write-Host "0) Volver al menu principal"
        Write-Host ""

        $op = Read-Host "Seleccione opcion"

        switch ($op) {
            "1" { Install-SSHService }
            "2" { Configure-SSHService }
            "3" { Get-SSHStatus }
            "4" { Show-SSHConnectionInfo }
        }

        Pause
    } while ($op -ne "0")
}