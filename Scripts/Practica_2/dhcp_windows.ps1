function Validar-IP {
    param([string]$ip)

    if ($ip -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$') {
        $oct = $ip.Split('.')
        foreach ($o in $oct) {
            if ([int]$o -gt 255) { return $false }
        }
        return $true
    }
    return $false
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

    do { $start = Read-Host "IP inicial" } until (Validar-IP $start)
    do { $end = Read-Host "IP final" } until (Validar-IP $end)

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
