# =============================================================================
# menu_ftp.ps1 - Menú Administrador FTP para Windows Server 2022
# Equivalente a menu_ftp.sh (Fedora/vsftpd) => Windows Server / IIS FTP
# Se integra al orquestador main.ps1 como: Menu-FTP
# =============================================================================

# --- Resolución robusta de la ruta de ftp_functions.ps1 ---
# $PSScriptRoot puede quedar vacío si este script es dot-sourced desde main.ps1,
# por eso buscamos la ruta real con múltiples estrategias.
function _Resolver-RutaFunciones {
    # 1. Ruta relativa al archivo actual (funciona si se ejecuta directamente)
    if ($PSScriptRoot -and (Test-Path "$PSScriptRoot\ftp_functions.ps1")) {
        return "$PSScriptRoot\ftp_functions.ps1"
    }
    # 2. Mismo directorio que main.ps1 (cuando se dot-sourcea desde main.ps1)
    $mainScript = $MyInvocation.ScriptName
    if ($mainScript) {
        $mainDir = Split-Path $mainScript -Parent
        $candidate = Join-Path $mainDir "modules\ftp_functions.ps1"
        if (Test-Path $candidate) { return $candidate }
    }
    # 3. Relativo al directorio de trabajo actual
    $candidates = @(
        ".\modules\ftp_functions.ps1",
        "$PSScriptRoot\..\modules\ftp_functions.ps1",
        (Join-Path (Split-Path $PSCommandPath -Parent) "ftp_functions.ps1")
    )
    foreach ($c in $candidates) {
        if ($c -and (Test-Path $c)) { return (Resolve-Path $c).Path }
    }
    return $null
}

$_ftpFunctionsPath = _Resolver-RutaFunciones

if ($_ftpFunctionsPath) {
    . $_ftpFunctionsPath
} else {
    Write-Host "[ERROR] No se encontró ftp_functions.ps1." -ForegroundColor Red
    Write-Host "        Asegúrate de que esté en la carpeta 'modules\'" -ForegroundColor Yellow
    return
}

# ============================================================
# FUNCIÓN: Instalar-ServicioFTP
# Nueva: instala el rol IIS-FTP desde cero y valida prereqs
# ============================================================
function Instalar-ServicioFTP {
    Write-Host "`n[+] Instalando rol de Servidor FTP en Windows Server 2022..." -ForegroundColor Cyan

    # Verificar que se ejecuta como Administrador
    $esAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                 [Security.Principal.WindowsBuiltInRole]"Administrator")
    if (!$esAdmin) {
        Write-Host "[ERROR] Debes ejecutar PowerShell como Administrador." -ForegroundColor Red
        return
    }

    $features = @(
        @{Name="Web-Server";       Desc="IIS (Servidor Web base)"},
        @{Name="Web-Ftp-Server";   Desc="Servidor FTP"},
        @{Name="Web-Ftp-Service";  Desc="Servicio FTP"},
        @{Name="Web-Mgmt-Console"; Desc="Consola de administracion IIS"}
    )

    $reinicioRequerido = $false
    foreach ($f in $features) {
        $feat = Get-WindowsFeature -Name $f.Name
        if ($feat.InstallState -eq "Installed") {
            Write-Host "  [✓] Ya instalado:  $($f.Desc)" -ForegroundColor DarkGray
        } else {
            Write-Host "  [~] Instalando:    $($f.Desc)..." -ForegroundColor Yellow
            $result = Install-WindowsFeature -Name $f.Name -IncludeManagementTools
            if ($result.Success) {
                Write-Host "  [✓] Instalado:     $($f.Desc)" -ForegroundColor Green
                if ($result.RestartNeeded -eq "Yes") { $reinicioRequerido = $true }
            } else {
                Write-Host "  [!] FALLO:         $($f.Desc)" -ForegroundColor Red
            }
        }
    }

    Write-Host "`n[+] Configurando servicio ftpsvc..." -ForegroundColor Cyan
    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if ($svc) {
        Set-Service -Name "ftpsvc" -StartupType Automatic
        if ($svc.Status -ne "Running") {
            Start-Service -Name "ftpsvc"
            Write-Host "  [✓] Servicio ftpsvc iniciado." -ForegroundColor Green
        } else {
            Write-Host "  [✓] Servicio ftpsvc ya en ejecucion." -ForegroundColor Green
        }
    } else {
        Write-Host "  [!] Servicio ftpsvc no encontrado aun. Puede requerir reinicio." -ForegroundColor Yellow
    }

    Import-Module WebAdministration -ErrorAction SilentlyContinue
    if (Get-Module -Name WebAdministration) {
        Write-Host "  [✓] Modulo WebAdministration cargado." -ForegroundColor Green
    } else {
        Write-Host "  [!] WebAdministration no disponible aun." -ForegroundColor Yellow
    }

    if ($reinicioRequerido) {
        Write-Host "`n[!] Se requiere REINICIAR el servidor para completar la instalacion." -ForegroundColor Yellow
        $resp = Read-Host "Reiniciar ahora? (s/n)"
        if ($resp -eq "s") { Restart-Computer -Force }
    } else {
        Write-Host "`n[✓] Instalacion completada. Usa la opcion 6 para inicializar carpetas y sitio FTP." -ForegroundColor Green
    }
}

# ============================================================
# FUNCIÓN: Menu-FTP
# ============================================================
function Menu-FTP {

    # Verificar que las funciones estén cargadas correctamente
    if (!(Get-Command "Inicializar-SistemaFTP" -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] Las funciones FTP no se cargaron. Ruta buscada:" -ForegroundColor Red
        Write-Host "        $_ftpFunctionsPath" -ForegroundColor Yellow
        Read-Host "Presione Enter para continuar"
        return
    }

    do {
        Clear-Host
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "   ADMINISTRADOR DE SERVIDOR FTP"       -ForegroundColor Cyan
        Write-Host "       Windows Server 2022 / IIS"       -ForegroundColor DarkCyan
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "  1) Instalar servicio FTP (IIS)"
        Write-Host "  2) Alta masiva de usuarios"
        Write-Host "  3) Modificar grupo de usuario"
        Write-Host "  4) Listar usuarios registrados"
        Write-Host "  5) Verificar estado / IP del servicio"
        Write-Host "  6) INICIALIZAR / RECONFIGURAR SERVICIO"
        Write-Host "  0) Regresar al Menu Principal"
        Write-Host "---------------------------------------" -ForegroundColor DarkGray
        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {

            "1" {
                Instalar-ServicioFTP
            }

            "2" {
                $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
                if (!$svc -or $svc.Status -ne "Running") {
                    Write-Host "[!] Servicio FTP no activo. Use opcion 1 para instalar y opcion 6 para inicializar." -ForegroundColor Yellow
                    break
                }

                [int]$n = 0
                while ($n -lt 1) {
                    $inputN = Read-Host "Numero de usuarios a crear"
                    if ([int]::TryParse($inputN, [ref]$n) -and $n -ge 1) { break }
                    Write-Host "  [!] Ingrese un numero valido mayor a 0." -ForegroundColor Yellow
                }

                for ($i = 1; $i -le $n; $i++) {
                    Write-Host "`n--- Usuario $i de $n ---" -ForegroundColor DarkCyan
                    $uname = Read-Host "  Username"
                    $secPass = Read-Host "  Password" -AsSecureString
                    $upass   = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
                                   [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secPass))
                    $g_op = ""
                    while ($g_op -notin @("1","2")) {
                        $g_op = Read-Host "  Grupo (1=reprobados, 2=recursadores)"
                    }
                    $ugroup = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                    Crear-UsuarioFTP -Usuario $uname -Password $upass -Grupo $ugroup
                }
            }

            "3" {
                $uname = Read-Host "Usuario a modificar"
                $g_op  = ""
                while ($g_op -notin @("1","2")) {
                    $g_op = Read-Host "Nuevo grupo (1=reprobados, 2=recursadores)"
                }
                $ugroup = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                Modificar-GrupoUsuarioFTP -Usuario $uname -NuevoGrupo $ugroup
            }

            "4" {
                Listar-UsuariosFTP
            }

            "5" {
                Verificar-ServicioFTP
            }

            "6" {
                $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
                if (!$svc) {
                    Write-Host "[!] Servicio FTP no instalado. Use la opcion 1 primero." -ForegroundColor Red
                } else {
                    Write-Host "`n[!] Reaplicando configuracion completa..." -ForegroundColor Yellow
                    Inicializar-SistemaFTP
                }
            }

            "0" {
                Write-Host "`nRegresando al Menu Principal..." -ForegroundColor DarkGray
            }

            default {
                Write-Host "`n[!] Opcion invalida. Intente de nuevo." -ForegroundColor Red
            }
        }

        if ($opcion -ne "0") {
            Write-Host ""
            Read-Host "Presione Enter para continuar"
        }

    } while ($opcion -ne "0")
}
