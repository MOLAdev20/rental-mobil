<script setup lang="js">
import {
  Car,
  CheckCircle2,
  Clock,
  IdCard,
  LoaderCircle,
  TriangleAlert,
} from "@lucide/vue";
import { computed, onMounted, onUnmounted, ref } from "vue";
import { useRoute } from "vue-router";
import StatusBadge from "../components/StatusBadge.vue";
import { useAuth } from "../composables/useAuth";
import {
  formatDateTime,
  formatDuration,
  getVehicleThumbnail,
  rentalDays,
  rupiah,
} from "../lib/format";
import { KTP_BUCKET, supabase } from "../lib/supabase-client";

const route = useRoute();
const { session } = useAuth();

const bookings = ref([]);
const loading = ref(true);
const errorMessage = ref("");
const infoMessage = ref(route.query.created === "1" ? "Pengajuan sewa berhasil dikirim. Menunggu verifikasi admin." : "");
const actionId = ref("");
const filter = ref("ALL");

const now = ref(Date.now());
let clock;

const filters = [
  { value: "ALL", label: "Semua" },
  { value: "PENDING", label: "Menunggu" },
  { value: "APPROVED", label: "Disetujui" },
  { value: "ACTIVE", label: "Aktif" },
  { value: "COMPLETED", label: "Selesai" },
];

const filteredBookings = computed(() =>
  filter.value === "ALL"
    ? bookings.value
    : bookings.value.filter((item) => item.status === filter.value),
);

function remainingLabel(booking) {
  const diff = new Date(booking.end_date).getTime() - now.value;
  if (diff > 0) return `Sisa waktu sewa: ${formatDuration(diff)}`;
  return `Terlambat ${formatDuration(diff)} dari jadwal kembali`;
}

function isOverdue(booking) {
  return (
    booking.status === "ACTIVE" &&
    new Date(booking.end_date).getTime() < now.value
  );
}

async function loadBookings() {
  loading.value = true;
  errorMessage.value = "";

  const { data, error } = await supabase
    .from("bookings")
    .select(
      "*, vehicle:vehicles(*, vehicle_images(id, image_url, created_at)), return_info:returns(*)",
    )
    .eq("user_id", session.value?.user?.id)
    .order("created_at", { ascending: false });

  if (error) {
    errorMessage.value = error.message;
  } else {
    bookings.value = data ?? [];
  }

  loading.value = false;
}

async function cancelBooking(booking) {
  const confirmed = window.confirm(
    "Batalkan pengajuan sewa kendaraan ini? Tindakan ini tidak bisa dibatalkan.",
  );
  if (!confirmed) return;

  actionId.value = booking.id;
  errorMessage.value = "";

  const { error } = await supabase
    .from("bookings")
    .update({ status: "CANCELLED" })
    .eq("id", booking.id);

  if (error) {
    errorMessage.value = error.message;
  } else {
    await loadBookings();
  }

  actionId.value = "";
}

async function openKtp(booking) {
  if (!booking.ktp_image_url) return;

  const { data, error } = await supabase.storage
    .from(KTP_BUCKET)
    .createSignedUrl(booking.ktp_image_url, 120);

  if (error) {
    errorMessage.value = error.message;
    return;
  }

  window.open(data.signedUrl, "_blank", "noopener");
}

onMounted(loadBookings);
onMounted(() => {
  clock = setInterval(() => {
    now.value = Date.now();
  }, 1000);
});
onUnmounted(() => clearInterval(clock));
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-xl font-extrabold text-slate-800">Pesanan Saya</h1>
        <p class="text-sm text-slate-500">
          Pantau status pengajuan dan masa sewa kendaraan kamu.
        </p>
      </div>
      <RouterLink
        :to="{ name: 'catalog' }"
        class="rounded-xl bg-blue-600 px-4 py-2 text-xs font-semibold text-white shadow-sm shadow-blue-500/20 transition-colors hover:bg-blue-700"
      >
        Sewa Kendaraan Baru
      </RouterLink>
    </div>

    <p
      v-if="infoMessage"
      class="flex items-start gap-2 rounded-2xl border border-emerald-200 bg-emerald-50 px-4 py-3 text-sm text-emerald-700"
    >
      <CheckCircle2 class="mt-0.5 h-4 w-4 shrink-0" />
      <span>{{ infoMessage }}</span>
    </p>

    <p
      v-if="errorMessage"
      class="flex items-start gap-2 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
    >
      <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
      <span>{{ errorMessage }}</span>
    </p>

    <!-- Filter status -->
    <div class="flex gap-2 overflow-x-auto pb-1">
      <button
        v-for="option in filters"
        :key="option.value"
        type="button"
        class="shrink-0 rounded-xl px-4 py-2 text-xs transition-colors"
        :class="
          filter === option.value
            ? 'bg-blue-600 font-semibold text-white shadow-sm shadow-blue-500/20'
            : 'bg-white font-medium text-slate-600 hover:bg-slate-200'
        "
        @click="filter = option.value"
      >
        {{ option.label }}
      </button>
    </div>

    <!-- Loading -->
    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 rounded-2xl border border-slate-200 bg-white py-16 text-sm text-slate-500"
    >
      <LoaderCircle class="h-5 w-5 animate-spin" />
      Memuat pesanan...
    </div>

    <!-- Kosong -->
    <div
      v-else-if="filteredBookings.length === 0"
      class="rounded-2xl border border-dashed border-slate-300 bg-white py-16 text-center text-sm text-slate-500"
    >
      Belum ada pesanan pada kategori ini.
    </div>

    <!-- Daftar pesanan -->
    <div v-else class="space-y-4">
      <article
        v-for="booking in filteredBookings"
        :key="booking.id"
        class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
      >
        <div class="flex items-start justify-between gap-3 border-b border-slate-100 p-5">
          <div class="flex items-center gap-3.5">
            <div
              class="flex h-14 w-20 shrink-0 items-center justify-center overflow-hidden rounded-xl border border-slate-200 bg-slate-100"
            >
              <img
                v-if="getVehicleThumbnail(booking.vehicle)"
                :src="getVehicleThumbnail(booking.vehicle)"
                :alt="booking.vehicle?.name"
                class="h-full w-full object-cover"
              />
              <Car v-else class="h-6 w-6 text-slate-300" />
            </div>
            <div>
              <h2 class="font-bold text-slate-800">
                {{ booking.vehicle?.name ?? "Kendaraan" }}
              </h2>
              <p class="text-xs text-slate-500">
                {{ booking.vehicle?.license_plate ?? "-" }} ·
                {{ rentalDays(booking.start_date, booking.end_date) }} hari
              </p>
            </div>
          </div>
          <StatusBadge :value="booking.status" />
        </div>

        <div class="grid gap-3 p-5 text-sm sm:grid-cols-2">
          <div>
            <p class="text-xs text-slate-400">Mulai Sewa</p>
            <p class="font-semibold text-slate-700">
              {{ formatDateTime(booking.start_date) }}
            </p>
          </div>
          <div>
            <p class="text-xs text-slate-400">Selesai Sewa</p>
            <p class="font-semibold text-slate-700">
              {{ formatDateTime(booking.end_date) }}
            </p>
          </div>
          <div>
            <p class="text-xs text-slate-400">Total Biaya</p>
            <p class="font-bold text-blue-600">
              {{ rupiah(booking.total_price) }}
            </p>
          </div>
          <div>
            <p class="text-xs text-slate-400">Diajukan</p>
            <p class="font-semibold text-slate-700">
              {{ formatDateTime(booking.created_at) }}
            </p>
          </div>
          <div v-if="booking.notes" class="sm:col-span-2">
            <p class="text-xs text-slate-400">Catatan</p>
            <p class="text-slate-700">{{ booking.notes }}</p>
          </div>
        </div>

        <!-- Timer sewa aktif -->
        <div
          v-if="booking.status === 'ACTIVE'"
          class="flex items-center gap-2 border-t px-5 py-3 text-xs font-semibold"
          :class="
            isOverdue(booking)
              ? 'border-red-100 bg-red-50 text-red-700'
              : 'border-indigo-100 bg-indigo-50 text-indigo-700'
          "
        >
          <Clock class="h-4 w-4" />
          <span>{{ remainingLabel(booking) }}</span>
        </div>

        <!-- Rincian pengembalian -->
        <div
          v-if="booking.return_info"
          class="space-y-2 border-t border-slate-100 bg-slate-50 px-5 py-4 text-xs"
        >
          <p class="font-bold uppercase tracking-wide text-slate-500">
            Rincian Pengembalian
          </p>
          <div class="flex justify-between text-slate-600">
            <span>Dikembalikan pada</span>
            <span class="font-semibold">{{
              formatDateTime(booking.return_info.return_date)
            }}</span>
          </div>
          <div class="flex justify-between text-slate-600">
            <span>Denda keterlambatan</span>
            <span class="font-semibold">{{
              rupiah(booking.return_info.late_fee)
            }}</span>
          </div>
          <div class="flex justify-between text-slate-600">
            <span>Biaya kerusakan</span>
            <span class="font-semibold">{{
              rupiah(booking.return_info.damage_fee)
            }}</span>
          </div>
          <div class="flex justify-between border-t border-slate-200 pt-2 text-slate-800">
            <span class="font-bold">Total akhir</span>
            <span class="font-extrabold text-blue-600">{{
              rupiah(booking.return_info.final_price)
            }}</span>
          </div>
          <p v-if="booking.return_info.admin_notes" class="text-slate-500">
            Catatan admin: {{ booking.return_info.admin_notes }}
          </p>
        </div>

        <div class="flex flex-wrap gap-2 border-t border-slate-100 p-5 pt-4">
          <button
            type="button"
            class="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 px-3 py-2 text-xs font-semibold text-slate-600 transition-colors hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700"
            @click="openKtp(booking)"
          >
            <IdCard class="h-4 w-4" />
            Lihat Dokumen KTP
          </button>

          <button
            v-if="['PENDING', 'APPROVED'].includes(booking.status)"
            type="button"
            :disabled="actionId === booking.id"
            class="inline-flex items-center gap-1.5 rounded-xl border border-red-200 px-3 py-2 text-xs font-semibold text-red-600 transition-colors hover:bg-red-50 disabled:opacity-60"
            @click="cancelBooking(booking)"
          >
            <LoaderCircle
              v-if="actionId === booking.id"
              class="h-4 w-4 animate-spin"
            />
            Batalkan Pesanan
          </button>
        </div>
      </article>
    </div>
  </div>
</template>
