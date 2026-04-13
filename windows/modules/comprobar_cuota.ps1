# Crea un archivo de 6MB en la carpeta de un usuario NoCuates
# Debería fallar al intentar escribir más de 5MB
$testPath = "C:\Perfiles\NoCuates\storres\test.dat"
$bytes = New-Object byte[] (6MB)
[System.IO.File]::WriteAllBytes($testPath, $bytes)
# Si la cuota funciona, esto lanzará un error de espacio insuficiente