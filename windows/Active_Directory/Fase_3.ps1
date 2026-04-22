Clear-Host
Write-Host "================================================="
Write-Host " FASE 3: CONFIGURACION DE GPO Y LOGON HOURS      "
Write-Host "================================================="

# 1. Instalar el modulo de administracion de GPO (necesario en Server Core)
Write-Host "1. Instalando modulo de Directivas de Grupo (GPMC)..."
Install-WindowsFeature GPMC -ErrorAction SilentlyContinue | Out-Null

# 2. Crear y linkear la GPO de desconexion forzada
$NombreGPO = "GPO_CierreSesionForzado"
$Dominio = (Get-ADDomain).DistinguishedName

Write-Host "`n2. Configurando la GPO de Desconexion Forzada..."
if (-not (Get-GPO -Name $NombreGPO -ErrorAction SilentlyContinue)) {
    # Crear la GPO
    New-GPO -Name $NombreGPO | Out-Null
    
    # Vincularla a la raiz del dominio
    New-GPLink -Name $NombreGPO -Target $Dominio | Out-Null
    
    # TRUCO: Modificar el registro que activa la desconexion forzada en clientes SMB
    $KeyPath = "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters"
    Set-GPRegistryValue -Name $NombreGPO -Key $KeyPath -ValueName "enableforcedlogoff" -Type DWord -Value 1 | Out-Null
    
    Write-Host "   -> GPO '$NombreGPO' creada, vinculada y configurada."
} else {
    Write-Host "   -> La GPO ya existia. Omitiendo creacion."
}


# 3. Funcion para crear el arreglo de bytes (LogonHours)
function Convertir-HorarioABytes {
    param (
        [int]$HoraInicioLocal,
        [int]$HoraFinLocal
    )
    
    [byte[]]$horasArray = New-Object byte[] 21
    $OffsetUTC = [System.TimeZoneInfo]::Local.BaseUtcOffset.Hours
    $InicioUTC = ($HoraInicioLocal - $OffsetUTC + 24) % 24
    $FinUTC = ($HoraFinLocal - $OffsetUTC + 24) % 24

    for ($dia = 0; $dia -lt 7; $dia++) {
        for ($hora = 0; $hora -lt 24; $hora++) {
            $dentroDelHorario = $false
            if ($InicioUTC -lt $FinUTC) {
                if ($hora -ge $InicioUTC -and $hora -lt $FinUTC) { $dentroDelHorario = $true }
            } else {
                if ($hora -ge $InicioUTC -or $hora -lt $FinUTC) { $dentroDelHorario = $true }
            }

            if ($dentroDelHorario) {
                $byteIndex = ($dia * 3) + [math]::Floor($hora / 8)
                $bitIndex = $hora % 8
                $horasArray[$byteIndex] = $horasArray[$byteIndex] -bor (1 -shl $bitIndex)
            }
        }
    }
    return $horasArray
}

Write-Host "`n3. Aplicando LogonHours a los usuarios..."

# CORRECCIÓN: Usando los nombres de variables correctos y forzando el tipo byte array
[byte[]]$HorarioCuates = Convertir-HorarioABytes -HoraInicioLocal 8 -HoraFinLocal 15
[byte[]]$HorarioNoCuates = Convertir-HorarioABytes -HoraInicioLocal 15 -HoraFinLocal 2

# Aplicar horarios a CUATES
$UsuariosCuates = Get-ADUser -Filter * -SearchBase "OU=cuates,DC=practica,DC=local"
foreach ($User in $UsuariosCuates) {
    Set-ADUser -Identity $User.SamAccountName -Replace @{logonHours=$HorarioCuates}
    Write-Host "   -> Horario asignado a (Cuates): $($User.SamAccountName) [8:00 AM - 3:00 PM]" -ForegroundColor Yellow
}

# Aplicar horarios a NO CUATES
$UsuariosNoCuates = Get-ADUser -Filter * -SearchBase "OU=no_cuates,DC=practica,DC=local"
foreach ($User in $UsuariosNoCuates) {
    Set-ADUser -Identity $User.SamAccountName -Replace @{logonHours=$HorarioNoCuates}
    Write-Host "   -> Horario asignado a (No Cuates): $($User.SamAccountName) [3:00 PM - 2:00 AM]" -ForegroundColor Yellow
}

Write-Host "`n================================================="
Write-Host " FASE 3 COMPLETADA EXITOSAMENTE "
Write-Host "================================================="