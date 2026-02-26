. "$PSScriptRoot\core_utils.ps1"
. "$PSScriptRoot\dns_functions.ps1"

function Menu-DNS {
    do {
        Clear-Host
        Write-Host ""
        Write-Host "++++++++++++++++++++++++++++++++++"
        Write-Host "         SISTEMA DNS - WINDOWS"
        Write-Host "++++++++++++++++++++++++++++++++++"
        Write-Host "1) Verificar instalacion DNS"
        Write-Host "2) Instalar DNS"
        Write-Host "3) Agregar dominio"
        Write-Host "4) Borrar dominio"
        Write-Host "5) Ver dominios"
        Write-Host "6) RECONFIGURAR / REPARAR RESOLUCION (Ethernet)"
        Write-Host "0) Volver al menu principal"
        Write-Host "__________________________________________"

        $OPT = Read-Host "Selecciona una opcion"

        switch ($OPT) {
            "1" { Opcion-Verificar }
            "2" { Opcion-Instalar }
            "3" { Opcion-Agregar }
            "4" { Opcion-Borrar }
            "5" { Opcion-Ver }
            "6" { Opcion-ReconfigurarDNS }
            "0" { return }
            default {
                Write-Color "Opcion invalida." Red
                Start-Sleep -Seconds 1
            }
        }
    } while ($OPT -ne "0")
}