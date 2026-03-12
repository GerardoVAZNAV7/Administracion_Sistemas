# ── DIAGNOSTICO TEMPORAL - borrar despues ──
Write-Host "`n=== ESTADO DEL DIRECTORIO DEL USUARIO ===" -ForegroundColor Yellow
Write-Host "UserHome: $UserHome"
Write-Host "Existe UserHome: $(Test-Path $UserHome)"
Get-ChildItem $UserHome -Force -ErrorAction SilentlyContinue | ForEach-Object {
    $esJunction = ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0
    Write-Host "  $($_.Name)  [Junction=$esJunction]  Atributos=$($_.Attributes)"
    if ($esJunction) {
        $target = cmd /c "fsutil reparsepoint query `"$($_.FullName)`"" 2>&1 | Select-String "Print Name"
        Write-Host "    -> Target: $target"
    }
}
Write-Host "==========================================`n" -ForegroundColor Yellow