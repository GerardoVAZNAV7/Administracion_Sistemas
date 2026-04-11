# 1. Exportar la política efectiva actual a XML
Get-AppLockerPolicy -Effective -Xml | Out-File "C:\applocker_export.xml"

# 2. Vincular la política AppLocker a la GPO existente
$gpoName = "Politicas_FIM_CierreForzado"
$xmlContent = Get-Content "C:\applocker_export.xml" -Raw

Set-GPRegistryValue -Name $gpoName `
    -Key "HKLM\Software\Policies\Microsoft\Windows\SrpV2\Exe" `
    -ValueName "EnforcementMode" `
    -Type DWord -Value 1

# 3. Forzar actualización
gpupdate /force