# parche_notepad_editor.ps1
# Ejecutar como Administrador en el Servidor

$Dominio = (Get-ADDomain).DistinguishedName
$GpoAppLocker = "GPO_AppLocker"

Write-Host "Obteniendo SID de Grupo_NoCuates..." -ForegroundColor Cyan
$SidNoCuates = (Get-ADGroup "Grupo_NoCuates").SID.Value

Write-Host "Generando regla de bloqueo por EDITOR (Firma Digital) para Notepad..." -ForegroundColor Cyan

# Esta regla lee el certificado interno. Bloquea cualquier cosa firmada por Microsoft
# cuyo nombre binario original sea NOTEPAD.EXE, sin importar su nombre de archivo actual.
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

Write-Host "Inyectando regla a la GPO existente..." -ForegroundColor Cyan
Set-AppLockerPolicy -XmlPolicy $TempXml -Ldap $RutaLdap -Merge

Write-Host "[+] ¡Listo! Regla de Editor aplicada exitosamente." -ForegroundColor Green
Write-Host "Nota: Esto cubre el Notepad clásico (.exe). El moderno (.appx) ya esta bloqueado por el parche anterior." -ForegroundColor DarkGray
