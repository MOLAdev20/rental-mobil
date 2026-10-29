<script setup lang="js">
import {
  Car,
  CheckCircle2,
  CirclePlay,
  IdCard,
  LoaderCircle,
  TriangleAlert,
  XCircle,
} from "@lucide/vue";
import { computed, onMounted, ref } from "vue";
import StatusBadge from "../../components/StatusBadge.vue";
import {
  formatDateTime,
  getVehicleThumbnail,
  rentalDays,
  rupiah,
} from "../../lib/format";
import { KTP_BUCKET, supabase } from "../../lib/supabase-client";

const bookings = ref([]);
const loading = ref(true);
const errorMessage = ref("");
const actionId = ref("");
const filter = ref("PENDING");

const filters = [
  { value: "PENDING", label: "Perlu Verifikasi" },
  { value: "APPROVED", label: "Disetujui" },
  { value: "ACTIVE", label: "Sedang Disewa" },
  { value: "COMPLETED", label: "Selesai" },
  { value: "ALL", label: "Semua" },
];

const filteredBookings = computed(() =>
  filter.value === "ALL"
    ? bookings.value
    : bookings.value.filter((item) => item.status === filter.value),
);

const stats = computed(() => ({
  pending: bookings.value.filter((item) => item.status === "PENDING").length,
  approved: bookings.value.filter((item) => item.status === "APPROVED").length,
  active: bookings.value.filter((item) => item.status === "ACTIVE").length,
  completed: bookings.value.filter((item) => item.status === "COMPLETED").length,
}));

async function loadBookings() {
  loading.value = true;
  errorMessage.value = "";

  const { data, error } = await supabase
    .from("bookings")
    .select(
      "*, vehicle:vehicles(*, vehicle_images(id, image_url, created_at)), customer:users(id, email, full_name, phone_number, avatar_url), return_info:returns(*)",
    )
    .order("created_at", { ascending: false });

  if (error) {
    errorMessage.value = error.message;
  } else {
    bookings.value = data ?? [];
  }

  loading.value = false;
}

async function updateStatus(booking, status) {
  actionId.value = booking.id;
  errorMessage.value = "";

  const { error } = await supabase
    .from("bookings")
    .update({ status })
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

function rejectBooking(booking) {
  if (
    window.confirm(
      `Tolak pengajuan sewa ${booking.vehicle?.name ?? ""} dari ${booking.customer?.full_name ?? booking.customer?.email}?`,
    )
  ) {
    updateStatus(booking, "CANCELLED");
  }
}

onMounted(loadBookings);
</script>

<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-extrabold text-slate-800">
        Verifikasi Booking
      </h1>
      <p class="text-sm text-slate-500">
        Periksa dokumen identitas customer lalu setujui atau tolak pengajuan.
      </p>
    </div>

    <!-- Statistik ringkas -->
    <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <p class="text-xs text-slate-500">Perlu Verifikasi</p>
        <p class="text-2xl font-extrabold text-amber-600">{{ stats.pending }}</p>
      </div>
      <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <p class="text-xs text-slate-500">Disetujui</p>
        <p class="text-2xl font-extrabold text-blue-600">{{ stats.approved }}</p>
      </div>
      <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <p class="text-xs text-slate-500">Sedang Disewa</p>
        <p class="text-2xl font-extrabold text-indigo-600">{{ stats.active }}</p>
      </div>
      <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <p class="text-xs text-slate-500">Selesai</p>
        <p class="text-2xl font-extrabold text-emerald-600">
          {{ stats.completed }}
        </p>
      </div>
    </div>

    <p
      v-if="errorMessage"
      class="flex items-start gap-2 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
    >
      <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
      <span>{{ errorMessage }}</span>
    </p>

    <!-- Filter -->
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
      Memuat pengajuan...
    </div>

    <!-- Kosong -->
    <div
      v-else-if="filteredBookings.length === 0"
      class="rounded-2xl border border-dashed border-slate-300 bg-white py-16 text-center text-sm text-slate-500"
    >
      Tidak ada pengajuan pada kategori ini.
    </div>

    <!-- Daftar -->
    <div v-else class="space-y-4">
      <article
        v-for="booking in filteredBookings"
        :key="booking.id"
        class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
      >
        <div class="flex flex-wrap items-start justify-between gap-3 border-b border-slate-100 p-5">
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

        <div class="grid gap-4 p-5 sm:grid-cols-2">
          <!-- Data customer -->
          <div class="space-y-1">
            <p class="text-xs font-bold uppercase tracking-wide text-slate-400">
              Customer
            </p>
            <div class="flex items-center gap-3">
              <div
                class="flex h-10 w-10 items-center justify-center overflow-hidden rounded-full bg-blue-100 text-sm font-bold text-blue-700"
              >
                <img
                  v-if="booking.customer?.avatar_url"
                  :src="booking.customer.avatar_url"
                  :alt="booking.customer?.full_name ?? 'Customer'"
                  class="h-full w-full object-cover"
                />
                <span v-else>{{
                  (booking.customer?.full_name ?? booking.customer?.email ?? "?")
                    .charAt(0)
                    .toUpperCase()
                }}</span>
              </div>
              <div class="text-sm">
                <p class="font-semibold text-slate-700">
                  {{ booking.customer?.full_name ?? "Tanpa nama" }}
                </p>
                <p class="text-xs text-slate-500">
                  {{ booking.customer?.email }}
                </p>
                <p class="text-xs text-slate-500">
                  {{ booking.customer?.phone_number || "No. HP belum diisi" }}
                </p>
              </div>
            </div>
          </div>

          <!-- Jadwal & biaya -->
          <div class="grid grid-cols-2 gap-3 text-sm">
            <div>
              <p class="text-xs text-slate-400">Mulai</p>
              <p class="font-semibold text-slate-700">
                {{ formatDateTime(booking.start_date) }}
              </p>
            </div>
            <div>
              <p class="text-xs text-slate-400">Selesai</p>
              <p class="font-semibold text-slate-700">
                {{ formatDateTime(booking.end_date) }}
              </p>
            </div>
            <div>
              <p class="text-xs text-slate-400">Total</p>
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
            <div v-if="booking.notes" class="col-span-2">
              <p class="text-xs text-slate-400">Catatan customer</p>
              <p class="text-slate-700">{{ booking.notes }}</p>
            </div>
          </div>
        </div>

        <!-- Aksi -->
        <div class="flex flex-wrap gap-2 border-t border-slate-100 p-5 pt-4">
          <button
            type="button"
            class="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 px-3 py-2 text-xs font-semibold text-slate-600 transition-colors hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700"
            @click="openKtp(booking)"
          >
            <IdCard class="h-4 w-4" />
            Periksa KTP
          </button>

          <template v-if="booking.status === 'PENDING'">
            <button
              type="button"
              :disabled="actionId === booking.id"
              class="inline-flex items-center gap-1.5 rounded-xl bg-emerald-600 px-3 py-2 text-xs font-semibold text-white transition-colors hover:bg-emerald-700 disabled:opacity-60"
              @click="updateStatus(booking, 'APPROVED')"
            >
              <CheckCircle2 class="h-4 w-4" />
              Setujui
            </button>
            <button
              type="button"
              :disabled="actionId === booking.id"
              class="inline-flex items-center gap-1.5 rounded-xl border border-red-200 px-3 py-2 text-xs font-semibold text-red-600 transition-colors hover:bg-red-50 disabled:opacity-60"
              @click="rejectBooking(booking)"
            >
              <XCircle class="h-4 w-4" />
              Tolak
            </button>
          </template>

          <button
            v-if="booking.status === 'APPROVED'"
            type="button"
            :disabled="actionId === booking.id"
            class="inline-flex items-center gap-1.5 rounded-xl bg-indigo-600 px-3 py-2 text-xs font-semibold text-white transition-colors hover:bg-indigo-700 disabled:opacity-60"
            @click="updateStatus(booking, 'ACTIVE')"
          >
            <CirclePlay class="h-4 w-4" />
            Serahkan Kendaraan (Aktif)
          </button>

          <RouterLink
            v-if="booking.status === 'ACTIVE'"
            :to="{ name: 'admin-returns' }"
            class="inline-flex items-center gap-1.5 rounded-xl bg-slate-800 px-3 py-2 text-xs font-semibold text-white transition-colors hover:bg-slate-900"
          >
            Proses Pengembalian
          </RouterLink>
        </div>
      </article>
    </div>
  </div>
</template>
