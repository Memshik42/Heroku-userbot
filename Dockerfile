FROM python:3.9-slim

# 2. Устанавливаем рабочую директорию
WORKDIR /app

# 3. Копируем файл с зависимостями, который Leapcell взял из ВАШЕГО репозитория
COPY requirements.txt .

# 4. Устанавливаем зависимости
RUN pip install --no-cache-dir -r requirements.txt

# 5. Копируем ВАШ код (с вашими изменениями)
COPY . .

# 6. Указываем команду для запуска
CMD ["python3", "-m", "heroku"]
