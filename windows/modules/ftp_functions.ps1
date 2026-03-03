# =====================================================
# FUNCIONES TECNICAS PARA SERVICIO FTP - ESTRUCTURA DINAMICA
# =====================================================

function Configure-FTPEnvironment {
    $ftpSiteName = "FTPServer_Practica"
    $basePath = "C:\inetpub\ftproot"
    $appcmd = "$env:windir\system32\inetsrv\appcmd.exe"
    
    Import-Module WebAdministration

    Write-Host "[*] Limpiando sitio y deteniendo servicio para evitar bloqueos..." -ForegroundColor Yellow
    Stop-Service ftpsvc -ErrorAction SilentlyContinue

    # 1. ELIMINACIÓN CORRECTA (Solución a image_9be441.png y image_9b77de.png)
    # Se usa Remove-WebSite porque en IIS los sitios FTP y Web comparten el mismo espacio de nombres
    if (Get-Website -Name $ftpSiteName -ErrorAction SilentlyContinue) { 
        Remove-WebSite -Name $ftpSiteName 
    }

    # 2. PERMISOS DE CARPETA RAÍZ (Solución a image_9bd5b8.png)
    if (!(Test-Path $basePath)) { New-Item -Path $basePath -ItemType Directory -Force }
    takeown /f $basePath /r /d y > $null
    # Damos control total a Administradores para que el script no falle
    icacls $basePath /grant "Administrators:(OI)(CI)F" /t > $null
    
    # 3. CREAR ESTRUCTURA BASE
    $dirs = @("general", "reprobados", "recursadores")
    foreach ($dir in $dirs) {
        $path = Join-Path $basePath $dir
        if (!(Test-Path $path)) { New-Item -Path $path -ItemType Directory -Force | Out-Null }
    }

    # 4. CREAR SITIO FTP (Sin aislamiento de usuarios)
    # Importante: El PhysicalPath debe ser exactamente C:\inetpub\ftproot
    New-WebFtpSite -Name $ftpSiteName -Port 21 -PhysicalPath $basePath -Force
    Start-Sleep -s 2 # Pausa para sincronización de IIS

    # 5. CONFIGURACIÓN DE ACCESO
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty "IIS:\Sites\$ftpSiteName" -Name ftpServer.security.authentication.basicAuthentication.enabled -Value $true

    # Reglas de autorización: Permitir a todos entrar a la raíz
    & $appcmd set config -section:system.ftpServer/security/authorization /+"[accessType='Allow',roles='Users',permissions='Read,Write']" /commit:apphost
    & $appcmd set config -section:system.ftpServer/security/authorization /+"[accessType='Allow',users='anonymous',permissions='Read']" /commit:apphost

    # 6. CONFIGURACIÓN NTFS PARA VISIBILIDAD (La clave del problema)
    icacls $basePath /inheritance:r
    icacls $basePath /grant "Administrators:(OI)(CI)F"
    icacls $basePath /grant "SYSTEM:(OI)(CI)F"
    
    # Permitir que todos los usuarios LISTE la raíz (RX), pero sin heredar a las subcarpetas
    # Esto hace que vean las carpetas, pero solo entren a las que tengan permiso.
    icacls $basePath /grant "Users:(RX)"

    # Carpeta General: Todos ven y escriben
    icacls "$basePath\general" /grant "Users:(OI)(CI)M"
    icacls "$basePath\general" /grant "IUSR:(OI)(CI)RX"

    # Carpetas de grupo: Nadie las ve por defecto (se activa en Add-MassiveUsers)
    icacls "$basePath\reprobados" /remove "Users"
    icacls "$basePath\recursadores" /remove "Users"

    Start-Service ftpsvc
    Write-Host "[+] Servidor configurado en $basePath" -ForegroundColor Green
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

        # 1. Crear usuario y asignar a grupos
        if (!(Get-LocalGroup -Name $grupo -ErrorAction SilentlyContinue)) { New-LocalGroup -Name $grupo }
        if (!(Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
            New-LocalUser -Name $userName -Password $password
            Add-LocalGroupMember -Group "Users" -Member $userName
            Add-LocalGroupMember -Group $grupo -Member $userName
        }

        # 2. Carpeta Personal dentro de ftproot
        $userPath = Join-Path $basePath $userName
        if (!(Test-Path $userPath)) { New-Item -Path $userPath -ItemType Directory -Force | Out-Null }
        
        # 3. Permisos Específicos (Hacerlas visibles para el usuario)
        # Solo el dueño ve su carpeta
        icacls $userPath /inheritance:r
        icacls $userPath /grant "Administrators:(OI)(CI)F"
        icacls $userPath /grant "${userName}:(OI)(CI)M"

        # Solo el grupo ve su carpeta de grupo
        icacls "$basePath\$grupo" /grant "${grupo}:(OI)(CI)M"
        
        Write-Host "[+] Usuario $userName listo. Vera: general, $grupo y $userName." -ForegroundColor Green
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