import { computed, ref } from "vue";
import { supabase } from "../lib/supabase-client";

// State disimpan di level modul supaya dipakai bersama oleh semua komponen
// (pengganti Pinia tanpa menambah dependency baru).
const session = ref(null);
const profile = ref(null);
const loading = ref(true);

let readyPromise = null;
let listenerAttached = false;

function appUrl() {
  return import.meta.env.VITE_APP_URL || window.location.origin;
}

async function refreshProfile() {
  const user = session.value?.user;
  if (!user) {
    profile.value = null;
    return null;
  }

  const [userRes, detailRes] = await Promise.all([
    supabase.from("users").select("*").eq("id", user.id).maybeSingle(),
    supabase.from("detail_user").select("*").eq("user_id", user.id).maybeSingle(),
  ]);

  if (userRes.error) {
    console.error("[auth] gagal memuat profil:", userRes.error.message);
    profile.value = null;
    return null;
  }

  let baseUser = userRes.data;
  if (!baseUser) {
    // Self-heal: jaga-jaga kalau trigger handle_new_user belum sempat jalan.
    const { data: created, error: insertError } = await supabase
      .from("users")
      .insert({
        id: user.id,
        email: user.email || `${user.id}@no-email.local`,
        full_name:
          user.user_metadata?.full_name || user.user_metadata?.name || null,
        avatar_url: user.user_metadata?.avatar_url || null,
      })
      .select()
      .maybeSingle();

    if (insertError) {
      console.error("[auth] gagal membuat profil:", insertError.message);
      profile.value = null;
      return null;
    }
    baseUser = created;
  }

  const detail = detailRes.data ?? null;

  profile.value = {
    ...baseUser,
    detail_user: detail,
    // Flatten detail_user ke root profile untuk kemudahan akses
    nik: detail?.nik ?? null,
    sim_number: detail?.sim_number ?? null,
    ktp_image_url: detail?.ktp_image_url ?? null,
    address: detail?.address ?? null,
    city: detail?.city ?? null,
    emergency_contact_name: detail?.emergency_contact_name ?? null,
    emergency_contact_phone: detail?.emergency_contact_phone ?? null,
    emergency_contact_relation: detail?.emergency_contact_relation ?? null,
    job_title: detail?.job_title ?? null,
    social_media: detail?.social_media ?? null,
  };

  return profile.value;
}

async function bootstrap() {
  const { data } = await supabase.auth.getSession();
  session.value = data.session ?? null;
  if (session.value) await refreshProfile();
  loading.value = false;

  if (!listenerAttached) {
    listenerAttached = true;
    supabase.auth.onAuthStateChange((_event, newSession) => {
      session.value = newSession ?? null;

      if (!newSession) {
        profile.value = null;
        return;
      }

      // Jangan await panggilan Supabase langsung di dalam callback ini.
      const needsProfile =
        !profile.value || profile.value.id !== newSession.user.id;
      if (needsProfile) setTimeout(refreshProfile, 0);
    });
  }
}

export function useAuth() {
  if (!readyPromise) readyPromise = bootstrap();

  const isAuthenticated = computed(() => Boolean(session.value));
  const isAdmin = computed(() => profile.value?.role === "ADMIN");
  const displayName = computed(
    () =>
      profile.value?.full_name ||
      session.value?.user?.user_metadata?.full_name ||
      session.value?.user?.email?.split("@")[0] ||
      "Pengguna",
  );
  const initials = computed(() =>
    displayName.value
      .split(" ")
      .filter(Boolean)
      .slice(0, 2)
      .map((part) => part[0]?.toUpperCase() ?? "")
      .join(""),
  );

  async function signInWithEmail(email, password) {
    const { error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });
    if (error) throw error;
    await refreshProfile();
    return profile.value;
  }

  async function signUpWithEmail({ email, password, fullName }) {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: { full_name: fullName },
        emailRedirectTo: `${appUrl()}/dashboard`,
      },
    });
    if (error) throw error;

    // Kalau konfirmasi email dimatikan, session langsung terbentuk.
    if (data.session) {
      session.value = data.session;
      await refreshProfile();
    }
    return data;
  }

  async function signInWithGoogle() {
    const { error } = await supabase.auth.signInWithOAuth({
      provider: "google",
      options: { redirectTo: `${appUrl()}/dashboard` },
    });
    if (error) throw error;
  }

  async function updateProfile(payload = {}) {
    const user = session.value?.user;
    if (!user) throw new Error("Sesi login tidak ditemukan.");

    // Data pribadi rental hanya diperuntukkan bagi customer / non-admin
    if (profile.value?.role === "ADMIN") {
      throw new Error("Akun Administrator tidak dapat mengisi data pribadi penyewa.");
    }

    // Pisahkan field untuk tabel users dan tabel detail_user
    const userKeys = ["full_name", "phone_number", "avatar_url"];
    const detailKeys = [
      "nik",
      "sim_number",
      "ktp_image_url",
      "address",
      "city",
      "emergency_contact_name",
      "emergency_contact_phone",
      "emergency_contact_relation",
      "job_title",
      "social_media",
    ];

    const userUpdates = {};
    const detailUpdates = {};

    for (const [k, v] of Object.entries(payload)) {
      if (userKeys.includes(k)) {
        userUpdates[k] = v;
      } else if (detailKeys.includes(k)) {
        detailUpdates[k] = v;
      }
    }

    // 1. Simpan perubahan ke tabel public.users jika ada
    if (Object.keys(userUpdates).length > 0) {
      const { error: userErr } = await supabase
        .from("users")
        .update(userUpdates)
        .eq("id", user.id);
      if (userErr) throw userErr;
    }

    // 2. Simpan/Upsert perubahan ke tabel public.detail_user jika ada
    if (Object.keys(detailUpdates).length > 0) {
      const { error: detailErr } = await supabase
        .from("detail_user")
        .upsert(
          {
            user_id: user.id,
            ...detailUpdates,
            updated_at: new Date().toISOString(),
          },
          { onConflict: "user_id" },
        );
      if (detailErr) throw detailErr;
    }

    // Refresh state profile lokal
    await refreshProfile();
    return profile.value;
  }

  async function signOut() {
    await supabase.auth.signOut();
    session.value = null;
    profile.value = null;
  }

  return {
    session,
    profile,
    loading,
    isAuthenticated,
    isAdmin,
    displayName,
    initials,
    ready: () => readyPromise,
    refreshProfile,
    updateProfile,
    signInWithEmail,
    signUpWithEmail,
    signInWithGoogle,
    signOut,
  };
}
