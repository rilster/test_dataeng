-- ==============================================================================
-- BRONZE -> SILVER LAYER MERGE QUERIES
-- Project: Music Data Warehouse
-- Tujuan:
--   Melakukan MERGE (UPSERT) dari Bronze Layer (raw/landing) ke Silver Layer
--   (cleaned/deduplicated). Pola ini memastikan data tidak duplikat saat
--   pipeline dijalankan berulang kali setiap hari.
-- =============================================================================


-- ==============================================================================
-- [1] MERGE: Bronze -> Silver untuk Tabel FCT_SPOTIFY_TRACK
-- Bronze Source : bronze.spotify_raw
-- Silver Target : silver.fct_spotify_track
-- Kunci Merge  : spotify_track_id (Primary Key dari Spotify)
-- ==============================================================================
MERGE `peppy-gist-495807-s5.silver.fct_spotify_track` AS target
USING (
    SELECT
        spotify_track_id,
        song_id,
        isrc,
        recording_title,
        album_name,
        album_id,
        release_date,
        label,
        extracted_at
    FROM (
        SELECT
            TRIM(spotify_track_id)                                     AS spotify_track_id,
            CAST(song_id AS STRING)                                    AS song_id,
            UPPER(TRIM(isrc))                                          AS isrc,
            TRIM(recording_title)                                      AS recording_title,
            TRIM(album_name)                                           AS album_name,
            TRIM(album_id)                                             AS album_id,
            SAFE.PARSE_DATE('%Y-%m-%d', release_date)                  AS release_date,
            TRIM(label)                                                AS label,
            SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S', extracted_at) AS extracted_at,
            -- Deduplikasi: per spotify_track_id, ambil data yang paling baru
            ROW_NUMBER() OVER (PARTITION BY spotify_track_id ORDER BY extracted_at DESC) AS rn
        FROM `peppy-gist-495807-s5.bronze.spotify_raw`
        WHERE spotify_track_id IS NOT NULL
          AND song_id IS NOT NULL
    )
    WHERE rn = 1
) AS source
ON target.spotify_track_id = source.spotify_track_id

-- Update jika ada perubahan metadata (misal: album name, label, atau isrc diperbaiki)
WHEN MATCHED AND (
    target.isrc            != source.isrc OR
    target.recording_title != source.recording_title OR
    target.album_name      != source.album_name OR
    target.album_id        != source.album_id OR
    IFNULL(target.label, '') != IFNULL(source.label, '')
) THEN
    UPDATE SET
        song_id         = source.song_id,
        isrc            = source.isrc,
        recording_title = source.recording_title,
        album_name      = source.album_name,
        album_id        = source.album_id,
        release_date    = source.release_date,
        label           = source.label,
        extracted_at    = source.extracted_at

-- Insert jika spotify_track_id belum pernah ada di Silver
WHEN NOT MATCHED BY TARGET THEN
    INSERT (spotify_track_id, song_id, isrc, recording_title, album_name, album_id, release_date, label, extracted_at)
    VALUES (source.spotify_track_id, source.song_id, source.isrc, source.recording_title, source.album_name, source.album_id, source.release_date, source.label, source.extracted_at);


-- ==============================================================================
-- [2] MERGE: Bronze -> Silver untuk Tabel FCT_YOUTUBE_VIDEO
-- Bronze Source : bronze.youtube_raw
-- Silver Target : silver.fct_youtube_video
-- Kunci Merge  : video_id (Primary Key dari YouTube)
-- ==============================================================================
MERGE `peppy-gist-495807-s5.silver.fct_youtube_video` AS target
USING (
    SELECT
        video_id,
        song_id,
        channel_id,
        channel_title,
        video_title,
        publish_time,
        extracted_at
    FROM (
        SELECT
            TRIM(video_id)                                                     AS video_id,
            CAST(song_id AS STRING)                                            AS song_id,
            TRIM(channel_id)                                                   AS channel_id,
            TRIM(channel_title)                                                AS channel_title,
            TRIM(video_title)                                                  AS video_title,
            SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*SZ', publish_time)        AS publish_time,
            SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S', extracted_at)         AS extracted_at,
            -- Deduplikasi: per video_id, ambil data yang paling baru
            ROW_NUMBER() OVER (PARTITION BY video_id ORDER BY extracted_at DESC) AS rn
        FROM `peppy-gist-495807-s5.bronze.youtube_raw`
        WHERE video_id IS NOT NULL
          AND song_id IS NOT NULL
    )
    WHERE rn = 1
) AS source
ON target.video_id = source.video_id

-- Update jika ada perubahan metadata video
WHEN MATCHED AND (
    target.video_title   != source.video_title OR
    target.channel_title != source.channel_title
) THEN
    UPDATE SET
        song_id       = source.song_id,
        channel_id    = source.channel_id,
        channel_title = source.channel_title,
        video_title   = source.video_title,
        publish_time  = source.publish_time,
        extracted_at  = source.extracted_at

-- Insert jika video_id belum pernah ada di Silver
WHEN NOT MATCHED BY TARGET THEN
    INSERT (video_id, song_id, channel_id, channel_title, video_title, publish_time, extracted_at)
    VALUES (source.video_id, source.song_id, source.channel_id, source.channel_title, source.video_title, source.publish_time, source.extracted_at);
