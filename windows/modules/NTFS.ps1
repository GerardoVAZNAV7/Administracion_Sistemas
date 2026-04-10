# 1. Cargar el CSV y definir ruta base
$usuarios = Import-Csv "C:\Users\Administrator\Administracion_Sistemas\windows\modules\usuarios.csv"
$RutaRaiz = "C:\Perfiles"
$Dominio = (Get-ADDomain).NetBIOSName 

# 1. Configurar Carpetas Generales y Permisos de Grupo
$Departamentos = @("Cuates", "NoCuates")

foreach ($dep in $Departamentos) {
    $depLimpio = $dep -replace " ", "" 
    $nombreGrupoAD = "Grupo_" + $depLimpio 
    
    $rutaDep = Join-Path $RutaRaiz $depLimpio
    $rutaGen = Join-Path $rutaDep "General"
    
    if (-not (Test-Path $rutaGen)) { New-Item -Path $rutaGen -ItemType Directory -Force | Out-Null }

    $acl = Get-Acl $rutaDep
    $acl.SetAccessRuleProtection($true, $false)
    
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    # Validar si el grupo existe antes de asignar
    try {
        $groupRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Dominio\$nombreGrupoAD", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $acl.SetAccessRule($adminRule)
        $acl.SetAccessRule($groupRule)
        Set-Acl $rutaDep $acl
    } catch {
        Write-Host "Error: No se encontró el grupo $nombreGrupoAD en el AD" -ForegroundColor Red
    }
}

# 2. Procesar Usuarios del CSV
foreach ($u in $usuarios) {
    # AJUSTE AQUÍ: Coincidir con las cabeceras de tu CSV (Mayúsculas)
    $nombre = $u.Usuario
    $depto = $u.Departamento -replace " ", "" 
    
    if (-not $nombre) { continue } # Saltar si la línea está vacía

    $rutaPrivada = Join-Path $RutaRaiz "$depto\$nombre"

    if (-not (Test-Path $rutaPrivada)) { New-Item -Path $rutaPrivada -ItemType Directory -Force | Out-Null }

    $aclPriv = Get-Acl $rutaPrivada
    $aclPriv.SetAccessRuleProtection($true, $false)
    
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    try {
        # Intentar crear la regla del usuario
        $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Dominio\$nombre", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        
        $aclPriv.SetAccessRule($adminRule)
        $aclPriv.SetAccessRule($userRule)
        Set-Acl $rutaPrivada $aclPriv
        Write-Host "Carpeta y permisos listos para: $nombre en $depto" -ForegroundColor Green
    } catch {
        Write-Host "ERROR: El usuario '$nombre' no existe en el AD. Corre el script de creación primero." -ForegroundColor Red
    }
}