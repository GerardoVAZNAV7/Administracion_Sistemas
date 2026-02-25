# =====================================================
# SSH FUNCTIONS - WINDOWS SERVER 2022
# Requiere: . .\core_utils.ps1
# =====================================================

# =====================================================
# INSTALAR OPENSSH SERVER
# =====================================================

function Install-SSHService {
    Write-Section "INSTALANDO OPENSSH SERVER"

    if (-not (Test-Admin)) {
        Write-Color "Ejecute PowerShell como Administrador" Red
        return
    }

    $cap = Get-WindowsCapability -Online | Where-Object Name -like 'OpenSSH.Server*'

    if ($cap.State -eq "Installed") {
        Write-Color "OpenSSH ya esta instalado" Yellow
        return
    }

    Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    Write-Color "OpenSSH instalado correctamente" Green
}

# =====================================================
# CONFIGURACION COMPLETA AUTOMATICA
# =====================================================

function Configure-SSHService {
    Write-Section "CONFIGURACION AUTOMATICA SSH"

    if (-not (Test-Admin)) {
        Write-Color "Ejecute PowerShell como Administrador" Red
        return
    }

    # Iniciar servicio
    Start-Service sshd

    # Inicio automatico en boot
    Set-Service -Name sshd -StartupType Automatic

    # Configurar firewall
    if (-not (Get-NetFirewallRule -Name "OpenSSH-Server-In-TCP" -ErrorAction SilentlyContinue)) {
        New-NetFirewallRule `
            -Name "OpenSSH-Server-In-TCP" `
            -DisplayName "OpenSSH Server" `
            -Enabled True `
            -Direction Inbound `
            -Protocol TCP `
            -Action Allow `
            -LocalPort 22
    }

    Write-Color "SSH configurado y listo para acceso remoto" Green
}

# =====================================================
# VERIFICAR SERVICIO
# =====================================================

function Get-SSHStatus {
    Write-Section "ESTADO DEL SERVICIO SSH"

    $service = Get-Service -Name sshd -ErrorAction SilentlyContinue

    if (-not $service) {
        Write-Color "OpenSSH no instalado" Red
        return
    }

    Write-Color "Servicio: $($service.Status)" Yellow

    $rule = Get-NetFirewallRule -DisplayName "OpenSSH Server" -ErrorAction SilentlyContinue

    if ($rule) {
        Write-Color "Firewall: Puerto 22 permitido" Green
    } else {
        Write-Color "Firewall: Puerto 22 NO configurado" Red
    }

    Write-Host ""
    Write-Host "Puerto escuchando:"
    netstat -an | findstr :22
}

# =====================================================
# MOSTRAR DATOS DE CONEXION
# =====================================================

function Show-SSHConnectionInfo {
    Write-Section "DATOS DE CONEXION"

    $ip = (Get-NetIPAddress -AddressFamily IPv4 |
           Where-Object {$_.IPAddress -notlike "169.*"} |
           Select-Object -First 1).IPAddress

    Write-Host ""
    Write-Host "IP del servidor: $ip"
    Write-Host "Puerto: 22"
    Write-Host "Usuario Windows: $env:USERNAME"
    Write-Host ""

    Write-Host "Desde PuTTY:"
    Write-Host "Host Name: $ip"
    Write-Host "Port: 22"
    Write-Host ""

    Write-Host "Transferir archivo desde tu PC:"
    Write-Host "scp archivo.txt usuario@$ip:C:\Users\usuario\Desktop\"
}