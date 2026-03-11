. .\http_functions.ps1

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "ERROR: Ejecuta como ADMINISTRADOR." -ForegroundColor Red ; exit
}

while ($true) {
    Write-Host "`n=========================================" -ForegroundColor Magenta
    Write-Host "   Aprovisionamiento Directo HTTP        " -ForegroundColor Magenta
    Write-Host "=========================================" -ForegroundColor Magenta
    Write-Host "1. IIS (Nativo de Windows)"
    Write-Host "2. Apache (Standalone ZIP)"
    Write-Host "3. Nginx (Standalone ZIP)"
    Write-Host "4. Limpiar Entorno"
    Write-Host "5. Salir"
    $op = Read-Host "Opcion"
    
    if ($op -eq "5") { break }
    if ($op -eq "4") { Liberar-Entorno-Win; continue }

    $p = Read-Host "Ingrese el puerto (ej. 80, 81, 8080)"

    switch ($op) {
        "1" { Instalar-IIS -puerto $p }
        "2" { Instalar-Apache-Win -puerto $p }
        "3" { Instalar-Nginx-Win -puerto $p }
        Default { Write-Host "Opcion invalida" -ForegroundColor Yellow }
    }
}