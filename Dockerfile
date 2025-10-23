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

# Создание entrypoint скрипта для сохранения и восстановления сессий
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "🔄 Heroku Session Manager"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
# Функция проверки валидности сессии\n\
check_session() {\n\
    if [ -f "$1" ]; then\n\
        if sqlite3 "$1" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then\n\
            return 0\n\
        fi\n\
    fi\n\
    return 1\n\
}\n\
\n\
# Функция сохранения сессий\n\
save_sessions() {\n\
    echo "💾 Saving sessions..."\n\
    mkdir -p /data/sessions /data/export/secret_files\n\
    saved_count=0\n\
    \n\
    for session in /data/*.session; do\n\
        if [ -f "$session" ] && check_session "$session"; then\n\
            filename=$(basename "$session")\n\
            # Сохранение в persistent storage\n\
            cp "$session" /data/sessions/\n\
            # Подготовка для Secret Files\n\
            cp "$session" /data/export/secret_files/\n\
            echo "   ✅ Saved: $filename"\n\
            ((saved_count++))\n\
        fi\n\
    done\n\
    \n\
    if [ $saved_count -gt 0 ]; then\n\
        # Создание архива для удобства\n\
        cd /data/export\n\
        zip -q -r sessions_backup.zip secret_files/*.session 2>/dev/null || true\n\
        echo "   📦 Archive created: sessions_backup.zip"\n\
        echo "   📥 Download: docker cp $(hostname):/data/export/sessions_backup.zip ./"\n\
    fi\n\
    \n\
    return 0\n\
}\n\
\n\
# Функция экспорта для Secret Files\n\
export_for_secret_files() {\n\
    echo "📤 Preparing sessions for Secret Files upload..."\n\
    mkdir -p /data/export/secret_files\n\
    \n\
    for session in /data/*.session; do\n\
        if [ -f "$session" ] && check_session "$session"; then\n\
            cp "$session" /data/export/secret_files/\n\
        fi\n\
    done\n\
    \n\
    if ls /data/export/secret_files/*.session 1> /dev/null 2>&1; then\n\
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
        echo "📋 TO SAVE SESSIONS IN SECRET FILES:"\n\
        echo ""\n\
        echo "1. Download sessions:"\n\
        echo "   docker cp $(hostname):/data/export/secret_files/ ./"\n\
        echo ""\n\
        echo "2. Upload to your platform:"\n\
        echo "   • Railway: Settings → Variables → Secret Files"\n\
        echo "   • Render: Environment → Secret Files"\n\
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
    fi\n\
}\n\
\n\
# 1. Импорт из Secret Files (Railway/Render)\n\
if [ -d "/etc/secrets" ]; then\n\
    echo "🔍 Checking Secret Files..."\n\
    if ls /etc/secrets/*.session 1> /dev/null 2>&1; then\n\
        echo "📁 Found sessions in Secret Files:"\n\
        for session in /etc/secrets/*.session; do\n\
            filename=$(basename "$session")\n\
            if check_session "$session"; then\n\
                cp "$session" /data/\n\
                echo "   ✅ Imported: $filename"\n\
                # Сохранение копии\n\
                mkdir -p /data/sessions\n\
                cp "$session" /data/sessions/\n\
            else\n\
                echo "   ⚠️ Skipped corrupted: $filename"\n\
            fi\n\
        done\n\
    else\n\
        echo "   ℹ️ No sessions in Secret Files"\n\
    fi\n\
fi\n\
\n\
# 2. Восстановление из persistent storage\n\
if [ -d "/data/sessions" ] && ls /data/sessions/*.session 1> /dev/null 2>&1; then\n\
    echo "📂 Restoring saved sessions..."\n\
    for session in /data/sessions/*.session; do\n\
        filename=$(basename "$session")\n\
        if [ ! -f "/data/$filename" ]; then\n\
            if check_session "$session"; then\n\
                cp "$session" /data/\n\
                echo "   ✅ Restored: $filename"\n\
            fi\n\
        fi\n\
    done\n\
fi\n\
\n\
# 3. Обработчик завершения работы\n\
cleanup() {\n\
    echo "\n🛑 Shutting down..."\n\
    save_sessions\n\
    exit 0\n\
}\n\
\n\
trap cleanup SIGTERM SIGINT EXIT\n\
\n\
# 4. Периодическое автосохранение (каждые 5 минут)\n\
(\n\
    while true; do\n\
        sleep 300\n\
        echo "⏰ Auto-saving sessions..."\n\
        save_sessions > /dev/null 2>&1\n\
    done\n\
) &\n\
AUTOSAVE_PID=$!\n\
\n\
# 5. Мониторинг новых сессий\n\
(\n\
    last_count=0\n\
    while true; do\n\
        sleep 30\n\
        current_count=$(ls -1 /data/*.session 2>/dev/null | wc -l)\n\
        if [ "$current_count" -gt "$last_count" ]; then\n\
            echo "🆕 New session detected!"\n\
            save_sessions\n\
            export_for_secret_files\n\
            last_count=$current_count\n\
        fi\n\
    done\n\
) &\n\
MONITOR_PID=$!\n\
\n\
# 6. Проверка текущего состояния\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
session_count=$(ls -1 /data/*.session 2>/dev/null | wc -l)\n\
\n\
if [ "$session_count" -gt 0 ]; then\n\
    echo "✅ Found $session_count session(s):"\n\
    for session in /data/*.session; do\n\
        if [ -f "$session" ]; then\n\
            size=$(du -h "$session" | cut -f1)\n\
            echo "   • $(basename $session) ($size)"\n\
        fi\n\
    done\n\
    echo ""\n\
    echo "💡 Sessions will be auto-saved every 5 minutes"\n\
    echo "💡 New sessions will be detected automatically"\n\
else\n\
    echo "⚠️ No sessions found"\n\
    echo ""\n\
    echo "📝 To create a session:"\n\
    echo "   1. Open Heroku web interface (port 8080)"\n\
    echo "   2. Complete the authorization process"\n\
    echo "   3. Session will be automatically saved"\n\
fi\n\
\n\
if [ -n "$MONGO_URI" ]; then\n\
    echo "🗄️ MongoDB connection configured"\n\
fi\n\
\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
echo "🚀 Starting Heroku userbot..."\n\
echo "🌐 Web interface will be available at port 8080"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
# Запуск основного процесса Heroku\n\
exec "$@"' > /entrypoint.sh && chmod +x /entrypoint.sh

# Создание helper скрипта для ручного экспорта
RUN echo '#!/bin/bash\n\
echo "📤 Manual Session Export"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
mkdir -p /data/export/secret_files\n\
count=0\n\
\n\
for session in /data/*.session; do\n\
    if [ -f "$session" ]; then\n\
        cp "$session" /data/export/secret_files/\n\
        echo "✅ Exported: $(basename $session)"\n\
        ((count++))\n\
    fi\n\
done\n\
\n\
if [ $count -gt 0 ]; then\n\
    cd /data/export\n\
    zip -r sessions_backup.zip secret_files/*.session\n\
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
    echo "✅ Exported $count session(s)"\n\
    echo ""\n\
    echo "📥 Download command:"\n\
    echo "   docker cp $(hostname):/data/export/sessions_backup.zip ./"\n\
else\n\
    echo "❌ No sessions found to export"\n\
fi' > /data/export_sessions.sh && chmod +x /data/export_sessions.sh

# Volume для постоянного хранения сессий
VOLUME ["/data/sessions", "/data/export"]

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "heroku", "--root"]
