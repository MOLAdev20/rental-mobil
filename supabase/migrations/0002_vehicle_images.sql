-- ============================================================================
-- Rental Jaya — Galeri Foto Kendaraan
-- ----------------------------------------------------------------------------
-- CARA PAKAI:
--   Supabase Dashboard → SQL Editor → New query → paste seluruh file → Run.
--   (Jalankan setelah 0001_init.sql.)
--
-- Satu kendaraan bisa punya berapa pun foto (interior, kabin, kondisi unit).
-- File fisik disimpan di bucket `vehicle-images` yang sudah dibuat pada
-- 0001_init.sql, sehingga tidak perlu bucket baru.
--
-- File ini idempotent — aman dijalankan berulang kali.
-- ============================================================================


-- ============================================================================
-- 1. TABEL: public.vehicle_images
-- ============================================================================
create table if not exists public.vehicle_images (
  id uuid primary key default gen_random_uuid(),
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  image_url text not null,
  -- Path objek di bucket `vehicle-images` (dipakai untuk hapus file di storage).
  -- Boleh null untuk foto lama yang hanya menyimpan URL.
  storage_path text,
  created_at timestamptz not null default now()
);

create index if not exists vehicle_images_vehicle_idx
  on public.vehicle_images (vehicle_id, created_at);


-- ============================================================================
-- 2. BACKFILL: pindahkan foto utama lama (vehicles.image_url) ke galeri
--    Dilewati kalau unit tersebut sudah punya minimal satu foto galeri.
-- ============================================================================
insert into public.vehicle_images (vehicle_id, image_url)
select v.id, v.image_url
from public.vehicles v
where v.image_url is not null
  and not exists (
    select 1 from public.vehicle_images vi where vi.vehicle_id = v.id
  );


-- ============================================================================
-- 3. ROW LEVEL SECURITY
-- ============================================================================
alter table public.vehicle_images enable row level security;

-- Katalog publik: semua orang boleh melihat foto kendaraan.
drop policy if exists "vehicle_images_select_public" on public.vehicle_images;
create policy "vehicle_images_select_public" on public.vehicle_images
  for select to anon, authenticated
  using (true);

-- Hanya admin yang boleh menambah / mengubah / menghapus foto.
drop policy if exists "vehicle_images_admin_insert" on public.vehicle_images;
create policy "vehicle_images_admin_insert" on public.vehicle_images
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "vehicle_images_admin_update" on public.vehicle_images;
create policy "vehicle_images_admin_update" on public.vehicle_images
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "vehicle_images_admin_delete" on public.vehicle_images;
create policy "vehicle_images_admin_delete" on public.vehicle_images
  for delete to authenticated
  using (public.is_admin());


-- ============================================================================
-- 4. GRANT (RLS tetap menentukan baris mana yang boleh diakses)
-- ============================================================================
grant select on public.vehicle_images to anon, authenticated;
grant insert, update, delete on public.vehicle_images to authenticated;
