FROM python:3.12-slim-bookworm

# Установка системных зависимостей для компиляции
RUN apt-get update && apt-get install -y \
    gcc \
    g++ \
    make \
    git \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Копирование файлов проекта
COPY . /app

# Установка Python зависимостей
RUN pip install --no-cache-dir -r requirements.txt

# Команда запуска (heroku, а не hikka!)
CMD ["python3", "-m", "heroku", "--no-web"]
