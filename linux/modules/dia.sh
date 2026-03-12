# 1. Ver si SELinux esta bloqueando
sudo ausearch -m avc -ts recent 2>/dev/null | grep vsftpd | tail -20

# 2. Ver estado actual de los booleanos FTP
getsebool -a | grep ftp

# 3. Ver contexto SELinux de la carpeta del grupo
ls -lZd /srv/ftp/groups/reprobados
ls -lZd /home/t1/reprobados

# 4. Ver permisos reales y ACLs
ls -la /home/t1/
getfacl /srv/ftp/groups/reprobados
id t1