# =====================================================
# SSH FUNCTIONS - PRACTICA 4
# Implementacion y aseguramiento de OpenSSH Server
# =====================================================

# Cargar utilidades base
. .\core_utils.ps1


# =====================================================
# INSTALACION DE OPENSSH
# =====================================================

function Install-SSHService {
    Write-Section "INSTALANDO OPENSSH SERVER"

    if (-not (Test-Admin)) {
        Write-Color "Debe ejecutar PowerShell como Administrador" Red
        return
    }

    Install-OpenSSHServer

    Write-Color "OpenSSH instalado correctamente" Green
}


# =====================================================
# CONFIGURACION DEL SERVICIO
# =====================================================

function Configure-SSHService {
    Write-Section "CONFIGURANDO SERVICIO SSH"

    Start-OpenSSHServer
    Write-Color "Servicio SSH habilitado y en inicio automatico" Green
}


# =====================================================
# CONFIGURACION DE FIREWALL
# =====================================================

function Configure-SSHFirewall {
    Write-Section "CONFIGURANDO FIREWALL PARA SSH"

    Enable-SSHFirewall

    Write-Color "Puerto 22 habilitado en firewall" Green
}


# =====================================================
# INSTALACION COMPLETA AUTOMATIZADA
# =====================================================

function Install-SSHFull {
    Install-SSHService
    Configure-SSHService
    Configure-SSHFirewall

    Write-Color "SSH listo para acceso remoto" Cyan
}


# =====================================================
# VERIFICAR ESTADO DEL SERVICIO
# =====================================================

function Get-SSHStatus {
    Write-Section "ESTADO DEL SERVICIO SSH"

    $service = Get-ServiceSafe "sshd"

    if (-not $service) {
        Write-Color "OpenSSH no esta instalado" Red
        return
    }

    Write-Color "Servicio: $($service.Status)" Yellow

    $rule = Get-NetFirewallRule -DisplayName "OpenSSH Server" -ErrorAction SilentlyContinue

    if ($rule) {
        Write-Color "Firewall: Puerto 22 permitido" Green
    } else {
        Write-Color "Firewall: Regla NO encontrada" Red
    }
}