#Requires -RunAsAdministrator
# =============================================================================
# 03_usuarios_gpo.ps1
# PRACTICA 8 - Crear OUs, importar usuarios del CSV, configurar horarios
#
# EJECUTAR despues de que el DC haya reiniciado y el dominio este activo.
# Iniciar sesion como: PRACTICA\Administrator
# =============================================================================

Import-Module ActiveDirectory
$ErrorActionPreference = "Stop"

function Write-Paso { param($n,$m) Write-Host "`n[$n] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m)    Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Info { param($m)    Write-Host "    [i]  $m" -ForegroundColor Yellow }
function Write-Err  { param($m)    Write-Host "    [ERR] $m" -ForegroundColor Red }

Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "   PRACTICA 8 - USUARIOS, OUs Y GPOs       " -ForegroundColor Magenta
Write-Host "============================================`n" -ForegroundColor Magenta

# ── Variables globales ────────────────────────────────────────────────────────
$dominioDN   = "DC=practica,DC=local"
$dominioFQDN = "practica.local"
$rutaCSV     = "C:\Practica8\usuarios.csv"     # Copia el CSV aqui antes de ejecutar
$carpetasBase = "C:\Perfiles"                   # Carpetas de perfil de usuarios

# ── Paso 1: Crear las Unidades Organizativas ──────────────────────────────────
Write-Paso "1" "Creando Unidades Organizativas (UO)..."

$ous = @("Cuates", "NoCuates")
foreach ($ou in $ous) {
    $rutaOU = "OU=$ou,$dominioDN"
    if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$rutaOU'" `
              -ErrorAction SilentlyContinue)) {
        New-ADOrganizationalUnit -Name $ou -Path $dominioDN -ProtectedFromAccidentalDeletion $false
        Write-Ok "OU '$ou' creada."
    } else {
        Write-Info "OU '$ou' ya existe."
    }
}

# ── Paso 2: Crear grupos de seguridad ─────────────────────────────────────────
Write-Paso "2" "Creando grupos de seguridad..."

$grupos = @{
    "GrupoCuates"   = "OU=Cuates,$dominioDN"
    "GrupoNoCuates" = "OU=NoCuates,$dominioDN"
}

foreach ($grupo in $grupos.GetEnumerator()) {
    if (-not (Get-ADGroup -Filter "Name -eq '$($grupo.Key)'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $grupo.Key `
            -GroupScope Global `
            -GroupCategory Security `
            -Path $grupo.Value `
            -Description "Grupo de seguridad para $($grupo.Key)"
        Write-Ok "Grupo '$($grupo.Key)' creado."
    } else {
        Write-Info "Grupo '$($grupo.Key)' ya existe."
    }
}

# ── Paso 3: Crear carpeta base para perfiles ──────────────────────────────────
Write-Paso "3" "Preparando carpeta de perfiles: $carpetasBase..."
if (-not (Test-Path $carpetasBase)) {
    New-Item -ItemType Directory -Path $carpetasBase -Force | Out-Null
}

# Permisos NTFS en la carpeta base
$acl = Get-Acl $carpetasBase
$acl.SetAccessRuleProtection($true, $false)
$reglaAdmins = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$reglaUsers = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "PRACTICA\Domain Users", "ReadAndExecute,ListDirectory", "None", "None", "Allow")
$acl.AddAccessRule($reglaAdmins)
$acl.AddAccessRule($reglaUsers)
Set-Acl -Path $carpetasBase -AclObject $acl
Write-Ok "Permisos configurados en $carpetasBase"

# ── Paso 4: Importar usuarios desde CSV ───────────────────────────────────────
Write-Paso "4" "Importando usuarios desde CSV: $rutaCSV..."

if (-not (Test-Path $rutaCSV)) {
    Write-Err "No se encontro el archivo CSV en: $rutaCSV"
    Write-Info "Copia el archivo usuarios.csv a C:\Practica8\ y vuelve a ejecutar."
    exit 1
}

$usuarios = Import-Csv -Path $rutaCSV -Encoding UTF8

Write-Info "Encontrados $($usuarios.Count) usuarios en el CSV."

foreach ($user in $usuarios) {
    $ouDestino = if ($user.Departamento -eq "Cuates") {
        "OU=Cuates,$dominioDN"
    } else {
        "OU=NoCuates,$dominioDN"
    }

    $grupoDestino = if ($user.Departamento -eq "Cuates") {
        "GrupoCuates"
    } else {
        "GrupoNoCuates"
    }

    $contrasenaSegura = ConvertTo-SecureString $user.Contrasena -AsPlainText -Force

    # Crear carpeta personal del usuario
    $carpetaUsuario = "$carpetasBase\$($user.Usuario)"
    if (-not (Test-Path $carpetaUsuario)) {
        New-Item -ItemType Directory -Path $carpetaUsuario -Force | Out-Null

        # Dar control total solo al usuario sobre su propia carpeta
        $aclUser = Get-Acl $carpetaUsuario
        $aclUser.SetAccessRuleProtection($true, $false)
        $reglaAdmin2 = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "BUILTIN\Administrators", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
        $reglaUsuario = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "PRACTICA\$($user.Usuario)", "Modify", "ContainerInherit,ObjectInherit", "None", "Allow")
        $aclUser.AddAccessRule($reglaAdmin2)
        $aclUser.AddAccessRule($reglaUsuario)
        Set-Acl -Path $carpetaUsuario -AclObject $aclUser
    }

    # Crear el usuario en AD
    if (-not (Get-ADUser -Filter "SamAccountName -eq '$($user.Usuario)'" -ErrorAction SilentlyContinue)) {
        try {
            New-ADUser `
                -SamAccountName $user.Usuario `
                -UserPrincipalName "$($user.Usuario)@$dominioFQDN" `
                -Name "$($user.Nombre) $($user.Apellido)" `
                -GivenName $user.Nombre `
                -Surname $user.Apellido `
                -DisplayName "$($user.Nombre) $($user.Apellido)" `
                -AccountPassword $contrasenaSegura `
                -Enabled $true `
                -PasswordNeverExpires $true `
                -ChangePasswordAtLogon $false `
                -Path $ouDestino `
                -HomeDirectory $carpetaUsuario `
                -HomeDrive "H:" `
                -Department $user.Departamento

            # Agregar al grupo correspondiente
            Add-ADGroupMember -Identity $grupoDestino -Members $user.Usuario

            Write-Ok "Usuario '$($user.Usuario)' creado en OU '$($user.Departamento)' y agregado a '$grupoDestino'."
        } catch {
            Write-Err "Error creando usuario '$($user.Usuario)': $($_.Exception.Message)"
        }
    } else {
        Write-Info "Usuario '$($user.Usuario)' ya existe. Verificando grupo..."
        Add-ADGroupMember -Identity $grupoDestino -Members $user.Usuario -ErrorAction SilentlyContinue
    }
}

# ── Paso 5: Configurar horarios de inicio de sesion (LogonHours) ──────────────
Write-Paso "5" "Configurando horarios de inicio de sesion (LogonHours)..."
Write-Info "Concepto clave: LogonHours usa un arreglo de 21 bytes (168 bits = 168 horas)"
Write-Info "Cada bit representa 1 hora. 1=permitido, 0=bloqueado."
Write-Info "Las horas son en UTC. Si tu zona es UTC-6, suma 6 a las horas locales."

# EXPLICACION DIDACTICA DE LogonHours:
# -----------------------------------------------------------------------
# Windows representa los horarios de inicio de sesion como un arreglo de
# 21 bytes (168 bits). Cada bit = 1 hora de la semana.
# El orden es: Domingo 00:00, Domingo 01:00 ... Sabado 23:00
#
# CUATES: Lunes a Viernes, 8AM-3PM LOCAL (UTC-6 = 14:00-21:00 UTC)
# NO CUATES: Lunes a Viernes, 3PM-2AM LOCAL (UTC-6 = 21:00-08:00 UTC)
# -----------------------------------------------------------------------

function New-LogonHours {
    param([hashtable]$HorasPorDia)
    # HorasPorDia: @{ 0=Domingo, 1=Lunes, ..., 6=Sabado } = @(horas_permitidas)
    # Devuelve un arreglo de 21 bytes

    $bytes = New-Object byte[] 21
    foreach ($dia in $HorasPorDia.Keys) {
        foreach ($hora in $HorasPorDia[$dia]) {
            # Calcular la posicion del bit
            $bitIndex = $dia * 24 + $hora
            $byteIndex = [math]::Floor($bitIndex / 8)
            $bitOffset = $bitIndex % 8
            $bytes[$byteIndex] = $bytes[$byteIndex] -bor (1 -shl $bitOffset)
        }
    }
    return $bytes
}

# Horario CUATES: Lunes a Viernes 8AM-3PM (local UTC-6)
# En UTC: 14:00 a 21:00 (horas 14,15,16,17,18,19,20 de cada dia laboral)
$horasCuates = @{}
foreach ($dia in 1..5) {  # 1=Lunes, 2=Martes ... 5=Viernes
    $horasCuates[$dia] = 14..20  # 14:00 UTC a 20:59 UTC = 8AM a 2:59PM local
}
$logonCuates = New-LogonHours -HorasPorDia $horasCuates

# Horario NO CUATES: Lunes a Viernes 3PM-2AM (local UTC-6)
# En UTC: 21:00 a 08:00 del dia siguiente
$horasNoCuates = @{}
foreach ($dia in 0..6) {
    $horasNoCuates[$dia] = @()
}
foreach ($dia in 1..5) {  # Dias laborales
    $horasNoCuates[$dia] += 21..23  # 9PM-11:59PM UTC (3PM-5:59PM local)
}
foreach ($dia in 2..6) {  # Dia siguiente (martes a sabado)
    $horasNoCuates[$dia] += 0..7    # 0AM-7:59AM UTC (6PM-1:59AM local anterior)
}
$logonNoCuates = New-LogonHours -HorasPorDia $horasNoCuates

# Aplicar horarios a los usuarios segun su grupo
$usuariosAD = Get-ADUser -Filter * -SearchBase $dominioDN -Properties Department

foreach ($usuarioAD in $usuariosAD) {
    if ($usuarioAD.Department -eq "Cuates") {
        Set-ADUser -Identity $usuarioAD -LogonHours $logonCuates
        Write-Ok "Horario 8AM-3PM aplicado a: $($usuarioAD.SamAccountName)"
    } elseif ($usuarioAD.Department -eq "NoCuates") {
        Set-ADUser -Identity $usuarioAD -LogonHours $logonNoCuates
        Write-Ok "Horario 3PM-2AM aplicado a: $($usuarioAD.SamAccountName)"
    }
}

# ── Paso 6: Crear y vincular GPO para cerrar sesion al expirar horario ─────────
Write-Paso "6" "Creando GPO: Cierre de sesion al expirar horario..."

Import-Module GroupPolicy

$nombreGPO = "Practica8-LogonHours-Enforcement"

if (-not (Get-GPO -Name $nombreGPO -ErrorAction SilentlyContinue)) {
    $gpo = New-GPO -Name $nombreGPO -Comment "Fuerza cierre de sesion cuando expira el horario"
    Write-Ok "GPO '$nombreGPO' creada."
} else {
    $gpo = Get-GPO -Name $nombreGPO
    Write-Info "GPO '$nombreGPO' ya existe."
}

# Configurar la politica: "Network security: Force logoff when logon hours expire"
# Ruta: Computer Configuration > Windows Settings > Security Settings > Local Policies > Security Options
Set-GPRegistryValue -Name $nombreGPO `
    -Key "HKLM\SYSTEM\CurrentControlSet\Services\LanManServer\Parameters" `
    -ValueName "EnableForcedLogOff" `
    -Type DWord `
    -Value 1

Write-Ok "Politica 'Force logoff when logon hours expire' habilitada."

# Vincular la GPO al dominio entero (aplica a todos)
New-GPLink -Name $nombreGPO -Target $dominioDN -LinkEnabled Yes -ErrorAction SilentlyContinue
Write-Ok "GPO vinculada al dominio $dominioFQDN"

# ── Paso 7: GPO adicional - Seguridad de contrasenas ──────────────────────────
Write-Paso "7" "Configurando politica de contrasenas..."

# La politica de contrasenas default del dominio
Set-ADDefaultDomainPasswordPolicy -Identity $dominioFQDN `
    -MinPasswordLength 8 `
    -MaxPasswordAge (New-TimeSpan -Days 90) `
    -MinPasswordAge (New-TimeSpan -Days 1) `
    -PasswordHistoryCount 5 `
    -ComplexityEnabled $true `
    -ReversibleEncryptionEnabled $false

Write-Ok "Politica de contrasenas configurada."

# ── Resumen ───────────────────────────────────────────────────────────────────
Write-Host "`n============================================" -ForegroundColor Green
Write-Host "   USUARIOS Y GPOs CONFIGURADOS             " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

Write-Host "`nResumen de usuarios creados:" -ForegroundColor Cyan
Get-ADUser -Filter * -SearchBase $dominioDN -Properties Department |
    Select-Object Name, SamAccountName, Department |
    Format-Table -AutoSize

Write-Host "SIGUIENTE PASO:" -ForegroundColor Yellow
Write-Host "  Ejecuta: .\04_fsrm_applocker.ps1"
Write-Host ""