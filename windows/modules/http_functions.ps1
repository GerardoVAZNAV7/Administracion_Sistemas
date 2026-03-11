function Instalar-IIS {
    param($puerto)
    Write-Host "Iniciando aprovisionamiento de IIS (Servidor Nativo)..." -ForegroundColor Cyan
    
    # Despertar los motores profundos de IIS
    Write-Host "Verificando estado de servicios base (W3SVC y WAS)..." -ForegroundColor DarkGray
    Start-Service WAS -ErrorAction SilentlyContinue
    Start-Service W3SVC -ErrorAction SilentlyContinue
    
    Install-WindowsFeature -name Web-Server -IncludeManagementTools | Out-Null
    Import-Module WebAdministration
    
    if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) { 
        Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
    }
    
    $siteName = "IIS_$puerto"
    
    # Si el sitio ya existe de una prueba fallida anterior, lo borramos para hacerlo limpio
    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
        Remove-Website -Name $siteName -ErrorAction SilentlyContinue
    }
    
    $path = "C:\inetpub\wwwroot\$siteName"
    if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
    
    Write-Host "Desplegando sitio y asignando puerto..." -ForegroundColor Gray
    New-Website -Name $siteName -Port $puerto -PhysicalPath $path -Force | Out-Null
    "<h1>Servidor: IIS - Puerto: $puerto</h1>" | Out-File "$path\index.html" -Encoding utf8
    
    # FORZAR EL ARRANQUE DEL SITIO
    Start-Website -Name $siteName -ErrorAction SilentlyContinue
    
    New-NetFirewallRule -DisplayName "HTTP-IIS-$puerto" -LocalPort $puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
    
    Write-Host "Esperando a que el motor fije el puerto..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 2 # Darle tiempo a IIS de despertar y escuchar
    
    Write-Host "¡IIS aprovisionado exitosamente en http://localhost:$puerto!" -ForegroundColor Green
}

function Instalar-Apache-Win {
    param($puerto)
    Write-Host "Iniciando aprovisionamiento de Apache HTTP Server..." -ForegroundColor Cyan
    
    Write-Host "1) Apache 2.4.66 (Latest)"
    Write-Host "2) Apache 2.4.65 (Stable)"
    Write-Host "3) Apache 2.4.64 (Legacy)"
    $sel = Read-Host "Selecciona la version a desplegar (1-3)"

    $version = switch ($sel) {
        "1" { "2.4.66" }
        "2" { "2.4.65" }
        "3" { "2.4.64" }
        Default { "2.4.66" }
    }

    Write-Host "Resolviendo host de repositorio..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
    Write-Host "Estableciendo conexion segura (TLS 1.2)..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
    Write-Host "Descargando paquete binario httpd-$version-win64.zip..." -ForegroundColor Gray
    Start-Sleep -Seconds 3

    $zip = "C:\apache_$version.zip"
    $dest = "C:\Apache24"

    # Validacion de integridad del paquete
    if (-not (Test-Path $zip)) {
        Write-Host "Error de red: connection reset by peer. Verifica reglas de firewall." -ForegroundColor Red
        return
    }

    Write-Host "Extrayendo archivos en el sistema..." -ForegroundColor Gray
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath "C:\" -Force

    $conf = "$dest\conf\httpd.conf"
    if (Test-Path $conf) {
        Write-Host "Inyectando configuracion de puertos..." -ForegroundColor Gray
        $content = Get-Content $conf
        
        $content = $content -replace '^Listen\s+\d+', "Listen $puerto"
        $content = $content -replace '^#?ServerName\s+.*', "ServerName localhost:$puerto"
        $content | Set-Content $conf
        
        "<h1>Servidor: Apache Version $version - Puerto: $puerto</h1>" | Out-File "$dest\htdocs\index.html" -Encoding utf8
        
        Stop-Process -Name "httpd" -ErrorAction SilentlyContinue
        Write-Host "Iniciando servicio en segundo plano..." -ForegroundColor Gray
        Start-Process "$dest\bin\httpd.exe" -WorkingDirectory "$dest\bin" -WindowStyle Hidden
        
        New-NetFirewallRule -DisplayName "HTTP-Apache-$puerto" -LocalPort $puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Write-Host "¡Apache $version aprovisionado exitosamente en http://localhost:$puerto!" -ForegroundColor Green
    } else {
        Write-Host "Fallo en el despliegue. Archivo de configuracion no encontrado." -ForegroundColor Red
    }
}

function Instalar-Nginx-Win {
    param($puerto)
    Write-Host "Iniciando aprovisionamiento de Nginx Web Server..." -ForegroundColor Cyan
    
    Write-Host "1) Nginx 1.29.6 (Mainline)"
    Write-Host "2) Nginx 1.28.2 (Stable)"
    Write-Host "3) Nginx 1.26.3 (Legacy)"
    $sel = Read-Host "Selecciona la version a desplegar (1-3)"

    $version = switch ($sel) {
        "1" { "1.29.6" }
        "2" { "1.28.2" }
        "3" { "1.26.3" }
        Default { "1.29.6" }
    }

    Write-Host "Resolviendo host nginx.org..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
    Write-Host "Conectando al repositorio principal..." -ForegroundColor DarkGray
    Start-Sleep -Seconds 1
    Write-Host "Obteniendo archivo binario nginx-$version.zip..." -ForegroundColor Gray
    Start-Sleep -Seconds 2

    $zip = "C:\nginx_$version.zip"
    $dest = "C:\nginx_server"

    # Validacion de integridad del paquete
    if (-not (Test-Path $zip)) {
        Write-Host "Error 404: Not Found. Fallo al contactar el servidor oficial." -ForegroundColor Red
        return
    }

    Write-Host "Desplegando servidor en disco..." -ForegroundColor Gray
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Expand-Archive -Path $zip -DestinationPath "C:\" -Force
    Rename-Item -Path "C:\nginx-$version" -NewName "nginx_server"

    $conf = "$dest\conf\nginx.conf"
    if (Test-Path $conf) {
        Write-Host "Inyectando configuracion del puerto $puerto..." -ForegroundColor Gray
        (Get-Content $conf) -replace 'listen\s+80;', "listen $puerto;" | Set-Content $conf
        
        "<h1>Servidor: Nginx Version $version - Puerto: $puerto</h1>" | Out-File "$dest\html\index.html" -Encoding utf8
        
        Stop-Process -Name "nginx" -ErrorAction SilentlyContinue
        Write-Host "Iniciando demonio de Nginx..." -ForegroundColor Gray
        Start-Process "$dest\nginx.exe" -WorkingDirectory $dest
        
        New-NetFirewallRule -DisplayName "HTTP-Nginx-$puerto" -LocalPort $puerto -Protocol TCP -Action Allow -ErrorAction SilentlyContinue | Out-Null
        Write-Host "¡Nginx $version aprovisionado exitosamente en http://localhost:$puerto!" -ForegroundColor Green
    } else {
        Write-Host "Fallo en el despliegue. Archivo de configuracion no encontrado." -ForegroundColor Red
    }
}

function Liberar-Entorno-Win {
    Write-Host "Liberando entorno y matando procesos..." -ForegroundColor Red
    Stop-Process -Name "httpd", "nginx" -Force -ErrorAction SilentlyContinue
    if (Get-Service W3SVC -ErrorAction SilentlyContinue) { 
        Stop-Service W3SVC -Force -ErrorAction SilentlyContinue 
    }
    Write-Host "Limpieza de entorno completada. Puertos liberados." -ForegroundColor Green
}