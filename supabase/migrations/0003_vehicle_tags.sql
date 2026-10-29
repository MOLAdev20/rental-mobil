-- ============================================================================
-- Rental Jaya — Kolom Tags Kendaraan
-- ----------------------------------------------------------------------------
-- CARA PAKAI:
--   Supabase Dashboard → SQL Editor → New query → paste seluruh file → Run.
--   (Jalankan setelah 0002_vehicle_images.sql.)
--
-- Menambahkan kolom tags ke tabel vehicles untuk informasi spesifikasi & fasilitas
-- seperti jenis transmisi, kapasitas kursi, AC, dll.
-- File ini idempotent — aman dijalankan berulang kali tanpa error.
-- ============================================================================

alter table public.vehicles
  add column if not exists tags text[] default '{}';

-- Inisialisasi tags untuk data awal jika masih kosong
update public.vehicles
set tags = array['Matic (Automatic)', '7 Kursi', 'AC Dingin', 'Lepas Kunci']
where name ilike '%Avanza%' and (tags is null or cardinality(tags) = 0);

update public.vehicles
set tags = array['Matic (Automatic)', '5 Kursi', 'AC Dingin', 'Irit BBM']
where name ilike '%Brio%' and (tags is null or cardinality(tags) = 0);

update public.vehicles
set tags = array['Matic (Automatic)', '7 Kursi', 'AC Dingin', 'Diesel / Solar']
where name ilike '%Xenia%' and (tags is null or cardinality(tags) = 0);

update public.vehicles
set tags = array['Matic', 'Include 2 Helm', 'Include Jas Hujan', 'Lepas Kunci']
where type = 'MOTORCYCLE' and (tags is null or cardinality(tags) = 0);
