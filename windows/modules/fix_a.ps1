# PASO 1: Obtener el hash de notepad.exe del cliente
# (ya debes tenerlo copiado en C:\Perfiles\notepad_cliente.exe por la opción 10)
# Si NO lo tienes aún, copia esto primero desde el cliente:
# copy C:\Windows\System32\notepad.exe \\SERVIDOR\Perfiles\notepad_cliente.exe

$hashNotepad = (Get-FileHash "C:\Perfiles\notepad_cliente.exe" -Algorithm SHA256).Hash
$sidNoCuates = (Get-ADGroup "Grupo_NoCuates").SID.Value

Write-Host "Hash obtenido: $hashNotepad"
Write-Host "SID NoCuates:  $sidNoCuates"

# PASO 2: Construir el XML con regla de HASH (no de path)
$xmlAppLocker = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">

    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20"
      Name="Permitir Program Files" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*"/></Conditions>
    </FilePathRule>

    <FilePathRule Id="a61c8b2c-a319-4cd0-9690-d2177cad7e51"
      Name="Permitir Windows" Description="" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*"/></Conditions>
    </FilePathRule>

    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2"
      Name="Permitir Administradores" Description="" UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions><FilePathCondition Path="*"/></Conditions>
    </FilePathRule>

    <FileHashRule Id="33333333-3333-3333-3333-333333333334"
      Name="Bloquear Notepad por Hash NoCuates" Description=""
      UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions>
        <FileHashCondition>
          <FileHash Type="SHA256" Data="0x$hashNotepad" SourceFileName="notepad.exe" SourceFileLength="0"/>
        </FileHashCondition>
      </Conditions>
    </FileHashRule>

  </RuleCollection>
</AppLockerPolicy>
"@

# PASO 3: Guardar y aplicar localmente
$xmlPath = "C:\Windows\Temp\applocker_fim.xml"
$xmlAppLocker | Set-Content $xmlPath -Encoding UTF8
Set-AppLockerPolicy -XmlPolicy $xmlPath
Write-Host "Política AppLocker aplicada localmente." -ForegroundColor Green

# PASO 4: Meter en la GPO existente
$domDN = (Get-ADDomain).DistinguishedName
$gpoName = "Politicas_AppLocker_FIM"

if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
    New-GPO -Name $gpoName | Out-Null
}
if (-not (Get-GPInheritance -Target $domDN | Select-Object -ExpandProperty GpoLinks | Where-Object { $_.DisplayName -eq $gpoName })) {
    New-GPLink -Name $gpoName -Target $domDN | Out-Null
}

$gpoId    = (Get-GPO -Name $gpoName).Id.ToString()
$ldapPath = "LDAP://CN={$gpoId},CN=Policies,CN=System,$domDN"
Set-AppLockerPolicy -XmlPolicy $xmlPath -Ldap $ldapPath
Write-Host "Política guardada en GPO." -ForegroundColor Green

# PASO 5: Asegurar que AppIDSvc arranque automático en clientes vía GPO
Set-GPRegistryValue -Name $gpoName `
    -Key "HKLM\SYSTEM\CurrentControlSet\Services\AppIDSvc" `
    -ValueName "Start" -Type DWord -Value 2 | Out-Null

# PASO 6: Servicio local
Set-Service -Name AppIDSvc -StartupType Automatic
Start-Service AppIDSvc -ErrorAction SilentlyContinue

gpupdate /force
Write-Host "Listo. Ahora ejecuta 'gpupdate /force' en el cliente Windows 10." -ForegroundColor Yellow