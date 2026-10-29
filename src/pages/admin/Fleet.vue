<script setup lang="js">
import {
  Images,
  LoaderCircle,
  Pencil,
  Plus,
  Trash2,
  TriangleAlert,
  X,
} from "@lucide/vue";
import { computed, onMounted, reactive, ref } from "vue";
import AppModal from "../../components/AppModal.vue";
import StatusBadge from "../../components/StatusBadge.vue";
import {
  getVehicleThumbnail,
  parseVehicleTags,
  rupiah,
  VEHICLE_TAG_PRESETS,
} from "../../lib/format";
import { supabase, VEHICLE_IMAGE_BUCKET } from "../../lib/supabase-client";

const vehicles = ref([]);
const loading = ref(true);
const errorMessage = ref("");
const saving = ref(false);
const deletingId = ref("");

const modalOpen = ref(false);
const editingId = ref(null);

// Galeri foto (bisa banyak foto per unit)
const galleryImages = ref([]);
const galleryLoading = ref(false);
const galleryUploading = ref(false);
const galleryError = ref("");
const galleryInput = ref(null);

const form = reactive({
  name: "",
  type: "CAR",
  license_plate: "",
  price_per_day: "",
  status: "AVAILABLE",
  description: "",
  tags: [],
});

const selectedTagToAdd = ref("");
const customTagInput = ref("");

const availableTagGroups = computed(() => {
  return VEHICLE_TAG_PRESETS[form.type] ?? VEHICLE_TAG_PRESETS.CAR;
});

const quickSuggestions = computed(() => {
  const groups = availableTagGroups.value;
  const list = [];
  for (const g of groups) {
    for (const opt of g.options) {
      if (!list.includes(opt)) {
        list.push(opt);
      }
    }
  }
  return list;
});

function handleSelectTag() {
  const val = selectedTagToAdd.value.trim();
  if (val && !form.tags.includes(val)) {
    form.tags.push(val);
  }
  selectedTagToAdd.value = "";
}

function addCustomTag() {
  const val = customTagInput.value.trim();
  if (val && !form.tags.includes(val)) {
    form.tags.push(val);
  }
  customTagInput.value = "";
}

function toggleTag(tag) {
  const idx = form.tags.indexOf(tag);
  if (idx >= 0) {
    form.tags.splice(idx, 1);
  } else {
    form.tags.push(tag);
  }
}

function removeTag(index) {
  form.tags.splice(index, 1);
}

const stats = computed(() => ({
  total: vehicles.value.length,
  available: vehicles.value.filter((v) => v.status === "AVAILABLE").length,
  booked: vehicles.value.filter((v) => v.status === "BOOKED").length,
  maintenance: vehicles.value.filter((v) => v.status === "MAINTENANCE").length,
}));

async function loadVehicles() {
  loading.value = true;
  errorMessage.value = "";

  const { data, error } = await supabase
    .from("vehicles")
    .select("*, vehicle_images(id, image_url, created_at)")
    .order("created_at", { ascending: false });

  if (error) {
    errorMessage.value = error.message;
  } else {
    vehicles.value = data ?? [];
  }

  loading.value = false;
}

function resetForm() {
  editingId.value = null;
  galleryImages.value = [];
  galleryError.value = "";
  selectedTagToAdd.value = "";
  customTagInput.value = "";
  Object.assign(form, {
    name: "",
    type: "CAR",
    license_plate: "",
    price_per_day: "",
    status: "AVAILABLE",
    description: "",
    tags: [],
  });
}

function openCreate() {
  resetForm();
  modalOpen.value = true;
}

function openEdit(vehicle) {
  resetForm();
  editingId.value = vehicle.id;
  const initialTags = parseVehicleTags(vehicle.tags);
  Object.assign(form, {
    name: vehicle.name ?? "",
    type: vehicle.type ?? "CAR",
    license_plate: vehicle.license_plate ?? "",
    price_per_day: vehicle.price_per_day ?? "",
    status: vehicle.status ?? "AVAILABLE",
    description: vehicle.description ?? "",
    tags: [...initialTags],
  });
  modalOpen.value = true;
  loadGallery(vehicle.id);
}

async function loadGallery(vehicleId) {
  if (!vehicleId) {
    galleryImages.value = [];
    return;
  }

  galleryLoading.value = true;
  galleryError.value = "";

  const { data, error } = await supabase
    .from("vehicle_images")
    .select("id, image_url, storage_path, created_at")
    .eq("vehicle_id", vehicleId)
    .order("created_at", { ascending: true });

  if (error) {
    galleryError.value = error.message;
  } else {
    galleryImages.value = data ?? [];
  }

  galleryLoading.value = false;
}

async function handleGalleryUpload(event) {
  const files = Array.from(event.target.files ?? []);
  event.target.value = "";

  if (!files.length || !editingId.value) return;

  galleryUploading.value = true;
  galleryError.value = "";

  try {
    for (const file of files) {
      if (!file.type.startsWith("image/")) {
        throw new Error(`File "${file.name}" bukan gambar.`);
      }
      if (file.size > 5 * 1024 * 1024) {
        throw new Error(`File "${file.name}" lebih dari 5 MB.`);
      }

      const extension = file.name.split(".").pop()?.toLowerCase() || "jpg";
      const path = `vehicles/${editingId.value}/${Date.now()}-${Math.random()
        .toString(36)
        .slice(2, 8)}.${extension}`;

      const { error: uploadError } = await supabase.storage
        .from(VEHICLE_IMAGE_BUCKET)
        .upload(path, file, {
          cacheControl: "3600",
          upsert: false,
          contentType: file.type || "image/jpeg",
        });

      if (uploadError) throw uploadError;

      const { data } = supabase.storage
        .from(VEHICLE_IMAGE_BUCKET)
        .getPublicUrl(path);

      const { error: insertError } = await supabase
        .from("vehicle_images")
        .insert({
          vehicle_id: editingId.value,
          image_url: data.publicUrl,
          storage_path: path,
        });

      if (insertError) throw insertError;
    }
  } catch (error) {
    galleryError.value = error?.message ?? "Gagal mengunggah foto galeri.";
  } finally {
    galleryUploading.value = false;
    await loadGallery(editingId.value);
    await loadVehicles();
  }
}

async function removeGalleryImage(image) {
  if (!window.confirm("Hapus foto ini dari galeri kendaraan?")) return;

  galleryError.value = "";

  if (image.storage_path) {
    await supabase.storage
      .from(VEHICLE_IMAGE_BUCKET)
      .remove([image.storage_path]);
  }

  const { error } = await supabase
    .from("vehicle_images")
    .delete()
    .eq("id", image.id);

  if (error) {
    galleryError.value = error.message;
    return;
  }

  await loadGallery(editingId.value);
  await loadVehicles();
}

async function handleSave() {
  errorMessage.value = "";

  if (!form.name.trim() || !form.license_plate.trim()) {
    errorMessage.value = "Nama kendaraan dan nomor polisi wajib diisi.";
    return;
  }
  if (!form.price_per_day || Number(form.price_per_day) <= 0) {
    errorMessage.value = "Tarif harian harus lebih besar dari 0.";
    return;
  }

  saving.value = true;

  try {
    const payload = {
      name: form.name.trim(),
      type: form.type,
      license_plate: form.license_plate.trim().toUpperCase(),
      price_per_day: Number(form.price_per_day),
      status: form.status,
      description: form.description.trim() || null,
      tags: form.tags,
    };

    const response = editingId.value
      ? await supabase
          .from("vehicles")
          .update(payload)
          .eq("id", editingId.value)
      : await supabase.from("vehicles").insert(payload);

    if (response.error) throw response.error;

    modalOpen.value = false;
    resetForm();
    await loadVehicles();
  } catch (error) {
    errorMessage.value =
      error?.code === "23505"
        ? "Nomor polisi sudah terdaftar pada unit lain."
        : (error?.message ?? "Gagal menyimpan data kendaraan.");
  } finally {
    saving.value = false;
  }
}

async function handleDelete(vehicle) {
  const confirmed = window.confirm(
    `Hapus unit ${vehicle.name} (${vehicle.license_plate})? Riwayat booking unit ini juga akan terhapus.`,
  );
  if (!confirmed) return;

  deletingId.value = vehicle.id;
  errorMessage.value = "";

  const { error } = await supabase
    .from("vehicles")
    .delete()
    .eq("id", vehicle.id);

  if (error) {
    errorMessage.value = error.message;
  } else {
    await loadVehicles();
  }

  deletingId.value = "";
}

onMounted(loadVehicles);
</script>

<template>
  <div class="space-y-6">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <div>
        <h1 class="text-xl font-extrabold text-slate-800">Manajemen Armada</h1>
        <p class="text-sm text-slate-500">
          Tambah, ubah, atau nonaktifkan unit kendaraan rental.
        </p>
      </div>
      <button
        type="button"
        class="inline-flex items-center gap-2 rounded-xl bg-blue-600 px-4 py-2.5 text-xs font-semibold text-white shadow-sm shadow-blue-500/20 transition-colors hover:bg-blue-700 cursor-pointer"
        @click="openCreate"
      >
        <Plus class="h-4 w-4" />
        Tambah Unit
      </button>
    </div>

    <div class="grid grid-cols-2 gap-4 lg:grid-cols-4">
      <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <p class="text-xs text-slate-500">Total Unit</p>
        <p class="text-2xl font-extrabold text-slate-800">{{ stats.total }}</p>
      </div>
      <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <p class="text-xs text-slate-500">Tersedia</p>
        <p class="text-2xl font-extrabold text-emerald-600">
          {{ stats.available }}
        </p>
      </div>
      <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <p class="text-xs text-slate-500">Disewa</p>
        <p class="text-2xl font-extrabold text-slate-600">{{ stats.booked }}</p>
      </div>
      <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-sm">
        <p class="text-xs text-slate-500">Maintenance</p>
        <p class="text-2xl font-extrabold text-amber-600">
          {{ stats.maintenance }}
        </p>
      </div>
    </div>

    <p
      v-if="errorMessage && !modalOpen"
      class="flex items-start gap-2 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
    >
      <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
      <span>{{ errorMessage }}</span>
    </p>

    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 rounded-2xl border border-slate-200 bg-white py-16 text-sm text-slate-500"
    >
      <LoaderCircle class="h-5 w-5 animate-spin" />
      Memuat armada...
    </div>

    <div
      v-else-if="vehicles.length === 0"
      class="rounded-2xl border border-dashed border-slate-300 bg-white py-16 text-center text-sm text-slate-500"
    >
      Belum ada unit kendaraan. Klik "Tambah Unit" untuk mulai.
    </div>

    <div v-else class="grid grid-cols-1 gap-5 sm:grid-cols-2 lg:grid-cols-3">
      <article
        v-for="vehicle in vehicles"
        :key="vehicle.id"
        class="group flex flex-col justify-between overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-xs transition-all hover:border-blue-300 hover:shadow-md"
      >
        <RouterLink
          :to="{
            name: 'admin-vehicle-detail',
            params: { vehicleId: vehicle.id },
          }"
          class="block flex-1 cursor-pointer"
        >
          <div
            class="relative flex h-40 items-center justify-center overflow-hidden bg-slate-100"
          >
            <img
              v-if="getVehicleThumbnail(vehicle)"
              :src="getVehicleThumbnail(vehicle)"
              :alt="vehicle.name"
              class="h-full w-full object-cover transition-transform duration-300 group-hover:scale-105"
            />
            <span v-else class="text-sm text-gray-400">Tidak ada gambar</span>
            <span class="absolute right-3 top-3">
              <StatusBadge :value="vehicle.status" kind="vehicle" />
            </span>
          </div>

          <div class="space-y-1 p-5">
            <h2
              class="text-base font-bold text-slate-800 transition-colors group-hover:text-blue-600"
            >
              {{ vehicle.name }}
            </h2>
            <p class="text-xs text-slate-500">
              {{ vehicle.license_plate }} ·
              {{ rupiah(vehicle.price_per_day) }}/hari
            </p>
            <p
              v-if="vehicle.description"
              class="text-xs text-slate-400 line-clamp-1"
            >
              {{ vehicle.description }}
            </p>

            <!-- Tags pada kartu armada -->
            <div
              v-if="parseVehicleTags(vehicle.tags).length"
              class="flex flex-wrap gap-1 pt-1"
            >
              <span
                v-for="tag in parseVehicleTags(vehicle.tags).slice(0, 3)"
                :key="tag"
                class="inline-flex items-center rounded-md border border-slate-200 bg-slate-50 px-2 py-0.5 text-[10px] font-medium text-slate-600"
              >
                {{ tag }}
              </span>
              <span
                v-if="parseVehicleTags(vehicle.tags).length > 3"
                class="inline-flex items-center rounded-md bg-slate-100 px-1.5 py-0.5 text-[10px] font-semibold text-slate-400"
              >
                +{{ parseVehicleTags(vehicle.tags).length - 3 }}
              </span>
            </div>
          </div>
        </RouterLink>

        <div class="flex gap-2 p-5 pt-0">
          <button
            type="button"
            class="inline-flex flex-1 items-center justify-center gap-1.5 rounded-xl border border-slate-200 px-3 py-2 text-xs font-semibold text-slate-600 transition-colors hover:border-blue-200 hover:bg-blue-50 hover:text-blue-700 cursor-pointer"
            @click="openEdit(vehicle)"
          >
            <Pencil class="h-4 w-4" />
            Ubah
          </button>
          <button
            type="button"
            :disabled="deletingId === vehicle.id"
            class="inline-flex items-center justify-center gap-1.5 rounded-xl border border-red-200 px-3 py-2 text-xs font-semibold text-red-600 transition-colors hover:bg-red-50 disabled:opacity-60 cursor-pointer"
            @click="handleDelete(vehicle)"
          >
            <LoaderCircle
              v-if="deletingId === vehicle.id"
              class="h-4 w-4 animate-spin"
            />
            <Trash2 v-else class="h-4 w-4" />
          </button>
        </div>
      </article>
    </div>

    <!-- Modal form -->
    <AppModal
      :open="modalOpen"
      :title="editingId ? 'Ubah Unit Kendaraan' : 'Tambah Unit Kendaraan'"
      @close="modalOpen = false"
    >
      <form class="space-y-4" @submit.prevent="handleSave">
        <div>
          <label
            for="name"
            class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >Nama Kendaraan</label
          >
          <input
            id="name"
            v-model="form.name"
            type="text"
            required
            placeholder="Toyota Avanza 2023"
            class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label
              for="type"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >Jenis</label
            >
            <select
              id="type"
              v-model="form.type"
              class="w-full rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            >
              <option value="CAR">Mobil</option>
              <option value="MOTORCYCLE">Motor</option>
            </select>
          </div>

          <div>
            <label
              for="plate"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >Nomor Polisi</label
            >
            <input
              id="plate"
              v-model="form.license_plate"
              type="text"
              required
              placeholder="B 1234 RJY"
              class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm uppercase text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <div>
            <label
              for="price"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >Tarif / Hari (Rp)</label
            >
            <input
              id="price"
              v-model="form.price_per_day"
              type="number"
              min="0"
              step="1000"
              required
              placeholder="350000"
              class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <div>
            <label
              for="status"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >Status</label
            >
            <select
              id="status"
              v-model="form.status"
              class="w-full rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            >
              <option value="AVAILABLE">Tersedia</option>
              <option value="MAINTENANCE">Maintenance</option>
              <option value="BOOKED">Disewa</option>
            </select>
          </div>
        </div>

        <div>
          <label
            for="description"
            class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >Deskripsi</label
          >
          <textarea
            id="description"
            v-model="form.description"
            rows="2"
            placeholder="Transmisi Matic • 7 Kursi • Bensin"
            class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          ></textarea>
        </div>

        <!-- Form Select Option Tags Kendaraan -->
        <div class="rounded-xl border border-slate-200 p-4 space-y-3">
          <div class="flex items-center justify-between">
            <label
              for="tag-select"
              class="block text-xs font-bold uppercase tracking-wider text-slate-700"
            >
              Tags Spesifikasi &amp; Fasilitas
            </label>
            <span
              class="rounded bg-blue-50 px-2 py-0.5 text-[10px] font-semibold text-blue-700"
            >
              {{ form.tags.length }} tag dipilih
            </span>
          </div>
          <p class="text-xs text-slate-500">
            Pilih spesifikasi dan fasilitas sewa kendaraan dari dropdown opsi di
            bawah.
          </p>

          <!-- Select option dropdown -->
          <div>
            <select
              id="tag-select"
              v-model="selectedTagToAdd"
              class="w-full rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
              @change="handleSelectTag"
            >
              <option value="" disabled>
                -- Pilih informasi tag untuk ditambahkan --
              </option>
              <optgroup
                v-for="group in availableTagGroups"
                :key="group.category"
                :label="group.category"
              >
                <option
                  v-for="opt in group.options"
                  :key="opt"
                  :value="opt"
                  :disabled="form.tags.includes(opt)"
                >
                  {{ opt }}
                  {{ form.tags.includes(opt) ? "✓ (Sudah dipilih)" : "" }}
                </option>
              </optgroup>
            </select>
          </div>

          <!-- Input tag kustom jika ada opsi khusus -->
          <div class="flex gap-2">
            <input
              v-model="customTagInput"
              type="text"
              placeholder="Atau ketik tag kustom sendiri..."
              class="flex-1 rounded-xl border border-slate-300 px-3 py-2 text-xs text-slate-800 placeholder-slate-400 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
              @keydown.enter.prevent="addCustomTag"
            />
            <button
              type="button"
              class="rounded-xl border border-slate-200 bg-slate-100 px-3 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-200 cursor-pointer"
              @click="addCustomTag"
            >
              + Tambah
            </button>
          </div>

          <!-- Daftar tag terpilih -->
          <div>
            <p class="mb-1.5 text-[11px] font-semibold text-slate-500">
              Tag Terpilih:
            </p>
            <div v-if="form.tags.length" class="flex flex-wrap gap-1.5">
              <span
                v-for="(tag, idx) in form.tags"
                :key="tag"
                class="inline-flex items-center gap-1.5 rounded-lg border border-blue-200 bg-blue-50 px-2.5 py-1 text-xs font-semibold text-blue-700 shadow-2xs"
              >
                {{ tag }}
                <button
                  type="button"
                  title="Hapus tag"
                  class="rounded-full p-0.5 text-blue-500 hover:bg-blue-200 hover:text-blue-900 cursor-pointer"
                  @click="removeTag(idx)"
                >
                  <X class="h-3 w-3" />
                </button>
              </span>
            </div>
            <p v-else class="text-xs italic text-slate-400">
              Belum ada tag dipilih. Pilih dari opsi di atas atau klik
              rekomendasi di bawah.
            </p>
          </div>

          <!-- Rekomendasi Cepat / Chip Click -->
          <div class="border-t border-slate-100 pt-2.5">
            <p class="mb-1.5 text-[11px] font-semibold text-slate-400">
              Rekomendasi Cepat (Klik untuk memilih/membatalkan):
            </p>
            <div class="flex flex-wrap gap-1.5">
              <button
                v-for="opt in quickSuggestions"
                :key="opt"
                type="button"
                class="rounded-md px-2 py-0.5 text-[11px] font-medium transition-colors cursor-pointer"
                :class="
                  form.tags.includes(opt)
                    ? 'bg-blue-600 text-white font-semibold shadow-xs'
                    : 'bg-slate-100 text-slate-600 hover:bg-slate-200'
                "
                @click="toggleTag(opt)"
              >
                {{ form.tags.includes(opt) ? "✓ " : "+ " }}{{ opt }}
              </button>
            </div>
          </div>
        </div>

        <!-- Galeri foto (jumlah dinamis) -->
        <div class="rounded-xl border border-slate-200 p-4">
          <p
            class="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-slate-600"
          >
            <Images class="h-4 w-4" />
            Galeri Foto
          </p>
          <p class="mt-1 text-xs text-slate-500">
            Foto pertama yang diunggah ke galeri otomatis dijadikan foto thumbnail di katalog dan pesanan.
          </p>

          <p
            v-if="!editingId"
            class="mt-3 rounded-lg bg-slate-50 px-3 py-2 text-xs text-slate-500"
          >
            Simpan unit terlebih dahulu, lalu buka kembali unit ini untuk
            menambahkan foto galeri.
          </p>

          <template v-else>
            <div
              v-if="galleryLoading"
              class="mt-3 flex items-center gap-2 py-3 text-xs text-slate-500"
            >
              <LoaderCircle class="h-4 w-4 animate-spin" />
              Memuat galeri...
            </div>

            <div v-else class="mt-3 grid grid-cols-3 gap-2">
              <div
                v-for="image in galleryImages"
                :key="image.id"
                class="relative aspect-4/3 overflow-hidden rounded-lg border border-slate-200"
              >
                <img
                  :src="image.image_url"
                  alt="Foto kendaraan"
                  class="h-full w-full object-cover"
                />
                <button
                  type="button"
                  title="Hapus foto"
                  class="absolute right-1 top-1 rounded-full bg-white/90 p-1 text-red-600 shadow-sm transition-colors hover:bg-white"
                  @click="removeGalleryImage(image)"
                >
                  <Trash2 class="h-3.5 w-3.5" />
                </button>
              </div>

              <button
                type="button"
                :disabled="galleryUploading"
                class="flex aspect-4/3 flex-col items-center justify-center gap-1 rounded-lg border border-dashed border-slate-300 text-xs font-semibold text-slate-500 transition-colors hover:border-blue-400 hover:bg-blue-50 disabled:opacity-60"
                @click="galleryInput?.click()"
              >
                <LoaderCircle
                  v-if="galleryUploading"
                  class="h-5 w-5 animate-spin"
                />
                <Plus v-else class="h-5 w-5" />
                {{ galleryUploading ? "Mengunggah..." : "Tambah" }}
              </button>
            </div>

            <p
              v-if="!galleryLoading && galleryImages.length === 0"
              class="mt-2 text-xs text-slate-400"
            >
              Belum ada foto galeri.
            </p>

            <p
              v-if="galleryError"
              class="mt-2 flex items-start gap-1.5 text-xs font-medium text-red-700"
            >
              <TriangleAlert class="mt-0.5 h-3.5 w-3.5 shrink-0" />
              <span>{{ galleryError }}</span>
            </p>

            <input
              ref="galleryInput"
              type="file"
              accept="image/*"
              multiple
              class="hidden"
              @change="handleGalleryUpload"
            />
          </template>
        </div>

        <p
          v-if="errorMessage"
          class="flex items-start gap-2 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700"
        >
          <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
          <span>{{ errorMessage }}</span>
        </p>

        <div class="flex gap-3">
          <button
            type="button"
            class="flex-1 rounded-xl border border-slate-300 px-4 py-2.5 text-sm font-semibold text-slate-600 transition-colors hover:bg-slate-50"
            @click="modalOpen = false"
          >
            Batal
          </button>
          <button
            type="submit"
            :disabled="saving"
            class="flex flex-1 items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-blue-700 disabled:opacity-60"
          >
            <LoaderCircle v-if="saving" class="h-4 w-4 animate-spin" />
            {{ saving ? "Menyimpan..." : "Simpan" }}
          </button>
        </div>
      </form>
    </AppModal>
  </div>
</template>
