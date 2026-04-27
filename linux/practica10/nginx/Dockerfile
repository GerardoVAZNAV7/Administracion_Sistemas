# ============================================================
# Dockerfile — Servidor Web Nginx personalizado
# Base: Alpine Linux (imagen ligera ~5MB)
# ============================================================

# 1. Usamos Alpine como base (muy ligero, seguro)
FROM nginx:alpine

# 2. Instalamos iputils (incluye ping) para la prueba de red
RUN apk add --no-cache iputils

# 3. Eliminamos las firmas del servidor (server_tokens off)
#    Esto evita que Nginx revele su versión en cabeceras HTTP
RUN sed -i 's|#server_tokens off;|server_tokens off;|' /etc/nginx/nginx.conf

# 3. Copiamos nuestra configuración personalizada de Nginx
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 4. Creamos un usuario no administrativo llamado "webuser"
#    Los contenedores seguros NO deben correr como root
RUN addgroup -S webgroup && adduser -S webuser -G webgroup

# 5. Copiamos el contenido web inicial (luego se reemplaza con volumen)
COPY web_content/ /usr/share/nginx/html/

# 6. Asignamos permisos correctos al usuario webuser
RUN chown -R webuser:webgroup /usr/share/nginx/html && \
    chown -R webuser:webgroup /var/cache/nginx && \
    chown -R webuser:webgroup /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown webuser:webgroup /var/run/nginx.pid

# 7. Cambiamos al usuario no-root para ejecutar nginx
USER webuser

# 8. Exponemos el puerto 80
EXPOSE 80

# 9. Comando de inicio
CMD ["nginx", "-g", "daemon off;"]
