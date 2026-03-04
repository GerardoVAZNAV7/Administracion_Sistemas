# =============================================================================
# menu_ftp.ps1 - Solo el menú. Toda la lógica está en ftp_functions.ps1
# main.ps1 hace dot-source de este archivo, que a su vez carga ftp_functions.ps1
# La función expuesta al orquestador se llama: Menu-FTP
# =============================================================================

# ── Cargar ftp_functions.ps1 con ruta robusta ──────────────────────────────
# Cuando main.ps1 hace ". modules\menu_ftp.ps1", $PSScriptRoot apunta a la
# carpeta de main.ps1 (no a modules\). Por eso usamos $PSScriptRoot si existe,
# y como fallback calculamos la ruta desde $MyInvocation.
$_menuFtpDir = if ($PSScriptRoot) { $PSScriptRoot } `
               else { Split-Path $MyInvocation.MyCommand.Path -Parent }

$_ftpFunctions = Join-Path $_menuFtpDir "ftp_functions.ps1"

if (Test-Path $_ftpFunctions) {
    . $_ftpFunctions
} else {
    Write-Host "[ERROR] No se encontro ftp_functions.ps1 en: $_ftpFunctions" -ForegroundColor Red
    Write-Host "        Verifica que ambos archivos esten en la carpeta modules\" -ForegroundColor Yellow
}

# ── Función principal expuesta al orquestador (main.ps1 llama Menu-FTP) ────
function global:Menu-FTP {

    # Verificar que ftp_functions.ps1 se cargó correctamente
    if (!(Get-Command "Inicializar-SistemaFTP" -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] ftp_functions.ps1 no se cargo. Revisa que exista en modules\" -ForegroundColor Red
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

            "1" { Instalar-ServicioFTP }

            "2" {
                $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
                if (!$svc -or $svc.Status -ne "Running") {
                    Write-Host "[!] Servicio FTP no activo. Usa opcion 1 (instalar) y luego opcion 6 (inicializar)." -ForegroundColor Yellow
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
                    $uname   = Read-Host "  Username"
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

            "4" { Listar-UsuariosFTP }

            "5" { Verificar-ServicioFTP }

            "6" {
                $svc = Get-Service -Name "ftpsvc" -ErrorAction SilentlyContinue
                if (!$svc) {
                    Write-Host "[!] Servicio no instalado. Usa la opcion 1 primero." -ForegroundColor Red
                } else {
                    Inicializar-SistemaFTP
                }
            }

            "0" { Write-Host "`nRegresando al Menu Principal..." -ForegroundColor DarkGray }

            default { Write-Host "`n[!] Opcion invalida." -ForegroundColor Red }
        }

        if ($opcion -ne "0") {
            Write-Host ""
            Read-Host "Presione Enter para continuar"
        }

    } while ($opcion -ne "0")
}
