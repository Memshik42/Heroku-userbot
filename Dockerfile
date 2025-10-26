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

RUN git clone --depth=1 --single-branch --branch master \
    https://github.com/coddrago/Heroku .

RUN pip install --no-cache-dir -U pip && \
    pip install --no-cache-dir -r requirements.txt

RUN mkdir -p /data/private

EXPOSE 8080

CMD ["python", "-m", "heroku", "--root"]
