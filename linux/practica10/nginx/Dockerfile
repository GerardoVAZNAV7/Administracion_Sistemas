# ── Imagen base ligera ──────────────────────────────────────────────────────
FROM nginx:1.25-alpine

# Instalar módulo WebDAV (para subida de archivos desde el navegador)
# ngx_http_dav_module viene compilado en el paquete nginx-module-dav de Alpine
RUN apk add --no-cache nginx-mod-dav-ext || true
# (El módulo DAV básico ya está incluido en nginx:alpine por defecto)

# ── Copiar configuración personalizada ────────────────────────────────────────
COPY nginx.conf /etc/nginx/nginx.conf

# ── Copiar contenido web estático ─────────────────────────────────────────────
COPY html/ /usr/share/nginx/html/

# ── Crear directorio de archivos FTP compartido ───────────────────────────────
# Este directorio se montará como volumen compartido con ftp_server
RUN mkdir -p /usr/share/nginx/html/files

# ── Permisos para usuario no-root (nginx, uid=101) ────────────────────────────
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

# ── Ejecutar como usuario no administrativo ───────────────────────────────────
USER nginx

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]