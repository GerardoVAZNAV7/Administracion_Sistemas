Clear-Host
Write-Host "================================================="
Write-Host "   CREACION MASIVA DE USUARIOS Y DIRECTORIOS     "
Write-Host "================================================="

# 1. Preparar la carpeta compartida raiz para los usuarios (Vital para FSRM)
$RutaBase = "C:\Shares\Usuarios"
$NombreServidor = $env:COMPUTERNAME

Write-Host "1. Creando y compartiendo el directorio raiz en $RutaBase..."
if (-not (Test-Path $RutaBase)) {
    New-Item -Path $RutaBase -ItemType Directory -Force | Out-Null
}
# Compartir la carpeta en red con permisos totales (luego NTFS controla el acceso real)
New-SmbShare -Name "Usuarios" -Path $RutaBase -FullAccess "Everyone" -ErrorAction SilentlyContinue | Out-Null


# 2. Obtener el Dominio actual (ej. DC=practica,DC=local)
$Dominio = (Get-ADDomain).DistinguishedName
$NombreDominio = (Get-ADDomain).Name

# 3. Importar el archivo CSV
$RutaCSV = "C:\usuarios.csv"
if (-not (Test-Path $RutaCSV)) {
    Write-Host "[!] ERROR: No se encontro el archivo $RutaCSV." -ForegroundColor Red
    exit
}
$UsuariosCSV = Import-Csv -Path $RutaCSV

Write-Host "`n2. Procesando el archivo CSV..."

# 4. Iterar sobre cada linea del CSV
foreach ($Fila in $UsuariosCSV) {
    
    $UO_Nombre = $Fila.departamento
    $UO_Ruta = "OU=$UO_Nombre,$Dominio"

    # --- A. Verificar y crear la UO si no existe ---
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq '$UO_Nombre'" -ErrorAction SilentlyContinue)) {
        Write-Host "   -> Creando nueva Unidad Organizativa: $UO_Nombre"
        New-ADOrganizationalUnit -Name $UO_Nombre -Path $Dominio
    }

    # --- B. Crear el usuario en AD ---
    $PassSegura = ConvertTo-SecureString $Fila.contrasena -AsPlainText -Force
    $RutaCarpetaRed = "\\$NombreServidor\Usuarios\$($Fila.usuario)"
    
    Write-Host "   -> Creando usuario: $($Fila.usuario) en la UO $UO_Nombre"
    
    $ParametrosUsuario = @{
        Name                  = $Fila.nombre
        SamAccountName        = $Fila.usuario
        UserPrincipalName     = "$($Fila.usuario)@$NombreDominio"
        AccountPassword       = $PassSegura
        Path                  = $UO_Ruta
        Enabled               = $true
        PasswordNeverExpires  = $true
        HomeDrive             = "H:"
        HomeDirectory         = $RutaCarpetaRed
    }
    
    # Se crea el usuario (SilentlyContinue evita error si ya existe)
    New-ADUser @ParametrosUsuario -ErrorAction SilentlyContinue

    # --- C. Crear la carpeta fisica personal ---
    $RutaCarpetaFisica = "$RutaBase\$($Fila.usuario)"
    if (-not (Test-Path $RutaCarpetaFisica)) {
        New-Item -Path $RutaCarpetaFisica -ItemType Directory -Force | Out-Null
    }
}

Write-Host "`n================================================="
Write-Host " PROCESO COMPLETADO EXITOSAMENTE "
Write-Host "================================================="
Write-Host "Verifica abriendo PowerShell y ejecutando: Get-ADUser -Filter *"