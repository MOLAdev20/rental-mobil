<script setup>
import { BarChart3, Car, ClipboardList, Package, User } from "@lucide/vue";
import { computed } from "vue";
import { useRoute } from "vue-router";
import { useAuth } from "../composables/useAuth";

const route = useRoute();
const { isAdmin } = useAuth();

const links = computed(() =>
  isAdmin.value
    ? [
        { name: "admin-bookings", label: "Verifikasi", icon: ClipboardList },
        { name: "admin-vehicles", label: "Armada", icon: Car },
        { name: "admin-returns", label: "Kembali", icon: Package },
        { name: "admin-reports", label: "Laporan", icon: BarChart3 },
      ]
    : [
        { name: "catalog", label: "Beranda", icon: Car },
        { name: "orders", label: "Pesanan", icon: ClipboardList },
        { name: "profile", label: "Profil", icon: User },
      ],
);
</script>

<template>
  <nav
    class="fixed bottom-0 left-0 right-0 z-50 flex items-center justify-around border-t border-slate-200 bg-white px-4 py-2 md:hidden"
  >
    <RouterLink
      v-for="link in links"
      :key="link.name"
      :to="{ name: link.name }"
      class="flex flex-col items-center gap-1 px-3 text-[10px]"
      :class="
        route.name === link.name
          ? 'font-bold text-blue-600'
          : 'font-medium text-slate-400'
      "
    >
      <component :is="link.icon" class="h-6 w-6" />
      <span>{{ link.label }}</span>
    </RouterLink>
  </nav>
</template>
