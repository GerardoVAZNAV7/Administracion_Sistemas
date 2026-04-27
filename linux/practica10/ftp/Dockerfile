FROM alpine:3.19

RUN apk add --no-cache vsftpd

# Crear usuario ftpuser con directorio home correcto
RUN adduser -D -h /ftp/webfiles ftpuser && \
    echo "ftpuser:ftp12345" | chpasswd

# Crear directorio con permisos correctos
RUN mkdir -p /ftp/webfiles && \
    chown -R ftpuser:ftpuser /ftp && \
    chmod 755 /ftp && \
    chmod 777 /ftp/webfiles

COPY vsftpd.conf /etc/vsftpd/vsftpd.conf

EXPOSE 21 21100 21101 21102 21103 21104 21105

CMD ["/usr/sbin/vsftpd", "/etc/vsftpd/vsftpd.conf"]
