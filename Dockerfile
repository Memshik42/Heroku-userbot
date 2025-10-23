# Используем slim образ для экономии ~300MB
FROM python:3.10-slim

# Оптимизированные переменные окружения
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

# Установка только критически важных пакетов в один слой
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        git \
        ffmpeg \
        libmagic1 \
        ca-certificates \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

# Создание рабочей директории
WORKDIR /data

# Клонирование репозитория (shallow clone для экономии места)
RUN git clone --depth=1 --single-branch --branch master \
    https://github.com/coddrago/Heroku /data/Heroku

WORKDIR /data/Heroku

# Оптимизированная установка Python зависимостей
RUN pip install --no-cache-dir --compile -U pip setuptools wheel && \
    pip install --no-cache-dir --compile -U -r requirements.txt && \
    # Удаление скомпилированных файлов и кэша
    find /usr/local/lib/python3.10 -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true && \
    find /usr/local/lib/python3.10 -type f -name '*.pyc' -delete && \
    find /usr/local/lib/python3.10 -type f -name '*.pyo' -delete && \
    # Очистка всех временных файлов
    rm -rf ~/.cache/pip /tmp/* /var/tmp/* /root/.cache

# Создание директории для данных
RUN mkdir -p /data/private

EXPOSE 8080

# Запуск с явным флагом unbuffered
CMD ["python", "-u", "-m", "heroku", "--root"]
