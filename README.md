# RentalGo — Sistem Rental Kendaraan UMKM

freebuff --continue 2026-10-27T14-11-14.969Z
Aplikasi web mobile-first untuk rental mobil & motor, dibangun dengan **Vue 3 (Vite)**,
**Tailwind CSS v4**, **Vue Router 4**, dan **Supabase** (PostgreSQL + Auth + Storage).

Ada dua peran pengguna: **Customer** dan **Admin**.

## 1. Setup Supabase

1. Buat project baru di [supabase.com](https://supabase.com).
2. Import skema database: buka **SQL Editor → New query**, paste seluruh isi file di
   [`supabase/migrations/`](supabase/migrations) **secara berurutan** (`0001_init.sql`, lalu
   `0002_vehicle_images.sql`), jalankan **Run** pada masing-masing. File-file ini idempotent
   (aman dijalankan berulang). `0001_init.sql` membuat:
   - tabel `users`, `vehicles`, `bookings`, `returns` beserta ENUM & index
   - trigger `handle_new_user` (sinkronisasi otomatis dari `auth.users`)
   - RLS policy untuk 4 tabel + proteksi anti-eskalasi role
   - trigger anti double-booking & sinkronisasi status kendaraan
   - storage bucket `ktp-documents` (private) dan `vehicle-images` (public)
   - 6 unit kendaraan contoh

   `0002_vehicle_images.sql` menambahkan tabel `vehicle_images` untuk galeri foto kendaraan
   dengan jumlah dinamis (RLS: publik boleh membaca, hanya admin yang boleh menulis).

3. Aktifkan provider **Google** di **Authentication → Providers** (opsional, untuk login Google).
4. Tambahkan URL aplikasi ke **Authentication → URL Configuration** (mis. `http://localhost:5173`
   dan `http://localhost:5173/dashboard`).

## 2. Environment

```bash
cp .env.example .env
```

Isi `.env`:

| Variabel                 | Sumber                                              |
| :----------------------- | :-------------------------------------------------- |
| `VITE_SUPABASE_URL`      | Supabase → Project Settings → API → Project URL     |
| `VITE_SUPABASE_ANON_KEY` | Supabase → Project Settings → API → anon/public key |
| `VITE_APP_URL`           | URL aplikasi, mis. `http://localhost:5173`          |

## 3. Menjalankan

```bash
npm install
npm run dev      # development
npm run build    # production build
```

## 4. Menjadikan akun sebagai Admin

Daftar/login dulu lewat aplikasi, lalu jalankan dari SQL Editor:

```sql
update public.users set role = 'ADMIN' where email = 'email-kamu@gmail.com';
```

## 5. Alur Aplikasi

**Customer**

| Route           | Fungsi                                                           |
| :-------------- | :--------------------------------------------------------------- |
| `/auth`         | Masuk/daftar via Google atau email + password                    |
| `/dashboard`    | Katalog armada, pencarian, filter mobil/motor, banner sewa aktif |
| `/vehicles/:id` | Detail kendaraan + galeri foto (interior, kabin, kondisi unit)   |
| `/booking/:id`  | Pilih tanggal, cek ketersediaan, upload KTP/SIM, ajukan sewa     |
| `/orders`       | Tracking status pesanan, timer sewa aktif, pembatalan            |

**Admin**

| Route             | Fungsi                                                          |
| :---------------- | :-------------------------------------------------------------- |
| `/admin/bookings` | Verifikasi pengajuan, periksa KTP, setujui/tolak, serahkan unit |
| `/admin/vehicles` | CRUD armada: tarif harian, status, foto utama, dan galeri foto  |
| `/admin/returns`  | Proses pengembalian, catat denda telat & biaya kerusakan        |

### Status booking

`PENDING` → `APPROVED` → `ACTIVE` → `COMPLETED` (atau `CANCELLED`).
Status kendaraan (`AVAILABLE` / `BOOKED` / `MAINTENANCE`) disinkronkan otomatis
oleh trigger database saat status booking berubah.
