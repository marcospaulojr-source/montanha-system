FROM nginx:alpine
COPY index.html /usr/share/nginx/html/index.html
COPY manifest.json /usr/share/nginx/html/manifest.json
COPY sw.js /usr/share/nginx/html/sw.js
COPY icon-192.png /usr/share/nginx/html/icon-192.png
COPY icon-512.png /usr/share/nginx/html/icon-512.png
COPY nginx.conf /etc/nginx/conf.d/default.conf
EXPOSE 80
