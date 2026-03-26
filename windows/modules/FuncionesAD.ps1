function Instalar-Requisitos {
    Write-Host "Instalando FSRM y GPMC..." -ForegroundColor Cyan
    Install-WindowsFeature -Name FS-Resource-Manager, GPMC -IncludeManagementTools | Out-Null
}

function Crear-EstructuraAD {
    # Hardcodeamos el Distinguished Name de baja.com
    $dominioDN = "DC=baja,DC=com"
    Write-Host "Verificando/Creando Unidades Organizativas y Grupos en $dominioDN..." -ForegroundColor Cyan
    
    # Crear OUs
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Cuates'")) {
        New-ADOrganizationalUnit -Name "Cuates" -Path $dominioDN -ProtectedFromAccidentalDeletion $false
    }
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'No Cuates'")) {
        New-ADOrganizationalUnit -Name "No Cuates" -Path $dominioDN -ProtectedFromAccidentalDeletion $false
    }

    # Crear Grupos
    if (-not (Get-ADGroup -Filter "Name -eq 'Grupo_Cuates'")) {
        New-ADGroup -Name "Grupo_Cuates" -GroupCategory Security -GroupScope Global -Path "OU=Cuates,$dominioDN"
    }
    if (-not (Get-ADGroup -Filter "Name -eq 'Grupo_NoCuates'")) {
        New-ADGroup -Name "Grupo_NoCuates" -GroupCategory Security -GroupScope Global -Path "OU=No Cuates,$dominioDN"
    }
}

function Importar-UsuariosCSV {
    param([string]$rutaCSV)
    $dominioDN = "DC=baja,DC=com"
    $forest = "baja.com"

    Write-Host "Importando usuarios a $forest..." -ForegroundColor Cyan

    function Crear-HorarioBytes {
        param([int]$Inicio, [int]$Fin)
        [byte[]]$bytes = New-Object byte[] 21
        for ($dia = 0; $dia -lt 7; $dia++) {
            for ($hora = 0; $hora -lt 24; $hora++) {
                $permitido = $false
                if ($Inicio -lt $Fin) {
                    if ($hora -ge $Inicio -and $hora -lt $Fin) { $permitido = $true }
                } else {
                    if ($hora -ge $Inicio -or $hora -lt $Fin) { $permitido = $true }
                }
                if ($permitido) {
                    $fechaLocal = (Get-Date -Year 2024 -Month 1 -Day 7 -Hour 0 -Minute 0 -Second 0).AddDays($dia).AddHours($hora)
                    $fechaUTC = $fechaLocal.ToUniversalTime()
                    $diaUTC = [int]$fechaUTC.DayOfWeek
                    $horaUTC = $fechaUTC.Hour
                    $byteIndex = ($diaUTC * 3) + [Math]::Floor($horaUTC / 8)
                    $bitIndex = $horaUTC % 8
                    $bytes[$byteIndex] = $bytes[$byteIndex] -bor (1 -shl $bitIndex)
                }
            }
        }
        return $bytes
    }

    [byte[]]$horasCuates = Crear-HorarioBytes -Inicio 8 -Fin 15
    [byte[]]$horasNoCuates = Crear-HorarioBytes -Inicio 15 -Fin 2

    $usuarios = Import-Csv $rutaCSV
    foreach ($u in $usuarios) {
        $nUsuario = $u.Usuario
        $nPass = $u.Contrasena
        $nDepto = $u.Departamento

        $ouPath = if ($nDepto -eq "Cuates") { "OU=Cuates,$dominioDN" } else { "OU=No Cuates,$dominioDN" }
        [byte[]]$logonHoursToApply = if ($nDepto -eq "Cuates") { $horasCuates } else { $horasNoCuates }
        $grupoSeguridad = if ($nDepto -eq "Cuates") { "Grupo_Cuates" } else { "Grupo_NoCuates" }

        $password = ConvertTo-SecureString $nPass -AsPlainText -Force
        $upn = "$($nUsuario)@$forest"

        if (Get-ADUser -Filter {SamAccountName -eq $nUsuario} -ErrorAction SilentlyContinue) { 
            Remove-ADUser -Identity $nUsuario -Confirm:$false 
        }
        
        New-ADUser -Name $nUsuario -SamAccountName $nUsuario -UserPrincipalName $upn -AccountPassword $password -Enabled $true -Path $ouPath
        Set-ADUser -Identity $nUsuario -Replace @{logonhours=[byte[]]$logonHoursToApply}
        Add-ADGroupMember -Identity $grupoSeguridad -Members $nUsuario
        
        Write-Host "Usuario $nUsuario configurado en $nDepto" -ForegroundColor Green
    }
}

function Configurar-GPO-Logoff {
    $dominioDN = "DC=baja,DC=com"
    Write-Host "Configurando GPO en baja.com..." -ForegroundColor Cyan
    
    $gpoName = "Politicas_FIM_CierreForzado"
    if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
        New-GPO -Name $gpoName | New-GPLink -Target $dominioDN | Out-Null
    }
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters" -ValueName "enableforcedlogoff" -Type DWord -Value 1 | Out-Null
}

# (Las funciones Configurar-FSRM y Configurar-AppLocker no requieren cambios de dominio, se mantienen igual)