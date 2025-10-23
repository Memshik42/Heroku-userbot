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
    python3-pip

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
RUN mkdir /data/private

RUN git clone https://github.com/coddrago/Heroku /data/Heroku

WORKDIR /data/Heroku

RUN git fetch && git checkout master && git pull

RUN pip install --no-warn-script-location --no-cache-dir -U -r requirements.txt

# Создание entrypoint скрипта для копирования сессий
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "🔍 Checking for session files..."\n\
\n\
if [ -d "/etc/secrets" ] && ls /etc/secrets/*.session 1> /dev/null 2>&1; then\n\
    echo "📁 Found sessions in Secret Files"\n\
    for session in /etc/secrets/*.session; do\n\
        filename=$(basename "$session")\n\
        echo "Copying $filename..."\n\
        cp "$session" /data/\n\
        \n\
        # Проверка целостности\n\
        if sqlite3 "/data/$filename" "PRAGMA integrity_check;" | grep -q "ok"; then\n\
            echo "✅ Session $filename is valid"\n\
        else\n\
            echo "❌ Session $filename is corrupted, removing..."\n\
            rm "/data/$filename"\n\
        fi\n\
    done\n\
else\n\
    echo "ℹ️ No sessions in Secret Files"\n\
fi\n\
\n\
if [ -n "$MONGO_URI" ]; then\n\
    echo "🗄️ MONGO_URI detected"\n\
fi\n\
\n\
if ls /data/heroku-*.session 1> /dev/null 2>&1 || ls /data/hikka-*.session 1> /dev/null 2>&1; then\n\
    echo "✅ Valid session files found"\n\
else\n\
    echo "⚠️ No valid sessions - first time setup required"\n\
fi\n\
\n\
echo "🚀 Starting Heroku userbot..."\n\
exec "$@"' > /entrypoint.sh && chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "heroku", "--root"]
