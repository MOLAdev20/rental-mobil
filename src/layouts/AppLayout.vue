<script setup>
import { RouterView } from "vue-router";
import AppHeader from "../components/AppHeader.vue";
import BottomNav from "../components/BottomNav.vue";
</script>

<template>
  <div class="flex min-h-screen flex-col bg-slate-100">
    <AppHeader />

    <main
      class="mx-auto w-full max-w-7xl flex-1 px-4 py-6 pb-24 sm:px-6 sm:py-8 md:pb-8 lg:px-8"
    >
      <RouterView />
    </main>

    <BottomNav />

    <footer
      class="mt-12 hidden border-t border-slate-200 bg-white py-6 md:block"
    >
      <div class="mx-auto max-w-7xl px-4 text-center text-xs text-slate-400">
        &copy; 2026 RentalGo. Studi Kasus UMKM Rental Kendaraan.
      </div>
    </footer>
  </div>
</template>
