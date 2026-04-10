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
$rutaCSV = "C:\Users\Administrator\Administracion_Sistemas\windows\modules\usuarios.csv"
if (-not (Test-Path $rutaCSV)) {
    Write-Host "Error: No se encontro el archivo CSV en $rutaCSV. Crealo antes de continuar." -ForegroundColor Red
    exit
}

$dominioDN = (Get-ADDomain).DistinguishedName

# Forzar aplicacion de politicas al final
Instalar-Requisitos
Crear-EstructuraAD
Importar-UsuariosCSV -rutaCSV $rutaCSV
Configurar-GPO-Logoff
Configurar-FSRM
Configurar-AppLocker

gpupdate /force | Out-Null

Write-Host "=== PRACTICA 8 CONFIGURADA CON EXITO ===" -ForegroundColor Yellow