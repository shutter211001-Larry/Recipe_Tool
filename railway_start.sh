#!/usr/bin/env bash
# ------------------------------------------------------------
# railway_start.sh
#   - Runs before the actual Gunicorn server.
#   - Fixes the missing/invalid sequence for usersessions_usersession.id
#   - Executes all Django migrations
#   - Starts the Gunicorn (or custom) process
# ------------------------------------------------------------

# ---- 1. 環境變數 ------------------------------------------------
# Railway 會自動把 DATABASE_URL 注入環境變數，以下是常見的變數名稱
#   DATABASE_URL     → 完整的 PostgreSQL 連線字串
#   TANDOOR_PORT     → 讓內部 Nginx (若有) 監聽的埠號，預設 8080
#   PORT (Railway)   → Railway 需要的外部埠號（與 TANDOOR_PORT 同步）

export DATABASE_URL=${DATABASE_URL}
export TANDOOR_PORT=${TANDOOR_PORT:-8080}
export PORT=${PORT:-8080}

# ---- 2. 取得 Postgres 連線資訊 -------------------------------
if ! command -v python3 >/dev/null; then
    echo "❌ Python3 not found – aborting."
    exit 1
fi

read -r DB_USER DB_PASS DB_HOST DB_PORT DB_NAME <<<$(python3 - <<'PY'
import os, urllib.parse, sys
url = os.getenv("DATABASE_URL")
if not url:
    sys.exit(1)
 p = urllib.parse.urlparse(url)
user = urllib.parse.unquote(p.username)
pw   = urllib.parse.unquote(p.password)
host = p.hostname
port = p.port
dbname = p.path.lstrip('/')
print(user, pw, host, port, dbname)
PY
)

if [ -z "$DB_USER" ]; then
    echo "❌ 無法解析 DATABASE_URL – aborting."
    exit 1
fi

# ---- 3. 檢查並修復 usersessions_userssession.id 序列 -------------
if ! command -v psql >/dev/null; then
    echo "⚙️  安裝 postgresql client ..."
    if command -v apk >/dev/null; then
        apk add --no-cache postgresql-client > /dev/null 2>&1
    else
        apt-get update -y && apt-get install -y postgresql-client
    fi
fi

SEQ_EXISTS=$(psql "$DATABASE_URL" -tAc "SELECT EXISTS (SELECT 1 FROM pg_class WHERE relkind = 'S' AND relname = 'usersessions_usersession_id_seq');" 2>/dev/null)

if [ "$SEQ_EXISTS" != "t" ]; then
    echo "🔧 建立缺失的序列 usersessions_userssession_id_seq ..."
    psql "$DATABASE_URL" <<SQL
CREATE SEQUENCE usersessions_userssession_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
SQL
fi

# 確保 id 欄位有正確的 DEFAULT nextval(...)
echo "🔧 為 usersessions_userssession.id 設定 default ..."
psql "$DATABASE_URL" <<SQL
ALTER TABLE usersessions_usersession
    ALTER COLUMN id SET NOT NULL,
    ALTER COLUMN id SET DEFAULT nextval('usersessions_usersession_id_seq'::regclass);
SQL

# 若表的型別是 bigint（BigAutoField）而序列是 integer，改成 bigint 序列
CURRENT_TYPE=$(psql "$DATABASE_URL" -tAc "SELECT data_type FROM information_schema.columns WHERE table_name='usersessions_userssession' AND column_name='id';")
if [[ "$CURRENT_TYPE" == "bigint" ]]; then
    echo "🔧 將序列升級為 bigint ..."
    psql "$DATABASE_URL" <<SQL
ALTER SEQUENCE usersessions_userssession_id_seq AS BIGINT;
SQL
fi

# ------------------------------------------------------------
# 4. 讓 Django 知道使用哪個 DEFAULT_AUTO_FIELD（避免 AutoField/BigAutoField 不一致）
export DEFAULT_AUTO_FIELD=${DEFAULT_AUTO_FIELD:-django.db.models.AutoField}

# ------------------------------------------------------------
# 5. 執行 Django migrations
echo "🚀 執行 Django migrations ..."
python3 manage.py migrate --noinput

# ------------------------------------------------------------
# 6. (可選) 清除所有舊的 Session，避免 SuspiciousSession 警告
echo "🧹 清除過期的 Session ..."
python3 manage.py clearsessions

# ------------------------------------------------------------
# 7. 啟動 Gunicorn（或你原本的啟動指令）
# 下面假設你是使用官方的 gunicorn entrypoint：
# gunicorn recipes.wsgi:application --bind 0.0.0.0:${PORT}
# 若你在 docker‑compose 中使用了其他指令，請自行調整。

echo "🔌 啟動 Gunicorn (Port $PORT) ..."
exec gunicorn recipes.wsgi:application \
    --bind 0.0.0.0:${PORT} \
    --workers 3 \
    --timeout 120 \
    --log-level info
