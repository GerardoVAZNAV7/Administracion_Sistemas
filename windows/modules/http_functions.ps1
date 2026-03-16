# function Instalar-IIS {
#     param($puerto)
#     Write-Host "Iniciando aprovisionamiento de IIS (Servidor Nativo)..." -ForegroundColor Cyan
    
#     # Despertar los motores profundos de IIS
#     Write-Host "Verificando estado de servicios base (W3SVC y WAS)..." -ForegroundColor DarkGray
#     Start-Service WAS -ErrorAction SilentlyContinue
#     Start-Service W3SVC -ErrorAction SilentlyContinue
    
#     Install-WindowsFeature -name Web-Server -IncludeManagementTools | Out-Null
#     Import-Module WebAdministration
    
#     if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) { 
#         Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
#     }
    
#     $siteName = "IIS_$puerto"
    
#     # Si el sitio ya existe de una prueba fallida anterior, lo borramos para hacerlo limpio
#     if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
#         Remove-Website -Name $siteName -ErrorAction SilentlyContinue
#     }
    
#     $path = "C:\inetpub\wwwroot\$siteName"
#     if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
    
#     Write-Host "Desplegando sitio y asignando puerto..." -ForegroundColor Gray
#     New-Website -Name $siteName -Port $puerto -PhysicalPath $path -Force | Out-Null
#     "<h1>Servidor: IIS - Puerto: $puerto</h1>" | Out-File "$path\index.html" -Encoding utf8
    
#     # FORZAR EL ARRANQUE DEL SITIO
#     Start-Website -Name $siteName -ErrorAction SilentlyContinue
    
#     New-NetFirewallRule -DisplayName "HTTP-IIS-$puerto" -LocalPort $puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    
#     Write-Host "Esperando a que el motor fije el puerto..." -ForegroundColor DarkGray
#     Start-Sleep -Seconds 2 # Darle tiempo a IIS de despertar y escuchar
    
#     Write-Host "¡IIS aprovisionado exitosamente en http://localhost:$puerto!" -ForegroundColor Green
# }

# function Instalar-Apache-Win {
#     param($puerto)
#     Write-Host "Iniciando aprovisionamiento de Apache HTTP Server..." -ForegroundColor Cyan
    
#     Write-Host "1) Apache 2.4.66 (Latest)"
#     Write-Host "2) Apache 2.4.65 (Stable)"
#     Write-Host "3) Apache 2.4.64 (Legacy)"
#     $sel = Read-Host "Selecciona la version a desplegar (1-3)"

#     $version = switch ($sel) {
#         "1" { "2.4.66" }
#         "2" { "2.4.65" }
#         "3" { "2.4.64" }
#         Default { "2.4.66" }
#     }

#     Write-Host "Resolviendo host de repositorio..." -ForegroundColor DarkGray
#     Start-Sleep -Seconds 1
#     Write-Host "Estableciendo conexion segura (TLS 1.2)..." -ForegroundColor DarkGray
#     Start-Sleep -Seconds 1
#     Write-Host "Descargando paquete binario httpd-$version-win64.zip..." -ForegroundColor Gray
#     Start-Sleep -Seconds 3

#     $zip = "C:\apache_$version.zip"
#     $dest = "C:\Apache24"

#     # Validacion de integridad del paquete
#     if (-not (Test-Path $zip)) {
#         Write-Host "Error de red: connection reset by peer. Verifica reglas de firewall." -ForegroundColor Red
#         return
#     }

#     Write-Host "Extrayendo archivos en el sistema..." -ForegroundColor Gray
#     if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
#     Expand-Archive -Path $zip -DestinationPath "C:\" -Force

#     $conf = "$dest\conf\httpd.conf"
#     if (Test-Path $conf) {
#         Write-Host "Inyectando configuracion de puertos..." -ForegroundColor Gray
#         $content = Get-Content $conf
        
#         $content = $content -replace '^Listen\s+\d+', "Listen $puerto"
#         $content = $content -replace '^#?ServerName\s+.*', "ServerName localhost:$puerto"
#         $content | Set-Content $conf
        
#         "<h1>Servidor: Apache Version $version - Puerto: $puerto</h1>" | Out-File "$dest\htdocs\index.html" -Encoding utf8
        
#         Stop-Process -Name "httpd" -ErrorAction SilentlyContinue
#         Write-Host "Iniciando servicio en segundo plano..." -ForegroundColor Gray
#         Start-Process "$dest\bin\httpd.exe" -WorkingDirectory "$dest\bin" -WindowStyle Hidden
        
#         New-NetFirewallRule -DisplayName "HTTP-Apache-$puerto" -LocalPort $puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
#         Write-Host "¡Apache $version aprovisionado exitosamente en http://localhost:$puerto!" -ForegroundColor Green
#     } else {
#         Write-Host "Fallo en el despliegue. Archivo de configuracion no encontrado." -ForegroundColor Red
#     }
# }

# function Instalar-Nginx-Win {
#     param($puerto)
#     Write-Host "Iniciando aprovisionamiento de Nginx Web Server..." -ForegroundColor Cyan
    
#     Write-Host "1) Nginx 1.29.6 (Mainline)"
#     Write-Host "2) Nginx 1.28.2 (Stable)"
#     Write-Host "3) Nginx 1.26.3 (Legacy)"
#     $sel = Read-Host "Selecciona la version a desplegar (1-3)"

#     $version = switch ($sel) {
#         "1" { "1.29.6" }
#         "2" { "1.28.2" }
#         "3" { "1.26.3" }
#         Default { "1.29.6" }
#     }

#     Write-Host "Resolviendo host nginx.org..." -ForegroundColor DarkGray
#     Start-Sleep -Seconds 1
#     Write-Host "Conectando al repositorio principal..." -ForegroundColor DarkGray
#     Start-Sleep -Seconds 1
#     Write-Host "Obteniendo archivo binario nginx-$version.zip..." -ForegroundColor Gray
#     Start-Sleep -Seconds 2

#     $zip = "C:\nginx_$version.zip"
#     $dest = "C:\nginx_server"

#     # Validacion de integridad del paquete
#     if (-not (Test-Path $zip)) {
#         Write-Host "Error 404: Not Found. Fallo al contactar el servidor oficial." -ForegroundColor Red
#         return
#     }

#     Write-Host "Desplegando servidor en disco..." -ForegroundColor Gray
#     if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
#     Expand-Archive -Path $zip -DestinationPath "C:\" -Force
#     Rename-Item -Path "C:\nginx-$version" -NewName "nginx_server"

#     $conf = "$dest\conf\nginx.conf"
#     if (Test-Path $conf) {
#         Write-Host "Inyectando configuracion del puerto $puerto..." -ForegroundColor Gray
#         (Get-Content $conf) -replace 'listen\s+80;', "listen $puerto;" | Set-Content $conf
        
#         "<h1>Servidor: Nginx Version $version - Puerto: $puerto</h1>" | Out-File "$dest\html\index.html" -Encoding utf8
        
#         Stop-Process -Name "nginx" -ErrorAction SilentlyContinue
#         Write-Host "Iniciando demonio de Nginx..." -ForegroundColor Gray
#         Start-Process "$dest\nginx.exe" -WorkingDirectory $dest
        
#         New-NetFirewallRule -DisplayName "HTTP-Nginx-$puerto" -LocalPort $puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
#         Write-Host "¡Nginx $version aprovisionado exitosamente en http://localhost:$puerto!" -ForegroundColor Green
#     } else {
#         Write-Host "Fallo en el despliegue. Archivo de configuracion no encontrado." -ForegroundColor Red
#     }
# }

# function Liberar-Entorno-Win {
#     Write-Host "Liberando entorno y matando procesos..." -ForegroundColor Red
#     Stop-Process -Name "httpd", "nginx" -Force -ErrorAction SilentlyContinue
#     if (Get-Service W3SVC -ErrorAction SilentlyContinue) { 
#         Stop-Service W3SVC -Force -ErrorAction SilentlyContinue 
#     }
#     Write-Host "Limpieza de entorno completada. Puertos liberados." -ForegroundColor Green
# }


# =============================================================================
# http_functions.ps1 - Funciones para aprovisionamiento HTTP en Windows Server 2022
# Uso: . .\http_functions.ps1  (dot-source desde main_windows.ps1)
# Servidores: IIS, Apache (ZIP), Nginx (ZIP), Tomcat (ZIP)
# IP VM: 192.168.56.102
# =============================================================================

$VM_IP    = "192.168.56.102"
$ZIP_BASE = "C:\"

# Versiones - ZIPs ya en C:\ segun foto del host
$APACHE_VERSIONES = @(
    @{ num = "1"; version = "2.4.66"; etiqueta = "Latest"  },
    @{ num = "2"; version = "2.4.65"; etiqueta = "Stable"  },
    @{ num = "3"; version = "2.4.64"; etiqueta = "Legacy"  }
)

$NGINX_VERSIONES = @(
    @{ num = "1"; version = "1.29.6"; etiqueta = "Mainline" },
    @{ num = "2"; version = "1.28.2"; etiqueta = "Stable"   },
    @{ num = "3"; version = "1.26.3"; etiqueta = "Legacy"   }
)

$TOMCAT_VERSIONES = @(
    @{ num = "1"; version = "11.0.18"; etiqueta = "Latest"     },
    @{ num = "2"; version = "10.1.52"; etiqueta = "Stable"     },
    @{ num = "3"; version = "9.0.115"; etiqueta = "LTS/Legacy" }
)

$PUERTOS_RESERVADOS = @(1,7,9,11,13,15,17,19,20,21,22,23,25,37,42,43,53,69,
    77,79,110,111,113,115,117,118,119,123,135,137,139,143,161,177,179,389,
    427,445,465,512,513,514,515,526,530,531,532,540,548,554,556,563,587,
    601,636,989,990,993,995,1723,2049,2222,3306,3389,5432)

$SERVICIOS_RESERVADOS = @{
    20="FTP-Data"; 21="FTP"; 22="SSH"; 25="SMTP"; 53="DNS"
    110="POP3"; 143="IMAP"; 445="SMB"; 2222="SSH-Alt"
    3306="MySQL"; 5432="PostgreSQL"; 3389="RDP"
}

# =============================================================================
# UTILIDADES GENERALES
# =============================================================================

function Mostrar-Banner {
    Clear-Host
    $os    = (Get-WmiObject Win32_OperatingSystem -ErrorAction SilentlyContinue).Caption
    $fecha = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host ""
    Write-Host "  +======================================================+" -ForegroundColor Cyan
    Write-Host "  |     APROVISIONAMIENTO WEB - WINDOWS SERVER 2022     |" -ForegroundColor Cyan
    Write-Host "  |          Practica 6 | PowerShell Automatizado        |" -ForegroundColor Cyan
    Write-Host "  +======================================================+" -ForegroundColor Cyan
    Write-Host ("  |  IP VM   : {0,-43}|" -f $VM_IP)  -ForegroundColor Cyan
    Write-Host ("  |  Sistema : {0,-43}|" -f $os)     -ForegroundColor Cyan
    Write-Host ("  |  Fecha   : {0,-43}|" -f $fecha)  -ForegroundColor Cyan
    Write-Host "  +======================================================+" -ForegroundColor Cyan
    Write-Host ""
}

function Solicitar-Puerto {
    param([string]$ServicioNombre = "el servicio")
    while ($true) {
        $input_p = Read-Host "  Puerto para $ServicioNombre (ej. 80, 8080, 9090)"

        if ($input_p -notmatch '^\d+$') {
            Write-Host "  [!] Solo numeros. Intenta de nuevo." -ForegroundColor Red
            continue
        }
        $p = [int]$input_p
        if ($p -le 0 -or $p -gt 65535) {
            Write-Host "  [!] Puerto fuera de rango (1-65535)." -ForegroundColor Red
            continue
        }
        if ($PUERTOS_RESERVADOS -contains $p) {
            $desc = if ($SERVICIOS_RESERVADOS.ContainsKey($p)) { $SERVICIOS_RESERVADOS[$p] } else { "Sistema Critico" }
            Write-Host "  [!] Puerto $p reservado para $desc. Elige otro." -ForegroundColor Red
            continue
        }
        $ocupado = netstat -ano 2>$null | Select-String ":$p "
        if ($ocupado) {
            Write-Host "  [!] Puerto $p ya esta en uso." -ForegroundColor Red
            continue
        }
        return $p
    }
}

function Crear-Index {
    param([string]$Ruta, [string]$Servicio, [string]$Version, [int]$Puerto)
    if (!(Test-Path $Ruta)) { New-Item -Path $Ruta -ItemType Directory -Force | Out-Null }
    $html = @"
<!DOCTYPE html>
<html lang="es">
<head>
  <meta charset="UTF-8">
  <title>$Servicio - Puerto $Puerto</title>
  <style>
    body { font-family: Arial, sans-serif; background: #1a1a2e; color: #eee;
           display: flex; justify-content: center; align-items: center;
           height: 100vh; margin: 0; }
    .card { background: #16213e; border: 2px solid #0f3460; border-radius: 12px;
            padding: 40px 60px; text-align: center; }
    h1 { color: #e94560; }
    .badge { background: #0f3460; border-radius: 6px; padding: 6px 14px;
             margin-top: 12px; display: inline-block; font-family: monospace; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Servidor Activo</h1>
    <p><strong>Servidor:</strong> $Servicio</p>
    <p><strong>Version:</strong> $Version</p>
    <p><strong>Puerto:</strong> $Puerto</p>
    <p><strong>IP:</strong> $VM_IP</p>
    <div class="badge">http://${VM_IP}:${Puerto}</div>
  </div>
</body>
</html>
"@
    $html | Out-File "$Ruta\index.html" -Encoding utf8
}

function Configurar-Firewall {
    param([int]$Puerto, [string]$Nombre)
    Write-Host "  [*] Abriendo puerto $Puerto en firewall..." -ForegroundColor DarkGray
    $ruleName = "WebServer_${Nombre}_${Puerto}"
    Remove-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName $ruleName `
        -Direction Inbound -Protocol TCP -LocalPort $Puerto `
        -Action Allow -Profile Any -ErrorAction SilentlyContinue | Out-Null
    Write-Host "  [OK] Puerto $Puerto habilitado en firewall." -ForegroundColor Green
}

function Verificar-Servicio {
    param([string]$Servicio, [int]$Puerto)
    Write-Host ""
    Write-Host "  +------ Verificacion: $Servicio en puerto $Puerto ------+" -ForegroundColor Cyan

    $svc = Get-Service -Name $Servicio -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq "Running") {
        Write-Host "  [OK] Servicio $Servicio : ACTIVO" -ForegroundColor Green
    } elseif ($svc) {
        Write-Host "  [!!] Servicio $Servicio : $($svc.Status)" -ForegroundColor Red
    } else {
        Write-Host "  [--] $Servicio : proceso standalone (no como servicio Windows)" -ForegroundColor Yellow
    }

    $escuchando = netstat -ano 2>$null | Select-String ":$Puerto "
    if ($escuchando) {
        Write-Host "  [OK] Puerto $Puerto : ESCUCHANDO" -ForegroundColor Green
    } else {
        Write-Host "  [??] Puerto $Puerto : no detectado aun" -ForegroundColor Yellow
    }

    Write-Host "  [>>] Encabezados HTTP (curl -I http://localhost:$Puerto):" -ForegroundColor Cyan
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:$Puerto" -UseBasicParsing -TimeoutSec 6 -ErrorAction Stop
        Write-Host "       HTTP $($resp.StatusCode) OK" -ForegroundColor Green
        $resp.Headers.GetEnumerator() | Where-Object { $_.Key -match "Server|X-Frame|X-Content|X-XSS" } | ForEach-Object {
            Write-Host "       $($_.Key): $($_.Value)" -ForegroundColor Gray
        }
    } catch {
        Write-Host "       (Sin respuesta - el servicio puede estar iniciando)" -ForegroundColor Yellow
    }
    Write-Host "  +---------------------------------------------------+" -ForegroundColor Cyan
}

function Seleccionar-Version {
    param([array]$Versiones, [string]$NombreServidor)
    Write-Host ""
    Write-Host "  Versiones disponibles para $NombreServidor :" -ForegroundColor White

    foreach ($v in $Versiones) {
        $zipNombre = if     ($NombreServidor -match "Apache") { "apache_$($v.version).zip"  }
                     elseif ($NombreServidor -match "Nginx")  { "nginx_$($v.version).zip"   }
                     else                                      { "apache-tomcat-$($v.version).zip" }
        $estado = if (Test-Path "${ZIP_BASE}${zipNombre}") { "[ZIP OK]" } else { "[ZIP NO ENCONTRADO]" }
        Write-Host "    $($v.num)) $NombreServidor $($v.version)  ($($v.etiqueta))  $estado"
    }
    Write-Host ""

    while ($true) {
        $sel = Read-Host "  Selecciona la version (1-$($Versiones.Count))"
        if ($sel -notmatch '^\d+$') { Write-Host "  [!] Solo el numero." -ForegroundColor Red; continue }
        $entrada = $Versiones | Where-Object { $_.num -eq $sel } | Select-Object -First 1
        if ($entrada) { return $entrada.version }
        Write-Host "  [!] Opcion invalida (1-$($Versiones.Count))." -ForegroundColor Red
    }
}

# =============================================================================
# INSTALAR IIS
# =============================================================================

function Instalar-IIS {
    param([int]$Puerto)
    Write-Host ""
    Write-Host "  [*] Instalando IIS en puerto $Puerto..." -ForegroundColor Cyan

    $feature = Get-WindowsFeature -Name Web-Server -ErrorAction SilentlyContinue
    if (-not $feature.Installed) {
        Write-Host "  [*] Instalando rol Web-Server (IIS)..." -ForegroundColor DarkGray
        Install-WindowsFeature -Name Web-Server,Web-Common-Http,Web-Http-Errors, `
            Web-Static-Content,Web-Http-Logging,Web-Security `
            -IncludeManagementTools -ErrorAction Stop | Out-Null
    }

    Import-Module WebAdministration -ErrorAction Stop

    if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
        Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
    }

    $siteName = "IIS_Puerto_$Puerto"
    $webRoot  = "C:\inetpub\wwwroot\$siteName"

    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
        Stop-Website  -Name $siteName -ErrorAction SilentlyContinue
        Remove-Website -Name $siteName -ErrorAction SilentlyContinue
    }

    New-Item -Path $webRoot -ItemType Directory -Force | Out-Null

    $iisVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $iisVersion) { $iisVersion = "10.0" }

    Crear-Index -Ruta $webRoot -Servicio "IIS (Internet Information Services)" `
                -Version $iisVersion -Puerto $Puerto

    # web.config: security headers + bloqueo de metodos peligrosos
    $webconfig = @"
<?xml version="1.0" encoding="UTF-8"?>
<configuration>
  <system.webServer>
    <httpProtocol>
      <customHeaders>
        <remove name="X-Powered-By" />
        <add name="X-Frame-Options" value="SAMEORIGIN" />
        <add name="X-Content-Type-Options" value="nosniff" />
        <add name="X-XSS-Protection" value="1; mode=block" />
      </customHeaders>
    </httpProtocol>
    <security>
      <requestFiltering removeServerHeader="true">
        <verbs allowUnlisted="false">
          <add verb="GET"  allowed="true" />
          <add verb="POST" allowed="true" />
          <add verb="HEAD" allowed="true" />
        </verbs>
      </requestFiltering>
    </security>
  </system.webServer>
</configuration>
"@
    $webconfig | Out-File "$webRoot\web.config" -Encoding utf8

    New-Website -Name $siteName -Port $Puerto -PhysicalPath $webRoot -Force | Out-Null
    Start-Website -Name $siteName -ErrorAction SilentlyContinue
    Start-Service -Name W3SVC -ErrorAction SilentlyContinue
    Configurar-Firewall -Puerto $Puerto -Nombre "IIS"

    $i = 0
    while ($i -lt 15) { Start-Sleep -Seconds 1; if (netstat -ano 2>$null | Select-String ":$Puerto ") { break }; $i++ }

    Write-Host ""
    Write-Host "  +==================================================+" -ForegroundColor Green
    Write-Host "  |  [OK] IIS activo                                 |" -ForegroundColor Green
    Write-Host "  |  URL : http://${VM_IP}:${Puerto}                 |" -ForegroundColor Green
    Write-Host "  |  Version IIS: $iisVersion                        |" -ForegroundColor Green
    Write-Host "  +==================================================+" -ForegroundColor Green
    Verificar-Servicio -Servicio "W3SVC" -Puerto $Puerto
}

# =============================================================================
# INSTALAR APACHE (ZIP en C:\)
# =============================================================================

function Instalar-Apache-Win {
    param([int]$Puerto)
    Write-Host ""
    Write-Host "  [*] Aprovisionamiento de Apache HTTP Server" -ForegroundColor Cyan

    $version  = Seleccionar-Version -Versiones $APACHE_VERSIONES -NombreServidor "Apache"
    $zipPath  = "${ZIP_BASE}apache_${version}.zip"
    $destBase = "C:\apache_$version"

    if (-not (Test-Path $zipPath)) {
        Write-Host "  [!] No se encontro $zipPath - coloca el ZIP en C:\" -ForegroundColor Red
        return
    }

    Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (Test-Path $destBase) { Remove-Item -Path $destBase -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host "  [*] Extrayendo $zipPath..." -ForegroundColor DarkGray
    try { Expand-Archive -Path $zipPath -DestinationPath $ZIP_BASE -Force -ErrorAction Stop }
    catch { Write-Host "  [!] Error al extraer: $_" -ForegroundColor Red; return }

    foreach ($c in @("C:\Apache24", "C:\Apache_$version")) {
        if ((Test-Path $c) -and ($c -ne $destBase)) {
            Rename-Item -Path $c -NewName "apache_$version" -ErrorAction SilentlyContinue; break
        }
    }

    if (-not (Test-Path $destBase)) {
        Write-Host "  [!] No se encontro $destBase tras extraer." -ForegroundColor Red; return
    }

    $conf = "$destBase\conf\httpd.conf"
    if (-not (Test-Path $conf)) { Write-Host "  [!] httpd.conf no encontrado." -ForegroundColor Red; return }

    Write-Host "  [*] Configurando puerto y hardening en httpd.conf..." -ForegroundColor DarkGray
    $c = Get-Content $conf
    $c = $c -replace '^Listen\s+\d+',           "Listen $Puerto"
    $c = $c -replace '^#?ServerName\s+.*',      "ServerName localhost:$Puerto"
    $c = $c -replace '^#?ServerTokens\s+.*',    "ServerTokens Prod"
    $c = $c -replace '^#?ServerSignature\s+.*', "ServerSignature Off"
    $c = $c -replace '^#?TraceEnable\s+.*',     "TraceEnable Off"
    $c = $c -replace '#LoadModule headers_module', 'LoadModule headers_module'
    $srootFwd = $destBase -replace '\\', '/'
    $c = $c -replace 'Define SRVROOT ".*"', "Define SRVROOT `"$srootFwd`""
    $c | Set-Content $conf -Encoding UTF8

    if (-not (Select-String -Path $conf -Pattern "X-Frame-Options" -Quiet)) {
        Add-Content $conf ""
        Add-Content $conf "# Security Headers"
        Add-Content $conf '<IfModule mod_headers.c>'
        Add-Content $conf '    Header always set X-Frame-Options "SAMEORIGIN"'
        Add-Content $conf '    Header always set X-Content-Type-Options "nosniff"'
        Add-Content $conf '    Header always set X-XSS-Protection "1; mode=block"'
        Add-Content $conf '</IfModule>'
    }

    $htdocs = "$destBase\htdocs"
    if (-not (Test-Path $htdocs)) { New-Item $htdocs -ItemType Directory -Force | Out-Null }
    Crear-Index -Ruta $htdocs -Servicio "Apache HTTP Server (Windows)" -Version $version -Puerto $Puerto
    Configurar-Firewall -Puerto $Puerto -Nombre "Apache"

    # Apache para Windows requiere Visual C++ Redistributable 2015-2022 (VCRUNTIME140.dll)
    # Si no esta instalado, httpd.exe falla con "VCRUNTIME140.dll was not found"
    _Instalar-VCRedist

    Write-Host "  [*] Iniciando Apache $version en puerto $Puerto..." -ForegroundColor DarkGray
    $proc = Start-Process -FilePath "$destBase\bin\httpd.exe" `
                          -WorkingDirectory "$destBase\bin" `
                          -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2

    # Verificar que el proceso sigue vivo (si falta DLL muere de inmediato)
    if ($proc.HasExited) {
        Write-Host "  [!] httpd.exe termino inesperadamente (codigo: $($proc.ExitCode))." -ForegroundColor Red
        Write-Host "  [!] Causa probable: falta VCRUNTIME140.dll o error en httpd.conf" -ForegroundColor Yellow
        Write-Host "       Revisa: $destBase\logs\error.log" -ForegroundColor Yellow
        # Intentar mostrar las ultimas lineas del log si existe
        $errLog = "$destBase\logs\error.log"
        if (Test-Path $errLog) {
            Write-Host "  --- Ultimas lineas de error.log ---" -ForegroundColor Yellow
            Get-Content $errLog -Tail 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }
        return
    }

    # Esperar hasta 10s a que el puerto responda
    $i = 0
    while ($i -lt 10) {
        Start-Sleep -Seconds 1
        if (netstat -ano 2>$null | Select-String ":$Puerto ") { break }
        $i++
    }

    if (netstat -ano 2>$null | Select-String ":$Puerto ") {
        Write-Host ""
        Write-Host "  +==================================================+" -ForegroundColor Green
        Write-Host "  |  [OK] Apache activo                              |" -ForegroundColor Green
        Write-Host "  |  URL : http://${VM_IP}:${Puerto}                 |" -ForegroundColor Green
        Write-Host "  |  Version: $version                               |" -ForegroundColor Green
        Write-Host "  +==================================================+" -ForegroundColor Green
    } else {
        Write-Host "  [!] Apache inicio pero el puerto $Puerto no responde aun." -ForegroundColor Yellow
        Write-Host "       Revisa: $destBase\logs\error.log" -ForegroundColor Yellow
    }
    Verificar-Servicio -Servicio "httpd" -Puerto $Puerto
}

function _Instalar-VCRedist {
    # Verificar si VCRUNTIME140.dll ya esta presente en el sistema
    $vcDll = Get-ChildItem "C:\Windows\System32\VCRUNTIME140.dll" -ErrorAction SilentlyContinue
    if ($vcDll) {
        Write-Host "  [OK] VCRUNTIME140.dll encontrado - no requiere instalacion." -ForegroundColor DarkGray
        return
    }

    Write-Host "  [!] VCRUNTIME140.dll no encontrado." -ForegroundColor Yellow
    Write-Host "  [*] Descargando Visual C++ Redistributable 2015-2022 (x64)..." -ForegroundColor Cyan

    $vcUrl  = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
    $vcExe  = "$env:TEMP\vc_redist.x64.exe"

    try {
        Invoke-WebRequest -Uri $vcUrl -OutFile $vcExe -UseBasicParsing -ErrorAction Stop
        Write-Host "  [*] Instalando VC++ Redistributable (silencioso)..." -ForegroundColor DarkGray
        $p = Start-Process -FilePath $vcExe -ArgumentList "/install /quiet /norestart" -Wait -PassThru
        Remove-Item $vcExe -Force -ErrorAction SilentlyContinue

        if ($p.ExitCode -eq 0 -or $p.ExitCode -eq 3010) {
            Write-Host "  [OK] VC++ Redistributable instalado correctamente." -ForegroundColor Green
        } else {
            Write-Host "  [!] Instalacion termino con codigo $($p.ExitCode)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "  [!] No se pudo descargar VC++ Redistributable: $_" -ForegroundColor Red
        Write-Host "       Descargalo manualmente: https://aka.ms/vs/17/release/vc_redist.x64.exe" -ForegroundColor Yellow
        Write-Host "       Instala y vuelve a ejecutar el script." -ForegroundColor Yellow
    }
}

# =============================================================================
# INSTALAR NGINX (ZIP en C:\)
# =============================================================================

function Instalar-Nginx-Win {
    param([int]$Puerto)
    Write-Host ""
    Write-Host "  [*] Aprovisionamiento de Nginx Web Server" -ForegroundColor Cyan

    $version  = Seleccionar-Version -Versiones $NGINX_VERSIONES -NombreServidor "Nginx"
    $zipPath  = "${ZIP_BASE}nginx_${version}.zip"
    $destBase = "C:\nginx_$version"

    if (-not (Test-Path $zipPath)) {
        Write-Host "  [!] No se encontro $zipPath - coloca el ZIP en C:\" -ForegroundColor Red
        return
    }

    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    if (Test-Path $destBase) { Remove-Item -Path $destBase -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host "  [*] Extrayendo $zipPath..." -ForegroundColor DarkGray
    try { Expand-Archive -Path $zipPath -DestinationPath $ZIP_BASE -Force -ErrorAction Stop }
    catch { Write-Host "  [!] Error al extraer: $_" -ForegroundColor Red; return }

    foreach ($c in @("C:\nginx-$version", "C:\nginx$version")) {
        if ((Test-Path $c) -and ($c -ne $destBase)) {
            Rename-Item -Path $c -NewName "nginx_$version" -ErrorAction SilentlyContinue; break
        }
    }

    if (-not (Test-Path $destBase)) {
        Write-Host "  [!] No se encontro $destBase tras extraer." -ForegroundColor Red; return
    }

    $htmlDir    = "$destBase\html"
    if (-not (Test-Path $htmlDir)) { New-Item $htmlDir -ItemType Directory -Force | Out-Null }
    $htmlDirFwd = $htmlDir -replace '\\', '/'

    # nginx.conf limpio con puerto elegido y security headers
    $nginxConf = @"
worker_processes 1;
events { worker_connections 1024; }
http {
    include      mime.types;
    default_type application/octet-stream;
    server_tokens off;
    sendfile on;
    keepalive_timeout 65;
    server {
        listen $Puerto;
        server_name localhost;
        root $htmlDirFwd;
        index index.html;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;
        if (`$request_method !~ ^(GET|POST|HEAD)`$) { return 405; }
        location / { try_files `$uri `$uri/ =404; }
    }
}
"@
    $nginxConf | Out-File "$destBase\conf\nginx.conf" -Encoding utf8

    Crear-Index -Ruta $htmlDir -Servicio "Nginx (Windows)" -Version $version -Puerto $Puerto
    Configurar-Firewall -Puerto $Puerto -Nombre "Nginx"

    # Validar nginx.conf antes de lanzar
    Write-Host "  [*] Validando nginx.conf..." -ForegroundColor DarkGray
    $testResult = & "$destBase\nginx.exe" -t -p "$destBase" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [!] Error en nginx.conf:" -ForegroundColor Red
        $testResult | ForEach-Object { Write-Host "      $_" -ForegroundColor Yellow }
        return
    }
    Write-Host "  [OK] nginx.conf valido." -ForegroundColor DarkGray

    Write-Host "  [*] Iniciando Nginx $version en puerto $Puerto..." -ForegroundColor DarkGray
    $proc = Start-Process -FilePath "$destBase\nginx.exe" `
                          -WorkingDirectory $destBase `
                          -PassThru
    Start-Sleep -Seconds 2

    # Verificar que el proceso no murio de inmediato
    if ($proc.HasExited) {
        Write-Host "  [!] nginx.exe termino inesperadamente." -ForegroundColor Red
        $errLog = "$destBase\logs\error.log"
        if (Test-Path $errLog) {
            Write-Host "  --- Ultimas lineas de error.log ---" -ForegroundColor Yellow
            Get-Content $errLog -Tail 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }
        return
    }

    # Esperar hasta 10s a que el puerto responda
    $i = 0
    while ($i -lt 10) {
        Start-Sleep -Seconds 1
        if (netstat -ano 2>$null | Select-String ":$Puerto ") { break }
        $i++
    }

    if (netstat -ano 2>$null | Select-String ":$Puerto ") {
        Write-Host ""
        Write-Host "  +==================================================+" -ForegroundColor Green
        Write-Host "  |  [OK] Nginx activo                               |" -ForegroundColor Green
        Write-Host "  |  URL : http://${VM_IP}:${Puerto}                 |" -ForegroundColor Green
        Write-Host "  |  Version: $version                               |" -ForegroundColor Green
        Write-Host "  +==================================================+" -ForegroundColor Green
    } else {
        Write-Host "  [!] Nginx inicio pero el puerto $Puerto no responde." -ForegroundColor Yellow
        $errLog = "$destBase\logs\error.log"
        if (Test-Path $errLog) {
            Write-Host "  --- Ultimas lineas de error.log ---" -ForegroundColor Yellow
            Get-Content $errLog -Tail 10 | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkGray }
        }
    }
    Verificar-Servicio -Servicio "nginx" -Puerto $Puerto
}

# =============================================================================
# INSTALAR TOMCAT (ZIP en C:\, requiere Java en PATH)
# =============================================================================

function Instalar-Tomcat-Win {
    param([int]$Puerto)
    Write-Host ""
    Write-Host "  [*] Aprovisionamiento de Apache Tomcat" -ForegroundColor Cyan

    $java = Get-Command java -ErrorAction SilentlyContinue
    if (-not $java) {
        Write-Host "  [!] Java no encontrado en PATH." -ForegroundColor Red
        Write-Host "       Instala OpenJDK 17 desde https://adoptium.net/ y agrega al PATH." -ForegroundColor Yellow
        return
    }
    Write-Host "  [OK] Java detectado." -ForegroundColor DarkGray

    $version  = Seleccionar-Version -Versiones $TOMCAT_VERSIONES -NombreServidor "Tomcat"
    $zipPath  = "${ZIP_BASE}apache-tomcat-${version}.zip"
    $destBase = "C:\tomcat_$version"

    if (-not (Test-Path $zipPath)) {
        Write-Host "  [!] No se encontro $zipPath" -ForegroundColor Red
        Write-Host "       El ZIP debe llamarse apache-tomcat-$version.zip y estar en C:\" -ForegroundColor Yellow
        return
    }

    Get-Service | Where-Object { $_.Name -like "Tomcat*" } | ForEach-Object {
        Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 1
    if (Test-Path $destBase) { Remove-Item -Path $destBase -Recurse -Force -ErrorAction SilentlyContinue }

    Write-Host "  [*] Extrayendo $zipPath..." -ForegroundColor DarkGray
    try { Expand-Archive -Path $zipPath -DestinationPath $ZIP_BASE -Force -ErrorAction Stop }
    catch { Write-Host "  [!] Error al extraer: $_" -ForegroundColor Red; return }

    foreach ($c in @("C:\apache-tomcat-$version", "C:\tomcat-$version")) {
        if ((Test-Path $c) -and ($c -ne $destBase)) {
            Rename-Item -Path $c -NewName "tomcat_$version" -ErrorAction SilentlyContinue; break
        }
    }

    if (-not (Test-Path $destBase)) {
        Write-Host "  [!] No se encontro $destBase tras extraer." -ForegroundColor Red; return
    }

    $serverXml = "$destBase\conf\server.xml"
    if (-not (Test-Path $serverXml)) { Write-Host "  [!] server.xml no encontrado." -ForegroundColor Red; return }

    Write-Host "  [*] Configurando puerto $Puerto en server.xml..." -ForegroundColor DarkGray
    $xml = Get-Content $serverXml -Raw
    $xml = $xml -replace 'port="8080"', "port=`"$Puerto`""
    # Ocultar banner de version en el Connector HTTP
    $xml = $xml -replace '(Connector port="' + $Puerto + '")', '$1 server="Apache"'
    $xml | Set-Content $serverXml -Encoding UTF8

    $webRoot = "$destBase\webapps\ROOT"
    New-Item -Path $webRoot -ItemType Directory -Force | Out-Null
    Crear-Index -Ruta $webRoot -Servicio "Apache Tomcat (Windows)" -Version $version -Puerto $Puerto

    Configurar-Firewall -Puerto $Puerto -Nombre "Tomcat"

    $env:CATALINA_HOME = $destBase
    $env:JAVA_HOME     = (Split-Path (Split-Path $java.Source))

    $svcName    = "Tomcat_$Puerto"
    $serviceBat = "$destBase\bin\service.bat"
    if (Test-Path $serviceBat) {
        Write-Host "  [*] Registrando como servicio Windows ($svcName)..." -ForegroundColor DarkGray
        & cmd /c "`"$serviceBat`" install $svcName" 2>&1 | Out-Null
        Start-Service -Name $svcName -ErrorAction SilentlyContinue
    } else {
        Write-Host "  [*] Iniciando Tomcat directamente (startup.bat)..." -ForegroundColor DarkGray
        Start-Process -FilePath "$destBase\bin\startup.bat" -WorkingDirectory "$destBase\bin" -WindowStyle Hidden
    }

    Write-Host "  [*] Esperando que Tomcat escuche en puerto $Puerto (hasta 20s)..." -ForegroundColor DarkGray
    $i = 0
    while ($i -lt 20) { Start-Sleep -Seconds 1; if (netstat -ano 2>$null | Select-String ":$Puerto ") { break }; $i++ }

    Write-Host ""
    Write-Host "  +==================================================+" -ForegroundColor Green
    Write-Host "  |  [OK] Tomcat activo                              |" -ForegroundColor Green
    Write-Host "  |  URL : http://${VM_IP}:${Puerto}                 |" -ForegroundColor Green
    Write-Host "  |  Version: $version                               |" -ForegroundColor Green
    Write-Host "  +==================================================+" -ForegroundColor Green
    Verificar-Servicio -Servicio $svcName -Puerto $Puerto
}

# =============================================================================
# DESINSTALAR SERVIDOR ESPECIFICO
# =============================================================================

function Desinstalar-Servidor {
    Write-Host ""
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |    Desinstalar servidor especifico       |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  1) IIS   2) Apache   3) Nginx   4) Tomcat"
    Write-Host ""
    $op = Read-Host "  Selecciona (1-4)"

    switch ($op) {
        "1" {
            Write-Host "  [*] Desinstalando IIS..." -ForegroundColor Yellow
            Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            Get-Website -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "Default Web Site" } | ForEach-Object {
                Remove-Website -Name $_.Name -ErrorAction SilentlyContinue
            }
            Uninstall-WindowsFeature -Name Web-Server -IncludeManagementTools -ErrorAction SilentlyContinue | Out-Null
            Remove-Item "C:\inetpub\wwwroot\IIS_*" -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] IIS desinstalado." -ForegroundColor Green
        }
        "2" {
            Write-Host "  [*] Deteniendo y eliminando Apache..." -ForegroundColor Yellow
            Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force
            Get-ChildItem "C:\" -Filter "apache_*" -Directory | ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  [OK] Eliminado: $($_.FullName)" -ForegroundColor DarkGray
            }
            Write-Host "  [OK] Apache desinstalado." -ForegroundColor Green
        }
        "3" {
            Write-Host "  [*] Deteniendo y eliminando Nginx..." -ForegroundColor Yellow
            Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
            Get-ChildItem "C:\" -Filter "nginx_*" -Directory | ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  [OK] Eliminado: $($_.FullName)" -ForegroundColor DarkGray
            }
            Write-Host "  [OK] Nginx desinstalado." -ForegroundColor Green
        }
        "4" {
            Write-Host "  [*] Deteniendo y eliminando Tomcat..." -ForegroundColor Yellow
            Get-Service | Where-Object { $_.Name -like "Tomcat*" } | ForEach-Object {
                Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
                $catHome = "C:\tomcat_" + ($_.Name -replace 'Tomcat_','')
                if (Test-Path "$catHome\bin\service.bat") {
                    $env:CATALINA_HOME = $catHome
                    & cmd /c "`"$catHome\bin\service.bat`" remove $($_.Name)" 2>&1 | Out-Null
                }
            }
            Get-ChildItem "C:\" -Filter "tomcat_*" -Directory | ForEach-Object {
                Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "  [OK] Eliminado: $($_.FullName)" -ForegroundColor DarkGray
            }
            Write-Host "  [OK] Tomcat desinstalado." -ForegroundColor Green
        }
        default { Write-Host "  [!] Opcion invalida." -ForegroundColor Red }
    }
}

# =============================================================================
# LEVANTAR / REINICIAR SERVICIO
# =============================================================================

function Levantar-Servicio {
    Write-Host ""
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |    Levantar / Reiniciar servicio         |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan

    $instalados = @()
    if (Get-Service W3SVC -ErrorAction SilentlyContinue)                                   { $instalados += "1) IIS"    }
    if (Get-ChildItem "C:\" -Filter "apache_*" -Directory -ErrorAction SilentlyContinue)  { $instalados += "2) Apache" }
    if (Get-ChildItem "C:\" -Filter "nginx_*"  -Directory -ErrorAction SilentlyContinue)  { $instalados += "3) Nginx"  }
    if (Get-ChildItem "C:\" -Filter "tomcat_*" -Directory -ErrorAction SilentlyContinue)  { $instalados += "4) Tomcat" }

    if ($instalados.Count -eq 0) { Write-Host "  No hay ningun servidor instalado." -ForegroundColor Yellow; return }

    Write-Host "  Servidores detectados:"
    $instalados | ForEach-Object { Write-Host "    $_" }
    Write-Host ""

    $op     = Read-Host "  Selecciona (1-4)"
    $puerto = Solicitar-Puerto -ServicioNombre "reinicio"

    switch ($op) {
        "1" {
            Import-Module WebAdministration -ErrorAction SilentlyContinue
            Configurar-Firewall -Puerto $puerto -Nombre "IIS"
            Restart-Service W3SVC -ErrorAction SilentlyContinue
            Write-Host "  [OK] IIS reiniciado en puerto $puerto." -ForegroundColor Green
            Verificar-Servicio -Servicio "W3SVC" -Puerto $puerto
        }
        "2" {
            $dir = Get-ChildItem "C:\" -Filter "apache_*" -Directory | Select-Object -Last 1
            if ($dir) {
                $conf = "$($dir.FullName)\conf\httpd.conf"
                (Get-Content $conf) -replace '^Listen\s+\d+', "Listen $puerto" | Set-Content $conf
                Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force
                Start-Sleep -Seconds 1
                Start-Process -FilePath "$($dir.FullName)\bin\httpd.exe" -WorkingDirectory "$($dir.FullName)\bin" -WindowStyle Hidden
                Configurar-Firewall -Puerto $puerto -Nombre "Apache"
                Write-Host "  [OK] Apache reiniciado en puerto $puerto." -ForegroundColor Green
                Verificar-Servicio -Servicio "httpd" -Puerto $puerto
            }
        }
        "3" {
            $dir = Get-ChildItem "C:\" -Filter "nginx_*" -Directory | Select-Object -Last 1
            if ($dir) {
                $conf = "$($dir.FullName)\conf\nginx.conf"
                (Get-Content $conf) -replace 'listen\s+\d+;', "listen $puerto;" | Set-Content $conf
                Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
                Start-Sleep -Seconds 1
                Start-Process -FilePath "$($dir.FullName)\nginx.exe" -WorkingDirectory $dir.FullName
                Configurar-Firewall -Puerto $puerto -Nombre "Nginx"
                Write-Host "  [OK] Nginx reiniciado en puerto $puerto." -ForegroundColor Green
                Verificar-Servicio -Servicio "nginx" -Puerto $puerto
            }
        }
        "4" {
            $dir = Get-ChildItem "C:\" -Filter "tomcat_*" -Directory | Select-Object -Last 1
            if ($dir) {
                $xml = "$($dir.FullName)\conf\server.xml"
                (Get-Content $xml) -replace 'port="\d+"', "port=`"$puerto`"" | Set-Content $xml
                Get-Service | Where-Object { $_.Name -like "Tomcat*" } | Restart-Service -ErrorAction SilentlyContinue
                Configurar-Firewall -Puerto $puerto -Nombre "Tomcat"
                Write-Host "  [OK] Tomcat reiniciado en puerto $puerto." -ForegroundColor Green
                $svc = (Get-Service | Where-Object { $_.Name -like "Tomcat*" } | Select-Object -First 1).Name
                if ($svc) { Verificar-Servicio -Servicio $svc -Puerto $puerto }
            }
        }
        default { Write-Host "  [!] Opcion invalida." -ForegroundColor Red }
    }
}

# =============================================================================
# VERIFICACION MANUAL
# =============================================================================

function Flujo-Verificacion {
    Write-Host ""
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  |    Verificacion de servicio activo       |" -ForegroundColor Cyan
    Write-Host "  +------------------------------------------+" -ForegroundColor Cyan
    Write-Host "  1) IIS   2) Apache   3) Nginx   4) Tomcat"
    Write-Host ""
    $op     = Read-Host "  Selecciona el servicio (1-4)"
    $puerto = Read-Host "  Puerto del servicio"

    if ($puerto -notmatch '^\d+$') { Write-Host "  [!] Puerto invalido." -ForegroundColor Red; return }

    $svcName = switch ($op) {
        "1" { "W3SVC" }
        "2" { "httpd" }
        "3" { "nginx" }
        "4" { (Get-Service | Where-Object { $_.Name -like "Tomcat*" } | Select-Object -First 1).Name }
        default { Write-Host "  [!] Opcion invalida." -ForegroundColor Red; return }
    }
    Verificar-Servicio -Servicio $svcName -Puerto ([int]$puerto)
}

# =============================================================================
# LIMPIAR ENTORNO COMPLETO
# =============================================================================

function Limpiar-Entorno-Win {
    Write-Host ""
    Write-Host "  [*] Limpiando entorno completo..." -ForegroundColor Yellow

    # IIS
    Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
    Import-Module WebAdministration -ErrorAction SilentlyContinue
    Get-Website -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "Default Web Site" } | ForEach-Object {
        Remove-Website -Name $_.Name -ErrorAction SilentlyContinue
    }
    Remove-Item "C:\inetpub\wwwroot\IIS_*" -Recurse -Force -ErrorAction SilentlyContinue

    # Apache
    Get-Process -Name "httpd" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-Service | Where-Object { $_.Name -like "Apache*" } | Stop-Service -Force -ErrorAction SilentlyContinue
    Get-ChildItem "C:\" -Filter "apache_*" -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Nginx
    Get-Process -Name "nginx" -ErrorAction SilentlyContinue | Stop-Process -Force
    Get-ChildItem "C:\" -Filter "nginx_*" -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Tomcat
    Get-Service | Where-Object { $_.Name -like "Tomcat*" } | ForEach-Object {
        Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
        $catHome = "C:\tomcat_" + ($_.Name -replace 'Tomcat_','')
        if (Test-Path "$catHome\bin\service.bat") {
            $env:CATALINA_HOME = $catHome
            & cmd /c "`"$catHome\bin\service.bat`" remove $($_.Name)" 2>&1 | Out-Null
        }
    }
    Get-ChildItem "C:\" -Filter "tomcat_*" -Directory | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue

    # Reglas de firewall del script
    Get-NetFirewallRule | Where-Object { $_.DisplayName -match "^WebServer_" } | `
        Remove-NetFirewallRule -ErrorAction SilentlyContinue

    Write-Host "  [OK] Entorno limpiado. Todos los servidores eliminados." -ForegroundColor Green
}