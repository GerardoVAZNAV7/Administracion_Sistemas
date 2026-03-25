# Cargar archivo de funciones
$rutaFunciones = ".\funcionesAD.ps1"
if (Test-Path $rutaFunciones) {
    . $rutaFunciones
} else {
    Write-Host "Error: No se encontro el archivo $rutaFunciones" -ForegroundColor Red
    exit
}

Write-Host "=== INICIANDO CONFIGURACION PRACTICA 8 ===" -ForegroundColor Yellow

# Validacion del CSV
$rutaCSV = "C:\Practica8\usuarios.csv"
if (-not (Test-Path $rutaCSV)) {
    Write-Host "Error: No se encontro el archivo CSV en $rutaCSV. Crealo antes de continuar." -ForegroundColor Red
    exit
}

$dominioDN = (Get-ADDomain).DistinguishedName

# Ejecucion secuencial de las funciones
Instalar-Requisitos
Crear-EstructuraAD -dominioDN $dominioDN
Importar-UsuariosCSV -rutaCSV $rutaCSV -dominioDN $dominioDN
Configurar-GPO-Logoff -dominioDN $dominioDN
Configurar-FSRM
Configurar-AppLocker

# Forzar aplicacion de politicas al final
gpupdate /force | Out-Null

Write-Host "=== PRACTICA 8 CONFIGURADA CON EXITO ===" -ForegroundColor Yellow