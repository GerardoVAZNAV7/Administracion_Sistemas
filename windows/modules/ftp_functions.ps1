# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP
# =====================================================

function Install-FTPService {
    Write-Host "[*] Verificando e instalando Rol Web-Server e IIS-FTPServer..." -ForegroundColor Cyan
    Install-WindowsFeature Web-Server, Web-Mgmt-Console, Web-Ftp-Server, Web-Ftp-Service -IncludeManagementTools
    Write-Host "[+] Instalacion completada." -ForegroundColor Green
}

function Configure-FTPEnvironment {
    $ftpSiteName = "FTPServer_Practica"
    $basePath = "C:\inetpub\ftproot"
    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
    
    Import-Module WebAdministration

    Write-Host "[*] Iniciando configuracion forzada..." -ForegroundColor Yellow

    # 1. ELIMINACIÓN LIMPIA (Evita errores de 'Destination element already exists')
    if (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue) { 
        Remove-WebSite -Name $ftpSiteName 
        Write-Host "[-] Sitio anterior removido correctamente." -ForegroundColor Gray
    }

    # 2. FORZAR PERMISOS DE CARPETA (Soluciona 'Access is denied')
    if (!(Test-Path $basePath)) { New-Item -Path $basePath -ItemType Directory -Force | Out-Null }
    # Tomar propiedad de la carpeta para el grupo Administradores
    takeown /f $basePath /r /d y > $null
    icacls $basePath /grant "Administrators:(OI)(CI)F" /t > $null

    # 3. DESBLOQUEO DE CONFIGURACIÓN
    & $appcmd unlock config -section:system.ftpServer/security/authorization
    & $appcmd unlock config -section:system.ftpServer/security/authentication
    Start-Sleep -s 1 # Pausa para que IIS procese el desbloqueo

    # 4. CREACIÓN DE DIRECTORIOS
    foreach ($dir in @("general", "reprobados", "recursadores")) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
    }

    # 5. CREAR SITIO FTP (Con -Force para sobrescribir)
    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath -Force
    Write-Host "[*] Esperando registro en IIS..." -ForegroundColor Gray
    Start-Sleep -s 2 # CRUCIAL para evitar 'Index out of range'

    # 6. APLICAR PROPIEDADES SSL Y AUTH
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # 7. REGLAS DE AUTORIZACIÓN (Solución a errores de web.config)
    try {
        Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="anonymous";permissions="Read"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName
        Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";roles="Users";permissions="Read,Write"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName
    } catch {
        Write-Host "[!] Advertencia: No se pudieron aplicar reglas de autorizacion. Verifique privilegios." -ForegroundColor Red
    }

    # 8. PERMISOS NTFS FINALES
    icacls $basePath /inheritance:r
    icacls $basePath /grant "Administrators:(OI)(CI)F"
    icacls $basePath /grant "SYSTEM:(OI)(CI)F"
    icacls $basePath /grant "Users:(R)"
    
    Write-Host "[+] Entorno configurado exitosamente." -ForegroundColor Green
}
function Add-MassiveUsers {
    $n_input = Read-Host "Ingrese el numero de usuarios a crear"
    $n = 0 
    if (!([int]::TryParse($n_input, [ref]$n))) { return }

    $basePath = "C:\inetpub\ftproot"

    for ($i = 1; $i -le $n; $i++) {
        Write-Host "`n--- Datos Usuario $i ---" -ForegroundColor Yellow
        $userName = Read-Host "Nombre de usuario"
        $passwordRaw = Read-Host "Password"
        $password = $passwordRaw | ConvertTo-SecureString -AsPlainText -Force
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        try {
            if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
                New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName"
                Add-LocalGroupMember -Group "Users" -Member $userName
                Add-LocalGroupMember -Group $grupo -Member $userName
            }

            # --- CARPETA PERSONAL ---
            $userPath = Join-Path $basePath $userName
            if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory -Force | Out-Null }
            
            icacls $userPath /inheritance:r
            icacls $userPath /grant "Administrators:(OI)(CI)F"
            icacls $userPath /grant "${userName}:(OI)(CI)M"
            
            Write-Host "[+] Usuario $userName creado y carpeta configurada." -ForegroundColor Green
        } catch { 
            Write-Host "[!] Error: Verifique que el grupo '$grupo' exista." -ForegroundColor Red
        }
    }
}

function Update-UserGroup {
    $user = Read-Host "Usuario a mover"
    $nuevoGrupo = Read-Host "Nuevo grupo destino (reprobados/recursadores)"
    
    $gruposBusqueda = @("reprobados", "recursadores")
    foreach ($g in $gruposBusqueda) {
        Remove-LocalGroupMember -Group $g -Member $user -ErrorAction SilentlyContinue
    }
    
    Add-LocalGroupMember -Group $nuevoGrupo -Member $user
    Write-Host "[+] El usuario $user ahora pertenece a $nuevoGrupo (se actualizo su acceso FTP)." -ForegroundColor Green
}