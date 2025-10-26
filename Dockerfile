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
    GIT_PYTHON_REFRESH=quiet

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        libmagic1 \
        ca-certificates \
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

HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
    CMD python -c "import sys; sys.exit(0)" || exit 1

EXPOSE 8080

CMD ["python", "-u", "-m", "heroku", "--root"]
