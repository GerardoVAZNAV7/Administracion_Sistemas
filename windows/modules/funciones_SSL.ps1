# =============================================================================
# funciones_ssl.ps1  —  Servidores HTTP/HTTPS con puerto elegible
# Permite levantar múltiples instancias al mismo tiempo en puertos distintos
# =============================================================================

$global:resumenInstalaciones = @()

function Escribir-Resumen {
    param([string]$mensaje)
    $global:resumenInstalaciones += $mensaje
}

# =============================================================================
# VALIDAR PUERTO  (función nueva, reutilizada por las tres instalaciones)
# =============================================================================
# Enseñanza: separamos la validación en su propia función para no repetir
# el mismo bloque de código en Apache, Nginx e IIS (principio DRY).
# El resultado se devuelve como [int] para que el llamador lo use directo.
# =============================================================================
function Obtener-Puerto {
    param([string]$Servicio = "el servicio")

    $puertosBloqueados = @(21, 22, 25, 53, 110, 143, 445, 3306, 3389, 5432, 990)

    while ($true) {
        $raw = Read-Host "Puerto para $Servicio (ej. 80, 443, 8080, 8443, 9090)"

        # Debe ser número
        if ($raw -notmatch '^\d+$') {
            Write-Host "  [!] Ingresa solo números." -ForegroundColor Red
            continue
        }

        $p = [int]$raw

        # Rango válido
        if ($p -lt 1 -or $p -gt 65535) {
            Write-Host "  [!] Puerto fuera de rango (1-65535)." -ForegroundColor Red
            continue
        }

        # Puertos reservados del sistema
        if ($puertosBloqueados -contains $p) {
            Write-Host "  [!] Puerto $p reservado por otro servicio del sistema." -ForegroundColor Red
            continue
        }

        # Verificar que no esté ya ocupado en este momento
        $ocupado = netstat -ano 2>$null | Select-String ":$p "
        if ($ocupado) {
            Write-Host "  [!] Puerto $p ya está en uso por otro proceso." -ForegroundColor Red
            continue
        }

        return $p
    }
}

# =============================================================================
# LIBERAR PUERTOS  (sin cambios respecto a tu versión original)
# =============================================================================
function Liberar-Puertos-Web {
    Write-Host "Limpiando procesos residuales..." -ForegroundColor Yellow

    taskkill /F /IM httpd.exe /T 2>$null
    taskkill /F /IM nginx.exe /T 2>$null

    foreach ($svc in @("W3SVC","WAS","Apache-Practica7","apache","Apache2.4")) {
        Stop-Service -Name $svc -Force -ErrorAction SilentlyContinue
    }
    foreach ($svc in @("Apache-Practica7","apache","Apache2.4")) {
        sc.exe delete $svc | Out-Null
    }

    Remove-Item -Path "C:\tools\apache24","C:\Apache24","$env:APPDATA\Apache24",
                      "C:\tools\nginx","C:\nginx" -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\" -Filter "nginx-*" -Directory |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    foreach ($site in @("SitioIIS_Practica7","Default Web Site")) {
        if (Get-Website -Name $site -ErrorAction SilentlyContinue) {
            Remove-Website -Name $site
        }
    }

    Write-Host "Entorno limpio." -ForegroundColor Green
}

# =============================================================================
# INSTALAR APACHE
# =============================================================================
# Enseñanza: ahora pedimos el puerto AL INICIO de la función antes de tocar
# nada.  Si el usuario elige 443 ya existe SSL; si elige 80 es HTTP puro.
# El VirtualHost de redireccion usa $PuertoHTTP (siempre 80) apuntando a
# https://...:$Puerto para que la redirección sea correcta incluso en 8443.
# =============================================================================
function Instalar-Apache {
    Write-Host "`n--- INSTALANDO APACHE ---" -ForegroundColor Cyan
    Liberar-Puertos-Web

    # ── Elegir puerto ──────────────────────────────────────────────────────
    $Puerto = Obtener-Puerto -Servicio "Apache"
    Write-Host "  [OK] Puerto elegido: $Puerto" -ForegroundColor DarkGray

    # ── Origen ────────────────────────────────────────────────────────────
    Write-Host "1) Descargar de la Web (Chocolatey)"
    Write-Host "2) Descargar del FTP (Privado)"
    $origen = Read-Host "Selecciona el origen"

    $apacheDir = "C:\Apache24"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $chocoExe  = "C:\ProgramData\chocolatey\bin\choco.exe"

    if ($origen -eq "1") {
        if (-not (Test-Path $chocoExe)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
                'https://community.chocolatey.org/install.ps1'))
        }
        & $chocoExe install apache-httpd -y --force --params '"/NoService"' --limit-output

        $tempDir = ""
        foreach ($ruta in @("C:\tools\apache24","$env:APPDATA\Apache24","C:\Apache24")) {
            if (Test-Path $ruta) { $tempDir = $ruta; break }
        }
        if (-not $tempDir) { Write-Host "Error: instalación Choco falló." -ForegroundColor Red; return }
        if ($tempDir -ne "C:\Apache24") {
            if (Test-Path "C:\Apache24") { Remove-Item "C:\Apache24" -Recurse -Force }
            Move-Item -Path $tempDir -Destination "C:\Apache24" -Force
        }
    } else {
        $rutaZip = Navegar-Descargar-FTP -Servicio "Apache"
        if (-not $rutaZip) { return }
        Expand-Archive -Path $rutaZip -DestinationPath "C:\" -Force
    }

    # ── ¿SSL? ──────────────────────────────────────────────────────────────
    $resSSL = Read-Host "Desea activar SSL? [S/N]"
    $isSSL  = ($resSSL -match '^[sS]$')

    # ── httpd.conf ─────────────────────────────────────────────────────────
    $confPath  = "$apacheDir\conf\httpd.conf"
    $confArray = Get-Content $confPath | Where-Object {
        $_ -notmatch '^\s*Listen ' -and $_ -notmatch '^\s*ServerName '
    }
    $conf = $confArray -join "`r`n"
    $conf = $conf -replace 'Define SRVROOT ".*"', 'Define SRVROOT "C:/Apache24"'
    $conf = $conf -replace '(?m)^\s*Include conf/extra/httpd-ahssl\.conf.*$',
                            '#Include conf/extra/httpd-ahssl.conf'
    $conf = $conf -replace '(?m)^\s*Include conf/extra/httpd-ssl\.conf.*$',
                            '#Include conf/extra/httpd-ssl.conf'

    if ($isSSL) {
        # ── SSL: genera cert, configura HTTPS en $Puerto, redirige 80 ──────
        Write-Host "Generando certificado SSL para www.reprobados.com..."
        $env:OPENSSL_CONF = "$apacheDir\conf\openssl.cnf"
        Set-Location "$apacheDir\bin"
        .\openssl.exe req -x509 -nodes -newkey rsa:2048 `
            -keyout "$apacheDir\conf\server.key" `
            -out    "$apacheDir\conf\server.crt" `
            -days 365 -subj "/CN=www.reprobados.com"
        Set-Location "C:\"

        foreach ($mod in @("ssl_module","socache_shmcb_module","rewrite_module","headers_module")) {
            $conf = $conf -replace "(?m)^#?\s*LoadModule ${mod}_module.*$",
                                   "LoadModule $mod modules/mod_${mod}.so"
        }
        # LoadModule ssl_module tiene nombre especial
        $conf = $conf -replace "(?m)^#?\s*LoadModule ssl_module.*$",
                               "LoadModule ssl_module modules/mod_ssl.so"

        # Cabecera general: escuchar en 80 (redirección) Y en $Puerto (SSL)
        $conf = "Listen 80`r`nListen ${Puerto}`r`nServerName localhost:80`r`n" + $conf
        $conf += "`r`nInclude conf/extra/httpd-ssl.conf"

        # VirtualHost HTTP → redirige a HTTPS:$Puerto
        $conf += @"

<VirtualHost *:80>
    ServerName www.reprobados.com
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}:${Puerto}%{REQUEST_URI} [L,R=301]
</VirtualHost>
"@

        # httpd-ssl.conf con el puerto elegido
        $sslConf = @"
Listen ${Puerto}
SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLProxyCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLHonorCipherOrder on
SSLProtocol all -SSLv3
SSLProxyProtocol all -SSLv3
SSLPassPhraseDialog builtin
SSLSessionCache "shmcb:c:/Apache24/logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost _default_:${Puerto}>
    DocumentRoot "c:/Apache24/htdocs"
    ServerName www.reprobados.com:${Puerto}
    ServerAdmin admin@reprobados.com
    ErrorLog    "c:/Apache24/logs/error.log"
    TransferLog "c:/Apache24/logs/access.log"
    SSLEngine on
    SSLCertificateFile    "c:/Apache24/conf/server.crt"
    SSLCertificateKeyFile "c:/Apache24/conf/server.key"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</VirtualHost>
"@
        Set-Content -Path "$apacheDir\conf\extra\httpd-ssl.conf" -Value $sslConf -Force

        Escribir-Resumen "[OK] Apache: HTTPS puerto $Puerto (HTTP 80 redirige)."
        $protocolo = "HTTPS (Seguro)"; $bgColor = "#27ae60"

        # Firewall: abrir 80 (redirección) y el puerto SSL elegido
        New-NetFirewallRule -DisplayName "Apache HTTP  80"        -Direction Inbound `
            -LocalPort 80      -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "Apache HTTPS $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    } else {
        # ── HTTP puro en $Puerto ────────────────────────────────────────────
        $conf = "Listen ${Puerto}`r`nServerName localhost:${Puerto}`r`n" + $conf
        $conf = $conf -replace '(?m)^\s*LoadModule ssl_module.*$',
                               '#LoadModule ssl_module modules/mod_ssl.so'

        Escribir-Resumen "[OK] Apache: HTTP puro puerto $Puerto."
        $protocolo = "HTTP (Inseguro)"; $bgColor = "#2c3e50"

        New-NetFirewallRule -DisplayName "Apache HTTP $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    }

    $conf | Set-Content $confPath

    # ── index.html ─────────────────────────────────────────────────────────
    $versionFull  = (& "$apacheDir\bin\httpd.exe" -v | Select-String "Server version")
    $versionClean = ($versionFull -split "/")[1] -replace " .*", ""

    $html = @"
<html>
<body style='font-family:Arial;text-align:center;background-color:${bgColor};color:white;padding-top:50px;'>
  <div style='background:rgba(0,0,0,0.5);display:inline-block;padding:40px;border-radius:20px;border:3px solid white;'>
    <h1>SERVIDOR WEB: APACHE</h1>
    <hr style='width:80%;margin:20px auto;'>
    <p><b>Versión:</b> $versionClean</p>
    <p><b>Protocolo:</b> $protocolo</p>
    <p><b>Puerto:</b> $Puerto</p>
    <p>Configuración para www.reprobados.com</p>
  </div>
</body>
</html>
"@
    Set-Content -Path "$apacheDir\htdocs\index.html" -Value $html -Force

    Write-Host "Iniciando Apache en puerto $Puerto..." -ForegroundColor Cyan
    Start-Process -FilePath "$apacheDir\bin\httpd.exe" -WindowStyle Hidden
    Write-Host "[OK] Apache instalado." -ForegroundColor Green
}

# =============================================================================
# INSTALAR NGINX
# =============================================================================
# Enseñanza: Nginx escucha en un único "server { listen PUERTO; }" dentro de
# nginx.conf.  Generamos ese bloque con el puerto que el usuario eligió.
# Si hay SSL también generamos el bloque de redirección en 80 → HTTPS:$Puerto.
# =============================================================================
function Instalar-Nginx {
    Write-Host "`n--- INSTALANDO NGINX ---" -ForegroundColor Cyan
    Liberar-Puertos-Web

    $Puerto = Obtener-Puerto -Servicio "Nginx"
    Write-Host "  [OK] Puerto elegido: $Puerto" -ForegroundColor DarkGray

    Write-Host "1) Descargar de la Web (Chocolatey)"
    Write-Host "2) Descargar del FTP (Privado)"
    $origen = Read-Host "Selecciona el origen"

    $nginxDir = "C:\nginx"
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
    $viejoProgreso = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"

    if ($origen -eq "1") {
        if (-not (Test-Path $chocoExe)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
                'https://community.chocolatey.org/install.ps1'))
        }
        & $chocoExe install nginx -y --force --params '"/port:8080"' *>$null
        Stop-Service  -Name "nginx" -Force -ErrorAction SilentlyContinue
        sc.exe delete "nginx" | Out-Null

        $tempDir = ""
        foreach ($ruta in @("C:\tools","C:\","$env:APPDATA","$env:ProgramData")) {
            $found = Get-ChildItem -Path $ruta -Filter "nginx-*" -Directory -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if (-not $found) {
                $found = Get-ChildItem -Path $ruta -Filter "nginx" -Directory -ErrorAction SilentlyContinue |
                         Select-Object -First 1
            }
            if ($found) { $tempDir = $found.FullName; break }
        }
        if (-not $tempDir) {
            Write-Host "Error: instalación Choco falló." -ForegroundColor Red
            $ProgressPreference = $viejoProgreso; return
        }
        if ($tempDir -ne "C:\nginx") {
            if (Test-Path "C:\nginx") { Remove-Item "C:\nginx" -Recurse -Force }
            Move-Item -Path $tempDir -Destination "C:\nginx" -Force
        }
    } else {
        $rutaZip = Navegar-Descargar-FTP -Servicio "Nginx"
        if (-not $rutaZip) { $ProgressPreference = $viejoProgreso; return }
        Expand-Archive -Path $rutaZip -DestinationPath "C:\" -Force
        $busqueda = Get-ChildItem -Path "C:\" -Filter "nginx-*" -Directory | Select-Object -First 1
        if ($busqueda.FullName -ne "C:\nginx") {
            if (Test-Path "C:\nginx") { Remove-Item "C:\nginx" -Recurse -Force }
            Move-Item -Path $busqueda.FullName -Destination "C:\nginx" -Force
        }
    }

    $resSSL = Read-Host "Desea activar SSL? [S/N]"
    $isSSL  = ($resSSL -match '^[sS]$')

    if ($isSSL) {
        $opensslExe = "C:\Program Files\OpenSSL-Win64\bin\openssl.exe"
        if (-not (Test-Path $opensslExe)) {
            & $chocoExe install openssl -y *>$null
        }
        Write-Host "Generando certificado SSL para www.reprobados.com..."
        if (-not (Test-Path "$nginxDir\conf")) {
            New-Item -ItemType Directory -Path "$nginxDir\conf" -Force | Out-Null
        }
        $env:OPENSSL_CONF = "C:\Program Files\OpenSSL-Win64\bin\openssl.cfg"
        & $opensslExe req -x509 -nodes -newkey rsa:2048 `
            -keyout "$nginxDir\conf\server.key" `
            -out    "$nginxDir\conf\server.crt" `
            -days 365 -subj "/CN=www.reprobados.com" 2>$null

        # nginx.conf: 80 redirige, $Puerto escucha SSL
        $nginxConf = @"
worker_processes 1;
events { worker_connections 1024; }
http {
    include      mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;

    server {
        listen 80;
        server_name www.reprobados.com;
        return 301 https://`$host:${Puerto}`$request_uri;
    }

    server {
        listen ${Puerto} ssl;
        server_name www.reprobados.com;
        ssl_certificate     server.crt;
        ssl_certificate_key server.key;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        location / { root html; index index.html index.htm; }
    }
}
"@
        Escribir-Resumen "[OK] Nginx: HTTPS puerto $Puerto (HTTP 80 redirige)."
        $protocolo = "HTTPS (Seguro)"; $bgColor = "#115c2a"

        New-NetFirewallRule -DisplayName "Nginx HTTP  80"        -Direction Inbound `
            -LocalPort 80      -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "Nginx HTTPS $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    } else {
        $nginxConf = @"
worker_processes 1;
events { worker_connections 1024; }
http {
    include      mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    server {
        listen ${Puerto};
        server_name localhost;
        location / { root html; index index.html index.htm; }
    }
}
"@
        Escribir-Resumen "[OK] Nginx: HTTP puro puerto $Puerto."
        $protocolo = "HTTP (Inseguro)"; $bgColor = "#2c3e50"

        New-NetFirewallRule -DisplayName "Nginx HTTP $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    }

    Set-Content -Path "$nginxDir\conf\nginx.conf" -Value $nginxConf -Force

    # ── index.html ─────────────────────────────────────────────────────────
    $version = (& "$nginxDir\nginx.exe" -v 2>&1) -replace '.*nginx/', ''
    if (-not (Test-Path "$nginxDir\html")) {
        New-Item -ItemType Directory -Path "$nginxDir\html" -Force | Out-Null
    }
    $html = @"
<html>
<body style='font-family:Arial;text-align:center;background-color:${bgColor};color:white;padding-top:50px;'>
  <div style='background:rgba(0,0,0,0.5);display:inline-block;padding:40px;border-radius:20px;border:3px solid white;'>
    <h1>SERVIDOR WEB: NGINX</h1>
    <hr style='width:80%;margin:20px auto;'>
    <p><b>Versión:</b> $version</p>
    <p><b>Protocolo:</b> $protocolo</p>
    <p><b>Puerto:</b> $Puerto</p>
    <p>Configuración para www.reprobados.com</p>
  </div>
</body>
</html>
"@
    Set-Content -Path "$nginxDir\html\index.html" -Value $html -Force

    Write-Host "Iniciando Nginx en puerto $Puerto..." -ForegroundColor Cyan
    Start-Process -FilePath "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -WindowStyle Hidden
    $ProgressPreference = $viejoProgreso
    Write-Host "[OK] Nginx instalado." -ForegroundColor Green
}

# =============================================================================
# INSTALAR IIS WEB
# =============================================================================
# Enseñanza: IIS usa bindings.  Un binding es la combinación IP:Puerto:HostHeader.
# Podemos crear varios sitios en IIS siempre que cada uno tenga un puerto distinto.
# Si SSL, creamos el binding HTTPS también en $Puerto.
# =============================================================================
function Instalar-IIS-Web {
    Write-Host "`n--- INSTALANDO IIS WEB ---" -ForegroundColor Cyan
    Liberar-Puertos-Web

    $Puerto = Obtener-Puerto -Servicio "IIS"
    Write-Host "  [OK] Puerto elegido: $Puerto" -ForegroundColor DarkGray

    Write-Host "Instalando características base de IIS..."
    Install-WindowsFeature -name Web-Server -IncludeManagementTools | Out-Null
    Start-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    Start-Service -Name "WAS"   -ErrorAction SilentlyContinue

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    # Limpiar sitios anteriores de esta práctica (no el Default)
    Get-Website | Where-Object { $_.Name -like "SitioIIS_Practica7*" } | ForEach-Object {
        Stop-Website   -Name $_.Name -ErrorAction SilentlyContinue
        Remove-Website -Name $_.Name -ErrorAction SilentlyContinue
    }

    $resSSL = Read-Host "Desea activar SSL? [S/N]"
    $isSSL  = ($resSSL -match '^[sS]$')

    # Nombre único del sitio incluye el puerto para poder correr varios a la vez
    $siteName = "SitioIIS_Practica7_$Puerto"
    $sitePath = "C:\inetpub\wwwroot\$siteName"

    if (Test-Path $sitePath) { Remove-Item -Path $sitePath -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $sitePath | Out-Null

    if ($isSSL) {
        $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $chocoExe)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
                'https://community.chocolatey.org/install.ps1'))
        }
        & $chocoExe install urlrewrite -y --force *>$null
        iisreset /restart | Out-Null

        Add-Content -Path "$sitePath\index.html" `
            -Value "<h1>IIS Seguro (HTTPS) — Puerto $Puerto — www.reprobados.com</h1>" -Force

        Write-Host "Generando certificado SSL para www.reprobados.com..."
        $cert = New-SelfSignedCertificate -DnsName "www.reprobados.com" `
                    -CertStoreLocation "cert:\LocalMachine\My"

        # Sitio base en HTTP (redirección) + binding HTTPS en $Puerto
        New-Website -Name $siteName -Port 80 -PhysicalPath $sitePath -Force | Out-Null
        New-WebBinding -Name $siteName -Protocol "https" -Port $Puerto -IPAddress "*"

        Push-Location IIS:\SslBindings
        Remove-Item -Path "*!$Puerto" -Force -ErrorAction SilentlyContinue
        Get-Item "cert:\LocalMachine\My\$($cert.Thumbprint)" |
            New-Item -Path "*!$Puerto" -Force | Out-Null
        Pop-Location

        # web.config: redirige 80 → HTTPS:$Puerto y activa HSTS
        $webConfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <rewrite>
      <rules>
        <rule name="HTTP to HTTPS" stopProcessing="true">
          <match url="(.*)" />
          <conditions><add input="{HTTPS}" pattern="^OFF$" /></conditions>
          <action type="Redirect"
                  url="https://{HTTP_HOST}:${Puerto}/{R:1}"
                  redirectType="Permanent" />
        </rule>
      </rules>
    </rewrite>
    <httpProtocol>
      <customHeaders>
        <add name="Strict-Transport-Security"
             value="max-age=31536000; includeSubDomains" />
      </customHeaders>
    </httpProtocol>
  </system.webServer>
</configuration>
"@
        Set-Content -Path "$sitePath\web.config" -Value $webConfig -Force

        New-NetFirewallRule -DisplayName "IIS HTTPS $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        New-NetFirewallRule -DisplayName "IIS HTTP  80"      -Direction Inbound `
            -LocalPort 80      -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

        Escribir-Resumen "[OK] IIS: HTTPS puerto $Puerto (HTTP 80 redirige)."
    } else {
        Add-Content -Path "$sitePath\index.html" `
            -Value "<h1>IIS HTTP — Puerto $Puerto</h1>" -Force
        New-Website -Name $siteName -Port $Puerto -PhysicalPath $sitePath -Force | Out-Null

        New-NetFirewallRule -DisplayName "IIS HTTP $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

        Escribir-Resumen "[OK] IIS: HTTP puro puerto $Puerto."
    }

    Start-Website -Name $siteName -ErrorAction SilentlyContinue
    Write-Host "[OK] IIS configurado en puerto $Puerto." -ForegroundColor Green
}

# =============================================================================
# IIS FTP  (sin cambios funcionales, sólo ajuste de variables de entorno)
# =============================================================================
function Instalar-IIS-FTP {
    Write-Host "`n--- INSTALANDO IIS FTP ---" -ForegroundColor Cyan
    Install-WindowsFeature Web-FTP-Server -IncludeManagementTools | Out-Null

    $ftpUser = Read-Host "Usuario de la Práctica 5 a reutilizar"
    $ADSI    = [ADSI]"WinNT://$env:ComputerName"
    $existe  = $ADSI.Children | Where-Object {
        $_.SchemaClassName -eq 'User' -and $_.Name -eq $ftpUser
    }
    if (-not $existe) {
        Write-Host "El usuario $ftpUser no existe. Créalo primero con el script de la Práctica 5." -ForegroundColor Red
        return
    }

    $ftpPath = "C:\FTP\LocalUser\$ftpUser"
    if (-not (Test-Path $ftpPath)) {
        Write-Host "La ruta $ftpPath no existe." -ForegroundColor Red
        return
    }

    icacls $ftpPath /grant "${ftpUser}:(OI)(CI)(F)" /T | Out-Null
    icacls $ftpPath /grant "IUSR:(OI)(CI)(RX)"      /T | Out-Null
    icacls $ftpPath /grant "IIS_IUSRS:(OI)(CI)(RX)" /T | Out-Null

    $resSSL = Read-Host "Activar SSL en FTP? [S/N]"
    $isSSL  = ($resSSL -match '^[sS]$')
    $puerto = if ($isSSL) { 990 } else { 21 }

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (Get-WebSite -Name "FTP_Practica7" -ErrorAction SilentlyContinue) {
        Remove-WebSite -Name "FTP_Practica7"
    }

    New-WebFtpSite -Name "FTP_Practica7" -Port $puerto -PhysicalPath $ftpPath -Force | Out-Null
    Set-ItemProperty "IIS:\Sites\FTP_Practica7" `
        -Name ftpServer.userIsolation.mode -Value 0
    Remove-WebConfigurationProperty `
        -Filter "/system.ftpServer/security/authorization" `
        -Name "." -Location "FTP_Practica7" -ErrorAction SilentlyContinue

    if ($isSSL) {
        $cert = New-SelfSignedCertificate -DnsName "www.reprobados.com" `
                    -CertStoreLocation "cert:\LocalMachine\My"
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" `
            -Name ftpServer.security.ssl.serverCertHash -Value $cert.Thumbprint
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" `
            -Name ftpServer.security.ssl.controlChannelPolicy -Value 1
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" `
            -Name ftpServer.security.ssl.dataChannelPolicy -Value 1
        New-NetFirewallRule -DisplayName "IIS FTPS 990" -Direction Inbound `
            -LocalPort 990 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Escribir-Resumen "[OK] IIS FTP: FTPS puerto 990. Cert: www.reprobados.com"
    } else {
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" `
            -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" `
            -Name ftpServer.security.ssl.dataChannelPolicy -Value 0
        New-NetFirewallRule -DisplayName "IIS FTP 21" -Direction Inbound `
            -LocalPort 21 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Escribir-Resumen "[OK] IIS FTP: FTP plano puerto 21."
    }

    Set-ItemProperty "IIS:\Sites\FTP_Practica7" `
        -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -Value @{accessType="Allow"; users=$ftpUser; permissions="Read,Write"} `
        -PSPath IIS:\ -Location "FTP_Practica7"
    Restart-WebItem "IIS:\Sites\FTP_Practica7"

    Write-Host "[OK] IIS FTP configurado para $ftpUser en puerto $puerto." -ForegroundColor Green
}

# =============================================================================
# NAVEGAR / DESCARGAR POR FTP  (sin cambios)
# =============================================================================
function Navegar-Descargar-FTP {
    param([string]$Servicio)
    Write-Host "--- BUSCANDO INSTALADORES DE $Servicio EN FTP ---" -ForegroundColor Cyan

    $ftpUser     = "repositorio"
    $ftpPassword = "Hola1234."
    $urlBase     = "ftp://localhost:21/"
    $dirDescargas = "C:\descargas_ftp"
    if (-not (Test-Path $dirDescargas)) {
        New-Item -ItemType Directory -Force -Path $dirDescargas | Out-Null
    }

    $urlVersiones = "${urlBase}repositorio/${Servicio}/"
    $archivosRaw  = curl.exe -s -l -k -u "${ftpUser}:${ftpPassword}" $urlVersiones
    $archivos     = $archivosRaw -split "`n" |
                    Where-Object { $_.Trim() -match "\.zip$" }

    if ($archivos.Count -eq 0) {
        Write-Host "No hay archivos .zip en $urlVersiones" -ForegroundColor Red
        return $null
    }

    for ($i = 0; $i -lt $archivos.Count; $i++) {
        Write-Host "$($i+1)) $($archivos[$i].Trim())"
    }
    $selVer         = Read-Host "Selecciona el número de versión"
    $archivoElegido = $archivos[[int]$selVer - 1].Trim()

    $rutaInstalador = "$dirDescargas\$archivoElegido"
    $rutaHash       = "$dirDescargas\$archivoElegido.sha256"

    curl.exe -s --show-error -k -u "${ftpUser}:${ftpPassword}" `
        "${urlVersiones}${archivoElegido}"        -o $rutaInstalador
    curl.exe -s --show-error -k -u "${ftpUser}:${ftpPassword}" `
        "${urlVersiones}${archivoElegido}.sha256" -o $rutaHash

    if ((Test-Path $rutaInstalador) -and (Test-Path $rutaHash)) {
        $hashCalculado = (Get-FileHash -Path $rutaInstalador -Algorithm SHA256).Hash.ToLower()
        $hashOriginal  = ((Get-Content -Path $rutaHash -Raw) -split "\s+")[0].ToLower()
        if ($hashCalculado -eq $hashOriginal) {
            Write-Host "Integridad SHA256 confirmada." -ForegroundColor Green
            return $rutaInstalador
        }
        Write-Host "Error: hash no coincide." -ForegroundColor Red
        return $null
    }
    Write-Host "Error: descarga fallida." -ForegroundColor Red
    return $null
    
}