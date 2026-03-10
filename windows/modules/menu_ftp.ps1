# =============================================================================
# menu_ftp.ps1 — Menu interactivo de gestion FTP
# Ubicacion: windows/modules/menu_ftp.ps1
# Llamado desde: windows/main.ps1
# Depende de:    windows/modules/ftp_functions.ps1
# =============================================================================

function menu-ftp {

    # Importar funciones si no estan cargadas
    $modulePath = Join-Path $PSScriptRoot "ftp_functions.ps1"
    if (-not (Get-Command "Initialize-ServidorFTP" -ErrorAction SilentlyContinue)) {
        . $modulePath   # dot-source para que las funciones queden en el scope actual
    }

    # Configurar el servidor la primera vez (idempotente — seguro llamar siempre)
    Initialize-ServidorFTP

    # -------------------------------------------------------------------------
    # Bucle principal del menu
    # -------------------------------------------------------------------------
    do {
        Write-Host ""
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "        GESTOR DE USUARIOS FTP (WINDOWS)"        -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  1. Agregar usuarios"
        Write-Host "  2. Cambiar de grupo"
        Write-Host "  3. Eliminar usuario"
        Write-Host "  4. Volver al menu principal"
        Write-Host "-------------------------------------------------" -ForegroundColor DarkGray
        $opcion = Read-Host "  Elige una opcion (1-4)"

        switch ($opcion) {

            # ------------------------------------------------------------------
            "1" {
                Write-Host ""
                Write-Host "--- Agregar Usuarios ---" -ForegroundColor White

                $rawNum = Read-Host "  Cuantos usuarios deseas agregar?"
                $num = 0
                if (-not [int]::TryParse($rawNum, [ref]$num) -or $num -lt 1) {
                    Write-Host "  [!] Numero no valido." -ForegroundColor Yellow
                    break
                }

                for ($i = 1; $i -le $num; $i++) {
                    Write-Host ""
                    Write-Host "  -- Usuario $i de $num --" -ForegroundColor Cyan
                    $nombre = Invoke-CapturarUsuarioFTPValido -mensaje "  Nombre de usuario"
                    $contra = Invoke-CapturarContra
                    $grupo  = Invoke-CapturarGrupoFTP
                    New-UsuarioFTP -FTPUserName $nombre -FTPPassword $contra -FTPUserGroupName $grupo
                }
            }

            # ------------------------------------------------------------------
            "2" {
                Write-Host ""
                Write-Host "--- Cambiar de Grupo ---" -ForegroundColor White

                $nombre = Read-Host "  Nombre del usuario a modificar"

                if (-not (Invoke-UsuarioExiste -nombreUsuario $nombre)) {
                    Write-Host "  [!] El usuario '$nombre' no existe." -ForegroundColor Yellow
                    break
                }

                $grupoActual = Get-GrupoActualFTP -FTPUserName $nombre
                if ($grupoActual -eq "") {
                    Write-Host "  [!] El usuario '$nombre' no pertenece a ningun grupo FTP." -ForegroundColor Yellow
                    break
                }
                Write-Host "  Grupo actual: $grupoActual" -ForegroundColor DarkGray

                $nuevoGrupo = Invoke-CapturarGrupoFTP
                Set-GrupoFTP -FTPUserName $nombre -NuevoGrupo $nuevoGrupo
            }

            # ------------------------------------------------------------------
            "3" {
                Write-Host ""
                Write-Host "--- Eliminar Usuario ---" -ForegroundColor White

                $nombre = Read-Host "  Nombre del usuario a eliminar"

                if (-not (Invoke-UsuarioExiste -nombreUsuario $nombre)) {
                    Write-Host "  [!] El usuario '$nombre' no existe." -ForegroundColor Yellow
                    break
                }

                $confirm = Read-Host "  Confirmar eliminacion de '$nombre' (s/n)"
                if ($confirm -eq "s") {
                    Remove-UsuarioFTP -FTPUserName $nombre
                }
                else {
                    Write-Host "  Operacion cancelada." -ForegroundColor DarkGray
                }
            }

            # ------------------------------------------------------------------
            "4" {
                Write-Host "  Volviendo al menu principal..." -ForegroundColor DarkGray
            }

            # ------------------------------------------------------------------
            default {
                Write-Host "  [!] Opcion no valida. Intenta de nuevo." -ForegroundColor Yellow
            }
        }

    } while ($opcion -ne "4")
}