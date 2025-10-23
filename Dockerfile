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
    sqlite3

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

# Создание entrypoint скрипта для копирования сессий и загрузки в Render Secret Files
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "heroku", "--root"]
