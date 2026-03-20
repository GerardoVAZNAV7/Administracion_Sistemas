# Archivo: mainWindows.ps1

. .\funciones_SSL.ps1

function Menu-Principal {
    do {
        Write-Host "=========================================" -ForegroundColor Yellow
        Write-Host " ORQUESTADOR DE SERVICIOS WINDOWS" -ForegroundColor Yellow
        Write-Host "=========================================" -ForegroundColor Yellow
        Write-Host "1) Instalar IIS Web"
        Write-Host "2) Instalar IIS FTP"
        Write-Host "3) Instalar Apache (Descarga Web/FTP)"
        Write-Host "4) Instalar Nginx (Descarga Web/FTP)"
        Write-Host "5) Salir y mostrar resumen final"
        $opc = Read-Host "Selecciona una opcion"

        switch ($opc) {
            "1" { Instalar-IIS-Web }
            "2" { Instalar-IIS-FTP }
            "3" { Instalar-Apache }
            "4" { Instalar-Nginx }
            "5" {
                Write-Host "=========================================" -ForegroundColor Green
                Write-Host " RESUMEN DE INSTALACIONES (WINDOWS)" -ForegroundColor Green
                Write-Host "=========================================" -ForegroundColor Green
                foreach ($linea in $global:resumenInstalaciones) { Write-Host $linea }
                exit
            }
        }
    } while ($true)
}

Menu-Principal