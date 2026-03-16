# =============================================================================
# cleanup_windows.ps1 — Limpieza profunda para Windows Server 2022
# Deja el sistema listo para ejecutar main_windows.ps1 desde cero
# Uso: Ejecutar como Administrador en PowerShell
# =============================================================================

$currentPrincipal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "[ERROR] Ejecuta como Administrador." -ForegroundColor Red
    Read-Host "Presiona Enter para salir"
    exit 1
}

Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "  ╔═════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║   Limpieza Profunda — Windows Server 2022  ║" -ForegroundColor Cyan
Write-Host "  ╚═════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# =============================================================================
# 1. MATAR PROCESOS DE SERVIDORES STANDALONE
# =============================================================================
Write-Host "[1/7] Matando procesos de servidores HTTP standalone..." -ForegroundColor Yellow

$procesos = @("httpd", "nginx")
foreach ($proc in $procesos) {
    $p = Get-Process -Name $proc -ErrorAction SilentlyContinue
    if ($p) {
        Stop-Process -Name $proc -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Proceso '$proc' terminado." -ForegroundColor Green
    } else {
        Write-Host "  [--] '$proc' no estaba corriendo." -ForegroundColor DarkGray
    }
}

Start-Sleep -Seconds 2

# =============================================================================
# 2. LIMPIAR IIS — SITIOS CREADOS POR SCRIPTS ANTERIORES
# =============================================================================
Write-Host "[2/7] Limpiando sitios IIS de scripts anteriores..." -ForegroundColor Yellow

try {
    Import-Module WebAdministration -ErrorAction SilentlyContinue

    if (Get-Module -Name WebAdministration -ErrorAction SilentlyContinue) {

        # Obtener todos los sitios que NO son el Default Web Site
        $sitios = Get-Website -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -ne "Default Web Site"
        }

        foreach ($sitio in $sitios) {
            Write-Host "  [*] Eliminando sitio IIS: $($sitio.Name)..." -ForegroundColor DarkGray
            Stop-Website  -Name $sitio.Name -ErrorAction SilentlyContinue
            Remove-Website -Name $sitio.Name -ErrorAction SilentlyContinue
            Write-Host "  [OK] Sitio '$($sitio.Name)' eliminado." -ForegroundColor Green
        }

        # Detener también el Default Web Site para dejar IIS limpio
        if (Get-Website -Name "Default Web Site" -ErrorAction SilentlyContinue) {
            Stop-Website -Name "Default Web Site" -ErrorAction SilentlyContinue
            Write-Host "  [OK] Default Web Site detenido." -ForegroundColor DarkGray
        }

        # Detener servicios IIS
        Stop-Service W3SVC -Force -ErrorAction SilentlyContinue
        Stop-Service WAS   -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Servicios IIS (W3SVC, WAS) detenidos." -ForegroundColor Green

    } else {
        Write-Host "  [--] WebAdministration no disponible (IIS no estaba instalado)." -ForegroundColor DarkGray
    }
} catch {
    Write-Host "  [!] Error limpiando IIS: $_" -ForegroundColor Yellow
}

# =============================================================================
# 3. LIMPIAR DIRECTORIOS WEB RESIDUALES EN inetpub
# =============================================================================
Write-Host "[3/7] Limpiando directorios web residuales..." -ForegroundColor Yellow

# Directorios IIS creados por scripts anteriores
$patronesIIS = @(
    "C:\inetpub\wwwroot\IIS_*",
    "C:\inetpub\wwwroot\IIS_Puerto_*"
)

foreach ($patron in $patronesIIS) {
    $dirs = Get-Item $patron -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Eliminado: $($dir.FullName)" -ForegroundColor Green
    }
}

# Limpiar directorios de Apache extraídos por scripts anteriores
# (NO eliminar los ZIPs, solo las carpetas extraídas)
$patronesApache = @("C:\Apache24", "C:\apache_*")
foreach ($patron in $patronesApache) {
    $dirs = Get-Item $patron -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        # Solo eliminar si es directorio (no ZIP)
        if ($dir.PSIsContainer) {
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Directorio Apache eliminado: $($dir.FullName)" -ForegroundColor Green
        }
    }
}

# Limpiar directorios de Nginx extraídos por scripts anteriores
$patronesNginx = @("C:\nginx*", "C:\nginx_server")
foreach ($patron in $patronesNginx) {
    $dirs = Get-Item $patron -ErrorAction SilentlyContinue
    foreach ($dir in $dirs) {
        # Solo eliminar si es directorio (no ZIP)
        if ($dir.PSIsContainer) {
            Remove-Item -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Directorio Nginx eliminado: $($dir.FullName)" -ForegroundColor Green
        }
    }
}

Write-Host "  [OK] Directorios web limpiados (ZIPs conservados en C:\)." -ForegroundColor Green

# =============================================================================
# 4. ELIMINAR REGLAS DE FIREWALL DE SCRIPTS ANTERIORES
# =============================================================================
Write-Host "[4/7] Eliminando reglas de firewall de scripts anteriores..." -ForegroundColor Yellow

# Patrones de nombres que usan scripts anteriores y el nuevo script
$patronesFirewall = @(
    "HTTP-IIS-*",
    "HTTP-Apache-*",
    "HTTP-Nginx-*",
    "HTTP-Custom*",
    "HTTP-IIS*",
    "IIS-HTTP*"
)

$eliminadas = 0
foreach ($patron in $patronesFirewall) {
    $reglas = Get-NetFirewallRule -DisplayName $patron -ErrorAction SilentlyContinue
    foreach ($regla in $reglas) {
        Remove-NetFirewallRule -DisplayName $regla.DisplayName -ErrorAction SilentlyContinue
        Write-Host "  [OK] Regla eliminada: $($regla.DisplayName)" -ForegroundColor Green
        $eliminadas++
    }
}

if ($eliminadas -eq 0) {
    Write-Host "  [--] No se encontraron reglas de firewall de scripts anteriores." -ForegroundColor DarkGray
}

# =============================================================================
# 5. VERIFICAR QUE LOS PUERTOS HTTP ESTÉN LIBRES
# =============================================================================
Write-Host "[5/7] Verificando puertos HTTP..." -ForegroundColor Yellow

$puertosVerificar = @(80, 443, 8080, 8443, 8888)
$todoLibre = $true

foreach ($p in $puertosVerificar) {
    $conn = Test-NetConnection -ComputerName localhost -Port $p `
                -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    if ($conn.TcpTestSucceeded) {
        Write-Host "  [!] ADVERTENCIA: Puerto $p todavía en uso." -ForegroundColor Yellow

        # Intentar identificar qué proceso usa el puerto
        $netstat = netstat -ano 2>/dev/null | Select-String ":$p\s"
        if ($netstat) {
            Write-Host "       $netstat" -ForegroundColor DarkGray
        }
        $todoLibre = $false
    } else {
        Write-Host "  [OK] Puerto $p libre." -ForegroundColor Green
    }
}

if ($todoLibre) {
    Write-Host "  [OK] Todos los puertos HTTP verificados están libres." -ForegroundColor Green
}

# =============================================================================
# 6. VERIFICAR QUE LOS ZIPs ESTÁN LISTOS EN C:\
# =============================================================================
Write-Host "[6/7] Verificando ZIPs disponibles en C:\..." -ForegroundColor Yellow

$zipsEsperados = @(
    @{ path = "C:\apache_2.4.64.zip"; nombre = "Apache 2.4.64 (Legacy)"   },
    @{ path = "C:\apache_2.4.65.zip"; nombre = "Apache 2.4.65 (Stable)"   },
    @{ path = "C:\apache_2.4.66.zip"; nombre = "Apache 2.4.66 (Latest)"   },
    @{ path = "C:\nginx_1.26.3.zip";  nombre = "Nginx 1.26.3 (Legacy)"    },
    @{ path = "C:\nginx_1.28.2.zip";  nombre = "Nginx 1.28.2 (Stable)"    },
    @{ path = "C:\nginx_1.29.6.zip";  nombre = "Nginx 1.29.6 (Mainline)"  }
)

$zipsFaltantes = 0
foreach ($zip in $zipsEsperados) {
    if (Test-Path $zip.path) {
        $size = [math]::Round((Get-Item $zip.path).Length / 1MB, 1)
        Write-Host "  [OK] $($zip.nombre) — $($zip.path) ($size MB)" -ForegroundColor Green
    } else {
        Write-Host "  [!] FALTANTE: $($zip.path) — $($zip.nombre)" -ForegroundColor Red
        $zipsFaltantes++
    }
}

if ($zipsFaltantes -gt 0) {
    Write-Host ""
    Write-Host "  [!] Faltan $zipsFaltantes ZIPs. El script funcionará solo con los que existan." -ForegroundColor Yellow
}

# =============================================================================
# 7. LIMPIAR VARIABLES DE AMBIENTE RESIDUALES Y TEMP
# =============================================================================
Write-Host "[7/7] Limpieza final..." -ForegroundColor Yellow

# Limpiar archivos temporales de instalaciones anteriores
$tempFiles = Get-Item "C:\apache_*.zip.tmp", "C:\nginx_*.zip.tmp" -ErrorAction SilentlyContinue
foreach ($f in $tempFiles) {
    Remove-Item $f.FullName -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Temp eliminado: $($f.FullName)" -ForegroundColor DarkGray
}

Write-Host "  [OK] Limpieza final completada." -ForegroundColor Green

# =============================================================================
# RESUMEN FINAL
# =============================================================================
Write-Host ""
Write-Host "  ╔═════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "  ║        ✅  Limpieza Completada              ║" -ForegroundColor Green
Write-Host "  ╠═════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host "  ║  El sistema está listo para:                ║" -ForegroundColor Green
Write-Host "  ║  .\main_windows.ps1                         ║" -ForegroundColor Green
Write-Host "  ╚═════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "  Estado actual de puertos en escucha:" -ForegroundColor Cyan
netstat -ano 2>/dev/null | Select-String "LISTENING" | `
    Where-Object { $_ -notmatch "127\.0\.0\.1" } | `
    Select-Object -First 15
Write-Host ""