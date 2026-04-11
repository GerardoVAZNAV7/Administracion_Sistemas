# Compartir la carpeta Perfiles en red
New-SmbShare -Name "Perfiles" `
    -Path "C:\Perfiles" `
    -FullAccess "BAJA\Administrators" `
    -ChangeAccess "BAJA\Domain Users"

    $usuarios = Import-Csv "C:\Users\Administrator\Administracion_Sistemas\windows\modules\usuarios.csv"

foreach ($u in $usuarios) {
    $nombre = $u.Usuario
    $depto = $u.Departamento -replace " ", ""
    
    Set-ADUser -Identity $nombre `
        -HomeDirectory "\\192.168.10.10\Perfiles\$depto\$nombre" `
        -HomeDrive "H:"
}