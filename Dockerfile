FROM vabene1111/recipes:latest

USER root

# 修復所有可能導致 Nginx 權限失敗的資料夾
RUN mkdir -p /opt/recipes/staticfiles /opt/recipes/mediafiles /var/lib/nginx /var/log/nginx && \
    chown -R 1000:1000 /opt/recipes/staticfiles /opt/recipes/mediafiles /var/lib/nginx /var/log/nginx /run

USER 1000
