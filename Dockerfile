FROM python:3.10-slim AS builder

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_DEFAULT_TIMEOUT=100 \
    AIOHTTP_NO_EXTENSIONS=1

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    gcc \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /tmp
RUN git clone --depth=1 --branch=master https://github.com/coddrago/Heroku /tmp/heroku && \
    cd /tmp/heroku && \
    pip install --upgrade pip setuptools wheel && \
    pip install -r requirements.txt

FROM python:3.10-slim

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DOCKER=true \
    GIT_PYTHON_REFRESH=quiet \
    PATH="/opt/venv/bin:$PATH"

RUN apt-get update && apt-get install -y --no-install-recommends \
    ffmpeg \
    libcairo2 \
    libmagic1 \
    git \
    curl \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && \
    (apt-get install -y --no-install-recommends wkhtmltopdf || echo "wkhtmltopdf not available, skipping...") && \
    rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN groupadd -r heroku && useradd -r -g heroku -m -d /home/heroku heroku

COPY --from=builder /opt/venv /opt/venv

WORKDIR /data
RUN mkdir -p /data/private /data/Heroku && \
    chown -R heroku:heroku /data

COPY --from=builder --chown=heroku:heroku /tmp/heroku /data/Heroku

USER heroku
WORKDIR /data/Heroku

HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import sys; sys.exit(0)" || exit 1

EXPOSE 8080
CMD ["python", "-m", "heroku", "--root"]
