# 1. Instalar el binario del rol
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# 2. Crear el nuevo bosque (Cambia "practica8.local" por el nombre que quieras)
# NOTA: Esto reiniciará el servidor automáticamente al terminar.
Install-ADDSForest -DomainName "practica8.local" -SafeModeAdministratorPassword (ConvertTo-SecureString "DRAGONBALLz1234!!" -AsPlainText -Force) -Force