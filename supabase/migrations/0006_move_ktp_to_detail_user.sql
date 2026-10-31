-- ============================================================================
-- Rental Jaya — Pindahkan KTP Dokumen ke tabel detail_user
-- ----------------------------------------------------------------------------
-- CARA PAKAI:
--   Supabase Dashboard → SQL Editor → New query → paste seluruh file → Run.
--   (Jalankan setelah 0005_customer_profile_details.sql.)
--
-- File ini bersifat idempotent — aman dijalankan berulang kali tanpa error.
-- ============================================================================

-- 1. Tambahkan kolom ktp_image_url ke tabel public.detail_user
ALTER TABLE public.detail_user
  ADD COLUMN IF NOT EXISTS ktp_image_url TEXT;

COMMENT ON COLUMN public.detail_user.ktp_image_url IS 'Path berkas foto KTP di storage bucket ktp-documents';

-- 2. Hapus kolom ktp_image_url dari tabel public.bookings (tidak lagi diupload per-transaksi)
ALTER TABLE public.bookings
  DROP COLUMN IF EXISTS ktp_image_url;

-- 3. Pastikan bucket ktp-documents privat dan terdaftar
INSERT INTO storage.buckets (id, name, public)
VALUES ('ktp-documents', 'ktp-documents', false)
ON CONFLICT (id) DO UPDATE SET public = false;

-- 4. Policy RLS Storage ktp-documents untuk Customer & Admin
DROP POLICY IF EXISTS "ktp_upload_own" ON storage.objects;
CREATE POLICY "ktp_upload_own" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'ktp-documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "ktp_select_own_or_admin" ON storage.objects;
CREATE POLICY "ktp_select_own_or_admin" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'ktp-documents'
    AND (
      auth.uid()::text = (storage.foldername(name))[1]
      OR public.is_admin()
    )
  );

DROP POLICY IF EXISTS "ktp_update_own" ON storage.objects;
CREATE POLICY "ktp_update_own" ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'ktp-documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'ktp-documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

DROP POLICY IF EXISTS "ktp_delete_own_or_admin" ON storage.objects;
CREATE POLICY "ktp_delete_own_or_admin" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'ktp-documents'
    AND (
      auth.uid()::text = (storage.foldername(name))[1]
      OR public.is_admin()
    )
  );
