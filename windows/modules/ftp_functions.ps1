# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP
# =====================================================

# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP REFORZADO
# =====================================================

function Configure-FTPEnvironment {
    $ftpSiteName = "FTPServer_Practica"
    $basePath = "C:\inetpub\ftproot"
    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
    
    Import-Module WebAdministration

    Write-Host "[*] Limpiando y preparando entorno..." -ForegroundColor Yellow
    
    # 1. Eliminar sitio si existe (Corrección de image_9be441.png)
    if (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue) { 
        Remove-WebSite -Name $ftpSiteName 
    }

    # 2. Permisos base y Desbloqueo (Solución a image_9bd5b8.png)
    if (!(Test-Path $basePath)) { New-Item -Path $basePath -ItemType Directory -Force }
    takeown /f $basePath /r /d y > $null
    icacls $basePath /grant "Administrators:(OI)(CI)F" /t > $null
    
    & $appcmd unlock config -section:system.ftpServer/security/authorization
    & $appcmd unlock config -section:system.ftpServer/security/authentication

    # 3. Crear Estructura Base
    $dirs = @("general", "reprobados", "recursadores")
    foreach ($dir in $dirs) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
    }

    # 4. Crear Sitio FTP
    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath -Force
    Start-Sleep -s 2 # Espera necesaria para evitar 'Index out of range' (image_9b77de.png)

    # 5. Configuración de Seguridad
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.controlChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.ssl.dataChannelPolicy -Value "SslAllow"
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # Reglas de Autorización IIS
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";users="anonymous";permissions="Read"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName
    Add-WebConfiguration -Filter "/system.ftpServer/security/authorization" -Value @{accessType="Allow";roles="Users";permissions="Read,Write"} -PSPath "MACHINE/WEBROOT/APPHOST" -Location $ftpSiteName

    # 6. Permisos NTFS Lógicos (Aquí ocurre la magia de visibilidad)
    icacls $basePath /inheritance:r
    icacls $basePath /grant "Administrators:(OI)(CI)F"
    icacls $basePath /grant "SYSTEM:(OI)(CI)F"
    icacls $basePath /grant "Users:(RX)" # Permiso para listar la raíz

    # Carpeta General: Solo lectura para anónimos, Escritura para logeados
    icacls "$basePath\general" /grant "IUSR:(RX)"
    icacls "$basePath\general" /grant "Users:(OI)(CI)M"

    # Grupos: Nadie ve nada por defecto
    icacls "$basePath\reprobados" /remove "Users"
    icacls "$basePath\recursadores" /remove "Users"

    Write-Host "[+] Servidor base listo. Los grupos se activaran al crear usuarios." -ForegroundColor Green
}

function Add-MassiveUsers {
    $n_input = Read-Host "Ingrese el numero de usuarios a crear"
    $n = 0 
    if (!([int]::TryParse($n_input, [ref]$n))) { return }

    $basePath = "C:\inetpub\ftproot"

    for ($i = 1; $i -le $n; $i++) {
        $userName = Read-Host "Nombre de usuario"
        $passwordRaw = Read-Host "Password"
        $password = $passwordRaw | ConvertTo-SecureString -AsPlainText -Force
        $grupo = Read-Host "Grupo (reprobados/recursadores)"

        # 1. Crear usuario y grupos
        if (!(Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $grupo }
        if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $userName -Password $password -FullName "Estudiante $userName"
            Add-LocalGroupMember -Group "Users" -Member $userName
            Add-LocalGroupMember -Group $grupo -Member $userName
        }

        # 2. Carpeta Personal
        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory -Force | Out-Null }
        
        # 3. Permisos Específicos para el Usuario (Visibilidad)
        icacls $userPath /inheritance:r
        icacls $userPath /grant "Administrators:(OI)(CI)F"
        icacls $userPath /grant "${userName}:(OI)(CI)M"

        # 4. Asegurar que el grupo tenga acceso a su carpeta compartida
        icacls "$basePath\$grupo" /grant "${grupo}:(OI)(CI)M"
        
        Write-Host "[+] $userName configurado. Vera: general, $grupo y $userName." -ForegroundColor Green
    }
}

function Update-UserGroup {
    $user = Read-Host "Usuario a mover"
    $nuevoGrupo = Read-Host "Nuevo grupo destino (reprobados/recursadores)"
    $basePath = "C:\inetpub\ftproot"

    # Eliminar de grupos viejos
    @("reprobados", "recursadores") | ForEach-Object {
        Remove-LocalGroupMember -Group $_ -Member $user -ErrorAction SilentlyContinue
    }
    
    # Agregar al nuevo
    if (!(Get-LocalGroup -Name $nuevoGrupo -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $nuevoGrupo }
    Add-LocalGroupMember -Group $nuevoGrupo -Member $user

    # Refrescar permisos de la carpeta de grupo
    icacls "$basePath\$nuevoGrupo" /grant "${nuevoGrupo}:(OI)(CI)M"

    Write-Host "[+] Cambio completado. FileZilla actualizara la carpeta de grupo al reconectar." -ForegroundColor Green
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