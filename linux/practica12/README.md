# Práctica 12 + 13 — Servidor de Correo Privado + Webmail
## Fedora Server · Usuario: gerardovn · Dominio: reprobados.com

---

## Estructura del proyecto

```
practica12/
├── .env                          # credenciales (NO subir a git)
├── docker-compose.yml            # orquestación completa
├── roundcube/
│   └── config.inc.php            # personalización institucional
├── certs/                        # generado por setup.sh
│   ├── cert.pem
│   └── key.pem
├── backups/                      # respaldos automáticos
├── setup.sh                      # instalación completa
├── backup.sh                     # respaldo manual/cron
├── restore.sh                    # restauración desde backup
├── tests.sh                      # pruebas de aceptación
└── README.md
```

---

## Pasos de instalación

```bash
# 1. Subir al servidor
scp -r practica12/ gerardovn@IP_SERVIDOR:~/

# 2. Ejecutar setup (requiere sudo)
ssh gerardovn@IP_SERVIDOR
cd ~/practica12
sudo bash setup.sh

# 3. Correr pruebas
bash tests.sh
```

---

## Coexistencia con Práctica 11

| Servicio        | Puerto | Práctica |
|----------------|--------|----------|
| nginx (web)    | 80     | P11      |
| Roundcube HTTP | 8080   | P12      |
| Roundcube HTTPS| 8443   | P12      |
| SMTP           | 25, 587, 465 | P12 |
| IMAP           | 143, 993 | P12   |

No hay conflictos de puertos entre ambas prácticas.

---

## Accesos

| Recurso         | URL / Dirección                          |
|----------------|------------------------------------------|
| Roundcube HTTP  | http://IP_SERVIDOR:8080                  |
| Roundcube HTTPS | https://IP_SERVIDOR:8443                 |
| IMAP (cliente)  | IP_SERVIDOR:993  SSL habilitado          |
| SMTP (cliente)  | IP_SERVIDOR:587  STARTTLS habilitado     |

### Cuentas de correo
| Cuenta                        | Contraseña    |
|-------------------------------|---------------|
| director@reprobados.com       | Director2025! |
| admin@reprobados.com          | Admin2025!    |

---

## Configurar respaldo automático cada 24 horas

### Opción A — Cron
```bash
sudo crontab -e
# Agregar esta línea:
0 2 * * * bash /home/gerardovn/practica12/backup.sh >> /home/gerardovn/practica12/backups/backup.log 2>&1
```

### Opción B — Systemd Timer
```bash
# Crear el servicio
sudo tee /etc/systemd/system/mail-backup.service << 'EOF'
[Unit]
Description=Respaldo de buzones de correo

[Service]
Type=oneshot
User=gerardovn
ExecStart=/bin/bash /home/gerardovn/practica12/backup.sh
EOF

# Crear el timer (cada 24 horas a las 02:00)
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
sudo systemctl list-timers | grep mail-backup
```

---

## Arquitectura

```
[Navegador del estudiante]
        │
        │ HTTPS :8443 / HTTP :8080
        ▼
   [Roundcube] ──────────────────── red_correo (Docker)
        │  IMAP :993 (interno)
        │  SMTP :587 (interno)
        ▼
  [Mailserver] ← Postfix + Dovecot + Rspamd + Fail2Ban + OpenDKIM
        │
        │ volumen nombrado
        ▼
   [mail_data] /var/mail  (buzones persistentes)

  [Roundcube DB (MariaDB)] ← preferencias, libreta de direcciones
        │
        ▼
  [roundcube_db_data] (volumen persistente)
```

---

## Registros DNS (para dominio real)

```
MX    reprobados.com.          10 mail.reprobados.com.
A     mail.reprobados.com.     IP_DEL_SERVIDOR
TXT   reprobados.com.          "v=spf1 ip4:IP_DEL_SERVIDOR -all"
TXT   _dmarc.reprobados.com.   "v=DMARC1; p=quarantine; rua=mailto:admin@reprobados.com"
TXT   mail._domainkey.         (ver salida de setup.sh para la clave DKIM)
```

---

## En modo laboratorio — /etc/hosts

Agregar en **tu PC** (cliente):
```
IP_SERVIDOR   mail.reprobados.com   reprobados.com   mail
```
- Windows: `C:\Windows\System32\drivers\etc\hosts`
- Linux/Mac: `/etc/hosts`

---

## Comandos útiles

```bash
# Ver logs del servidor de correo
docker logs -f p12_mailserver

# Ver logs de Roundcube
docker logs -f p12_roundcube

# Agregar cuenta de correo
docker exec p12_mailserver setup email add usuario@reprobados.com Contrasena123!

# Ver cuentas existentes
docker exec p12_mailserver setup email list

# Verificar Fail2Ban
docker exec p12_mailserver fail2ban-client status

# Ver jails de Fail2Ban
docker exec p12_mailserver fail2ban-client status dovecot

# Restaurar backup más reciente
sudo bash restore.sh

# Restaurar backup específico
sudo bash restore.sh backups/mail_backup_20250509_020000.tar.gz
```
