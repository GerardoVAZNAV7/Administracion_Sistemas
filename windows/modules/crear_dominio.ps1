Write-Host "=== INICIANDO CREACION DEL DOMINIO BAJA.COM ===" -ForegroundColor Yellow

# 1. Instalar el Rol de Active Directory
Write-Host "Instalando binarios de AD DS..." -ForegroundColor Cyan
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# 2. Configurar el nuevo Bosque (Forest)
# Nota: El servidor se reiniciará solo al terminar.
Write-Host "Promoviendo a Controlador de Dominio (baja.com)..." -ForegroundColor Cyan

$passwordSeguro = ConvertTo-SecureString "Gerardo1234!!" -AsPlainText -Force

Install-ADDSForest `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "WinThreshold" `
    -DomainName "baja.com" `
    -DomainNetbiosName "BAJA" `
    -ForestMode "WinThreshold" `
    -InstallDns:$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword $passwordSeguro `
    -Force:$true