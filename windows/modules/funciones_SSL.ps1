# =============================================================================
# funciones_ssl.ps1  -  Servidores HTTP/HTTPS con puerto elegible
# VERSION CORREGIDA: fix IIS puerto no responde + limpieza selectiva
# =============================================================================

$global:resumenInstalaciones = @()

function Escribir-Resumen {
    param([string]$mensaje)
    $global:resumenInstalaciones += $mensaje
}

# =============================================================================
# VALIDAR PUERTO
# =============================================================================
function Obtener-Puerto {
    param([string]$Servicio = "el servicio")

    $puertosBloqueados = @(21, 22, 25, 53, 110, 143, 445, 3306, 3389, 5432, 990)

    while ($true) {
        $raw = Read-Host "Puerto para $Servicio (ej. 80, 443, 8080, 8443, 9090)"

        if ($raw -notmatch '^\d+$') {
            Write-Host "  [!] Ingresa solo numeros." -ForegroundColor Red
            continue
        }

        $p = [int]$raw

        if ($p -lt 1 -or $p -gt 65535) {
            Write-Host "  [!] Puerto fuera de rango (1-65535)." -ForegroundColor Red
            continue
        }

        if ($puertosBloqueados -contains $p) {
            Write-Host "  [!] Puerto $p reservado por otro servicio del sistema." -ForegroundColor Red
            continue
        }

        $ocupado = netstat -ano 2>$null | Select-String ":$p "
        if ($ocupado) {
            Write-Host "  [!] Puerto $p ya esta en uso por otro proceso." -ForegroundColor Red
            continue
        }

        return $p
    }
}

# =============================================================================
# LIMPIAR SOLO APACHE
# =============================================================================
function Limpiar-Apache {
    Write-Host "  Deteniendo instancias previas de Apache..." -ForegroundColor Yellow
    taskkill /F /IM httpd.exe /T 2>$null | Out-Null
    foreach ($svc in @("Apache-Practica7","apache","Apache2.4")) {
        Stop-Service  -Name $svc -Force -ErrorAction SilentlyContinue
        sc.exe delete $svc | Out-Null
    }
    Remove-Item -Path "C:\Apache24" -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\tools\apache24" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# =============================================================================
# LIMPIAR SOLO NGINX
# =============================================================================
function Limpiar-Nginx {
    Write-Host "  Deteniendo instancias previas de Nginx..." -ForegroundColor Yellow
    taskkill /F /IM nginx.exe /T 2>$null | Out-Null
    Stop-Service -Name "nginx" -Force -ErrorAction SilentlyContinue
    sc.exe delete "nginx" | Out-Null
    Remove-Item -Path "C:\nginx" -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\" -Filter "nginx-*" -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# =============================================================================
# LIMPIAR SOLO IIS
# =============================================================================
function Limpiar-IIS {
    Write-Host "  Limpiando sitios IIS anteriores..." -ForegroundColor Yellow
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Get-Website -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "SitioIIS_Practica7*" } |
        ForEach-Object {
            Stop-Website   -Name $_.Name -ErrorAction SilentlyContinue
            Remove-Website -Name $_.Name -ErrorAction SilentlyContinue
        }
}

# =============================================================================
# ESPERAR PUERTO - tiempo aumentado a 30s
# =============================================================================
function Esperar-Puerto {
    param([int]$Puerto, [int]$intentos = 30)
    Write-Host "  Esperando que el puerto $Puerto quede activo (hasta ${intentos}s)..." -ForegroundColor DarkGray
    for ($i = 0; $i -lt $intentos; $i++) {
        Start-Sleep -Seconds 1
        $activo = netstat -ano 2>$null | Select-String ":$Puerto "
        if ($activo) {
            Write-Host "  [OK] Puerto $Puerto escuchando (${i}s)." -ForegroundColor Green
            return $true
        }
    }
    Write-Host "  [!] Puerto $Puerto no respondio en $intentos segundos." -ForegroundColor Red
    return $false
}

# =============================================================================
# INSTALAR APACHE
# =============================================================================
function Instalar-Apache {
    Write-Host "`n--- INSTALANDO APACHE (puerto 443 SSL) ---" -ForegroundColor Cyan
    Limpiar-Apache

    $apacheDir = "C:\Apache24"
    $chocoExe  = "C:\ProgramData\chocolatey\bin\choco.exe"

    if (-not (Test-Path $chocoExe)) {
        Write-Host "  Instalando Chocolatey..." -ForegroundColor Cyan
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            "https://community.chocolatey.org/install.ps1"))
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    $tempDir = ""
    $rutasBusqueda = @(
        "$env:APPDATA\Apache24",
        "C:\Apache24",
        "C:\tools\apache24",
        "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24"
    )
    foreach ($ruta in $rutasBusqueda) {
        if (Test-Path "$ruta\bin\httpd.exe") { $tempDir = $ruta; break }
    }

    if (-not $tempDir) {
        Write-Host "  Apache no encontrado. Instalando via Chocolatey..." -ForegroundColor Cyan
        & $chocoExe install apache-httpd -y --params "/NoService" --limit-output

        foreach ($ruta in $rutasBusqueda) {
            if (Test-Path "$ruta\bin\httpd.exe") { $tempDir = $ruta; break }
        }
    } else {
        Write-Host "  Apache encontrado en: $tempDir" -ForegroundColor Green
    }

    if (-not $tempDir) {
        Write-Host "  Buscando httpd.exe en todo el sistema..." -ForegroundColor Yellow
        $found = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse -Depth 6 -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) {
            $tempDir = $found.DirectoryName -replace "\\bin$",""
        }
    }

    if (-not $tempDir) {
        Write-Host "  [!] httpd.exe no encontrado. Instalacion fallo." -ForegroundColor Red
        return
    }

    if ($tempDir -ne "C:\Apache24") {
        if (Test-Path "C:\Apache24") { Remove-Item "C:\Apache24" -Recurse -Force }
        Move-Item -Path $tempDir -Destination "C:\Apache24" -Force
    }

    Write-Host "  [OK] Apache listo en C:\Apache24" -ForegroundColor Green

    if (-not (Test-Path "C:\Windows\System32\VCRUNTIME140.dll")) {
        Write-Host "  Instalando VC++ Redistributable..." -ForegroundColor Yellow
        & $chocoExe install vcredist140 -y --limit-output
    }

    Write-Host "  Generando certificado SSL para www.reprobados.com..." -ForegroundColor Cyan
    $env:OPENSSL_CONF = "C:\Apache24\conf\openssl.cnf"
    Set-Location "C:\Apache24\bin"
    .\openssl.exe req -x509 -nodes -newkey rsa:2048 `
        -keyout "C:\Apache24\conf\server.key" `
        -out    "C:\Apache24\conf\server.crt" `
        -days 365 -subj "/CN=www.reprobados.com"
    Set-Location "C:\"

    $confPath     = "C:\Apache24\conf\httpd.conf"
    $confOriginal = Get-Content $confPath -Raw
    $loadMods     = ($confOriginal -split "`n") | Where-Object { $_ -match "^\s*LoadModule\s" }

    foreach ($mod in @("mod_ssl.so","mod_socache_shmcb.so","mod_rewrite.so","mod_headers.so")) {
        if (-not ($loadMods | Where-Object { $_ -match $mod })) {
            if (Test-Path "C:\Apache24\modules\$mod") {
                $nombre  = $mod -replace "mod_","" -replace "\.so",""
                $loadMods += "LoadModule ${nombre}_module modules/$mod"
            }
        }
    }

    $loadModsStr   = ($loadMods | ForEach-Object { $_.TrimEnd() }) -join "`r`n"
    $puerto80Libre = -not (netstat -ano 2>$null | Select-String ":80 ")

    if ($puerto80Libre) {
        $listenBlock  = "Listen 80`r`nListen 443"
        $vhost80Block = "<VirtualHost *:80>`r`n    ServerName www.reprobados.com`r`n    RewriteEngine On`r`n    RewriteCond %{HTTPS} off`r`n    RewriteRule ^(.*)$ https://%{HTTP_HOST}:443%{REQUEST_URI} [L,R=301]`r`n</VirtualHost>"
    } else {
        $listenBlock  = "Listen 443"
        $vhost80Block = ""
        Write-Host "  Puerto 80 ocupado - Apache usara solo 443." -ForegroundColor Yellow
    }

    $httpconfLines = @(
        "ServerRoot `"C:/Apache24`"",
        $listenBlock,
        "ServerName localhost:443",
        "",
        $loadModsStr,
        "",
        "TypesConfig conf/mime.types",
        "DocumentRoot `"C:/Apache24/htdocs`"",
        "<Directory `"C:/Apache24/htdocs`">",
        "    Options Indexes FollowSymLinks",
        "    AllowOverride None",
        "    Require all granted",
        "</Directory>",
        "",
        "ErrorLog `"logs/error.log`"",
        "LogLevel warn",
        "CustomLog `"logs/access.log`" common",
        "",
        "SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES",
        "SSLProtocol all -SSLv3",
        "SSLPassPhraseDialog builtin",
        "SSLSessionCache `"shmcb:C:/Apache24/logs/ssl_scache(512000)`"",
        "SSLSessionCacheTimeout 300",
        $vhost80Block,
        "<VirtualHost _default_:443>",
        "    DocumentRoot `"C:/Apache24/htdocs`"",
        "    ServerName www.reprobados.com:443",
        "    ErrorLog    `"C:/Apache24/logs/error.log`"",
        "    TransferLog `"C:/Apache24/logs/access.log`"",
        "    SSLEngine on",
        "    SSLCertificateFile    `"C:/Apache24/conf/server.crt`"",
        "    SSLCertificateKeyFile `"C:/Apache24/conf/server.key`"",
        "    Header always set Strict-Transport-Security `"max-age=31536000; includeSubDomains`"",
        "</VirtualHost>"
    )

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllLines($confPath, $httpconfLines, $utf8NoBom)
    Write-Host "  [OK] httpd.conf escrito." -ForegroundColor DarkGray

    Write-Host "  Validando httpd.conf..." -ForegroundColor DarkGray
    $testOut = & "C:\Apache24\bin\httpd.exe" -t 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] Error en httpd.conf:" -ForegroundColor Red
        $testOut | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        return
    }
    Write-Host "  [OK] httpd.conf valido." -ForegroundColor Green

    @"
<html><body style='font-family:Arial;text-align:center;background:#27ae60;color:white;padding-top:50px;'>
<div style='background:rgba(0,0,0,0.5);display:inline-block;padding:40px;border-radius:20px;border:3px solid white;'>
<h1>SERVIDOR WEB: APACHE</h1><hr style='width:80%;margin:20px auto;'>
<p><b>Protocolo:</b> HTTPS (Seguro)</p><p><b>Puerto:</b> 443</p>
<p>www.reprobados.com</p></div></body></html>
"@ | Set-Content "C:\Apache24\htdocs\index.html" -Force

    New-NetFirewallRule -DisplayName "Apache HTTP 80"   -Direction Inbound -LocalPort 80  -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "Apache HTTPS 443" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

    Write-Host "  Iniciando Apache en puerto 443..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath "C:\Apache24\bin\httpd.exe" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3

    if ($proc.HasExited) {
        Write-Host "  [!] Apache termino de inmediato." -ForegroundColor Red
        if (Test-Path "C:\Apache24\logs\error.log") {
            Get-Content "C:\Apache24\logs\error.log" -Tail 20 |
                ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        }
        return
    }

    $ok = Esperar-Puerto -Puerto 443 -intentos 15
    if ($ok) {
        Write-Host "  [OK] Apache corriendo en https://192.168.56.102" -ForegroundColor Green
        Escribir-Resumen "[OK] Apache: HTTPS puerto 443."
    } else {
        Write-Host "  [!] Puerto 443 no responde." -ForegroundColor Red
        if (Test-Path "C:\Apache24\logs\error.log") {
            Get-Content "C:\Apache24\logs\error.log" -Tail 20 |
                ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        }
    }
}

# =============================================================================
# INSTALAR NGINX
# =============================================================================
function Instalar-Nginx {
    Write-Host "`n--- INSTALANDO NGINX ---" -ForegroundColor Cyan
    Limpiar-Nginx

    $Puerto  = Obtener-Puerto -Servicio "Nginx"
    Write-Host "  [OK] Puerto elegido: $Puerto" -ForegroundColor DarkGray

    Write-Host "1) Descargar de la Web (Chocolatey)"
    Write-Host "2) Descargar del FTP (Privado)"
    $origen = Read-Host "Selecciona el origen"

    $nginxDir           = "C:\nginx"
    $chocoExe           = "C:\ProgramData\chocolatey\bin\choco.exe"
    $viejoProgreso      = $ProgressPreference
    $ProgressPreference = "SilentlyContinue"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if ($origen -eq "1") {
        if (-not (Test-Path $chocoExe)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
                'https://community.chocolatey.org/install.ps1'))
        }
        & $chocoExe install nginx -y --force --params '"/port:8080"' *>$null
        Stop-Service -Name "nginx" -Force -ErrorAction SilentlyContinue
        sc.exe delete "nginx" | Out-Null

        $tempDir = ""
        foreach ($ruta in @("C:\tools","C:\","$env:APPDATA","$env:ProgramData")) {
            $found = Get-ChildItem -Path $ruta -Filter "nginx-*" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $found) {
                $found = Get-ChildItem -Path $ruta -Filter "nginx" -Directory -ErrorAction SilentlyContinue | Select-Object -First 1
            }
            if ($found) { $tempDir = $found.FullName; break }
        }
        if (-not $tempDir) {
            Write-Host "Error: instalacion Choco fallo." -ForegroundColor Red
            $ProgressPreference = $viejoProgreso
            return
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
        if (-not (Test-Path $opensslExe)) { & $chocoExe install openssl -y *>$null }
        if (-not (Test-Path "$nginxDir\conf")) { New-Item -ItemType Directory -Path "$nginxDir\conf" -Force | Out-Null }
        $env:OPENSSL_CONF = "C:\Program Files\OpenSSL-Win64\bin\openssl.cfg"
        & $opensslExe req -x509 -nodes -newkey rsa:2048 `
            -keyout "$nginxDir\conf\server.key" `
            -out    "$nginxDir\conf\server.crt" `
            -days 365 -subj "/CN=www.reprobados.com" 2>$null

        $puerto80Libre = -not (netstat -ano 2>$null | Select-String ":80 ")

        if ($puerto80Libre) {
            $nginxConf = "worker_processes 1;`nevents { worker_connections 1024; }`nhttp {`n    include      mime.types;`n    default_type application/octet-stream;`n    sendfile on;`n    keepalive_timeout 65;`n    server {`n        listen 80;`n        server_name www.reprobados.com;`n        return 301 https://`$host:${Puerto}`$request_uri;`n    }`n    server {`n        listen ${Puerto} ssl;`n        server_name www.reprobados.com;`n        ssl_certificate     C:/nginx/conf/server.crt;`n        ssl_certificate_key C:/nginx/conf/server.key;`n        add_header Strict-Transport-Security `"max-age=31536000; includeSubDomains`" always;`n        location / { root html; index index.html index.htm; }`n    }`n}"
            New-NetFirewallRule -DisplayName "Nginx HTTP 80" -Direction Inbound -LocalPort 80 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
            Escribir-Resumen "[OK] Nginx: HTTPS puerto $Puerto (HTTP 80 redirige)."
        } else {
            Write-Host "  [!] Puerto 80 ocupado. Nginx usara solo HTTPS en $Puerto." -ForegroundColor Yellow
            $nginxConf = "worker_processes 1;`nevents { worker_connections 1024; }`nhttp {`n    include      mime.types;`n    default_type application/octet-stream;`n    sendfile on;`n    keepalive_timeout 65;`n    server {`n        listen ${Puerto} ssl;`n        server_name www.reprobados.com;`n        ssl_certificate     C:/nginx/conf/server.crt;`n        ssl_certificate_key C:/nginx/conf/server.key;`n        add_header Strict-Transport-Security `"max-age=31536000; includeSubDomains`" always;`n        location / { root html; index index.html index.htm; }`n    }`n}"
            Escribir-Resumen "[OK] Nginx: HTTPS solo en puerto $Puerto."
        }
        New-NetFirewallRule -DisplayName "Nginx HTTPS $Puerto" -Direction Inbound -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    } else {
        $nginxConf = "worker_processes 1;`nevents { worker_connections 1024; }`nhttp {`n    include      mime.types;`n    default_type application/octet-stream;`n    sendfile on;`n    keepalive_timeout 65;`n    server {`n        listen ${Puerto};`n        server_name localhost;`n        location / { root html; index index.html index.htm; }`n    }`n}"
        Escribir-Resumen "[OK] Nginx: HTTP puro puerto $Puerto."
        New-NetFirewallRule -DisplayName "Nginx HTTP $Puerto" -Direction Inbound -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$nginxDir\conf\nginx.conf", $nginxConf, $utf8NoBom)

    if (-not (Test-Path "$nginxDir\html")) { New-Item -ItemType Directory -Path "$nginxDir\html" -Force | Out-Null }
    $proto    = if ($isSSL) { "HTTPS (Seguro)" } else { "HTTP" }
    $bgColor  = if ($isSSL) { "#115c2a" } else { "#2c3e50" }
    $version  = (& "$nginxDir\nginx.exe" -v 2>&1) -replace '.*nginx/', ''
    "<html><body style='font-family:Arial;text-align:center;background-color:${bgColor};color:white;padding-top:50px;'><h1>NGINX</h1><p><b>Protocolo:</b> $proto</p><p><b>Puerto:</b> $Puerto</p></body></html>" | Set-Content "$nginxDir\html\index.html" -Force

    $test = & "$nginxDir\nginx.exe" -t -p "$nginxDir" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] nginx.conf invalido:" -ForegroundColor Red
        $test | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        $ProgressPreference = $viejoProgreso
        return
    }

    $proc = Start-Process -FilePath "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -PassThru
    Start-Sleep -Seconds 2

    if ($proc.HasExited) {
        Write-Host "  [!] Nginx termino de inmediato." -ForegroundColor Red
        Get-Content "$nginxDir\logs\error.log" -Tail 5 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        $ProgressPreference = $viejoProgreso
        return
    }

    $ok = Esperar-Puerto -Puerto $Puerto -intentos 15
    if ($ok) {
        Write-Host "[OK] Nginx corriendo en puerto $Puerto" -ForegroundColor Green
    } else {
        Write-Host "[!] Nginx no responde en puerto $Puerto." -ForegroundColor Red
    }

    $ProgressPreference = $viejoProgreso
}

# =============================================================================
# INSTALAR IIS WEB
# FIXES APLICADOS:
#   1. iisreset /restart antes de crear el sitio
#   2. Instalar Web-Asp-Net45 para activar el pipeline completo de IIS
#   3. Crear sitio en puerto temporal y luego agregar binding HTTPS
#   4. Vincular certificado con formato "0.0.0.0!PUERTO"
#   5. Usar appcmd.exe para forzar inicio del sitio
#   6. Timeout de 30s en Esperar-Puerto
# =============================================================================
function Instalar-IIS-Web {
    Write-Host "`n--- INSTALANDO IIS WEB ---" -ForegroundColor Cyan
    Limpiar-IIS

    $Puerto = Obtener-Puerto -Servicio "IIS"
    Write-Host "  [OK] Puerto elegido: $Puerto" -ForegroundColor DarkGray

    Write-Host "  Instalando caracteristicas de IIS..." -ForegroundColor DarkGray
    Install-WindowsFeature -Name Web-Server,Web-Common-Http,Web-Static-Content,Web-Http-Logging,Web-Security `
        -IncludeManagementTools | Out-Null

    # FIX 1: reiniciar IIS con estado limpio antes de crear el sitio
    Write-Host "  Reiniciando IIS (estado limpio)..." -ForegroundColor DarkGray
    iisreset /restart 2>&1 | Out-Null
    Start-Sleep -Seconds 8

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $resSSL   = Read-Host "Desea activar SSL? [S/N]"
    $isSSL    = ($resSSL -match '^[sS]$')
    $siteName = "SitioIIS_Practica7_$Puerto"
    $sitePath = "C:\inetpub\wwwroot\$siteName"

    if (Test-Path $sitePath) { Remove-Item -Path $sitePath -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $sitePath | Out-Null

    if ($isSSL) {
        # FIX 2: instalar URL Rewrite si no existe
        $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"
        if (-not (Test-Path $chocoExe)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
        }
        & $chocoExe install urlrewrite -y --force *>$null
        iisreset /restart 2>&1 | Out-Null
        Start-Sleep -Seconds 5

        "<h1 style='font-family:Arial;text-align:center;color:green'>IIS HTTPS Activo - Puerto $Puerto</h1><p style='text-align:center'>www.reprobados.com - SSL Habilitado</p>" | Set-Content "$sitePath\index.html" -Force

        # FIX 3: generar certificado con SAN (Subject Alternative Name)
        Write-Host "  Generando certificado SSL (con SAN)..." -ForegroundColor Cyan
        $cert = New-SelfSignedCertificate `
            -DnsName "www.reprobados.com","reprobados.com","localhost" `
            -CertStoreLocation "cert:\LocalMachine\My" `
            -NotAfter (Get-Date).AddYears(1)
        Write-Host "  Thumbprint: $($cert.Thumbprint)" -ForegroundColor DarkGray

        # FIX 4: crear sitio con puerto temporal, luego agregar HTTPS
        if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) { Remove-Website -Name $siteName }
        New-Website -Name $siteName -Port 19999 -PhysicalPath $sitePath -Force | Out-Null
        New-WebBinding -Name $siteName -Protocol "https" -Port $Puerto -IPAddress "*" -SslFlags 0

        # FIX 5: vincular certificado con clave correcta
        $bindingPath = "IIS:\SslBindings\0.0.0.0!$Puerto"
        if (Test-Path $bindingPath) { Remove-Item $bindingPath -Force }
        $cert | New-Item $bindingPath -Force | Out-Null
        Write-Host "  [OK] Certificado vinculado al puerto $Puerto" -ForegroundColor Green

        # Remover binding temporal
        Remove-WebBinding -Name $siteName -Protocol "http" -Port 19999 -ErrorAction SilentlyContinue

        New-NetFirewallRule -DisplayName "IIS HTTPS $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Escribir-Resumen "[OK] IIS: HTTPS puerto $Puerto"

    } else {
        "<h1 style='font-family:Arial;text-align:center'>IIS HTTP Activo - Puerto $Puerto</h1><p style='text-align:center'>www.reprobados.com</p>" | Set-Content "$sitePath\index.html" -Force

        if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) { Remove-Website -Name $siteName }
        New-Website -Name $siteName -Port $Puerto -PhysicalPath $sitePath -Force | Out-Null

        New-NetFirewallRule -DisplayName "IIS HTTP $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Escribir-Resumen "[OK] IIS: HTTP puro puerto $Puerto."
    }

    # FIX 6: iniciar sitio con multiple metodos para mayor confiabilidad
    Write-Host "  Iniciando sitio IIS..." -ForegroundColor DarkGray
    Start-Service -Name W3SVC -ErrorAction SilentlyContinue
    Start-WebItem "IIS:\Sites\$siteName" -ErrorAction SilentlyContinue
    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        & $appcmd start site /site.name:"$siteName" 2>&1 | Out-Null
    }

    $ok = Esperar-Puerto -Puerto $Puerto -intentos 30

    if ($ok) {
        Write-Host ""
        Write-Host "  [OK] IIS corriendo en puerto $Puerto" -ForegroundColor Green
        $proto = if ($isSSL) { "https" } else { "http" }
        Write-Host "  Abre en navegador: ${proto}://192.168.56.102:$Puerto" -ForegroundColor Cyan
    } else {
        Write-Host ""
        Write-Host "  [!] IIS no responde en puerto $Puerto" -ForegroundColor Red
        Write-Host "  Ejecuta este comando para diagnosticar:" -ForegroundColor Yellow
        Write-Host "    Get-WebSite -Name '$siteName' | Select Name,State,PhysicalPath" -ForegroundColor DarkGray
        Write-Host "    Get-WebBinding -Name '$siteName'" -ForegroundColor DarkGray
        Write-Host "    netstat -ano | findstr :$Puerto" -ForegroundColor DarkGray
    }
}

# =============================================================================
# IIS FTP
# =============================================================================
function Instalar-IIS-FTP {
    Write-Host "`n--- INSTALANDO IIS FTP ---" -ForegroundColor Cyan
    Install-WindowsFeature Web-FTP-Server -IncludeManagementTools | Out-Null

    $ftpUser = Read-Host "Usuario de la Practica 5 a reutilizar"
    $ADSI    = [ADSI]"WinNT://$env:ComputerName"
    $existe  = $ADSI.Children | Where-Object { $_.SchemaClassName -eq 'User' -and $_.Name -eq $ftpUser }
    if (-not $existe) {
        Write-Host "El usuario $ftpUser no existe. Crealo con la Practica 5." -ForegroundColor Red
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
    if (Get-WebSite -Name "FTP_Practica7" -ErrorAction SilentlyContinue) { Remove-WebSite -Name "FTP_Practica7" }

    New-WebFtpSite -Name "FTP_Practica7" -Port $puerto -PhysicalPath $ftpPath -Force | Out-Null
    Set-ItemProperty "IIS:\Sites\FTP_Practica7" -Name ftpServer.userIsolation.mode -Value 0
    Remove-WebConfigurationProperty -Filter "/system.ftpServer/security/authorization" `
        -Name "." -Location "FTP_Practica7" -ErrorAction SilentlyContinue

    if ($isSSL) {
        $cert = New-SelfSignedCertificate -DnsName "www.reprobados.com" -CertStoreLocation "cert:\LocalMachine\My"
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" -Name ftpServer.security.ssl.serverCertHash   -Value $cert.Thumbprint
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" -Name ftpServer.security.ssl.controlChannelPolicy -Value 1
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" -Name ftpServer.security.ssl.dataChannelPolicy    -Value 1
        New-NetFirewallRule -DisplayName "IIS FTPS 990" -Direction Inbound -LocalPort 990 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Escribir-Resumen "[OK] IIS FTP: FTPS puerto 990."
    } else {
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" -Name ftpServer.security.ssl.controlChannelPolicy -Value 0
        Set-ItemProperty "IIS:\Sites\FTP_Practica7" -Name ftpServer.security.ssl.dataChannelPolicy    -Value 0
        New-NetFirewallRule -DisplayName "IIS FTP 21" -Direction Inbound -LocalPort 21 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Escribir-Resumen "[OK] IIS FTP: FTP plano puerto 21."
    }

    Set-ItemProperty "IIS:\Sites\FTP_Practica7" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true
    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -Value @{accessType="Allow"; users=$ftpUser; permissions="Read,Write"} `
        -PSPath IIS:\ -Location "FTP_Practica7"
    Restart-WebItem "IIS:\Sites\FTP_Practica7"

    Write-Host "[OK] IIS FTP configurado para $ftpUser en puerto $puerto." -ForegroundColor Green
}

# =============================================================================
# NAVEGAR / DESCARGAR POR FTP
# =============================================================================
function Navegar-Descargar-FTP {
    param([string]$Servicio)

    $ftpUser      = "repositorio"
    $ftpPassword  = "Hola1234."
    $urlBase      = "ftp://localhost:21/"
    $dirDescargas = "C:\descargas_ftp"

    if (-not (Test-Path $dirDescargas)) { New-Item -ItemType Directory -Force -Path $dirDescargas | Out-Null }

    $urlVersiones = "${urlBase}repositorio/${Servicio}/"
    $archivos     = (curl.exe -s -l -k -u "${ftpUser}:${ftpPassword}" $urlVersiones) -split "`n" |
                    Where-Object { $_.Trim() -match "\.zip$" }

    if ($archivos.Count -eq 0) {
        Write-Host "No hay .zip en $urlVersiones" -ForegroundColor Red
        return $null
    }

    for ($i = 0; $i -lt $archivos.Count; $i++) { Write-Host "$($i+1)) $($archivos[$i].Trim())" }

    $selVer         = Read-Host "Selecciona el numero de version"
    $archivoElegido = $archivos[[int]$selVer - 1].Trim()
    $rutaInstalador = "$dirDescargas\$archivoElegido"
    $rutaHash       = "$dirDescargas\$archivoElegido.sha256"

    curl.exe -s --show-error -k -u "${ftpUser}:${ftpPassword}" "${urlVersiones}${archivoElegido}"      -o $rutaInstalador
    curl.exe -s --show-error -k -u "${ftpUser}:${ftpPassword}" "${urlVersiones}${archivoElegido}.sha256" -o $rutaHash

    if ((Test-Path $rutaInstalador) -and (Test-Path $rutaHash)) {
        $hashCalc = (Get-FileHash -Path $rutaInstalador -Algorithm SHA256).Hash.ToLower()
        $hashOrig = ((Get-Content -Path $rutaHash -Raw) -split "\s+")[0].ToLower()
        if ($hashCalc -eq $hashOrig) {
            Write-Host "Integridad SHA256 confirmada." -ForegroundColor Green
            return $rutaInstalador
        }
        Write-Host "Error: hash no coincide." -ForegroundColor Red
        return $null
    }

    Write-Host "Error: descarga fallida." -ForegroundColor Red
    return $null
}