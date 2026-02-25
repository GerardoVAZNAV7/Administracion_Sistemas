# =====================================================
# MENU PRINCIPAL SSH - PRACTICA 4
# =====================================================

. .\ssh_functions.ps1

do {
    Clear-Host
    Write-Section "ADMINISTRACION SSH"

    Write-Host "1) Instalar y configurar SSH completo"
    Write-Host "2) Instalar servicio OpenSSH"
    Write-Host "3) Configurar servicio SSH"
    Write-Host "4) Configurar firewall SSH"
    Write-Host "5) Ver estado del servicio"
    Write-Host "0) Salir"
    Write-Host ""

    $opcion = Read-Host "Seleccione una opcion"

    switch ($opcion) {
        "1" { Install-SSHFull }
        "2" { Install-SSHService }
        "3" { Configure-SSHService }
        "4" { Configure-SSHFirewall }
        "5" { Get-SSHStatus }
    }

    if ($opcion -ne "0") {
        Pause
    }

} while ($opcion -ne "0")