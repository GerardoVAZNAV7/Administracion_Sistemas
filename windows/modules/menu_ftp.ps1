# =============================================================================
# menu_ftp.ps1
# Ubicacion: windows/modules/menu_ftp.ps1
# =============================================================================

function menu-ftp {

    $modulePath = Join-Path $PSScriptRoot "ftp_functions.ps1"
    if (-not (Get-Command "Initialize-ServidorFTP" -ErrorAction SilentlyContinue)) {
        . $modulePath
    }

    Initialize-ServidorFTP

    do {
        Write-Host ""
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "        GESTOR DE USUARIOS FTP (WINDOWS)"        -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "  1. Agregar usuarios"
        Write-Host "  2. Cambiar de grupo"
        Write-Host "  3. Eliminar usuario"
        Write-Host "  4. Listar usuarios"
        Write-Host "  5. Reconfigurar servidor (Reset)"
        Write-Host "  6. Volver al menu principal"
        Write-Host "-------------------------------------------------" -ForegroundColor DarkGray
        $op = Read-Host "  Elige una opcion (1-6)"

        switch ($op) {

            "1" {
                Write-Host ""
                Write-Host "--- Agregar Usuarios ---" -ForegroundColor White
                $rawN = Read-Host "  Cuantos usuarios?"
                $n = 0
                if (-not [int]::TryParse($rawN, [ref]$n) -or $n -lt 1) {
                    Write-Host "  [!] Numero invalido." -ForegroundColor Yellow
                    break
                }
                for ($i = 1; $i -le $n; $i++) {
                    Write-Host ""
                    Write-Host "  -- Usuario $i de $n --" -ForegroundColor Cyan
                    $nom   = Invoke-CapturarUsuarioFTPValido -mensaje "Nombre de usuario"
                    $pass  = Invoke-CapturarContra
                    $grupo = Invoke-CapturarGrupoFTP
                    New-UsuarioFTP -FTPUserName $nom -FTPPassword $pass -FTPUserGroupName $grupo
                }
                Restart-WebItem "IIS:\Sites\FTP" -ErrorAction SilentlyContinue
                Write-Host ""
                Get-FtpUsers
            }

            "2" {
                Write-Host ""
                Write-Host "--- Cambiar de Grupo ---" -ForegroundColor White
                Get-FtpUsers
                $nom = Read-Host "  Nombre del usuario"
                if (-not (Invoke-UsuarioExiste -nombre $nom)) {
                    Write-Host "  [!] El usuario '$nom' no existe." -ForegroundColor Yellow
                    break
                }
                $actual = Get-GrupoActualFTP -FTPUserName $nom
                if ($actual -eq "") {
                    Write-Host "  [!] '$nom' no pertenece a ningun grupo FTP." -ForegroundColor Yellow
                    break
                }
                Write-Host "  Grupo actual: $actual" -ForegroundColor DarkGray
                $nuevo = Invoke-CapturarGrupoFTP
                Set-GrupoFTP -FTPUserName $nom -NuevoGrupo $nuevo
            }

            "3" {
                Write-Host ""
                Write-Host "--- Eliminar Usuario ---" -ForegroundColor White
                Get-FtpUsers
                $nom = Read-Host "  Nombre del usuario a eliminar"
                if (-not (Invoke-UsuarioExiste -nombre $nom)) {
                    Write-Host "  [!] El usuario '$nom' no existe." -ForegroundColor Yellow
                    break
                }
                $cf = Read-Host "  Confirmar eliminacion de '$nom' [s/N]"
                if ($cf -eq "s" -or $cf -eq "S") {
                    Remove-UsuarioFTP -FTPUserName $nom
                } else {
                    Write-Host "  Cancelado." -ForegroundColor DarkGray
                }
            }

            "4" {
                Get-FtpUsers
            }

            "5" {
                Write-Host ""
                Write-Host "--- Reconfigurar Servidor ---" -ForegroundColor White
                $cf = Read-Host "  Confirmar reset completo [s/N]"
                if ($cf -eq "s" -or $cf -eq "S") {
                    Initialize-ServidorFTP
                } else {
                    Write-Host "  Cancelado." -ForegroundColor DarkGray
                }
            }

            "6" {
                Write-Host "  Volviendo al menu principal..." -ForegroundColor DarkGray
            }

            default {
                Write-Host "  [!] Opcion invalida." -ForegroundColor Yellow
            }
        }

    } while ($op -ne "6")
}