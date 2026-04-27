# ============================================================
# Dockerfile — Servidor FTP con vsftpd
# Base: Alpine Linux
# ============================================================

FROM alpine:3.19

# Instalamos vsftpd (Very Secure FTP Daemon)
RUN apk add --no-cache vsftpd

# Creamos el usuario FTP con su carpeta
RUN adduser -D -h /ftp/webfiles ftpuser && \
    echo "ftpuser:ftppass123" | chpasswd

# Creamos la carpeta que se compartirá con nginx
RUN mkdir -p /ftp/webfiles && \
    chown ftpuser:ftpuser /ftp/webfiles && \
    chmod 755 /ftp/webfiles

# Copiamos la configuración de vsftpd
COPY vsftpd.conf /etc/vsftpd/vsftpd.conf

# Exponemos los puertos FTP
# 21 = control,  21100-21110 = datos (modo pasivo)
EXPOSE 21 21100 21101 21102 21103 21104 21105

CMD ["/usr/sbin/vsftpd", "/etc/vsftpd/vsftpd.conf"]
