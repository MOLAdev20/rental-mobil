<script setup lang="js">
import {
  ArrowLeft,
  Check,
  ChevronLeft,
  ChevronRight,
  Images,
  LoaderCircle,
  TriangleAlert,
} from "@lucide/vue";
import { computed, onMounted, ref } from "vue";
import { useRouter } from "vue-router";
import StatusBadge from "../components/StatusBadge.vue";
import { useAuth } from "../composables/useAuth";
import { isProfileComplete, parseVehicleTags, rupiah, VEHICLE_TYPE } from "../lib/format";
import { supabase } from "../lib/supabase-client";

const props = defineProps({
  vehicleId: { type: String, required: true },
});

const router = useRouter();
const { profile } = useAuth();

const vehicle = ref(null);
const images = ref([]);
const loading = ref(true);
const errorMessage = ref("");
const activeIndex = ref(0);

const typeMeta = computed(
  () => VEHICLE_TYPE[vehicle.value?.type] ?? { label: "", emoji: "🚗" },
);
const vehicleTags = computed(() => parseVehicleTags(vehicle.value?.tags));

// Seluruh foto kendaraan diambil dari tabel vehicle_images
// Gambar pertama otomatis menjadi foto utama/thumbnail
const photos = computed(() => {
  return images.value.map((item) => item.image_url).filter(Boolean);
});

const activePhoto = computed(() => photos.value[activeIndex.value] ?? null);
const isAvailable = computed(() => vehicle.value?.status === "AVAILABLE");

// Arah animasi slide: 'next' = foto baru masuk dari kanan, 'prev' = dari kiri.
const direction = ref("next");
const slideName = computed(() =>
  direction.value === "next" ? "slide-next" : "slide-prev",
);

function goTo(index, directionHint) {
  const total = photos.value.length;
  if (!total) return;

  const target = (index + total) % total;
  if (target === activeIndex.value) return;

  direction.value =
    directionHint ?? (target > activeIndex.value ? "next" : "prev");
  activeIndex.value = target;
}

async function loadDetail() {
  loading.value = true;
  errorMessage.value = "";

  const [vehicleResult, imagesResult] = await Promise.all([
    supabase
      .from("vehicles")
      .select("*")
      .eq("id", props.vehicleId)
      .maybeSingle(),
    supabase
      .from("vehicle_images")
      .select("id, image_url, created_at")
      .eq("vehicle_id", props.vehicleId)
      .order("created_at", { ascending: true }),
  ]);

  if (vehicleResult.error) {
    errorMessage.value = vehicleResult.error.message;
  } else if (!vehicleResult.data) {
    errorMessage.value = "Kendaraan tidak ditemukan.";
  } else {
    vehicle.value = vehicleResult.data;
    images.value = imagesResult.data ?? [];
    activeIndex.value = 0;
  }

  loading.value = false;
}

function handleBook() {
  if (!isProfileComplete(profile.value)) {
    router.push({
      name: "profile",
      query: {
        redirect: `/booking/${props.vehicleId}`,
        required: "1",
      },
    });
    return;
  }
  router.push({ name: "booking", params: { vehicleId: props.vehicleId } });
}

onMounted(loadDetail);
</script>

<template>
  <div class="mx-auto max-w-4xl space-y-6">
    <button
      type="button"
      class="inline-flex items-center gap-1.5 text-sm font-semibold text-slate-500 transition-colors hover:text-blue-600 cursor-pointer"
      @click="router.back()"
    >
      <ArrowLeft class="h-4 w-4" />
      Kembali
    </button>

    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 rounded-2xl border border-slate-200 bg-white py-16 text-sm text-slate-500"
    >
      <LoaderCircle class="h-5 w-5 animate-spin" />
      Memuat detail kendaraan...
    </div>

    <div
      v-else-if="errorMessage"
      class="flex items-start gap-2 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
    >
      <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
      <span>{{ errorMessage }}</span>
    </div>

    <template v-else>
      <!-- Galeri foto -->
      <section
        class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm"
      >
        <div
          class="relative flex h-64 items-center justify-center overflow-hidden bg-slate-900 sm:h-96"
        >
          <Transition v-if="activePhoto" :name="slideName" appear>
            <img
              :key="activeIndex"
              :src="activePhoto"
              :alt="`${vehicle.name} - foto ${activeIndex + 1}`"
              class="absolute inset-0 h-full w-full object-contain"
            />
          </Transition>
          <span v-else class="text-8xl">{{ typeMeta.emoji }}</span>

          <span class="absolute left-3 top-3">
            <StatusBadge :value="vehicle.status" kind="vehicle" />
          </span>

          <template v-if="photos.length > 1">
            <button
              type="button"
              aria-label="Foto sebelumnya"
              class="absolute left-3 top-1/2 -translate-y-1/2 rounded-full bg-white/90 p-2 text-slate-700 shadow-md transition-colors hover:bg-white"
              @click="goTo(activeIndex - 1, 'prev')"
            >
              <ChevronLeft class="h-5 w-5" />
            </button>
            <button
              type="button"
              aria-label="Foto berikutnya"
              class="absolute right-3 top-1/2 -translate-y-1/2 rounded-full bg-white/90 p-2 text-slate-700 shadow-md transition-colors hover:bg-white"
              @click="goTo(activeIndex + 1, 'next')"
            >
              <ChevronRight class="h-5 w-5" />
            </button>
            <span
              class="absolute bottom-3 right-3 rounded-full bg-slate-900/70 px-3 py-1 text-xs font-semibold text-white backdrop-blur-sm"
            >
              {{ activeIndex + 1 }} / {{ photos.length }}
            </span>
          </template>
        </div>

        <!-- Thumbnail -->
        <div v-if="photos.length" class="space-y-3 p-4">
          <div class="flex gap-2 overflow-x-auto pb-1">
            <button
              v-for="(photo, index) in photos"
              :key="photo"
              type="button"
              class="relative h-16 w-24 shrink-0 overflow-hidden rounded-xl border-2 transition-all cursor-pointer"
              :class="
                index === activeIndex
                  ? 'border-blue-600 ring-2 ring-blue-100'
                  : 'border-transparent opacity-70 hover:opacity-100'
              "
              @click="goTo(index)"
            >
              <img
                :src="photo"
                :alt="`Thumbnail ${index + 1}`"
                class="h-full w-full object-cover"
              />
            </button>
          </div>

          <p class="flex items-center gap-1.5 text-xs text-slate-500">
            <Images class="h-4 w-4" />
            {{ photos.length }} foto tersedia
          </p>
        </div>

        <p v-else class="p-4 text-xs text-slate-500">
          Belum ada foto untuk kendaraan ini.
        </p>
      </section>

      <!-- Informasi kendaraan -->
      <section
        class="space-y-4 rounded-2xl border border-slate-200 bg-white p-5 shadow-sm sm:p-6"
      >
        <div class="space-y-2">
          <span
            class="rounded bg-blue-50 px-2 py-0.5 text-[10px] font-bold uppercase text-blue-600"
          >
            {{ typeMeta.label }}
          </span>
          <h1 class="text-2xl font-extrabold text-slate-800">
            {{ vehicle.name }}
          </h1>
          <p class="text-sm text-slate-500">
            {{ vehicle.description || "Kendaraan siap pakai dan terawat." }}
          </p>
        </div>

        <div
          class="grid gap-3 border-t border-slate-100 pt-4 text-sm sm:grid-cols-2"
        >
          <div>
            <p class="text-xs text-slate-400">Nomor Polisi</p>
            <p class="font-semibold text-slate-700">
              {{ vehicle.license_plate }}
            </p>
          </div>
          <div>
            <p class="text-xs text-slate-400">Tarif Sewa</p>
            <p class="text-base font-extrabold text-blue-600">
              {{ rupiah(vehicle.price_per_day) }}
              <span class="text-xs font-normal text-slate-400">/hari</span>
            </p>
          </div>
        </div>

        <!-- Spesifikasi & Fasilitas (Tags) -->
        <div v-if="vehicleTags.length" class="space-y-2.5 border-t border-slate-100 pt-4">
          <p class="text-xs font-bold uppercase tracking-wider text-slate-500">
            Fasilitas &amp; Spesifikasi
          </p>
          <div class="flex flex-wrap gap-2">
            <span
              v-for="tag in vehicleTags"
              :key="tag"
              class="inline-flex items-center gap-1.5 rounded-lg border border-blue-200/80 bg-blue-50/70 px-3 py-1.5 text-xs font-medium text-blue-800"
            >
              <Check class="h-3.5 w-3.5 text-blue-600" />
              {{ tag }}
            </span>
          </div>
        </div>

        <button
          type="button"
          :disabled="!isAvailable"
          class="w-full rounded-xl py-3 text-sm font-semibold transition-all active:scale-[0.99]"
          :class="
            isAvailable
              ? 'bg-blue-600 text-white shadow-md shadow-blue-500/20 hover:bg-blue-700'
              : 'cursor-not-allowed bg-slate-200 text-slate-400'
          "
          @click="handleBook"
        >
          {{ isAvailable ? "Sewa Sekarang" : "Sedang Tidak Tersedia" }}
        </button>
      </section>
    </template>
  </div>
</template>

<style scoped>
/* Animasi slide saat berpindah foto. Elemen yang leave tetap di posisi
   absolut supaya foto lama dan foto baru bergerak bersamaan. */
.slide-next-enter-active,
.slide-next-leave-active,
.slide-prev-enter-active,
.slide-prev-leave-active {
  transition:
    transform 0.35s cubic-bezier(0.4, 0, 0.2, 1),
    opacity 0.35s ease;
}

.slide-next-enter-from {
  transform: translateX(100%);
  opacity: 0.3;
}
.slide-next-leave-to {
  transform: translateX(-100%);
  opacity: 0.3;
}

.slide-prev-enter-from {
  transform: translateX(-100%);
  opacity: 0.3;
}
.slide-prev-leave-to {
  transform: translateX(100%);
  opacity: 0.3;
}

@media (prefers-reduced-motion: reduce) {
  .slide-next-enter-active,
  .slide-next-leave-active,
  .slide-prev-enter-active,
  .slide-prev-leave-active {
    transition: opacity 0.2s ease;
  }

  .slide-next-enter-from,
  .slide-next-leave-to,
  .slide-prev-enter-from,
  .slide-prev-leave-to {
    transform: none;
  }
}
</style>
