function Instalar-Requisitos {
    Write-Host "Instalando FSRM y GPMC..." -ForegroundColor Cyan
    Install-WindowsFeature -Name FS-Resource-Manager, GPMC -IncludeManagementTools | Out-Null
}

function Crear-EstructuraAD {
    param([string]$dominioDN)
    Write-Host "Verificando/Creando Unidades Organizativas y Grupos..." -ForegroundColor Cyan
    
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'Cuates'")) {
        New-ADOrganizationalUnit -Name "Cuates" -Path $dominioDN -ProtectedFromAccidentalDeletion $false
    }
    if (-not (Get-ADOrganizationalUnit -Filter "Name -eq 'No Cuates'")) {
        New-ADOrganizationalUnit -Name "No Cuates" -Path $dominioDN -ProtectedFromAccidentalDeletion $false
    }

    if (-not (Get-ADGroup -Filter "Name -eq 'Grupo_Cuates'")) {
        New-ADGroup -Name "Grupo_Cuates" -GroupCategory Security -GroupScope Global -Path "OU=Cuates,$dominioDN"
    }
    if (-not (Get-ADGroup -Filter "Name -eq 'Grupo_NoCuates'")) {
        New-ADGroup -Name "Grupo_NoCuates" -GroupCategory Security -GroupScope Global -Path "OU=No Cuates,$dominioDN"
    }
}

function Importar-UsuariosCSV {
    param([string]$rutaCSV, [string]$dominioDN)
    Write-Host "Calculando horarios exactos y aplicando a los usuarios..." -ForegroundColor Cyan

    # Funcion que calcula los bits perfectos segun la zona horaria del servidor
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
                    # Usa una fecha base para calcular el desfase de la zona horaria
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

    # Asignamos las horas exactas de tu rubrica
    [byte[]]$horasCuates = Crear-HorarioBytes -Inicio 8 -Fin 15
    [byte[]]$horasNoCuates = Crear-HorarioBytes -Inicio 15 -Fin 2

    if (-not (Test-Path $rutaCSV)) {
        Write-Host "[!] No se encontro el archivo CSV en $rutaCSV." -ForegroundColor Red
        return
    }

    $usuarios = Import-Csv $rutaCSV
    foreach ($u in $usuarios) {
        $nUsuario = $u.usuario
        $nPass = $u.pass
        $nDepto = $u.departamento

        $ouPath = if ($nDepto -eq "Cuates") { "OU=Cuates,$dominioDN" } else { "OU=No Cuates,$dominioDN" }
        [byte[]]$logonHoursToApply = if ($nDepto -eq "Cuates") { $horasCuates } else { $horasNoCuates }
        $grupoSeguridad = if ($nDepto -eq "Cuates") { "Grupo_Cuates" } else { "Grupo_NoCuates" }

        $password = ConvertTo-SecureString $nPass -AsPlainText -Force
        $upn = "$($nUsuario)@$((Get-ADDomain).Forest)"

        $existe = Get-ADUser -Filter {SamAccountName -eq $nUsuario} -ErrorAction SilentlyContinue
        if ($existe) { 
            Remove-ADUser -Identity $nUsuario -Confirm:$false 
        }
        
        New-ADUser -Name $nUsuario -SamAccountName $nUsuario -UserPrincipalName $upn -AccountPassword $password -Enabled $true -Path $ouPath
        
        Set-ADUser -Identity $nUsuario -Replace @{logonhours=[byte[]]$logonHoursToApply} -ErrorAction Continue
        
        Add-ADGroupMember -Identity $grupoSeguridad -Members $nUsuario -ErrorAction SilentlyContinue
        
        Write-Host "Usuario $nUsuario creado limpio y horario asignado." -ForegroundColor Green
    }
}
function Configurar-GPO-Logoff {
    param([string]$dominioDN)
    Write-Host "Aplicando GPO de desconexion forzada..." -ForegroundColor Cyan
    
    $gpoName = "Politicas_FIM_CierreForzado"
    
    if (-not (Get-GPO -Name $gpoName -ErrorAction SilentlyContinue)) {
        New-GPO -Name $gpoName | New-GPLink -Target $dominioDN | Out-Null
    }
    
    Set-GPRegistryValue -Name $gpoName -Key "HKLM\System\CurrentControlSet\Services\LanManServer\Parameters" -ValueName "enableforcedlogoff" -Type DWord -Value 1 | Out-Null
    
    Write-Host "GPO de cierre forzado aplicada al dominio." -ForegroundColor Green
}
function Configurar-FSRM {
    Write-Host "Configurando FSRM: Cuotas por Usuario (10MB y 5MB)..." -ForegroundColor Cyan
    
    $rutaBase = "C:\Perfiles"
    $rutaCuates = "C:\Perfiles\Cuates"
    $rutaNoCuates = "C:\Perfiles\NoCuates"

    # 1. Asegurar directorios
    if (-not (Test-Path $rutaCuates)) { New-Item -Path $rutaCuates -ItemType Directory -Force | Out-Null }
    if (-not (Test-Path $rutaNoCuates)) { New-Item -Path $rutaNoCuates -ItemType Directory -Force | Out-Null }

    # 2. LIMPIEZA TOTAL: Borramos cualquier cuota o auto-cuota previa para empezar de cero
    # Usamos el ejecutable directo para evitar errores de objetos no encontrados
    & dirquota quota delete /path:$rutaBase /quiet /recursive 2>$null
    & dirquota autoquota delete /path:$rutaBase /quiet /recursive 2>$null

    # 3. APLICAR AUTO-CUOTAS (Para carpetas que se creen en el futuro)
    # Esto cumple tu regla: cualquier carpeta dentro de Cuates hereda 10MB individualmente
    Write-Host "Estableciendo Auto-Cuotas en carpetas padre..." -ForegroundColor Yellow
    & dirquota autoquota add /path:$rutaCuates /limit:10mb /type:hard | Out-Null
    & dirquota autoquota add /path:$rutaNoCuates /limit:5mb /type:hard | Out-Null

    # 4. APLICAR CUOTAS A CARPETAS EXISTENTES (El punto clave que nos faltaba)
    # Las Auto-cuotas NO afectan a carpetas que YA existen (como las que creo tu script de usuarios)
    # Por eso recorremos cada usuario y le clavamos su cuota manual
    Write-Host "Sincronizando cuotas con carpetas de usuarios actuales..." -ForegroundColor Yellow
    
    # Cuotas para carpetas dentro de Cuates
    Get-ChildItem $rutaCuates -Directory | ForEach-Object {
        $pathUser = $_.FullName
        & dirquota quota add /path:"$pathUser" /limit:10mb /type:hard | Out-Null
    }

    # Cuotas para carpetas dentro de No Cuates
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

    Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Services\AppIDSvc" -Name "Start" -Value 2 -ErrorAction SilentlyContinue
    Start-Service -Name AppIDSvc -ErrorAction SilentlyContinue

    Write-Host "AppLocker configurado correctamente con reglas de rescate." -ForegroundColor Green
}