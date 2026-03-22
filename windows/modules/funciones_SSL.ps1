# =============================================================================
# funciones_ssl.ps1  -  Servidores HTTP/HTTPS con puerto elegible
# VERSION CORREGIDA: limpieza SELECTIVA para no matar servidores ya activos
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
# LIMPIAR SOLO APACHE  (no toca Nginx ni IIS)
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
    Remove-Item -Path "$env:APPDATA\Apache24" -Recurse -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
}

# =============================================================================
# LIMPIAR SOLO NGINX  (no toca Apache ni IIS)
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
# LIMPIAR SOLO IIS  (no toca Apache ni Nginx)
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
# ESPERAR A QUE UN PUERTO ESTE EN ESCUCHA
# Reintenta hasta $intentos veces con pausa de 1 segundo entre cada intento.
# Devuelve $true si el puerto responde, $false si se agoto el tiempo.
# =============================================================================
function Esperar-Puerto {
    param([int]$Puerto, [int]$intentos = 15)
    Write-Host "  Esperando que el puerto $Puerto quede activo..." -ForegroundColor DarkGray
    for ($i = 0; $i -lt $intentos; $i++) {
        Start-Sleep -Seconds 1
        $activo = netstat -ano 2>$null | Select-String ":$Puerto "
        if ($activo) {
            Write-Host "  [OK] Puerto $Puerto escuchando." -ForegroundColor Green
            return $true
        }
    }
    Write-Host "  [!] Puerto $Puerto no respondio en $intentos segundos." -ForegroundColor Red
    return $false
}

# =============================================================================
# INSTALAR APACHE
# Limpia SOLO Apache antes de instalar.
# No toca Nginx ni IIS aunque esten corriendo.
# =============================================================================
function Instalar-Apache {
    Write-Host "`n--- INSTALANDO APACHE (puerto fijo 443 + SSL) ---" -ForegroundColor Cyan
    Limpiar-Apache

    $apacheDir = "C:\Apache24"
    $chocoExe  = "C:\ProgramData\chocolatey\bin\choco.exe"

    Write-Host "1) Descargar de la Web (Chocolatey)"
    Write-Host "2) Descargar del FTP (Privado)"
    $origen = Read-Host "Selecciona el origen"

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

    if ($origen -eq "1") {
        if (-not (Test-Path $chocoExe)) {
            Set-ExecutionPolicy Bypass -Scope Process -Force
            Invoke-Expression ((New-Object System.Net.WebClient).DownloadString(
                "https://community.chocolatey.org/install.ps1"))
        }
        & $chocoExe install apache-httpd -y --force --params "/NoService" --limit-output

        $tempDir = ""
        foreach ($ruta in @("C:\tools\apache24","$env:APPDATA\Apache24","C:\Apache24")) {
            if (Test-Path $ruta) { $tempDir = $ruta; break }
        }
        if (-not $tempDir) {
            Write-Host "Error: instalacion Choco fallo." -ForegroundColor Red
            return
        }
        if ($tempDir -ne "C:\Apache24") {
            if (Test-Path "C:\Apache24") { Remove-Item "C:\Apache24" -Recurse -Force }
            Move-Item -Path $tempDir -Destination "C:\Apache24" -Force
        }
    } else {
        $rutaZip = Navegar-Descargar-FTP -Servicio "Apache"
        if (-not $rutaZip) { return }
        Expand-Archive -Path $rutaZip -DestinationPath "C:\" -Force
    }

    # Generar certificado SSL
    Write-Host "Generando certificado SSL para www.reprobados.com..." -ForegroundColor Cyan
    $env:OPENSSL_CONF = "$apacheDir\conf\openssl.cnf"
    Set-Location "$apacheDir\bin"
    .\openssl.exe req -x509 -nodes -newkey rsa:2048 `
        -keyout "$apacheDir\conf\server.key" `
        -out    "$apacheDir\conf\server.crt" `
        -days 365 -subj "/CN=www.reprobados.com"
    Set-Location "C:\"

    # =========================================================
    # DETECTAR MODULOS REALES que existen en esta instalacion
    # Cada version de Apache puede tener nombres distintos.
    # Leemos el httpd.conf ORIGINAL para obtener los LoadModule
    # que el propio instalador sabe que existen, y solo cambiamos
    # las rutas y agregamos los modulos SSL que necesitamos.
    # =========================================================
    $confPath    = "$apacheDir\conf\httpd.conf"
    $confOriginal = Get-Content $confPath -Raw

    Write-Host "  Leyendo modulos del httpd.conf original..." -ForegroundColor DarkGray

    # Extraer todas las lineas LoadModule del original (las que NO estan comentadas)
    $loadMods = ($confOriginal -split "`n") | Where-Object {
        $_ -match "^\s*LoadModule\s"
    }

    # Modulos SSL extra que necesitamos agregar si no estan ya
    $modosRequeridos = @(
        "mod_ssl.so",
        "mod_socache_shmcb.so",
        "mod_rewrite.so",
        "mod_headers.so"
    )
    foreach ($mod in $modosRequeridos) {
        $yaEsta = $loadMods | Where-Object { $_ -match $mod }
        if (-not $yaEsta) {
            $nombre = $mod -replace "mod_","" -replace "\.so",""
            $linea  = "LoadModule ${nombre}_module modules/$mod"
            if (Test-Path "$apacheDir\modules\$mod") {
                $loadMods += $linea
                Write-Host "  [+] Agregado: $linea" -ForegroundColor DarkGray
            }
        }
    }

    $loadModsStr = $loadMods -join "`r`n"

    # Construir el httpd.conf final con rutas correctas
    $conf = @"
ServerRoot "C:/Apache24"
Listen 80
Listen 443
ServerName localhost:80

$loadModsStr

TypesConfig conf/mime.types
DocumentRoot "C:/Apache24/htdocs"
<Directory "C:/Apache24/htdocs">
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>

ErrorLog "logs/error.log"
LogLevel warn
CustomLog "logs/access.log" common

SSLCipherSuite HIGH:MEDIUM:!MD5:!RC4:!3DES
SSLProtocol all -SSLv3
SSLPassPhraseDialog builtin
SSLSessionCache "shmcb:C:/Apache24/logs/ssl_scache(512000)"
SSLSessionCacheTimeout 300

<VirtualHost *:80>
    ServerName www.reprobados.com
    RewriteEngine On
    RewriteCond %{HTTPS} off
    RewriteRule ^(.*)$ https://%{HTTP_HOST}:443%{REQUEST_URI} [L,R=301]
</VirtualHost>

<VirtualHost _default_:443>
    DocumentRoot "C:/Apache24/htdocs"
    ServerName www.reprobados.com:443
    ErrorLog    "C:/Apache24/logs/error.log"
    TransferLog "C:/Apache24/logs/access.log"
    SSLEngine on
    SSLCertificateFile    "C:/Apache24/conf/server.crt"
    SSLCertificateKeyFile "C:/Apache24/conf/server.key"
    Header always set Strict-Transport-Security "max-age=31536000; includeSubDomains"
</VirtualHost>
"@

    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($confPath, $conf, $utf8NoBom)
    Write-Host "  [OK] httpd.conf escrito." -ForegroundColor DarkGray

    # Validar antes de lanzar
    Write-Host "  Validando httpd.conf..." -ForegroundColor DarkGray
    $testOut = & "$apacheDir\bin\httpd.exe" -t 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] Error en httpd.conf:" -ForegroundColor Red
        $testOut | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        return
    }
    Write-Host "  [OK] httpd.conf valido." -ForegroundColor Green

    # index.html
    $html = @"
<html>
<body style='font-family:Arial;text-align:center;background-color:#27ae60;color:white;padding-top:50px;'>
  <div style='background:rgba(0,0,0,0.5);display:inline-block;padding:40px;border-radius:20px;border:3px solid white;'>
    <h1>SERVIDOR WEB: APACHE</h1>
    <hr style='width:80%;margin:20px auto;'>
    <p><b>Protocolo:</b> HTTPS (Seguro)</p>
    <p><b>Puerto:</b> 443</p>
    <p>www.reprobados.com</p>
  </div>
</body>
</html>
"@
    Set-Content -Path "$apacheDir\htdocs\index.html" -Value $html -Force

    # Firewall
    New-NetFirewallRule -DisplayName "Apache HTTP 80"   -Direction Inbound `
        -LocalPort 80  -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName "Apache HTTPS 443" -Direction Inbound `
        -LocalPort 443 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

    # Lanzar
    # Verificar si el puerto 443 ya esta ocupado (IIS u otro)
    $p443 = netstat -ano 2>$null | Select-String ":443 "
    if ($p443) {
        Write-Host "  [!] PUERTO 443 YA OCUPADO. Mostrando quien lo usa:" -ForegroundColor Red
        $p443 | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        Write-Host "  Sugerencia: instala IIS primero en otro puerto (ej. 8443)" -ForegroundColor Yellow
        Write-Host "  o detente en IIS y ejecuta Apache de nuevo." -ForegroundColor Yellow
        return
    }

    # Verificar VCRUNTIME140.dll (Apache lo necesita para arrancar)
    $vcDll = Get-ChildItem "C:\Windows\System32\VCRUNTIME140.dll" -ErrorAction SilentlyContinue
    if (-not $vcDll) {
        Write-Host "  [!] Falta VCRUNTIME140.dll. Instalando VC++ Redistributable..." -ForegroundColor Yellow
        $vcUrl = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
        $vcExe = "$env:TEMPc_redist.x64.exe"
        try {
            Invoke-WebRequest -Uri $vcUrl -OutFile $vcExe -UseBasicParsing -ErrorAction Stop
            Start-Process -FilePath $vcExe -ArgumentList "/install /quiet /norestart" -Wait
            Remove-Item $vcExe -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] VC++ Redistributable instalado." -ForegroundColor Green
        } catch {
            Write-Host "  [!] No se pudo instalar VC++. Apache puede fallar." -ForegroundColor Red
        }
    }

    Write-Host "Iniciando Apache en puerto 443..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath "$apacheDir\bin\httpd.exe" -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 3

    if ($proc.HasExited) {
        Write-Host "  [!] Apache termino de inmediato." -ForegroundColor Red
        Write-Host "  --- error.log ---" -ForegroundColor Yellow
        if (Test-Path "$apacheDir\logs\error.log") {
            Get-Content "$apacheDir\logs\error.log" -Tail 25 |
                ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        } else {
            Write-Host "      (error.log no existe - falla antes de iniciar)" -ForegroundColor Red
            Write-Host "      Causa probable: VCRUNTIME140.dll faltante o puerto 443 ocupado" -ForegroundColor Red
        }
        # Intentar lanzar en modo consola para ver el error directo
        Write-Host "  --- Salida directa de httpd.exe ---" -ForegroundColor Yellow
        $directOut = & "$apacheDir\bin\httpd.exe" 2>&1
        $directOut | Select-Object -First 10 | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        return
    }

    $ok = Esperar-Puerto -Puerto 443 -intentos 15
    if ($ok) {
        Write-Host "[OK] Apache corriendo en https://192.168.56.102" -ForegroundColor Green
        Escribir-Resumen "[OK] Apache: HTTPS puerto 443 (HTTP 80 redirige)."
    } else {
        Write-Host "[!] Apache inicio pero el puerto 443 no responde." -ForegroundColor Red
        Get-Content "$apacheDir\logs\error.log" -Tail 20 -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
    }
}

# =============================================================================
# INSTALAR NGINX
# Limpia SOLO Nginx antes de instalar.
# No toca Apache ni IIS aunque esten corriendo.
# =============================================================================
function Instalar-Nginx {
    Write-Host "`n--- INSTALANDO NGINX ---" -ForegroundColor Cyan
    Limpiar-Nginx

    $Puerto = Obtener-Puerto -Servicio "Nginx"
    Write-Host "  [OK] Puerto elegido: $Puerto" -ForegroundColor DarkGray

    Write-Host "1) Descargar de la Web (Chocolatey)"
    Write-Host "2) Descargar del FTP (Privado)"
    $origen = Read-Host "Selecciona el origen"

    $nginxDir      = "C:\nginx"
    $chocoExe      = "C:\ProgramData\chocolatey\bin\choco.exe"
    $viejoProgreso = $ProgressPreference
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
            $found = Get-ChildItem -Path $ruta -Filter "nginx-*" -Directory -ErrorAction SilentlyContinue |
                     Select-Object -First 1
            if (-not $found) {
                $found = Get-ChildItem -Path $ruta -Filter "nginx" -Directory -ErrorAction SilentlyContinue |
                         Select-Object -First 1
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
        if (-not $rutaZip) {
            $ProgressPreference = $viejoProgreso
            return
        }
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

        # FIX: si el puerto 80 ya esta ocupado (por IIS u otro proceso),
        # Nginx no puede abrirlo y muere con error 10013 (permission/address in use).
        # Detectamos si 80 esta libre antes de agregar el bloque de redireccion.
        $puerto80Libre = -not (netstat -ano 2>$null | Select-String ":80 ")

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
            Write-Host "  [!] Puerto 80 ocupado por otro servicio. Nginx usara solo HTTPS en $Puerto." -ForegroundColor Yellow
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
            Escribir-Resumen "[OK] Nginx: HTTPS solo en puerto $Puerto (80 ocupado por otro servicio)."
        }
        $protocolo = "HTTPS (Seguro)"
        $bgColor   = "#115c2a"

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
        $protocolo = "HTTP (Inseguro)"
        $bgColor   = "#2c3e50"

        New-NetFirewallRule -DisplayName "Nginx HTTP $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    }

    # Escribir nginx.conf sin BOM (Nginx falla con BOM)
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText("$nginxDir\conf\nginx.conf", $nginxConf, $utf8NoBom)

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
    <p><b>Version:</b> $version</p>
    <p><b>Protocolo:</b> $protocolo</p>
    <p><b>Puerto:</b> $Puerto</p>
    <p>Configuracion para www.reprobados.com</p>
  </div>
</body>
</html>
"@
    Set-Content -Path "$nginxDir\html\index.html" -Value $html -Force

    # Validar config antes de lanzar
    $test = & "$nginxDir\nginx.exe" -t -p "$nginxDir" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] nginx.conf invalido:" -ForegroundColor Red
        $test | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        $ProgressPreference = $viejoProgreso
        return
    }

    Write-Host "Iniciando Nginx en puerto $Puerto..." -ForegroundColor Cyan
    $proc = Start-Process -FilePath "$nginxDir\nginx.exe" -WorkingDirectory $nginxDir -PassThru
    Start-Sleep -Seconds 2

    if ($proc.HasExited) {
        Write-Host "  [!] Nginx termino de inmediato." -ForegroundColor Red
        Get-Content "$nginxDir\logs\error.log" -Tail 5 -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        $ProgressPreference = $viejoProgreso
        return
    }

    $ok = Esperar-Puerto -Puerto $Puerto -intentos 15
    if ($ok) {
        Write-Host "[OK] Nginx corriendo. Abre: http://192.168.56.102:$Puerto" -ForegroundColor Green
    } else {
        Write-Host "[!] Nginx inicio pero el puerto $Puerto no responde." -ForegroundColor Red
        Write-Host "    Revisa: $nginxDir\logs\error.log" -ForegroundColor Yellow
    }

    $ProgressPreference = $viejoProgreso
}

# =============================================================================
# INSTALAR IIS WEB
# Limpia SOLO sitios IIS anteriores.
# No toca Apache ni Nginx.
# =============================================================================
function Instalar-IIS-Web {
    Write-Host "`n--- INSTALANDO IIS WEB ---" -ForegroundColor Cyan
    Limpiar-IIS

    $Puerto = Obtener-Puerto -Servicio "IIS"
    Write-Host "  [OK] Puerto elegido: $Puerto" -ForegroundColor DarkGray

    Write-Host "Instalando caracteristicas base de IIS..."
    Install-WindowsFeature -name Web-Server -IncludeManagementTools | Out-Null
    Start-Service -Name "W3SVC" -ErrorAction SilentlyContinue
    Start-Service -Name "WAS"   -ErrorAction SilentlyContinue

    Import-Module WebAdministration -ErrorAction SilentlyContinue

    $resSSL = Read-Host "Desea activar SSL? [S/N]"
    $isSSL  = ($resSSL -match '^[sS]$')

    # Nombre unico con puerto para poder tener varios sitios IIS simultaneos
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
            -Value "<h1>IIS Seguro (HTTPS) - Puerto $Puerto - www.reprobados.com</h1>" -Force

        Write-Host "Generando certificado SSL para www.reprobados.com..."
        $cert = New-SelfSignedCertificate -DnsName "www.reprobados.com" `
                    -CertStoreLocation "cert:\LocalMachine\My"

        New-Website -Name $siteName -Port 80 -PhysicalPath $sitePath -Force | Out-Null
        New-WebBinding -Name $siteName -Protocol "https" -Port $Puerto -IPAddress "*"

        Push-Location IIS:\SslBindings
        Remove-Item -Path "*!$Puerto" -Force -ErrorAction SilentlyContinue
        Get-Item "cert:\LocalMachine\My\$($cert.Thumbprint)" |
            New-Item -Path "*!$Puerto" -Force | Out-Null
        Pop-Location

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
        New-NetFirewallRule -DisplayName "IIS HTTP 80" -Direction Inbound `
            -LocalPort 80 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

        Escribir-Resumen "[OK] IIS: HTTPS puerto $Puerto (HTTP 80 redirige)."
    } else {
        Add-Content -Path "$sitePath\index.html" `
            -Value "<h1>IIS HTTP - Puerto $Puerto</h1>" -Force
        New-Website -Name $siteName -Port $Puerto -PhysicalPath $sitePath -Force | Out-Null

        New-NetFirewallRule -DisplayName "IIS HTTP $Puerto" -Direction Inbound `
            -LocalPort $Puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null

        Escribir-Resumen "[OK] IIS: HTTP puro puerto $Puerto."
    }

    Start-Website -Name $siteName -ErrorAction SilentlyContinue

    $ok = Esperar-Puerto -Puerto $Puerto -intentos 15
    if ($ok) {
        Write-Host "[OK] IIS corriendo. Abre: http://192.168.56.102:$Puerto" -ForegroundColor Green
    } else {
        Write-Host "[!] IIS inicio pero el puerto $Puerto no responde todavia." -ForegroundColor Yellow
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
    $existe  = $ADSI.Children | Where-Object {
        $_.SchemaClassName -eq 'User' -and $_.Name -eq $ftpUser
    }
    if (-not $existe) {
        Write-Host "El usuario $ftpUser no existe. Crealo primero con la Practica 5." -ForegroundColor Red
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
    Set-ItemProperty "IIS:\Sites\FTP_Practica7" -Name ftpServer.userIsolation.mode -Value 0
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
# NAVEGAR / DESCARGAR POR FTP
# =============================================================================
function Navegar-Descargar-FTP {
    param([string]$Servicio)
    Write-Host "--- BUSCANDO INSTALADORES DE $Servicio EN FTP ---" -ForegroundColor Cyan

    $ftpUser      = "repositorio"
    $ftpPassword  = "Hola1234."
    $urlBase      = "ftp://localhost:21/"
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

    $selVer         = Read-Host "Selecciona el numero de version"
    $archivoElegido = $archivos[[int]$selVer - 1].Trim()

    $rutaInstalador = "$dirDescargas\$archivoElegido"
    $rutaHash       = "$dirDescargas\$archivoElegido.sha256"

    curl.exe -s --show-error -k -u "${ftpUser}:${ftpPassword}" `
        "${urlVersiones}${archivoElegido}" -o $rutaInstalador
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