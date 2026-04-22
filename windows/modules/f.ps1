$path = "C:\ProgramData\ssh\sshd_config"
$config = Get-Content $path -Raw

# Quitar solo la linea AuthorizedKeysFile dentro del bloque Match
$config = $config -replace "(?m)^\s*AuthorizedKeysFile\s+__PROGRAMDATA__.*?(\r?\n)", ""

$config | Out-File $path -Encoding UTF8 -Force
Restart-Service sshd -Force
Write-Host "Listo!" -ForegroundColor Green