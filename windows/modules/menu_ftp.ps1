function Menu-FTP {
    # Importamos las funciones si no están cargadas
    if (!(Get-Command Initialize-FTPServer -ErrorAction SilentlyContinue)) {
        . .\ftp_functions.ps1
    }

    # Inicializar configuración base al entrar al módulo
    Clear-Host
    Write-Host "--- Inicializando módulo FTP ---" -ForegroundColor Gray
    Initialize-FTPServer

    $salirModulo = $false

    do {
        Write-Host "`n===============================================" -ForegroundColor Gray
        Write-Host "   MENU FTP SYSADMIN (Windows Server 2022)" -ForegroundColor Yellow
        Write-Host "===============================================" -ForegroundColor Gray
        Write-Host "1. Alta de usuarios (n)"
        Write-Host "2. Cambiar grupo de usuario"
        Write-Host "3. Regresar al Menú Principal"
        $opcion = Read-Host "Seleccione una opción"

        switch ($opcion) {
            "1" {
                $n = Read-Host "¿Cuántos usuarios desea crear?"
                for ($i=1; $i -le $n; $i++) {
                    Write-Host "`n--- Registro de Usuario $i ---" -ForegroundColor Cyan
                    $user = Read-Host "Nombre de usuario"
                    $pass = Read-Host "Contraseña"
                    $g_op = Read-Host "Grupo (1: reprobados, 2: recursadores)"
                    $group = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                    Add-FTPUser -Username $user -Password $pass -GroupName $group
                }
            }
            "2" {
                Write-Host "`n--- Modificación de Grupo ---" -ForegroundColor Cyan
                $user = Read-Host "Nombre del usuario a modificar"
                $g_op = Read-Host "Nuevo Grupo (1: reprobados, 2: recursadores)"
                $group = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                Edit-FTPUserGroup -Username $user -NewGroup $group
            }
            "3" { 
                Write-Host "Saliendo del módulo FTP..." -ForegroundColor Gray
                $salirModulo = $true 
            }
            Default { 
                Write-Host "Opción inválida." -ForegroundColor Red 
            }
        }
    } while (-not $salirModulo)
}