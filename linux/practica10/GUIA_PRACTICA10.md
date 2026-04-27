# ============================================================
#  PRÁCTICA 10 — GUÍA COMPLETA PASO A PASO
#  Migración de Servicios a Contenedores Docker
#  Fedora Server · Nginx · PostgreSQL · FTP
# ============================================================

## PARTE 0: PREPARAR EL SERVIDOR FEDORA

### Paso 0.1 — Instalar Docker y Docker Compose

```bash
# Actualizar el sistema primero
sudo dnf update -y

# Instalar el repositorio oficial de Docker
sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo

# Instalar Docker y sus componentes
sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Iniciar Docker y habilitarlo para que arranque con el servidor
sudo systemctl start docker
sudo systemctl enable docker

# Verificar que funciona (debe mostrar "Hello from Docker!")
sudo docker run hello-world
```

### Paso 0.2 — Agregar tu usuario al grupo docker (opcional, evita escribir sudo)

```bash
sudo usermod -aG docker $USER
# Cierra sesión y vuelve a entrar para que aplique
```

---

## PARTE 1: PREPARAR LOS ARCHIVOS DEL PROYECTO

### Estructura de carpetas que debes tener:

```
practica10/
├── docker-compose.yml          ← Orquesta todo
├── nginx/
│   ├── Dockerfile              ← Construye la imagen de Nginx
│   ├── nginx.conf              ← Configuración de Nginx
│   └── web_content/            ← Archivos web iniciales
│       ├── index.html
│       ├── css/style.css
│       └── img/server.svg
├── ftp/
│   ├── Dockerfile              ← Construye la imagen FTP
│   └── vsftpd.conf             ← Configuración FTP
├── postgres/
│   └── backup_postgres.sh      ← Script de respaldo
└── backups/                    ← Aquí llegan los respaldos (se crea solo)
```

### Paso 1.1 — Copiar todos los archivos a tu servidor

Sube toda la carpeta `practica10/` a tu Fedora Server.
Puedes usar SCP desde tu máquina local:

```bash
scp -r practica10/ usuario@IP_DEL_SERVIDOR:/home/usuario/
```

### Paso 1.2 — Entrar a la carpeta del proyecto

```bash
cd ~/practica10
```

### Paso 1.3 — Dar permisos al script de respaldo

```bash
chmod +x postgres/backup_postgres.sh
mkdir -p backups
```

---

## PARTE 2: CONSTRUIR Y LEVANTAR LOS CONTENEDORES

### Paso 2.1 — Construir las imágenes personalizadas

```bash
# Este comando lee los Dockerfiles y construye las imágenes
sudo docker compose build
```

### Paso 2.2 — Levantar toda la infraestructura

```bash
# -d significa "detached" = en segundo plano
sudo docker compose up -d
```

### Paso 2.3 — Verificar que los contenedores están corriendo

```bash
sudo docker ps
```
Debes ver tres contenedores: nginx-web, postgres-db, ftp-server con estado "Up".

### Paso 2.4 — Ver los logs si algo falla

```bash
sudo docker compose logs nginx-web
sudo docker compose logs postgres-db
sudo docker compose logs ftp-server
```

---

## PARTE 3: PRUEBAS DE VALIDACIÓN

### PRUEBA 10.1 — Persistencia de Base de Datos

```bash
# 1. Entrar al contenedor de postgres
sudo docker exec -it postgres-db psql -U admin -d practica10

# 2. Crear una tabla y agregar datos (dentro de psql)
CREATE TABLE usuarios (id SERIAL PRIMARY KEY, nombre VARCHAR(50));
INSERT INTO usuarios (nombre) VALUES ('Ana'), ('Carlos'), ('María');
SELECT * FROM usuarios;
\q

# 3. Eliminar el contenedor con fuerza
sudo docker rm -f postgres-db

# 4. Volver a levantarlo
sudo docker compose up -d postgres-db

# 5. Verificar que los datos siguen ahí
sudo docker exec -it postgres-db psql -U admin -d practica10
SELECT * FROM usuarios;
# ✅ Deben aparecer los mismos 3 usuarios
\q
```

### PRUEBA 10.2 — Aislamiento de Red (ping por nombre)

```bash
# Entrar al contenedor de nginx
sudo docker exec -it nginx-web sh

# Instalar ping (Alpine no lo trae por defecto)
apk add --no-cache iputils

# Hacer ping al contenedor de base de datos POR NOMBRE
ping postgres-db -c 3

# ✅ Debe responder desde 172.20.0.20
exit
```

### PRUEBA 10.3 — Permisos FTP (subir archivo y verlo en web)

```bash
# Opción A: usar el cliente ftp desde Fedora
sudo dnf install -y ftp
ftp localhost

# Credenciales:
# usuario: ftpuser
# contraseña: ftppass123

# Dentro del cliente FTP:
put archivo_prueba.txt
bye

# Verificar que nginx puede ver el archivo
sudo docker exec -it nginx-web ls /usr/share/nginx/html/
# ✅ Debe aparecer archivo_prueba.txt

# También lo puedes verificar en el navegador:
# http://IP_DEL_SERVIDOR/archivo_prueba.txt
```

### PRUEBA 10.4 — Límites de Recursos

```bash
# Ver estadísticas de uso de recursos en tiempo real
sudo docker stats --no-stream

# ✅ En la columna MEM LIMIT debes ver:
# nginx-web   → 512MiB
# postgres-db → 512MiB
# ftp-server  → 256MiB
```

---

## PARTE 4: RESPALDO MANUAL DE POSTGRESQL

```bash
# Ejecutar el script de respaldo manualmente
sudo docker exec postgres-db sh /usr/local/bin/backup_postgres.sh

# Ver los respaldos generados en el HOST
ls -lh ~/practica10/backups/
# ✅ Debe aparecer un archivo backup_YYYYMMDD_HHMMSS.sql
```

---

## COMANDOS ÚTILES DE REFERENCIA

```bash
# Ver todos los contenedores (incluyendo detenidos)
sudo docker ps -a

# Detener toda la infraestructura
sudo docker compose down

# Detener Y eliminar volúmenes (¡CUIDADO! borra datos)
sudo docker compose down -v

# Reiniciar un servicio específico
sudo docker compose restart nginx-web

# Ver redes creadas
sudo docker network ls
sudo docker network inspect infra_red

# Ver volúmenes creados
sudo docker volume ls
sudo docker volume inspect db_data
```

---

## ¿QUÉ HACE CADA ARCHIVO?

| Archivo | Para qué sirve |
|---|---|
| `docker-compose.yml` | Define y orquesta los 3 servicios juntos |
| `nginx/Dockerfile` | Construye una imagen Nginx segura sobre Alpine |
| `nginx/nginx.conf` | Configura el servidor web (rutas, cabeceras, logs) |
| `ftp/Dockerfile` | Construye la imagen del servidor FTP |
| `ftp/vsftpd.conf` | Configura el FTP (usuarios, puertos, modo pasivo) |
| `postgres/backup_postgres.sh` | Script que genera respaldos SQL automáticamente |
| `web_content/` | La página web que sirve Nginx |
