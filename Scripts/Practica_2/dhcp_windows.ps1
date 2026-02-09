
#*** PRACTICA 2 CONFIGURACION DEL SERVICIO DHCP

function Validar-IP {
    param([string]$ip)
    return $ip -match '^([0-9]{1,3}\.){3}[0-9]{1,3}$'
}

function Instalar-DHCP {
    if (-not (Get-WindowsFeature DHCP).Installed) {
        Install-WindowsFeature DHCP -IncludeManagementTools
        Add-DhcpServerInDC
    } else {
        Write-Host "DHCP ya instalado"
    }
}

function Configurar-DHCP {
    $scope = Read-Host "Nombre del ámbito"

    do {
        $start = Read-Host "IP inicial"
    } until (Validar-IP $start)

    do {
        $end = Read-Host "IP final"
    } until (Validar-IP $end)

    $lease = Read-Host "Tiempo de concesión (horas)"

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
        -LeaseDuration ([TimeSpan]::FromHours($lease))

    Set-DhcpServerv4OptionValue `
        -Router $router `
        -DnsServer $dns
}

function Monitoreo-DHCP {
    Get-Service DHCPServer
    Get-DhcpServerv4Scope
    Get-DhcpServerv4Lease
}

param($accion)

switch ($accion) {
    "instalar" { Instalar-DHCP }
    "configurar" { Configurar-DHCP }
    "monitoreo" { Monitoreo-DHCP }
    default { Write-Host "Uso: .\dhcp_windows.ps1 instalar|configurar|monitoreo" }
}
