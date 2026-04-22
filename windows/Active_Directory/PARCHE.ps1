#Requires -RunAsAdministrator
Clear-Host
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " PARCHE UNIFICADO: HORARIOS, CUOTAS Y APPLOCKER  " -ForegroundColor Cyan
Write-Host "=================================================" -ForegroundColor Cyan

# Variable global para todo el script
$Dominio = (Get-ADDomain).DistinguishedName
Write-Host "[*] Dominio detectado: $Dominio`n" -ForegroundColor DarkGray

# =========================================================
# PARTE 1: REPARACION DE HORARIOS (LOGON HOURS)
# =========================================================
Write-Host ">> INICIANDO PARTE 1: Reparacion de Horarios..." -ForegroundColor Yellow

function Convertir-HorarioABytes {
    param([int]$HoraInicioLocal, [int]$HoraFinLocal)
    [byte[]]$horasArray = New-Object byte[] 21
    
    # Usamos Get-TimeZone para evitar el cache de PowerShell
    $OffsetUTC = (Get-TimeZone).BaseUtcOffset.Hours
    $InicioUTC = ($HoraInicioLocal - $OffsetUTC + 24) % 24
    $FinUTC    = ($HoraFinLocal    - $OffsetUTC + 24) % 24
    
    for ($dia = 0; $dia -lt 7; $dia++) {
        for ($hora = 0; $hora -lt 24; $hora++) {
            $dentro = $false
            if ($InicioUTC -lt $FinUTC) {
                if ($hora -ge $InicioUTC -and $hora -lt $FinUTC) { $dentro = $true }
            } else {
                if ($hora -ge $InicioUTC -or $hora -lt $FinUTC) { $dentro = $true }
            }
            if ($dentro) {
                $byteIndex = ($dia * 3) + [math]::Floor($hora / 8)
                $bitIndex  = $hora % 8
                $horasArray[$byteIndex] = $horasArray[$byteIndex] -bor (1 -shl $bitIndex)
            }
        }
    }
    return $horasArray
}

Write-Host "   [*] Aplicando horario a CUATES (08:00 - 15:00)..." -ForegroundColor Cyan
$HorarioCuates = Convertir-HorarioABytes -HoraInicioLocal 8 -HoraFinLocal 15
Get-ADUser -Filter * -SearchBase "OU=cuates,$Dominio" -ErrorAction SilentlyContinue | ForEach-Object {
    Set-ADUser -Identity $_ -Clear logonHours
    Set-ADUser -Identity $_ -Replace @{logonHours = $HorarioCuates}
}

Write-Host "   [*] Aplicando horario a NO CUATES (15:00 - 02:00)..." -ForegroundColor Cyan
$HorarioNoCuates = Convertir-HorarioABytes -HoraInicioLocal 15 -HoraFinLocal 2
Get-ADUser -Filter * -SearchBase "OU=no_cuates,$Dominio" -ErrorAction SilentlyContinue | ForEach-Object {
    Set-ADUser -Identity $_ -Clear logonHours
    Set-ADUser -Identity $_ -Replace @{logonHours = $HorarioNoCuates}
}
Write-Host "  [+] Horarios calculados y sincronizados.`n" -ForegroundColor Green


# =========================================================
# PARTE 2: LIMITES DE MEMORIA EN PERFILES MOVILES (GPOs)
# =========================================================
Write-Host ">> INICIANDO PARTE 2: Limites de Memoria por GPO..." -ForegroundColor Yellow

Write-Host "   [*] Limpiando el limite global anterior..." -ForegroundColor Cyan
Remove-GPRegistryValue -Name "GPO_PerfilesMoviles" -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "EnableProfileQuota" -ErrorAction SilentlyContinue | Out-Null
Remove-GPRegistryValue -Name "GPO_PerfilesMoviles" -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "MaxProfileSize" -ErrorAction SilentlyContinue | Out-Null

Write-Host "   [*] Creando GPO de 10MB para OU=cuates..." -ForegroundColor Cyan
$GpoCuates = "GPO_Cuota_Cuates_10MB"
if (-not (Get-GPO -Name $GpoCuates -ErrorAction SilentlyContinue)) { New-GPO -Name $GpoCuates | Out-Null }
New-GPLink -Name $GpoCuates -Target "OU=cuates,$Dominio" | Out-Null
Set-GPRegistryValue -Name $GpoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "EnableProfileQuota" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $GpoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "MaxProfileSize" -Type DWord -Value 10000 | Out-Null
Set-GPRegistryValue -Name $GpoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "ProfileQuotaMessage" -Type String -Value "Has excedido tus 10MB de perfil movil." | Out-Null

Write-Host "   [*] Creando GPO de 5MB para OU=no_cuates..." -ForegroundColor Cyan
$GpoNoCuates = "GPO_Cuota_NoCuates_5MB"
if (-not (Get-GPO -Name $GpoNoCuates -ErrorAction SilentlyContinue)) { New-GPO -Name $GpoNoCuates | Out-Null }
New-GPLink -Name $GpoNoCuates -Target "OU=no_cuates,$Dominio" | Out-Null
Set-GPRegistryValue -Name $GpoNoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "EnableProfileQuota" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $GpoNoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "MaxProfileSize" -Type DWord -Value 5000 | Out-Null
Set-GPRegistryValue -Name $GpoNoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "ProfileQuotaMessage" -Type String -Value "Has excedido tus 5MB de perfil movil (No Cuates)." | Out-Null
Write-Host "  [+] Limites de memoria aplicados en OUs independientes.`n" -ForegroundColor Green


# =========================================================
# PARTE 3: APPLOCKER (BLOQUEO DE NOTEPAD POR EDITOR)
# =========================================================
Write-Host ">> INICIANDO PARTE 3: AppLocker Notepad (Firma Digital)..." -ForegroundColor Yellow

$GpoAppLocker = "GPO_AppLocker"
$SidNoCuates = (Get-ADGroup "Grupo_NoCuates").SID.Value

Write-Host "   [*] Inyectando regla de Firma Digital para Notepad..." -ForegroundColor Cyan
$xmlPublisherDeny = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePublisherRule Id="$([guid]::NewGuid().ToString())" Name="Bloqueo Absoluto Notepad (Firma/Editor)" Description="Bloquea el binario original sin importar renombre" UserOrGroupSid="$SidNoCuates" Action="Deny">
      <Conditions>
        <FilePublisherCondition PublisherName="O=MICROSOFT CORPORATION, L=REDMOND, S=WASHINGTON, C=US" ProductName="*" BinaryName="NOTEPAD.EXE">
          <BinaryVersionRange LowSection="0.0.0.0" HighSection="*" />
        </FilePublisherCondition>
      </Conditions>
    </FilePublisherRule>
  </RuleCollection>
</AppLockerPolicy>
"@

$TempXml = "$env:TEMP\NotepadPublisherDeny.xml"
$xmlPublisherDeny | Out-File $TempXml -Encoding UTF8

$RutaLdap = "LDAP://CN={$( (Get-GPO $GpoAppLocker).Id )},CN=Policies,CN=System,$Dominio"
Set-AppLockerPolicy -XmlPolicy $TempXml -Ldap $RutaLdap -Merge | Out-Null

Write-Host "  [+] Regla de Editor de AppLocker fusionada exitosamente.`n" -ForegroundColor Green

Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " PARCHE UNIFICADO COMPLETADO CON EXITO           " -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Cyan
Write-Host " Recuerda ejecutar 'gpupdate /force' en las maquinas cliente." -ForegroundColor White
