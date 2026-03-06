# =============================================================================
# ftp_functions.ps1 — Funciones del servidor FTP (IIS) para Windows
# Ubicacion: windows/modules/ftp_functions.ps1
# =============================================================================

# -----------------------------------------------------------------------------
# VALIDACION Y CAPTURA
# -----------------------------------------------------------------------------

function Invoke-ValidarContra {
    param ([string]$contra)

    if ($contra.Length -lt 8) {
        Write-Host "  [!] La contrasena debe tener al menos 8 caracteres." -ForegroundColor Yellow
        return $false
    }
    if ($contra.Length -gt 15) {
        Write-Host "  [!] La contrasena no puede tener mas de 15 caracteres." -ForegroundColor Yellow
        return $false
    }
    if ($contra -notmatch "[A-Z]") {
        Write-Host "  [!] La contrasena debe contener al menos una letra mayuscula." -ForegroundColor Yellow
        return $false
    }
    if ($contra -notmatch "[a-z]") {
        Write-Host "  [!] La contrasena debe contener al menos una letra minuscula." -ForegroundColor Yellow
        return $false
    }
    if ($contra -notmatch "\d") {
        Write-Host "  [!] La contrasena debe contener al menos un numero." -ForegroundColor Yellow
        return $false
    }
    if ($contra -notmatch "[^a-zA-Z0-9]") {
        Write-Host "  [!] La contrasena debe contener al menos un caracter especial." -ForegroundColor Yellow
        return $false
    }
    return $true
}

function Invoke-CapturarContra {
    $esValida = $false
    do {
        $contra = Read-Host "  Contrasena (8-15 chars, May, min, num, especial)"
        $esValida = Invoke-ValidarContra -contra $contra
        if (-not $esValida) {
            Write-Host "  Contrasena no valida. Intentelo de nuevo." -ForegroundColor Red
        }
    } while (-not $esValida)
    return $contra
}

function Invoke-CapturarUsuarioFTPValido {
    param ([string]$mensaje)

    $caracteresPermitidos = '^[a-zA-Z0-9]+$'
    $longitudMaxima = 15
    $cadenaValida = $false

    do {
        $cadena = Read-Host $mensaje

        if (-not $cadena) {
            Write-Host "  [!] El nombre no puede estar vacio." -ForegroundColor Yellow
        }
        elseif ($cadena -notmatch $caracteresPermitidos) {
            Write-Host "  [!] Solo se permiten letras y numeros." -ForegroundColor Yellow
        }
        elseif ($cadena -match '^[0-9]') {
            Write-Host "  [!] El nombre no puede comenzar con un numero." -ForegroundColor Yellow
        }
        elseif ($cadena.Length -gt $longitudMaxima) {
            Write-Host "  [!] El nombre no puede exceder $longitudMaxima caracteres." -ForegroundColor Yellow
        }
        elseif (Invoke-UsuarioExiste -nombreUsuario $cadena) {
            Write-Host "  [!] El usuario '$cadena' ya existe. Elija otro nombre." -ForegroundColor Yellow
        }
        else {
            $cadenaValida = $true
        }
    } while (-not $cadenaValida)

    return $cadena
}

function Invoke-CapturarGrupoFTP {
    do {
        Write-Host ""
        Write-Host "  Seleccione el grupo:" -ForegroundColor Cyan
        Write-Host "    1) reprobados"
        Write-Host "    2) recursadores"
        $grupo = Read-Host "  Opcion"

        switch ($grupo) {
            "1" { return "reprobados" }
            "2" { return "recursadores" }
            default { Write-Host "  [!] Opcion no valida. Ingrese 1 o 2." -ForegroundColor Yellow }
        }
    } while ($true)
}

# -----------------------------------------------------------------------------
# CONSULTAS
# -----------------------------------------------------------------------------

function Invoke-UsuarioExiste {
    param ([string]$nombreUsuario)
    $adsi = [ADSI]"WinNT://$env:ComputerName"
    $usuario = $adsi.Children | Where-Object {
        $_.SchemaClassName -eq 'User' -and $_.Name -eq $nombreUsuario
    }
    return ($null -ne $usuario)
}

function Get-GrupoActualFTP {
    param ([string]$FTPUserName)
    $userADSI = [ADSI]"WinNT://$env:ComputerName/$FTPUserName,user"
    $grupos = $userADSI.Groups() | ForEach-Object {
        $_.GetType().InvokeMember("Name", 'GetProperty', $null, $_, $null)
    }
    if ($grupos -contains "reprobados")  { return "reprobados" }
    if ($grupos -contains "recursadores") { return "recursadores" }
    return ""
}

# -----------------------------------------------------------------------------
# CONFIGURACION INICIAL DEL SERVIDOR FTP
# -----------------------------------------------------------------------------

function Initialize-ServidorFTP {
    Write-Host ""
    Write-Host "=================================================" -ForegroundColor Cyan
    Write-Host "  CONFIGURACION INICIAL DEL SERVIDOR FTP (IIS)"  -ForegroundColor Cyan
    Write-Host "=================================================" -ForegroundColor Cyan

    # 1. Instalar IIS + FTP
    Write-Host "`n[1/7] Instalando IIS y Servicio FTP..." -ForegroundColor White
    Install-WindowsFeature Web-Server, Web-FTP-Server -IncludeManagementTools | Out-Null
    Write-Host "  OK" -ForegroundColor Green

    # 2. Estructura de directorios
    Write-Host "[2/7] Creando estructura de directorios..." -ForegroundColor White
    $rutas = @(
        "C:\FTP",
        "C:\FTP\grupos",
        "C:\FTP\grupos\recursadores",
        "C:\FTP\grupos\reprobados",
        "C:\FTP\LocalUser",
        "C:\FTP\LocalUser\Public",
        "C:\FTP\LocalUser\Public\general"
    )
    foreach ($ruta in $rutas) {
        if (-not (Test-Path $ruta)) {
            New-Item -Path $ruta -ItemType Directory -Force | Out-Null
        }
    }
    Write-Host "  OK" -ForegroundColor Green

    # 3. Permisos NTFS para carpetas de grupo
    Write-Host "[3/7] Configurando permisos NTFS en carpetas de grupo..." -ForegroundColor White
    foreach ($g in @("reprobados", "recursadores")) {
        $rutaGrupo = "C:\FTP\grupos\$g"
        $acl = Get-Acl $rutaGrupo
        $acl.SetAccessRuleProtection($true, $false)

        $adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "Administrators", "FullControl",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($adminRule)

        $groupRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $g, "Modify",
            "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.AddAccessRule($groupRule)
        Set-Acl $rutaGrupo $acl
    }

    # Permisos NTFS para el usuario anonimo (IUSR) sobre su raiz
    $aclPublic = Get-Acl "C:\FTP\LocalUser\Public"
    $aclPublic.SetAccessRuleProtection($true, $false)

    $adminRuleP = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl",
        "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $aclPublic.AddAccessRule($adminRuleP)

    $iusrRuleRoot = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IUSR", "ReadAndExecute",
        "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $aclPublic.AddAccessRule($iusrRuleRoot)
    Set-Acl "C:\FTP\LocalUser\Public" $aclPublic

    # Permisos carpeta general: IUSR solo lectura, usuarios autenticados pueden modificar
    $aclGen = Get-Acl "C:\FTP\LocalUser\Public\general"
    $aclGen.SetAccessRuleProtection($true, $false)

    $adminRuleG = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Administrators", "FullControl",
        "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $aclGen.AddAccessRule($adminRuleG)

    $iusrRuleGen = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "IUSR", "ReadAndExecute",
        "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $aclGen.AddAccessRule($iusrRuleGen)

    $authRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        "Authenticated Users", "Modify",
        "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $aclGen.AddAccessRule($authRule)
    Set-Acl "C:\FTP\LocalUser\Public\general" $aclGen

    Write-Host "  OK" -ForegroundColor Green

    # 4. Firewall
    Write-Host "[4/7] Configurando Firewall (puerto 21)..." -ForegroundColor White
    if (-not (Get-NetFirewallRule -DisplayName "FTP_Practica" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule -DisplayName "FTP_Practica" -Direction Inbound `
            -Protocol TCP -LocalPort 21 -Action Allow | Out-Null
    }
    Write-Host "  OK" -ForegroundColor Green

    # 5. Sitio FTP en IIS
    Write-Host "[5/7] Configurando Sitio FTP en IIS..." -ForegroundColor White
    Import-Module WebAdministration
    if (-not (Get-WebSite -Name "FTP" -ErrorAction SilentlyContinue)) {
        New-WebFtpSite -Name "FTP" -Port 21 -PhysicalPath "C:\FTP" -Force | Out-Null
    }
    Set-WebConfigurationProperty `
        -Filter "/system.applicationHost/sites/siteDefaults/ftpServer/userIsolation" `
        -Name "mode" -Value "IsolateAllDirectories"
    Write-Host "  OK" -ForegroundColor Green

    # 6. Grupos locales de Windows
    Write-Host "[6/7] Verificando grupos del sistema..." -ForegroundColor White
    $adsi = [ADSI]"WinNT://$env:ComputerName"
    foreach ($g in @("reprobados", "recursadores")) {
        if (-not ($adsi.Children | Where-Object {
            $_.SchemaClassName -eq 'Group' -and $_.Name -eq $g
        })) {
            $nuevoGrupo = $adsi.Create("Group", $g)
            $nuevoGrupo.SetInfo()
        }
    }
    Write-Host "  OK" -ForegroundColor Green

    # 7. Autorizacion, autenticacion y SSL
    Write-Host "[7/7] Aplicando reglas de seguridad IIS..." -ForegroundColor White
    Remove-WebConfigurationProperty `
        -Filter "/system.ftpServer/security/authorization" `
        -Name "." -Location "FTP" -ErrorAction SilentlyContinue

    # Regla anonimo: comodin "*" para que IIS reconozca sesiones anonimas
    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\" `
        -Value @{ accessType = "Allow"; users = "*"; permissions = 1 } `
        -Location "FTP"

    Add-WebConfiguration "/system.ftpServer/security/authorization" `
        -PSPath "IIS:\" `
        -Value @{ accessType = "Allow"; roles = "reprobados,recursadores"; permissions = 3 } `
        -Location "FTP"

    Set-ItemProperty -Path "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.anonymousAuthentication.enabled -Value $true
    Set-ItemProperty -Path "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.anonymousAuthentication.userName -Value "IUSR"
    Set-ItemProperty -Path "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.anonymousAuthentication.password -Value ""
    Set-ItemProperty -Path "IIS:\Sites\FTP" `
        -Name ftpServer.Security.authentication.basicAuthentication.enabled -Value $true
    Set-ItemProperty -Path "IIS:\Sites\FTP" `
        -Name "ftpServer.security.ssl.controlChannelPolicy" -Value 0
    Set-ItemProperty -Path "IIS:\Sites\FTP" `
        -Name "ftpServer.security.ssl.dataChannelPolicy" -Value 0

    # Directorio virtual para que IIS resuelva la raiz del usuario anonimo
    if (-not (Get-WebVirtualDirectory -Site "FTP" -Application "/" -Name "LocalUser" -ErrorAction SilentlyContinue)) {
        New-WebVirtualDirectory -Site "FTP" -Application "/" `
            -Name "LocalUser" -PhysicalPath "C:\FTP\LocalUser" | Out-Null
    }

    Restart-WebItem "IIS:\Sites\FTP"
    Write-Host "  OK" -ForegroundColor Green

    Write-Host ""
    Write-Host "  Servidor FTP configurado exitosamente." -ForegroundColor Green
    Write-Host "=================================================" -ForegroundColor Cyan
}

# -----------------------------------------------------------------------------
# CRUD DE USUARIOS
# -----------------------------------------------------------------------------

function New-UsuarioFTP {
    param (
        [string]$FTPUserName,
        [string]$FTPPassword,
        [string]$FTPUserGroupName
    )

    $adsi = [ADSI]"WinNT://$env:ComputerName"

    # Crear usuario en Windows
    $newUser = $adsi.Create("User", $FTPUserName)
    $newUser.SetPassword($FTPPassword)
    $newUser.SetInfo()

    # Asignar al grupo
    $group = [ADSI]"WinNT://$env:ComputerName/$FTPUserGroupName,group"
    $group.Invoke("Add", "WinNT://$env:ComputerName/$FTPUserName,user")

    # Estructura de carpetas personales
    $userPath = "C:\FTP\LocalUser\$FTPUserName"
    New-Item -Path $userPath -ItemType Directory -Force | Out-Null
    New-Item -Path "$userPath\$FTPUserName" -ItemType Directory -Force | Out-Null

    # Permisos NTFS sobre carpeta personal
    $acl = Get-Acl "$userPath\$FTPUserName"
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $FTPUserName, "Modify",
        "ContainerInherit,ObjectInherit", "None", "Allow"
    )
    $acl.SetAccessRule($rule)
    Set-Acl "$userPath\$FTPUserName" $acl

    # Junctions: carpeta general y carpeta de grupo (mklink /J en lugar de /D)
    cmd /c "mklink /J `"$userPath\general`" `"C:\FTP\LocalUser\Public\general`"" | Out-Null
    cmd /c "mklink /J `"$userPath\$FTPUserGroupName`" `"C:\FTP\grupos\$FTPUserGroupName`"" | Out-Null

    Write-Host "  [OK] Usuario '$FTPUserName' creado en el grupo '$FTPUserGroupName'." -ForegroundColor Green
}

function Set-GrupoFTP {
    param (
        [string]$FTPUserName,
        [string]$NuevoGrupo
    )

    $viejoGrupo = Get-GrupoActualFTP -FTPUserName $FTPUserName

    if ($viejoGrupo -eq $NuevoGrupo) {
        Write-Host "  [!] El usuario ya pertenece al grupo '$NuevoGrupo'." -ForegroundColor Yellow
        return
    }

    # Quitar del grupo anterior
    if ($viejoGrupo -ne "") {
        $oldGroup = [ADSI]"WinNT://$env:ComputerName/$viejoGrupo,group"
        $oldGroup.Invoke("Remove", "WinNT://$env:ComputerName/$FTPUserName,user")
    }

    # Agregar al nuevo grupo
    $newGroup = [ADSI]"WinNT://$env:ComputerName/$NuevoGrupo,group"
    $newGroup.Invoke("Add", "WinNT://$env:ComputerName/$FTPUserName,user")

    # Actualizar junction de grupo
    $userPath = "C:\FTP\LocalUser\$FTPUserName"
    if ($viejoGrupo -ne "") {
        cmd /c "rmdir /S /Q `"$userPath\$viejoGrupo`"" 2>$null
    }
    cmd /c "mklink /J `"$userPath\$NuevoGrupo`" `"C:\FTP\grupos\$NuevoGrupo`"" | Out-Null

    # Reiniciar servicio FTP para aplicar permisos
    Write-Host "  Actualizando permisos en tiempo real..." -ForegroundColor White
    Restart-Service ftpsvc -Force

    Write-Host "  [OK] '$FTPUserName' movido de '$viejoGrupo' a '$NuevoGrupo'." -ForegroundColor Green
}

function Remove-UsuarioFTP {
    param ([string]$FTPUserName)

    # Eliminar usuario de Windows
    $adsi = [ADSI]"WinNT://$env:ComputerName"
    $adsi.Delete("User", $FTPUserName)

    # Eliminar carpeta y junctions
    $userPath = "C:\FTP\LocalUser\$FTPUserName"
    if (Test-Path $userPath) {
        Remove-Item $userPath -Recurse -Force
    }

    Write-Host "  [OK] Usuario '$FTPUserName' eliminado del servidor." -ForegroundColor Green
}