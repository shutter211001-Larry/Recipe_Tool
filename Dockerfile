FROM vabene1111/recipes:latest

USER root

# 修復所有可能導致 Nginx 權限失敗的資料夾
RUN mkdir -p /opt/recipes/staticfiles /opt/recipes/mediafiles /var/lib/nginx /var/log/nginx && \
    chown -R 1000:1000 /opt/recipes/staticfiles /opt/recipes/mediafiles /var/lib/nginx /var/log/nginx /run

# 複製啟動腳本並給予執行權限
COPY railway_start.sh /opt/recipes/railway_start.sh
RUN chmod +x /opt/recipes/railway_start.sh

USER 1000

# 設定為容器的啟動入口點
ENTRYPOINT ["/opt/recipes/railway_start.sh"]
