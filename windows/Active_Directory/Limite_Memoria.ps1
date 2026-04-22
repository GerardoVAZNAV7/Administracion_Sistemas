# parche_gpo_limites_separados.ps1
# Ejecutar como Administrador en el Servidor

$Dominio = (Get-ADDomain).DistinguishedName

Write-Host "1. Limpiando el limite global anterior..." -ForegroundColor Cyan
# Le quitamos el limite a la GPO global para que no estorbe
Remove-GPRegistryValue -Name "GPO_PerfilesMoviles" `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "EnableProfileQuota" -ErrorAction SilentlyContinue | Out-Null
Remove-GPRegistryValue -Name "GPO_PerfilesMoviles" `
    -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" `
    -ValueName "MaxProfileSize" -ErrorAction SilentlyContinue | Out-Null

Write-Host "2. Creando GPO de 10MB para OU=cuates..." -ForegroundColor Cyan
$GpoCuates = "GPO_Cuota_Cuates_10MB"
if (-not (Get-GPO -Name $GpoCuates -ErrorAction SilentlyContinue)) { New-GPO -Name $GpoCuates | Out-Null }
New-GPLink -Name $GpoCuates -Target "OU=cuates,$Dominio" | Out-Null

Set-GPRegistryValue -Name $GpoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "EnableProfileQuota" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $GpoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "MaxProfileSize" -Type DWord -Value 10000 | Out-Null
Set-GPRegistryValue -Name $GpoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "ProfileQuotaMessage" -Type String -Value "Has excedido tus 10MB de perfil movil." | Out-Null


Write-Host "3. Creando GPO de 5MB para OU=no_cuates..." -ForegroundColor Cyan
$GpoNoCuates = "GPO_Cuota_NoCuates_5MB"
if (-not (Get-GPO -Name $GpoNoCuates -ErrorAction SilentlyContinue)) { New-GPO -Name $GpoNoCuates | Out-Null }
New-GPLink -Name $GpoNoCuates -Target "OU=no_cuates,$Dominio" | Out-Null

Set-GPRegistryValue -Name $GpoNoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "EnableProfileQuota" -Type DWord -Value 1 | Out-Null
Set-GPRegistryValue -Name $GpoNoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "MaxProfileSize" -Type DWord -Value 5000 | Out-Null
Set-GPRegistryValue -Name $GpoNoCuates -Key "HKCU\Software\Microsoft\Windows\CurrentVersion\Policies\System" -ValueName "ProfileQuotaMessage" -Type String -Value "Has excedido tus 5MB de perfil movil (No Cuates)." | Out-Null


Write-Host "[+] Listo. Ahora las OUs tienen sus limites independientes." -ForegroundColor Green
Write-Host "Recuerda ejecutar 'gpupdate /force' en las maquinas cliente." -ForegroundColor DarkGray
