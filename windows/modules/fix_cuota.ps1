$RutaRaiz     = "C:\Perfiles"
$RutaCuates   = "$RutaRaiz\Cuates"
$RutaNoCuates = "$RutaRaiz\NoCuates"

# Limpiar plantillas anteriores (fallidas)
foreach ($p in @("FIM_10MB","FIM_5MB")) {
    if (Get-FsrmQuotaTemplate -Name $p -ErrorAction SilentlyContinue) {
        Remove-FsrmQuotaTemplate -Name $p -Confirm:$false
    }
}

# Crear plantillas SIN -SoftLimit (dura es el default)
New-FsrmQuotaTemplate -Name "FIM_10MB" -Size 10485760   # 10 MB en bytes
New-FsrmQuotaTemplate -Name "FIM_5MB"  -Size 5242880    # 5 MB en bytes
Write-Host "Plantillas creadas." -ForegroundColor Green

# Verificar que existen antes de continuar
Get-FsrmQuotaTemplate | Where-Object { $_.Name -like "FIM*" } | Format-Table Name, Size

# Aplicar a carpetas Cuates (10MB)
Get-ChildItem $RutaCuates -Directory | Where-Object { $_.Name -ne "General" } | ForEach-Object {
    if (Get-FsrmQuota -Path $_.FullName -ErrorAction SilentlyContinue) {
        Remove-FsrmQuota -Path $_.FullName -Confirm:$false
    }
    New-FsrmQuota -Path $_.FullName -Template "FIM_10MB"
    Write-Host "  10MB -> $($_.Name)" -ForegroundColor Green
}

# Aplicar a carpetas NoCuates (5MB)
Get-ChildItem $RutaNoCuates -Directory | Where-Object { $_.Name -ne "General" } | ForEach-Object {
    if (Get-FsrmQuota -Path $_.FullName -ErrorAction SilentlyContinue) {
        Remove-FsrmQuota -Path $_.FullName -Confirm:$false
    }
    New-FsrmQuota -Path $_.FullName -Template "FIM_5MB"
    Write-Host "  5MB -> $($_.Name)" -ForegroundColor Green
}

# Verificación final
Write-Host "`n=== Resultado ===" -ForegroundColor Cyan
Get-FsrmQuota | Format-Table Path, @{N="MB";E={$_.Size/1MB}}, Usage -AutoSize