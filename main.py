import pandas as pd
from config.settings import Config
from extractors.spotify_extractor import SpotifyExtractor
from extractors.youtube_extractor import YouTubeExtractor
import logging
import sys
import time
import json
import os

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

CHECKPOINT_FILE    = "checkpoint.json"
AUTOSAVE_EVERY     = 50    
REQUEST_DELAY      = 0.5   

# === YouTube Quota Management ===
YOUTUBE_COST_PER_SEARCH = 100   
YOUTUBE_DAILY_QUOTA     = 10000 
YOUTUBE_SAFETY_MARGIN   = 0.85  
YOUTUBE_MAX_REQUESTS    = int((YOUTUBE_DAILY_QUOTA * YOUTUBE_SAFETY_MARGIN) / YOUTUBE_COST_PER_SEARCH)
YOUTUBE_DELAY           = 1.0   

def load_checkpoint():
    """Baca checkpoint terakhir jika ada, sehingga pipeline bisa dilanjutkan."""
    if os.path.exists(CHECKPOINT_FILE):
        with open(CHECKPOINT_FILE, 'r') as f:
            cp = json.load(f)
            logger.info(f"Resuming from checkpoint: index {cp['last_index']} ({cp['last_song_id']})")
            return cp['last_index']
    return 0

def save_checkpoint(index, song_id):
    """Simpan posisi terakhir yang berhasil diproses."""
    with open(CHECKPOINT_FILE, 'w') as f:
        json.dump({"last_index": index, "last_song_id": song_id}, f)

def clear_checkpoint():
    """Hapus checkpoint setelah pipeline selesai penuh."""
    if os.path.exists(CHECKPOINT_FILE):
        os.remove(CHECKPOINT_FILE)
        logger.info("Checkpoint cleared.")

def process_catalog(catalog_df):
    """
    Process a catalog of songs, extract data from APIs, and return structured datasets.
    Includes: checkpointing, polite delay, and auto-save every N songs.
    """
    try:
        Config.validate()
    except ValueError as e:
        logger.error(str(e))
        return None, None

    spotify = SpotifyExtractor(Config.SPOTIFY_CLIENT_ID, Config.SPOTIFY_CLIENT_SECRET)
    youtube = YouTubeExtractor(Config.YOUTUBE_API_KEY)

    
    spotify_results = []
    youtube_results = []
    if os.path.exists("spotify_raw.csv"):
        spotify_results = pd.read_csv("spotify_raw.csv").to_dict('records')
        logger.info(f"Loaded {len(spotify_results)} existing Spotify rows from spotify_raw.csv")
    if os.path.exists("youtube_raw.csv"):
        youtube_results = pd.read_csv("youtube_raw.csv").to_dict('records')
        logger.info(f"Loaded {len(youtube_results)} existing YouTube rows from youtube_raw.csv")

    
    start_index = load_checkpoint()
    catalog_df = catalog_df.iloc[start_index:].reset_index(drop=True)
    logger.info(f"Processing {len(catalog_df)} remaining songs from catalog...")
    logger.info(f"YouTube quota limit: {YOUTUBE_MAX_REQUESTS} requests/day (safety margin {int(YOUTUBE_SAFETY_MARGIN*100)}%)")

    youtube_request_count = 0          
    youtube_quota_exceeded = False     

    for i, row in catalog_df.iterrows():
        actual_index = start_index + i
        song_id = str(row.get('CODE'))
        title   = row.get('SONG TITLE')
        artist  = row.get('ORIGINAL ARTIST')
        
        if pd.isna(artist):
            artist = ""
            
        logger.info(f"[{actual_index+1}] Extracting: {title} by {artist} (ID: {song_id})")

        sp_data = spotify.search_song_metadata(song_id, title, artist, limit=1)
        if sp_data:
            spotify_results.extend(sp_data)
        time.sleep(REQUEST_DELAY)  

        if youtube_request_count < YOUTUBE_MAX_REQUESTS and not youtube_quota_exceeded:
            try:
                yt_data = youtube.search_song_videos(song_id, title, artist, max_results=3)
                if yt_data:
                    youtube_results.extend(yt_data)
                youtube_request_count += 1
                time.sleep(YOUTUBE_DELAY)
                logger.info(f"   YouTube quota used: {youtube_request_count}/{YOUTUBE_MAX_REQUESTS} requests")
            except Exception as yt_err:
                if "quotaExceeded" in str(yt_err):
                    youtube_quota_exceeded = True
                    logger.warning("   ⚠️ YouTube quota HABIS (403). Menonaktifkan YouTube untuk sisa sesi ini.")
                else:
                    logger.error(f"   YouTube error: {yt_err}")
        elif youtube_quota_exceeded:
            pass 
        else:
            logger.warning(f"   ⚠️ YouTube safety limit ({YOUTUBE_MAX_REQUESTS} requests) tercapai.")

   
        save_checkpoint(actual_index + 1, song_id)

        
        if (i + 1) % AUTOSAVE_EVERY == 0:
            logger.info(f"Auto-saving progress at song {actual_index + 1}...")
            pd.DataFrame(spotify_results).to_csv("spotify_raw.csv", index=False)
            pd.DataFrame(youtube_results).to_csv("youtube_raw.csv", index=False)

    # Convert to DataFrames
    df_spotify = pd.DataFrame(spotify_results)
    df_youtube = pd.DataFrame(youtube_results)

    return df_spotify, df_youtube


if __name__ == "__main__":
    # Read the Internal Song Catalog from Google Sheets
    url = "https://docs.google.com/spreadsheets/d/1OkDM1miCXh48M23n_C4AOGPl_DW1QtIXFSdHW6Grzxg/export?format=csv&gid=0"
    logger.info("Downloading catalog from Google Sheets...")
    catalog_df = pd.read_csv(url)


    df_sp, df_yt = process_catalog(catalog_df)

    if df_sp is not None and not df_sp.empty:
        logger.info("Saving Spotify data to spotify_raw.csv...")
        df_sp.to_csv("spotify_raw.csv", index=False)
        logger.info(f"✅ {len(df_sp)} rows saved to spotify_raw.csv")

    if df_yt is not None and not df_yt.empty:
        logger.info("Saving YouTube data to youtube_raw.csv...")
        df_yt.to_csv("youtube_raw.csv", index=False)
        logger.info(f"✅ {len(df_yt)} rows saved to youtube_raw.csv")

    clear_checkpoint()



