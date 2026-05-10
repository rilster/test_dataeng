-- ==============================================================================
-- SILVER -> GOLD (DATAMART) LAYER QUERY
-- Project  : Music Data Warehouse
-- Tabel    : gold.dm_music_catalog
-- Tujuan   :
--   Membuat tabel Datamart siap-analisis yang menggabungkan DIM_SONG (katalog),
--   FCT_SPOTIFY_TRACK (metadata & ISRC), FCT_YOUTUBE_VIDEO (video metadata),
--   serta menghasilkan ringkasan per lagu lengkap dengan agregasi kolom-kolom
--   kunci untuk keperluan Royalty & Reporting.
-- Granularity: 1 baris = 1 Song Code (Lagu Unik)
-- ==============================================================================

CREATE OR REPLACE TABLE `peppy-gist-495807-s5.gold.dm_music_catalog`
PARTITION BY DATE(created_at)
OPTIONS (
    description = "Datamart layer: Ringkasan katalog lagu yang sudah diperkaya data Spotify"
)
AS

WITH

-- CTE 1: Base Dimension dari katalog internal
base_catalog AS (
    SELECT
        song_id                         AS song_code,
        title                           AS song_title,
        -- Kolom song_writer & label belum ada di source saat ini.
        -- Perlu ditambahkan ke DIM_SONG jika tersedia di Google Sheets.
        CAST(NULL AS STRING)            AS song_writer,
        CAST(NULL AS STRING)            AS label,
        artist                          AS artist_name,
        created_at
    FROM `peppy-gist-495807-s5.silver.dim_song`
),

-- CTE 2: Agregasi data Spotify per lagu
-- Satu lagu bisa punya >1 ISRC (jika muncul di beberapa album/rilis)
spotify_agg AS (
    SELECT
        song_id,
        -- Ambil recording title pertama yang ditemukan Spotify (prioritas tertinggi)
        MAX(recording_title)                              AS recording_title,
        -- Gabungkan semua ISRC yang ditemukan menjadi satu string, dipisah koma
        STRING_AGG(DISTINCT isrc, ', ' ORDER BY isrc)    AS isrc_list,
        -- Gabungkan semua album yang berisi lagu ini
        STRING_AGG(DISTINCT album_name, ' | '
                   ORDER BY album_name)                   AS album_list,
        -- Informasi rilis: ambil tanggal rilis pertama (paling awal)
        MIN(release_date)                                 AS earliest_release_date,
        -- Label rekaman: ambil label pertama yang ditemukan (biasanya sama per album)
        MAX(label)                                        AS label,
        -- Jumlah track Spotify yang ditemukan untuk lagu ini
        COUNT(DISTINCT spotify_track_id)                  AS total_spotify_tracks
    FROM `peppy-gist-495807-s5.silver.fct_spotify_track`
    GROUP BY song_id
),

-- CTE 3: Agregasi data YouTube per lagu
youtube_agg AS (
    SELECT
        song_id,
        -- Jumlah video YouTube yang ditemukan untuk lagu ini
        COUNT(DISTINCT video_id)                                     AS total_youtube_videos,
        -- Gabungkan semua video_id menjadi satu string
        STRING_AGG(DISTINCT video_id, ', ' ORDER BY video_id)        AS video_id_list,
        -- Gabungkan semua judul video YouTube
        STRING_AGG(DISTINCT video_title, ' | '
                   ORDER BY video_title)                              AS video_title_list,
        -- Gabungkan semua channel yang mengupload
        STRING_AGG(DISTINCT channel_title, ', '
                   ORDER BY channel_title)                            AS channel_list,
        -- Tanggal publish video yang paling awal ditemukan
        MIN(publish_time)                                             AS earliest_publish_time
    FROM `peppy-gist-495807-s5.silver.fct_youtube_video`
    GROUP BY song_id
)

-- FINAL SELECT: Join semua CTE untuk membentuk tabel Datamart
SELECT
    -- === Identitas Lagu (dari Katalog Internal) ===
    bc.song_code,
    bc.song_title,
    bc.song_writer,                         -- NULL: perlu sumber data tambahan (MusicBrainz/internal)
    bc.artist_name,

    -- === Metadata dari Spotify ===
    sp.recording_title,                     -- Judul resmi sesuai Spotify
    sp.isrc_list             AS isrc,       -- Semua ISRC yang ditemukan (dipisah koma)
    sp.album_list,                          -- Daftar album yang memuat lagu ini
    sp.label,                               -- Label rekaman dari Spotify
    sp.earliest_release_date AS release_date,
    sp.total_spotify_tracks,

    -- === Metadata dari YouTube ===
    yt.total_youtube_videos,
    yt.video_id_list,                       -- Semua Video ID yang terkait lagu ini
    yt.video_title_list,                    -- Daftar judul video di YouTube
    yt.channel_list,                        -- Channel-channel yang mengupload
    yt.earliest_publish_time,               -- Tanggal pertama kali diupload ke YouTube

    -- === Status Ketersediaan ===
    CASE
        WHEN sp.song_id IS NOT NULL THEN 'FOUND'
        ELSE 'NOT FOUND'
    END AS spotify_status,
    CASE
        WHEN yt.song_id IS NOT NULL THEN 'FOUND'
        ELSE 'NOT FOUND'
    END AS youtube_status,

    -- === Audit ===
    bc.created_at

FROM base_catalog bc
LEFT JOIN spotify_agg sp
    ON bc.song_code = sp.song_id
LEFT JOIN youtube_agg yt
    ON bc.song_code = yt.song_id

ORDER BY bc.song_code;


-- ==============================================================================
-- [OPTIONAL] View Ringkasan Eksekutif — Hanya lagu yang ditemukan di kedua platform
-- Cocok untuk laporan royalti ke label atau distributor
-- ==============================================================================
CREATE OR REPLACE VIEW `peppy-gist-495807-s5.gold.vw_royalty_report`
AS
SELECT
    song_code,
    song_title,
    song_writer,
    artist_name,
    recording_title,
    isrc,
    label,
    album_list,
    release_date,
    total_spotify_tracks,
    total_youtube_videos,
    video_id_list,
    channel_list,
    earliest_publish_time
FROM `peppy-gist-495807-s5.gold.dm_music_catalog`
WHERE spotify_status = 'FOUND'
ORDER BY song_code;
