# =============================================================================
# funciones_ssl.ps1  -  Servidores HTTP/HTTPS con puerto elegible
# VERSION CORREGIDA v3: Apache fuerza reinstalacion | IIS limpieza total
# NGINX: NO MODIFICADO (ya funciona)
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
    Remove-Item -Path "C:\Apache24"       -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\tools\apache24" -Recurse -Force -ErrorAction SilentlyContinue

    # FORZAR ELIMINACION del cache de Chocolatey para apache-httpd
    Write-Host "  Eliminando cache Chocolatey de apache-httpd..." -ForegroundColor Yellow
    Remove-Item -Path "C:\ProgramData\chocolatey\lib\apache-httpd"  -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\ProgramData\chocolatey\lib-bad\apache-httpd" -Recurse -Force -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2
}

# =============================================================================
# LIMPIAR SOLO NGINX  (NO TOCAR - YA FUNCIONA)
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
# LIMPIAR IIS - LIMPIEZA TOTAL INCLUYENDO applicationHost.config
# =============================================================================
function Limpiar-IIS {
    Write-Host "  Limpiando TODOS los sitios IIS y reseteando config..." -ForegroundColor Yellow

    # Detener todo
    iisreset /stop 2>&1 | Out-Null
    Stop-Service -Name W3SVC,WAS -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Eliminar sitios via appcmd (mas confiable que PowerShell cuando config esta daada)
    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        # Listar y eliminar todos los sitios excepto "Default Web Site"
        $sitios = & $appcmd list site /text:name 2>$null
        foreach ($s in $sitios) {
            $s = $s.Trim()
            if ($s -and $s -ne "Default Web Site") {
                Write-Host "    Eliminando sitio: $s" -ForegroundColor DarkGray
                & $appcmd delete site /site.name:"$s" 2>$null | Out-Null
            }
        }
        # Eliminar App Pools huerfanos (excepto DefaultAppPool y .NET v4.5 Classic)
        $pools = & $appcmd list apppool /text:name 2>$null
        foreach ($pool in $pools) {
            $pool = $pool.Trim()
            if ($pool -and $pool -ne "DefaultAppPool" -and $pool -ne ".NET v4.5 Classic" -and $pool -ne ".NET v4.5") {
                Write-Host "    Eliminando pool: $pool" -ForegroundColor DarkGray
                & $appcmd delete apppool /apppool.name:"$pool" 2>$null | Out-Null
            }
        }
    }

    # Limpiar SSL bindings del registro (causa del FileLoadException)
    Write-Host "  Limpiando SSL bindings del sistema..." -ForegroundColor Yellow
    $sslPath = "HKLM:\SYSTEM\CurrentControlSet\Services\HTTP\Parameters\SslBindingInfo"
    if (Test-Path $sslPath) {
        Get-ChildItem $sslPath -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    }
    # Limpiar con netsh
    netsh http show sslcert 2>$null | Select-String "IP:port" | ForEach-Object {
        $binding = ($_ -split ":\s+")[1].Trim()
        if ($binding) {
            netsh http delete sslcert ipport=$binding 2>$null | Out-Null
        }
    }

    # Limpiar carpetas fisicas de sitios anteriores
    Get-ChildItem "C:\inetpub\wwwroot" -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like "SitioIIS_*" } |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    Start-Sleep -Seconds 2
    Write-Host "  [OK] Limpieza IIS completada." -ForegroundColor Green
}

# =============================================================================
# ESPERAR PUERTO
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
# INSTALAR APACHE - FUERZA REINSTALACION COMPLETA CON CHOCOLATEY
# =============================================================================
function Instalar-Apache {
    Write-Host "`n--- INSTALANDO APACHE (REINSTALACION FORZADA) ---" -ForegroundColor Cyan

    # Limpiar todo incluyendo cache de choco
    Limpiar-Apache

    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"

    # Instalar Chocolatey si no existe
    if (-not (Test-Path $chocoExe)) {
        Write-Host "  Instalando Chocolatey..." -ForegroundColor Cyan
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            "https://community.chocolatey.org/install.ps1"))
    }

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    # FORZAR descarga e instalacion limpia (--force + ignoredependencies)
    Write-Host "  Descargando e instalando Apache via Chocolatey (forzado)..." -ForegroundColor Cyan
    & $chocoExe install apache-httpd -y --force --no-progress `
        --params "/NoService" `
        --ignore-checksums `
        2>&1 | Where-Object { $_ -notmatch "^Progress" } | ForEach-Object {
            Write-Host "    $_" -ForegroundColor DarkGray
        }

    # Buscar donde quedo instalado
    $apacheDir = ""
    $rutasBusqueda = @(
        "C:\tools\apache24",
        "C:\Apache24",
        "$env:APPDATA\Apache24",
        "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24"
    )

    foreach ($ruta in $rutasBusqueda) {
        if (Test-Path "$ruta\bin\httpd.exe") { $apacheDir = $ruta; break }
    }

    # Busqueda exhaustiva si no se encontro
    if (-not $apacheDir) {
        Write-Host "  Buscando httpd.exe en el sistema..." -ForegroundColor Yellow
        $found = Get-ChildItem "C:\" -Filter "httpd.exe" -Recurse -Depth 8 -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) {
            $apacheDir = $found.DirectoryName -replace "\\bin$",""
            Write-Host "  Encontrado en: $apacheDir" -ForegroundColor Green
        }
    }

    if (-not $apacheDir) {
        Write-Host "  [!] httpd.exe no encontrado tras instalacion. Abortando." -ForegroundColor Red
        return
    }

    # Mover a C:\Apache24 si no esta ahi
    if ($apacheDir -ne "C:\Apache24") {
        Write-Host "  Moviendo Apache a C:\Apache24..." -ForegroundColor DarkGray
        if (Test-Path "C:\Apache24") { Remove-Item "C:\Apache24" -Recurse -Force }
        Copy-Item -Path $apacheDir -Destination "C:\Apache24" -Recurse -Force
    }

    Write-Host "  [OK] Apache listo en C:\Apache24" -ForegroundColor Green

    # VC++ Redistributable
    if (-not (Test-Path "C:\Windows\System32\VCRUNTIME140.dll")) {
        Write-Host "  Instalando VC++ Redistributable..." -ForegroundColor Yellow
        & $chocoExe install vcredist140 -y --limit-output
    }

    # Generar certificado SSL
    Write-Host "  Generando certificado SSL para www.reprobados.com..." -ForegroundColor Cyan
    $env:OPENSSL_CONF = "C:\Apache24\conf\openssl.cnf"

    if (-not (Test-Path "C:\Apache24\conf")) {
        New-Item -ItemType Directory -Path "C:\Apache24\conf" -Force | Out-Null
    }

    $opensslExe = "C:\Apache24\bin\openssl.exe"
    if (-not (Test-Path $opensslExe)) {
        Write-Host "  [!] openssl.exe no encontrado en Apache. Buscando alternativo..." -ForegroundColor Yellow
        $opensslAlt = Get-ChildItem "C:\" -Filter "openssl.exe" -Recurse -Depth 6 -ErrorAction SilentlyContinue |
                      Select-Object -First 1
        if ($opensslAlt) { $opensslExe = $opensslAlt.FullName }
    }

    if (Test-Path $opensslExe) {
        & $opensslExe req -x509 -nodes -newkey rsa:2048 `
            -keyout "C:\Apache24\conf\server.key" `
            -out    "C:\Apache24\conf\server.crt" `
            -days 365 -subj "/CN=www.reprobados.com" 2>&1 | Out-Null
        Write-Host "  [OK] Certificado generado." -ForegroundColor Green
    } else {
        Write-Host "  [!] openssl.exe no encontrado. SSL puede fallar." -ForegroundColor Red
    }

    # Construir httpd.conf
    $confPath = "C:\Apache24\conf\httpd.conf"
    $confOriginal = Get-Content $confPath -Raw -ErrorAction SilentlyContinue
    $loadMods = @()
    if ($confOriginal) {
        $loadMods = ($confOriginal -split "`n") | Where-Object { $_ -match "^\s*LoadModule\s" }
    }

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

    # Validar config
    Write-Host "  Validando httpd.conf..." -ForegroundColor DarkGray
    $testOut = & "C:\Apache24\bin\httpd.exe" -t 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] Error en httpd.conf:" -ForegroundColor Red
        $testOut | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        return
    }
    Write-Host "  [OK] httpd.conf valido." -ForegroundColor Green

    # Pagina de inicio
    if (-not (Test-Path "C:\Apache24\htdocs")) {
        New-Item -ItemType Directory -Path "C:\Apache24\htdocs" -Force | Out-Null
    }
    @"
<html><body style='font-family:Arial;text-align:center;background:#27ae60;color:white;padding-top:50px;'>
<div style='background:rgba(0,0,0,0.5);display:inline-block;padding:40px;border-radius:20px;border:3px solid white;'>
<h1>SERVIDOR WEB: APACHE</h1><hr style='width:80%;margin:20px auto;'>
<p><b>Protocolo:</b> HTTPS (Seguro)</p><p><b>Puerto:</b> 443</p>
<p>www.reprobados.com</p></div></body></html>
"@ | Set-Content "C:\Apache24\htdocs\index.html" -Force

    # Firewall
    New-NetFirewallRule -DisplayName "Apache HTTP 80"   -Direction Inbound -LocalPort 80  -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "Apache HTTPS 443" -Direction Inbound -LocalPort 443 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

    # Asegurar directorio de logs
    if (-not (Test-Path "C:\Apache24\logs")) {
        New-Item -ItemType Directory -Path "C:\Apache24\logs" -Force | Out-Null
    }

    Write-Host "  Iniciando Apache en puerto 443..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath "C:\Apache24\bin\httpd.exe" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3

    if ($proc.HasExited) {
        Write-Host "  [!] Apache termino de inmediato. Error log:" -ForegroundColor Red
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
# INSTALAR NGINX - NO MODIFICADO (YA FUNCIONA BIEN)
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
# INSTALAR IIS WEB - CORREGIDO
# FIXES:
#   1. Limpieza total de sitios Y ssl bindings ANTES de instalar
#   2. Usar appcmd.exe para crear el sitio (evita bug de New-Website con arrays)
#   3. Vincular cert con netsh (evita FileLoadException de New-Item en IIS:\SslBindings)
#   4. Verificar que el sitio existe antes de arrancar
# =============================================================================
function Instalar-IIS-Web {
    Write-Host "`n--- INSTALANDO IIS WEB ---" -ForegroundColor Cyan

    # PASO 1: Limpieza total
    Limpiar-IIS

    # PASO 2: Asegurar que IIS esta instalado y corriendo
    Write-Host "  [1/6] Verificando/instalando IIS..." -ForegroundColor Yellow
    $iisFeature = Get-WindowsFeature Web-Server -ErrorAction SilentlyContinue
    if (-not $iisFeature -or -not $iisFeature.Installed) {
        Write-Host "  Instalando IIS..." -ForegroundColor Cyan
        Install-WindowsFeature -Name Web-Server,Web-Common-Http,Web-Static-Content,`
Web-Http-Logging,Web-Security,Web-Mgmt-Console -IncludeManagementTools | Out-Null
        Start-Sleep -Seconds 5
    }

    # Arrancar servicios
    Start-Service -Name WAS   -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Service -Name W3SVC -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    iisreset /start 2>&1 | Out-Null
    Start-Sleep -Seconds 3

    Import-Module WebAdministration -Force -ErrorAction Stop

    # PASO 3: Pedir configuracion
    $Puerto   = Obtener-Puerto -Servicio "IIS"
    $resSSL   = Read-Host "  Desea activar SSL? [S/N]"
    $isSSL    = ($resSSL -match '^[sS]$')
    $siteName = "SitioIIS_Practica7_$Puerto"
    $sitePath = "C:\inetpub\wwwroot\$siteName"
    $proto    = if ($isSSL) { "HTTPS" } else { "HTTP" }

    Write-Host "  [OK] Puerto: $Puerto  |  SSL: $isSSL  |  Sitio: $siteName" -ForegroundColor DarkGray

    # PASO 4: Crear carpeta y HTML
    Write-Host "  [2/6] Creando contenido web..." -ForegroundColor Yellow
    if (Test-Path $sitePath) { Remove-Item $sitePath -Recurse -Force }
    New-Item -ItemType Directory -Path $sitePath -Force | Out-Null

    @"
<!DOCTYPE html>
<html>
<head><meta charset="UTF-8"><title>IIS $proto - Puerto $Puerto</title></head>
<body style="font-family:Arial;text-align:center;background:#1a3c5c;color:white;padding-top:80px;">
  <div style="display:inline-block;background:rgba(0,0,0,0.5);padding:40px;border-radius:16px;">
    <h1>IIS ACTIVO</h1>
    <p><b>Protocolo:</b> $proto</p>
    <p><b>Puerto:</b> $Puerto</p>
    <p>www.reprobados.com - Windows Server 2022</p>
  </div>
</body>
</html>
"@ | Set-Content "$sitePath\index.html" -Encoding UTF8 -Force

    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"

    if ($isSSL) {
        # PASO 5 SSL: Generar certificado
        Write-Host "  [3/6] Generando certificado SSL..." -ForegroundColor Yellow
        $cert = New-SelfSignedCertificate `
            -DnsName "www.reprobados.com","reprobados.com","localhost" `
            -CertStoreLocation "cert:\LocalMachine\My" `
            -NotAfter (Get-Date).AddYears(1)
        $thumbprint = $cert.Thumbprint
        Write-Host "  [OK] Thumbprint: $thumbprint" -ForegroundColor DarkGray

        # PASO 5 SSL: Crear sitio con appcmd (evita el bug de New-Website)
        Write-Host "  [4/6] Creando sitio HTTPS con appcmd..." -ForegroundColor Yellow
        & $appcmd add site /name:"$siteName" `
            /physicalPath:"$sitePath" `
            /bindings:"https/*:${Puerto}:" 2>&1 | ForEach-Object {
                Write-Host "    appcmd: $_" -ForegroundColor DarkGray
            }

        Start-Sleep -Seconds 2

        # Verificar que el sitio se creo
        $siteCheck = & $appcmd list site /site.name:"$siteName" 2>$null
        if (-not $siteCheck) {
            Write-Host "  [!] appcmd no creo el sitio. Intentando con New-Website..." -ForegroundColor Yellow
            try {
                New-Website -Name $siteName -Port $Puerto -PhysicalPath $sitePath -Ssl -Force -ErrorAction Stop | Out-Null
            } catch {
                Write-Host "  [!] New-Website fallo: $_" -ForegroundColor Red
                Write-Host "  Intenta ejecutar: iisreset /restart  y vuelve a correr el script." -ForegroundColor Cyan
                return
            }
        }

        # Vincular certificado con netsh (MAS CONFIABLE que IIS:\SslBindings)
        Write-Host "  [5/6] Vinculando certificado con netsh..." -ForegroundColor Yellow

        # Obtener GUID de la app IIS
        $appGuid = [guid]::NewGuid().ToString("B")

        # Eliminar binding anterior si existe
        netsh http delete sslcert ipport=0.0.0.0:$Puerto 2>$null | Out-Null

        # Agregar binding nuevo
        $netshOut = netsh http add sslcert ipport=0.0.0.0:$Puerto `
            certhash=$thumbprint `
            appid="$appGuid" `
            certstorename=MY 2>&1
        Write-Host "  netsh: $netshOut" -ForegroundColor DarkGray

        # Tambien intentar via PowerShell como respaldo
        try {
            $bindPath = "IIS:\SslBindings\0.0.0.0!$Puerto"
            if (Test-Path $bindPath) { Remove-Item $bindPath -Force -ErrorAction SilentlyContinue }
            $cert | New-Item $bindPath -Force -ErrorAction SilentlyContinue | Out-Null
        } catch {
            Write-Host "  (IIS:\SslBindings fallback ignorado, netsh ya lo hizo)" -ForegroundColor DarkGray
        }

        # Firewall
        New-NetFirewallRule -DisplayName "IIS HTTPS $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow `
            -ErrorAction SilentlyContinue | Out-Null

        Escribir-Resumen "[OK] IIS HTTPS puerto $Puerto"

    } else {
        # PASO 5 HTTP: Crear sitio HTTP con appcmd
        Write-Host "  [4/6] Creando sitio HTTP con appcmd..." -ForegroundColor Yellow
        & $appcmd add site /name:"$siteName" `
            /physicalPath:"$sitePath" `
            /bindings:"http/*:${Puerto}:" 2>&1 | ForEach-Object {
                Write-Host "    appcmd: $_" -ForegroundColor DarkGray
            }

        Start-Sleep -Seconds 2

        # Verificar y fallback
        $siteCheck = & $appcmd list site /site.name:"$siteName" 2>$null
        if (-not $siteCheck) {
            Write-Host "  [!] appcmd no creo el sitio. Intentando con New-Website..." -ForegroundColor Yellow
            try {
                New-Website -Name $siteName -Port $Puerto -PhysicalPath $sitePath -Force -ErrorAction Stop | Out-Null
            } catch {
                Write-Host "  [!] New-Website fallo: $_" -ForegroundColor Red
                return
            }
        }

        Write-Host "  [5/6] Sin SSL - nada que vincular." -ForegroundColor DarkGray

        # Firewall
        New-NetFirewallRule -DisplayName "IIS HTTP $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow `
            -ErrorAction SilentlyContinue | Out-Null

        Escribir-Resumen "[OK] IIS HTTP puerto $Puerto"
    }

    # PASO 6: Arrancar sitio y pool
    Write-Host "  [6/6] Arrancando sitio '$siteName'..." -ForegroundColor Yellow

    # Arrancar Application Pool
    $poolName = (Get-Website -Name $siteName -ErrorAction SilentlyContinue).ApplicationPool
    if (-not $poolName) { $poolName = "DefaultAppPool" }
    Start-WebAppPool -Name $poolName -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # Arrancar sitio por 3 metodos
    Start-Website -Name $siteName -ErrorAction SilentlyContinue
    & $appcmd start site /site.name:"$siteName" 2>&1 | Out-Null
    Start-Sleep -Seconds 3

    # Verificar estado
    $estado = (Get-Website -Name $siteName -ErrorAction SilentlyContinue).State
    Write-Host "  Estado del sitio: $estado" -ForegroundColor DarkGray

    # Esperar puerto
    $ok = Esperar-Puerto -Puerto $Puerto -intentos 30

    if ($ok) {
        $protoLower = $proto.ToLower()
        Write-Host ""
        Write-Host "  ================================================" -ForegroundColor Green
        Write-Host "  [OK] IIS CORRIENDO EXITOSAMENTE" -ForegroundColor Green
        Write-Host "  Protocolo : $proto" -ForegroundColor Green
        Write-Host "  Puerto    : $Puerto" -ForegroundColor Green
        Write-Host "  URL       : ${protoLower}://192.168.56.102:$Puerto" -ForegroundColor Green
        Write-Host "  ================================================" -ForegroundColor Green
    } else {
        Write-Host ""
        Write-Host "  [!] Puerto $Puerto no responde. Diagnostico:" -ForegroundColor Red

        Write-Host "  --- Sitios ---" -ForegroundColor Yellow
        Get-Website -ErrorAction SilentlyContinue | ForEach-Object {
            Write-Host "      $($_.Name) -> $($_.State)" -ForegroundColor Yellow
        }
        Write-Host "  --- Pools ---" -ForegroundColor Yellow
        Get-WebConfiguration "system.applicationHost/applicationPools/add" |
            ForEach-Object { Write-Host "      $($_.name) -> $($_.state)" -ForegroundColor Yellow }
        Write-Host "  --- netstat puerto $Puerto ---" -ForegroundColor Yellow
        netstat -ano 2>$null | Select-String ":$Puerto " |
            ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }

        Write-Host ""
        Write-Host "  Abre IIS Manager y verifica que '$siteName' este en Started." -ForegroundColor Cyan
    }
}

# =============================================================================
# INSTALAR IIS FTP - SIN CAMBIOS
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
# NAVEGAR / DESCARGAR POR FTP - SIN CAMBIOS
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