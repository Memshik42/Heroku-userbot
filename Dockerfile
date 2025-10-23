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
    sqlite3 \
    zip \
    inotify-tools

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
RUN mkdir -p /data/private /data/sessions /data/export/secret_files /data/upload

RUN git clone https://github.com/coddrago/Heroku /data/Heroku

WORKDIR /data/Heroku

RUN git fetch && git checkout master && git pull

RUN pip install --no-warn-script-location --no-cache-dir -U -r requirements.txt
RUN pip install flask flask-cors

# Веб-интерфейс для загрузки сессий
RUN echo '#!/usr/bin/env python3\n\
from flask import Flask, request, jsonify, render_template_string\n\
from flask_cors import CORS\n\
import os\n\
import shutil\n\
from pathlib import Path\n\
import sqlite3\n\
\n\
app = Flask(__name__)\n\
CORS(app)\n\
\n\
HTML = """\n\
<!DOCTYPE html>\n\
<html>\n\
<head>\n\
    <title>Session Upload</title>\n\
    <meta charset="utf-8">\n\
    <meta name="viewport" content="width=device-width, initial-scale=1">\n\
    <style>\n\
        * { margin: 0; padding: 0; box-sizing: border-box; }\n\
        body {\n\
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;\n\
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);\n\
            min-height: 100vh;\n\
            display: flex;\n\
            align-items: center;\n\
            justify-content: center;\n\
            padding: 20px;\n\
        }\n\
        .container {\n\
            background: white;\n\
            border-radius: 20px;\n\
            box-shadow: 0 20px 60px rgba(0,0,0,0.3);\n\
            max-width: 600px;\n\
            width: 100%;\n\
            padding: 40px;\n\
        }\n\
        h1 {\n\
            color: #333;\n\
            margin-bottom: 10px;\n\
            text-align: center;\n\
        }\n\
        .subtitle {\n\
            text-align: center;\n\
            color: #666;\n\
            margin-bottom: 30px;\n\
            font-size: 14px;\n\
        }\n\
        .upload-area {\n\
            border: 3px dashed #667eea;\n\
            border-radius: 15px;\n\
            padding: 40px;\n\
            text-align: center;\n\
            cursor: pointer;\n\
            transition: all 0.3s;\n\
            margin-bottom: 20px;\n\
        }\n\
        .upload-area:hover {\n\
            background: #f8f9ff;\n\
            border-color: #764ba2;\n\
        }\n\
        .upload-area.dragover {\n\
            background: #f0f4ff;\n\
            border-color: #764ba2;\n\
        }\n\
        input[type="file"] {\n\
            display: none;\n\
        }\n\
        .upload-icon {\n\
            font-size: 48px;\n\
            margin-bottom: 15px;\n\
        }\n\
        .upload-text {\n\
            color: #666;\n\
            font-size: 16px;\n\
        }\n\
        .file-list {\n\
            margin: 20px 0;\n\
        }\n\
        .file-item {\n\
            background: #f8f9fa;\n\
            padding: 12px;\n\
            border-radius: 8px;\n\
            margin-bottom: 10px;\n\
            display: flex;\n\
            justify-content: space-between;\n\
            align-items: center;\n\
        }\n\
        .btn {\n\
            padding: 12px 24px;\n\
            border: none;\n\
            border-radius: 8px;\n\
            font-size: 16px;\n\
            font-weight: 600;\n\
            cursor: pointer;\n\
            transition: all 0.3s;\n\
        }\n\
        .btn-primary {\n\
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);\n\
            color: white;\n\
            width: 100%;\n\
        }\n\
        .btn-primary:hover {\n\
            transform: translateY(-2px);\n\
            box-shadow: 0 5px 15px rgba(102, 126, 234, 0.4);\n\
        }\n\
        .btn-danger {\n\
            background: #dc3545;\n\
            color: white;\n\
            padding: 6px 12px;\n\
            font-size: 14px;\n\
        }\n\
        .status {\n\
            margin-top: 20px;\n\
            padding: 15px;\n\
            border-radius: 8px;\n\
            text-align: center;\n\
            display: none;\n\
        }\n\
        .status.show { display: block; }\n\
        .status.success { background: #d4edda; color: #155724; }\n\
        .status.error { background: #f8d7da; color: #721c24; }\n\
        .status.info { background: #d1ecf1; color: #0c5460; }\n\
        .sessions-list {\n\
            margin-top: 30px;\n\
            padding-top: 20px;\n\
            border-top: 2px solid #e9ecef;\n\
        }\n\
        .sessions-title {\n\
            font-size: 18px;\n\
            font-weight: 600;\n\
            margin-bottom: 15px;\n\
            color: #333;\n\
        }\n\
        .session-item {\n\
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);\n\
            color: white;\n\
            padding: 15px;\n\
            border-radius: 10px;\n\
            margin-bottom: 10px;\n\
        }\n\
        .session-name {\n\
            font-weight: 600;\n\
            margin-bottom: 5px;\n\
        }\n\
        .session-details {\n\
            font-size: 13px;\n\
            opacity: 0.9;\n\
        }\n\
    </style>\n\
</head>\n\
<body>\n\
    <div class="container">\n\
        <h1>📤 Session File Upload</h1>\n\
        <p class="subtitle">Upload .session files from any source</p>\n\
        \n\
        <div class="upload-area" id="uploadArea">\n\
            <div class="upload-icon">📁</div>\n\
            <div class="upload-text">\n\
                <strong>Click to select</strong> or drag and drop<br>\n\
                .session files here\n\
            </div>\n\
            <input type="file" id="fileInput" accept=".session" multiple>\n\
        </div>\n\
        \n\
        <div class="file-list" id="fileList"></div>\n\
        \n\
        <button class="btn btn-primary" id="uploadBtn" style="display:none">Upload Sessions</button>\n\
        \n\
        <div class="status" id="status"></div>\n\
        \n\
        <div class="sessions-list" id="sessionsList"></div>\n\
    </div>\n\
    \n\
    <script>\n\
        let selectedFiles = [];\n\
        const uploadArea = document.getElementById("uploadArea");\n\
        const fileInput = document.getElementById("fileInput");\n\
        const fileList = document.getElementById("fileList");\n\
        const uploadBtn = document.getElementById("uploadBtn");\n\
        const status = document.getElementById("status");\n\
        \n\
        uploadArea.onclick = () => fileInput.click();\n\
        \n\
        fileInput.onchange = (e) => {\n\
            handleFiles(e.target.files);\n\
        };\n\
        \n\
        uploadArea.ondragover = (e) => {\n\
            e.preventDefault();\n\
            uploadArea.classList.add("dragover");\n\
        };\n\
        \n\
        uploadArea.ondragleave = () => {\n\
            uploadArea.classList.remove("dragover");\n\
        };\n\
        \n\
        uploadArea.ondrop = (e) => {\n\
            e.preventDefault();\n\
            uploadArea.classList.remove("dragover");\n\
            handleFiles(e.dataTransfer.files);\n\
        };\n\
        \n\
        function handleFiles(files) {\n\
            selectedFiles = Array.from(files).filter(f => f.name.endsWith(".session"));\n\
            \n\
            if (selectedFiles.length === 0) {\n\
                showStatus("Please select .session files only", "error");\n\
                return;\n\
            }\n\
            \n\
            fileList.innerHTML = "";\n\
            selectedFiles.forEach((file, index) => {\n\
                const div = document.createElement("div");\n\
                div.className = "file-item";\n\
                div.innerHTML = `\n\
                    <span>📄 ${file.name} (${(file.size/1024).toFixed(2)} KB)</span>\n\
                    <button class="btn btn-danger" onclick="removeFile(${index})">Remove</button>\n\
                `;\n\
                fileList.appendChild(div);\n\
            });\n\
            \n\
            uploadBtn.style.display = "block";\n\
        }\n\
        \n\
        function removeFile(index) {\n\
            selectedFiles.splice(index, 1);\n\
            if (selectedFiles.length === 0) {\n\
                fileList.innerHTML = "";\n\
                uploadBtn.style.display = "none";\n\
            } else {\n\
                handleFiles(selectedFiles);\n\
            }\n\
        }\n\
        \n\
        uploadBtn.onclick = async () => {\n\
            uploadBtn.disabled = true;\n\
            showStatus("Uploading sessions...", "info");\n\
            \n\
            const formData = new FormData();\n\
            selectedFiles.forEach(file => {\n\
                formData.append("sessions", file);\n\
            });\n\
            \n\
            try {\n\
                const res = await fetch("/upload", {\n\
                    method: "POST",\n\
                    body: formData\n\
                });\n\
                \n\
                const data = await res.json();\n\
                \n\
                if (data.success) {\n\
                    showStatus(`✅ Uploaded ${data.uploaded} session(s) successfully!`, "success");\n\
                    selectedFiles = [];\n\
                    fileList.innerHTML = "";\n\
                    uploadBtn.style.display = "none";\n\
                    loadSessions();\n\
                } else {\n\
                    showStatus("Error: " + data.message, "error");\n\
                }\n\
            } catch (err) {\n\
                showStatus("Upload failed: " + err.message, "error");\n\
            }\n\
            \n\
            uploadBtn.disabled = false;\n\
        };\n\
        \n\
        function showStatus(message, type) {\n\
            status.textContent = message;\n\
            status.className = `status show ${type}`;\n\
            setTimeout(() => status.classList.remove("show"), 5000);\n\
        }\n\
        \n\
        async function loadSessions() {\n\
            try {\n\
                const res = await fetch("/sessions");\n\
                const data = await res.json();\n\
                \n\
                const list = document.getElementById("sessionsList");\n\
                \n\
                if (data.sessions && data.sessions.length > 0) {\n\
                    list.innerHTML = `<div class="sessions-title">✅ Active Sessions (${data.sessions.length})</div>`;\n\
                    data.sessions.forEach(s => {\n\
                        const div = document.createElement("div");\n\
                        div.className = "session-item";\n\
                        div.innerHTML = `\n\
                            <div class="session-name">${s.name}</div>\n\
                            <div class="session-details">Size: ${s.size} | Saved: ${s.saved ? "✅" : "⏳"}</div>\n\
                        `;\n\
                        list.appendChild(div);\n\
                    });\n\
                } else {\n\
                    list.innerHTML = "";\n\
                }\n\
            } catch (err) {\n\
                console.error("Failed to load sessions:", err);\n\
            }\n\
        }\n\
        \n\
        loadSessions();\n\
        setInterval(loadSessions, 5000);\n\
    </script>\n\
</body>\n\
</html>\n\
"""\n\
\n\
def check_session(path):\n\
    """Проверка валидности session файла"""\n\
    try:\n\
        conn = sqlite3.connect(path)\n\
        cursor = conn.cursor()\n\
        cursor.execute("PRAGMA integrity_check")\n\
        result = cursor.fetchone()\n\
        conn.close()\n\
        return result[0] == "ok"\n\
    except:\n\
        return False\n\
\n\
@app.route("/")\n\
def index():\n\
    return render_template_string(HTML)\n\
\n\
@app.route("/upload", methods=["POST"])\n\
def upload():\n\
    try:\n\
        files = request.files.getlist("sessions")\n\
        uploaded = 0\n\
        \n\
        for file in files:\n\
            if file.filename.endswith(".session"):\n\
                # Сохранение во временную папку\n\
                temp_path = f"/data/upload/{file.filename}"\n\
                file.save(temp_path)\n\
                \n\
                # Проверка валидности\n\
                if check_session(temp_path):\n\
                    # Перемещение в /data\n\
                    final_path = f"/data/{file.filename}"\n\
                    shutil.move(temp_path, final_path)\n\
                    print(f"✅ Uploaded and validated: {file.filename}")\n\
                    uploaded += 1\n\
                else:\n\
                    os.remove(temp_path)\n\
                    print(f"❌ Invalid session file: {file.filename}")\n\
        \n\
        return jsonify({"success": True, "uploaded": uploaded})\n\
    except Exception as e:\n\
        return jsonify({"success": False, "message": str(e)})\n\
\n\
@app.route("/sessions")\n\
def get_sessions():\n\
    sessions = []\n\
    \n\
    for f in Path("/data").glob("*.session"):\n\
        saved = Path(f"/data/sessions/{f.name}").exists()\n\
        sessions.append({\n\
            "name": f.name,\n\
            "size": f"{f.stat().st_size / 1024:.2f} KB",\n\
            "saved": saved\n\
        })\n\
    \n\
    return jsonify({"sessions": sessions})\n\
\n\
if __name__ == "__main__":\n\
    app.run(host="0.0.0.0", port=8081)' > /data/upload_server.py && chmod +x /data/upload_server.py

# Основной entrypoint
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
echo "🔄 Universal Session Manager"\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
\n\
# Функция проверки сессии\n\
check_session() {\n\
    if [ -f "$1" ]; then\n\
        if sqlite3 "$1" "PRAGMA integrity_check;" 2>/dev/null | grep -q "ok"; then\n\
            return 0\n\
        fi\n\
    fi\n\
    return 1\n\
}\n\
\n\
# Функция сохранения сессии\n\
save_single_session() {\n\
    local session_file="$1"\n\
    local filename=$(basename "$session_file")\n\
    \n\
    if check_session "$session_file"; then\n\
        cp "$session_file" /data/sessions/\n\
        cp "$session_file" /data/export/secret_files/\n\
        date "+%Y-%m-%d %H:%M:%S" > "/data/sessions/${filename}.timestamp"\n\
        echo "✅ Saved: $filename"\n\
        return 0\n\
    fi\n\
    return 1\n\
}\n\
\n\
# Функция сохранения всех сессий\n\
save_all_sessions() {\n\
    local saved=0\n\
    for session in /data/*.session; do\n\
        if [ -f "$session" ]; then\n\
            if save_single_session "$session"; then\n\
                ((saved++))\n\
            fi\n\
        fi\n\
    done\n\
    \n\
    if [ $saved -gt 0 ]; then\n\
        cd /data/export\n\
        rm -f sessions_backup.zip\n\
        zip -q -r sessions_backup.zip secret_files/*.session 2>/dev/null || true\n\
    fi\n\
}\n\
\n\
# 1. Загрузка из Secret Files\n\
if [ -d "/etc/secrets" ] && ls /etc/secrets/*.session 1> /dev/null 2>&1; then\n\
    echo "📁 Loading from Secret Files (/etc/secrets)..."\n\
    for session in /etc/secrets/*.session; do\n\
        filename=$(basename "$session")\n\
        if check_session "$session"; then\n\
            cp "$session" /data/\n\
            cp "$session" /data/sessions/\n\
            echo "   ✅ Imported: $filename"\n\
        fi\n\
    done\n\
fi\n\
\n\
# 2. Загрузка из persistent storage\n\
if [ -d "/data/sessions" ] && ls /data/sessions/*.session 1> /dev/null 2>&1; then\n\
    echo "📂 Loading from saved sessions..."\n\
    for session in /data/sessions/*.session; do\n\
        filename=$(basename "$session")\n\
        if [ ! -f "/data/$filename" ] && check_session "$session"; then\n\
            cp "$session" /data/\n\
            echo "   ✅ Restored: $filename"\n\
        fi\n\
    done\n\
fi\n\
\n\
# 3. Загрузка из внешней директории (если примонтирована)\n\
if [ -d "/external_sessions" ] && ls /external_sessions/*.session 1> /dev/null 2>&1; then\n\
    echo "📦 Loading from external directory..."\n\
    for session in /external_sessions/*.session; do\n\
        filename=$(basename "$session")\n\
        if check_session "$session"; then\n\
            cp "$session" /data/\n\
            save_single_session "/data/$filename"\n\
            echo "   ✅ Imported: $filename"\n\
        fi\n\
    done\n\
fi\n\
\n\
# 4. Запуск веб-сервера для загрузки сессий\n\
echo "🌐 Starting session upload server on port 8081..."\n\
python3 /data/upload_server.py &\n\
UPLOAD_PID=$!\n\
\n\
# 5. Мониторинг файловой системы\n\
echo "👁️ Starting filesystem monitor..."\n\
(\n\
    inotifywait -m -e create -e modify -e moved_to --format "%f" /data 2>/dev/null | \\\n\
    while read filename; do\n\
        if [[ "$filename" == *.session ]]; then\n\
            sleep 2\n\
            session_path="/data/$filename"\n\
            if [ -f "$session_path" ]; then\n\
                echo "🆕 New session detected: $filename"\n\
                if save_single_session "$session_path"; then\n\
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
                    echo "✅ SESSION SAVED: $filename"\n\
                    echo "📥 Download: docker cp heroku-userbot:/data/export/secret_files/$filename ./"\n\
                    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
                fi\n\
            fi\n\
        fi\n\
    done\n\
) &\n\
WATCH_PID=$!\n\
\n\
# 6. Периодическое автосохранение\n\
(\n\
    while true; do\n\
        sleep 300\n\
        save_all_sessions > /dev/null 2>&1\n\
    done\n\
) &\n\
AUTOSAVE_PID=$!\n\
\n\
# 7. Статус\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
session_count=$(ls -1 /data/*.session 2>/dev/null | wc -l)\n\
\n\
if [ "$session_count" -gt 0 ]; then\n\
    echo "✅ Active sessions: $session_count"\n\
    echo ""\n\
    for session in /data/*.session; do\n\
        if [ -f "$session" ]; then\n\
            filename=$(basename "$session")\n\
            size=$(du -h "$session" | cut -f1)\n\
            echo "   • $filename ($size)"\n\
        fi\n\
    done\n\
else\n\
    echo "⚠️ No sessions found"\n\
    echo ""\n\
    echo "📝 Create session via:"\n\
    echo "   • Heroku web UI: http://localhost:8080"\n\
    echo "   • Upload UI: http://localhost:8081"\n\
    echo "   • External site → upload to port 8081"\n\
    echo "   • Mount directory with sessions"\n\
fi\n\
\n\
echo ""\n\
echo "🌐 Session upload interface: http://localhost:8081"\n\
echo "🚀 Heroku userbot interface: http://localhost:8080"\n\
\n\
# 8. Cleanup handler\n\
cleanup() {\n\
    echo "\n🛑 Shutting down..."\n\
    kill $UPLOAD_PID $WATCH_PID $AUTOSAVE_PID 2>/dev/null || true\n\
    save_all_sessions\n\
    echo "✅ All sessions saved"\n\
    exit 0\n\
}\n\
\n\
trap cleanup SIGTERM SIGINT EXIT\n\
\n\
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"\n\
echo "🚀 Starting Heroku userbot..."\n\
\n\
exec "$@"' > /entrypoint.sh && chmod +x /entrypoint.sh

VOLUME ["/data/sessions", "/data/export", "/external_sessions"]

EXPOSE 8080 8081

ENTRYPOINT ["/entrypoint.sh"]
CMD ["python", "-m", "heroku", "--root"]
