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

function Configurar-FSRM {
    Write-Host "Configurando FSRM: Cuotas por Usuario (10MB y 5MB)..." -ForegroundColor Cyan
    
    $rutaBase = "C:\Perfiles"
    $rutaCuates = "C:\Perfiles\Cuates"
    $rutaNoCuates = "C:\Perfiles\NoCuates"

    # 1. Asegurar directorios
    if (-not (Test-Path $rutaCuates)) { New-Item -Path $rutaCuates -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $rutaNoCuates)) { New-Item -Path $rutaNoCuates -ItemType Directory -Force | Out-Null }

    # 2. LIMPIEZA TOTAL
    & dirquota quota delete /path:$rutaBase /quiet /recursive 2>$null
    & dirquota autoquota delete /path:$rutaBase /quiet /recursive 2>$null

    # 3. APLICAR AUTO-CUOTAS
    Write-Host "Estableciendo Auto-Cuotas en carpetas padre..." -ForegroundColor Yellow
    & dirquota autoquota add /path:$rutaCuates /limit:10mb /type:hard | Out-Null
    & dirquota autoquota add /path:$rutaNoCuates /limit:5mb /type:hard | Out-Null

    # 4. APLICAR CUOTAS A CARPETAS EXISTENTES
    Write-Host "Sincronizando cuotas con carpetas de usuarios actuales..." -ForegroundColor Yellow
    
    Get-ChildItem $rutaCuates -Directory | ForEach-Object {
        $pathUser = $_.FullName
        & dirquota quota add /path:"$pathUser" /limit:10mb /type:hard | Out-Null
    }

    Get-ChildItem $rutaNoCuates -Directory | ForEach-Object {
        $pathUser = $_.FullName
        & dirquota quota add /path:"$pathUser" /limit:5mb /type:hard | Out-Null
    }

    # 5. Bloqueo de extensiones (Screening)
    Get-FsrmFileScreen -Path $rutaBase -ErrorAction SilentlyContinue | Remove-FsrmFileScreen -Confirm:$false
    New-FsrmFileScreen -Path $rutaBase -IncludeGroup "Executable Files","Audio and Video Files" -Active | Out-Null

    Write-Host "FSRM: Cuotas de usuario configuradas y activas." -ForegroundColor Green
}

function Configurar-AppLocker {
    Write-Host "Configurando AppLocker por Hash y Reglas por Defecto..." -ForegroundColor Cyan
    
    Stop-Service -Name AppIDSvc -Force -ErrorAction SilentlyContinue

    $xmlSalvavidas = @"
<AppLockerPolicy Version="1">
  <RuleCollection Type="Exe" EnforcementMode="Enabled">
    <FilePathRule Id="921cc481-6e17-4653-8f75-050b80acca20" Name="Permitir Program Files" Description="Regla por defecto" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%PROGRAMFILES%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="a61c8b2c-a319-4cd0-9690-d2177cad7e51" Name="Permitir Windows" Description="Regla por defecto" UserOrGroupSid="S-1-1-0" Action="Allow">
      <Conditions><FilePathCondition Path="%WINDIR%\*" /></Conditions>
    </FilePathRule>
    <FilePathRule Id="fd686d83-a829-4351-8ff4-27c7de5755d2" Name="Permitir Administradores" Description="Regla por defecto" UserOrGroupSid="S-1-5-32-544" Action="Allow">
      <Conditions><FilePathCondition Path="*" /></Conditions>
    </FilePathRule>
  </RuleCollection>
</AppLockerPolicy>
"@
    $rutaXML = "$env:TEMP\salvavidas.xml"
    $xmlSalvavidas | Out-File -FilePath $rutaXML -Encoding UTF8
    
    Set-AppLockerPolicy -XmlPolicy $rutaXML -ErrorAction SilentlyContinue

    $netbios = (Get-ADDomain).NetBIOSName
    $polNotepad = Get-AppLockerFileInformation -Path "C:\Windows\System32\notepad.exe" | New-AppLockerPolicy -RuleType Hash -User "$netbios\Grupo_NoCuates" -ErrorAction SilentlyContinue
    
     if ($polNotepad) {
        foreach ($coleccion in $polNotepad.RuleCollections) {
            foreach ($regla in $coleccion) {
                $regla.Action = 'Deny'
            }
        }
        Set-AppLockerPolicy -PolicyObject $polNotepad -Merge | Out-Null
    }

    # AGREGA AQUÍ — Allow para Cuates (después del Deny de NoCuates)
    $polAllow = Get-AppLockerFileInformation -Path "C:\Windows\System32\notepad.exe" |
        New-AppLockerPolicy -RuleType Hash -User "$netbios\Grupo_Cuates" -ErrorAction SilentlyContinue
    if ($polAllow) {
        Set-AppLockerPolicy -PolicyObject $polAllow -Merge | Out-Null
    }
    # FIN DEL BLOQUE NUEVO

    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\AppIDSvc" -Name "Start" -Value 2 -ErrorAction SilentlyContinue
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue

    Write-Host "AppLocker configurado correctamente con reglas de rescate." -ForegroundColor Green
}