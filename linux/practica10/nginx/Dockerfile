FROM nginx:alpine

RUN apk add --no-cache iputils busybox-extras && \
    chmod u+s $(find / -name "ping" 2>/dev/null | head -1)

RUN sed -i 's|#server_tokens off;|server_tokens off;|' /etc/nginx/nginx.conf

COPY nginx.conf /etc/nginx/conf.d/default.conf

RUN addgroup -S webgroup && adduser -S webuser -G webgroup

COPY web_content/ /usr/share/nginx/html/

RUN chown -R webuser:webgroup /usr/share/nginx/html && \
    chown -R webuser:webgroup /var/cache/nginx && \
    chown -R webuser:webgroup /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown webuser:webgroup /var/run/nginx.pid

USER webuser

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
