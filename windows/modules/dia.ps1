#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Limpieza TOTAL del servidor FTP (IIS) antes de ejecutar el script principal.
    Elimina sitio, usuarios, grupos, directorios y configuraciones previas.
#>

$Global:BASE_DATA  = "C:\inetpub\ftproot"
$Global:FTP_ROOT   = "C:\FTP_Users"
$Global:LOCAL_USER = "$Global:FTP_ROOT\LocalUser"
$Global:SITE_NAME  = "ServidorPracticas"

$appcmd = "$env:windir\system32\inetsrv\appcmd.exe"

# ─────────────────────────────────────────────
# VERIFICAR ADMIN
# ─────────────────────────────────────────────
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "[ERROR] Ejecutar como Administrador (PowerShell como Admin)."
    exit 1
}

Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "   LIMPIEZA TOTAL DEL SERVIDOR FTP       " -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

# ─────────────────────────────────────────────
# 1. DETENER Y LIMPIAR SERVICIO FTP
# ─────────────────────────────────────────────
Write-Host "[1] Deteniendo servicio FTP (ftpsvc)..." -ForegroundColor Cyan
try {
    Stop-Service ftpsvc -Force -ErrorAction SilentlyContinue
    Write-Host "    [OK] Servicio detenido." -ForegroundColor Green
} catch {
    Write-Host "    [!] El servicio ftpsvc no estaba activo." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────
# 2. ELIMINAR SITIO FTP EN IIS
# ─────────────────────────────────────────────
Write-Host "[2] Eliminando sitio IIS '$Global:SITE_NAME'..." -ForegroundColor Cyan
Import-Module WebAdministration -ErrorAction SilentlyContinue
if (Get-Website -Name $Global:SITE_NAME -ErrorAction SilentlyContinue) {
    & $appcmd delete site /site.name:"$Global:SITE_NAME" | Out-Null
    Write-Host "    [OK] Sitio eliminado." -ForegroundColor Green
} else {
    Write-Host "    [!] El sitio no existia." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────
# 3. ELIMINAR USUARIOS LOCALES CREADOS (excepto cuentas del sistema)
# ─────────────────────────────────────────────
Write-Host "[3] Eliminando usuarios locales FTP..." -ForegroundColor Cyan
$excluir = @("Administrator","Guest","DefaultAccount","WDAGUtilityAccount")
$usuariosFTP = Get-LocalUser | Where-Object { $_.Name -notin $excluir }

if ($usuariosFTP) {
    foreach ($u in $usuariosFTP) {
        try {
            Remove-LocalUser -Name $u.Name -ErrorAction Stop
            Write-Host "    [OK] Usuario '$($u.Name)' eliminado." -ForegroundColor Green
        } catch {
            Write-Host "    [!] No se pudo eliminar '$($u.Name)': $_" -ForegroundColor Red
        }
    }
} else {
    Write-Host "    [!] No habia usuarios FTP para eliminar." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────
# 4. ELIMINAR GRUPOS LOCALES
# ─────────────────────────────────────────────
Write-Host "[4] Eliminando grupos locales..." -ForegroundColor Cyan
foreach ($g in @("reprobados", "recursadores")) {
    if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) {
        Remove-LocalGroup -Name $g -ErrorAction SilentlyContinue
        Write-Host "    [OK] Grupo '$g' eliminado." -ForegroundColor Green
    } else {
        Write-Host "    [!] Grupo '$g' no existia." -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────
# 5. ELIMINAR DIRECTORIOS DE DATOS (general, reprobados, recursadores)
# ─────────────────────────────────────────────
Write-Host "[5] Eliminando directorios de datos FTP..." -ForegroundColor Cyan
foreach ($dir in @("general", "reprobados", "recursadores")) {
    $path = Join-Path $Global:BASE_DATA $dir
    if (Test-Path $path) {
        # Quitar atributos de solo lectura recursivamente antes de borrar
        Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $_.Attributes = 'Normal'
        }
        Remove-Item $path -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    [OK] Eliminado: $path" -ForegroundColor Green
    } else {
        Write-Host "    [!] No existia: $path" -ForegroundColor Yellow
    }
}

# ─────────────────────────────────────────────
# 6. ELIMINAR DIRECTORIO RAIZ DE USUARIOS FTP (C:\FTP_Users)
# ─────────────────────────────────────────────
Write-Host "[6] Eliminando directorio raiz de usuarios ($Global:FTP_ROOT)..." -ForegroundColor Cyan
if (Test-Path $Global:FTP_ROOT) {
    # Eliminar symlinks primero (rmdir para junction points)
    Get-ChildItem $Global:FTP_ROOT -Recurse -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            cmd /c "rmdir `"$($_.FullName)`"" | Out-Null
        }
    }
    Remove-Item $Global:FTP_ROOT -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "    [OK] Directorio $Global:FTP_ROOT eliminado." -ForegroundColor Green
} else {
    Write-Host "    [!] No existia $Global:FTP_ROOT." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────
# 7. LIMPIAR REGLAS DE AUTORIZACION FTP EN IIS (applicationHost.config)
# ─────────────────────────────────────────────
Write-Host "[7] Limpiando configuracion residual en applicationHost.config..." -ForegroundColor Cyan
$appHostPath = "$env:windir\system32\inetsrv\config\applicationHost.config"
if (Test-Path $appHostPath) {
    try {
        [xml]$xml = Get-Content $appHostPath -Encoding UTF8
        # Buscar y eliminar el site si quedara alguna referencia
        $sites = $xml.configuration.'system.applicationHost'.sites.site | Where-Object { $_.name -eq $Global:SITE_NAME }
        if ($sites) {
            $sites | ForEach-Object { $_.ParentNode.RemoveChild($_) | Out-Null }
            $xml.Save($appHostPath)
            Write-Host "    [OK] Referencia residual del sitio eliminada del config." -ForegroundColor Green
        } else {
            Write-Host "    [!] No habia referencias residuales en applicationHost.config." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "    [!] No se pudo limpiar applicationHost.config: $_" -ForegroundColor Red
    }
} else {
    Write-Host "    [!] No se encontro applicationHost.config." -ForegroundColor Yellow
}

# ─────────────────────────────────────────────
# 8. REINICIAR IIS PARA APLICAR CAMBIOS
# ─────────────────────────────────────────────
Write-Host "[8] Reiniciando IIS (iisreset)..." -ForegroundColor Cyan
try {
    iisreset /restart | Out-Null
    Write-Host "    [OK] IIS reiniciado." -ForegroundColor Green
} catch {
    Write-Host "    [!] No se pudo reiniciar IIS: $_" -ForegroundColor Red
}

# ─────────────────────────────────────────────
# RESUMEN FINAL
# ─────────────────────────────────────────────
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "   LIMPIEZA COMPLETADA EXITOSAMENTE      " -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Magenta
Write-Host "Ahora puedes ejecutar el script principal:"
Write-Host "   .\ServidorFTP.ps1" -ForegroundColor Cyan
Write-Host ""