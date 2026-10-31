-- ============================================================================
-- Rental Jaya — Tabel detail_user (Detail Profil Customer / Penyewa)
-- ----------------------------------------------------------------------------
-- CARA PAKAI:
--   Supabase Dashboard → SQL Editor → New query → paste seluruh file → Run.
--   (Jalankan setelah 0004_deprecate_image_url.sql.)
--
-- Membuat tabel terpisah public.detail_user yang berelasi 1-to-1 dengan public.users.
-- Data umum pengguna seperti nama & no hp tetap di public.users,
-- sedangkan detail kependudukan, SIM, domisili, dan kontak darurat disimpan di detail_user.
--
-- File ini bersifat idempotent — aman dijalankan berulang kali tanpa error.
-- ============================================================================

create table if not exists public.detail_user (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references public.users (id) on delete cascade,
  nik text,
  sim_number text,
  address text,
  city text,
  emergency_contact_name text,
  emergency_contact_phone text,
  emergency_contact_relation text,
  job_title text,
  social_media text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists detail_user_user_id_idx on public.detail_user (user_id);

-- Komentar dokumentasi
comment on table public.detail_user is 'Informasi detail identitas dan kontak darurat pelanggan/penyewa rental';
comment on column public.detail_user.user_id is 'Relasi ke public.users(id)';
comment on column public.detail_user.nik is 'Nomor Induk Kependudukan (KTP) 16 digit';
comment on column public.detail_user.sim_number is 'Nomor Surat Izin Mengemudi (SIM A/C)';
comment on column public.detail_user.address is 'Alamat lengkap domisili saat ini';
comment on column public.detail_user.city is 'Kota / Kabupaten domisili';
comment on column public.detail_user.emergency_contact_name is 'Nama lengkap kontak darurat kerabat';
comment on column public.detail_user.emergency_contact_phone is 'Nomor telepon kontak darurat';
comment on column public.detail_user.emergency_contact_relation is 'Hubungan kerabat kontak darurat';
comment on column public.detail_user.job_title is 'Pekerjaan / Instansi penyewa';
comment on column public.detail_user.social_media is 'Akun media sosial penyewa';

-- ============================================================================
-- ROW LEVEL SECURITY (RLS)
-- ============================================================================
alter table public.detail_user enable row level security;

-- 1. SELECT: Pemilik data atau Admin
drop policy if exists "detail_user_select_own_or_admin" on public.detail_user;
create policy "detail_user_select_own_or_admin" on public.detail_user
  for select to authenticated
  using (auth.uid() = user_id or public.is_admin());

-- 2. INSERT: Customer hanya dapat menginput data untuk user_id miliknya sendiri
drop policy if exists "detail_user_insert_own" on public.detail_user;
create policy "detail_user_insert_own" on public.detail_user
  for insert to authenticated
  with check (auth.uid() = user_id);

-- 3. UPDATE: Pemilik data atau Admin
drop policy if exists "detail_user_update_own_or_admin" on public.detail_user;
create policy "detail_user_update_own_or_admin" on public.detail_user
  for update to authenticated
  using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());

-- 4. DELETE: Pemilik data atau Admin
drop policy if exists "detail_user_delete_own_or_admin" on public.detail_user;
create policy "detail_user_delete_own_or_admin" on public.detail_user
  for delete to authenticated
  using (auth.uid() = user_id or public.is_admin());

-- ============================================================================
-- GRANT PERMISSIONS
-- ============================================================================
grant select, insert, update, delete on public.detail_user to authenticated;
