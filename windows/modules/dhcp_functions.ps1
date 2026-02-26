# =========================================
# DHCP - VERIFICACIONES
# =========================================

function DHCP-Instalado {
    try { return (Get-WindowsFeature DHCP).Installed }
    catch { return $false }
}

function Servicio-DHCP-Activo {
    $serv = Get-Service DHCPServer -ErrorAction SilentlyContinue
    if ($serv) { return $serv.Status -eq "Running" }
    return $false
}

function Verificar-EstadoServicio {

    Write-Host ""
    Write-Host "=== ESTADO DEL SERVICIO DHCP ==="

    if (DHCP-Instalado) {
        Write-Host "Servicio DHCP: INSTALADO"

        if (Servicio-DHCP-Activo) {
            Write-Host "Estado: EN EJECUCION"
        }
        else {
            Write-Host "Estado: DETENIDO"
        }
    }
    else {
        Write-Host "Servicio DHCP: NO INSTALADO"
    }
}

# =========================================
# INSTALAR DHCP
# =========================================

function Instalar-DHCP {

    if (DHCP-Instalado) {

        do {
            $r = Read-Host "DHCP ya esta instalado ¿Desea reinstalarlo? (y/n)"
        } until ($r -in @("y","n"))

        if ($r -eq "n") { return }

        Write-Host "Reinstalando DHCP..."
        Uninstall-WindowsFeature DHCP -IncludeManagementTools -Confirm:$false | Out-Null
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    }
    else {
        Write-Host "Instalando DHCP..."
        Install-WindowsFeature DHCP -IncludeManagementTools | Out-Null
    }

    try { Add-DhcpServerInDC | Out-Null } catch {}
    Start-Service DHCPServer

    Write-Host "DHCP instalado y autorizado correctamente"
}

# =========================================
# LIMPIAR CONFIGURACION
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
}

# =========================================
# CONFIGURAR DHCP COMPLETO
# =========================================

function Configurar-DHCP {

    if (-not (DHCP-Instalado)) {
        Write-Host "DHCP no esta instalado"
        return
    }

    Limpiar-ScopesDHCP

    $scope = Read-Host "Nombre del ambito"

    do { $ipServidor = Read-Host "IP del servidor DHCP" }
    until (Test-IPv4 $ipServidor)

    do { $ipFinal = Read-Host "IP final del pool" }
    until (Test-IPv4 $ipFinal)

    $poolInicio = Get-NextIP $ipServidor
    $mask = Get-SubnetMask24

    Set-StaticIP $ipServidor
    Forzar-InterfazDHCP

    $scopeObj = Add-DhcpServerv4Scope `
        -Name $scope `
        -StartRange $poolInicio `
        -EndRange $ipFinal `
        -SubnetMask $mask `
        -State Active `
        -PassThru

    do { $gateway = Read-Host "Gateway" }
    until (Test-IPv4 $gateway)

    do { $dns = Read-Host "Servidor DNS" }
    until (Test-IPv4 $dns)

    $dominio = Read-Host "Nombre de dominio (opcional)"

    Set-DhcpServerv4OptionValue -ScopeId $scopeObj.ScopeId -Router $gateway
    Set-DhcpServerv4OptionValue -ScopeId $scopeObj.ScopeId -DnsServer $dns

    if ($dominio) {
        Set-DhcpServerv4OptionValue -ScopeId $scopeObj.ScopeId -DnsDomain $dominio
    }

    Restart-Service DHCPServer

    Write-Host ""
    Write-Host "===== DHCP CONFIGURADO ====="
    Write-Host "Servidor DHCP: $ipServidor"
    Write-Host "Pool desde: $poolInicio"
    Write-Host "Gateway: $gateway"
    Write-Host "DNS entregado a clientes: $dns"
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
        Get-Service DHCPServer
        Write-Host ""

        $scopes = Get-DhcpServerv4Scope -ErrorAction SilentlyContinue

        foreach ($s in $scopes) {
            Write-Host "Ambito:" $s.Name
            Write-Host "Rango:" $s.StartRange "-" $s.EndRange
            Write-Host "Leases activos:"
            Get-DhcpServerv4Lease -ScopeId $s.ScopeId -ErrorAction SilentlyContinue
            Write-Host ""
        }

        Start-Sleep 5
    }
}