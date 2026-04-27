# Práctica 10 — Migración de Servicios a Contenedores

## Estructura del proyecto

```
practica10/
├── docker-compose.yml
├── instalar_docker.sh      ← Instala Docker en VM nueva
├── test_practica10.sh      ← Pruebas automatizadas 10.1 - 10.4
├── upload_ftp.sh           ← Subida de archivos por FTP
├── nginx/
│   ├── Dockerfile
│   ├── nginx.conf
│   └── html/
│       ├── index.html
│       ├── css/style.css
│       └── img/server.svg
├── postgres/
│   └── backup_postgres.sh
└── ftp/
    ├── Dockerfile
    └── vsftpd.conf
```

## Paso 1 — Instalar Docker (VM sin Docker)

```bash
sudo bash instalar_docker.sh
```

Cierra sesión y vuelve a entrar para que el grupo docker surta efecto, luego:

```bash
docker --version
docker compose version
```

## Paso 2 — Levantar los contenedores

```bash
cd practica10
docker compose up -d --build
```

Verifica que todos estén corriendo:

```bash
docker ps
```

Debes ver: `web_server`, `db_postgres`, `ftp_server`, `busybox`

## Paso 3 — Ejecutar pruebas

```bash
chmod +x test_practica10.sh upload_ftp.sh
./test_practica10.sh
```

## Prueba manual de FTP

```bash
./upload_ftp.sh /ruta/a/tu/archivo.txt
```

O desde otro cliente FTP:
- Host: 127.0.0.1
- Puerto: 21
- Usuario: ftpuser
- Contraseña: ftp12345
- Modo: Pasivo

El archivo aparecerá en: http://localhost/files/

## Servicios y puertos

| Servicio     | IP interna    | Puerto externo |
|-------------|---------------|----------------|
| web_server  | 172.20.0.10   | 80             |
| db_postgres | 172.20.0.20   | —              |
| ftp_server  | 172.20.0.30   | 21, 21100-21105|
| busybox     | 172.20.0.40   | —              |

## Credenciales

| Servicio   | Usuario  | Contraseña |
|-----------|----------|------------|
| PostgreSQL | admin    | admin123   |
| FTP        | ftpuser  | ftp12345   |

## Comandos útiles

```bash
# Ver logs
docker logs web_server
docker logs ftp_server
docker logs db_postgres

# Ping entre contenedores (prueba 10.2)
docker exec busybox ping -c 3 db_postgres
docker exec busybox ping -c 3 web_server

# Ver estadísticas de recursos (prueba 10.4)
docker stats --no-stream

# Inspeccionar red
docker network inspect practica10_infra_red

# Backup manual de PostgreSQL
docker exec db_postgres bash /backup.sh

# Apagar todo
docker compose down

# Apagar y borrar volúmenes (CUIDADO: elimina datos)
docker compose down -v
```
