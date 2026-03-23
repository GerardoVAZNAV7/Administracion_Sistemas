# =====================================================
# CORE UTILS - ADMINISTRACION DE SISTEMAS
# Funciones reutilizables para todas las practicas
# =====================================================



# =====================================================
# MENSAJES Y FORMATO
# =====================================================
$Global:DomainName    = "practica.local"    # Tu dominio
$Global:DomainNetBIOS = "PRACTICA"          # Nombre corto
$Global:DomainDN      = "DC=practica,DC=local"
$Global:SafePassword  = "Gerardo1234!!"     # Contraseña DSRM
$Global:ProfilesRoot  = "C:\Perfiles"       # Carpeta de perfiles
function Write-Color {
    param(
        [string]$Mensaje,
        [string]$Color = "White"
    )
    Write-Host $Mensaje -ForegroundColor $Color
}

function Write-Section {
    param([string]$Titulo)
    Write-Host ""
    Write-Host "====================================="
    Write-Host $Titulo
    Write-Host "====================================="
}



# =====================================================
# VALIDACIONES GENERALES
# =====================================================

function Test-IPv4 {
    param([string]$IP)

    if ([string]::IsNullOrWhiteSpace($IP)) { return $false }

    if ($IP -notmatch '^([0-9]{1,3}\.){3}[0-9]{1,3}$') {
        return $false
    }

    foreach ($o in $IP.Split('.')) {
        if ([int]$o -lt 0 -or [int]$o -gt 255) {
            return $false
        }
    }
    return $true
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}



# =====================================================
# UTILIDADES DE RED
# =====================================================

function Convert-IPToInt {
    param([string]$IP)

    $o = $IP.Split('.')

    return ([int]$o[0] -shl 24) -bor
           ([int]$o[1] -shl 16) -bor
           ([int]$o[2] -shl 8)  -bor
           ([int]$o[3])
}

function Convert-IntToIP {
    param([int]$Numero)

    return "$(($Numero -shr 24) -band 255)." +
           "$((($Numero -shr 16) -band 255))." +
           "$((($Numero -shr 8) -band 255))." +
           "$($Numero -band 255)"
}

function Get-NextIP {
    param([string]$IP)
    return Convert-IntToIP ((Convert-IPToInt $IP) + 1)
}

function Get-SubnetMask24 {
    return "255.255.255.0"
}



# =====================================================
# ADAPTADOR DE RED
# =====================================================

function Get-EthernetAdapter {
    Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue
}

function Set-StaticIP {
    param([string]$IP)

    $adapter = Get-EthernetAdapter

    if (-not $adapter) {
        Write-Color "No se encontro interfaz Ethernet" Red
        return $false
    }

    Get-NetIPAddress `
        -InterfaceIndex $adapter.InterfaceIndex `
        -AddressFamily IPv4 `
        -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false

    New-NetIPAddress `
        -IPAddress $IP `
        -PrefixLength 24 `
        -InterfaceIndex $adapter.InterfaceIndex

    return $true
}



# =====================================================
# SERVICIOS WINDOWS
# =====================================================

function Get-ServiceSafe {
    param([string]$Nombre)
    Get-Service -Name $Nombre -ErrorAction SilentlyContinue
}

function Start-ServiceSafe {
    param([string]$Nombre)
    Start-Service -Name $Nombre -ErrorAction SilentlyContinue
}

function Restart-ServiceSafe {
    param([string]$Nombre)
    Restart-Service -Name $Nombre -ErrorAction SilentlyContinue
}



# =====================================================
# ROLES Y FEATURES
# =====================================================

function Test-WindowsFeatureInstalled {
    param([string]$Feature)
    (Get-WindowsFeature $Feature).Installed
}

function Install-WindowsFeatureSafe {
    param([string]$Feature)
    Install-WindowsFeature $Feature -IncludeManagementTools | Out-Null
}



# =====================================================
# DIAGNOSTICO DEL SISTEMA
# (Se usa en practica 1)
# =====================================================

function Get-SystemHostname {
    hostname
}

function Get-SystemIPv4 {
    ipconfig | Select-String "IPv4"
}

function Get-DiskUsageC {
    Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" |
    Select-Object DeviceID,
    @{Name="SizeGB";Expression={[math]::Round($_.Size/1GB,2)}},
    @{Name="FreeGB";Expression={[math]::Round($_.FreeSpace/1GB,2)}}
}



# =====================================================
# FIREWALL (REQUERIDO PARA SSH PRACTICA 4)
# =====================================================

function Enable-FirewallPort {
    param(
        [int]$Port,
        [string]$Name
    )

    New-NetFirewallRule `
        -DisplayName $Name `
        -Direction Inbound `
        -Protocol TCP `
        -LocalPort $Port `
        -Action Allow `
        -ErrorAction SilentlyContinue
}



# =====================================================
# OPENSSH SERVER (WINDOWS)
# PRACTICA 4
# =====================================================

function Install-OpenSSHServer {
    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
}

function Start-OpenSSHServer {
    Start-Service sshd
    Set-Service -Name sshd -StartupType Automatic
}

function Enable-SSHFirewall {
    Enable-FirewallPort -Port 22 -Name "OpenSSH Server"
}