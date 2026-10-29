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

  const { data, error } = await supabase
    .from("users")
    .select("*")
    .eq("id", user.id)
    .maybeSingle();

  if (error) {
    console.error("[auth] gagal memuat profil:", error.message);
    profile.value = null;
    return null;
  }

  if (!data) {
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

    profile.value = created ?? null;
    return profile.value;
  }

  profile.value = data;
  return data;
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
    signInWithEmail,
    signUpWithEmail,
    signInWithGoogle,
    signOut,
  };
}
