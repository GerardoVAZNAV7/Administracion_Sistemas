# =============================================================================
# ver_certificado.ps1
# Muestra informacion de los certificados SSL generados por la Practica 7
#
# USO:
#   .\ver_certificado.ps1
# =============================================================================

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

function Write-Ok   { param($m) Write-Host "  [OK]  $m" -ForegroundColor Green  }
function Write-Info { param($m) Write-Host "  [*]   $m" -ForegroundColor Cyan   }
function Write-Warn { param($m) Write-Host "  [!]   $m" -ForegroundColor Yellow }

Write-Host ""
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |        CERTIFICADOS SSL - PRACTICA 7 - WINDOWS             |" -ForegroundColor Cyan
Write-Host "  +============================================================+" -ForegroundColor Cyan

# =============================================================================
# METODO 1: Ver certificados en el almacen de Windows (cert store)
# Aqui viven los certificados que usa IIS Web e IIS FTP
# =============================================================================
Write-Host ""
Write-Host "  --- Certificados en el almacen de Windows (LocalMachine\My) ---" -ForegroundColor Yellow
Write-Host ""

$certs = Get-ChildItem Cert:\LocalMachine\My -ErrorAction SilentlyContinue

if ($certs) {
    foreach ($cert in $certs) {
        Write-Host "  Certificado:" -ForegroundColor White
        Write-Host ("    Sujeto (Subject)   : " + $cert.Subject)          -ForegroundColor Gray
        Write-Host ("    Emitido por        : " + $cert.Issuer)           -ForegroundColor Gray
        Write-Host ("    Valido desde       : " + $cert.NotBefore)        -ForegroundColor Gray
        Write-Host ("    Valido hasta       : " + $cert.NotAfter)         -ForegroundColor Gray
        Write-Host ("    Thumbprint         : " + $cert.Thumbprint)       -ForegroundColor Gray

        # Verificar si el certificado esta vencido
        if ($cert.NotAfter -lt (Get-Date)) {
            Write-Host "    ESTADO             : VENCIDO" -ForegroundColor Red
        } else {
            $diasRestantes = ($cert.NotAfter - (Get-Date)).Days
            Write-Host ("    ESTADO             : VALIDO (vence en $diasRestantes dias)") -ForegroundColor Green
        }

        # Mostrar SAN (Subject Alternative Names) si existe
        # El SAN es lo que hace que el navegador muestre el candado verde
        $sanExtension = $cert.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }
        if ($sanExtension) {
            Write-Host ("    SAN                : " + $sanExtension.Format($false)) -ForegroundColor Cyan
        } else {
            Write-Host "    SAN                : NO TIENE (el navegador dira No seguro)" -ForegroundColor Red
        }
        Write-Host ""
    }
} else {
    Write-Warn "No hay certificados en LocalMachine\My"
    Write-Host "    Ejecuta mainSSL.ps1 primero para generar los certificados." -ForegroundColor DarkGray
}

# =============================================================================
# METODO 2: Ver el certificado activo en el sitio IIS Web (puerto 443)
# =============================================================================
Write-Host ""
Write-Host "  --- Certificado vinculado a IIS (puerto 443) ---" -ForegroundColor Yellow
Write-Host ""

try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    $binding443 = Get-WebBinding -Protocol "https" -ErrorAction SilentlyContinue | Select-Object -First 1

    if ($binding443) {
        # Obtener el thumbprint del certificado vinculado al puerto 443
        $thumbprint = (Get-Item "IIS:\SslBindings\0.0.0.0!443" -ErrorAction SilentlyContinue).Thumbprint
        if ($thumbprint) {
            $certIIS = Get-Item "Cert:\LocalMachine\My\$thumbprint" -ErrorAction SilentlyContinue
            if ($certIIS) {
                Write-Ok "Certificado activo en IIS puerto 443:"
                Write-Host ("    Subject    : " + $certIIS.Subject)    -ForegroundColor Gray
                Write-Host ("    Thumbprint : " + $certIIS.Thumbprint) -ForegroundColor Gray
                Write-Host ("    Vence      : " + $certIIS.NotAfter)   -ForegroundColor Gray
            }
        } else {
            Write-Warn "No hay certificado vinculado al puerto 443 en IIS."
        }
    } else {
        Write-Warn "No hay binding HTTPS activo en IIS."
    }
} catch {
    Write-Warn "No se pudo leer el binding de IIS: $_"
}

# =============================================================================
# METODO 3: Ver el certificado de Apache o Nginx (archivos .crt en C:\)
# =============================================================================
Write-Host ""
Write-Host "  --- Archivos de certificado en disco (Apache/Nginx) ---" -ForegroundColor Yellow
Write-Host ""

$rutas = @(
    "C:\Apache24\conf\server.crt",
    "C:\nginx\conf\server.crt"
)

foreach ($ruta in $rutas) {
    if (Test-Path $ruta) {
        Write-Ok "Certificado encontrado: $ruta"
        # Usar certutil para mostrar info del certificado en archivo .crt
        $info = certutil -dump $ruta 2>&1 | Select-String -Pattern "Subject|Issuer|NotBefore|NotAfter|DNS Name|IP Address"
        foreach ($linea in $info) {
            Write-Host ("    " + $linea.Line.Trim()) -ForegroundColor Gray
        }
        Write-Host ""
    } else {
        Write-Host "    No encontrado: $ruta" -ForegroundColor DarkGray
    }
}

# =============================================================================
# METODO 4: Ver el certificado conectandose al servidor (como lo ve el navegador)
# =============================================================================
Write-Host ""
Write-Host "  --- Como ve el certificado el navegador (conexion real) ---" -ForegroundColor Yellow
Write-Host ""

$puertos = @(443, 8443)
$ip = (Get-NetIPAddress -AddressFamily IPv4 |
    Where-Object { $_.IPAddress -ne "127.0.0.1" } |
    Select-Object -First 1).IPAddress

foreach ($puerto in $puertos) {
    try {
        $tcpClient = New-Object System.Net.Sockets.TcpClient
        $tcpClient.Connect($ip, $puerto)

        $sslStream = New-Object System.Net.Security.SslStream(
            $tcpClient.GetStream(), $false,
            # Aceptar certificados autofirmados para la inspeccion
            { param($s,$c,$ch,$e) return $true }
        )
        $sslStream.AuthenticateAsClient("www.reprobados.com")
        $certConexion = $sslStream.RemoteCertificate

        if ($certConexion) {
            Write-Ok "Puerto $puerto responde con certificado:"
            Write-Host ("    Subject    : " + $certConexion.Subject)    -ForegroundColor Gray
            Write-Host ("    Issuer     : " + $certConexion.Issuer)     -ForegroundColor Gray
            Write-Host ("    Vence      : " + $certConexion.GetExpirationDateString()) -ForegroundColor Gray

            # Verificar SAN en el certificado recibido
            $cert2 = [System.Security.Cryptography.X509Certificates.X509Certificate2]$certConexion
            $sanExt = $cert2.Extensions | Where-Object { $_.Oid.FriendlyName -eq "Subject Alternative Name" }
            if ($sanExt) {
                Write-Host ("    SAN        : " + $sanExt.Format($false)) -ForegroundColor Cyan
                Write-Ok "El SAN esta presente. El navegador puede mostrar candado verde."
            } else {
                Write-Host "    SAN        : NO TIENE" -ForegroundColor Red
                Write-Warn "Sin SAN el navegador dira No seguro aunque el HTTPS funcione."
            }
        }

        $sslStream.Close()
        $tcpClient.Close()
    } catch {
        Write-Host ("    Puerto " + $puerto + ": no hay servicio escuchando o no es HTTPS.") -ForegroundColor DarkGray
    }
    Write-Host ""
}

Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host "  |  Para que el navegador muestre el candado verde:           |" -ForegroundColor White
Write-Host "  |    1. El certificado debe tener SAN (Subject Alt Names)    |" -ForegroundColor White
Write-Host "  |    2. El SAN debe incluir la IP o el dominio que usas      |" -ForegroundColor White
Write-Host "  |    3. Siempre aparecera aviso de cert autofirmado          |" -ForegroundColor White
Write-Host "  |       -> Haz clic en Avanzado -> Continuar igualmente      |" -ForegroundColor White
Write-Host "  +============================================================+" -ForegroundColor Cyan
Write-Host ""