# Práctica 12 + 13 — Servidor de Correo Privado + Webmail
## Fedora Server · Usuario: gerardovn · Dominio: reprobados.com

---

## Estructura del proyecto

```
practica12/
├── .env                          # credenciales (NO subir a git)
├── docker-compose.yml            # orquestación completa
├── setup.sh                      # instalación completa
├── backup.sh                     # respaldo manual/cron
├── restore.sh                    # restauración desde backup
├── tests.sh                      # pruebas de aceptación
├── README.md                     # este archivo
│
├── roundcube/
│   └── config.inc.php            # personalización institucional
│
├── logo/                         # personalización visual
│   ├── logo_login.png            # logo para pantalla de login
│   ├── logo_nav.png              # logo para barra superior
│   ├── favicon.png               # ícono pestaña del navegador
│   ├── custom.css                # estilos institucionales
│   └── instalar_logo.sh         # script de instalación del logo
│
├── certs/                        # generado por setup.sh
├── backups/                      # respaldos automáticos
├── mail-config/                  # configuración dinámica
└── logs/                         # logs auditables
```

---

## Pasos de instalación

### 1. Subir al servidor
```bash
scp -r practica12/ gerardovn@IP_SERVIDOR:~/
```

### 2. Ejecutar setup principal (requiere sudo)
```bash
ssh gerardovn@IP_SERVIDOR
cd ~/practica12
sudo bash setup.sh
```

### 3. Instalar logo institucional
```bash
bash logo/instalar_logo.sh
```

### 4. Correr pruebas de aceptación
```bash
bash tests.sh
```

---

## Coexistencia con Práctica 11

| Servicio         | Puerto       | Práctica |
|-----------------|--------------|----------|
| nginx (web)     | 80           | P11      |
| Roundcube HTTP  | 8080         | P12      |
| Roundcube HTTPS | 8443         | P12      |
| SMTP            | 25, 587, 465 | P12      |
| IMAP            | 143, 993     | P12      |

---

## Accesos

| Recurso          | Dirección                              |
|-----------------|----------------------------------------|
| Roundcube HTTP  | http://IP_SERVIDOR:8080                |
| Roundcube HTTPS | https://IP_SERVIDOR:8443               |
| IMAP (cliente)  | IP_SERVIDOR:993  SSL habilitado        |
| SMTP (cliente)  | IP_SERVIDOR:587  STARTTLS habilitado   |

### Cuentas de correo
| Cuenta                    | Contraseña    |
|--------------------------|---------------|
| director@reprobados.com  | Director2025! |
| admin@reprobados.com     | Admin2025!    |

---

## Configurar respaldo automático cada 24 horas

### Opción A — Cron
```bash
sudo crontab -e
# Agregar:
0 2 * * * bash /home/gerardovn/practica12/backup.sh >> /home/gerardovn/practica12/backups/backup.log 2>&1
```

### Opción B — Systemd Timer
```bash
sudo tee /etc/systemd/system/mail-backup.service << 'EOF'
[Unit]
Description=Respaldo de buzones de correo
[Service]
Type=oneshot
User=gerardovn
ExecStart=/bin/bash /home/gerardovn/practica12/backup.sh
EOF

sudo tee /etc/systemd/system/mail-backup.timer << 'EOF'
[Unit]
Description=Timer de respaldo de correo
[Timer]
OnCalendar=*-*-* 02:00:00
Persistent=true
[Install]
WantedBy=timers.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now mail-backup.timer
```

---

## Personalización visual

El logo de Reprobados.com aparece en login, navbar y favicon.
Colores: azul oscuro `#2B3A4A` y cobre `#C07840`.

Para reinstalar tras recrear el contenedor:
```bash
bash ~/practica12/logo/instalar_logo.sh
```

---

## Registros DNS (dominio real)

```
MX    reprobados.com.         10 mail.reprobados.com.
A     mail.reprobados.com.    IP_DEL_SERVIDOR
TXT   reprobados.com.         "v=spf1 ip4:IP_DEL_SERVIDOR -all"
TXT   _dmarc.reprobados.com.  "v=DMARC1; p=quarantine; rua=mailto:admin@reprobados.com"
TXT   mail._domainkey.        (ver salida de setup.sh para clave DKIM)
```

En modo laboratorio agregar en `/etc/hosts` de tu PC:
```
IP_SERVIDOR   mail.reprobados.com   reprobados.com   mail
```

---

## Comandos útiles

```bash
docker logs -f p12_mailserver                         # logs correo
docker logs -f p12_roundcube                          # logs webmail
docker exec p12_mailserver setup email list           # ver cuentas
docker exec p12_mailserver setup email add user@reprobados.com Pass123!
docker exec p12_mailserver fail2ban-client status     # fail2ban
sudo bash restore.sh                                  # restaurar backup
bash logo/instalar_logo.sh                            # reinstalar logo
```
