# =============================================================================
# SCRIPT 05 - SCRIPT DE MONITOREO Y EXTRACCIÓN DE EVENTOS (TEST 5)
# Ejecutar en: Windows Server 2022 (como admin_auditoria o Administrator)
# Descripción: Extrae automáticamente los últimos 10 eventos de "Acceso Denegado"
#              (ID 4625 = Logon fallido, ID 4656 = Acceso a objeto fallido)
#              y los exporta a .txt y .csv
# =============================================================================

Write-Host "=== [05] SCRIPT DE MONITOREO - EXTRACCIÓN DE EVENTOS ===" -ForegroundColor Cyan

# =========================================================
# VARIABLES
# =========================================================
$FechaActual    = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ArchivoTXT     = "C:\AuditLogs\AccesosDenegados_$FechaActual.txt"
$ArchivoCSV     = "C:\AuditLogs\AccesosDenegados_$FechaActual.csv"
$MaxEventos     = 10

# Crear directorio si no existe
if (-not (Test-Path "C:\AuditLogs")) {
    New-Item -ItemType Directory -Path "C:\AuditLogs" | Out-Null
    Write-Host "Directorio C:\AuditLogs creado." -ForegroundColor White
}

Write-Host "Extrayendo los últimos $MaxEventos eventos de Acceso Denegado..." -ForegroundColor Yellow

# =========================================================
# EXTRACCIÓN DE EVENTOS ID 4625 (Logon Fallido)
# =========================================================
Write-Host "`n[+] Buscando eventos ID 4625 (Logon Fallido)..." -ForegroundColor Green

$Eventos4625 = Get-WinEvent -FilterHashtable @{
    LogName   = "Security"
    Id        = 4625
} -MaxEvents $MaxEventos -ErrorAction SilentlyContinue

# =========================================================
# EXTRACCIÓN DE EVENTOS ID 4656 (Acceso a Objeto Denegado)
# =========================================================
Write-Host "[+] Buscando eventos ID 4656 (Acceso a Objeto Denegado)..." -ForegroundColor Green

$Eventos4656 = Get-WinEvent -FilterHashtable @{
    LogName   = "Security"
    Id        = 4656
} -MaxEvents $MaxEventos -ErrorAction SilentlyContinue

# =========================================================
# EXTRACCIÓN DE EVENTOS ID 4740 (Cuenta Bloqueada - LockOut)
# =========================================================
Write-Host "[+] Buscando eventos ID 4740 (Cuenta Bloqueada por intentos fallidos)..." -ForegroundColor Green

$Eventos4740 = Get-WinEvent -FilterHashtable @{
    LogName   = "Security"
    Id        = 4740
} -MaxEvents $MaxEventos -ErrorAction SilentlyContinue

# =========================================================
# COMBINAR Y PROCESAR EVENTOS
# =========================================================
$TodosEventos = @()

foreach ($evt in $Eventos4625) {
    $xml = [xml]$evt.ToXml()
    $datos = $xml.Event.EventData.Data

    $obj = [PSCustomObject]@{
        FechaHora      = $evt.TimeCreated
        EventoID       = $evt.Id
        TipoEvento     = "Logon Fallido (4625)"
        Computador     = $evt.MachineName
        UsuarioSujeto  = ($datos | Where-Object { $_.Name -eq "TargetUserName"  }).'#text'
        DominioCuenta  = ($datos | Where-Object { $_.Name -eq "TargetDomainName"}).'#text'
        DireccionIP    = ($datos | Where-Object { $_.Name -eq "IpAddress"       }).'#text'
        RazonFallo     = ($datos | Where-Object { $_.Name -eq "FailureReason"   }).'#text'
        StatusCode     = ($datos | Where-Object { $_.Name -eq "Status"          }).'#text'
        TipoLogon      = ($datos | Where-Object { $_.Name -eq "LogonType"       }).'#text'
    }
    $TodosEventos += $obj
}

foreach ($evt in $Eventos4656) {
    $xml = [xml]$evt.ToXml()
    $datos = $xml.Event.EventData.Data

    $obj = [PSCustomObject]@{
        FechaHora      = $evt.TimeCreated
        EventoID       = $evt.Id
        TipoEvento     = "Acceso Objeto Denegado (4656)"
        Computador     = $evt.MachineName
        UsuarioSujeto  = ($datos | Where-Object { $_.Name -eq "SubjectUserName" }).'#text'
        DominioCuenta  = ($datos | Where-Object { $_.Name -eq "SubjectDomainName"}).'#text'
        DireccionIP    = "N/A"
        RazonFallo     = ($datos | Where-Object { $_.Name -eq "ObjectName"      }).'#text'
        StatusCode     = ($datos | Where-Object { $_.Name -eq "AccessMask"      }).'#text'
        TipoLogon      = "Acceso a Objeto"
    }
    $TodosEventos += $obj
}

foreach ($evt in $Eventos4740) {
    $xml = [xml]$evt.ToXml()
    $datos = $xml.Event.EventData.Data

    $obj = [PSCustomObject]@{
        FechaHora      = $evt.TimeCreated
        EventoID       = $evt.Id
        TipoEvento     = "CUENTA BLOQUEADA (4740)"
        Computador     = $evt.MachineName
        UsuarioSujeto  = ($datos | Where-Object { $_.Name -eq "TargetUserName"       }).'#text'
        DominioCuenta  = ($datos | Where-Object { $_.Name -eq "TargetDomainName"     }).'#text'
        DireccionIP    = ($datos | Where-Object { $_.Name -eq "CallerComputerName"   }).'#text'
        RazonFallo     = "Cuenta bloqueada por exceso de intentos fallidos"
        StatusCode     = "LOCKOUT"
        TipoLogon      = "N/A"
    }
    $TodosEventos += $obj
}

# Ordenar por fecha descendente y tomar los 10 más recientes
$TodosEventos = $TodosEventos | Sort-Object FechaHora -Descending | Select-Object -First $MaxEventos

# =========================================================
# EXPORTAR A TXT
# =========================================================
$Header = @"
==========================================================
  REPORTE DE ACCESOS DENEGADOS - AUDITORÍA DE SEGURIDAD
  Generado: $(Get-Date -Format "dd/MM/yyyy HH:mm:ss")
  Servidor: $env:COMPUTERNAME
  Total eventos: $($TodosEventos.Count)
==========================================================

"@

$Header | Out-File -FilePath $ArchivoTXT -Encoding UTF8

foreach ($e in $TodosEventos) {
    $linea = @"
----------------------------------------------------------
Fecha/Hora    : $($e.FechaHora)
Evento ID     : $($e.EventoID)  |  Tipo: $($e.TipoEvento)
Usuario       : $($e.UsuarioSujeto)  |  Dominio: $($e.DominioCuenta)
Computador    : $($e.Computador)
Direccion IP  : $($e.DireccionIP)
Razon/Objeto  : $($e.RazonFallo)
Status Code   : $($e.StatusCode)
Tipo Logon    : $($e.TipoLogon)

"@
    $linea | Out-File -FilePath $ArchivoTXT -Encoding UTF8 -Append
}

# =========================================================
# EXPORTAR A CSV
# =========================================================
$TodosEventos | Export-Csv -Path $ArchivoCSV -NoTypeInformation -Encoding UTF8

# =========================================================
# MOSTRAR RESUMEN EN PANTALLA
# =========================================================
Write-Host "`n========================================================" -ForegroundColor Cyan
Write-Host "  RESUMEN DEL REPORTE DE ACCESOS DENEGADOS" -ForegroundColor Cyan
Write-Host "========================================================" -ForegroundColor Cyan

if ($TodosEventos.Count -eq 0) {
    Write-Host "`n  No se encontraron eventos de acceso denegado." -ForegroundColor Yellow
    Write-Host "  Tip: Genera intentos fallidos de login y vuelve a ejecutar." -ForegroundColor Yellow
} else {
    $TodosEventos | Format-Table FechaHora, EventoID, UsuarioSujeto, DireccionIP, TipoEvento -AutoSize
}

Write-Host "`n[+] Archivos exportados:" -ForegroundColor Green
Write-Host "  TXT: $ArchivoTXT" -ForegroundColor White
Write-Host "  CSV: $ArchivoCSV" -ForegroundColor White

Write-Host "`n=== [05] EXTRACCIÓN DE EVENTOS COMPLETADA ===" -ForegroundColor Cyan
Write-Host "Siguiente paso: Ejecutar 06_Instalar_MFA_WinOTP.ps1" -ForegroundColor Magenta
