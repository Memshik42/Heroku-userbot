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
    zip \
    inotify-tools

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
RUN mkdir -p /data/private /data/sessions /data/export/secret_files

RUN git clone https://github.com/coddrago/Heroku /data/Heroku

WORKDIR /data/Heroku

RUN git fetch && git checkout master && git pull

RUN pip install --no-warn-script-location --no-cache-dir -U -r requirements.txt

# Основной entrypoint скрипт
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "🔄 Heroku Auto Session Manager"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
# Функция проверки сессии\n\
check_session() {\n\
    if [ -f "$1" ]; then\n\
        if sqlite3 "$1" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then\n\
            return 0\n\
        fi\n\
    fi\n\
    return 1\n\
}\n\
\n\
# Функция сохранения одной сессии\n\
save_single_session() {\n\
    local session_file="$1"\n\
    local filename=$(basename "$session_file")\n\
    \n\
    if check_session "$session_file"; then\n\
        # Копирование в persistent storage\n\
        cp "$session_file" /data/sessions/\n\
        # Копирование для Secret Files export\n\
        cp "$session_file" /data/export/secret_files/\n\
        # Создание timestamp файла\n\
        date "+%Y-%m-%d %H:%M:%S" > "/data/sessions/${filename}.timestamp"\n\
        echo "✅ Saved: $filename"\n\
        return 0\n\
    else\n\
        echo "❌ Invalid session: $filename"\n\
        return 1\n\
    fi\n\
}\n\
\n\
# Функция сохранения всех сессий\n\
save_all_sessions() {\n\
    echo "💾 Saving all sessions..."\n\
    local saved=0\n\
    \n\
    for session in /data/*.session; do\n\
        if [ -f "$session" ]; then\n\
            if save_single_session "$session"; then\n\
                ((saved++))\n\
            fi\n\
        fi\n\
    done\n\
    \n\
    if [ $saved -gt 0 ]; then\n\
        # Создание архива\n\
        cd /data/export\n\
        rm -f sessions_backup.zip\n\
        zip -q -r sessions_backup.zip secret_files/*.session 2>/dev/null || true\n\
        echo "📦 Saved $saved session(s) to archive"\n\
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
        echo "📥 Download command:"\n\
        echo "   docker cp heroku-userbot:/data/export/sessions_backup.zip ./"\n\
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
    fi\n\
}\n\
\n\
# Функция загрузки сохраненных сессий\n\
load_saved_sessions() {\n\
    local loaded=0\n\
    \n\
    # 1. Проверка Secret Files (приоритет)\n\
    if [ -d "/etc/secrets" ] && ls /etc/secrets/*.session 1> /dev/null 2>&1; then\n\
        echo "📁 Loading from Secret Files (/etc/secrets)..."\n\
        for session in /etc/secrets/*.session; do\n\
            filename=$(basename "$session")\n\
            if check_session "$session"; then\n\
                cp "$session" /data/\n\
                cp "$session" /data/sessions/  # Сохраняем копию\n\
                echo "   ✅ Loaded: $filename"\n\
                ((loaded++))\n\
            else\n\
                echo "   ⚠️ Corrupted: $filename"\n\
            fi\n\
        done\n\
    fi\n\
    \n\
    # 2. Проверка persistent storage\n\
    if [ -d "/data/sessions" ] && ls /data/sessions/*.session 1> /dev/null 2>&1; then\n\
        echo "📂 Loading from persistent storage..."\n\
        for session in /data/sessions/*.session; do\n\
            filename=$(basename "$session")\n\
            \n\
            # Пропускаем если уже загружена\n\
            if [ -f "/data/$filename" ]; then\n\
                echo "   ℹ️ Already exists: $filename"\n\
                continue\n\
            fi\n\
            \n\
            if check_session "$session"; then\n\
                cp "$session" /data/\n\
                echo "   ✅ Restored: $filename"\n\
                ((loaded++))\n\
            else\n\
                echo "   ⚠️ Corrupted: $filename"\n\
            fi\n\
        done\n\
    fi\n\
    \n\
    return $loaded\n\
}\n\
\n\
# Функция мониторинга новых сессий в реальном времени\n\
watch_sessions() {\n\
    echo "👁️ Starting session file monitor..."\n\
    \n\
    # Используем inotifywait для отслеживания изменений\n\
    inotifywait -m -e create -e modify -e moved_to --format "%f" /data 2>/dev/null | \\\n\
    while read filename; do\n\
        if [[ "$filename" == *.session ]]; then\n\
            sleep 2  # Ждем завершения записи\n\
            \n\
            session_path="/data/$filename"\n\
            if [ -f "$session_path" ]; then\n\
                echo "🆕 Detected new/updated session: $filename"\n\
                \n\
                if save_single_session "$session_path"; then\n\
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
                    echo "✅ SESSION SAVED SUCCESSFULLY!"\n\
                    echo ""\n\
                    echo "📥 Download for Secret Files:"\n\
                    echo "   docker cp heroku-userbot:/data/export/secret_files/$filename ./"\n\
                    echo ""\n\
                    echo "📤 Upload to platform:"\n\
                    echo "   • Railway: Settings → Variables → Secret Files"\n\
                    echo "   • Render: Environment → Secret Files"\n\
                    echo "   • Upload file: $filename"\n\
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
                fi\n\
            fi\n\
        fi\n\
    done\n\
}\n\
\n\
# 1. Загрузка сохраненных сессий\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
load_saved_sessions\n\
loaded_count=$?\n\
\n\
# 2. Проверка текущего состояния\n\
session_count=$(ls -1 /data/*.session 2>/dev/null | wc -l)\n\
\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
if [ "$session_count" -gt 0 ]; then\n\
    echo "✅ Active sessions: $session_count"\n\
    echo ""\n\
    for session in /data/*.session; do\n\
        if [ -f "$session" ]; then\n\
            filename=$(basename "$session")\n\
            size=$(du -h "$session" | cut -f1)\n\
            timestamp_file="/data/sessions/${filename}.timestamp"\n\
            \n\
            echo -n "   • $filename ($size)"\n\
            \n\
            if [ -f "$timestamp_file" ]; then\n\
                timestamp=$(cat "$timestamp_file")\n\
                echo " - saved: $timestamp"\n\
            else\n\
                echo ""\n\
            fi\n\
        fi\n\
    done\n\
    echo ""\n\
    echo "💡 Sessions are auto-saved every 5 minutes"\n\
    echo "💡 New sessions are detected instantly"\n\
else\n\
    echo "⚠️ No sessions found"\n\
    echo ""\n\
    echo "📝 To create a session:"\n\
    echo "   1. Open http://localhost:8080 in browser"\n\
    echo "   2. Complete Heroku authorization"\n\
    echo "   3. Session will be auto-saved"\n\
fi\n\
\n\
if [ -n "$MONGO_URI" ]; then\n\
    echo "🗄️ MongoDB: Connected"\n\
fi\n\
\n\
# 3. Запуск мониторинга новых сессий в фоне\n\
watch_sessions &\n\
WATCH_PID=$!\n\
\n\
# 4. Периодическое автосохранение\n\
(\n\
    while true; do\n\
        sleep 300  # 5 минут\n\
        echo "⏰ Auto-saving sessions..."\n\
        save_all_sessions > /dev/null 2>&1\n\
    done\n\
) &\n\
AUTOSAVE_PID=$!\n\
\n\
# 5. Обработчик завершения\n\
cleanup() {\n\
    echo "\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
    echo "🛑 Shutting down gracefully..."\n\
    \n\
    # Останавливаем фоновые процессы\n\
    kill $WATCH_PID 2>/dev/null || true\n\
    kill $AUTOSAVE_PID 2>/dev/null || true\n\
    \n\
    # Финальное сохранение\n\
    save_all_sessions\n\
    \n\
    echo "✅ All sessions saved"\n\
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
    exit 0\n\
}\n\
\n\
trap cleanup SIGTERM SIGINT EXIT\n\
\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
echo "🚀 Starting Heroku userbot..."\n\
echo "🌐 Web interface: http://localhost:8080"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
# Запуск Heroku\n\
exec "$@"' > /entrypoint.sh && chmod +x /entrypoint.sh

# Скрипт для ручного экспорта
RUN echo '#!/bin/bash\n\
echo "📤 Session Export Utility"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
if ! ls /data/*.session 1> /dev/null 2>&1; then\n\
    echo "❌ No sessions found!"\n\
    exit 1\n\
fi\n\
\n\
mkdir -p /data/export/secret_files\n\
count=0\n\
\n\
for session in /data/*.session; do\n\
    filename=$(basename "$session")\n\
    cp "$session" /data/export/secret_files/\n\
    echo "✅ Exported: $filename"\n\
    ((count++))\n\
done\n\
\n\
cd /data/export\n\
zip -r sessions_backup.zip secret_files/*.session\n\
\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
echo "✅ Exported $count session(s)"\n\
echo ""\n\
echo "📥 Download archive:"\n\
echo "   docker cp heroku-userbot:/data/export/sessions_backup.zip ./"\n\
echo ""\n\
echo "📥 Download individual sessions:"\n\
for session in /data/export/secret_files/*.session; do\n\
    filename=$(basename "$session")\n\
    echo "   docker cp heroku-userbot:/data/export/secret_files/$filename ./"\n\
done\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"' > /data/export_sessions.sh && chmod +x /data/export_sessions.sh

# Скрипт для просмотра статуса
RUN echo '#!/bin/bash\n\
echo "📊 Session Status"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
echo "📂 Active sessions in /data:"\n\
if ls /data/*.session 1> /dev/null 2>&1; then\n\
    for session in /data/*.session; do\n\
        filename=$(basename "$session")\n\
        size=$(du -h "$session" | cut -f1)\n\
        modified=$(stat -c "%y" "$session" | cut -d. -f1)\n\
        echo "   ✅ $filename ($size) - modified: $modified"\n\
    done\n\
else\n\
    echo "   ❌ No active sessions"\n\
fi\n\
\n\
echo ""\n\
echo "💾 Saved sessions in /data/sessions:"\n\
if ls /data/sessions/*.session 1> /dev/null 2>&1; then\n\
    for session in /data/sessions/*.session; do\n\
        filename=$(basename "$session")\n\
        size=$(du -h "$session" | cut -f1)\n\
        timestamp_file="${session}.timestamp"\n\
        if [ -f "$timestamp_file" ]; then\n\
            timestamp=$(cat "$timestamp_file")\n\
            echo "   ✅ $filename ($size) - saved: $timestamp"\n\
        else\n\
            echo "   ✅ $filename ($size)"\n\
        fi\n\
    done\n\
else\n\
    echo "   ❌ No saved sessions"\n\
fi\n\
\n\
echo ""\n\
echo "📤 Exported sessions in /data/export/secret_files:"\n\
if ls /data/export/secret_files/*.session 1> /dev/null 2>&1; then\n\
    for session in /data/export/secret_files/*.session; do\n\
        filename=$(basename "$session")\n\
        size=$(du -h "$session" | cut -f1)\n\
        echo "   ✅ $filename ($size)"\n\
    done\n\
else\n\
    echo "   ❌ No exported sessions"\n\
fi\n\
\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"' > /data/session_status.sh && chmod +x /data/session_status.sh

# Volume для постоянного хранения
VOLUME ["/data/sessions", "/data/export"]

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "heroku", "--root"]
