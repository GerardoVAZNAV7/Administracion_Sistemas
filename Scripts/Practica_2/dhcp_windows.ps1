# ==============================
# UTILIDADES IP
# ==============================

function Convertir-IPaEntero {
    param([string]$ip)
    $o = $ip.Split('.')
    return ([uint32]$o[0] -shl 24) -bor
           ([uint32]$o[1] -shl 16) -bor
           ([uint32]$o[2] -shl 8)  -bor
           ([uint32]$o[3])
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

    $a = $ip1.Split('.') | ForEach-Object {[int]$_}
    $b = $ip2.Split('.') | ForEach-Object {[int]$_}

    $mask = @(0,0,0,0)
    $net  = @(0,0,0,0)

    for ($i=0; $i -lt 4; $i++) {

        $binA = [Convert]::ToString($a[$i],2).PadLeft(8,'0')
        $binB = [Convert]::ToString($b[$i],2).PadLeft(8,'0')

        $bits = ""
        for ($j=0; $j -lt 8; $j++) {
            if ($binA[$j] -eq $binB[$j]) {
                $bits += $binA[$j]
            } else {
                $bits += "0"
            }
        }

        $net[$i] = [Convert]::ToInt32($bits,2)

        $maskBits = ""
        for ($j=0; $j -lt 8; $j++) {
            if ($binA[$j] -eq $binB[$j]) {
                $maskBits += "1"
            } else {
                $maskBits += "0"
            }
        }

        $mask[$i] = [Convert]::ToInt32($maskBits,2)
    }

    $global:MASCARA = $mask -join "."
    $global:RED = $net -join "."
}

# ==============================
# CONFIGURAR IP DEL SERVIDOR
# ==============================

function Mascara-A-Prefix {
    param([string]$mask)

    $prefix = 0
    foreach ($o in $mask.Split('.')) {
        $bin = [Convert]::ToString([int]$o,2)
        $prefix += ($bin -replace '0','').Length
    }
    return $prefix
}


function Configurar-IPServidor {
    param(
        [string]$ip,
        [string]$mask
    )

    Write-Host "Configurando IP del servidor..."

$adapter = Get-NetAdapter -Name "Ethernet" -ErrorAction SilentlyContinue


    if (-not $adapter) {
        Write-Host "No se encontro interfaz de red activa"
        return
    }

    $prefix = Mascara-A-Prefix $mask

    Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false

    New-NetIPAddress `
        -IPAddress $ip `
        -PrefixLength $prefix `
        -InterfaceIndex $adapter.InterfaceIndex

    Write-Host "IP asignada:" $ip
    Write-Host "Mascara:" $mask
    Write-Host "Prefix:" $prefix
    Write-Host "Interfaz:" $adapter.Name
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

function Limpiar-ScopesDHCP {

    $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

    if ($scopes) {
        Write-Host "Eliminando configuracion DHCP anterior..."

        foreach ($s in $scopes) {
            Remove-DhcpServerv4Scope -ScopeId $s.ScopeId -Force
        }

        Write-Host "Scopes anteriores eliminados"
    }
}


function Forzar-InterfazDHCP {
    param(
        [string]$InterfaceObjetivo = "Ethernet"
    )

    Write-Host "Configurando interfaz de escucha DHCP..."

    $bindings = Get-DhcpServerv4Binding

    foreach ($b in $bindings) {
        if ($b.InterfaceAlias -eq $InterfaceObjetivo) {
            Set-DhcpServerv4Binding `
                -InterfaceAlias $b.InterfaceAlias `
                -BindingState $true
        }
        else {
            Set-DhcpServerv4Binding `
                -InterfaceAlias $b.InterfaceAlias `
                -BindingState $false
        }
    }

    Restart-Service DHCPServer
    Write-Host "DHCP ahora escucha solo en:" $InterfaceObjetivo
}


function Configurar-DHCP {



    Write-Host "=== CONFIGURACION DHCP ==="
    Limpiar-ScopesDHCP

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
   $serverIP = Convertir-EnteroaIP ((Convertir-IPaEntero $RED) + 1)


Configurar-IPServidor $serverIP $MASCARA

Forzar-InterfazDHCP "Ethernet"


    do {
        $lease = Read-Host "Tiempo de concesion en segundos"
    } until ($lease -match '^[0-9]+$' -and [int]$lease -gt 0)

    $router = Read-Host "Gateway (opcional)"
    if (-not (Validar-IP $router)) { $router = $null }

    $dns = Read-Host "DNS (opcional)"
    if (-not (Validar-IP $dns)) { $dns = $null }

    $scopeId = $RED

$scopeObj = Add-DhcpServerv4Scope `
    -Name $scope `
    -StartRange $start `
    -EndRange $end `
    -SubnetMask $MASCARA `
    -LeaseDuration ([TimeSpan]::FromSeconds($lease)) `
    -State Active

$scopeId = $scopeObj.ScopeId


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
# VERIFICAR INSTALACION
# ==============================

function Verificar-Instalacion {

    Write-Host "=== VERIFICACION DEL SERVICIO DHCP ==="
    Write-Host ""

    $feature = Get-WindowsFeature DHCP

    if ($feature.Installed) {
        Write-Host "Rol DHCP instalado"
    } else {
        Write-Host "Rol DHCP NO instalado"
        return
    }

    $serv = Get-Service DHCPServer -ErrorAction SilentlyContinue

    if (-not $serv) {
        Write-Host "Servicio DHCP no registrado"
        return
    }

    switch ($serv.Status) {
        "Running" { Write-Host "Servicio en ejecucion" }
        "Stopped" { Write-Host "Servicio instalado pero detenido" }
        default { Write-Host "Estado:" $serv.Status }
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
        Write-Host "4. Verificar instalacion"
        Write-Host "5. Salir"


        $op = Read-Host "Seleccione una opcion"

       switch ($op) {
    "1" { Instalar-DHCP }
    "2" { Configurar-DHCP }
    "3" { Monitoreo-DHCP }
    "4" { Verificar-Instalacion }
    "5" { Write-Host "Saliendo..." }
    default { Write-Host "Opcion invalida" }
     }

} while ($op -ne "5")


    
}

Menu
