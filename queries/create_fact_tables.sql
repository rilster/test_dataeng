-- ==============================================================================
-- STEP 0: Load raw CSV ke Bronze terlebih dahulu (jalankan via bq CLI)
--
--   bq load --source_format=CSV --skip_leading_rows=1 --autodetect \
--     peppy-gist-495807-s5:bronze.spotify_raw spotify_raw.csv
--
--   bq load --source_format=CSV --skip_leading_rows=1 --autodetect \
--     peppy-gist-495807-s5:bronze.youtube_raw youtube_raw.csv
-- ==============================================================================


-- ==============================================================================
-- [1] CREATE: FCT_SPOTIFY_TRACK di Silver Layer
-- Source  : bronze.spotify_raw
-- Lookup  : silver.dim_song (untuk mendapatkan song_id)
-- Strategi: Cocokkan via LOWER(recording_title) + LOWER(artist)
--           karena Spotify tidak menyimpan identifier internal kita.
-- ==============================================================================
CREATE OR REPLACE TABLE `peppy-gist-495807-s5.silver.fct_spotify_track`
OPTIONS (
    description = "Fact table: Metadata lagu dari Spotify API sesuai ERD"
)
AS

WITH

-- Bersihkan dan deduplikasi raw Spotify
spotify_clean AS (
    SELECT
        TRIM(spotify_track_id)                                  AS spotify_track_id,
        LOWER(TRIM(recording_title))                            AS recording_title_key, -- untuk JOIN
        TRIM(recording_title)                                   AS recording_title,
        UPPER(TRIM(isrc))                                       AS isrc,
        TRIM(album_name)                                        AS album_name,
        TRIM(album_id)                                          AS album_id,
        SAFE.PARSE_DATE('%Y-%m-%d', release_date)               AS release_date,
        TRIM(label)                                             AS label,
        SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S', extracted_at) AS extracted_at,
        ROW_NUMBER() OVER (
            PARTITION BY spotify_track_id ORDER BY extracted_at DESC
        ) AS rn
    FROM `peppy-gist-495807-s5.bronze.spotify_raw`
    WHERE spotify_track_id IS NOT NULL
),

-- Lookup song_id dari DIM_SONG via title matching
dim_lookup AS (
    SELECT
        LOWER(TRIM(title))  AS title_key,
        LOWER(TRIM(artist)) AS artist_key,
        song_id
    FROM `peppy-gist-495807-s5.silver.dim_song`
)

SELECT
    sp.spotify_track_id,
    ds.song_id,                 -- ✅ song_id dari DIM_SONG (lookup)
    sp.isrc,
    sp.recording_title,
    sp.album_name,
    sp.album_id,
    sp.release_date,
    sp.label,
    sp.extracted_at

FROM spotify_clean sp
-- JOIN ke dim_song berdasarkan kesamaan judul lagu
LEFT JOIN dim_lookup ds
    ON sp.recording_title_key = ds.title_key

WHERE sp.rn = 1;


-- ==============================================================================
-- [2] CREATE: FCT_YOUTUBE_VIDEO di Silver Layer
-- Source  : bronze.youtube_raw
-- Lookup  : silver.dim_song (untuk mendapatkan song_id)
-- Strategi: Cocokkan via LOWER(video_title) LIKE '%song_title%'
--           karena judul video YouTube sering mengandung judul lagu.
--           (Pendekatan fuzzy — ada risiko mismatch, namun umum di industri)
-- ==============================================================================
CREATE OR REPLACE TABLE `peppy-gist-495807-s5.silver.fct_youtube_video`
OPTIONS (
    description = "Fact table: Metadata video dari YouTube API sesuai ERD"
)
AS

WITH

-- Bersihkan dan deduplikasi raw YouTube
youtube_clean AS (
    SELECT
        TRIM(video_id)                                                    AS video_id,
        TRIM(channel_id)                                                  AS channel_id,
        TRIM(channel_title)                                               AS channel_title,
        TRIM(video_title)                                                 AS video_title,
        LOWER(TRIM(video_title))                                          AS video_title_lower,
        SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*SZ', publish_time)       AS publish_time,
        SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S', extracted_at)        AS extracted_at,
        ROW_NUMBER() OVER (
            PARTITION BY video_id ORDER BY extracted_at DESC
        ) AS rn
    FROM `peppy-gist-495807-s5.bronze.youtube_raw`
    WHERE video_id IS NOT NULL
),

-- Lookup song_id dari DIM_SONG
dim_lookup AS (
    SELECT
        song_id,
        LOWER(TRIM(title))  AS title_key
    FROM `peppy-gist-495807-s5.silver.dim_song`
)

SELECT
    yt.video_id,
    ds.song_id,                 -- ✅ song_id dari DIM_SONG (lookup via LIKE)
    yt.channel_id,
    yt.channel_title,
    yt.video_title,
    yt.publish_time,
    yt.extracted_at

FROM youtube_clean yt
-- Fuzzy match: video_title mengandung judul lagu dari DIM_SONG
LEFT JOIN dim_lookup ds
    ON yt.video_title_lower LIKE CONCAT('%', ds.title_key, '%')

WHERE yt.rn = 1;


-- ==============================================================================
-- [3] VALIDASI: Cek hasil dan integritas relasi
-- ==============================================================================

-- Jumlah total baris per tabel
SELECT 'fct_spotify_track' AS tabel, COUNT(*) AS total_rows,
       COUNTIF(song_id IS NULL) AS unmatched_song_id
FROM `peppy-gist-495807-s5.silver.fct_spotify_track`
UNION ALL
SELECT 'fct_youtube_video' AS tabel, COUNT(*) AS total_rows,
       COUNTIF(song_id IS NULL) AS unmatched_song_id
FROM `peppy-gist-495807-s5.silver.fct_youtube_video`;

-- Tujuan   :
--   Membuat tabel FCT_SPOTIFY_TRACK dan FCT_YOUTUBE_VIDEO di Silver Layer
--   dari data mentah (raw CSV) yang sudah di-load ke Bronze Layer.
--   Query ini sesuai dengan desain ERD yang sudah didokumentasikan.
-- ==============================================================================


-- ==============================================================================
-- STEP 0: Pastikan dataset Bronze sudah ada dan raw CSV sudah di-load ke sana
-- Jika belum, gunakan perintah bq CLI berikut untuk masing-masing file:
--
--   bq load --source_format=CSV --skip_leading_rows=1 --autodetect \
--     peppy-gist-495807-s5:bronze.spotify_raw spotify_raw.csv
--
--   bq load --source_format=CSV --skip_leading_rows=1 --autodetect \
--     peppy-gist-495807-s5:bronze.youtube_raw youtube_raw.csv
-- ==============================================================================


-- ==============================================================================
-- [1] CREATE: FCT_SPOTIFY_TRACK di Silver Layer
-- Source : bronze.spotify_raw (hasil ekstraksi main.py -> spotify_raw.csv)
-- Target : silver.fct_spotify_track
-- Sesuai ERD: spotify_track_id (PK), song_id (FK), isrc, recording_title,
--             album_name, release_date, extracted_at
-- ==============================================================================
CREATE OR REPLACE TABLE `peppy-gist-495807-s5.silver.fct_spotify_track`
OPTIONS (
    description = "Fact table: Metadata lagu dari Spotify API sesuai ERD"
)
AS
SELECT
    -- Primary Key
    TRIM(spotify_track_id)          AS spotify_track_id,
    
    -- Foreign Key ke DIM_SONG
    CAST(song_id AS STRING)         AS song_id,
    
    -- Atribut Spotify
    UPPER(TRIM(isrc))               AS isrc,            -- ISRC distandarisasi ke UPPERCASE
    TRIM(recording_title)           AS recording_title,
    TRIM(album_name)                AS album_name,
    TRIM(album_id)                  AS album_id,
    
    -- Release date: pastikan formatnya DATE
    SAFE.PARSE_DATE('%Y-%m-%d', release_date) AS release_date,
    
    -- Label rekaman dari endpoint /albums (hasil update extractor)
    TRIM(label)                     AS label,
    
    -- Audit timestamp
    SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S', extracted_at) AS extracted_at

FROM (
    -- Deduplikasi: jika ada spotify_track_id ganda, ambil yang paling baru
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY spotify_track_id
            ORDER BY extracted_at DESC
        ) AS rn
    FROM `peppy-gist-495807-s5.bronze.spotify_raw`
    WHERE spotify_track_id IS NOT NULL
      AND song_id IS NOT NULL
)
WHERE rn = 1;


-- ==============================================================================
-- [2] CREATE: FCT_YOUTUBE_VIDEO di Silver Layer
-- Source : bronze.youtube_raw (hasil ekstraksi main.py -> youtube_raw.csv)
-- Target : silver.fct_youtube_video
-- Sesuai ERD: video_id (PK), song_id (FK), channel_id, channel_title,
--             video_title, publish_time, extracted_at
-- ==============================================================================
CREATE OR REPLACE TABLE `peppy-gist-495807-s5.silver.fct_youtube_video`
OPTIONS (
    description = "Fact table: Metadata video dari YouTube API sesuai ERD"
)
AS
SELECT
    -- Primary Key
    TRIM(video_id)                  AS video_id,
    
    -- Foreign Key ke DIM_SONG
    CAST(song_id AS STRING)         AS song_id,
    
    -- Atribut YouTube
    TRIM(channel_id)                AS channel_id,
    TRIM(channel_title)             AS channel_title,
    TRIM(video_title)               AS video_title,
    
    -- Publish time: pastikan formatnya TIMESTAMP
    SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*SZ', publish_time) AS publish_time,
    
    -- Audit timestamp
    SAFE.PARSE_TIMESTAMP('%Y-%m-%dT%H:%M:%E*S', extracted_at)  AS extracted_at

FROM (
    -- Deduplikasi: jika ada video_id ganda, ambil yang paling baru
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY video_id
            ORDER BY extracted_at DESC
        ) AS rn
    FROM `peppy-gist-495807-s5.bronze.youtube_raw`
    WHERE video_id IS NOT NULL
      AND song_id IS NOT NULL
)
WHERE rn = 1;


-- ==============================================================================
-- [3] VALIDASI: Cek hasil pembuatan kedua tabel
-- ==============================================================================

-- Cek jumlah baris dan sample data FCT_SPOTIFY_TRACK
SELECT 'fct_spotify_track' AS tabel, COUNT(*) AS total_rows FROM `peppy-gist-495807-s5.silver.fct_spotify_track`
UNION ALL
SELECT 'fct_youtube_video' AS tabel, COUNT(*) AS total_rows FROM `peppy-gist-495807-s5.silver.fct_youtube_video`;

-- Cek integritas relasi: lagu dari FCT yang TIDAK ada di DIM_SONG (orphan records)
SELECT 'Spotify orphans' AS check_name, COUNT(*) AS jumlah
FROM `peppy-gist-495807-s5.silver.fct_spotify_track` sp
WHERE NOT EXISTS (
    SELECT 1 FROM `peppy-gist-495807-s5.silver.dim_song` ds
    WHERE ds.song_id = sp.song_id
)
UNION ALL
SELECT 'YouTube orphans' AS check_name, COUNT(*) AS jumlah
FROM `peppy-gist-495807-s5.silver.fct_youtube_video` yt
WHERE NOT EXISTS (
    SELECT 1 FROM `peppy-gist-495807-s5.silver.dim_song` ds
    WHERE ds.song_id = yt.song_id
);
