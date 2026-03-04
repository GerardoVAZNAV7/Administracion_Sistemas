# =============================================================================
# menu_ftp.ps1 - Menú Administrador FTP para Windows Server 2022
# Equivalente a menu_ftp.sh (Fedora/vsftpd) => Windows Server / IIS FTP
# Se integra al orquestador main.ps1 como: Menu-FTP
# =============================================================================

# Importar funciones FTP (ruta relativa al módulo)
$_ftpFunctionsPath = Join-Path $PSScriptRoot "ftp_functions.ps1"
if (Test-Path $_ftpFunctionsPath) {
    . $_ftpFunctionsPath
} else {
    Write-Host "[ERROR] No se encontró ftp_functions.ps1 en: $_ftpFunctionsPath" -ForegroundColor Red
    return
}

function Menu-FTP {

    # Auto-inicializar si el servicio FTP no está corriendo
    $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
    if (!$svc -or $svc.Status -ne "Running") {
        Write-Host "`n[!] Servicio FTP no activo. Inicializando sistema..." -ForegroundColor Yellow
        Inicializar-SistemaFTP
    }

    do {
        Clear-Host
        Write-Host ""
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "   ADMINISTRADOR DE SERVIDOR FTP"       -ForegroundColor Cyan
        Write-Host "       Windows Server 2022 / IIS"       -ForegroundColor DarkCyan
        Write-Host "=======================================" -ForegroundColor Cyan
        Write-Host "  1) Alta masiva de usuarios"
        Write-Host "  2) Modificar grupo de usuario"
        Write-Host "  3) Listar usuarios registrados"
        Write-Host "  4) Verificar estado / IP del servicio"
        Write-Host "  5) RECONFIGURAR SERVICIO (Reset)"
        Write-Host "  0) Regresar al Menu Principal"
        Write-Host "---------------------------------------" -ForegroundColor DarkGray
        $opcion = Read-Host "Seleccione una opcion"

        switch ($opcion) {

            "1" {
                # Alta masiva de usuarios
                [int]$n = 0
                while ($n -lt 1) {
                    $input = Read-Host "Numero de usuarios a crear"
                    if ([int]::TryParse($input, [ref]$n) -and $n -ge 1) { break }
                    Write-Host "  [!] Ingrese un número válido mayor a 0." -ForegroundColor Yellow
                }

                for ($i = 1; $i -le $n; $i++) {
                    Write-Host "`n--- Usuario $i de $n ---" -ForegroundColor DarkCyan
                    $uname = Read-Host "  Username"

                    # Leer password de forma segura (oculta)
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

            "2" {
                # Modificar grupo de usuario existente
                $uname = Read-Host "Usuario a modificar"
                $g_op  = ""
                while ($g_op -notin @("1","2")) {
                    $g_op = Read-Host "Nuevo grupo (1=reprobados, 2=recursadores)"
                }
                $ugroup = if ($g_op -eq "1") { "reprobados" } else { "recursadores" }
                Modificar-GrupoUsuarioFTP -Usuario $uname -NuevoGrupo $ugroup
            }

            "3" {
                # Listar usuarios registrados
                Listar-UsuariosFTP
            }

            "4" {
                # Verificar estado del servicio
                Verificar-ServicioFTP
            }

            "5" {
                # Reconfigurar / Reset completo del servicio
                Write-Host "`n[!] Reaplicando configuracion completa del servicio FTP..." -ForegroundColor Yellow
                Inicializar-SistemaFTP
            }

            "0" {
                # Regresar al menú principal
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
