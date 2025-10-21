import os
import subprocess
import logging
from datetime import datetime

logger = logging.getLogger(__name__)

class GitAutoSave:
    def __init__(self):
        self.git_token = os.getenv("GIT_TOKEN")
        self.git_username = os.getenv("GIT_USERNAME", "Memshik42")
        self.git_email = os.getenv("GIT_EMAIL", "bot@example.com")
        self.repo_path = "/data/Heroku"
        
    def configure_git(self):
        """Настройка Git с токеном"""
        try:
            # Настройка credentials
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
            
            logger.info("✅ Git configured successfully")
            return True
        except Exception as e:
            logger.error(f"❌ Git config failed: {e}")
            return False
    
    def save_modules(self, commit_message=None):
        """Сохранить модули в GitHub"""
        if not self.git_token:
            logger.warning("⚠️ GIT_TOKEN not set, skipping autosave")
            return False
            
        try:
            # Настроить Git
            self.configure_git()
            
            # Добавить изменения
            subprocess.run([
                "git", "add", "heroku/modules/", "heroku/database/"
            ], cwd=self.repo_path, check=False)
            
            # Проверить есть ли изменения
            result = subprocess.run([
                "git", "status", "--porcelain"
            ], cwd=self.repo_path, capture_output=True, text=True)
            
            if not result.stdout.strip():
                logger.info("ℹ️ No changes to commit")
                return False
            
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
            
            logger.info(f"✅ Auto-saved to GitHub: {commit_message}")
            return True
            
        except subprocess.CalledProcessError as e:
            logger.error(f"❌ Git operation failed: {e}")
            return False
        except Exception as e:
            logger.error(f"❌ Auto-save failed: {e}")
            return False

# Singleton instance
git_autosave = GitAutoSave()
