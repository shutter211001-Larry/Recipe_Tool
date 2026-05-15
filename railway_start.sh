#!/bin/sh
# ------------------------------------------------------------
# railway_start.sh  (Alpine / sh 相容版)
#   1. 修復 usersessions_usersession.id 序列
#   2. 執行所有 Django migrations
#   3. 清除過期 Session
#   4. 啟動 Gunicorn
# ------------------------------------------------------------
set -e

echo "▶ railway_start.sh 開始執行..."

# ---- 1. 確認 DATABASE_URL 存在 --------------------------------
if [ -z "$DATABASE_URL" ]; then
    echo "❌ 找不到 DATABASE_URL 環境變數，請在 Railway Variables 中設定！"
    exit 1
fi

# ---- 2. 安裝 psql（若容器內沒有）-----------------------------
if ! command -v psql > /dev/null 2>&1; then
    echo "⚙️  安裝 postgresql-client..."
    apk add --no-cache postgresql-client > /dev/null 2>&1
fi

# ---- 3. 修復 usersessions_usersession.id 的序列 ---------------
echo "🔧 檢查並修復 usersessions 序列..."

psql "$DATABASE_URL" <<'SQL'
DO $$
BEGIN
    -- 如果序列不存在，先建立
    IF NOT EXISTS (
        SELECT 1 FROM pg_class WHERE relkind = 'S' AND relname = 'usersessions_usersession_id_seq'
    ) THEN
        CREATE SEQUENCE usersessions_usersession_id_seq
            START WITH 1
            INCREMENT BY 1
            NO MINVALUE
            NO MAXVALUE
            CACHE 1;
        RAISE NOTICE 'Created sequence usersessions_usersession_id_seq';
    ELSE
        RAISE NOTICE 'Sequence already exists, skipping create';
    END IF;

    -- 確保 id 欄位的 DEFAULT 指向序列
    IF EXISTS (
        SELECT 1 FROM information_schema.tables
        WHERE table_name = 'usersessions_usersession'
    ) THEN
        ALTER TABLE usersessions_usersession
            ALTER COLUMN id SET NOT NULL,
            ALTER COLUMN id SET DEFAULT nextval('usersessions_usersession_id_seq'::regclass);
        RAISE NOTICE 'id DEFAULT set to nextval';
    ELSE
        RAISE NOTICE 'Table usersessions_usersession does not exist yet, skipping ALTER';
    END IF;
END $$;
SQL

echo "✅ 序列修復完成"

# ---- 4. 執行 Django migrations --------------------------------
echo "🚀 執行 Django migrations..."
cd /opt/recipes
python manage.py migrate --noinput

# ---- 5. 清除過期 Session（解決 SuspiciousSession 警告）--------
echo "🧹 清除過期的 Session..."
python manage.py clearsessions || true

# ---- 6. 啟動原本的 Tandoor 容器內建啟動流程 -------------------
# 官方映像的 entrypoint 是 /start.sh，讓它繼續接管後續流程
# (包含 collectstatic、啟動 nginx 與 gunicorn)
echo "🔌 移交給官方 /start.sh 啟動..."
exec /start.sh
