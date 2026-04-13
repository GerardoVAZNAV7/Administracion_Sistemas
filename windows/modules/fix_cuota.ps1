$RutaRaiz = "C:\Perfiles"

# Verificar estado actual
Write-Host "=== Cuotas existentes ===" -ForegroundColor Cyan
Get-FsrmQuota | Format-Table Path, Size, SoftLimit, Usage -AutoSize
Get-FsrmAutoQuota | Format-Table Path, Template -AutoSize

# Forzar cuotas en TODAS las carpetas de usuario ya existentes
$RutaCuates   = "$RutaRaiz\Cuates"
$RutaNoCuates = "$RutaRaiz\NoCuates"

# Limpiar y recrear plantillas
foreach ($p in @("FIM_10MB","FIM_5MB")) {
    if (Get-FsrmQuotaTemplate -Name $p -ErrorAction SilentlyContinue) {
        Remove-FsrmQuotaTemplate -Name $p -Confirm:$false
    }
}

New-FsrmQuotaTemplate -Name "FIM_10MB" -Size 10MB -SoftLimit $false
New-FsrmQuotaTemplate -Name "FIM_5MB"  -Size 5MB  -SoftLimit $false
Write-Host "Plantillas recreadas (cuota DURA, no soft)." -ForegroundColor Green

# Aplicar cuota a cada carpeta de usuario manualmente
Get-ChildItem $RutaCuates -Directory | Where-Object { $_.Name -ne "General" } | ForEach-Object {
    if (Get-FsrmQuota -Path $_.FullName -ErrorAction SilentlyContinue) {
        Remove-FsrmQuota -Path $_.FullName -Confirm:$false
    }
    New-FsrmQuota -Path $_.FullName -Template "FIM_10MB"
    Write-Host "  Cuota 10MB -> $($_.FullName)" -ForegroundColor Green
}

Get-ChildItem $RutaNoCuates -Directory | Where-Object { $_.Name -ne "General" } | ForEach-Object {
    if (Get-FsrmQuota -Path $_.FullName -ErrorAction SilentlyContinue) {
        Remove-FsrmQuota -Path $_.FullName -Confirm:$false
    }
    New-FsrmQuota -Path $_.FullName -Template "FIM_5MB"
    Write-Host "  Cuota 5MB  -> $($_.FullName)" -ForegroundColor Green
}

# Verificar que quedó bien
Write-Host "`n=== Verificación final ===" -ForegroundColor Cyan
Get-FsrmQuota | Format-Table Path, @{N="Límite";E={"{0:N0} MB" -f ($_.Size/1MB)}}, SoftLimit, @{N="Uso MB";E={"{0:N2}" -f ($_.Usage/1MB)}} -AutoSize