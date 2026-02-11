# ==============================
# UTILIDADES IP
# ==============================

function Convertir-IPaEntero {
    param([string]$ip)
    $oct = $ip.Split('.')
    return ([int]$oct[0] -shl 24) -bor
           ([int]$oct[1] -shl 16) -bor
           ([int]$oct[2] -shl 8)  -bor
           ([int]$oct[3])
}

function Convertir-EnteroaIP {
    param([int64]$num)
    return "$(($num -shr 24) -band 255).$((($num -shr 16) -band 255)).$((($num -shr 8) -band 255)).$($num -band 255)"
}

function Validar-IP {
    param([string]$ip)

    if (-not ($ip -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$')) { return $false }

    $oct = $ip.Split('.')
    foreach ($o in $oct) {
        if ([int]$o -gt 255) { return $false }
    }

    if ($ip -eq "0.0.0.0") { return $false }
    if ($ip -eq "127.0.0.1") { return $false }
    if ($ip -eq "255.255.255.255") { return $false }

    return $true
}

function Rango-Valido {
    param($start, $end)

    if (-not (Validar-IP $start)) { return $false }
    if (-not (Validar-IP $end)) { return $false }

    $s = Convertir-IPaEntero $start
    $e = Convertir-IPaEntero $end

    return ($s -lt $e)
}

# ==============================
# CALCULO DE RED Y MASCARA
# ==============================

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

    $mask = ([uint32]0xFFFFFFFF -shl (32-$bits))
    $net = $n1 -band $mask

    $global:RED = Convertir-EnteroaIP $net
    $global:MASCARA = Convertir-EnteroaIP $mask
}

# ==============================
# INSTALACION
# ==============================

function Instalar-DHCP {
    $feature = Get-WindowsFeature DHCP

    if ($feature.Installed) {
        do {
            $op = Read-Host "El servicio ya esta instalado. ¿Quieres reinstalarlo? (y/n)"
        } until ($op -eq "y" -or $op -eq "n")

        if ($op -eq "n") {
            Write-Host "Instalacion cancelada."
            return
        }

        Uninstall-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    }

    Write-Host "Instalando DHCP..."
    Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    Add-DhcpServerInDC | Out-Null
    Write-Host "Instalacion completada."
}

# ==============================
# CONFIGURACION
# ==============================

function Configurar-DHCP {

    Write-Host "=== CONFIGURACION DHCP ==="

    $scope = Read-Host "Nombre del ambito"

    do { $start = Read-Host "IP inicial" }
    until (Validar-IP $start)

    do { $end = Read-Host "IP final" }
    until (Validar-IP $end)

    if (-not (Rango-Valido $start $end)) {
        Write-Host "La IP inicial debe ser menor que la final"
        return
    }

    Calcular-RedMascara $start $end

    $serverIP = $start

    do {
        $lease = Read-Host "Tiempo de concesion en segundos"
    } until ($lease -match '^[0-9]+$' -and [int]$lease -gt 0)

    $router = Read-Host "Gateway (opcional)"
    if (-not (Validar-IP $router)) { $router = $null }

    $dns = Read-Host "DNS (opcional)"
    if (-not (Validar-IP $dns)) { $dns = $null }

    $scopeId = $RED

    Add-DhcpServerv4Scope `
        -Name $scope `
        -StartRange $start `
        -EndRange $end `
        -SubnetMask $MASCARA `
        -LeaseDuration ([TimeSpan]::FromSeconds($lease)) `
        -State Active

    if ($router) {
        Set-DhcpServerv4OptionValue -ScopeId $scopeId -Router $router
    }

    if ($dns) {
        Set-DhcpServerv4OptionValue -ScopeId $scopeId -DnsServer $dns
    }

    Write-Host ""
    Write-Host "Configuracion aplicada correctamente"
    Write-Host "Red: $RED"
    Write-Host "Mascara: $MASCARA"
}

# ==============================
# MONITOREO
# ==============================

function Monitoreo-DHCP {

    Write-Host "CTRL + C para salir"

    while ($true) {
        Clear-Host

        $serv = Get-Service DHCPServer
        Write-Host "Estado del servicio:" $serv.Status
        Write-Host ""

        $scopes = Get-DhcpServerv4Scope

        foreach ($s in $scopes) {
            Write-Host "Ambito:" $s.ScopeId
            Write-Host "Rango:" $s.StartRange "-" $s.EndRange
            Write-Host ""

            Get-DhcpServerv4Lease -ScopeId $s.ScopeId -ErrorAction SilentlyContinue |
            Select-Object IPAddress, HostName, AddressState, LeaseExpiryTime

            Write-Host ""
        }

        Start-Sleep 5
    }
}

# ==============================
# MENU
# ==============================

function Menu {
    do {
        Write-Host ""
        Write-Host "===== MENU DHCP WINDOWS SERVER ====="
        Write-Host "1. Instalar servicio DHCP"
        Write-Host "2. Configurar servicio DHCP"
        Write-Host "3. Monitorear servicio"
        Write-Host "4. Salir"

        $op = Read-Host "Seleccione una opcion"

        switch ($op) {
            "1" { Instalar-DHCP }
            "2" { Configurar-DHCP }
            "3" { Monitoreo-DHCP }
            "4" { Write-Host "Saliendo..." }
            default { Write-Host "Opcion invalida" }
        }

    } while ($op -ne "4")
}

Menu
