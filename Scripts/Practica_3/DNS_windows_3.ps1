# Función para manejar colores sin caracteres raros
function Escribir-Mensaje($msg, $color) {
    if ($color) {
        Write-Host $msg -ForegroundColor $color
    } else {
        Write-Host $msg
    }
}

function Validar-IP ($ip) {
    $regex = "^([0-9]{1,3}\.){3}[0-9]{1,3}$"
    if ($ip -notmatch $regex) { return $false }
    $octetos = $ip.Split('.')
    foreach ($o in $octetos) {
        if ([int]$o -lt 0 -or [int]$o -gt 255) { return $false }
    }
    return $true
}

function Opcion-Verificar {
    Write-Host "__________________________________________"
    Write-Host "Verificando instalacion DNS..."
    $check = Get-WindowsFeature -Name DNS
    if ($check.Installed) {
        Escribir-Mensaje "El rol DNS esta instalado." "Green"
        Get-Service -Name DNS | Select-Object Name, Status
    } else {
        Escribir-Mensaje "DNS NO esta instalado." "Red"
    }
    Read-Host "Presiona Enter para continuar..."
}

function Opcion-Instalar {
    Write-Host "__________________________________________"
    $check = Get-WindowsFeature -Name DNS
    if (-not $check.Installed) {
        Write-Host "Instalando DNS, espera..."
        Install-WindowsFeature -Name DNS -IncludeManagementTools
        Start-Service -Name DNS
        Escribir-Mensaje "Instalacion y configuracion completadas." "Green"
    } else {
        Escribir-Mensaje "DNS ya estaba instalado." "Yellow"
    }
    Read-Host "Presiona Enter para continuar..."
}

function Opcion-Agregar {
    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++++"
    Write-Host "         AGREGAR DOMINIO DNS (WINDOWS)"
    Write-Host "++++++++++++++++++++++++++++++++++++++++++++++++++"
    
    $ZONA = Read-Host "Dominio (ej: reprobados.com)"
    if ([string]::IsNullOrWhiteSpace($ZONA)) {
        Escribir-Mensaje "Dominio no puede estar vacio." "Red"
        Read-Host "Enter para continuar..."
        return
    }

    while ($true) {
        $IP_CLIENTE = Read-Host "IP del servidor/cliente"
        if (Validar-IP $IP_CLIENTE) { break }
        else { Escribir-Mensaje "IP invalida, intenta de nuevo." "Red" }
    }

    if (Get-DnsServerZone -Name $ZONA -ErrorAction SilentlyContinue) {
        Escribir-Mensaje "El dominio '$ZONA' ya existe." "Yellow"
        Read-Host "Enter para continuar..."
        return
    }

    try {
        Add-DnsServerPrimaryZone -Name $ZONA -ZoneFile "$ZONA.dns"
        Add-DnsServerResourceRecordA -Name "@" -IPv4Address $IP_CLIENTE -ZoneName $ZONA
        Add-DnsServerResourceRecordA -Name "www" -IPv4Address $IP_CLIENTE -ZoneName $ZONA
        Add-DnsServerResourceRecordA -Name "ns1" -IPv4Address $IP_CLIENTE -ZoneName $ZONA
        Escribir-Mensaje "Dominio '$ZONA' agregado correctamente." "Green"
    } catch {
        Escribir-Mensaje "[ERROR] No se pudo agregar la zona." "Red"
    }
    
    Read-Host "Presiona Enter para continuar..."
}

function Opcion-Borrar {
    Write-Host "__________________________________________"
    $DOMINIOS = Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false -and $_.ZoneName -ne "TrustAnchors" }
    
    if ($DOMINIOS.Count -eq 0) {
        Escribir-Mensaje "No hay dominios configurados para eliminar." "Yellow"
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
            Escribir-Mensaje "Dominio '$ZONA' eliminado correctamente." "Green"
        } else {
            Write-Host "Operacion cancelada."
        }
    } catch {
        Escribir-Mensaje "Opcion invalida." "Red"
    }
    Read-Host "Presiona Enter para continuar..."
}

function Opcion-Ver {
    Write-Host "__________________________________________"
    Write-Host "DOMINIOS CONFIGURADOS EN DNS SERVER:"
    Get-DnsServerZone | Where-Object { $_.IsAutoCreated -eq $false -and $_.ZoneName -ne "TrustAnchors" } | Select-Object ZoneName
    Read-Host "Presiona Enter para continuar..."
}

while ($true) {
    Clear-Host
    Write-Host "`n++++++++++++++++++++++++++++++++++"
    Write-Host "         SISTEMA DNS - WINDOWS"
    Write-Host "++++++++++++++++++++++++++++++++++"
    Write-Host "1) Verificar instalacion DNS"
    Write-Host "2) Instalar DNS"
    Write-Host "3) Agregar dominio"
    Write-Host "4) Borrar dominio"
    Write-Host "5) Ver dominios"
    Write-Host "6) Salir"
    Write-Host "__________________________________________"
    $OPT = Read-Host "Selecciona una opcion"

    switch ($OPT) {
        "1" { Opcion-Verificar }
        "2" { Opcion-Instalar }
        "3" { Opcion-Agregar }
        "4" { Opcion-Borrar }
        "5" { Opcion-Ver }
        "6" { exit }
        default { Escribir-Mensaje "Opcion invalida." "Red" }
    }
}