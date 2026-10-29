import { createClient } from "@supabase/supabase-js";

// Kredensial dibaca dari file .env (lihat .env.example untuk daftarnya).
// VITE_SUPABASE_PUBLISHABLE_KEY tetap didukung untuk kompatibilitas.
const env = import.meta.env;
const supabaseUrl = env.VITE_SUPABASE_URL;
const supabaseKey =
  env.VITE_SUPABASE_ANON_KEY || env.VITE_SUPABASE_PUBLISHABLE_KEY;

if (!supabaseUrl || !supabaseKey) {
  console.warn(
    "[supabase] VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY belum diisi. " +
      "Salin .env.example menjadi .env lalu isi kredensial project Supabase kamu.",
  );
}

export const supabase = createClient(supabaseUrl ?? "", supabaseKey ?? "", {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
  },
});

export const KTP_BUCKET = "ktp-documents";
export const VEHICLE_IMAGE_BUCKET = "vehicle-images";
