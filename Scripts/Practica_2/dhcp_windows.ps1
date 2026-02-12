# =========================================
# UTILIDADES IP
# =========================================

function Convertir-IPaEntero {
    param([string]$ip)
    $o = $ip.Split('.')
    return ([uint32]$o[0] -shl 24) -bor
           ([uint32]$o[1] -shl 16) -bor
           ([uint32]$o[2] -shl 8)  -bor
           ([uint32]$o[3])
}

function Convertir-EnteroaIP {
    param([uint32]$num)
    return "$(($num -shr 24) -band 255).$((($num -shr 16) -band 255)).$((($num -shr 8) -band 255)).$($num -band 255)"
}

function Validar-IP {
    param([string]$ip)

    if (-not ($ip -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$')) { return $false }

    foreach ($o in $ip.Split('.')) {
        if ([int]$o -gt 255) { return $false }
    }

    if ($ip -in @("0.0.0.0","127.0.0.1","255.255.255.255")) { return $false }

    return $true
}

function Rango-Valido {
    param($start, $end)
    return (Convertir-IPaEntero $start) -lt (Convertir-IPaEntero $end)
}

# =========================================
# CALCULO RED Y MASCARA (ESTILO LINUX)
# =========================================

function Calcular-RedMascara {
    param($ip1, $ip2)

    $n1 = Convertir-IPaEntero $ip1
    $n2 = Convertir-IPaEntero $ip2

    $diff = $n1 -bxor $n2
    $bits = 32

    while ($diff -gt 0) {
        $diff = $diff -shr 1
        $bits--
    }

    $mask = ([uint32]0xFFFFFFFF -shl (32-$bits)) -band 0xFFFFFFFF
    $net = $n1 -band $mask

    $global:RED = Convertir-EnteroaIP $net
    $global:MASCARA = Convertir-EnteroaIP $mask
}

function Mascara-A-Prefix {
    param([string]$mask)
    $prefix = 0
    foreach ($o in $mask.Split('.')) {
        $bin = [Convert]::ToString([int]$o,2)
        $prefix += ($bin -replace '0','').Length
    }
    return $prefix
}

# =========================================
# CONFIGURAR IP SERVIDOR (ETHERNET INTERNA)
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

    Write-Host "Servidor configurado en Ethernet"
    Write-Host "IP:" $ip
    Write-Host "Mascara:" $mask
}

# =========================================
# INSTALACION DHCP
# =========================================

function DHCP-Instalado {
    (Get-WindowsFeature DHCP).Installed
}

function Instalar-DHCP {

    if (DHCP-Instalado) {
        do {
            $op = Read-Host "DHCP ya instalado. ¿Reinstalar? (y/n)"
        } until ($op -in @("y","n"))

        if ($op -eq "n") { return }

        Uninstall-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    }

    Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    Add-DhcpServerInDC | Out-Null

    Write-Host "DHCP instalado correctamente"
}

# =========================================
# CONFIGURACION DHCP
# =========================================

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
    Write-Host "DHCP escuchando solo en Ethernet"
}

function Configurar-DHCP {

    if (-not (DHCP-Instalado)) {
        Write-Host "ERROR: DHCP no instalado"
        return
    }

    Write-Host "=== CONFIGURACION DHCP ==="
    Limpiar-ScopesDHCP

    $scope = Read-Host "Nombre del ambito"

    do { $start = Read-Host "IP inicial" }
    until (Validar-IP $start)

    do {
        $end = Read-Host "IP final"
        if (-not (Validar-IP $end)) {
            Write-Host "IP invalida"
            $ok = $false
        }
        else { $ok = $true }
    } until ($ok)

    if (-not (Rango-Valido $start $end)) {
        Write-Host "La IP final debe ser mayor"
        return
    }

    Calcular-RedMascara $start $end

    Configurar-IPServidor $start $MASCARA
    Forzar-InterfazDHCP

    do {
        $lease = Read-Host "Tiempo de concesion (segundos)"
    } until ($lease -match '^[0-9]+$' -and [int]$lease -gt 0)

    $router = Read-Host "Gateway (opcional)"
    if (-not (Validar-IP $router)) { $router = $null }

    $dns = Read-Host "DNS (opcional)"
    if (-not (Validar-IP $dns)) { $dns = $null }

    $scopeObj = Add-DhcpServerv4Scope `
        -Name $scope `
        -StartRange $start `
        -EndRange $end `
        -SubnetMask $MASCARA `
        -LeaseDuration ([TimeSpan]::FromSeconds($lease)) `
        -State Active

    if ($router) {
        Set-DhcpServerv4OptionValue -ScopeId $scopeObj.ScopeId -Router $router
    }

    if ($dns) {
        Set-DhcpServerv4OptionValue -ScopeId $scopeObj.ScopeId -DnsServer $dns
    }

    Write-Host ""
    Write-Host "Servidor DHCP configurado correctamente"
    Write-Host "Red:" $RED
    Write-Host "Mascara:" $MASCARA
}

# =========================================
# MONITOREO
# =========================================

function Monitoreo-DHCP {

    if (-not (DHCP-Instalado)) {
        Write-Host "DHCP no instalado"
        return
    }

    Write-Host "CTRL + C para salir"

    while ($true) {
        Clear-Host
        Write-Host "Estado del servicio:"
        Get-Service DHCPServer
        Write-Host ""
        Get-DhcpServerv4Scope
        Write-Host ""
        Get-DhcpServerv4Lease -ErrorAction SilentlyContinue
        Start-Sleep 5
    }
}

# =========================================
# VERIFICACION
# =========================================

function Verificar-Instalacion {

    Write-Host "=== VERIFICACION DHCP ==="

    if (DHCP-Instalado) {
        Write-Host "Rol DHCP instalado"
    }
    else {
        Write-Host "Rol DHCP NO instalado"
        return
    }

    $serv = Get-Service DHCPServer -ErrorAction SilentlyContinue

    if ($serv.Status -eq "Running") {
        Write-Host "Servicio en ejecucion"
    }
    else {
        Write-Host "Servicio detenido"
    }
}

# =========================================
# MENU
# =========================================

function Menu {
    do {
        Write-Host ""
        Write-Host "===== DHCP WINDOWS SERVER 2022 ====="
        Write-Host "Estado:" (if (DHCP-Instalado) {"INSTALADO"} else {"NO INSTALADO"})
        Write-Host ""
        Write-Host "1. Instalar servicio DHCP"
        Write-Host "2. Configurar servicio DHCP"
        Write-Host "3. Monitorear servicio"
        Write-Host "4. Verificar instalacion"
        Write-Host "5. Salir"

        $op = Read-Host "Seleccione opcion"

        if ($op -eq "1") { Instalar-DHCP }
        elseif ($op -eq "2") { Configurar-DHCP }
        elseif ($op -eq "3") { Monitoreo-DHCP }
        elseif ($op -eq "4") { Verificar-Instalacion }

    } while ($op -ne "5")
}

Menu
