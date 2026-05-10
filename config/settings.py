import os
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

class Config:
    SPOTIFY_CLIENT_ID = os.getenv("SPOTIFY_CLIENT_ID")
    SPOTIFY_CLIENT_SECRET = os.getenv("SPOTIFY_CLIENT_SECRET")
    YOUTUBE_API_KEY = os.getenv("YOUTUBE_API_KEY")

    @classmethod
    def validate(cls):
        missing = []
        if not cls.SPOTIFY_CLIENT_ID: missing.append("SPOTIFY_CLIENT_ID")
        if not cls.SPOTIFY_CLIENT_SECRET: missing.append("SPOTIFY_CLIENT_SECRET")
        if not cls.YOUTUBE_API_KEY: missing.append("YOUTUBE_API_KEY")
        
        if missing:
            raise ValueError(f"Missing required environment variables: {', '.join(missing)}")
