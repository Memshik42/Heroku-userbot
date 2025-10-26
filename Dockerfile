FROM python:3.11-slim as builder

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        gcc \
        g++ \
        && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 --single-branch --branch master \
    https://github.com/coddrago/Heroku /build/Heroku

WORKDIR /build/Heroku

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install --no-cache-dir -U pip setuptools wheel && \
    pip install --no-cache-dir -r requirements.txt

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONOPTIMIZE=2 \
    PYTHONMALLOC=malloc \
    MALLOC_TRIM_THRESHOLD_=100000 \
    MALLOC_MMAP_THRESHOLD_=100000 \
    PATH="/opt/venv/bin:$PATH" \
    DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    UPDATES_DISABLED=false

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        libmagic1 \
        ca-certificates \
        git \
        && rm -rf /var/lib/apt/lists/* \
        /var/cache/apt/archives/* \
        /tmp/* \
        /var/tmp/*

WORKDIR /data/Heroku

COPY --from=builder /opt/venv /opt/venv

COPY --from=builder /build/Heroku /data/Heroku

RUN find /opt/venv -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
    find /opt/venv -type f -name '*.pyc' -delete && \
    find /opt/venv -type f -name '*.pyo' -delete && \
    find /data/Heroku -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
    find /data/Heroku -type f -name '*.pyc' -delete

RUN mkdir -p /data/private

RUN git config --global user.email "bot@koyeb.com" && \
    git config --global user.name "Koyeb Bot" && \
    git config --global pull.rebase false && \
    git config --global --add safe.directory /data/Heroku && \
    cd /data/Heroku && \
    git remote set-url origin https://github.com/coddrago/Heroku.git && \
    git fetch --unshallow 2>/dev/null || true

RUN chmod -R 755 /data/Heroku && \
    chown -R root:root /data/Heroku

EXPOSE 8080

CMD ["python", "-u", "-m", "heroku", "--root"]
