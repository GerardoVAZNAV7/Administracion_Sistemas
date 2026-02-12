# =========================================
# UTILIDADES IP
# =========================================

function Validar-IP {
    param([string]$ip)

    if (-not ($ip -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$')) { return $false }

    foreach ($o in $ip.Split('.')) {
        if ([int]$o -gt 255) { return $false }
    }

    if ($ip -in @("0.0.0.0","127.0.0.1","255.255.255.255")) { return $false }

    return $true
}

function Mascara-A-Prefix {
    param([string]$mask)
    $prefix = 0
    foreach ($o in $mask.Split('.')) {
        $prefix += ([Convert]::ToString([int]$o,2) -replace '0','').Length
    }
    return $prefix
}

# =========================================
# CONFIGURAR IP SERVIDOR (RED INTERNA)
# =========================================

function Configurar-IPServidor {
    param([string]$ip,[string]$mask)

    $adapter = Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue
    if (-not $adapter) {
        Write-Host "No se encontro interfaz Ethernet"
        return
    }

    $prefix = Mascara-A-Prefix $mask

    Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false

    New-NetIPAddress `
        -IPAddress $ip `
        -PrefixLength $prefix `
        -InterfaceIndex $adapter.InterfaceIndex

    Write-Host "Servidor configurado en red interna"
}

# =========================================
# DHCP
# =========================================

function DHCP-Instalado {
    (Get-WindowsFeature DHCP).Installed
}

function Instalar-DHCP {

    if (DHCP-Instalado) {
        Write-Host "DHCP ya instalado"
        return
    }

    Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    Add-DhcpServerInDC | Out-Null
    Write-Host "DHCP instalado correctamente"
}

function Limpiar-ScopesDHCP {
    Get-DhcpServerv4Scope -ErrorAction SilentlyContinue |
    Remove-DhcpServerv4Scope -Force -ErrorAction SilentlyContinue
}

function Forzar-InterfazDHCP {
    $bindings = Get-DhcpServerv4Binding
    foreach ($b in $bindings) {
        Set-DhcpServerv4Binding `
            -InterfaceAlias $b.InterfaceAlias `
            -BindingState ($b.InterfaceAlias -eq "Ethernet")
    }
    Restart-Service DHCPServer
}

# =========================================
# CONFIGURAR DHCP
# =========================================

function Configurar-DHCP {

    if (-not (DHCP-Instalado)) {
        Write-Host "DHCP no instalado"
        return
    }

    Limpiar-ScopesDHCP

    $scope = Read-Host "Nombre del ambito"

    do { $red = Read-Host "Red (ej: 192.168.100.0)" }
    until (Validar-IP $red)

    do { $mask = Read-Host "Mascara (ej: 255.255.255.0)" }
    until (Validar-IP $mask)

    do { $start = Read-Host "IP inicial" }
    until (Validar-IP $start)

    do { $end = Read-Host "IP final" }
    until (Validar-IP $end)

    Configurar-IPServidor $start $mask
    Forzar-InterfazDHCP

    $scopeObj = Add-DhcpServerv4Scope `
        -Name $scope `
        -StartRange $start `
        -EndRange $end `
        -SubnetMask $mask `
        -State Active

    Write-Host "Scope creado correctamente"
}

# =========================================
# MONITOREO AUTOMATICO
# =========================================

function Monitoreo-DHCP {

    if (-not (DHCP-Instalado)) {
        Write-Host "DHCP no instalado"
        return
    }

    Write-Host "CTRL + C para salir"

    while ($true) {
        Clear-Host

        Write-Host "=== SERVICIO DHCP ==="
        Get-Service DHCPServer
        Write-Host ""

        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

        if ($scopes) {
            foreach ($s in $scopes) {
                Write-Host "Ambito:" $s.Name
                Write-Host "ScopeId:" $s.ScopeId
                Get-DhcpServerv4Lease -ScopeId $s.ScopeId -ErrorAction SilentlyContinue
                Write-Host ""
            }
        }
        else {
            Write-Host "No hay ambitos configurados"
        }

        Start-Sleep 5
    }
}

# =========================================
# MENU
# =========================================

function Menu {
    do {
        Write-Host ""
        Write-Host "===== DHCP WINDOWS SERVER 2022 ====="
        Write-Host "1. Instalar DHCP"
        Write-Host "2. Configurar DHCP"
        Write-Host "3. Monitorear"
        Write-Host "4. Salir"

        $op = Read-Host "Seleccione opcion"

        if ($op -eq "1") { Instalar-DHCP }
        elseif ($op -eq "2") { Configurar-DHCP }
        elseif ($op -eq "3") { Monitoreo-DHCP }

    } while ($op -ne "4")
}

Menu
