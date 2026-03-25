#Requires -RunAsAdministrator
# =============================================================================
# 02_crear_dominio.ps1
# PRACTICA 8 - Promover el servidor a Domain Controller
#
# FIX: NoRebootOnCompletion=$true para poder configurar DNS forwarders
#      ANTES del reinicio, asi el servidor conserva acceso a internet.
# =============================================================================

#Requires -Module ADDSDeployment

$ErrorActionPreference = "Stop"

function Write-Paso { param($n,$m) Write-Host "`n[$n] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m)    Write-Host "    [OK] $m" -ForegroundColor Green }
function Write-Info { param($m)    Write-Host "    [i]  $m" -ForegroundColor Yellow }

Write-Host "`n============================================" -ForegroundColor Magenta
Write-Host "   PRACTICA 8 - CREACION DEL DOMINIO        " -ForegroundColor Magenta
Write-Host "============================================`n" -ForegroundColor Magenta

$dominioNombre  = "practica.local"
$dominioNetbios = "PRACTICA"
$contrasenaSegura = ConvertTo-SecureString "DSRM@Practica8!" -AsPlainText -Force

Write-Paso "1" "Configuracion del nuevo dominio..."
Write-Info "Nombre FQDN: $dominioNombre"
Write-Info "NetBIOS: $dominioNetbios"

Write-Paso "2" "Instalando el nuevo bosque de Active Directory..."
Write-Info "Usando -NoRebootOnCompletion para configurar DNS antes de reiniciar."

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
    -NoRebootOnCompletion:$true `
    -SysvolPath "C:\Windows\SYSVOL" `
    -SafeModeAdministratorPassword $contrasenaSegura `
    -Force:$true

Write-Ok "Bosque AD instalado. Configurando DNS antes de reiniciar..."

# ── FIX INTERNET: Configurar DNS Forwarders ───────────────────────────────────
# RAZON DEL PROBLEMA:
# Al volverse DC, el servidor cambia su DNS propio a 127.0.0.1.
# Para nombres locales (practica.local): los resuelve el. BIEN.
# Para nombres de internet (google.com): NO sabe → sin internet.
#
# SOLUCION: Forwarders = servidores externos a los que preguntar
# cuando el servidor local no sabe la respuesta.

Write-Paso "3" "Configurando DNS Forwarders (fix acceso a internet)..."

try {
    Import-Module DnsServer -ErrorAction Stop
    Set-DnsServerForwarder -IPAddress "8.8.8.8","8.8.4.4","1.1.1.1" -PassThru | Out-Null
    Write-Ok "Forwarders configurados: 8.8.8.8 (Google) | 1.1.1.1 (Cloudflare)"
    Write-Ok "Internet funcionara correctamente despues del reinicio."
} catch {
    Write-Info "Configura forwarders manualmente despues del reinicio:"
    Write-Info "  dnsmgmt.msc → SERVIDOR-DC → Properties → Forwarders → 8.8.8.8, 1.1.1.1"
}

Write-Paso "4" "Reiniciando el servidor en 10 segundos..."
Write-Host "  Despues: inicia sesion como PRACTICA\Administrator" -ForegroundColor Yellow
Write-Host "  Luego ejecuta: .\03_usuarios_gpo.ps1" -ForegroundColor Yellow

Start-Sleep -Seconds 10
Restart-Computer -Force