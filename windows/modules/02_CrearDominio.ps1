#Requires -RunAsAdministrator
# =============================================================================
# 02_crear_dominio.ps1
# PRACTICA 8 - Promover el servidor a Domain Controller
#
# EJECUTAR DESPUES de 01_setup_servidor.ps1 (y reinicio si fue necesario)
# El servidor SE REINICIARA automaticamente al finalizar este script
# =============================================================================

#Requires -Module ADDSDeployment

$ErrorActionPreference = "Stop"

function Write-Paso { param($n,$m) Write-Host "`n[$n] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m)    Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Info { param($m)    Write-Host "    [i]  $m" -ForegroundColor Yellow }

Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "   PRACTICA 8 - CREACION DEL DOMINIO        " -ForegroundColor Magenta
Write-Host "============================================`n" -ForegroundColor Magenta

# ── Configuracion del dominio ─────────────────────────────────────────────────
$dominioNombre  = "practica.local"
$dominioNetbios = "PRACTICA"

# IMPORTANTE: Esta sera la contrasena del modo DSRM (recuperacion de AD)
# Guardala en un lugar seguro
$contrasenaSegura = ConvertTo-SecureString "DSRM@Practica8!" -AsPlainText -Force

Write-Paso "1" "Configuracion del nuevo dominio..."
Write-Info "Nombre FQDN: $dominioNombre"
Write-Info "NetBIOS: $dominioNetbios"
Write-Info "Nivel funcional: Windows Server 2016"

Write-Paso "2" "Instalando el nuevo bosque de Active Directory..."
Write-Info "El servidor se reiniciara automaticamente al terminar."
Write-Info "Espera aproximadamente 3-5 minutos..."

Import-Module ADDSDeployment

Install-ADDSForest `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "WinThreshold" `
    -DomainName $dominioNombre `
    -DomainNetbiosName $dominioNetbios `
    -ForestMode "WinThreshold" `
    -InstallDns:$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:$false `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword $contrasenaSegura `
    -Force:$true

# NOTA: El servidor se reiniciara aqui automaticamente.
# Despues del reinicio, inicia sesion con: PRACTICA\Administrator
# y ejecuta el script 03_usuarios_gpo.ps1
Write-Host "`nEl servidor se esta reiniciando..." -ForegroundColor Yellow