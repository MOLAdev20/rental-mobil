<script setup>
import { X } from "@lucide/vue";

defineProps({
  open: { type: Boolean, default: false },
  title: { type: String, default: "" },
});

const emit = defineEmits(["close"]);
</script>

<template>
  <Teleport to="body">
    <div
      v-if="open"
      class="fixed inset-0 z-50 flex items-end justify-center bg-slate-900/50 backdrop-blur-sm sm:items-center sm:p-4"
      @click.self="emit('close')"
    >
      <div
        class="w-full max-h-[92vh] overflow-y-auto rounded-t-3xl bg-white shadow-2xl sm:max-w-lg sm:rounded-2xl"
      >
        <header
          class="sticky top-0 flex items-center justify-between border-b border-slate-100 bg-white px-5 py-4"
        >
          <h3 class="font-bold text-slate-800">{{ title }}</h3>
          <button
            type="button"
            class="rounded-lg p-1 text-slate-400 transition-colors hover:bg-slate-100 hover:text-slate-600"
            @click="emit('close')"
          >
            <X class="h-5 w-5" />
          </button>
        </header>

        <div class="p-5">
          <slot />
        </div>
      </div>
    </div>
  </Teleport>
</template>
