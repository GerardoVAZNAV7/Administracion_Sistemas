$Dominio = (Get-ADDomain).DistinguishedName

function Convertir-HorarioABytes {
    param([int]$HoraInicioLocal, [int]$HoraFinLocal)
    [byte[]]$horasArray = New-Object byte[] 21
    
    # Usamos Get-TimeZone para evitar el caché de PowerShell
    $OffsetUTC = (Get-TimeZone).BaseUtcOffset.Hours
    $InicioUTC = ($HoraInicioLocal - $OffsetUTC + 24) % 24
    $FinUTC    = ($HoraFinLocal    - $OffsetUTC + 24) % 24
    
    for ($dia = 0; $dia -lt 7; $dia++) {
        for ($hora = 0; $hora -lt 24; $hora++) {
            $dentro = $false
            if ($InicioUTC -lt $FinUTC) {
                if ($hora -ge $InicioUTC -and $hora -lt $FinUTC) { $dentro = $true }
            } else {
                if ($hora -ge $InicioUTC -or $hora -lt $FinUTC) { $dentro = $true }
            }
            if ($dentro) {
                $byteIndex = ($dia * 3) + [math]::Floor($hora / 8)
                $bitIndex  = $hora % 8
                $horasArray[$byteIndex] = $horasArray[$byteIndex] -bor (1 -shl $bitIndex)
            }
        }
    }
    return $horasArray
}

# Reparar CUATES (08:00 - 15:00)
Write-Host "Reparando horario de CUATES..." -ForegroundColor Cyan
$HorarioCuates = Convertir-HorarioABytes -HoraInicioLocal 8 -HoraFinLocal 15
Get-ADUser -Filter * -SearchBase "OU=cuates,$Dominio" | ForEach-Object {
    Set-ADUser -Identity $_ -Clear logonHours
    Set-ADUser -Identity $_ -Replace @{logonHours = $HorarioCuates}
}

# Reparar NO CUATES (15:00 - 02:00)
Write-Host "Reparando horario de NO CUATES..." -ForegroundColor Cyan
$HorarioNoCuates = Convertir-HorarioABytes -HoraInicioLocal 15 -HoraFinLocal 2
Get-ADUser -Filter * -SearchBase "OU=no_cuates,$Dominio" | ForEach-Object {
    Set-ADUser -Identity $_ -Clear logonHours
    Set-ADUser -Identity $_ -Replace @{logonHours = $HorarioNoCuates}
}

Write-Host "¡Horarios calculados en vivo y sincronizados con éxito!" -ForegroundColor Green
