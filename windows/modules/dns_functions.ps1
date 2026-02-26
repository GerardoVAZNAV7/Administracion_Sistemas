# =====================================================
# FUNCIONES DNS (usa core_utils.ps1)
# =====================================================

# =========================================
# VERIFICAR INSTALACION DNS
# =========================================

function Opcion-Verificar {

    Write-Host "__________________________________________"
    Write-Host "Verificando instalacion DNS..."

    if (Test-WindowsFeatureInstalled "DNS") {
        Write-Color "El rol DNS esta instalado." Green
        Get-ServiceSafe "DNS" | Select-Object Name, Status
    }
    else {
        Write-Color "DNS NO esta instalado." Red
    }

    Read-Host "Presiona Enter para continuar..."
}

# =========================================
# INSTALAR DNS
# =========================================

function Opcion-Instalar {

    Write-Host "__________________________________________"

    if (-not (Test-WindowsFeatureInstalled "DNS")) {

        Write-Host "Instalando DNS, espera..."
        Install-WindowsFeatureSafe "DNS"
        Start-ServiceSafe "DNS"
        Opcion-FijarResolucionLocal
        Write-Color "Instalacion y configuracion completadas." Green
    }
    else {
        Write-Color "DNS ya estaba instalado." Yellow
    }

    Read-Host "Presiona Enter para continuar..."
}

# =========================================
# AGREGAR DOMINIO
# =========================================

function Opcion-Agregar {

    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++++"
    Write-Host "         AGREGAR DOMINIO DNS (WINDOWS)"
    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++++"

    $ZONA = Read-Host "Dominio (ej: reprobados.com)"

    if ([string]::IsNullOrWhiteSpace($ZONA)) {
        Write-Color "Dominio no puede estar vacio." Red
        Read-Host "Enter para continuar..."
        return
    }

    while ($true) {
        $IP_CLIENTE = Read-Host "IP del servidor/cliente"
        if (Test-IPv4 $IP_CLIENTE) { break }
        else { Write-Color "IP invalida, intenta de nuevo." Red }
    }

    if (Get-DnsServerZone -Name $ZONA -ErrorAction SilentlyContinue) {
        Write-Color "El dominio '$ZONA' ya existe." Yellow
        Read-Host "Enter para continuar..."
        return
    }

    try {
        Add-DnsServerPrimaryZone -Name $ZONA -ZoneFile "$ZONA.dns"
        Add-DnsServerResourceRecordA -Name "@" -IPv4Address $IP_CLIENTE -ZoneName $ZONA
        Add-DnsServerResourceRecordA -Name "www" -IPv4Address $IP_CLIENTE -ZoneName $ZONA
        Add-DnsServerResourceRecordA -Name "ns1" -IPv4Address $IP_CLIENTE -ZoneName $ZONA

        Write-Color "Dominio '$ZONA' agregado correctamente." Green
    }
    catch {
        Write-Color "[ERROR] No se pudo agregar la zona." Red
    }

    Read-Host "Presiona Enter para continuar..."
}

# =========================================
# BORRAR DOMINIO
# =========================================

function Opcion-Borrar {

    Write-Host "__________________________________________"

    $DOMINIOS = Get-DnsServerZone |
        Where-Object { $_.IsAutoCreated -eq $false -and $_.ZoneName -ne "TrustAnchors" }

    if ($DOMINIOS.Count -eq 0) {
        Write-Color "No hay dominios configurados para eliminar." Yellow
        Read-Host "Enter para continuar..."
        return
    }

    Write-Host "Dominios configurados:"
    for ($i=0; $i -lt $DOMINIOS.Count; $i++) {
        Write-Host "  $($i+1)) $($DOMINIOS[$i].ZoneName)"
    }
    Write-Host "  0) Cancelar"

    $SEL = Read-Host "Selecciona el numero del dominio a borrar"
    if ($SEL -eq "0") { return }

    try {
        $ZONA = $DOMINIOS[[int]$SEL - 1].ZoneName
        $CONFIRM = Read-Host "Vas a eliminar '$ZONA'. Confirmas? (s/n)"

        if ($CONFIRM -eq "s") {
            Remove-DnsServerZone -Name $ZONA -Force
            Write-Color "Dominio '$ZONA' eliminado correctamente." Green
        }
        else {
            Write-Host "Operacion cancelada."
        }
    }
    catch {
        Write-Color "Opcion invalida." Red
    }

    Read-Host "Presiona Enter para continuar..."
}

# =========================================
# VER DOMINIOS
# =========================================

function Opcion-Ver {

    Write-Host "__________________________________________"
    Write-Host "DOMINIOS CONFIGURADOS EN DNS SERVER:"

    Get-DnsServerZone |
    Where-Object { $_.IsAutoCreated -eq $false -and $_.ZoneName -ne "TrustAnchors" } |
    Select-Object ZoneName

    Read-Host "Presiona Enter para continuar..."
}

# =========================================
# FIJAR RESOLUCION LOCAL (NUEVA FUNCIÓN)
# =========================================

function Opcion-FijarResolucionLocal {
    Write-Host "__________________________________________"
    Write-Host "Configurando adaptador Ethernet para DNS Local..." -ForegroundColor Cyan
    
    # 1. Obtener la interfaz que está activa (Ethernet)
    $Interface = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1 -ExpandProperty Name
    
    # 2. Obtener la IP propia de esa interfaz
    $MiIP = (Get-NetIPAddress -InterfaceAlias $Interface -AddressFamily IPv4).IPAddress
    
    # 3. Forzar al adaptador a usar el Loopback y su propia IP. 
    # Esto elimina servidores externos como el 172.16.1.1 de la tarjeta.
    Set-DnsClientServerAddress -InterfaceAlias $Interface -ServerAddresses ("127.0.0.1", $MiIP)
    
    Write-Color "Configuracion exitosa: El servidor ahora se consulta a si mismo ($MiIP)." Green
    Read-Host "Enter para continuar..."
}