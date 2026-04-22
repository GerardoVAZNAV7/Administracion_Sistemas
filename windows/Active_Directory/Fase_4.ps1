#Requires -RunAsAdministrator
Clear-Host
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " FASE 4: FSRM (CUOTAS) Y APPLOCKER             " -ForegroundColor Cyan
Write-Host " Windows Server 2022 - Sin entorno grafico      " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

$Dominio       = (Get-ADDomain).DistinguishedName
$NombreDominio = (Get-ADDomain).Name
$RutaBase      = "C:\Shares\Usuarios"

# ---------------------------------------------------------
# 1. INSTALACION DE FSRM
# ---------------------------------------------------------
Write-Host "`n> 1. Instalando FSRM..." -ForegroundColor Yellow
Install-WindowsFeature FS-Resource-Manager -IncludeManagementTools `
    -ErrorAction SilentlyContinue | Out-Null
Write-Host "  [+] FSRM instalado." -ForegroundColor Green

# ---------------------------------------------------------
# 2. APANTALLAMIENTO DE ARCHIVOS
#
# Se aplica SOLO sobre C:\Shares\Usuarios (unidad H:)
# NO se aplica sobre C:\Perfiles para no interferir
# con los archivos internos del perfil movil (.dat, .pol)
# ---------------------------------------------------------
Write-Host "`n> 2. Configurando bloqueo de archivos en H:..." -ForegroundColor Yellow

$NombreGrupo = "Bloqueo_Multimedia_Ejecutables"
if (-not (Get-FsrmFileGroup -Name $NombreGrupo -ErrorAction SilentlyContinue)) {
    New-FsrmFileGroup `
        -Name           $NombreGrupo `
        -IncludePattern @("*.mp3","*.mp4","*.exe","*.msi") | Out-Null
    Write-Host "  [+] Grupo de archivos bloqueados creado." -ForegroundColor Green
} else {
    Write-Host "  [-] Grupo ya existe." -ForegroundColor DarkGray
}

if (-not (Get-FsrmFileScreenTemplate -Name "Plantilla_Bloqueo_Total" -ErrorAction SilentlyContinue)) {
    New-FsrmFileScreenTemplate `
        -Name         "Plantilla_Bloqueo_Total" `
        -IncludeGroup $NombreGrupo `
        -Active:$true | Out-Null
    Write-Host "  [+] Plantilla de bloqueo creada." -ForegroundColor Green
} else {
    Write-Host "  [-] Plantilla ya existe." -ForegroundColor DarkGray
}

if (-not (Get-FsrmFileScreen -Path $RutaBase -ErrorAction SilentlyContinue)) {
    New-FsrmFileScreen `
        -Path     $RutaBase `
        -Template "Plantilla_Bloqueo_Total" `
        -Active:$true | Out-Null
    Write-Host "  [+] Bloqueo aplicado en: $RutaBase (H:)" -ForegroundColor Green
    Write-Host "  [!] C:\Perfiles NO bloqueado (protege perfil movil)" -ForegroundColor DarkGray
} else {
    Write-Host "  [-] Apantallamiento ya configurado." -ForegroundColor DarkGray
}

# ---------------------------------------------------------
# 3. CUOTAS ESTRICTAS
# ---------------------------------------------------------
Write-Host "`n> 3. Configurando cuotas FSRM..." -ForegroundColor Yellow

if (-not (Get-FsrmQuotaTemplate -Name "Cuota_5MB" -ErrorAction SilentlyContinue)) {
    New-FsrmQuotaTemplate -Name "Cuota_5MB"  -Size 5MB  | Out-Null
    New-FsrmQuotaTemplate -Name "Cuota_10MB" -Size 10MB | Out-Null
    Write-Host "  [+] Plantillas Cuota_5MB y Cuota_10MB creadas." -ForegroundColor Green
} else {
    Write-Host "  [-] Plantillas ya existen." -ForegroundColor DarkGray
}

foreach ($User in (Get-ADUser -Filter * -SearchBase "OU=cuates,$Dominio")) {
    $RutaUser = "$RutaBase\$($User.SamAccountName)"
    if ((Test-Path $RutaUser) -and
        -not (Get-FsrmQuota -Path $RutaUser -ErrorAction SilentlyContinue)) {
        New-FsrmQuota -Path $RutaUser -Template "Cuota_10MB" | Out-Null
        Write-Host "  [+] Cuota 10MB -> $($User.SamAccountName)" -ForegroundColor Green
    }
}

foreach ($User in (Get-ADUser -Filter * -SearchBase "OU=no_cuates,$Dominio")) {
    $RutaUser = "$RutaBase\$($User.SamAccountName)"
    if ((Test-Path $RutaUser) -and
        -not (Get-FsrmQuota -Path $RutaUser -ErrorAction SilentlyContinue)) {
        New-FsrmQuota -Path $RutaUser -Template "Cuota_5MB" | Out-Null
        Write-Host "  [+] Cuota 5MB -> $($User.SamAccountName)" -ForegroundColor Green
    }
}

# ---------------------------------------------------------
# 4. APPLOCKER VIA GPO CON REGLAS SALVAVIDAS
# ---------------------------------------------------------
Write-Host "`n> 4. Configurando AppLocker con reglas salvavidas y grupos..." -ForegroundColor Yellow

$GpoAppLocker = "GPO_AppLocker"

# Eliminar GPO anterior si existe para recrearla limpia
if (Get-GPO -Name $GpoAppLocker -ErrorAction SilentlyContinue) {
    Remove-GPO -Name $GpoAppLocker -ErrorAction SilentlyContinue
    Write-Host "  [!] GPO anterior eliminada para recrearla limpia." -ForegroundColor Yellow
}

$Gpo = New-GPO -Name $GpoAppLocker
New-GPLink -Name $GpoAppLocker -Target $Dominio | Out-Null

# Activar auto-arranque del servicio AppIDSvc en clientes
$AppIdKey = "HKLM\System\CurrentControlSet\Services\AppIDSvc"
Set-GPRegistryValue -Name $GpoAppLocker -Key $AppIdKey `
    -ValueName "Start" -Type DWord -Value 2 | Out-Null

$RutaLdap = "LDAP://CN={$($Gpo.Id)},CN=Policies,CN=System,$Dominio"

# ---- XML con reglas salvavidas ----
$xmlSalvavidas = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">

    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="(Salvavidas) Windows" Description="Permite ejecutables del sistema operativo" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
    </FilePathRule>

    <FilePathRule Id="a61c8b2c-a319-4cd0-9690-d2177cad7b51" Name="(Salvavidas) Program Files" Description="Permite aplicaciones instaladas x64" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
    </FilePathRule>

    <FilePathRule Id="b83c8b2c-a319-4cd0-9690-d2177cad7b52" Name="(Salvavidas) Program Files x86" Description="Permite aplicaciones instaladas x86" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES(X86)%\*" /></Conditions>
    </FilePathRule>

    <FilePathRule Id="c94d9c3d-b420-5de1-a786-e3288dbe8c63" Name="(Salvavidas) WindowsApps" Description="Permite apps modernas de Windows 10/11" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\WindowsApps\*" /></Conditions>
    </FilePathRule>

    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2" Name="(Salvavidas) Administradores" Description="Administradores pueden ejecutar todo" UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions><FilePathCondition Path="*" /></Conditions>
    </FilePathRule>

  </RuleCollection>
</AppLockerPolicy>
"@

$TempXmlSalvavidas = "$env:TEMP\Salvavidas.xml"
$xmlSalvavidas | Out-File $TempXmlSalvavidas -Encoding UTF8
Set-AppLockerPolicy -XmlPolicy $TempXmlSalvavidas -Ldap $RutaLdap
Write-Host "  [+] Reglas salvavidas inyectadas (incluye WindowsApps)." -ForegroundColor Green

# ---- Creación y Población de Grupos de Seguridad ----
Write-Host "  [>] Creando y poblando grupos de seguridad para AppLocker..." -ForegroundColor Yellow

$GruposAD = @("Grupo_Cuates", "Grupo_NoCuates")
foreach ($grp in $GruposAD) {
    if (-not (Get-ADGroup -Filter "Name -eq '$grp'" -ErrorAction SilentlyContinue)) {
        New-ADGroup -Name $grp -GroupCategory Security -GroupScope Global -Path "CN=Users,$Dominio" | Out-Null
    }
}

Get-ADUser -Filter * -SearchBase "OU=cuates,$Dominio" | ForEach-Object { 
    Add-ADGroupMember -Identity "Grupo_Cuates" -Members $_ -ErrorAction SilentlyContinue 
}
Get-ADUser -Filter * -SearchBase "OU=no_cuates,$Dominio" | ForEach-Object { 
    Add-ADGroupMember -Identity "Grupo_NoCuates" -Members $_ -ErrorAction SilentlyContinue 
}
Write-Host "  [+] Grupos de seguridad creados y sincronizados con las OUs." -ForegroundColor Green

# ---- Reglas Específicas de Notepad ----
$NotepadInfo = Get-AppLockerFileInformation -Path "C:\Windows\System32\notepad.exe"

# DENY para Grupo_NoCuates
$XmlHash = New-AppLockerPolicy -RuleType Hash `
    -User "$NombreDominio\Grupo_NoCuates" `
    -FileInformation $NotepadInfo -Xml

$XmlHash = $XmlHash -replace 'Action="Allow"', 'Action="Deny"'
$TempXmlHash = "$env:TEMP\NotepadHash.xml"
$XmlHash | Out-File $TempXmlHash -Encoding UTF8
Set-AppLockerPolicy -XmlPolicy $TempXmlHash -Ldap $RutaLdap -Merge
Write-Host "  [+] DENY Notepad clasico (notepad.exe) aplicado a Grupo_NoCuates." -ForegroundColor Green

# ALLOW para Grupo_Cuates
$XmlAllow = New-AppLockerPolicy -RuleType Hash `
    -User "$NombreDominio\Grupo_Cuates" `
    -FileInformation $NotepadInfo -Xml
$TempXmlAllow = "$env:TEMP\NotepadAllow.xml"
$XmlAllow | Out-File $TempXmlAllow -Encoding UTF8
Set-AppLockerPolicy -XmlPolicy $TempXmlAllow -Ldap $RutaLdap -Merge
Write-Host "  [+] ALLOW Notepad clasico aplicado a Grupo_Cuates." -ForegroundColor Green

Write-Host "`n=================================================" -ForegroundColor Cyan
Write-Host " FASE 4 COMPLETADA EXITOSAMENTE                 " -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " Resumen:" -ForegroundColor White
Write-Host "   FSRM: Bloqueo .mp3/.mp4/.exe/.msi en H:" -ForegroundColor DarkGray
Write-Host "   FSRM: Cuota 10MB (cuates) / 5MB (no_cuates) en H:" -ForegroundColor DarkGray
Write-Host "   AD: Grupos 'Grupo_Cuates' y 'Grupo_NoCuates' poblados." -ForegroundColor DarkGray
Write-Host "   AppLocker: Notepad.exe DENY para Grupo_NoCuates" -ForegroundColor DarkGray
Write-Host "   AppLocker: WindowsApps permitido (Bloc de Notas moderno OK)" -ForegroundColor DarkGray
Write-Host "=================================================" -ForegroundColor Cyan
