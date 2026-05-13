FROM nginx:1.28.3-alpine
LABEL org.opencontainers.image.title="Networking 4 PiCube Cluster Site"
LABEL org.opencontainers.image.description="Course project for MSTC Networking 4 — K3s deployment of a custom static site"
LABEL org.opencontainers.image.authors="Troy Krezine"
LABEL org.opencontainers.image.source="https://github.com/tkrezine2432/Net4_K3_Lab"
LABEL org.opencontainers.image.url="https://hub.docker.com/r/tkrezine2432/piweb"
LABEL org.opencontainers.image.licenses="MIT"
COPY index.html /usr/share/nginx/html/index.html
