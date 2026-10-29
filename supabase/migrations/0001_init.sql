-- ============================================================================
-- Rental Jaya — Skema Awal (UMKM Vehicle Rental System)
-- ----------------------------------------------------------------------------
-- CARA PAKAI (paling cepat):
--   1. Buka https://supabase.com/dashboard → pilih project kamu
--   2. Menu "SQL Editor" → "New query"
--   3. Paste SELURUH isi file ini → klik "Run"
--
-- Alternatif via Supabase CLI:
--   supabase link --project-ref <project-ref>
--   supabase db push
--
-- File ini idempotent — aman dijalankan berulang kali tanpa error.
-- Isi: ENUM types, tabel, trigger, RLS policy, storage bucket, data contoh.
-- ============================================================================


-- ============================================================================
-- 1. ENUM TYPES
-- ============================================================================
do $$
begin
  if not exists (select 1 from pg_type where typname = 'user_role') then
    create type public.user_role as enum ('ADMIN', 'CUSTOMER');
  end if;

  if not exists (select 1 from pg_type where typname = 'vehicle_type') then
    create type public.vehicle_type as enum ('CAR', 'MOTORCYCLE');
  end if;

  if not exists (select 1 from pg_type where typname = 'vehicle_status') then
    create type public.vehicle_status as enum ('AVAILABLE', 'BOOKED', 'MAINTENANCE');
  end if;

  if not exists (select 1 from pg_type where typname = 'booking_status') then
    create type public.booking_status as enum ('PENDING', 'APPROVED', 'ACTIVE', 'COMPLETED', 'CANCELLED');
  end if;
end
$$;


-- ============================================================================
-- 2. TABEL: public.users (extends auth.users)
-- ============================================================================
create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  email text unique not null,
  full_name text,
  avatar_url text,
  phone_number text,
  role public.user_role not null default 'CUSTOMER',
  created_at timestamptz not null default now()
);


-- ============================================================================
-- 3. HELPER: cek apakah user yang sedang login adalah ADMIN
--    SECURITY DEFINER supaya tidak memicu rekursi RLS pada tabel users.
--    Wajib didefinisikan SETELAH tabel users dibuat (body fungsi SQL divalidasi
--    saat CREATE FUNCTION).
-- ============================================================================
create or replace function public.is_admin(user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1
    from public.users
    where id = user_id
      and role = 'ADMIN'
  );
$$;


-- ============================================================================
-- 4. TABEL: public.vehicles
-- ============================================================================
create table if not exists public.vehicles (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type public.vehicle_type not null,
  license_plate text unique not null,
  price_per_day numeric(10, 2) not null check (price_per_day >= 0),
  image_url text,
  status public.vehicle_status not null default 'AVAILABLE',
  description text,
  created_at timestamptz not null default now()
);

create index if not exists vehicles_type_idx on public.vehicles (type);
create index if not exists vehicles_status_idx on public.vehicles (status);


-- ============================================================================
-- 5. TABEL: public.bookings
-- ============================================================================
create table if not exists public.bookings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users (id) on delete cascade,
  vehicle_id uuid not null references public.vehicles (id) on delete cascade,
  start_date timestamptz not null,
  end_date timestamptz not null,
  total_price numeric(10, 2) not null check (total_price >= 0),
  ktp_image_url text not null,
  status public.booking_status not null default 'PENDING',
  notes text,
  created_at timestamptz not null default now(),
  constraint bookings_date_range_check check (end_date > start_date)
);

create index if not exists bookings_user_idx on public.bookings (user_id);
create index if not exists bookings_vehicle_idx on public.bookings (vehicle_id, start_date, end_date);
create index if not exists bookings_status_idx on public.bookings (status);


-- ============================================================================
-- 6. TABEL: public.returns
-- ============================================================================
create table if not exists public.returns (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings (id) on delete cascade,
  return_date timestamptz not null default now(),
  late_fee numeric(10, 2) not null default 0.00 check (late_fee >= 0),
  damage_fee numeric(10, 2) not null default 0.00 check (damage_fee >= 0),
  final_price numeric(10, 2) not null check (final_price >= 0),
  admin_notes text,
  created_at timestamptz not null default now()
);

create index if not exists returns_booking_idx on public.returns (booking_id);


-- ============================================================================
-- 7. TRIGGER: otomatis membuat baris public.users saat user auth baru dibuat
-- ============================================================================
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  insert into public.users (id, email, full_name, avatar_url)
  values (
    new.id,
    coalesce(new.email, new.id::text || '@no-email.local'),
    coalesce(
      new.raw_user_meta_data ->> 'full_name',
      new.raw_user_meta_data ->> 'name'
    ),
    new.raw_user_meta_data ->> 'avatar_url'
  )
  on conflict (id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();


-- ============================================================================
-- 8. TRIGGER: cegah user biasa menaikkan role dirinya jadi ADMIN
-- ============================================================================
create or replace function public.prevent_role_escalation()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- auth.uid() null = dijalankan dari SQL Editor / service role, biarkan lewat.
  if new.role is distinct from old.role
     and auth.uid() is not null
     and not public.is_admin() then
    new.role := old.role;
  end if;

  return new;
end;
$$;

drop trigger if exists on_user_role_update on public.users;
create trigger on_user_role_update
  before update on public.users
  for each row execute function public.prevent_role_escalation();


-- ============================================================================
-- 9. TRIGGER: cegah booking bentrok (double booking) untuk kendaraan yang sama
-- ============================================================================
create or replace function public.check_booking_overlap()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.status = 'CANCELLED' then
    return new;
  end if;

  if exists (
    select 1
    from public.bookings b
    where b.vehicle_id = new.vehicle_id
      and b.id <> new.id
      and b.status in ('PENDING', 'APPROVED', 'ACTIVE')
      and b.start_date < new.end_date
      and new.start_date < b.end_date
  ) then
    raise exception 'Kendaraan sudah dibooking pada rentang tanggal tersebut'
      using errcode = 'P0001';
  end if;

  return new;
end;
$$;

drop trigger if exists on_booking_overlap on public.bookings;
create trigger on_booking_overlap
  before insert or update of vehicle_id, start_date, end_date, status on public.bookings
  for each row execute function public.check_booking_overlap();


-- ============================================================================
-- 10. TRIGGER: sinkronisasi status kendaraan dengan status booking
-- ============================================================================
create or replace function public.sync_vehicle_status()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Kalau booking dipindah ke unit lain, bebaskan unit lama.
  if tg_op = 'UPDATE' and new.vehicle_id <> old.vehicle_id then
    update public.vehicles
       set status = 'AVAILABLE'
     where id = old.vehicle_id
       and status = 'BOOKED'
       and not exists (
         select 1 from public.bookings b
         where b.vehicle_id = old.vehicle_id
           and b.status in ('APPROVED', 'ACTIVE')
       );
  end if;

  if new.status in ('APPROVED', 'ACTIVE') then
    update public.vehicles
       set status = 'BOOKED'
     where id = new.vehicle_id
       and status <> 'MAINTENANCE';
  elsif new.status in ('COMPLETED', 'CANCELLED') then
    if not exists (
      select 1 from public.bookings b
      where b.vehicle_id = new.vehicle_id
        and b.id <> new.id
        and b.status in ('APPROVED', 'ACTIVE')
    ) then
      update public.vehicles
         set status = 'AVAILABLE'
       where id = new.vehicle_id
         and status = 'BOOKED';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists on_booking_status_sync on public.bookings;
create trigger on_booking_status_sync
  after insert or update of status, vehicle_id on public.bookings
  for each row execute function public.sync_vehicle_status();


-- ============================================================================
-- 11. ROW LEVEL SECURITY
-- ============================================================================
alter table public.users    enable row level security;
alter table public.vehicles enable row level security;
alter table public.bookings enable row level security;
alter table public.returns  enable row level security;

-- --- 11a. users -------------------------------------------------------------
drop policy if exists "users_select_own_or_admin" on public.users;
create policy "users_select_own_or_admin" on public.users
  for select to authenticated
  using (auth.uid() = id or public.is_admin());

drop policy if exists "users_insert_self" on public.users;
create policy "users_insert_self" on public.users
  for insert to authenticated
  with check (auth.uid() = id and role = 'CUSTOMER');

drop policy if exists "users_update_own_or_admin" on public.users;
create policy "users_update_own_or_admin" on public.users
  for update to authenticated
  using (auth.uid() = id or public.is_admin())
  with check (auth.uid() = id or public.is_admin());

-- --- 11b. vehicles ----------------------------------------------------------
-- Katalog boleh dibaca siapa pun (termasuk pengunjung belum login).
drop policy if exists "vehicles_select_public" on public.vehicles;
create policy "vehicles_select_public" on public.vehicles
  for select to anon, authenticated
  using (true);

drop policy if exists "vehicles_admin_insert" on public.vehicles;
create policy "vehicles_admin_insert" on public.vehicles
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "vehicles_admin_update" on public.vehicles;
create policy "vehicles_admin_update" on public.vehicles
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "vehicles_admin_delete" on public.vehicles;
create policy "vehicles_admin_delete" on public.vehicles
  for delete to authenticated
  using (public.is_admin());

-- --- 11c. bookings ----------------------------------------------------------
drop policy if exists "bookings_select_own_or_admin" on public.bookings;
create policy "bookings_select_own_or_admin" on public.bookings
  for select to authenticated
  using (auth.uid() = user_id or public.is_admin());

-- Customer hanya boleh membuat booking untuk dirinya sendiri, status awal PENDING.
drop policy if exists "bookings_insert_own" on public.bookings;
create policy "bookings_insert_own" on public.bookings
  for insert to authenticated
  with check (auth.uid() = user_id and status = 'PENDING');

-- Customer boleh membatalkan booking miliknya sendiri.
drop policy if exists "bookings_cancel_own" on public.bookings;
create policy "bookings_cancel_own" on public.bookings
  for update to authenticated
  using (auth.uid() = user_id and status in ('PENDING', 'APPROVED'))
  with check (auth.uid() = user_id and status = 'CANCELLED');

-- Admin mengelola seluruh lifecycle booking.
drop policy if exists "bookings_admin_update" on public.bookings;
create policy "bookings_admin_update" on public.bookings
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());

drop policy if exists "bookings_admin_delete" on public.bookings;
create policy "bookings_admin_delete" on public.bookings
  for delete to authenticated
  using (public.is_admin());

-- --- 11d. returns -----------------------------------------------------------
drop policy if exists "returns_select_own_or_admin" on public.returns;
create policy "returns_select_own_or_admin" on public.returns
  for select to authenticated
  using (
    public.is_admin()
    or exists (
      select 1 from public.bookings b
      where b.id = returns.booking_id
        and b.user_id = auth.uid()
    )
  );

drop policy if exists "returns_admin_insert" on public.returns;
create policy "returns_admin_insert" on public.returns
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "returns_admin_update" on public.returns;
create policy "returns_admin_update" on public.returns
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());


-- ============================================================================
-- 12. STORAGE BUCKETS
--     ktp-documents   : private, hanya pemilik + admin yang bisa akses
--     vehicle-images  : public, hanya admin yang bisa upload/hapus
-- ============================================================================
insert into storage.buckets (id, name, public)
values ('ktp-documents', 'ktp-documents', false)
on conflict (id) do update set public = excluded.public;

insert into storage.buckets (id, name, public)
values ('vehicle-images', 'vehicle-images', true)
on conflict (id) do update set public = excluded.public;

-- --- 12a. ktp-documents -----------------------------------------------------
-- Customer upload ke folder miliknya sendiri: ktp-documents/{user_id}/...
drop policy if exists "ktp_insert_own_folder" on storage.objects;
create policy "ktp_insert_own_folder" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'ktp-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "ktp_select_own_or_admin" on storage.objects;
create policy "ktp_select_own_or_admin" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'ktp-documents'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
    )
  );

drop policy if exists "ktp_update_own_folder" on storage.objects;
create policy "ktp_update_own_folder" on storage.objects
  for update to authenticated
  using (
    bucket_id = 'ktp-documents'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "ktp_delete_own_folder" on storage.objects;
create policy "ktp_delete_own_folder" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'ktp-documents'
    and (
      (storage.foldername(name))[1] = auth.uid()::text
      or public.is_admin()
    )
  );

-- --- 12b. vehicle-images ----------------------------------------------------
drop policy if exists "vehicle_images_read_all" on storage.objects;
create policy "vehicle_images_read_all" on storage.objects
  for select to anon, authenticated
  using (bucket_id = 'vehicle-images');

drop policy if exists "vehicle_images_admin_write" on storage.objects;
create policy "vehicle_images_admin_write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'vehicle-images' and public.is_admin());

drop policy if exists "vehicle_images_admin_update" on storage.objects;
create policy "vehicle_images_admin_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'vehicle-images' and public.is_admin());

drop policy if exists "vehicle_images_admin_delete" on storage.objects;
create policy "vehicle_images_admin_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'vehicle-images' and public.is_admin());


-- ============================================================================
-- 13. GRANT (RLS tetap jadi penentu baris mana yang boleh diakses)
-- ============================================================================
grant usage on schema public to anon, authenticated;

grant select on public.vehicles to anon, authenticated;
grant insert, update, delete on public.vehicles to authenticated;

grant select, insert, update on public.users to authenticated;

grant select, insert, update, delete on public.bookings to authenticated;

grant select, insert, update on public.returns to authenticated;


-- ============================================================================
-- 14. DATA CONTOH (armada awal)
-- ============================================================================
insert into public.vehicles (name, type, license_plate, price_per_day, image_url, status, description)
values
  ('Toyota Avanza 2023', 'CAR', 'B 1234 RJY', 350000.00, null, 'AVAILABLE', 'Transmisi Matic • 7 Kursi • Bensin'),
  ('Honda Brio RS', 'CAR', 'B 5678 RJY', 280000.00, null, 'AVAILABLE', 'Transmisi Automatic • 5 Kursi'),
  ('Daihatsu Xenia 2022', 'CAR', 'B 9012 RJY', 320000.00, null, 'AVAILABLE', 'Transmisi Matic • 7 Kursi • Solar'),
  ('Yamaha NMAX 155', 'MOTORCYCLE', 'B 2345 RJY', 120000.00, null, 'AVAILABLE', 'Matic • Include 2 Helm & Jas Hujan'),
  ('Honda Vario 160', 'MOTORCYCLE', 'B 6789 RJY', 100000.00, null, 'AVAILABLE', 'Matic • Include 2 Helm'),
  ('Honda PCX 160', 'MOTORCYCLE', 'B 3456 RJY', 130000.00, null, 'MAINTENANCE', 'Matic • Sedang servis rutin')
on conflict (license_plate) do nothing;


-- ============================================================================
-- 15. CARA MENJADIKAN SEORANG USER SEBAGAI ADMIN
-- ----------------------------------------------------------------------------
-- Daftar/login dulu lewat aplikasi (Google atau email), lalu jalankan:
--
--   update public.users set role = 'ADMIN' where email = 'email-kamu@gmail.com';
--
-- Jalankan langsung dari SQL Editor (bukan dari aplikasi) supaya trigger
-- prevent_role_escalation tidak mengembalikan role ke CUSTOMER.
-- ============================================================================
