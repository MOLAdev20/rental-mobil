-- ============================================================================
-- Migration: 0004_deprecate_image_url.sql
-- Description:
--   Dokumentasi & adaptasi schema: thumbnail unit kendaraan tidak lagi
--   bergantung pada kolom spesifik `vehicles.image_url`.
--   Gambar thumbnail kini secara otomatis diambil dari baris pertama pada tabel
--   `public.vehicle_images` yang berelasi dengan kendaraan (diurutkan berdasarkan
--   created_at ASC). Jika tidak ada foto di vehicle_images, tidak ada foto yang
--   ditampilkan.
--
--   Kolom `image_url` pada `public.vehicles` dipertahankan sebagai nullable untuk
--   kompatibilitas backward tanpa memicu breaking change pada constraint database.
-- ============================================================================

-- Pastikan kolom image_url bersifat opsional/nullable jika sebelumnya memiliki constraint
ALTER TABLE public.vehicles
  ALTER COLUMN image_url DROP NOT NULL;

-- Komentar dokumentasi pada kolom vehicles.image_url
COMMENT ON COLUMN public.vehicles.image_url IS
  'DEPRECATED: Thumbnail kendaraan sekarang dibaca secara otomatis dari entri pertama di tabel vehicle_images (order by created_at ASC). Kolom ini tidak lagi wajib diisi.';
