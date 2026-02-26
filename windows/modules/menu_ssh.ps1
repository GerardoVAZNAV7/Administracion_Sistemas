# =====================================================
# MENU PRINCIPAL SSH - PRACTICA 4
# SOLO DEFINE FUNCION (NO EJECUTA NADA)
# =====================================================

. "$PSScriptRoot\ssh_functions.ps1"

function Menu-SSH {

    do {
        Clear-Host
        Write-Section "ADMINISTRACION SSH"

        Write-Host "1) Instalar y configurar SSH completo"
        Write-Host "2) Instalar servicio OpenSSH"
        Write-Host "3) Configurar servicio SSH"
        Write-Host "4) Configurar firewall SSH"
        Write-Host "5) Ver estado del servicio"
        Write-Host "0) Volver al menu principal"
        Write-Host ""

        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {
            "1" { Install-SSHFull }
            "2" { Install-SSHService }
            "3" { Configure-SSHService }
            "4" { Configure-SSHFirewall }
            "5" { Get-SSHStatus }
            "0" { break }
            default { Write-Color "Opcion invalida" Red }
        }

        if ($opcion -ne "0") {
            Pause
        }

    } while ($true)
}