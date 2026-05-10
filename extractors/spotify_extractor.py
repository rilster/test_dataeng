import spotipy
from spotipy.oauth2 import SpotifyClientCredentials
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class SpotifyExtractor:
    def __init__(self, client_id, client_secret):
        """
        Initialize Spotify API Client
        """
        auth_manager = SpotifyClientCredentials(
            client_id=client_id, 
            client_secret=client_secret
        )
        self.sp = spotipy.Spotify(auth_manager=auth_manager)

    def search_song_metadata(self, song_id, track_title, artist_name, limit=1):
        """
        Search for a song by title and artist, returning its ISRC, metadata, and label.
        Makes 2 API calls per song: /search + /albums/{id} (for label).
        """
        import datetime
        query = f"track:{track_title} artist:{artist_name}"
        logger.info(f"Searching Spotify for: {query}")
        
        try:
            results = self.sp.search(q=query, type='track', limit=limit)
            tracks = results.get('tracks', {}).get('items', [])
            
            extracted_data = []
            for track in tracks:
                album = track.get("album", {})
                album_id = album.get("id")

                # Step 2: Fetch label from album detail endpoint
                label = None
                if album_id:
                    try:
                        album_detail = self.sp.album(album_id)
                        label = album_detail.get("label")
                    except Exception as album_err:
                        logger.warning(f"Gagal mengambil detail album {album_id}: {album_err}")

                data = {
                    "spotify_track_id": track.get("id"),
                    "song_id": song_id,
                    "isrc": track.get("external_ids", {}).get("isrc"),
                    "recording_title": track.get("name"),
                    "album_name": album.get("name"),
                    "album_id": album_id,
                    "release_date": album.get("release_date"),
                    "label": label,           # <-- Field baru dari /albums/{id}
                    "extracted_at": datetime.datetime.now().isoformat()
                }
                extracted_data.append(data)
                
            return extracted_data
            
        except Exception as e:
            logger.error(f"Error searching Spotify for {track_title} by {artist_name}: {str(e)}")
            return []
