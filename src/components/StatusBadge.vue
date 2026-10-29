<script setup>
import { computed } from "vue";
import { BOOKING_STATUS, VEHICLE_STATUS, statusTone } from "../lib/format";

const props = defineProps({
  value: { type: String, required: true },
  kind: { type: String, default: "booking" }, // 'booking' | 'vehicle'
});

const meta = computed(() => {
  const source = props.kind === "vehicle" ? VEHICLE_STATUS : BOOKING_STATUS;
  return source[props.value] ?? { label: props.value, tone: "slate" };
});
</script>

<template>
  <span
    class="inline-flex items-center rounded-full border px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide"
    :class="statusTone(meta.tone)"
  >
    {{ meta.label }}
  </span>
</template>
