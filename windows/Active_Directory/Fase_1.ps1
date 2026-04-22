# Iniciar un bucle infinito para mantener el menu activo hasta que elijas salir
while ($true) {
    Clear-Host
    Write-Host "================================================="
    Write-Host "   MENU DE CONFIGURACION INICIAL DEL SERVIDOR    "
    Write-Host "================================================="
    Write-Host "1. Paso 1: Configurar IP Estatica y Nombre (Requiere Reinicio)"
    Write-Host "2. Paso 2: Instalar AD DS y Promover a Controlador de Dominio"
    Write-Host "3. Salir del Script"
    Write-Host "================================================="

    $opcion = Read-Host "Selecciona una opcion (1, 2 o 3)"

    if ($opcion -eq '1') {
        Write-Host "`n--- Iniciando Paso 1 ---"
        $nombre = Read-Host "Ingresa el nombre deseado para el servidor (ej. SRV-DC01)"
        
        # VALIDACION PASO 1
        if ($env:COMPUTERNAME -eq $nombre) {
            Write-Host "`n[AVISO] El servidor ya tiene el nombre '$nombre'."
            Write-Host "Parece que ya completaste el Paso 1. Regresando al menu principal..."
            Start-Sleep -Seconds 4
            continue
        }
        
        $ip = Read-Host "Ingresa la direccion IP (ej. 192.168.50.10)"
        $prefix = Read-Host "Ingresa el prefijo de red (ej. 24)"
        
        # MOSTRAR ADAPTADORES Y PREGUNTAR
        Write-Host "`nAdaptadores de red detectados:"
        Get-NetAdapter | Select-Object Name, Status, InterfaceDescription | Format-Table -AutoSize
        
        $adaptador = Read-Host "Ingresa el NOMBRE EXACTO de la tarjeta para tu red interna (ej. Ethernet 3)"
        
        Write-Host "`nConfigurando la tarjeta de red '$adaptador'..."
        # Configurar IP y DNS
        New-NetIPAddress -InterfaceAlias $adaptador -IPAddress $ip -PrefixLength $prefix -ErrorAction SilentlyContinue | Out-Null
        Set-DnsClientServerAddress -InterfaceAlias $adaptador -ServerAddresses "127.0.0.1" -ErrorAction SilentlyContinue
        
        Write-Host "Cambiando el nombre del servidor a '$nombre'..."
        Rename-Computer -NewName $nombre -ErrorAction SilentlyContinue
        
        Write-Host "`n[!] Proceso completado. El servidor se reiniciara FORZOSAMENTE en 5 segundos..."
        Start-Sleep -Seconds 5
        
        # REINICIO FORZADO PARA IGNORAR OTRAS SESIONES
        Restart-Computer -Force
    }
    elseif ($opcion -eq '2') {
        Write-Host "`n--- Iniciando Paso 2 ---"
        
        # VALIDACION PASO 2: Consultar a WMI/CIM si el servidor ya es Controlador de Dominio (Rol 4 o 5)
        $rol = (Get-CimInstance Win32_ComputerSystem).DomainRole
        if ($rol -ge 4) {
            Write-Host "`n[AVISO] Este servidor ya es un Controlador de Dominio."
            Write-Host "No puedes volver a promoverlo. Regresando al menu principal..."
            Start-Sleep -Seconds 4
            continue # Vuelve al menu
        }
        
        $dominio = Read-Host "Ingresa el nombre del dominio (ej. practica.local)"
        
        Write-Host "`nInstalando los binarios de Active Directory..."
        Install-WindowsFeature AD-Domain-Services -IncludeManagementTools | Out-Null
        
        Write-Host "`nPromoviendo el servidor a Controlador de Dominio..."
        Write-Host "(Se te pedira que crees una contrasena de modo seguro a continuacion)"
        
        Install-ADDSForest -DomainName $dominio -InstallDns -Force
    }
    elseif ($opcion -eq '3') {
        Write-Host "`nSaliendo del configurador..."
        break # Rompe el bucle while y finaliza el script
    }
    else {
        Write-Host "`n[!] Opcion no valida. Intenta de nuevo."
        Start-Sleep -Seconds 2
    }
}