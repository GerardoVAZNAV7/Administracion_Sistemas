$sidNoCuates = (Get-ADGroup "Grupo_NoCuates").SID.Value

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

    <FilePathRule Id="11111111-1111-1111-1111-111111111111"
      Name="Bloquear Notepad System32 NoCuates" Description=""
      UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions><FilePathCondition Path="%WINDIR%\System32\notepad.exe"/></Conditions>
    </FilePathRule>

    <FilePathRule Id="22222222-2222-2222-2222-222222222222"
      Name="Bloquear Notepad SysWOW64 NoCuates" Description=""
      UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions><FilePathCondition Path="%WINDIR%\SysWOW64\notepad.exe"/></Conditions>
    </FilePathRule>

    <FilePathRule Id="55555555-5555-5555-5555-555555555555"
      Name="Bloquear Notepad raiz Windows NoCuates" Description=""
      UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions><FilePathCondition Path="%WINDIR%\notepad.exe"/></Conditions>
    </FilePathRule>

    <FilePathRule Id="66666666-6666-6666-6666-666666666666"
      Name="Bloquear cualquier notepad.exe NoCuates" Description=""
      UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions><FilePathCondition Path="*\notepad.exe"/></Conditions>
    </FilePathRule>

    <FilePathRule Id="77777777-7777-7777-7777-777777777777"
      Name="Bloquear hola.exe NoCuates" Description=""
      UserOrGroupSid="$sidNoCuates" Action="Deny">
      <Conditions><FilePathCondition Path="*\hola.exe"/></Conditions>
    </FilePathRule>

  </RuleCollection>
</AppLockerPolicy>
"@

$xmlPath = "C:\Windows\Temp\applocker_final.xml"
$xmlAppLocker | Set-Content $xmlPath -Encoding UTF8

Set-AppLockerPolicy -XmlPolicy $xmlPath

$domDN    = (Get-ADDomain).DistinguishedName
$gpoName  = "Politicas_AppLocker_FIM"
$gpoId    = (Get-GPO -Name $gpoName).Id.ToString()
$ldapPath = "LDAP://CN={$gpoId},CN=Policies,CN=System,$domDN"
Set-AppLockerPolicy -XmlPolicy $xmlPath -Ldap $ldapPath

gpupdate /force
Write-Host "Listo - notepad bloqueado por path en todas sus ubicaciones." -ForegroundColor Green