FROM python:3.10 AS python-base
FROM python-base AS builder-base

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=off \
    PIP_DISABLE_PIP_VERSION_CHECK=on \
    PIP_DEFAULT_TIMEOUT=100 \
    AIOHTTP_NO_EXTENSIONS=1 \
    PYSETUP_PATH="/opt/pysetup" \
    VENV_PATH="/opt/pysetup/.venv" \
    DOCKER=true \
    GIT_PYTHON_REFRESH=quiet

RUN apt-get update && apt-get upgrade -y

RUN apt-get install --no-install-recommends -y \
    build-essential \
    curl \
    gcc \
    git \
    openssl \
    openssh-server \
    python3 \
    python3-dev \
    python3-pip \
    sqlite3 \
    zip

RUN apt-get install --no-install-recommends -y \
    ffmpeg \
    libavcodec-dev \
    libavdevice-dev \
    libavformat-dev \
    libavutil-dev \
    libswscale-dev

RUN apt-get install --no-install-recommends -y \
    libcairo2 \
    libmagic1

RUN apt-get install --no-install-recommends -y wkhtmltopdf || true

RUN curl -sL https://deb.nodesource.com/setup_18.x -o nodesource_setup.sh && \
    bash nodesource_setup.sh && \
    apt-get install -y nodejs && \
    rm nodesource_setup.sh

RUN rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/*

WORKDIR /data
RUN mkdir -p /data/private /data/sessions /data/export

RUN git clone https://github.com/coddrago/Heroku /data/Heroku

WORKDIR /data/Heroku

RUN git fetch && git checkout master && git pull

RUN pip install --no-warn-script-location --no-cache-dir -U -r requirements.txt

# Создание entrypoint скрипта с поддержкой Secret Files
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "🔄 Heroku Session Manager with Secret Files Support"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
# Функция проверки сессии\n\
check_session() {\n\
    if [ -f "$1" ] && sqlite3 "$1" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then\n\
        return 0\n\
    fi\n\
    return 1\n\
}\n\
\n\
# Функция экспорта для Secret Files\n\
export_for_secret_files() {\n\
    echo "📤 Exporting sessions for Secret Files..."\n\
    rm -rf /data/export/*\n\
    mkdir -p /data/export/secret_files\n\
    \n\
    for session in /data/*.session; do\n\
        if [ -f "$session" ] && check_session "$session"; then\n\
            filename=$(basename "$session")\n\
            cp "$session" "/data/export/secret_files/$filename"\n\
            echo "   ✅ Exported: $filename"\n\
        fi\n\
    done\n\
    \n\
    if ls /data/export/secret_files/*.session 1> /dev/null 2>&1; then\n\
        cd /data/export\n\
        zip -r secret_files.zip secret_files/*.session > /dev/null 2>&1\n\
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
        echo "📦 Sessions ready for Secret Files upload!"\n\
        echo ""\n\
        echo "📋 TO SAVE YOUR SESSIONS AS SECRET FILES:"\n\
        echo ""\n\
        echo "1️⃣  Download the sessions archive:"\n\
        echo "    docker cp heroku-userbot:/data/export/secret_files.zip ./"\n\
        echo ""\n\
        echo "2️⃣  Extract the archive:"\n\
        echo "    unzip secret_files.zip"\n\
        echo ""\n\
        echo "3️⃣  Upload to your platform:"\n\
        echo "    • Railway: Settings → Variables → Secret Files → Add"\n\
        echo "    • Render: Environment → Secret Files → Add Secret File"\n\
        echo "    • Upload each .session file from secret_files/ folder"\n\
        echo ""\n\
        echo "4️⃣  Files will be available at:"\n\
        echo "    /etc/secrets/<filename>.session"\n\
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
    fi\n\
}\n\
\n\
# 1. Проверка и импорт из Secret Files\n\
if [ -d "/etc/secrets" ]; then\n\
    echo "🔍 Checking Secret Files (/etc/secrets/)..."\n\
    if ls /etc/secrets/*.session 1> /dev/null 2>&1; then\n\
        echo "📁 Found sessions in Secret Files:"\n\
        for session in /etc/secrets/*.session; do\n\
            filename=$(basename "$session")\n\
            if check_session "$session"; then\n\
                cp "$session" /data/\n\
                mkdir -p /data/sessions\n\
                cp "$session" /data/sessions/\n\
                echo "   ✅ Imported: $filename"\n\
            else\n\
                echo "   ❌ Corrupted: $filename"\n\
            fi\n\
        done\n\
    else\n\
        echo "   ℹ️ No session files found in Secret Files"\n\
    fi\n\
else\n\
    echo "⚠️ Secret Files not available (not running on Railway/Render?)"\n\
fi\n\
\n\
# 2. Восстановление сохраненных сессий\n\
if [ -d "/data/sessions" ] && ls /data/sessions/*.session 1> /dev/null 2>&1; then\n\
    echo "📂 Restoring saved sessions..."\n\
    for session in /data/sessions/*.session; do\n\
        filename=$(basename "$session")\n\
        if [ ! -f "/data/$filename" ] && check_session "$session"; then\n\
            cp "$session" /data/\n\
            echo "   ✅ Restored: $filename"\n\
        fi\n\
    done\n\
fi\n\
\n\
# 3. Функция сохранения\n\
save_sessions() {\n\
    echo "💾 Saving sessions..."\n\
    mkdir -p /data/sessions\n\
    session_saved=false\n\
    for session in /data/*.session; do\n\
        if [ -f "$session" ] && check_session "$session"; then\n\
            cp "$session" /data/sessions/\n\
            echo "   ✅ Saved: $(basename $session)"\n\
            session_saved=true\n\
        fi\n\
    done\n\
    \n\
    # Автоматический экспорт для Secret Files при сохранении\n\
    if [ "$session_saved" = true ]; then\n\
        export_for_secret_files\n\
    fi\n\
}\n\
\n\
# 4. Создание helper скрипта\n\
cat > /data/export_sessions.sh << "HELPER"\n\
#!/bin/bash\n\
echo "🚀 Session Export Helper"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
if ! ls /data/*.session 1> /dev/null 2>&1; then\n\
    echo "❌ No sessions found to export!"\n\
    exit 1\n\
fi\n\
\n\
rm -rf /data/export/*\n\
mkdir -p /data/export/secret_files\n\
\n\
for session in /data/*.session; do\n\
    if [ -f "$session" ]; then\n\
        cp "$session" /data/export/secret_files/\n\
        echo "✅ Exported: $(basename $session)"\n\
    fi\n\
done\n\
\n\
cd /data/export\n\
zip -r secret_files.zip secret_files/*.session > /dev/null 2>&1\n\
\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
echo "✅ Export complete!"\n\
echo ""\n\
echo "📥 Download with:"\n\
echo "   docker cp heroku-userbot:/data/export/secret_files.zip ./"\n\
echo ""\n\
echo "Or get individual files from:"\n\
echo "   /data/export/secret_files/"\n\
HELPER\n\
chmod +x /data/export_sessions.sh\n\
\n\
# 5. Обработчик завершения\n\
cleanup() {\n\
    echo "\n🛑 Shutting down..."\n\
    save_sessions\n\
    exit 0\n\
}\n\
\n\
trap cleanup SIGTERM SIGINT EXIT\n\
\n\
# 6. Автосохранение\n\
(\n\
    while true; do\n\
        sleep 600\n\
        save_sessions > /dev/null 2>&1\n\
    done\n\
) &\n\
\n\
# 7. Проверка статуса\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
if ls /data/*.session 1> /dev/null 2>&1; then\n\
    echo "✅ Active sessions:"\n\
    for session in /data/*.session; do\n\
        size=$(du -h "$session" | cut -f1)\n\
        echo "   • $(basename $session) ($size)"\n\
    done\n\
    echo ""\n\
    echo "💡 TIP: To export sessions for Secret Files, run:"\n\
    echo "   docker exec heroku-userbot /data/export_sessions.sh"\n\
else\n\
    echo "⚠️ No sessions found - first time setup required"\n\
    echo ""\n\
    echo "After creating a session, it will be automatically:"\n\
    echo "  • Saved to persistent storage"\n\
    echo "  • Exported for Secret Files upload"\n\
fi\n\
\n\
if [ -n "$MONGO_URI" ]; then\n\
    echo "🗄️ MongoDB connection configured"\n\
fi\n\
\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
echo "🚀 Starting Heroku userbot..."\n\
\n\
# Запуск основного процесса\n\
exec "$@"' > /entrypoint.sh && chmod +x /entrypoint.sh

# Создание веб-интерфейса для скачивания сессий
RUN echo '#!/usr/bin/env python3\n\
import http.server\n\
import socketserver\n\
import os\n\
import json\n\
from pathlib import Path\n\
\n\
PORT = 8081\n\
\n\
class SessionHandler(http.server.SimpleHTTPRequestHandler):\n\
    def do_GET(self):\n\
        if self.path == "/sessions":\n\
            sessions = []\n\
            export_dir = Path("/data/export/secret_files")\n\
            if export_dir.exists():\n\
                for session in export_dir.glob("*.session"):\n\
                    sessions.append({\n\
                        "name": session.name,\n\
                        "size": session.stat().st_size\n\
                    })\n\
            \n\
            self.send_response(200)\n\
            self.send_header("Content-type", "application/json")\n\
            self.end_headers()\n\
            self.wfile.write(json.dumps(sessions).encode())\n\
        elif self.path == "/export":\n\
            os.system("/data/export_sessions.sh")\n\
            self.send_response(200)\n\
            self.end_headers()\n\
            self.wfile.write(b"Export complete!")\n\
        else:\n\
            super().do_GET()\n\
\n\
os.chdir("/data/export")\n\
with socketserver.TCPServer(("", PORT), SessionHandler) as httpd:\n\
    print(f"Session export server at port {PORT}")\n\
    httpd.serve_forever()' > /data/session_server.py && chmod +x /data/session_server.py

# Volume для постоянного хранения
VOLUME ["/data/sessions", "/data/export"]

EXPOSE 8080 8081

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "heroku", "--root"]
