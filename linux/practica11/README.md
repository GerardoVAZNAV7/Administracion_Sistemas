# Práctica 11 — Infraestructura como Código con Docker
## Fedora Server · Usuario: gerardovn

---

## Estructura del proyecto

```
practica11/
├── .env                # credenciales y variables (NO subir a git)
├── docker-compose.yml  # orquestación completa
├── nginx.conf          # balanceador de carga
├── setup.sh            # instalación + firewall
├── tests.sh            # pruebas de aceptación automáticas
└── README.md           # este archivo
```

---

## Pasos de instalación

### 1. Copiar archivos al servidor
```bash
scp -r practica11/ gerardovn@IP_DEL_SERVIDOR:~/
```

### 2. Ejecutar el setup (requiere sudo)
```bash
ssh gerardovn@IP_DEL_SERVIDOR
cd ~/practica11
sudo bash setup.sh
```

### 3. Verificar que todo está corriendo
```bash
docker compose ps
```

---

## Ejecutar las pruebas automáticas

```bash
cd ~/practica11
bash tests.sh
```

---

## Prueba 11.3 — Túnel SSH (manual desde tu PC)

```bash
ssh -L 8080:p11_pgadmin:80 gerardovn@IP_DEL_SERVIDOR
```
Luego abre en tu navegador: **http://localhost:8080**

Credenciales pgAdmin:
- Email: `admin@local.lab`
- Password: `Admin2025!`

En pgAdmin, agrega un servidor con:
- Host: `postgres`
- Puerto: `5432`
- Usuario/DB según `.env`

---

## Arquitectura

```
[Tu PC]
   │
   │  Puerto 80 (HTTP público)
   ▼
[nginx] ──────────────────────── red_publica
   │
   │  proxy_pass (interno, sin puerto en host)
   ▼
[webserver]                      red_publica

[Tu PC] ──SSH tunnel──► [Fedora Server] ──► [pgadmin] ── red_datos
                                                │
                                                └──────► [postgres] ── red_datos
                                                              │
                                                          volumen pg_data
```

---

## Comandos útiles

```bash
# Ver logs de un servicio
docker compose logs -f postgres

# Verificar healthcheck de postgres
docker inspect --format='{{.State.Health.Status}}' p11_postgres

# Entrar al contenedor de nginx
docker exec -it p11_nginx sh

# Bajar el stack (SIN borrar datos)
docker compose down

# Bajar el stack Y borrar volúmenes (datos perdidos)
docker compose down -v
```
