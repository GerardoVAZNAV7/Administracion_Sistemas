. .\ftp_functions.ps1

Clear-Host
Initialize-FTPServer

do {
    Write-Host "`n--- MENU FTP SYSADMIN (Windows Server 2022) ---" -ForegroundColor Yellow
    Write-Host "1. Alta de usuarios (n)"
    Write-Host "2. Cambiar grupo de usuario"
    Write-Host "3. Salir"
    $opcion = Read-Host "Seleccione una opción"

    switch ($opcion) {
        "1" {
            $n = Read-Host "¿Cuántos usuarios desea crear?"
            for ($i=1; $i -le $n; $i++) {
                $user = Read-Host "Nombre de usuario $i"
                $pass = Read-Host "Contraseña"
                $g_op = Read-Host "Grupo (1: reprobados, 2: recursadores)"
                $group = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                Add-FTPUser -Username $user -Password $pass -GroupName $group
            }
        }
        "2" {
            $user = Read-Host "Nombre del usuario a modificar"
            $g_op = Read-Host "Nuevo Grupo (1: reprobados, 2: recursadores)"
            $group = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
            Edit-FTPUserGroup -Username $user -NewGroup $group
        }
        "3" { Write-Host "Saliendo..." ; break }
        Default { Write-Host "Opción inválida." -ForegroundColor Red }
    }
} while ($opcion -ne "3")