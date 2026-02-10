
#*** PRACTICA 2 CONFIGURACION DEL SERVICIO DHCP

function Validar-IP {
    param([string]$ip)
    return $ip -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

function Instalar-SiNoExiste {
    if (-not (Get-WindowsFeature DHCP).Installed) {
        Write-Host "No se encontro servicio DHCP. Procederemos con la descarga..."
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
        Add-DhcpServerInDC | Out-Null
        Write-Host "Descarga completada."
    } else {
        Write-Host "Servicio DHCP detectado."
    }
}

function Configurar-DHCP {
    Write-Host "=== CONFIGURACION DHCP ==="

    $scope = Read-Host "Nombre del ambito"

    do {
        $start = Read-Host "IP inicial"
    } until (Validar-IP $start)

    do {
        $end = Read-Host "IP final"
    } until (Validar-IP $end)

    $lease = Read-Host "Tiempo de concesion (horas)"

    do {
        $router = Read-Host "Gateway"
    } until (Validar-IP $router)

    do {
        $dns = Read-Host "DNS"
    } until (Validar-IP $dns)

    Add-DhcpServerv4Scope `
        -Name $scope `
        -StartRange $start `
        -EndRange $end `
        -SubnetMask 255.255.255.0 `
        -LeaseDuration ([TimeSpan]::FromHours($lease)) `
        -State Active

    Set-DhcpServerv4OptionValue `
        -Router $router `
        -DnsServer $dns

    Write-Host "Configuracion aplicada."
}

function Monitoreo {
    Write-Host "=== MONITOREO EN TIEMPO REAL ==="
    Write-Host "Presiona CTRL + C para salir"
    Write-Host ""

    while ($true) {
        Clear-Host

        Write-Host "Estado del servicio DHCP:"
        Get-Service DHCPServer | Select-Object Status
        Write-Host ""

        # Obtener automaticamente el ScopeId
        $scope = Get-DhcpServerv4Scope | Select-Object -ExpandProperty ScopeId

        if ($scope) {
            Write-Host "Ambito detectado:" $scope
            Write-Host ""

            Write-Host "Concesiones activas:"
            Get-DhcpServerv4Lease -ScopeId $scope |
            Select-Object `
                IPAddress,
                HostName,
                ClientId,
                AddressState,
                LeaseExpiryTime
        }
        else {
            Write-Host "No se detecto ningun ambito DHCP configurado."
        }

        Start-Sleep -Seconds 5
    }
}


Instalar-SiNoExiste
Configurar-DHCP
Monitoreo

