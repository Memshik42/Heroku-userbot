FROM python:3.10-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONOPTIMIZE=2 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100 \
    AIOHTTP_NO_EXTENSIONS=1 \
    MALLOC_TRIM_THRESHOLD_=100000 \
    MALLOC_MMAP_THRESHOLD_=100000 \
    DOCKER=true \
    GIT_PYTHON_REFRESH=quiet

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        ffmpeg \
        libmagic1 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

WORKDIR /data

RUN git clone --depth=1 --single-branch --branch master \
    https://github.com/coddrago/Heroku /data/Heroku

WORKDIR /data/Heroku

RUN pip install --no-cache-dir --compile -U pip setuptools wheel && \
    pip install --no-cache-dir --compile -U -r requirements.txt && \
    find /usr/local/lib/python3.10 -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/python3.10 -type f -name '*.pyc' -delete && \
    find /usr/local/lib/python3.10 -type f -name '*.pyo' -delete && \
    rm -rf ~/.cache/pip /tmp/* /var/tmp/* /root/.cache

RUN mkdir -p /data/private

EXPOSE 8080

CMD ["python", "-u", "-m", "heroku", "--root"]
