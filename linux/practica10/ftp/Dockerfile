FROM alpine:3.19

RUN apk add --no-cache vsftpd

RUN adduser -D -h /ftp/webfiles ftpuser && \
    echo "ftpuser:ftppass123" | chpasswd

RUN mkdir -p /ftp/webfiles && \
    chown ftpuser:ftpuser /ftp/webfiles && \
    chmod 777 /ftp/webfiles

COPY vsftpd.conf /etc/vsftpd/vsftpd.conf

EXPOSE 21 21100 21101 21102 21103 21104 21105

CMD ["/usr/sbin/vsftpd", "/etc/vsftpd/vsftpd.conf"]
