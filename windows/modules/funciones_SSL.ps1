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
    # IMPORTANTE: NO borrar la carpeta de Chocolatey (ProgramData)
    # Solo borramos C:\Apache24 (copia de trabajo) y C:\tools\apache24
    Remove-Item -Path "C:\Apache24"       -Recurse -Force -ErrorAction SilentlyContinue
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
# =============================================================================
# INSTALAR APACHE - SIEMPRE REINSTALA DESDE CHOCOLATEY
# =============================================================================
function Instalar-Apache {
    Write-Host "`n--- INSTALANDO APACHE (REINSTALACION FORZADA CHOCO) ---" -ForegroundColor Cyan

    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"

    # PASO 1: Matar todo lo que sea Apache
    Write-Host "  [1/6] Limpiando instalacion anterior..." -ForegroundColor Yellow
    taskkill /F /IM httpd.exe /T 2>$null | Out-Null
    foreach ($svc in @("Apache-Practica7","apache","Apache2.4","httpd")) {
        Stop-Service  -Name $svc -Force -ErrorAction SilentlyContinue
        sc.exe delete $svc 2>$null | Out-Null
    }
    Remove-Item -Path "C:\Apache24"       -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -Path "C:\tools\apache24" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    # PASO 2: Instalar/actualizar Chocolatey
    Write-Host "  [2/6] Verificando Chocolatey..." -ForegroundColor Yellow
    if (-not (Test-Path $chocoExe)) {
        Write-Host "       Instalando Chocolatey..." -ForegroundColor DarkGray
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            "https://community.chocolatey.org/install.ps1"))
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "       [OK] Chocolatey listo." -ForegroundColor Green

    # PASO 3: Desinstalar apache-httpd de choco y reinstalar forzado
    Write-Host "  [3/6] Reinstalando apache-httpd via Chocolatey (forzado)..." -ForegroundColor Yellow
    & $chocoExe uninstall apache-httpd -y --limit-output 2>$null | Out-Null
    Start-Sleep -Seconds 2
    & $chocoExe install apache-httpd -y --force --params "/NoService" --limit-output
    Write-Host "       [OK] Instalacion de Chocolatey completada." -ForegroundColor Green

    # PASO 4: Encontrar httpd.exe (Choco puede instalarlo en distintos lugares)
    Write-Host "  [4/6] Localizando httpd.exe..." -ForegroundColor Yellow
    $tempDir = ""
    $rutasBusqueda = @(
        "$env:APPDATA\Apache24",
        "C:\Apache24",
        "C:\tools\apache24",
        "C:\ProgramData\chocolatey\lib\apache-httpd\tools\Apache24",
        "C:\ProgramData\chocolatey\lib\apache-httpd\Apache24"
    )
    foreach ($ruta in $rutasBusqueda) {
        if (Test-Path "$ruta\bin\httpd.exe") { $tempDir = $ruta; break }
    }
    # Busqueda exhaustiva si no aparecio
    if (-not $tempDir) {
        $found = Get-ChildItem "C:\ProgramData\chocolatey" -Filter "httpd.exe" `
                    -Recurse -Depth 10 -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $found) {
            $found = Get-ChildItem "C:\" -Filter "httpd.exe" `
                        -Recurse -Depth 6 -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        if ($found) { $tempDir = $found.DirectoryName -replace "\\bin$","" }
    }

    if (-not $tempDir) {
        Write-Host "  [!] httpd.exe no encontrado. Revisa la instalacion de Chocolatey." -ForegroundColor Red
        return
    }
    Write-Host "       Encontrado en: $tempDir" -ForegroundColor DarkGray

    # Mover a C:\Apache24 si no esta ahi
    if ($tempDir -ne "C:\Apache24") {
        if (Test-Path "C:\Apache24") { Remove-Item "C:\Apache24" -Recurse -Force }
        Copy-Item -Path $tempDir -Destination "C:\Apache24" -Recurse -Force
    }
    Write-Host "       [OK] Apache en C:\Apache24" -ForegroundColor Green

    # PASO 5: Verificar VCRUNTIME140.dll
    if (-not (Test-Path "C:\Windows\System32\VCRUNTIME140.dll")) {
        Write-Host "  [5/6] Instalando VC++ Redistributable..." -ForegroundColor Yellow
        & $chocoExe install vcredist140 -y --limit-output
    } else {
        Write-Host "  [5/6] VCRUNTIME140.dll OK." -ForegroundColor DarkGray
    }

    # PASO 6: Configurar SSL y lanzar
    Write-Host "  [6/6] Configurando SSL y lanzando Apache..." -ForegroundColor Yellow

    # Generar certificado SSL
    $env:OPENSSL_CONF = "C:\Apache24\conf\openssl.cnf"
    Set-Location "C:\Apache24\bin"
    .\openssl.exe req -x509 -nodes -newkey rsa:2048 `
        -keyout "C:\Apache24\conf\server.key" `
        -out    "C:\Apache24\conf\server.crt" `
        -days 365 -subj "/CN=www.reprobados.com" 2>&1 | Out-Null
    Set-Location "C:\"
    Write-Host "       Certificado SSL generado." -ForegroundColor DarkGray

    # Leer LoadModules del httpd.conf original
    $confPath     = "C:\Apache24\conf\httpd.conf"
    $confOriginal = Get-Content $confPath -Raw
    $loadMods     = ($confOriginal -split "`n") | Where-Object { $_ -match "^\s*LoadModule\s" }

    foreach ($mod in @("mod_ssl.so","mod_socache_shmcb.so","mod_rewrite.so","mod_headers.so")) {
        if (-not ($loadMods | Where-Object { $_ -match $mod })) {
            if (Test-Path "C:\Apache24\modules\$mod") {
                $nombre   = $mod -replace "mod_","" -replace "\.so",""
                $loadMods += "LoadModule ${nombre}_module modules/$mod"
                Write-Host "       [+] Modulo agregado: $mod" -ForegroundColor DarkGray
            }
        }
    }
    $loadModsStr = ($loadMods | ForEach-Object { $_.TrimEnd() }) -join "`r`n"

    # Detectar si el puerto 80 esta libre
    $puerto80Libre = -not (netstat -ano 2>$null | Select-String ":80 ")
    if ($puerto80Libre) {
        $listenBlock  = "Listen 80`r`nListen 443"
        $vhost80Block = "<VirtualHost *:80>`r`n    ServerName www.reprobados.com`r`n    RewriteEngine On`r`n    RewriteCond %{HTTPS} off`r`n    RewriteRule ^(.*)$ https://%{HTTP_HOST}:443%{REQUEST_URI} [L,R=301]`r`n</VirtualHost>"
        Write-Host "       Puerto 80 libre. Apache usara 80 y 443." -ForegroundColor DarkGray
    } else {
        $listenBlock  = "Listen 443"
        $vhost80Block = ""
        Write-Host "       Puerto 80 ocupado. Apache usara solo 443." -ForegroundColor Yellow
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

    # Validar configuracion
    $testOut = & "C:\Apache24\bin\httpd.exe" -t 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] Error en httpd.conf:" -ForegroundColor Red
        $testOut | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        return
    }
    Write-Host "       [OK] httpd.conf valido." -ForegroundColor Green

    # index.html
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

    # Lanzar Apache
    $proc = Start-Process -FilePath "C:\Apache24\bin\httpd.exe" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3

    if ($proc.HasExited) {
        Write-Host "  [!] Apache termino de inmediato. Revisando error.log..." -ForegroundColor Red
        if (Test-Path "C:\Apache24\logs\error.log") {
            Get-Content "C:\Apache24\logs\error.log" -Tail 20 |
                ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        }
        return
    }

    $ok = Esperar-Puerto -Puerto 443 -intentos 15
    if ($ok) {
        Write-Host ""
        Write-Host "  ============================================" -ForegroundColor Green
        Write-Host "  [OK] APACHE CORRIENDO" -ForegroundColor Green
        Write-Host "  URL: https://192.168.56.102" -ForegroundColor Green
        Write-Host "  ============================================" -ForegroundColor Green
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
# INSTALAR NGINX - SIEMPRE REINSTALA DESDE CHOCOLATEY
# =============================================================================
function Instalar-Nginx {
    Write-Host "`n--- INSTALANDO NGINX (REINSTALACION FORZADA CHOCO) ---" -ForegroundColor Cyan

    $chocoExe = "C:\ProgramData\chocolatey\bin\choco.exe"

    # PASO 1: Matar todo lo que sea Nginx
    Write-Host "  [1/5] Limpiando instalacion anterior..." -ForegroundColor Yellow
    taskkill /F /IM nginx.exe /T 2>$null | Out-Null
    Stop-Service -Name "nginx" -Force -ErrorAction SilentlyContinue
    sc.exe delete "nginx" 2>$null | Out-Null
    Remove-Item -Path "C:\nginx" -Recurse -Force -ErrorAction SilentlyContinue
    Get-ChildItem -Path "C:\" -Filter "nginx-*" -Directory -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Write-Host "       [OK] Limpieza completada." -ForegroundColor Green

    # PASO 2: Verificar Chocolatey
    Write-Host "  [2/5] Verificando Chocolatey..." -ForegroundColor Yellow
    if (-not (Test-Path $chocoExe)) {
        Set-ExecutionPolicy Bypass -Scope Process -Force
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
            'https://community.chocolatey.org/install.ps1'))
    }
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Write-Host "       [OK] Chocolatey listo." -ForegroundColor Green

    # PASO 3: Desinstalar y reinstalar Nginx forzado
    Write-Host "  [3/5] Reinstalando nginx via Chocolatey (forzado)..." -ForegroundColor Yellow
    & $chocoExe uninstall nginx -y --limit-output 2>$null | Out-Null
    Start-Sleep -Seconds 2
    & $chocoExe install nginx -y --force --limit-output
    Stop-Service -Name "nginx" -Force -ErrorAction SilentlyContinue
    sc.exe delete "nginx" 2>$null | Out-Null
    Write-Host "       [OK] Instalacion de Chocolatey completada." -ForegroundColor Green

    # Localizar la carpeta de nginx
    $nginxDir = ""
    foreach ($ruta in @("C:\tools\nginx","C:\nginx","$env:ProgramData\chocolatey\lib\nginx\tools\nginx")) {
        if (Test-Path "$ruta\nginx.exe") { $nginxDir = $ruta; break }
    }
    if (-not $nginxDir) {
        $found = Get-ChildItem "C:\" -Filter "nginx.exe" -Recurse -Depth 6 -ErrorAction SilentlyContinue |
                 Select-Object -First 1
        if ($found) { $nginxDir = $found.DirectoryName }
    }
    if (-not $nginxDir) {
        Write-Host "  [!] nginx.exe no encontrado tras instalacion." -ForegroundColor Red
        return
    }
    # Mover a C:\nginx si no esta ahi
    if ($nginxDir -ne "C:\nginx") {
        if (Test-Path "C:\nginx") { Remove-Item "C:\nginx" -Recurse -Force }
        Copy-Item -Path $nginxDir -Destination "C:\nginx" -Recurse -Force
        $nginxDir = "C:\nginx"
    }
    Write-Host "       Nginx en: $nginxDir" -ForegroundColor DarkGray

    # PASO 4: Pedir puerto y SSL
    Write-Host "  [4/5] Configuracion del servidor..." -ForegroundColor Yellow
    $Puerto = Obtener-Puerto -Servicio "Nginx"
    Write-Host "       Puerto elegido: $Puerto" -ForegroundColor DarkGray

    $resSSL = Read-Host "  Desea activar SSL? [S/N]"
    $isSSL  = ($resSSL -match '^[sS]$')

    # Generar certificado si SSL
    if ($isSSL) {
        $opensslExe = "C:\Program Files\OpenSSL-Win64\bin\openssl.exe"
        if (-not (Test-Path $opensslExe)) {
            & $chocoExe install openssl -y --limit-output *>$null
        }
        if (-not (Test-Path "$nginxDir\conf")) {
            New-Item -ItemType Directory -Path "$nginxDir\conf" -Force | Out-Null
        }
        $env:OPENSSL_CONF = "C:\Program Files\OpenSSL-Win64\bin\openssl.cfg"
        & $opensslExe req -x509 -nodes -newkey rsa:2048 `
            -keyout "$nginxDir\conf\server.key" `
            -out    "$nginxDir\conf\server.crt" `
            -days 365 -subj "/CN=www.reprobados.com" 2>&1 | Out-Null
        Write-Host "       Certificado SSL generado." -ForegroundColor DarkGray
    }

    # Construir nginx.conf
    $puerto80Libre = -not (netstat -ano 2>$null | Select-String ":80 ")

    if ($isSSL) {
        if ($puerto80Libre) {
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
        ssl_certificate     C:/nginx/conf/server.crt;
        ssl_certificate_key C:/nginx/conf/server.key;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        location / { root html; index index.html index.htm; }
    }
}
"@
            New-NetFirewallRule -DisplayName "Nginx HTTP 80" -Direction Inbound `
                -LocalPort 80 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
            Escribir-Resumen "[OK] Nginx: HTTPS puerto $Puerto (HTTP 80 redirige)."
        } else {
            Write-Host "       Puerto 80 ocupado. Nginx usara solo HTTPS en $Puerto." -ForegroundColor Yellow
            $nginxConf = @"
worker_processes 1;
events { worker_connections 1024; }
http {
    include      mime.types;
    default_type application/octet-stream;
    sendfile on;
    keepalive_timeout 65;
    server {
        listen ${Puerto} ssl;
        server_name www.reprobados.com;
        ssl_certificate     C:/nginx/conf/server.crt;
        ssl_certificate_key C:/nginx/conf/server.key;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        location / { root html; index index.html index.htm; }
    }
}
"@
            Escribir-Resumen "[OK] Nginx: HTTPS solo en puerto $Puerto."
        }
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
        New-NetFirewallRule -DisplayName "Nginx HTTP $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Escribir-Resumen "[OK] Nginx: HTTP puro puerto $Puerto."
    }

    # Escribir nginx.conf sin BOM
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$nginxDir\conf\nginx.conf", $nginxConf, $utf8NoBom)

    # index.html
    if (-not (Test-Path "$nginxDir\html")) { New-Item -ItemType Directory -Path "$nginxDir\html" -Force | Out-Null }
    $proto   = if ($isSSL) { "HTTPS (Seguro)" } else { "HTTP" }
    $bgColor = if ($isSSL) { "#115c2a" } else { "#2c3e50" }
    @"
<html><body style='font-family:Arial;text-align:center;background-color:${bgColor};color:white;padding-top:50px;'>
<div style='background:rgba(0,0,0,0.5);display:inline-block;padding:40px;border-radius:20px;border:3px solid white;'>
<h1>SERVIDOR WEB: NGINX</h1><hr style='width:80%;margin:20px auto;'>
<p><b>Protocolo:</b> $proto</p><p><b>Puerto:</b> $Puerto</p>
<p>www.reprobados.com</p></div></body></html>
"@ | Set-Content "$nginxDir\html\index.html" -Force

    # Validar configuracion
    $test = & "$nginxDir\nginx.exe" -t -p "$nginxDir" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] nginx.conf invalido:" -ForegroundColor Red
        $test | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        return
    }
    Write-Host "       [OK] nginx.conf valido." -ForegroundColor Green

    # PASO 5: Lanzar Nginx
    Write-Host "  [5/5] Lanzando Nginx en puerto $Puerto..." -ForegroundColor Yellow
    $proc = Start-Process -FilePath "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -PassThru
    Start-Sleep -Seconds 2

    if ($proc.HasExited) {
        Write-Host "  [!] Nginx termino de inmediato." -ForegroundColor Red
        if (Test-Path "$nginxDir\logs\error.log") {
            Get-Content "$nginxDir\logs\error.log" -Tail 10 |
                ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        }
        return
    }

    $ok = Esperar-Puerto -Puerto $Puerto -intentos 15
    if ($ok) {
        Write-Host ""
        Write-Host "  ============================================" -ForegroundColor Green
        Write-Host "  [OK] NGINX CORRIENDO" -ForegroundColor Green
        $protoLow = if ($isSSL) { "https" } else { "http" }
        Write-Host "  URL: ${protoLow}://192.168.56.102:$Puerto" -ForegroundColor Green
        Write-Host "  ============================================" -ForegroundColor Green
    } else {
        Write-Host "  [!] Nginx no responde en puerto $Puerto." -ForegroundColor Red
        if (Test-Path "$nginxDir\logs\error.log") {
            Get-Content "$nginxDir\logs\error.log" -Tail 10 |
                ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        }
    }
}

function Instalar-IIS-Web {
    Write-Host "`n--- INSTALANDO IIS WEB (REINSTALACION FORZADA) ---" -ForegroundColor Cyan

    # =========================================================
    # PASO 1: DESINSTALAR IIS COMPLETAMENTE Y REINSTALAR
    # =========================================================
    Write-Host "  [1/7] Desinstalando IIS completamente..." -ForegroundColor Yellow
    iisreset /stop 2>&1 | Out-Null
    Stop-Service -Name W3SVC,WAS -Force -ErrorAction SilentlyContinue
    Uninstall-WindowsFeature -Name Web-Server -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
    Start-Sleep -Seconds 3

    Write-Host "  [2/7] Reinstalando IIS limpio..." -ForegroundColor Yellow
    Install-WindowsFeature -Name Web-Server,Web-Common-Http,Web-Static-Content,`
Web-Http-Logging,Web-Security,Web-Mgmt-Console -IncludeManagementTools | Out-Null
    Start-Sleep -Seconds 5

    Write-Host "  [3/7] Arrancando servicios IIS..." -ForegroundColor Yellow
    Start-Service -Name WAS   -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3
    Start-Service -Name W3SVC -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    Import-Module WebAdministration -Force -ErrorAction Stop

    # =========================================================
    # PASO 2: PEDIR CONFIGURACION AL USUARIO
    # =========================================================
    $Puerto   = Obtener-Puerto -Servicio "IIS"
    $resSSL   = Read-Host "  Desea activar SSL? [S/N]"
    $isSSL    = ($resSSL -match '^[sS]$')
    $siteName = "SitioIIS_Practica7_$Puerto"
    $sitePath = "C:\inetpub\wwwroot\$siteName"

    Write-Host "  [OK] Puerto: $Puerto  |  SSL: $isSSL" -ForegroundColor DarkGray

    # =========================================================
    # PASO 3: DETENER DEFAULT WEB SITE
    # =========================================================
    Write-Host "  [4/7] Deteniendo Default Web Site..." -ForegroundColor Yellow
    if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
        Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
    }

    # =========================================================
    # PASO 4: CREAR CARPETA Y CONTENIDO WEB
    # =========================================================
    if (Test-Path $sitePath) { Remove-Item $sitePath -Recurse -Force }
    New-Item -ItemType Directory -Path $sitePath -Force | Out-Null

    $proto = if ($isSSL) { "HTTPS" } else { "HTTP" }
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

    # =========================================================
    # PASO 5: CREAR SITIO IIS
    # =========================================================
    Write-Host "  [5/7] Creando sitio IIS '$siteName'..." -ForegroundColor Yellow

    if ($isSSL) {
        # Generar certificado autofirmado
        Write-Host "       Generando certificado SSL..." -ForegroundColor DarkGray
        $cert = New-SelfSignedCertificate `
            -DnsName "www.reprobados.com","reprobados.com","localhost" `
            -CertStoreLocation "cert:\LocalMachine\My" `
            -NotAfter (Get-Date).AddYears(1)
        Write-Host "       Thumbprint: $($cert.Thumbprint)" -ForegroundColor DarkGray

        # Crear sitio en puerto HTTPS directo (sin puerto temporal)
        New-Website -Name $siteName -Port $Puerto -PhysicalPath $sitePath `
            -Ssl -Force | Out-Null

        # Vincular certificado
        $bindPath = "IIS:\SslBindings\0.0.0.0!$Puerto"
        if (Test-Path $bindPath) { Remove-Item $bindPath -Force }
        $cert | New-Item $bindPath -Force | Out-Null
        Write-Host "       Certificado vinculado al puerto $Puerto" -ForegroundColor DarkGray

        # Firewall
        New-NetFirewallRule -DisplayName "IIS HTTPS $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow `
            -ErrorAction SilentlyContinue | Out-Null

        Escribir-Resumen "[OK] IIS HTTPS puerto $Puerto"

    } else {
        New-Website -Name $siteName -Port $Puerto -PhysicalPath $sitePath -Force | Out-Null

        New-NetFirewallRule -DisplayName "IIS HTTP $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow `
            -ErrorAction SilentlyContinue | Out-Null

        Escribir-Resumen "[OK] IIS HTTP puerto $Puerto"
    }

    # =========================================================
    # PASO 6: ARRANCAR SITIO Y APPLICATION POOL
    # =========================================================
    Write-Host "  [6/7] Arrancando sitio y Application Pool..." -ForegroundColor Yellow

    # Arrancar el Application Pool
    $poolName = (Get-Website -Name $siteName -ErrorAction SilentlyContinue).ApplicationPool
    if ($poolName) {
        Start-WebAppPool -Name $poolName -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        Write-Host "       Pool '$poolName' iniciado." -ForegroundColor DarkGray
    }

    # Arrancar el sitio por 3 métodos distintos
    Start-Website -Name $siteName -ErrorAction SilentlyContinue
    Start-WebItem  "IIS:\Sites\$siteName" -ErrorAction SilentlyContinue
    $appcmd = "$env:SystemRoot\system32\inetsrv\appcmd.exe"
    if (Test-Path $appcmd) {
        & $appcmd start site /site.name:"$siteName" 2>&1 | Out-Null
    }

    Start-Sleep -Seconds 3

    # Mostrar estado del sitio
    $estado = (Get-Website -Name $siteName -ErrorAction SilentlyContinue).State
    Write-Host "       Estado del sitio: $estado" -ForegroundColor DarkGray

    # =========================================================
    # PASO 7: VERIFICAR PUERTO
    # =========================================================
    Write-Host "  [7/7] Verificando puerto $Puerto..." -ForegroundColor Yellow
    $ok = Esperar-Puerto -Puerto $Puerto -intentos 30

    if ($ok) {
        Write-Host ""
        Write-Host "  ================================================" -ForegroundColor Green
        Write-Host "  [OK] IIS CORRIENDO EXITOSAMENTE" -ForegroundColor Green
        Write-Host "  Protocolo : $proto" -ForegroundColor Green
        Write-Host "  Puerto    : $Puerto" -ForegroundColor Green
        $protoLower = $proto.ToLower()
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