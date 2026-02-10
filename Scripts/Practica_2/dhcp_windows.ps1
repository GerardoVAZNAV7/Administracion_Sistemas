function Convertir-IPaEntero {
    param([string]$ip)
    $oct = $ip.Split('.')
    return ([int]$oct[0] -shl 24) -bor
           ([int]$oct[1] -shl 16) -bor
           ([int]$oct[2] -shl 8)  -bor
           ([int]$oct[3])
}

function IP-Logica {
    param([string]$ip)

    if (-not ($ip -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$')) { return $false }

    $oct = $ip.Split('.')
    foreach ($o in $oct) {
        if ([int]$o -gt 255) { return $false }
    }

    if ($ip -eq "0.0.0.0") { return $false }
    if ($ip -eq "8.8.8.8") { return $false }

    # Validar red 192.168.100.0/24
    if ($oct[0] -ne 192 -or $oct[1] -ne 168 -or $oct[2] -ne 100) { return $false }

    # No permitir red ni broadcast
    if ($oct[3] -eq 0 -or $oct[3] -eq 255) { return $false }

    return $true
}

function Rango-Valido {
    param($start, $end)

    if (-not (IP-Logica $start)) { return $false }
    if (-not (IP-Logica $end)) { return $false }

    $s = Convertir-IPaEntero $start
    $e = Convertir-IPaEntero $end

    return ($s -lt $e)
}

function Instalar-DHCP {
    if (-not (Get-WindowsFeature DHCP).Installed) {
        Write-Host "Iniciando descarga del servicio DHCP..."
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
        Add-DhcpServerInDC | Out-Null
        Write-Host "Descarga finalizada."
    } else {
        Write-Host "El servicio DHCP ya esta instalado."
    }
}

function Configurar-DHCP {
    Write-Host "=== CONFIGURACION DHCP ==="

    $scope = Read-Host "Nombre del ambito"

 do {
    $start = Read-Host "IP inicial"
} until (IP-Logica $start)

do {
    $end = Read-Host "IP final"
} until (IP-Logica $end)

if (-not (Rango-Valido $start $end)) {
    Write-Host "Rango incoherente. La IP inicial debe ser menor que la final."
    return
}


    $lease = Read-Host "Tiempo de concesion en horas"

    do { $router = Read-Host "Gateway" } until (Validar-IP $router)
    do { $dns = Read-Host "DNS" } until (Validar-IP $dns)

    Add-DhcpServerv4Scope `
        -Name $scope `
        -StartRange $start `
        -EndRange $end `
        -SubnetMask 255.255.255.0 `
        -LeaseDuration ([TimeSpan]::FromHours($lease)) `
        -State Active

    Set-DhcpServerv4OptionValue `
        -ScopeId ((Get-DhcpServerv4Scope).ScopeId) `
        -Router $router `
        -DnsServer $dns

    Write-Host "Configuracion aplicada correctamente."
}

function Monitoreo-DHCP {

    Write-Host "=== MONITOREO DHCP ==="
    Write-Host "Presiona CTRL + C para salir"

    while ($true) {
        Clear-Host

        $serv = Get-Service DHCPServer
        Write-Host "Estado del servicio:" $serv.Status
        Write-Host ""

        $scopes = Get-DhcpServerv4Scope

        if ($scopes) {
            foreach ($s in $scopes) {
                Write-Host "Ambito:" $s.ScopeId
                Write-Host "Rango:" $s.StartRange "-" $s.EndRange
                Write-Host ""

                $leases = Get-DhcpServerv4Lease -ScopeId $s.ScopeId -ErrorAction SilentlyContinue

                if ($leases) {
                    $leases | Select-Object IPAddress, HostName, ClientId, AddressState, LeaseExpiryTime
                } else {
                    Write-Host "Sin concesiones registradas en este ambito."
                }

                Write-Host ""
            }
        } else {
            Write-Host "No existen ambitos configurados."
        }

        Start-Sleep 5
    }
}

function Menu {
    do {
        Write-Host ""
        Write-Host "===== MENU DHCP WINDOWS ====="
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
