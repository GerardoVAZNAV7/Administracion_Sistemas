$usuarios = Import-Csv "C:\Users\Administrator\Administracion_Sistemas\windows\modules\usuarios.csv"
foreach ($u in $usuarios) {
    $nombre = $u.usuario.Trim()
    $depto  = $u.departamento.Trim() -replace " ", ""
    Set-ADUser -Identity $nombre `
        -HomeDirectory "\\192.168.10.10\Perfiles\$depto\$nombre" `
        -HomeDrive "H:"
}