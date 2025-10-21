import os
import subprocess
import logging
import asyncio
from datetime import datetime
from threading import Thread, Lock

logger = logging.getLogger(__name__)

class GitAutoSave:
    def __init__(self):
        self.git_token = os.getenv("GIT_TOKEN")
        self.git_username = os.getenv("GIT_USERNAME", "Memshik42")
        self.git_email = os.getenv("GIT_EMAIL", "bot@example.com")
        self.repo_path = "/data/Heroku"
        
        # Флаг для предотвращения одновременных коммитов
        self._save_lock = Lock()
        self._pending_changes = False
        self._last_save = None
        
        # Автосохранение включено по умолчанию
        self.auto_save_enabled = os.getenv("AUTO_SAVE", "True").lower() == "true"
        self.auto_save_interval = int(os.getenv("AUTO_SAVE_INTERVAL", "1800"))  # 30 минут
        
        # Пути для сохранения
        self.save_paths = [
            "heroku/modules/",
            "heroku/database/",
            "heroku/config.json",
            "heroku/*.db",
            "heroku/assets/",
        ]
        
        # Запустить фоновое автосохранение
        if self.auto_save_enabled and self.git_token:
            self._start_background_save()
        
    def configure_git(self):
        """Настройка Git с токеном"""
        try:
            subprocess.run([
                "git", "config", "--global", "user.name", self.git_username
            ], cwd=self.repo_path, check=True)
            
            subprocess.run([
                "git", "config", "--global", "user.email", self.git_email
            ], cwd=self.repo_path, check=True)
            
            # Настройка remote с токеном
            remote_url = f"https://{self.git_token}@github.com/{self.git_username}/Heroku-userbot.git"
            subprocess.run([
                "git", "remote", "set-url", "origin", remote_url
            ], cwd=self.repo_path, check=False)
            
            return True
        except Exception as e:
            logger.error(f"❌ Git config failed: {e}")
            return False
    
    def create_gitignore_exceptions(self):
        """Создать .gitignore исключения"""
        gitignore_path = os.path.join(self.repo_path, ".gitignore")
        
        try:
            if os.path.exists(gitignore_path):
                with open(gitignore_path, 'r') as f:
                    content = f.read()
            else:
                content = ""
            
            exceptions = """
# Auto-save exceptions
!heroku/modules/**
!heroku/database/**
!heroku/*.db
!heroku/config.json
!heroku/assets/**

# НЕ сохранять
heroku/session.session
heroku/*.session
*.log
__pycache__/
*.pyc
"""
            
            if "# Auto-save exceptions" not in content:
                with open(gitignore_path, 'a') as f:
                    f.write(exceptions)
                
        except Exception as e:
            logger.warning(f"⚠️ Could not update .gitignore: {e}")
    
    def mark_pending_changes(self):
        """Отметить что есть изменения для сохранения"""
        self._pending_changes = True
    
    def save_all(self, commit_message=None, silent=False):
        """Сохранить ВСЕ данные в GitHub"""
        if not self.git_token:
            if not silent:
                logger.warning("⚠️ GIT_TOKEN not set, skipping autosave")
            return False
        
        # Блокировка для предотвращения одновременных сохранений
        if not self._save_lock.acquire(blocking=False):
            if not silent:
                logger.info("⏳ Save already in progress, skipping...")
            return False
        
        try:
            self.configure_git()
            self.create_gitignore_exceptions()
            
            # Добавить все пути
            for path in self.save_paths:
                full_path = os.path.join(self.repo_path, path)
                if os.path.exists(full_path) or '*' in path:
                    subprocess.run([
                        "git", "add", "-f", path
                    ], cwd=self.repo_path, check=False)
            
            subprocess.run([
                "git", "add", ".gitignore"
            ], cwd=self.repo_path, check=False)
            
            # Проверить изменения
            result = subprocess.run([
                "git", "status", "--porcelain"
            ], cwd=self.repo_path, capture_output=True, text=True)
            
            if not result.stdout.strip():
                if not silent:
                    logger.info("ℹ️ No changes to commit")
                self._pending_changes = False
                return False
            
            changes = result.stdout.strip().split('\n')
            
            # Коммит
            if not commit_message:
                commit_message = f"Auto-save: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            
            subprocess.run([
                "git", "commit", "-m", commit_message
            ], cwd=self.repo_path, check=True)
            
            # Push
            subprocess.run([
                "git", "push", "origin", "master"
            ], cwd=self.repo_path, check=True)
            
            self._last_save = datetime.now()
            self._pending_changes = False
            
            if not silent:
                logger.info(f"✅ Auto-saved to GitHub: {len(changes)} files")
            
            return True
            
        except subprocess.CalledProcessError as e:
            if not silent:
                logger.error(f"❌ Git operation failed: {e}")
            return False
        except Exception as e:
            if not silent:
                logger.error(f"❌ Auto-save failed: {e}")
            return False
        finally:
            self._save_lock.release()
    
    def _background_save_loop(self):
        """Фоновый цикл автосохранения"""
        import time
        
        # Подождать 5 минут после запуска
        time.sleep(300)
        
        while True:
            try:
                if self._pending_changes or self.auto_save_interval > 0:
                    logger.info("🔄 Running scheduled auto-save...")
                    self.save_all("Auto-save: scheduled", silent=True)
            except Exception as e:
                logger.error(f"Background save error: {e}")
            
            time.sleep(self.auto_save_interval)
    
    def _start_background_save(self):
        """Запустить фоновое автосохранение"""
        thread = Thread(target=self._background_save_loop, daemon=True)
        thread.start()
        logger.info(f"✅ Auto-save enabled (every {self.auto_save_interval}s)")
    
    def save_modules(self, commit_message=None):
        """Алиас для обратной совместимости"""
        return self.save_all(commit_message)

# Singleton instance
git_autosave = GitAutoSave()
