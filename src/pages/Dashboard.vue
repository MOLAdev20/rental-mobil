<script setup lang="js">
import { CalendarClock, LoaderCircle, Search, TriangleAlert } from "@lucide/vue";
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import StatusBadge from "../components/StatusBadge.vue";
import VehicleCard from "../components/VehicleCard.vue";
import { useAuth } from "../composables/useAuth";
import { formatDateTime, getVehicleThumbnail } from "../lib/format";
import { supabase } from "../lib/supabase-client";

const router = useRouter();
const { session } = useAuth();

const vehicles = ref([]);
const activeBookings = ref([]);
const loading = ref(true);
const errorMessage = ref("");
const search = ref("");
const filter = ref("ALL"); // 'ALL' | 'CAR' | 'MOTORCYCLE'

const filters = [
  { value: "ALL", label: "Semua" },
  { value: "CAR", label: "🚘 Mobil" },
  { value: "MOTORCYCLE", label: "🛵 Motor" },
];

const filteredVehicles = computed(() => {
  const keyword = search.value.trim().toLowerCase();
  return vehicles.value.filter((vehicle) => {
    const matchType = filter.value === "ALL" || vehicle.type === filter.value;
    const matchKeyword =
      !keyword ||
      vehicle.name.toLowerCase().includes(keyword) ||
      (vehicle.license_plate ?? "").toLowerCase().includes(keyword);
    return matchType && matchKeyword;
  });
});

const activeRental = computed(
  () =>
    activeBookings.value.find((item) => item.status === "ACTIVE") ??
    activeBookings.value[0] ??
    null,
);

async function loadData() {
  loading.value = true;
  errorMessage.value = "";

  try {
    const userId = session.value?.user?.id;

    const vehiclesRequest = supabase
      .from("vehicles")
      .select("*, vehicle_images(id, image_url, created_at)")
      .order("name", { ascending: true });

    const bookingsRequest = userId
      ? supabase
          .from("bookings")
          .select("*, vehicle:vehicles(*, vehicle_images(id, image_url, created_at))")
          .eq("user_id", userId)
          .in("status", ["APPROVED", "ACTIVE"])
          .order("start_date", { ascending: true })
      : Promise.resolve({ data: [], error: null });

    const [vehiclesResult, bookingsResult] = await Promise.all([
      vehiclesRequest,
      bookingsRequest,
    ]);

    if (vehiclesResult.error) throw vehiclesResult.error;
    if (bookingsResult.error) throw bookingsResult.error;

    vehicles.value = vehiclesResult.data ?? [];
    activeBookings.value = bookingsResult.data ?? [];
  } catch (error) {
    errorMessage.value = error?.message ?? "Gagal memuat data kendaraan.";
  } finally {
    loading.value = false;
  }
}

function handleBook(vehicle) {
  router.push({ name: "booking", params: { vehicleId: vehicle.id } });
}

onMounted(loadData);
</script>

<template>
  <div class="space-y-6 sm:space-y-8">
    <!-- Banner sewa aktif -->
    <section
      v-if="activeRental"
      class="flex flex-col items-start justify-between gap-6 rounded-2xl bg-gradient-to-r from-blue-600 to-indigo-700 p-6 text-white shadow-lg md:flex-row md:items-center sm:p-8"
    >
      <div class="flex items-center gap-5">
        <div
          v-if="getVehicleThumbnail(activeRental.vehicle)"
          class="hidden h-24 w-32 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-white/20 bg-white/10 shadow-inner sm:flex"
        >
          <img
            :src="getVehicleThumbnail(activeRental.vehicle)"
            :alt="activeRental.vehicle?.name"
            class="h-full w-full object-cover"
          />
        </div>
        <div class="max-w-xl space-y-2">
          <span
            class="inline-block rounded-full bg-white/20 px-3 py-1 text-xs font-bold uppercase tracking-wider backdrop-blur-sm"
          >
            {{ activeRental.status === "ACTIVE" ? "Sewa Aktif" : "Menunggu Pengambilan" }}
          </span>
          <h1 class="text-2xl font-extrabold leading-tight sm:text-3xl">
            {{ activeRental.vehicle?.name ?? "Kendaraan" }}
          </h1>
          <p class="text-sm text-blue-100">
            Mulai {{ formatDateTime(activeRental.start_date) }} · Selesai
            {{ formatDateTime(activeRental.end_date) }}
          </p>
        </div>
      </div>

      <div
        class="w-full space-y-2 rounded-xl border border-white/20 bg-white/10 p-4 backdrop-blur-md md:w-80"
      >
        <div class="flex items-center gap-2 text-xs text-blue-100">
          <CalendarClock class="h-4 w-4" />
          <span>Batas Pengembalian</span>
        </div>
        <p class="text-sm font-bold">
          {{ formatDateTime(activeRental.end_date) }}
        </p>
        <RouterLink
          :to="{ name: 'orders' }"
          class="inline-block text-xs font-semibold underline underline-offset-2"
        >
          Lihat detail pesanan
        </RouterLink>
      </div>
    </section>

    <!-- Hero default -->
    <section
      v-else
      class="rounded-2xl bg-gradient-to-r from-blue-600 to-indigo-700 p-6 text-white shadow-lg sm:p-8"
    >
      <span
        class="inline-block rounded-full bg-white/20 px-3 py-1 text-xs font-bold uppercase tracking-wider backdrop-blur-sm"
      >
        Sewa Kendaraan Mudah &amp; Cepat
      </span>
      <h1 class="mt-2 text-2xl font-extrabold leading-tight sm:text-3xl">
        Cari Mobil atau Motor Untuk Perjalananmu
      </h1>
      <p class="mt-2 max-w-xl text-sm text-blue-100">
        Harga terjangkau, proses cepat tanpa ribet, dan armada selalu terawat.
      </p>
    </section>

    <!-- Pencarian & filter -->
    <section
      class="flex flex-col items-center justify-between gap-4 rounded-2xl border border-slate-200 bg-white p-4 shadow-sm sm:flex-row"
    >
      <div class="relative w-full sm:max-w-md">
        <Search class="absolute left-3 top-3 h-5 w-5 text-slate-400" />
        <input
          v-model="search"
          type="text"
          placeholder="Cari nama kendaraan (Avanza, NMAX...)"
          class="w-full rounded-xl border border-slate-200 py-2.5 pl-10 pr-4 text-sm text-slate-800 placeholder-slate-400 transition-all focus:border-blue-500 focus:outline-none focus:ring-2 focus:ring-blue-100"
        />
      </div>

      <div class="flex w-full items-center gap-2 sm:w-auto">
        <button
          v-for="option in filters"
          :key="option.value"
          type="button"
          class="flex-1 rounded-xl px-4 py-2 text-xs transition-colors sm:flex-none"
          :class="
            filter === option.value
              ? 'bg-blue-600 font-semibold text-white shadow-sm shadow-blue-500/20'
              : 'bg-slate-100 font-medium text-slate-600 hover:bg-slate-200'
          "
          @click="filter = option.value"
        >
          {{ option.label }}
        </button>
      </div>
    </section>

    <!-- Daftar armada -->
    <section class="space-y-4">
      <div class="flex items-center justify-between">
        <h2 class="text-lg font-bold text-slate-800">Daftar Armada</h2>
        <span class="text-xs font-semibold text-slate-500">
          Menampilkan {{ filteredVehicles.length }} Unit
        </span>
      </div>

      <!-- Loading -->
      <div
        v-if="loading"
        class="flex items-center justify-center gap-2 rounded-2xl border border-slate-200 bg-white py-16 text-sm text-slate-500"
      >
        <LoaderCircle class="h-5 w-5 animate-spin" />
        Memuat armada...
      </div>

      <!-- Error -->
      <div
        v-else-if="errorMessage"
        class="flex items-start gap-2 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
      >
        <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
        <span>{{ errorMessage }}</span>
      </div>

      <!-- Kosong -->
      <div
        v-else-if="filteredVehicles.length === 0"
        class="rounded-2xl border border-dashed border-slate-300 bg-white py-16 text-center text-sm text-slate-500"
      >
        Tidak ada kendaraan yang cocok dengan pencarian kamu.
      </div>

      <!-- Grid -->
      <div
        v-else
        class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
      >
        <VehicleCard
          v-for="vehicle in filteredVehicles"
          :key="vehicle.id"
          :vehicle="vehicle"
          @book="handleBook"
        />
      </div>
    </section>

    <!-- Ringkasan sewa aktif (mobile) -->
    <section v-if="activeRental" class="rounded-2xl border border-slate-200 bg-white p-5">
      <div class="flex items-center justify-between">
        <h3 class="text-sm font-bold text-slate-800">Status Sewa Kamu</h3>
        <StatusBadge :value="activeRental.status" />
      </div>
      <p class="mt-2 text-xs text-slate-500">
        {{ activeRental.vehicle?.name }} · berakhir
        {{ formatDateTime(activeRental.end_date) }}
      </p>
    </section>
  </div>
</template>
