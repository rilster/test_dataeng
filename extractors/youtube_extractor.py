from googleapiclient.discovery import build
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class YouTubeExtractor:
    def __init__(self, api_key):
        """
        Initialize YouTube Data API v3 Client
        """
        self.youtube = build('youtube', 'v3', developerKey=api_key)

    def search_song_videos(self, song_id, track_title, artist_name, max_results=5):
        """
        Search for videos relating to a specific song and artist.
        """
        import datetime
        query = f"{track_title} {artist_name} official audio OR official video"
        logger.info(f"Searching YouTube for: {query}")
        
        extracted_data = []
        try:
            # Step 1: Search for videos
            search_response = self.youtube.search().list(
                q=query,
                part='id,snippet',
                maxResults=max_results,
                type='video'
            ).execute()

            # Step 2: Extract relevant metadata
            for item in search_response.get('items', []):
                snippet = item.get('snippet', {})
                video_id = item.get('id', {}).get('videoId')
                
                if video_id:
                    data = {
                        "video_id": video_id,
                        "song_id": song_id,
                        "channel_id": snippet.get('channelId'),
                        "channel_title": snippet.get('channelTitle'),
                        "video_title": snippet.get('title'),
                        "publish_time": snippet.get('publishTime'),
                        "extracted_at": datetime.datetime.now().isoformat()
                    }
                extracted_data.append(data)
                
            return extracted_data
            
        except Exception as e:
            logger.error(f"Error searching YouTube for {track_title} by {artist_name}: {str(e)}")
            return []

    def get_video_stats(self, video_id):
        """
        Optional: Retrieve view counts or other stats for a given video ID.
        """
        try:
            video_response = self.youtube.videos().list(
                id=video_id,
                part='statistics'
            ).execute()
            
            items = video_response.get('items', [])
            if items:
                return items[0].get('statistics', {})
            return {}
        except Exception as e:
            logger.error(f"Error fetching stats for video {video_id}: {str(e)}")
            return {}
