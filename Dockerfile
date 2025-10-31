FROM python:3.11-slim as builder

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /build

RUN apt-get update && \
    apt-get install -y --no-install-recommends git && \
    rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 --single-branch --branch master \
    https://github.com/coddrago/Heroku /build/Heroku

WORKDIR /build/Heroku

RUN python -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

RUN pip install -U pip setuptools wheel && \
    pip install -r requirements.txt

FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    DOCKER=true

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ffmpeg \
        libmagic1 \
        git \
        && rm -rf /var/lib/apt/lists/*

WORKDIR /data/Heroku

COPY --from=builder /opt/venv /opt/venv
COPY --from=builder /build/Heroku /data/Heroku

RUN find . -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
    find . -type f -name '*.pyc' -delete && \
    mkdir -p /data/private

RUN git config --global user.name "Bot" && \
    git config --global pull.rebase false && \
    git config --global --add safe.directory /data/Heroku

EXPOSE 8080

CMD ["python", "-m", "heroku", "--root"]
