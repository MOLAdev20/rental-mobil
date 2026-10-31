<script setup lang="js">
import {
  ArrowLeft,
  CalendarDays,
  CheckCircle2,
  IdCard,
  LoaderCircle,
  TriangleAlert,
  XCircle,
} from "@lucide/vue";
import { computed, onMounted, ref, watch } from "vue";
import { useRouter } from "vue-router";
import { useAuth } from "../composables/useAuth";
import {
  getVehicleThumbnail,
  isProfileComplete,
  rentalDays,
  rupiah,
  toIso,
  VEHICLE_TYPE,
} from "../lib/format";
import { supabase } from "../lib/supabase-client";

const props = defineProps({
  vehicleId: { type: String, required: true },
});

const router = useRouter();
const { session, profile, refreshProfile } = useAuth();

const vehicle = ref(null);
const loadingVehicle = ref(true);
const loadError = ref("");

const startLocal = ref("");
const endLocal = ref("");
const notes = ref("");

const availability = ref({ state: "idle", message: "" });
const submitting = ref(false);
const submitError = ref("");

const typeMeta = computed(() =>
  vehicle.value ? (VEHICLE_TYPE[vehicle.value.type] ?? {}) : {},
);

const days = computed(() => rentalDays(startLocal.value, endLocal.value));
const totalPrice = computed(() =>
  vehicle.value ? days.value * Number(vehicle.value.price_per_day) : 0,
);

const canSubmit = computed(
  () =>
    Boolean(vehicle.value) &&
    days.value > 0 &&
    availability.value.state !== "checking" &&
    availability.value.state !== "unavailable" &&
    !submitting.value,
);

function defaultSchedule() {
  const start = new Date();
  start.setMinutes(0, 0, 0);
  start.setHours(start.getHours() + 1);

  const end = new Date(start);
  end.setDate(end.getDate() + 1);

  const toLocal = (date) => {
    const offset = date.getTimezoneOffset();
    return new Date(date.getTime() - offset * 60000).toISOString().slice(0, 16);
  };

  startLocal.value = toLocal(start);
  endLocal.value = toLocal(end);
}

async function loadVehicle() {
  loadingVehicle.value = true;
  loadError.value = "";

  const { data, error } = await supabase
    .from("vehicles")
    .select("*, vehicle_images(id, image_url, created_at)")
    .eq("id", props.vehicleId)
    .maybeSingle();

  if (error) {
    loadError.value = error.message;
  } else if (!data) {
    loadError.value = "Kendaraan tidak ditemukan.";
  } else {
    vehicle.value = data;
  }

  loadingVehicle.value = false;
}

let availabilityToken = 0;

async function checkAvailability() {
  const start = toIso(startLocal.value);
  const end = toIso(endLocal.value);

  if (!start || !end) {
    availability.value = { state: "idle", message: "" };
    return "idle";
  }

  if (new Date(end) <= new Date(start)) {
    availability.value = {
      state: "invalid",
      message: "Tanggal selesai harus setelah tanggal mulai.",
    };
    return "invalid";
  }

  availability.value = { state: "checking", message: "Mengecek ketersediaan..." };
  const token = ++availabilityToken;

  const { data, error } = await supabase
    .from("bookings")
    .select("id")
    .eq("vehicle_id", props.vehicleId)
    .in("status", ["PENDING", "APPROVED", "ACTIVE"])
    .lt("start_date", end)
    .gt("end_date", start)
    .limit(1);

  if (token !== availabilityToken) return availability.value.state;

  if (error) {
    availability.value = { state: "error", message: error.message };
    return "error";
  }

  if (data?.length) {
    availability.value = {
      state: "unavailable",
      message:
        "Kendaraan sudah dibooking pada rentang tanggal tersebut. Silakan pilih tanggal lain.",
    };
    return "unavailable";
  }

  availability.value = {
    state: "available",
    message: "Kendaraan tersedia pada rentang tanggal tersebut.",
  };
  return "available";
}

watch([startLocal, endLocal], () => {
  if (startLocal.value && endLocal.value) checkAvailability();
});

async function handleSubmit() {
  submitError.value = "";

  if (!vehicle.value) return;
  if (days.value <= 0) {
    submitError.value = "Rentang tanggal sewa belum valid.";
    return;
  }
  if (new Date(startLocal.value).getTime() < Date.now() - 60000) {
    submitError.value = "Waktu mulai sewa tidak boleh di masa lalu.";
    return;
  }

  submitting.value = true;

  try {
    const userId = session.value?.user?.id;
    if (!userId) throw new Error("Sesi login tidak ditemukan, silakan login ulang.");

    // Pastikan profil pelanggan lengkap (termasuk KTP yang sudah diunggah di profil)
    if (!isProfileComplete(profile.value)) {
      router.push({
        name: "profile",
        query: { redirect: `/booking/${props.vehicleId}`, required: "1" },
      });
      return;
    }

    const state = await checkAvailability();
    if (state === "unavailable") {
      throw new Error(
        "Maaf, kendaraan sudah dibooking pada rentang tanggal tersebut.",
      );
    }
    if (state !== "available") {
      throw new Error("Rentang tanggal belum valid, periksa kembali.");
    }

    const { error: insertError } = await supabase.from("bookings").insert({
      user_id: userId,
      vehicle_id: vehicle.value.id,
      start_date: toIso(startLocal.value),
      end_date: toIso(endLocal.value),
      total_price: totalPrice.value,
      notes: notes.value.trim() || null,
      status: "PENDING",
    });

    if (insertError) throw insertError;

    router.push({ name: "orders", query: { created: "1" } });
  } catch (error) {
    submitError.value = error?.message ?? "Gagal membuat pengajuan sewa.";
  } finally {
    submitting.value = false;
  }
}

onMounted(async () => {
  await refreshProfile();
  if (!isProfileComplete(profile.value)) {
    router.replace({
      name: "profile",
      query: { redirect: `/booking/${props.vehicleId}`, required: "1" },
    });
    return;
  }

  defaultSchedule();
  await loadVehicle();
  if (vehicle.value?.status !== "AVAILABLE") {
    availability.value = {
      state: "unavailable",
      message: "Kendaraan ini sedang tidak tersedia untuk disewa.",
    };
  } else {
    await checkAvailability();
  }
});
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-6">
    <button
      type="button"
      class="inline-flex items-center gap-1.5 text-sm font-semibold text-slate-500 transition-colors hover:text-blue-600"
      @click="router.back()"
    >
      <ArrowLeft class="h-4 w-4" />
      Kembali ke katalog
    </button>

    <div
      v-if="loadingVehicle"
      class="flex items-center justify-center gap-2 rounded-2xl border border-slate-200 bg-white py-16 text-sm text-slate-500"
    >
      <LoaderCircle class="h-5 w-5 animate-spin" />
      Memuat detail kendaraan...
    </div>

    <div
      v-else-if="loadError"
      class="flex items-start gap-2 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
    >
      <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
      <span>{{ loadError }}</span>
    </div>

    <template v-else>
      <!-- Detail kendaraan -->
      <section
        class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
      >
        <div class="flex h-48 items-center justify-center bg-slate-100">
          <img
            v-if="getVehicleThumbnail(vehicle)"
            :src="getVehicleThumbnail(vehicle)"
            :alt="vehicle.name"
            class="h-full w-full object-cover"
          />
          <span v-else class="text-7xl">{{ typeMeta.emoji }}</span>
        </div>
        <div class="space-y-2 p-5">
          <span
            class="rounded bg-blue-50 px-2 py-0.5 text-[10px] font-bold uppercase text-blue-600"
          >
            {{ typeMeta.label }}
          </span>
          <h1 class="text-xl font-extrabold text-slate-800">
            {{ vehicle.name }}
          </h1>
          <p class="text-sm text-slate-500">
            {{ vehicle.description || vehicle.license_plate }}
          </p>
          <p class="text-base font-extrabold text-blue-600">
            {{ rupiah(vehicle.price_per_day) }}
            <span class="text-xs font-normal text-slate-400">/hari</span>
          </p>
        </div>
      </section>

      <!-- Informasi Penyewa Terverifikasi -->
      <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-sm space-y-3">
        <div class="flex items-center justify-between">
          <h2 class="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-slate-700">
            <IdCard class="h-4 w-4 text-blue-600" />
            Data Penyewa (Terverifikasi)
          </h2>
          <RouterLink
            :to="{ name: 'profile', query: { redirect: `/booking/${vehicleId}` } }"
            class="text-xs font-semibold text-blue-600 hover:underline cursor-pointer"
          >
            Ubah Data Profil
          </RouterLink>
        </div>
        <div class="grid grid-cols-2 gap-3 text-xs sm:grid-cols-4 pt-1">
          <div>
            <p class="text-slate-400">Nama Lengkap</p>
            <p class="font-bold text-slate-800 line-clamp-1">{{ profile?.full_name || "-" }}</p>
          </div>
          <div>
            <p class="text-slate-400">NIK KTP</p>
            <p class="font-mono font-bold text-slate-800">{{ profile?.nik || "-" }}</p>
          </div>
          <div>
            <p class="text-slate-400">No. WhatsApp</p>
            <p class="font-bold text-slate-800">{{ profile?.phone_number || "-" }}</p>
          </div>
          <div>
            <p class="text-slate-400">Nomor SIM</p>
            <p class="font-mono font-bold text-slate-800">{{ profile?.sim_number || "-" }}</p>
          </div>
        </div>
        <div class="border-t border-slate-100 pt-2.5 flex items-center justify-between text-xs">
          <span class="inline-flex items-center gap-1.5 font-medium text-emerald-700">
            <CheckCircle2 class="h-3.5 w-3.5 text-emerald-600" />
            Dokumen KTP asli telah tersimpan di profil Anda
          </span>
          <RouterLink
            :to="{ name: 'profile', query: { redirect: `/booking/${vehicleId}` } }"
            class="text-[11px] text-slate-500 hover:text-blue-600 hover:underline"
          >
            Perbarui KTP
          </RouterLink>
        </div>
      </section>

      <!-- Form booking -->
      <section class="space-y-5 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm">
        <h2 class="text-lg font-bold text-slate-800">Detail Penyewaan</h2>

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label
              for="start"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >Mulai Sewa</label
            >
            <div class="relative">
              <CalendarDays class="absolute left-3 top-3 h-4 w-4 text-slate-400" />
              <input
                id="start"
                v-model="startLocal"
                type="datetime-local"
                class="w-full rounded-xl border border-slate-300 py-2.5 pl-10 pr-3 text-sm text-slate-800 transition-all focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
              />
            </div>
          </div>

          <div>
            <label
              for="end"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >Selesai Sewa</label
            >
            <div class="relative">
              <CalendarDays class="absolute left-3 top-3 h-4 w-4 text-slate-400" />
              <input
                id="end"
                v-model="endLocal"
                type="datetime-local"
                class="w-full rounded-xl border border-slate-300 py-2.5 pl-10 pr-3 text-sm text-slate-800 transition-all focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
              />
            </div>
          </div>
        </div>

        <!-- Status ketersediaan -->
        <p
          v-if="availability.state !== 'idle'"
          class="flex items-start gap-2 rounded-xl border px-3 py-2 text-xs font-medium"
          :class="{
            'border-emerald-200 bg-emerald-50 text-emerald-700':
              availability.state === 'available',
            'border-red-200 bg-red-50 text-red-700':
              availability.state === 'unavailable' || availability.state === 'invalid',
            'border-amber-200 bg-amber-50 text-amber-700':
              availability.state === 'checking' || availability.state === 'error',
          }"
        >
          <CheckCircle2
            v-if="availability.state === 'available'"
            class="mt-0.5 h-4 w-4 shrink-0"
          />
          <XCircle
            v-else-if="
              availability.state === 'unavailable' ||
              availability.state === 'invalid'
            "
            class="mt-0.5 h-4 w-4 shrink-0"
          />
          <LoaderCircle v-else class="mt-0.5 h-4 w-4 shrink-0 animate-spin" />
          <span>{{ availability.message }}</span>
        </p>

        <!-- Catatan -->
        <div>
          <label
            for="notes"
            class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >Catatan (opsional)</label
          >
          <textarea
            id="notes"
            v-model="notes"
            rows="3"
            placeholder="Contoh: diantar ke Stasiun Bandung jam 09.00"
            class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 placeholder-slate-400 transition-all focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          ></textarea>
        </div>

        <!-- Ringkasan harga -->
        <div class="space-y-2 rounded-xl bg-slate-50 p-4 text-sm">
          <div class="flex items-center justify-between text-slate-600">
            <span>Durasi sewa</span>
            <span class="font-semibold">{{ days }} hari</span>
          </div>
          <div class="flex items-center justify-between text-slate-600">
            <span>Tarif per hari</span>
            <span class="font-semibold">{{ rupiah(vehicle.price_per_day) }}</span>
          </div>
          <div
            class="flex items-center justify-between border-t border-slate-200 pt-2 text-base font-extrabold text-slate-800"
          >
            <span>Total</span>
            <span class="text-blue-600">{{ rupiah(totalPrice) }}</span>
          </div>
        </div>

        <p
          v-if="submitError"
          class="flex items-start gap-2 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700"
        >
          <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
          <span>{{ submitError }}</span>
        </p>

        <button
          type="button"
          :disabled="!canSubmit"
          class="flex w-full items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-3 text-sm font-semibold text-white shadow-md shadow-blue-500/20 transition-all hover:bg-blue-700 active:scale-[0.99] disabled:cursor-not-allowed disabled:opacity-60"
          @click="handleSubmit"
        >
          <LoaderCircle v-if="submitting" class="h-4 w-4 animate-spin" />
          {{ submitting ? "Mengirim pengajuan..." : "Ajukan Sewa Sekarang" }}
        </button>

        <p class="text-center text-xs text-slate-500">
          Pengajuan akan berstatus <strong>PENDING</strong> sampai admin
          memverifikasi dokumen kamu.
        </p>
      </section>
    </template>
  </div>
</template>
