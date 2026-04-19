# =============================================================================
# SCRIPT 01 - CREAR ESTRUCTURA BASE EN ACTIVE DIRECTORY
# Ejecutar en: Windows Server 2022 (como Administrator / Domain Admin)
# Descripción: Crea OUs, grupos de seguridad y usuarios de administración delegada
# =============================================================================

# --- VARIABLES GLOBALES ---
$DomainDN = (Get-ADDomain).DistinguishedName   # Ej: DC=lab,DC=local
$DomainName = (Get-ADDomain).DNSRoot           # Ej: lab.local

Write-Host "=== [01] CREANDO ESTRUCTURA DE ACTIVE DIRECTORY ===" -ForegroundColor Cyan
Write-Host "Dominio detectado: $DomainName" -ForegroundColor Yellow

# =========================================
# PASO 1: CREAR UNIDADES ORGANIZATIVAS (OU)
# =========================================
Write-Host "`n[+] Creando Unidades Organizativas..." -ForegroundColor Green

$OUs = @("Cuates", "NoCuates", "AdminsDelegados", "GruposSeguridad")
foreach ($ou in $OUs) {
    try {
        New-ADOrganizationalUnit -Name $ou -Path $DomainDN -ErrorAction Stop
        Write-Host "    OU '$ou' creada." -ForegroundColor White
    } catch {
        Write-Host "    OU '$ou' ya existe o error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# OU anidada para pruebas de delegación
try {
    New-ADOrganizationalUnit -Name "UsuariosTest" -Path "OU=Cuates,$DomainDN"
    Write-Host "    OU 'UsuariosTest' dentro de Cuates creada." -ForegroundColor White
} catch {
    Write-Host "    OU 'UsuariosTest' ya existe." -ForegroundColor Yellow
}

# =========================================
# PASO 2: CREAR GRUPOS DE SEGURIDAD
# =========================================
Write-Host "`n[+] Creando Grupos de Seguridad..." -ForegroundColor Green

$Grupos = @(
    @{ Name="GRP_IAMOperators";    Path="OU=GruposSeguridad,$DomainDN"; Desc="Grupo para Operadores IAM" },
    @{ Name="GRP_StorageOperators";Path="OU=GruposSeguridad,$DomainDN"; Desc="Grupo para Operadores de Storage" },
    @{ Name="GRP_GPOCompliance";   Path="OU=GruposSeguridad,$DomainDN"; Desc="Grupo para Administradores GPO" },
    @{ Name="GRP_Auditores";       Path="OU=GruposSeguridad,$DomainDN"; Desc="Grupo para Auditores de Seguridad" },
    @{ Name="GRP_AdminsPrivilegio";Path="OU=GruposSeguridad,$DomainDN"; Desc="Grupo para FGPP privilegiados" }
)
foreach ($g in $Grupos) {
    try {
        New-ADGroup -Name $g.Name -GroupScope Global -GroupCategory Security `
                    -Path $g.Path -Description $g.Desc -ErrorAction Stop
        Write-Host "    Grupo '$($g.Name)' creado." -ForegroundColor White
    } catch {
        Write-Host "    Grupo '$($g.Name)' ya existe o error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# =========================================
# PASO 3: CREAR USUARIOS ADMINISTRADORES DELEGADOS
# =========================================
Write-Host "`n[+] Creando Usuarios Administradores Delegados..." -ForegroundColor Green

$AdminPath = "OU=AdminsDelegados,$DomainDN"
$AdminPassword = ConvertTo-SecureString "Gerardo1234!!" -AsPlainText -Force

$Admins = @(
    @{ SAM="admin_identidad"; Display="Admin Identidad (IAM)";   Grupo="GRP_IAMOperators";     GrupoPriv=$true },
    @{ SAM="admin_storage";   Display="Admin Storage (FSRM)";    Grupo="GRP_StorageOperators"; GrupoPriv=$true },
    @{ SAM="admin_politicas"; Display="Admin Politicas (GPO)";   Grupo="GRP_GPOCompliance";    GrupoPriv=$true },
    @{ SAM="admin_auditoria"; Display="Admin Auditoria (SIEM)";  Grupo="GRP_Auditores";        GrupoPriv=$true }
)

foreach ($a in $Admins) {
    try {
        New-ADUser -Name $a.Display `
                   -SamAccountName $a.SAM `
                   -UserPrincipalName "$($a.SAM)@$DomainName" `
                   -AccountPassword $AdminPassword `
                   -Enabled $true `
                   -Path $AdminPath `
                   -PasswordNeverExpires $false `
                   -ChangePasswordAtLogon $false `
                   -ErrorAction Stop
        Write-Host "    Usuario '$($a.SAM)' creado." -ForegroundColor White
    } catch {
        Write-Host "    Usuario '$($a.SAM)' ya existe o error: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Agregar al grupo correspondiente
    try {
        Add-ADGroupMember -Identity $a.Grupo -Members $a.SAM -ErrorAction Stop
        Write-Host "    '$($a.SAM)' agregado a '$($a.Grupo)'." -ForegroundColor White
    } catch {
        Write-Host "    Error agregando a grupo: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Agregar al grupo de FGPP privilegiados (para política de 12 caracteres)
    if ($a.GrupoPriv) {
        try {
            Add-ADGroupMember -Identity "GRP_AdminsPrivilegio" -Members $a.SAM -ErrorAction Stop
        } catch {}
    }
}

# =========================================
# PASO 4: CREAR USUARIOS DE PRUEBA EN OUs CUATES / NOCUATES
# =========================================
Write-Host "`n[+] Creando usuarios de prueba en OU Cuates y NoCuates..." -ForegroundColor Green

$UserPass = ConvertTo-SecureString "User1234!!" -AsPlainText -Force

$UsuariosPrueba = @(
    @{ SAM="usuario.cuate1";    OU="OU=UsuariosTest,OU=Cuates,$DomainDN" },
    @{ SAM="usuario.cuate2";    OU="OU=UsuariosTest,OU=Cuates,$DomainDN" },
    @{ SAM="usuario.nocuate1";  OU="OU=NoCuates,$DomainDN" },
    @{ SAM="usuario.nocuate2";  OU="OU=NoCuates,$DomainDN" }
)

foreach ($u in $UsuariosPrueba) {
    try {
        New-ADUser -Name $u.SAM `
                   -SamAccountName $u.SAM `
                   -UserPrincipalName "$($u.SAM)@$DomainName" `
                   -AccountPassword $UserPass `
                   -Enabled $true `
                   -Path $u.OU `
                   -ErrorAction Stop
        Write-Host "    Usuario de prueba '$($u.SAM)' creado en $($u.OU)." -ForegroundColor White
    } catch {
        Write-Host "    Usuario '$($u.SAM)' ya existe o error: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

Write-Host "`n=== [01] ESTRUCTURA DE AD COMPLETADA ===" -ForegroundColor Cyan
Write-Host "Siguiente paso: Ejecutar 02_Configurar_Delegacion_ACL.ps1" -ForegroundColor Magenta
