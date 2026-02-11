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

    $a = $ip1.Split('.')
    $b = $ip2.Split('.')

    $mask = @()
    for ($i=0; $i -lt 4; $i++) {
        if ($a[$i] -eq $b[$i]) {
            $mask += 255
        } else {
            $mask += 0
        }
    }

    $global:MASCARA = ($mask -join ".")
    $global:RED = "$($a[0]).$($a[1]).$($a[2]).0"
}


# ==============================
# CONFIGURAR IP DEL SERVIDOR
# ==============================

function Configurar-IPServidor {
    param(
        [string]$ip,
        [string]$mask
    )

    Write-Host "Configurando IP del servidor..."

    $adapter = Get-NetAdapter |
               Where-Object {$_.Status -eq "Up"} |
               Select-Object -First 1

    if (-not $adapter) {
        Write-Host "No se encontro interfaz de red activa"
        return
    }

   $prefix = 0
foreach ($o in $mask.Split('.')) {
    switch ([int]$o) {
        255 { $prefix += 8 }
        254 { $prefix += 7 }
        252 { $prefix += 6 }
        248 { $prefix += 5 }
        240 { $prefix += 4 }
        224 { $prefix += 3 }
        192 { $prefix += 2 }
        128 { $prefix += 1 }
        0   { }
    }
}


    # Elimina IPs anteriores
    Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Remove-NetIPAddress -Confirm:$false

    # Asigna IP nueva
    New-NetIPAddress `
        -IPAddress $ip `
        -PrefixLength $prefix `
        -InterfaceIndex $adapter.InterfaceIndex

    Write-Host "IP asignada:" $ip
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
   $serverIP = $start

   Configurar-IPServidor $serverIP $MASCARA


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
