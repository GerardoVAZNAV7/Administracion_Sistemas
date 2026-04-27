# ── Imagen base ligera ──────────────────────────────────────────────────────
FROM nginx:1.25-alpine

# El módulo DAV básico ya viene incluido en nginx:alpine
# Intentamos el módulo extendido pero no falla si no está disponible
RUN apk add --no-cache nginx-mod-dav-ext 2>/dev/null || true

# Copiar configuración personalizada
COPY nginx.conf /etc/nginx/nginx.conf

# Copiar contenido web estático
COPY html/ /usr/share/nginx/html/

# Crear directorio de archivos compartido con FTP
RUN mkdir -p /usr/share/nginx/html/files

# Permisos para usuario no-root (nginx uid=101)
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

# Ejecutar como usuario no administrativo
USER nginx

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
