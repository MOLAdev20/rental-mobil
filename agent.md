# Project Specification: UMKM Vehicle Rental System

This document serves as the primary context file for AI coding agents working on this repository. It defines the application flow, tech stack, database schema, and standard operating procedures for development.

---

## 1. Application Overview & Core Flow

The system is a modern, responsive, mobile-first Web Application for a vehicle (car and motorcycle) rental business (UMKM). It supports two distinct roles: **Customer** and **Admin**.

### A. Customer Flow

1. **Authentication**: Users log in via Google OAuth or Email/Password handled by Supabase Auth.
2. **Catalog Browsing**: Customers explore available vehicles, filter by category (Cars/Motorcycles), and search by name.
3. **Vehicle Detail & Photo Gallery**: Clicking a vehicle card opens its detail page (`/vehicles/:id`), where the customer browses the unit's photo gallery (exterior, interior, cabin, overall condition). The number of photos per vehicle is dynamic and managed by admins.
4. **Booking Process & Profile Prerequisite**:
   - Customer must complete their profile details (NIK, SIM number, KTP document photo, address, city, emergency contact) once before initiating a booking. If incomplete, customer is automatically redirected to `/profile`.
   - Customer selects a vehicle and picks rental dates/times without needing to re-upload ID/KTP for each transaction.
   - Submits booking request (Initial status: `PENDING`).
5. **Order Tracking**: Customer tracks booking statuses (`APPROVED`, `ACTIVE`, `COMPLETED`, `CANCELLED`) and views active rental timers on their dashboard.

### B. Admin Flow

1. **Dashboard & Fleet Management**:
   - CRUD operations on vehicles (add/edit unit, set daily rates, manage tags, change status to Available/Maintenance, view detailed fleet page `/admin/vehicles/:vehicleId` with complete rental history, stats, tags, and controls).
   - Manage each unit's photo gallery: upload any number of photos directly (interior, cabin, condition) and delete existing ones.
   - Vehicle thumbnails across catalogs, orders, bookings, returns, and vehicle details are dynamically derived from the first photo in the `vehicle_images` gallery (ordered by `created_at` ASC). If no photos exist, a placeholder/emoji is shown. Specific `vehicles.image_url` upload is deprecated.
2. **Booking Verification**:
   - Reviews incoming booking requests and inspects uploaded identity documents (KTP).
   - Approves or rejects booking requests.
3. **Rental & Return Lifecycle**:
   - Marks vehicles as `ACTIVE` upon handover.
   - Processes vehicle returns, records late fees or damages if any, and updates vehicle status back to `AVAILABLE`.
4. **Transaction & Rental Reports**:
   - Interactive report dashboard (`/admin/reports`) with Chart.js daily line chart (dual-axis: transaction count & daily revenue).
   - Date range filters (1 month ago, 1 week ago, 1 day ago, custom range) and status dropdown.
   - Comprehensive transaction table with unit info, customer contact, duration, total revenue, status, and export to CSV functionality.

---

## 2. Tech Stack & 3rd-Party Libraries

| Component              | Technology / Library                               | Purpose & Functionality                                                 |
| :--------------------- | :------------------------------------------------- | :---------------------------------------------------------------------- |
| **Framework**          | **Vue 3** (Vite, Composition API `<script setup>`) | Core frontend reactive framework.                                       |
| **Styling**            | **Tailwind CSS**                                   | Utility-first CSS framework for clean, mobile-first responsive UI.      |
| **Routing**            | **Vue Router 4**                                   | Client-side routing with navigation guards for role-based protection.   |
| **Backend / Database** | **Supabase (PostgreSQL)**                          | Managed relational database, Auth engine, and storage provider.         |
| **Auth Client**        | `@supabase/supabase-js`                            | Official SDK to query database, handle OAuth, and manage JWT sessions.  |
| **Icons**              | **Lucide Vue Next** / Heroicons                    | UI vector icons for clean mobile UX.                                    |
| **Date Utility**       | **date-fns** / **Day.js**                          | Date arithmetic, range checking, and duration calculations for rentals. |
| **Charting**           | **Chart.js**                                       | Line chart visualizations for daily transactions and rental revenue.    |

---

## 3. Database Schema Plan (Supabase PostgreSQL)

> **Schema changes are migration-first.** Every change must ship as a new, idempotent SQL file under `supabase/migrations/` (safe to paste into the Supabase SQL Editor multiple times). Never rely on manual dashboard edits.

```sql
-- 1. ENUM TYPES
CREATE TYPE user_role AS ENUM ('ADMIN', 'CUSTOMER');
CREATE TYPE vehicle_type AS ENUM ('CAR', 'MOTORCYCLE');
CREATE TYPE vehicle_status AS ENUM ('AVAILABLE', 'BOOKED', 'MAINTENANCE');
CREATE TYPE booking_status AS ENUM ('PENDING', 'APPROVED', 'ACTIVE', 'COMPLETED', 'CANCELLED');

-- 2. USERS TABLE (Extends auth.users for basic profile & role)
CREATE TABLE public.users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT,
  avatar_url TEXT,
  phone_number TEXT,
  role user_role DEFAULT 'CUSTOMER',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. DETAIL_USER TABLE (1-to-1 extension of public.users for rental verification details)
CREATE TABLE public.detail_user (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  nik TEXT,
  sim_number TEXT,
  ktp_image_url TEXT, -- Uploaded once in customer profile, used across all bookings
  address TEXT,
  city TEXT,
  emergency_contact_name TEXT,
  emergency_contact_phone TEXT,
  emergency_contact_relation TEXT,
  job_title TEXT,
  social_media TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. VEHICLES TABLE
CREATE TABLE public.vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type vehicle_type NOT NULL,
  license_plate TEXT UNIQUE NOT NULL,
  price_per_day NUMERIC(10, 2) NOT NULL,
  image_url TEXT, -- DEPRECATED: Thumbnail derived dynamically from first vehicle_images entry
  status vehicle_status DEFAULT 'AVAILABLE',
  description TEXT,
  tags TEXT[] DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. BOOKINGS TABLE
CREATE TABLE public.bookings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  vehicle_id UUID NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  start_date TIMESTAMPTZ NOT NULL,
  end_date TIMESTAMPTZ NOT NULL,
  total_price NUMERIC(10, 2) NOT NULL,
  status booking_status DEFAULT 'PENDING',
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. VEHICLE IMAGES TABLE (photo gallery, dynamic count per vehicle)
--    Files live in the `vehicle-images` bucket; storage_path is kept so the
--    admin UI can remove the object when a photo row is deleted.
CREATE TABLE public.vehicle_images (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  vehicle_id UUID NOT NULL REFERENCES public.vehicles(id) ON DELETE CASCADE,
  image_url TEXT NOT NULL,
  storage_path TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. RETURNS TABLE
CREATE TABLE public.returns (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id UUID NOT NULL REFERENCES public.bookings(id) ON DELETE CASCADE,
  return_date TIMESTAMPTZ DEFAULT NOW(),
  late_fee NUMERIC(10, 2) DEFAULT 0.00,
  damage_fee NUMERIC(10, 2) DEFAULT 0.00,
  final_price NUMERIC(10, 2) NOT NULL,
  admin_notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. AUTOMATIC USER CREATION TRIGGER FROM SUPABASE AUTH
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    NEW.raw_user_meta_data->>'full_name',
    NEW.raw_user_meta_data->>'avatar_url'
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

---

## 4. Storage Bucket Configuration

- **Bucket Name**: `ktp-documents` (Private)
- **Policy**:
  - `CUSTOMERS` can upload files to their own subfolders (`/ktp-documents/{user_id}/*`).
  - `ADMINS` have full read access to verify document authenticity.

- **Bucket Name**: `vehicle-images` (Public)
- **Policy**:
  - `ADMINS` can upload/update/delete vehicle photos (cover photo and gallery).
  - Everyone (including anonymous visitors) can read them, since the photos appear in the public catalog.
- **Naming convention**: `vehicles/{vehicle_id}/{timestamp}-{random}.{ext}` for gallery photos.

---

## 5. Development Guidelines for AI Agents

1. **Composition API**: Always use Vue 3 `<script setup>` with JavaScript or TypeScript.
2. **Environment Variables**: Store Supabase URL and Publishable Key in `.env` as `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY`.
3. **Mobile First Responsive Design**: Prioritize mobile view UX (`w-full max-w-md` wrappers or fluid grids), scaling cleanly to desktop screens using Tailwind's responsive prefixes (`sm:`, `md:`, `lg:`).
4. **State & Session Persistence**: Always check `supabase.auth.getSession()` on app load and enforce Vue Router navigation guards before entering protected routes like `/dashboard` or `/admin`.
5. **Schema Migrations**: Any database change (new table, column, policy, bucket) must be delivered as a standalone idempotent file in `supabase/migrations/`, named `NNNN_description.sql`, and appended to this document's schema plan.
6. **Row Level Security**: Every new table must have RLS enabled with explicit policies — public catalog data readable by `anon`/`authenticated`, writes restricted to `ADMINS` via `public.is_admin()`.
