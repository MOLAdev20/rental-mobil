<script setup>
import { computed } from "vue";
import { getVehicleThumbnail, parseVehicleTags, rupiah, VEHICLE_TYPE } from "../lib/format";
import StatusBadge from "./StatusBadge.vue";

const props = defineProps({
  vehicle: { type: Object, required: true },
});

defineEmits(["book"]);

const typeMeta = computed(
  () => VEHICLE_TYPE[props.vehicle.type] ?? { label: props.vehicle.type, emoji: "🚗" },
);
const isAvailable = computed(() => props.vehicle.status === "AVAILABLE");
const tags = computed(() => parseVehicleTags(props.vehicle.tags));
const thumbnail = computed(() => getVehicleThumbnail(props.vehicle));
</script>

<template>
  <div
    class="flex flex-col justify-between overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-sm transition-all hover:shadow-md"
  >
    <div>
      <RouterLink
        :to="{ name: 'vehicle-detail', params: { vehicleId: vehicle.id } }"
        class="block"
      >
        <div
          class="relative flex h-44 items-center justify-center bg-slate-100 p-4"
        >
          <img
            v-if="thumbnail"
            :src="thumbnail"
            :alt="vehicle.name"
            class="h-full w-full rounded-xl object-cover"
          />
          <span v-else class="text-7xl">{{ typeMeta.emoji }}</span>

          <span class="absolute right-3 top-3">
            <StatusBadge :value="vehicle.status" kind="vehicle" />
          </span>
        </div>

        <div class="space-y-3 p-5">
          <div>
            <span
              class="rounded bg-blue-50 px-2 py-0.5 text-[10px] font-bold uppercase text-blue-600"
            >
              {{ typeMeta.label }}
            </span>
            <h3 class="mt-1 text-base font-bold text-slate-800">
              {{ vehicle.name }}
            </h3>
            <p class="mt-0.5 text-xs text-slate-500 line-clamp-1">
              {{ vehicle.description || vehicle.license_plate }}
            </p>
          </div>

          <!-- Tags Spesifikasi / Fasilitas -->
          <div v-if="tags.length" class="flex flex-wrap gap-1.5 pt-0.5">
            <span
              v-for="tag in tags.slice(0, 3)"
              :key="tag"
              class="inline-flex items-center rounded-md border border-slate-200 bg-slate-50 px-2 py-0.5 text-[10px] font-medium text-slate-600"
            >
              {{ tag }}
            </span>
            <span
              v-if="tags.length > 3"
              class="inline-flex items-center rounded-md bg-slate-100 px-1.5 py-0.5 text-[10px] font-semibold text-slate-400"
            >
              +{{ tags.length - 3 }}
            </span>
          </div>

          <div
            class="flex items-baseline justify-between border-t border-slate-100 pt-3"
          >
            <span class="text-xs text-slate-400">Tarif Sewa</span>
            <p class="text-base font-extrabold text-blue-600">
              {{ rupiah(vehicle.price_per_day) }}
              <span class="text-xs font-normal text-slate-400">/hari</span>
            </p>
          </div>
        </div>
      </RouterLink>
    </div>

    <div class="px-5 pb-5">
      <button
        type="button"
        :disabled="!isAvailable"
        class="w-full rounded-xl py-2.5 text-sm font-semibold transition-all active:scale-[0.98]"
        :class="
          isAvailable
            ? 'bg-blue-600 text-white shadow-sm hover:bg-blue-700'
            : 'cursor-not-allowed bg-slate-200 text-slate-400'
        "
        @click="isAvailable && $emit('book', vehicle)"
      >
        {{ isAvailable ? "Sewa Sekarang" : "Tidak Tersedia" }}
      </button>
    </div>
  </div>
</template>
