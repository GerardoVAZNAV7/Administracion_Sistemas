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
# =============================================================================

# IP de la VM Windows (adaptador host-only)
$VM_IP = "192.168.56.102"

# Ruta base donde estan los ZIPs preDescargados en C:\
# Los ZIPs deben existir como: C:\apache_2.4.64.zip, C:\nginx_1.26.3.zip, etc.
$ZIP_BASE = "C:\"

# Versiones disponibles (los ZIPs ya estan en C:\ segun la foto del host)
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

# Puertos reservados que el script no permite usar
$PUERTOS_RESERVADOS = @(1,7,9,11,13,15,17,19,20,21,22,23,25,37,42,43,53,69,
    77,79,110,111,113,115,117,118,119,123,135,137,139,143,161,177,179,389,
    427,445,465,512,513,514,515,526,530,531,532,540,548,554,556,563,587,
    601,636,989,990,993,995,1723,2049,2222,3306,3389,5432)

$SERVICIOS_RESERVADOS = @{
    20="FTP-Data"; 21="FTP"; 22="SSH"; 25="SMTP"; 53="DNS";
    110="POP3"; 143="IMAP"; 445="SMB"; 2222="SSH-Alt";
    3306="MySQL"; 5432="PostgreSQL"; 3389="RDP"
}

# =============================================================================
# FUNCION: Validar y solicitar puerto
# Devuelve el puerto como entero o $null si se cancela
# =============================================================================
function Solicitar-Puerto {
    param([string]$ServicioNombre = "el servicio")

    while ($true) {
        $input_puerto = Read-Host "  Puerto para $ServicioNombre (ej. 80, 8080, 9090)"

        # Validar que sea solo digitos
        if ($input_puerto -notmatch '^\d+$') {
            Write-Host "  [!] Solo se permiten numeros. Intenta de nuevo." -ForegroundColor Red
            continue
        }

        $p = [int]$input_puerto

        # Rango valido
        if ($p -le 0 -or $p -gt 65535) {
            Write-Host "  [!] Puerto fuera de rango (1-65535)." -ForegroundColor Red
            continue
        }

        # Puerto reservado del sistema
        if ($PUERTOS_RESERVADOS -contains $p) {
            $desc = if ($SERVICIOS_RESERVADOS.ContainsKey($p)) { $SERVICIOS_RESERVADOS[$p] } else { "Sistema Critico" }
            Write-Host "  [!] Puerto $p reservado para $desc. Elige otro." -ForegroundColor Red
            continue
        }

        # Puerto ya en uso
        $enUso = Test-NetConnection -ComputerName localhost -Port $p -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($enUso.TcpTestSucceeded) {
            Write-Host "  [!] Puerto $p ya esta en uso por otro proceso." -ForegroundColor Red
            continue
        }

        # Puerto valido
        return $p
    }
}

# =============================================================================
# FUNCION: Crear pagina index.html personalizada
# =============================================================================
function Crear-Index {
    param(
        [string]$Ruta,
        [string]$Servicio,
        [string]$Version,
        [int]$Puerto
    )

    if (!(Test-Path $Ruta)) {
        New-Item -Path $Ruta -ItemType Directory -Force | Out-Null
    }

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
    .card { background: #16213e; border: 1px solid #0f3460; border-radius: 12px;
            padding: 40px 60px; text-align: center; box-shadow: 0 4px 20px rgba(0,0,0,0.5); }
    h1 { color: #e94560; margin-bottom: 20px; }
    .info { font-size: 1.1em; margin: 8px 0; }
    .badge { display: inline-block; background: #0f3460; border-radius: 6px;
             padding: 4px 12px; margin-top: 10px; font-family: monospace; }
  </style>
</head>
<body>
  <div class="card">
    <h1>Servidor Activo</h1>
    <div class="info"><strong>Servidor:</strong> $Servicio</div>
    <div class="info"><strong>Version:</strong> $Version</div>
    <div class="info"><strong>Puerto:</strong> $Puerto</div>
    <div class="info"><strong>IP:</strong> $VM_IP</div>
    <div class="badge">http://${VM_IP}:${Puerto}</div>
  </div>
</body>
</html>
"@
    $html | Out-File "$Ruta\index.html" -Encoding utf8
}

# =============================================================================
# FUNCION: Configurar firewall de Windows
# =============================================================================
function Configurar-Firewall {
    param([int]$Puerto, [string]$Nombre)

    Write-Host "  [*] Configurando regla de firewall para puerto $Puerto..." -ForegroundColor DarkGray

    # Eliminar regla previa con mismo nombre si existe
    Remove-NetFirewallRule -DisplayName "HTTP-$Nombre-$Puerto" -ErrorAction SilentlyContinue

    New-NetFirewallRule `
        -DisplayName "HTTP-$Nombre-$Puerto" `
        -LocalPort $Puerto `
        -Protocol TCP `
        -Direction Inbound `
        -Action Allow `
        -ErrorAction SilentlyContinue | Out-Null

    Write-Host "  [OK] Puerto $Puerto abierto en Windows Firewall." -ForegroundColor Green
}

# =============================================================================
# FUNCION: Instalar IIS (nativo de Windows Server)
# =============================================================================
function Instalar-IIS {
    param([int]$Puerto)

    Write-Host ""
    Write-Host "  [*] Instalando IIS en puerto $Puerto..." -ForegroundColor Cyan

    # Instalar feature IIS con herramientas de administracion
    Write-Host "  [*] Instalando Windows Feature Web-Server..." -ForegroundColor DarkGray
    Install-WindowsFeature -Name Web-Server -IncludeManagementTools -IncludeAllSubFeature `
        -ErrorAction Stop | Out-Null

    # Asegurar que el modulo WebAdministration esta disponible
    Import-Module WebAdministration -ErrorAction Stop

    # Detener el Default Web Site para liberar el puerto 80
    if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
        Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
        Write-Host "  [OK] Default Web Site detenido." -ForegroundColor DarkGray
    }

    $siteName = "IIS_Puerto_$Puerto"
    $sitePath = "C:\inetpub\wwwroot\$siteName"

    # Eliminar sitio previo con mismo nombre si existe (re-deploy limpio)
    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
        Stop-Website -Name $siteName -ErrorAction SilentlyContinue
        Remove-Website -Name $siteName -ErrorAction SilentlyContinue
        Write-Host "  [OK] Sitio anterior '$siteName' eliminado." -ForegroundColor DarkGray
    }

    # Crear directorio fisico
    New-Item -Path $sitePath -ItemType Directory -Force | Out-Null

    # Obtener version instalada de IIS
    $iisVersion = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\InetStp" -ErrorAction SilentlyContinue).VersionString
    if (-not $iisVersion) { $iisVersion = "10.0" }

    # Crear pagina de prueba
    Crear-Index -Ruta $sitePath -Servicio "IIS (Internet Information Services)" `
                -Version $iisVersion -Puerto $Puerto

    # Crear sitio web en IIS
    New-Website -Name $siteName -Port $Puerto -PhysicalPath $sitePath -Force | Out-Null
    Start-Website -Name $siteName -ErrorAction SilentlyContinue

    # -- Hardening IIS ----------------------------------------------------------
    _IIS_Hardening -SiteName $siteName

    # Firewall
    Configurar-Firewall -Puerto $Puerto -Nombre "IIS"

    # Esperar a que IIS escuche
    Write-Host "  [*] Esperando que IIS escuche en el puerto $Puerto..." -ForegroundColor DarkGray
    $intentos = 0
    while ($intentos -lt 15) {
        Start-Sleep -Seconds 1
        $conn = Test-NetConnection -ComputerName localhost -Port $Puerto `
                    -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($conn.TcpTestSucceeded) { break }
        $intentos++
    }

    $conn = Test-NetConnection -ComputerName localhost -Port $Puerto `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($conn.TcpTestSucceeded) {
        Write-Host ""
        Write-Host "  +==================================================+" -ForegroundColor Green
        Write-Host "  |  [OK] IIS activo                                 |" -ForegroundColor Green
        Write-Host "  |  URL: http://${VM_IP}:${Puerto}                  |" -ForegroundColor Green
        Write-Host "  |  Version IIS: $iisVersion                        |" -ForegroundColor Green
        Write-Host "  +==================================================+" -ForegroundColor Green
    } else {
        Write-Host "  [!] IIS no respondio en el puerto $Puerto. Revisa el Event Viewer." -ForegroundColor Red
    }
}

function _IIS_Hardening {
    param([string]$SiteName)

    Write-Host "  [*] Aplicando hardening de seguridad en IIS..." -ForegroundColor DarkGray

    # Eliminar encabezado X-Powered-By
    try {
        Remove-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" `
            -Filter "system.webServer/httpProtocol/customHeaders" `
            -Name "." -AtElement @{name="X-Powered-By"} -ErrorAction SilentlyContinue
    } catch {}

    # Eliminar encabezado Server (requiere modulo URL Rewrite o configuracion directa)
    try {
        Set-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" `
            -Filter "system.webServer/security/requestFiltering" `
            -Name "removeServerHeader" -Value $true -ErrorAction SilentlyContinue
    } catch {}

    # Agregar security headers
    $headers = @(
        @{ name = "X-Frame-Options";        value = "SAMEORIGIN" },
        @{ name = "X-Content-Type-Options"; value = "nosniff"    },
        @{ name = "X-XSS-Protection";       value = "1; mode=block" }
    )

    foreach ($h in $headers) {
        try {
            # Quitar si ya existe para evitar duplicados
            Remove-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." -AtElement @{name=$h.name} -ErrorAction SilentlyContinue

            Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" `
                -Filter "system.webServer/httpProtocol/customHeaders" `
                -Name "." -Value @{name=$h.name; value=$h.value} -ErrorAction SilentlyContinue
        } catch {}
    }

    # Deshabilitar metodos HTTP peligrosos (TRACE, TRACK, DELETE)
    try {
        $verbsFilter = "system.webServer/security/requestFiltering/verbs"
        foreach ($verb in @("TRACE","TRACK","DELETE","PUT","OPTIONS")) {
            Add-WebConfigurationProperty -PSPath "IIS:\Sites\$SiteName" `
                -Filter $verbsFilter -Name "." `
                -Value @{verb=$verb; allowed=$false} -ErrorAction SilentlyContinue
        }
    } catch {}

    Write-Host "  [OK] Hardening IIS completado (headers de seguridad + metodos bloqueados)." -ForegroundColor Green
}

# =============================================================================
# FUNCION: Instalar Apache para Windows (desde ZIP preDescargado en C:\)
# =============================================================================
function Instalar-Apache-Win {
    param([int]$Puerto)

    Write-Host ""
    Write-Host "  [*] Aprovisionamiento de Apache HTTP Server para Windows" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Versiones disponibles (ZIPs en C:\):"

    foreach ($v in $APACHE_VERSIONES) {
        $zipExiste = Test-Path "${ZIP_BASE}apache_$($v.version).zip"
        $estado = if ($zipExiste) { "[ZIP OK]" } else { "[ZIP FALTANTE]" }
        Write-Host "    $($v.num)) Apache $($v.version) ($($v.etiqueta))  $estado"
    }

    Write-Host ""
    $sel = Read-Host "  Selecciona la version (1-3)"

    # Validar seleccion
    if ($sel -notmatch '^[1-3]$') {
        Write-Host "  [!] Seleccion invalida. Usando version 1 (Latest)." -ForegroundColor Yellow
        $sel = "1"
    }

    $entrada = $APACHE_VERSIONES | Where-Object { $_.num -eq $sel } | Select-Object -First 1
    $version  = $entrada.version
    $zipPath  = "${ZIP_BASE}apache_${version}.zip"
    $destBase = "C:\apache_$version"        # La carpeta extraida tiene el nombre con version

    Write-Host ""
    Write-Host "  [*] Version seleccionada: Apache $version" -ForegroundColor White

    # Verificar que el ZIP existe
    if (-not (Test-Path $zipPath)) {
        Write-Host "  [!] ERROR: No se encontro el archivo $zipPath" -ForegroundColor Red
        Write-Host "       Asegurate de que el ZIP este en C:\" -ForegroundColor Yellow
        return
    }

    # Detener instancia previa de Apache si esta corriendo
    $procApache = Get-Process -Name "httpd" -ErrorAction SilentlyContinue
    if ($procApache) {
        Write-Host "  [*] Deteniendo instancia previa de Apache..." -ForegroundColor DarkGray
        Stop-Process -Name "httpd" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    # Limpiar directorio destino
    if (Test-Path $destBase) {
        Write-Host "  [*] Limpiando directorio previo $destBase..." -ForegroundColor DarkGray
        Remove-Item -Path $destBase -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Extraer ZIP
    Write-Host "  [*] Extrayendo $zipPath..." -ForegroundColor DarkGray
    try {
        Expand-Archive -Path $zipPath -DestinationPath $ZIP_BASE -Force -ErrorAction Stop
    } catch {
        Write-Host "  [!] Error al extraer el ZIP: $_" -ForegroundColor Red
        return
    }

    # El ZIP puede extraer como Apache24 o apache_2.4.66 segun como fue empaquetado
    # Intentar ambas posibilidades y renombrar al formato con version
    $posibles = @("C:\Apache24", "C:\apache_$version", "C:\Apache_$version")
    $carpetaExtraida = $null
    foreach ($p in $posibles) {
        if ((Test-Path $p) -and ($p -ne $destBase)) {
            $carpetaExtraida = $p
            break
        }
    }

    if ($carpetaExtraida -and ($carpetaExtraida -ne $destBase)) {
        Rename-Item -Path $carpetaExtraida -NewName "apache_$version" -ErrorAction SilentlyContinue
        Write-Host "  [OK] Renombrado $carpetaExtraida -> $destBase" -ForegroundColor DarkGray
    }

    # Verificar que el directorio destino existe
    if (-not (Test-Path $destBase)) {
        Write-Host "  [!] ERROR: No se encontro el directorio $destBase tras extraer." -ForegroundColor Red
        Write-Host "       Verifica el contenido del ZIP." -ForegroundColor Yellow
        return
    }

    $conf = "$destBase\conf\httpd.conf"
    if (-not (Test-Path $conf)) {
        Write-Host "  [!] ERROR: No se encontro httpd.conf en $conf" -ForegroundColor Red
        return
    }

    Write-Host "  [*] Configurando puerto $Puerto en httpd.conf..." -ForegroundColor DarkGray

    # Cambiar puerto de escucha
    $content = Get-Content $conf
    $content = $content -replace '^Listen\s+\d+', "Listen $Puerto"
    $content = $content -replace '^#?ServerName\s+.*', "ServerName localhost:$Puerto"

    # Hardening: ocultar version
    $content = $content -replace '^#?ServerTokens\s+.*', "ServerTokens Prod"
    $content = $content -replace '^#?ServerSignature\s+.*', "ServerSignature Off"

    # Deshabilitar metodos peligrosos (agregar al final del conf)
    $hasTraceBlock = $content | Where-Object { $_ -match "TraceEnable" }
    if (-not $hasTraceBlock) {
        $content += ""
        $content += "# Hardening - deshabilitar metodos peligrosos"
        $content += "TraceEnable Off"
    }

    $content | Set-Content $conf -Encoding UTF8

    # Agregar security headers en httpd.conf
    _Apache_Win_SecurityHeaders -ConfPath $conf

    # Crear pagina de prueba en htdocs
    $htdocs = "$destBase\htdocs"
    if (-not (Test-Path $htdocs)) { New-Item -Path $htdocs -ItemType Directory -Force | Out-Null }
    Crear-Index -Ruta $htdocs -Servicio "Apache HTTP Server (Windows)" `
                -Version $version -Puerto $Puerto

    # Ajustar ServerRoot en httpd.conf (Apache Win necesita la ruta sin trailing slash)
    $content = Get-Content $conf
    $content = $content -replace 'Define SRVROOT ".*"', "Define SRVROOT `"$($destBase -replace '\\','/')`""
    $content | Set-Content $conf -Encoding UTF8

    # Firewall
    Configurar-Firewall -Puerto $Puerto -Nombre "Apache"

    # Iniciar Apache en background
    Write-Host "  [*] Iniciando Apache $version en puerto $Puerto..." -ForegroundColor DarkGray
    Start-Process -FilePath "$destBase\bin\httpd.exe" `
                  -WorkingDirectory "$destBase\bin" `
                  -WindowStyle Hidden

    Start-Sleep -Seconds 3

    # Verificar que esta escuchando
    $conn = Test-NetConnection -ComputerName localhost -Port $Puerto `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($conn.TcpTestSucceeded) {
        Write-Host ""
        Write-Host "  +==================================================+" -ForegroundColor Green
        Write-Host "  |  [OK] Apache Windows activo                      |" -ForegroundColor Green
        Write-Host "  |  URL: http://${VM_IP}:${Puerto}                  |" -ForegroundColor Green
        Write-Host "  |  Version: $version                               |" -ForegroundColor Green
        Write-Host "  +==================================================+" -ForegroundColor Green
    } else {
        Write-Host "  [!] Apache no respondio en el puerto $Puerto." -ForegroundColor Red
        Write-Host "       Prueba manual: $destBase\bin\httpd.exe" -ForegroundColor Yellow
        Write-Host "       Log de errores: $destBase\logs\error.log" -ForegroundColor Yellow
    }
}

function _Apache_Win_SecurityHeaders {
    param([string]$ConfPath)

    $content = Get-Content $ConfPath

    # Activar mod_headers si esta comentado
    $content = $content -replace '#LoadModule headers_module', 'LoadModule headers_module'

    # Agregar bloque de security headers si no existe
    $tieneHeaders = $content | Where-Object { $_ -match "X-Frame-Options" }
    if (-not $tieneHeaders) {
        $content += ""
        $content += "# Security Headers"
        $content += '<IfModule mod_headers.c>'
        $content += '    Header always set X-Frame-Options "SAMEORIGIN"'
        $content += '    Header always set X-Content-Type-Options "nosniff"'
        $content += '    Header always set X-XSS-Protection "1; mode=block"'
        $content += '</IfModule>'
    }

    $content | Set-Content $ConfPath -Encoding UTF8
    Write-Host "  [OK] Security headers configurados en Apache." -ForegroundColor DarkGray
}

# =============================================================================
# FUNCION: Instalar Nginx para Windows (desde ZIP preDescargado en C:\)
# =============================================================================
function Instalar-Nginx-Win {
    param([int]$Puerto)

    Write-Host ""
    Write-Host "  [*] Aprovisionamiento de Nginx Web Server para Windows" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Versiones disponibles (ZIPs en C:\):"

    foreach ($v in $NGINX_VERSIONES) {
        $zipExiste = Test-Path "${ZIP_BASE}nginx_$($v.version).zip"
        $estado = if ($zipExiste) { "[ZIP OK]" } else { "[ZIP FALTANTE]" }
        Write-Host "    $($v.num)) Nginx $($v.version) ($($v.etiqueta))  $estado"
    }

    Write-Host ""
    $sel = Read-Host "  Selecciona la version (1-3)"

    if ($sel -notmatch '^[1-3]$') {
        Write-Host "  [!] Seleccion invalida. Usando version 1 (Mainline)." -ForegroundColor Yellow
        $sel = "1"
    }

    $entrada  = $NGINX_VERSIONES | Where-Object { $_.num -eq $sel } | Select-Object -First 1
    $version  = $entrada.version
    $zipPath  = "${ZIP_BASE}nginx_${version}.zip"
    $destBase = "C:\nginx_$version"    # Carpeta con version en el nombre

    Write-Host ""
    Write-Host "  [*] Version seleccionada: Nginx $version" -ForegroundColor White

    # Verificar ZIP
    if (-not (Test-Path $zipPath)) {
        Write-Host "  [!] ERROR: No se encontro $zipPath" -ForegroundColor Red
        Write-Host "       Asegurate de que el ZIP este en C:\" -ForegroundColor Yellow
        return
    }

    # Detener instancia previa
    $procNginx = Get-Process -Name "nginx" -ErrorAction SilentlyContinue
    if ($procNginx) {
        Write-Host "  [*] Deteniendo instancia previa de Nginx..." -ForegroundColor DarkGray
        Stop-Process -Name "nginx" -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
    }

    # Limpiar directorio previo
    if (Test-Path $destBase) {
        Write-Host "  [*] Limpiando directorio previo $destBase..." -ForegroundColor DarkGray
        Remove-Item -Path $destBase -Recurse -Force -ErrorAction SilentlyContinue
    }

    # Extraer ZIP
    Write-Host "  [*] Extrayendo $zipPath..." -ForegroundColor DarkGray
    try {
        Expand-Archive -Path $zipPath -DestinationPath $ZIP_BASE -Force -ErrorAction Stop
    } catch {
        Write-Host "  [!] Error al extraer el ZIP: $_" -ForegroundColor Red
        return
    }

    # Nginx se extrae generalmente como nginx-1.29.6\ -> renombrar a nginx_1.29.6
    $posibles = @(
        "C:\nginx-$version",
        "C:\nginx_$version",
        "C:\nginx$version"
    )
    foreach ($p in $posibles) {
        if ((Test-Path $p) -and ($p -ne $destBase)) {
            Rename-Item -Path $p -NewName "nginx_$version" -ErrorAction SilentlyContinue
            Write-Host "  [OK] Renombrado $p -> $destBase" -ForegroundColor DarkGray
            break
        }
    }

    if (-not (Test-Path $destBase)) {
        Write-Host "  [!] ERROR: No se encontro el directorio $destBase tras extraer." -ForegroundColor Red
        return
    }

    $conf = "$destBase\conf\nginx.conf"
    if (-not (Test-Path $conf)) {
        Write-Host "  [!] ERROR: No se encontro nginx.conf en $conf" -ForegroundColor Red
        return
    }

    Write-Host "  [*] Configurando puerto $Puerto en nginx.conf..." -ForegroundColor DarkGray

    # Cambiar puerto de escucha y agregar server_tokens off
    $content = Get-Content $conf -Raw

    # Cambiar listen 80; por el puerto elegido
    $content = $content -replace 'listen\s+80\s*;', "listen $Puerto;"
    $content = $content -replace 'listen\s+\[::\]:80\s*;', "listen [::]:$Puerto;"

    # Agregar server_tokens off dentro del bloque http si no existe
    if ($content -notmatch 'server_tokens') {
        $content = $content -replace '(http\s*\{)', "`$1`n    server_tokens off;"
    }

    $content | Set-Content $conf -Encoding UTF8

    # Agregar security headers en el bloque server
    _Nginx_Win_SecurityHeaders -ConfPath $conf -Puerto $Puerto

    # Crear pagina de prueba en html/
    $htmlDir = "$destBase\html"
    if (-not (Test-Path $htmlDir)) { New-Item -Path $htmlDir -ItemType Directory -Force | Out-Null }
    Crear-Index -Ruta $htmlDir -Servicio "Nginx (Windows)" -Version $version -Puerto $Puerto

    # Firewall
    Configurar-Firewall -Puerto $Puerto -Nombre "Nginx"

    # Iniciar Nginx
    Write-Host "  [*] Iniciando Nginx $version en puerto $Puerto..." -ForegroundColor DarkGray
    Start-Process -FilePath "$destBase\nginx.exe" -WorkingDirectory $destBase

    Start-Sleep -Seconds 3

    # Verificar
    $conn = Test-NetConnection -ComputerName localhost -Port $Puerto `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($conn.TcpTestSucceeded) {
        Write-Host ""
        Write-Host "  +==================================================+" -ForegroundColor Green
        Write-Host "  |  [OK] Nginx Windows activo                       |" -ForegroundColor Green
        Write-Host "  |  URL: http://${VM_IP}:${Puerto}                  |" -ForegroundColor Green
        Write-Host "  |  Version: $version                               |" -ForegroundColor Green
        Write-Host "  +==================================================+" -ForegroundColor Green
    } else {
        Write-Host "  [!] Nginx no respondio en el puerto $Puerto." -ForegroundColor Red
        Write-Host "       Log de errores: $destBase\logs\error.log" -ForegroundColor Yellow
    }
}

function _Nginx_Win_SecurityHeaders {
    param([string]$ConfPath, [int]$Puerto)

    $content = Get-Content $ConfPath -Raw

    # Insertar security headers dentro del bloque location /
    $headersBlock = @"

        # Security Headers
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-XSS-Protection "1; mode=block" always;

        # Bloquear metodos peligrosos
        if (`$request_method !~ ^(GET|POST|HEAD)$) {
            return 405;
        }
"@

    # Insertar despues de "location / {"
    if ($content -notmatch "X-Frame-Options") {
        $content = $content -replace '(location\s*/\s*\{)', "`$1$headersBlock"
        $content | Set-Content $ConfPath -Encoding UTF8
        Write-Host "  [OK] Security headers configurados en Nginx." -ForegroundColor DarkGray
    }
}

# =============================================================================
# FUNCION: Limpiar entorno Windows
# =============================================================================
function Liberar-Entorno-Win {
    Write-Host ""
    Write-Host "  [*] Liberando entorno Windows..." -ForegroundColor Yellow

    # Detener procesos de servidores standalone
    $procesos = @("httpd", "nginx")
    foreach ($proc in $procesos) {
        $p = Get-Process -Name $proc -ErrorAction SilentlyContinue
        if ($p) {
            Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Proceso $proc detenido." -ForegroundColor DarkGray
        }
    }

    # Detener IIS
    if (Get-Service -Name W3SVC -ErrorAction SilentlyContinue) {
        Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] IIS (W3SVC) detenido." -ForegroundColor DarkGray
    }

    # Eliminar reglas de firewall creadas por este script
    Get-NetFirewallRule | Where-Object { $_.DisplayName -match "^HTTP-(IIS|Apache|Nginx)-" } | `
        Remove-NetFirewallRule -ErrorAction SilentlyContinue
    Write-Host "  [OK] Reglas de firewall del script eliminadas." -ForegroundColor DarkGray

    Write-Host "  [OK] Entorno liberado. Puertos desocupados." -ForegroundColor Green
}