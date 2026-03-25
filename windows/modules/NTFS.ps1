# 1. Cargar el CSV y definir ruta base
$usuarios = Import-Csv "C:\Practica8\usuarios.csv"
$RutaRaiz = "C:\Perfiles"
$Dominio = (Get-ADDomain).NetBIOSName 

# 1. Configurar Carpetas Generales y Permisos de Grupo
$Departamentos = @("Cuates", "NoCuates")

foreach ($dep in $Departamentos) {
    # Quitamos el espacio para las rutas
    $depLimpio = $dep -replace " ", "" 
    # Agregamos el prefijo para que coincida con tu script ("Grupo_Cuates" / "Grupo_NoCuates")
    $nombreGrupoAD = "Grupo_" + $depLimpio 
    
    $rutaDep = Join-Path $RutaRaiz $depLimpio
    $rutaGen = Join-Path $rutaDep "General"
    
    if (-not (Test-Path $rutaGen)) { New-Item -Path $rutaGen -ItemType Directory -Force | Out-Null }

    $acl = Get-Acl $rutaDep
    $acl.SetAccessRuleProtection($true, $false)
    
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    # Aplicamos la regla usando el nombre real de tu grupo
    $groupRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Dominio\$nombreGrupoAD", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    $acl.SetAccessRule($adminRule)
    $acl.SetAccessRule($groupRule)
    Set-Acl $rutaDep $acl
}

# 2. Procesar Usuarios del CSV
foreach ($u in $usuarios) {
    $nombre = $u.usuario
    $depLimpio = $u.departamento -replace " ", "" 
    $rutaPrivada = Join-Path $RutaRaiz "$depLimpio\$nombre"

    # Crear y aislar carpeta privada
    if (-not (Test-Path $rutaPrivada)) { New-Item -Path $rutaPrivada -ItemType Directory -Force | Out-Null }

    $aclPriv = Get-Acl $rutaPrivada
    $aclPriv.SetAccessRuleProtection($true, $false)
    
    $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule("Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $userRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Dominio\$nombre", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
    
    $aclPriv.SetAccessRule($adminRule)
    $aclPriv.SetAccessRule($userRule)
    Set-Acl $rutaPrivada $aclPriv
    
    Write-Host "Carpeta y permisos listos para: $nombre en $depLimpio" -ForegroundColor Green
}