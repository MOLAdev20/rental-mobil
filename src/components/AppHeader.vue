<script setup>
import { BarChart3, Car, ClipboardList, LogOut, Package, User } from "@lucide/vue";
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuth } from "../composables/useAuth";

const route = useRoute();
const router = useRouter();
const { displayName, initials, isAdmin, profile, signOut } = useAuth();

function isActive(name) {
  return route.name === name;
}

function navClass(name) {
  return isActive(name)
    ? "border-blue-600 text-blue-600"
    : "border-transparent text-slate-600 hover:text-blue-600";
}

const navLinks = computed(() => {
  if (isAdmin.value) {
    return [
      { name: "admin-bookings", label: "Verifikasi Booking", icon: ClipboardList },
      { name: "admin-vehicles", label: "Armada", icon: Car },
      { name: "admin-returns", label: "Pengembalian", icon: Package },
      { name: "admin-reports", label: "Laporan Transaksi", icon: BarChart3 },
    ];
  }
  return [
    { name: "catalog", label: "Katalog Armada", icon: Car },
    { name: "orders", label: "Pesanan Saya", icon: ClipboardList },
    { name: "profile", label: "Profil Saya", icon: User },
  ];
});

async function handleLogout() {
  await signOut();
  router.push({ name: "auth" });
}
</script>

<template>
  <header class="sticky top-0 z-40 border-b border-slate-200 bg-white">
    <div
      class="mx-auto flex h-16 max-w-7xl items-center justify-between gap-4 px-4 sm:px-6 lg:px-8"
    >
      <!-- Brand -->
      <RouterLink :to="{ name: isAdmin ? 'admin-bookings' : 'catalog' }" class="flex items-center gap-3">
        <div
          class="flex h-10 w-10 items-center justify-center rounded-xl bg-blue-600 text-white shadow-md shadow-blue-500/20"
        >
          <Car class="h-6 w-6" />
        </div>
        <span class="text-lg font-extrabold tracking-tight text-slate-800">
          RentalGo
        </span>
      </RouterLink>

      <!-- Navigasi desktop -->
      <nav
        class="hidden items-center gap-6 text-sm font-semibold text-slate-600 md:flex"
      >
        <RouterLink
          v-for="link in navLinks"
          :key="link.name"
          :to="{ name: link.name }"
          class="flex items-center gap-1.5 border-b-2 py-5 transition-colors"
          :class="navClass(link.name)"
        >
          <component :is="link.icon" class="h-4 w-4" />
          {{ link.label }}
        </RouterLink>
      </nav>

      <!-- Info user + logout -->
      <div class="flex items-center gap-3">
        <!-- Khusus Customer: Link menuju halaman Profil Pribadi -->
        <RouterLink
          v-if="!isAdmin"
          :to="{ name: 'profile' }"
          title="Buka Profil Saya"
          class="flex items-center gap-3 rounded-xl p-1 transition-colors hover:bg-slate-50 cursor-pointer"
        >
          <div class="hidden text-right sm:block">
            <p class="text-xs text-slate-500">
              Selamat datang,
            </p>
            <p class="text-sm font-bold leading-tight text-slate-800">
              {{ displayName }}
            </p>
          </div>

          <div
            class="flex h-10 w-10 items-center justify-center overflow-hidden rounded-full border-2 border-blue-600 bg-blue-100 text-sm font-bold text-blue-700"
          >
            <img
              v-if="profile?.avatar_url"
              :src="profile.avatar_url"
              :alt="displayName"
              class="h-full w-full object-cover"
            />
            <span v-else>{{ initials }}</span>
          </div>
        </RouterLink>

        <!-- Khusus Admin: Identitas Administrator (Non-clickable, tidak ada fitur isi data pribadi) -->
        <div
          v-else
          class="flex items-center gap-3 rounded-xl p-1"
        >
          <div class="hidden text-right sm:block">
            <span class="inline-block rounded-md bg-amber-100 px-2 py-0.5 text-[10px] font-bold text-amber-800 uppercase tracking-wide">
              Administrator
            </span>
            <p class="text-sm font-bold leading-tight text-slate-800">
              {{ displayName }}
            </p>
          </div>

          <div
            class="flex h-10 w-10 items-center justify-center overflow-hidden rounded-full border-2 border-amber-500 bg-amber-100 text-sm font-bold text-amber-800"
            title="Administrator"
          >
            <img
              v-if="profile?.avatar_url"
              :src="profile.avatar_url"
              :alt="displayName"
              class="h-full w-full object-cover"
            />
            <span v-else>{{ initials }}</span>
          </div>
        </div>

        <button
          type="button"
          title="Keluar"
          class="rounded-xl border border-slate-200 p-2 text-slate-500 transition-colors hover:border-red-200 hover:bg-red-50 hover:text-red-600 cursor-pointer"
          @click="handleLogout"
        >
          <LogOut class="h-5 w-5" />
        </button>
      </div>
    </div>
  </header>
</template>
