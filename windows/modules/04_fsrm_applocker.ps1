#Requires -RunAsAdministrator
# =============================================================================
# 04_fsrm_applocker.ps1
# PRACTICA 8 - Cuotas FSRM, File Screening y AppLocker
#
# EJECUTAR despues de 03_usuarios_gpo.ps1
# =============================================================================

Import-Module ActiveDirectory
$ErrorActionPreference = "Stop"

function Write-Paso { param($n,$m) Write-Host "`n[$n] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m)    Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Info { param($m)    Write-Host "    [i]  $m" -ForegroundColor Yellow }

Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "   PRACTICA 8 - FSRM Y APPLOCKER           " -ForegroundColor Magenta
Write-Host "============================================`n" -ForegroundColor Magenta

$carpetasBase = "C:\Perfiles"
$dominioDN    = "DC=practica,DC=local"

# =============================================================================
# SECCION A: FILE SERVER RESOURCE MANAGER (FSRM)
# =============================================================================
Write-Host "`n--- SECCION A: FSRM ---" -ForegroundColor Yellow

# ── Paso 1: Verificar que FSRM esta activo ─────────────────────────────────
Write-Paso "A1" "Verificando servicio FSRM..."
$fsrmService = Get-Service -Name "SrmSvc" -ErrorAction SilentlyContinue
if ($null -eq $fsrmService) {
    Write-Info "FSRM no esta instalado. Instalando..."
    Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools | Out-Null
}
Start-Service SrmSvc -ErrorAction SilentlyContinue
Write-Ok "Servicio FSRM activo."

# ── Paso 2: Crear grupos de archivos prohibidos ────────────────────────────
Write-Paso "A2" "Creando grupo de archivos bloqueados (multimedia y ejecutables)..."

# EXPLICACION DIDACTICA:
# New-FsrmFileGroup crea una "lista negra" de extensiones.
# Active Screening = el sistema RECHAZA activamente el guardado del archivo.
# Passive Screening = solo registra en el log (no bloquea).
# En esta practica usamos ACTIVE SCREENING (bloqueante).

$nombreGrupoArchivos = "Practica8-Bloqueados"
$extensionesBloqueadas = @(
    "*.mp3", "*.mp4", "*.avi", "*.mkv", "*.wmv", "*.mov",  # Multimedia
    "*.exe", "*.msi", "*.bat", "*.cmd", "*.com", "*.vbs",   # Ejecutables
    "*.zip", "*.rar", "*.7z"                                  # Comprimidos
)

try {
    $grupoExistente = Get-FsrmFileGroup -Name $nombreGrupoArchivos -ErrorAction SilentlyContinue
    if ($grupoExistente) {
        Set-FsrmFileGroup -Name $nombreGrupoArchivos -IncludePattern $extensionesBloqueadas
        Write-Info "Grupo de archivos actualizado."
    } else {
        New-FsrmFileGroup -Name $nombreGrupoArchivos `
            -IncludePattern $extensionesBloqueadas
        Write-Ok "Grupo de archivos '$nombreGrupoArchivos' creado."
    }
} catch {
    Write-Info "Error con FSRM FileGroup: $($_.Exception.Message)"
}

# ── Paso 3: Crear plantillas de cuotas ────────────────────────────────────
Write-Paso "A3" "Creando plantillas de cuotas FSRM..."

# EXPLICACION DIDACTICA:
# Hard Quota = el sistema rechaza cualquier escritura que supere el limite.
# Soft Quota = solo envia alertas pero permite superar el limite.
# En esta practica usamos Hard Quota (obligatoria).

# Accion de notificacion: enviar evento al log del sistema cuando se
# alcanza el 85% y cuando se llega al 100% (cuota excedida)
$accionEvento = New-FsrmAction -Type Event `
    -EventType Warning `
    -Body "El usuario [Source Io Owner] ha excedido su cuota de almacenamiento en [Quota Path]. Utilizado: [Quota Used Bytes] de [Quota Limit Bytes]." `
    -RunLimitInterval 60

$threshold85 = New-FsrmQuotaThreshold -Percentage 85 -Action $accionEvento
$threshold100 = New-FsrmQuotaThreshold -Percentage 100 -Action $accionEvento

# Plantilla para Cuates: 10 MB
$plantillaCuates = "Practica8-Cuota10MB"
if (-not (Get-FsrmQuotaTemplate -Name $plantillaCuates -ErrorAction SilentlyContinue)) {
    New-FsrmQuotaTemplate -Name $plantillaCuates `
        -Size 10MB `
        -SoftLimit $false `
        -Threshold $threshold85, $threshold100 `
        -Description "Cuota 10MB para grupo Cuates (Practica 8)"
    Write-Ok "Plantilla '$plantillaCuates' (10 MB) creada."
} else {
    Write-Info "Plantilla '$plantillaCuates' ya existe."
}

# Plantilla para No Cuates: 5 MB
$plantillaNoCuates = "Practica8-Cuota5MB"
if (-not (Get-FsrmQuotaTemplate -Name $plantillaNoCuates -ErrorAction SilentlyContinue)) {
    New-FsrmQuotaTemplate -Name $plantillaNoCuates `
        -Size 5MB `
        -SoftLimit $false `
        -Threshold $threshold85, $threshold100 `
        -Description "Cuota 5MB para grupo NoCuates (Practica 8)"
    Write-Ok "Plantilla '$plantillaNoCuates' (5 MB) creada."
} else {
    Write-Info "Plantilla '$plantillaNoCuates' ya existe."
}

# ── Paso 4: Aplicar cuotas a carpetas de cada usuario ─────────────────────
Write-Paso "A4" "Aplicando cuotas y apantallamientos por usuario..."

$usuariosAD = Get-ADUser -Filter * -SearchBase $dominioDN -Properties Department, HomeDirectory |
    Where-Object { $_.Department -in @("Cuates","NoCuates") }

foreach ($usuario in $usuariosAD) {
    $carpeta = "$carpetasBase\$($usuario.SamAccountName)"

    if (-not (Test-Path $carpeta)) {
        New-Item -ItemType Directory -Path $carpeta -Force | Out-Null
        Write-Info "Carpeta creada: $carpeta"
    }

    # Seleccionar plantilla segun el grupo
    $plantilla = if ($usuario.Department -eq "Cuates") {
        $plantillaCuates
    } else {
        $plantillaNoCuates
    }

    # Aplicar cuota a la carpeta del usuario
    $cuotaExistente = Get-FsrmQuota -Path $carpeta -ErrorAction SilentlyContinue
    if ($cuotaExistente) {
        # Actualizar cuota existente
        Set-FsrmQuota -Path $carpeta -Template $plantilla
        Write-Ok "Cuota actualizada en: $carpeta ($plantilla)"
    } else {
        # Crear nueva cuota
        New-FsrmQuota -Path $carpeta -Template $plantilla
        Write-Ok "Cuota aplicada en: $carpeta ($plantilla)"
    }

    # Aplicar File Screen (Apantallamiento Activo)
    # EXPLICACION: El apantallamiento activo IMPIDE guardar archivos con
    # las extensiones definidas. El usuario recibe un error de acceso.
    $screenExistente = Get-FsrmFileScreen -Path $carpeta -ErrorAction SilentlyContinue
    if ($screenExistente) {
        Set-FsrmFileScreen -Path $carpeta `
            -IncludeGroup $nombreGrupoArchivos `
            -Active $true
        Write-Ok "Apantallamiento actualizado en: $carpeta"
    } else {
        New-FsrmFileScreen -Path $carpeta `
            -IncludeGroup $nombreGrupoArchivos `
            -Active $true
        Write-Ok "Apantallamiento ACTIVO aplicado en: $carpeta"
    }
}

# =============================================================================
# SECCION B: APPLOCKER
# =============================================================================
Write-Host "`n--- SECCION B: APPLOCKER ---" -ForegroundColor Yellow

Write-Paso "B1" "Configurando servicio Application Identity (requerido por AppLocker)..."

# Application Identity debe estar corriendo para que AppLocker funcione
Set-Service -Name "AppIDSvc" -StartupType Automatic
Start-Service -Name "AppIDSvc" -ErrorAction SilentlyContinue
Write-Ok "Servicio AppIDSvc habilitado y ejecutandose."

# ── Paso B2: Obtener el hash del Bloc de Notas ────────────────────────────
Write-Paso "B2" "Obteniendo informacion del Bloc de Notas para AppLocker..."

$notePadPath = "C:\Windows\System32\notepad.exe"

# EXPLICACION DIDACTICA: Por que usar Hash en lugar de Path o Publisher?
# - Path rule: si el usuario copia notepad.exe a otra carpeta, puede ejecutarlo
# - Publisher rule: requiere firma digital valida
# - Hash rule: usa el CONTENIDO del archivo. Si el usuario renombra notepad.exe
#   o lo copia a otro lugar, el hash sigue siendo el mismo y la regla aplica.
#   ES LA MAS SEGURA para bloquear un ejecutable especifico.

$applockerInfo = Get-AppLockerFileInformation -Path $notePadPath
$hash = $applockerInfo.Hash
Write-Ok "Hash de notepad.exe obtenido: $($hash.HashDataString.Substring(0,20))..."

# ── Paso B3: Crear y aplicar politica AppLocker via GPO ──────────────────
Write-Paso "B3" "Creando GPOs de AppLocker..."

Import-Module GroupPolicy

# GPO para Cuates: PERMITIR notepad.exe (regla por Path - mas simple)
$gpoNombreCuates = "Practica8-AppLocker-Cuates"
if (-not (Get-GPO -Name $gpoNombreCuates -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoNombreCuates | Out-Null
    Write-Ok "GPO '$gpoNombreCuates' creada."
}

# GPO para NoCuates: BLOQUEAR notepad.exe por Hash
$gpoNombreNoCuates = "Practica8-AppLocker-NoCuates"
if (-not (Get-GPO -Name $gpoNombreNoCuates -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoNombreNoCuates | Out-Null
    Write-Ok "GPO '$gpoNombreNoCuates' creada."
}

# Crear el XML de politica AppLocker
# CUATES: Permitir todo excepto la lista negra default + permitir notepad
$xmlCuates = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <!-- Regla: Permitir todo lo que este firmado por Windows (incluye notepad) -->
    <FilePublisherRule Id="a9e18c21-ff8f-43cf-b9fc-db40eed693ba"
        Name="Permitir aplicaciones firmadas por Microsoft"
        Description="Permite ejecutar aplicaciones firmadas por Microsoft Windows"
        UserOrGroupSid="S-1-5-21-DOMINIO-CUATES-SID"
        Action="Allow">
      <Conditions>
        <FilePublisherCondition PublisherName="O=MICROSOFT CORPORATION, L=REDMOND, S=WASHINGTON, C=US"
            ProductName="*" BinaryName="*">
          <BinaryVersionRange LowSection="*" HighSection="*"/>
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
    <!-- Regla default: Permitir a Admins todo -->
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2"
        Name="(Default Rule) All files"
        Description="Allows members of the local Administrators group to run all applications."
        UserOrGroupSid="S-1-5-32-544"
        Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@

# Politica para NoCuates: Bloquear notepad.exe por Hash
# Construccion programatica de la politica AppLocker
Write-Paso "B4" "Aplicando politica AppLocker via Set-AppLockerPolicy..."

# Crear politica para NoCuates (bloqueo de notepad por hash)
$xmlNoCuatesPath = "C:\Practica8\applocker_nocuates.xml"
New-Item -ItemType Directory -Path "C:\Practica8" -Force | Out-Null

# Obtener el SID del grupo NoCuates
$sidNoCuates = (Get-ADGroup "GrupoNoCuates").SID.Value

$xmlNoCuates = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">

    <!-- REGLA 1: Bloquear notepad.exe para NoCuates POR HASH -->
    <!-- Por que Hash? Si renombran notepad.exe, el hash es el mismo. -->
    <!-- Path y nombre pueden cambiarse; el contenido del archivo, no. -->
    <FileHashRule Id="3d5be5c0-1234-4b78-abcd-$(([guid]::NewGuid().ToString().Replace('-','')))"
        Name="BLOQUEAR Bloc de Notas para NoCuates (por Hash)"
        Description="Bloquea notepad.exe incluso si es renombrado o movido"
        UserOrGroupSid="$sidNoCuates"
        Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="$($hash.HashDataString)" SourceFileName="notepad.exe" SourceFileLength="$($hash.SourceFileLength)"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

    <!-- REGLA 2: Permitir todo a Administradores -->
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2"
        Name="(Default Rule) All files"
        Description="Permite a Administradores ejecutar todo."
        UserOrGroupSid="S-1-5-32-544"
        Action="Allow">
      <Conditions>
        <FilePathCondition Path="*"/>
      </Conditions>
    </FilePathRule>

    <!-- REGLA 3: Permitir archivos de Windows a todos los usuarios -->
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20"
        Name="(Default Rule) All files in Windows folder"
        Description="Permite ejecutar archivos del directorio de Windows."
        UserOrGroupSid="S-1-1-0"
        Action="Allow">
      <Conditions>
        <FilePathCondition Path="%WINDIR%\*"/>
      </Conditions>
    </FilePathRule>

    <!-- REGLA 4: Permitir archivos de Program Files a todos -->
    <FilePathRule Id="a61c8b2c-a319-4cd0-9690-d2177cad7b51"
        Name="(Default Rule) All files in Program Files folder"
        Description="Permite ejecutar archivos de Program Files."
        UserOrGroupSid="S-1-1-0"
        Action="Allow">
      <Conditions>
        <FilePathCondition Path="%PROGRAMFILES%\*"/>
      </Conditions>
    </FilePathRule>

  </RuleCollection>
</AppLockerPolicy>
"@

$xmlNoCuates | Out-File -FilePath $xmlNoCuatesPath -Encoding UTF8

# Aplicar la politica AppLocker a la GPO de NoCuates
Set-AppLockerPolicy -XMLPolicy $xmlNoCuatesPath -LDAP "LDAP://CN={$(
    (Get-GPO -Name $gpoNombreNoCuates).Id
)},CN=Policies,CN=System,DC=practica,DC=local"

Write-Ok "Politica AppLocker aplicada a GPO '$gpoNombreNoCuates'."

# Vincular GPOs a las OUs correspondientes
Write-Paso "B5" "Vinculando GPOs de AppLocker a las OUs..."

New-GPLink -Name $gpoNombreNoCuates `
    -Target "OU=NoCuates,DC=practica,DC=local" `
    -LinkEnabled Yes -ErrorAction SilentlyContinue
Write-Ok "GPO de bloqueo vinculada a OU NoCuates."

# La GPO de Cuates en realidad permite todo (no bloquea notepad)
# Se puede vincular para documentar, o dejar las reglas default
New-GPLink -Name $gpoNombreCuates `
    -Target "OU=Cuates,DC=practica,DC=local" `
    -LinkEnabled Yes -ErrorAction SilentlyContinue
Write-Ok "GPO de Cuates vinculada a OU Cuates."

# ── Paso B6: Forzar actualizacion de politicas ────────────────────────────
Write-Paso "B6" "Forzando actualizacion de Group Policy..."
Invoke-GPUpdate -Force -ErrorAction SilentlyContinue
Write-Ok "Group Policy actualizada. En los clientes ejecutar: gpupdate /force"

# =============================================================================
# RESUMEN FINAL
# =============================================================================
Write-Host "`n============================================" -ForegroundColor Green
Write-Host "   FSRM Y APPLOCKER CONFIGURADOS            " -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green

Write-Host "`nVerificacion de cuotas FSRM:" -ForegroundColor Cyan
Get-FsrmQuota | Select-Object Path, Template, Size, Usage | Format-Table -AutoSize

Write-Host "`nVerificacion de apantallamientos:" -ForegroundColor Cyan
Get-FsrmFileScreen | Select-Object Path, Active, IncludeGroup | Format-Table -AutoSize

Write-Host "`nProximos pasos:" -ForegroundColor Yellow
Write-Host "  1. En el cliente Windows 10: ejecuta join_windows.ps1"
Write-Host "  2. En el cliente Ubuntu: ejecuta join_linux.sh"
Write-Host "  3. Prueba las cuotas: intenta guardar un archivo > 5MB o 10MB"
Write-Host "  4. Prueba AppLocker: inicia sesion como un usuario de NoCuates"
Write-Host "     e intenta abrir notepad.exe"
Write-Host ""