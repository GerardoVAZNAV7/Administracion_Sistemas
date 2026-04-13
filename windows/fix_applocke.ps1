# RESETEAR AppLocker completamente y poner política correcta
$sidNoCuates = (Get-ADGroup "Grupo_NoCuates").SID.Value
$hashNotepad = (Get-FileHash "C:\Perfiles\notepad_cliente.exe" -Algorithm SHA256).Hash

$xmlAppLocker = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="AuditOnly">

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

$xmlPath = "C:\Windows\Temp\applocker_fix2.xml"
$xmlAppLocker | Set-Content $xmlPath -Encoding UTF8

# Aplicar localmente en servidor
Set-AppLockerPolicy -XmlPolicy $xmlPath
Write-Host "Política aplicada localmente." -ForegroundColor Green

# Actualizar la GPO
$domDN    = (Get-ADDomain).DistinguishedName
$gpoName  = "Politicas_AppLocker_FIM"
$gpoId    = (Get-GPO -Name $gpoName).Id.ToString()
$ldapPath = "LDAP://CN={$gpoId},CN=Policies,CN=System,$domDN"
Set-AppLockerPolicy -XmlPolicy $xmlPath -Ldap $ldapPath
Write-Host "GPO actualizada." -ForegroundColor Green

gpupdate /force
Write-Host "Listo. Ahora gpupdate /force en el cliente." -ForegroundColor Yellow