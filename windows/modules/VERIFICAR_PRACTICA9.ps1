# =============================================================================
# VERIFICAR_PRACTICA9.ps1 — Prueba rapida de todos los componentes
# Ejecutar DESPUES del reinicio del servidor
# =============================================================================

#Requires -RunAsAdministrator

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   VERIFICACION PRACTICA 9 — POST REINICIO       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$pass = 0; $warn = 0; $fail = 0

function Test-OK   { param($msg) Write-Host "  [PASS] $msg" -ForegroundColor Green;  $global:pass++ }
function Test-Warn { param($msg) Write-Host "  [WARN] $msg" -ForegroundColor Yellow; $global:warn++ }
function Test-Fail { param($msg) Write-Host "  [FAIL] $msg" -ForegroundColor Red;    $global:fail++ }

# ── 1. NTP ──────────────────────────────────────────
Write-Host "[ NTP — Sincronizacion de tiempo ]" -ForegroundColor Cyan
$ntpConf = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Services\W32Time\Parameters" -ErrorAction SilentlyContinue
if ($ntpConf.NtpServer -like "*google*") {
    Test-OK "Servidor NTP configurado con Google: $($ntpConf.NtpServer)"
} else {
    Test-Warn "NTP server: $($ntpConf.NtpServer) — verifica que sea time.google.com"
}

$skew = & w32tm /query /status 2>&1 | Select-String "Offset"
Write-Host "  Offset de tiempo: $skew" -ForegroundColor Gray

Write-Host ""

# ── 2. multiOTP ─────────────────────────────────────
Write-Host "[ multiOTP — Usuarios registrados ]" -ForegroundColor Cyan
$exe = Get-ChildItem "C:\MultiOTP" -Recurse -Filter "multiotp.exe" -ErrorAction SilentlyContinue |
       Select-Object -First 1 -ExpandProperty FullName

if (-not $exe) {
    Test-Fail "multiotp.exe no encontrado en C:\MultiOTP"
} else {
    Test-OK "multiotp.exe encontrado: $exe"
    $exeDir  = Split-Path $exe -Parent
    $usersDir = Join-Path $exeDir "users"

    $AdminUsers = @("admin_identidad","admin_storage","admin_politicas","admin_auditoria","Administrator")
    foreach ($u in $AdminUsers) {
        $dbPath = Join-Path $usersDir ($u + ".db")
        if (Test-Path $dbPath) {
            Test-OK "$u — .db existe en $dbPath"
        } else {
            Test-Fail "$u — .db NO encontrado en $dbPath"
        }
    }

    # Puerto 8112
    $p = netstat -an 2>$null | Select-String ":8112"
    if ($p) { Test-OK "Puerto 8112 activo (servicio web multiOTP)" }
    else    { Test-Warn "Puerto 8112 no activo — ejecuta webservice_install.cmd" }
}

Write-Host ""

# ── 3. Prueba TOTP manual ───────────────────────────
Write-Host "[ multiOTP — Prueba de codigo TOTP ]" -ForegroundColor Cyan
Write-Host "  Abre Google Authenticator en tu celular." -ForegroundColor White
Write-Host "  Elige la cuenta 'admin_identidad'" -ForegroundColor White
$code = Read-Host "  Ingresa el codigo de 6 digitos (o Enter para omitir)"

if ($code -and $code.Length -eq 6 -and $exe) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe; $psi.Arguments = "-checkpwd admin_identidad $code"
    $psi.WorkingDirectory = (Split-Path $exe -Parent)
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $proc = New-Object System.Diagnostics.Process; $proc.StartInfo = $psi
    $proc.Start() | Out-Null
    if (-not $proc.WaitForExit(15000)) { $proc.Kill() }
    $out = $proc.StandardOutput.ReadToEnd().Trim()
    $err = $proc.StandardError.ReadToEnd().Trim()
    $result = if ($out) { $out } else { $err }

    Write-Host "  Resultado: $result" -ForegroundColor Gray
    if ($result -match "0|OK|success") {
        Test-OK "Codigo TOTP VALIDO — multiOTP funciona correctamente"
    } else {
        Test-Fail "Codigo invalido ($result) — verifica hora del servidor y del celular"
        Write-Host "  Ejecuta: w32tm /resync /force" -ForegroundColor Yellow
    }
} else {
    Write-Host "  (Prueba omitida)" -ForegroundColor Gray
}

Write-Host ""

# ── 4. Credential Provider ──────────────────────────
Write-Host "[ Credential Provider de multiOTP ]" -ForegroundColor Cyan
$cp = Get-ChildItem "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\Credential Providers\" `
      -ErrorAction SilentlyContinue |
      Where-Object {
          try { (Get-ItemProperty $_.PSPath).'(default)' -like "*multiOTP*" } catch { $false }
      }
if ($cp) {
    Test-OK "Credential Provider de multiOTP instalado en el registro"
} else {
    Test-Fail "CP de multiOTP NO encontrado — instala desde C:\MFA_Setup\CredentialProvider\"
    Write-Host "  Config: Server=127.0.0.1, Puerto=8112" -ForegroundColor Yellow
}

Write-Host ""

# ── 5. Active Directory ─────────────────────────────
Write-Host "[ Active Directory — Estructura de la Practica 8 ]" -ForegroundColor Cyan
try {
    Import-Module ActiveDirectory -ErrorAction Stop
    $domDN = (Get-ADDomain).DistinguishedName

    foreach ($ou in @("Cuates","NoCuates","AdminsDelegados","GruposSeguridad")) {
        $exists = Get-ADOrganizationalUnit -Filter "Name -eq '$ou'" -ErrorAction SilentlyContinue
        if ($exists) { Test-OK "OU '$ou' existe" }
        else          { Test-Fail "OU '$ou' NO encontrada" }
    }

    foreach ($u in @("admin_identidad","admin_storage","admin_politicas","admin_auditoria")) {
        $exists = Get-ADUser -Identity $u -ErrorAction SilentlyContinue
        if ($exists) { Test-OK "Usuario '$u' existe" }
        else          { Test-Fail "Usuario '$u' NO encontrado" }
    }

    # FGPP
    $pso = Get-ADFineGrainedPasswordPolicy -Identity "PSO_AdminsPrivilegiados" -ErrorAction SilentlyContinue
    if ($pso -and $pso.MinPasswordLength -ge 12) {
        Test-OK "FGPP PSO_AdminsPrivilegiados: $($pso.MinPasswordLength) chars min, lockout $($pso.LockoutThreshold) intentos"
    } else {
        Test-Fail "FGPP no configurada correctamente"
    }
} catch {
    Test-Fail "No se pudo conectar a AD: $($_.Exception.Message)"
}

Write-Host ""

# ── 6. Perfiles moviles ─────────────────────────────
Write-Host "[ Perfiles Moviles ]" -ForegroundColor Cyan
$share = Get-SmbShare -Name "Perfiles$" -ErrorAction SilentlyContinue
if ($share) { Test-OK "Share \\$env:COMPUTERNAME\Perfiles$ existe en $($share.Path)" }
else         { Test-Fail "Share Perfiles$ no encontrado" }

Write-Host ""

# ── 7. FSRM ─────────────────────────────────────────
Write-Host "[ FSRM — Cuotas y Bloqueos ]" -ForegroundColor Cyan
try {
    $screen = Get-FsrmFileScreen -Path "C:\UserData\Cuates" -ErrorAction Stop
    Test-OK "File Screen activo en C:\UserData\Cuates"
} catch { Test-Warn "File Screen en Cuates no configurado (puede ser que FSRM aun no inicio)" }

try {
    $quota = Get-FsrmQuota -Path "C:\UserData\Cuates" -ErrorAction Stop
    Test-OK "Cuota $([math]::Round($quota.Size/1MB))MB en C:\UserData\Cuates"
} catch { Test-Warn "Cuota en Cuates no configurada" }

try {
    $quota2 = Get-FsrmQuota -Path "C:\UserData\NoCuates" -ErrorAction Stop
    Test-OK "Cuota $([math]::Round($quota2.Size/1MB))MB en C:\UserData\NoCuates"
} catch { Test-Warn "Cuota en NoCuates no configurada" }

# ── Resumen ──────────────────────────────────────────
Write-Host ""
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  RESUMEN" -ForegroundColor Cyan
Write-Host "══════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  PASS: $pass" -ForegroundColor Green
Write-Host "  WARN: $warn" -ForegroundColor Yellow
Write-Host "  FAIL: $fail" -ForegroundColor Red
Write-Host ""

if ($fail -eq 0) {
    Write-Host "  Sistema listo para los Tests de evaluacion." -ForegroundColor Green
} elseif ($fail -le 2) {
    Write-Host "  Revisa los FAIL antes del examen." -ForegroundColor Yellow
} else {
    Write-Host "  Hay problemas criticos. Revisa el log en C:\MFA_Setup\practica9_log.txt" -ForegroundColor Red
}
Write-Host ""