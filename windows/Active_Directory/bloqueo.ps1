$exe = "C:\Program Files\multiOTP\multiotp.exe"

# Ver estado del usuario bloqueado
$p = New-Object System.Diagnostics.ProcessStartInfo
$p.FileName               = $exe
$p.Arguments              = "-user-info admin_identidad"
$p.WorkingDirectory       = "C:\Program Files\multiOTP"
$p.RedirectStandardOutput = $true
$p.RedirectStandardError  = $true
$p.UseShellExecute        = $false
$proc = [System.Diagnostics.Process]::Start($p)
$proc.WaitForExit()
Write-Host $proc.StandardOutput.ReadToEnd()
# Debe mostrar Locked: yes o Delayed: yes
