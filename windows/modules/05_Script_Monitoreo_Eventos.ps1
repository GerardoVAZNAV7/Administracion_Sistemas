# =============================================================================
# SCRIPT 05 - SCRIPT DE MONITOREO Y EXTRACCION DE EVENTOS (TEST 5) - CORREGIDO
# Ejecutar en: Windows Server 2022
# =============================================================================

Write-Host "=== [05] SCRIPT DE MONITOREO - EXTRACCION DE EVENTOS ===" -ForegroundColor Cyan

$FechaActual = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$ArchivoTXT  = "C:\AuditLogs\AccesosDenegados_$FechaActual.txt"
$ArchivoCSV  = "C:\AuditLogs\AccesosDenegados_$FechaActual.csv"
$MaxEventos  = 10

if (-not (Test-Path "C:\AuditLogs")) {
    New-Item -ItemType Directory -Path "C:\AuditLogs" | Out-Null
    Write-Host "Directorio C:\AuditLogs creado." -ForegroundColor White
}

Write-Host "Extrayendo los ultimos $MaxEventos eventos de Acceso Denegado..." -ForegroundColor Yellow

$Eventos4625 = Get-WinEvent -FilterHashtable @{ LogName="Security"; Id=4625 } -MaxEvents $MaxEventos -ErrorAction SilentlyContinue
$Eventos4656 = Get-WinEvent -FilterHashtable @{ LogName="Security"; Id=4656 } -MaxEvents $MaxEventos -ErrorAction SilentlyContinue
$Eventos4740 = Get-WinEvent -FilterHashtable @{ LogName="Security"; Id=4740 } -MaxEvents $MaxEventos -ErrorAction SilentlyContinue

$TodosEventos = @()

foreach ($evt in $Eventos4625) {
    $xml = [xml]$evt.ToXml()
    $datos = $xml.Event.EventData.Data
    $obj = [PSCustomObject]@{
        FechaHora     = $evt.TimeCreated
        EventoID      = $evt.Id
        TipoEvento    = "Logon Fallido (4625)"
        Computador    = $evt.MachineName
        UsuarioSujeto = ($datos | Where-Object { $_.Name -eq "TargetUserName"   }).'#text'
        DominioCuenta = ($datos | Where-Object { $_.Name -eq "TargetDomainName" }).'#text'
        DireccionIP   = ($datos | Where-Object { $_.Name -eq "IpAddress"        }).'#text'
        RazonFallo    = ($datos | Where-Object { $_.Name -eq "FailureReason"    }).'#text'
        StatusCode    = ($datos | Where-Object { $_.Name -eq "Status"           }).'#text'
        TipoLogon     = ($datos | Where-Object { $_.Name -eq "LogonType"        }).'#text'
    }
    $TodosEventos += $obj
}

foreach ($evt in $Eventos4656) {
    $xml = [xml]$evt.ToXml()
    $datos = $xml.Event.EventData.Data
    $obj = [PSCustomObject]@{
        FechaHora     = $evt.TimeCreated
        EventoID      = $evt.Id
        TipoEvento    = "Acceso Objeto Denegado (4656)"
        Computador    = $evt.MachineName
        UsuarioSujeto = ($datos | Where-Object { $_.Name -eq "SubjectUserName"   }).'#text'
        DominioCuenta = ($datos | Where-Object { $_.Name -eq "SubjectDomainName" }).'#text'
        DireccionIP   = "N/A"
        RazonFallo    = ($datos | Where-Object { $_.Name -eq "ObjectName"        }).'#text'
        StatusCode    = ($datos | Where-Object { $_.Name -eq "AccessMask"        }).'#text'
        TipoLogon     = "Acceso a Objeto"
    }
    $TodosEventos += $obj
}

foreach ($evt in $Eventos4740) {
    $xml = [xml]$evt.ToXml()
    $datos = $xml.Event.EventData.Data
    $obj = [PSCustomObject]@{
        FechaHora     = $evt.TimeCreated
        EventoID      = $evt.Id
        TipoEvento    = "CUENTA BLOQUEADA (4740)"
        Computador    = $evt.MachineName
        UsuarioSujeto = ($datos | Where-Object { $_.Name -eq "TargetUserName"     }).'#text'
        DominioCuenta = ($datos | Where-Object { $_.Name -eq "TargetDomainName"   }).'#text'
        DireccionIP   = ($datos | Where-Object { $_.Name -eq "CallerComputerName" }).'#text'
        RazonFallo    = "Cuenta bloqueada por exceso de intentos fallidos"
        StatusCode    = "LOCKOUT"
        TipoLogon     = "N/A"
    }
    $TodosEventos += $obj
}

$TodosEventos = $TodosEventos | Sort-Object FechaHora -Descending | Select-Object -First $MaxEventos

$Separador  = "=========================================================="
$Separador2 = "----------------------------------------------------------"

$Header  = "$Separador`r`n"
$Header += "  REPORTE DE ACCESOS DENEGADOS - AUDITORIA DE SEGURIDAD`r`n"
$Header += "  Generado: $(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')`r`n"
$Header += "  Servidor: $env:COMPUTERNAME`r`n"
$Header += "  Total eventos: $($TodosEventos.Count)`r`n"
$Header += "$Separador`r`n`r`n"
$Header | Out-File -FilePath $ArchivoTXT -Encoding UTF8

foreach ($e in $TodosEventos) {
    $linea  = "$Separador2`r`n"
    $linea += "Fecha/Hora    : $($e.FechaHora)`r`n"
    $linea += "Evento ID     : $($e.EventoID)  |  Tipo: $($e.TipoEvento)`r`n"
    $linea += "Usuario       : $($e.UsuarioSujeto)  |  Dominio: $($e.DominioCuenta)`r`n"
    $linea += "Computador    : $($e.Computador)`r`n"
    $linea += "Direccion IP  : $($e.DireccionIP)`r`n"
    $linea += "Razon/Objeto  : $($e.RazonFallo)`r`n"
    $linea += "Status Code   : $($e.StatusCode)`r`n"
    $linea += "Tipo Logon    : $($e.TipoLogon)`r`n`r`n"
    $linea | Out-File -FilePath $ArchivoTXT -Encoding UTF8 -Append
}

$TodosEventos | Export-Csv -Path $ArchivoCSV -NoTypeInformation -Encoding UTF8

Write-Host "`n$Separador" -ForegroundColor Cyan
Write-Host "  RESUMEN DEL REPORTE" -ForegroundColor Cyan
Write-Host "$Separador" -ForegroundColor Cyan

if ($TodosEventos.Count -eq 0) {
    Write-Host "`n  Sin eventos. Genera intentos fallidos y vuelve a ejecutar." -ForegroundColor Yellow
} else {
    $TodosEventos | Format-Table FechaHora, EventoID, UsuarioSujeto, DireccionIP, TipoEvento -AutoSize
}

Write-Host "`n[+] TXT: $ArchivoTXT" -ForegroundColor Green
Write-Host "[+] CSV: $ArchivoCSV" -ForegroundColor Green
Write-Host "`n=== [05] EXTRACCION COMPLETADA ===" -ForegroundColor Cyan