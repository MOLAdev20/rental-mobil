<script setup lang="js">
import {
  ArrowLeft,
  Check,
  CheckCircle2,
  IdCard,
  Images,
  LoaderCircle,
  Pencil,
  Plus,
  Trash2,
  TriangleAlert,
  X,
} from "@lucide/vue";
import { computed, onMounted, reactive, ref } from "vue";
import { useRouter } from "vue-router";
import AppModal from "../../components/AppModal.vue";
import StatusBadge from "../../components/StatusBadge.vue";
import {
  formatDateTime,
  parseVehicleTags,
  rentalDays,
  rupiah,
  VEHICLE_TAG_PRESETS,
  VEHICLE_TYPE,
} from "../../lib/format";
import {
  KTP_BUCKET,
  supabase,
  VEHICLE_IMAGE_BUCKET,
} from "../../lib/supabase-client";

const props = defineProps({
  vehicleId: { type: String, required: true },
});

const router = useRouter();

const vehicle = ref(null);
const galleryImages = ref([]);
const bookings = ref([]);
const loading = ref(true);
const errorMessage = ref("");
const deleting = ref(false);
const activePhotoIndex = ref(0);

// Filter riwayat transaksi sewa
const timeFilter = ref("ALL"); // 'ALL' | 'MONTH' | 'WEEK' | 'DAILY' | 'CUSTOM'
const statusFilter = ref("ALL"); // 'ALL' | 'ACTIVE' | 'APPROVED' | 'COMPLETED' | 'PENDING' | 'CANCELLED'
const customStartDate = ref("");
const customEndDate = ref("");

function resetFilters() {
  timeFilter.value = "ALL";
  statusFilter.value = "ALL";
  customStartDate.value = "";
  customEndDate.value = "";
}

const filteredBookings = computed(() => {
  return bookings.value.filter((b) => {
    // 1. Filter Status (Dropdown)
    if (statusFilter.value !== "ALL" && b.status !== statusFilter.value) {
      return false;
    }

    // 2. Filter Periode Waktu Transaksi (Bulanan, Mingguan, Harian, Custom)
    if (timeFilter.value === "ALL") {
      return true;
    }

    const bookingDate = new Date(b.created_at || b.start_date);
    if (isNaN(bookingDate.getTime())) return true;

    const now = new Date();

    if (timeFilter.value === "DAILY") {
      return (
        bookingDate.getFullYear() === now.getFullYear() &&
        bookingDate.getMonth() === now.getMonth() &&
        bookingDate.getDate() === now.getDate()
      );
    }

    if (timeFilter.value === "WEEK") {
      const startOfWeek = new Date(
        now.getFullYear(),
        now.getMonth(),
        now.getDate() - 7,
        0,
        0,
        0,
      );
      return bookingDate >= startOfWeek && bookingDate <= now;
    }

    if (timeFilter.value === "MONTH") {
      return (
        bookingDate.getFullYear() === now.getFullYear() &&
        bookingDate.getMonth() === now.getMonth()
      );
    }

    if (timeFilter.value === "CUSTOM") {
      if (customStartDate.value) {
        const start = new Date(customStartDate.value + "T00:00:00");
        if (bookingDate < start) return false;
      }
      if (customEndDate.value) {
        const end = new Date(customEndDate.value + "T23:59:59");
        if (bookingDate > end) return false;
      }
      return true;
    }

    return true;
  });
});

// KPI & Ringkasan Sewa
const stats = computed(() => {
  const all = bookings.value;
  const completed = all.filter((b) => b.status === "COMPLETED");
  const active = all.filter((b) => b.status === "ACTIVE");
  const totalRevenue = completed.reduce((sum, b) => {
    const finalVal = b.return_info?.final_price ?? b.total_price;
    return sum + Number(finalVal || 0);
  }, 0);

  return {
    total: all.length,
    active: active.length,
    completed: completed.length,
    revenue: totalRevenue,
  };
});

const vehicleTags = computed(() => parseVehicleTags(vehicle.value?.tags));

const typeMeta = computed(
  () =>
    VEHICLE_TYPE[vehicle.value?.type] ?? {
      label: vehicle.value?.type ?? "Kendaraan",
      emoji: "🚗",
    },
);

const allPhotos = computed(() => {
  return galleryImages.value.map((img) => img.image_url).filter(Boolean);
});

const activePhoto = computed(
  () => allPhotos.value[activePhotoIndex.value] ?? null,
);

// Load data kendaraan, galeri, dan data sewa
async function loadData() {
  loading.value = true;
  errorMessage.value = "";

  try {
    const [vehicleRes, imagesRes, bookingsRes] = await Promise.all([
      supabase
        .from("vehicles")
        .select("*")
        .eq("id", props.vehicleId)
        .maybeSingle(),
      supabase
        .from("vehicle_images")
        .select("*")
        .eq("vehicle_id", props.vehicleId)
        .order("created_at", { ascending: true }),
      supabase
        .from("bookings")
        .select(
          "*, customer:users(id, email, full_name, phone_number, avatar_url), return_info:returns(*)",
        )
        .eq("vehicle_id", props.vehicleId)
        .order("created_at", { ascending: false }),
    ]);

    if (vehicleRes.error) throw vehicleRes.error;
    if (imagesRes.error) throw imagesRes.error;
    if (bookingsRes.error) throw bookingsRes.error;

    if (!vehicleRes.data) {
      errorMessage.value = "Data armada tidak ditemukan.";
      return;
    }

    vehicle.value = vehicleRes.data;
    galleryImages.value = imagesRes.data ?? [];
    bookings.value = bookingsRes.data ?? [];
    activePhotoIndex.value = 0;
  } catch (err) {
    errorMessage.value = err?.message ?? "Gagal memuat detail armada.";
  } finally {
    loading.value = false;
  }
}

// ==========================================
// MANAJEMEN GALERI FOTO ARMADA (INLINE)
// ==========================================
const galleryUploading = ref(false);
const galleryError = ref("");
const galleryFileInput = ref(null);

// ==========================================
// EDIT MODAL STATE & METHODS
// ==========================================
const modalOpen = ref(false);
const saving = ref(false);

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

function openEdit() {
  const v = vehicle.value;
  if (!v) return;

  const initialTags = parseVehicleTags(v.tags);
  galleryError.value = "";
  selectedTagToAdd.value = "";
  customTagInput.value = "";

  Object.assign(form, {
    name: v.name ?? "",
    type: v.type ?? "CAR",
    license_plate: v.license_plate ?? "",
    price_per_day: v.price_per_day ?? "",
    status: v.status ?? "AVAILABLE",
    description: v.description ?? "",
    tags: [...initialTags],
  });

  modalOpen.value = true;
}

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

async function handleGalleryUpload(event) {
  const files = Array.from(event.target.files ?? []);
  event.target.value = "";

  if (!files.length || !props.vehicleId) return;

  galleryUploading.value = true;
  galleryError.value = "";

  try {
    for (const f of files) {
      if (!f.type.startsWith("image/")) {
        throw new Error(`File "${f.name}" bukan format gambar.`);
      }
      if (f.size > 5 * 1024 * 1024) {
        throw new Error(`File "${f.name}" melebihi batas 5 MB.`);
      }

      const extension = f.name.split(".").pop()?.toLowerCase() || "jpg";
      const path = `vehicles/${props.vehicleId}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${extension}`;

      const { error: uploadErr } = await supabase.storage
        .from(VEHICLE_IMAGE_BUCKET)
        .upload(path, f, {
          cacheControl: "3600",
          upsert: false,
          contentType: f.type || "image/jpeg",
        });

      if (uploadErr) throw uploadErr;

      const { data } = supabase.storage
        .from(VEHICLE_IMAGE_BUCKET)
        .getPublicUrl(path);

      const { error: insertErr } = await supabase
        .from("vehicle_images")
        .insert({
          vehicle_id: props.vehicleId,
          image_url: data.publicUrl,
          storage_path: path,
        });

      if (insertErr) throw insertErr;
    }

    // Refresh galeri
    const { data: updatedImages } = await supabase
      .from("vehicle_images")
      .select("*")
      .eq("vehicle_id", props.vehicleId)
      .order("created_at", { ascending: true });

    galleryImages.value = updatedImages ?? [];
  } catch (err) {
    galleryError.value = err?.message ?? "Gagal mengunggah foto galeri.";
  } finally {
    galleryUploading.value = false;
  }
}

async function removeGalleryImage(image) {
  if (!window.confirm("Hapus foto ini dari galeri armada?")) return;

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
  } else {
    galleryImages.value = galleryImages.value.filter(
      (img) => img.id !== image.id,
    );
    if (activePhotoIndex.value >= allPhotos.value.length) {
      activePhotoIndex.value = Math.max(0, allPhotos.value.length - 1);
    }
  }
}

async function handleSave() {
  errorMessage.value = "";

  if (!form.name.trim() || !form.license_plate.trim()) {
    errorMessage.value = "Nama armada dan nomor polisi wajib diisi.";
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

    const { data: updated, error } = await supabase
      .from("vehicles")
      .update(payload)
      .eq("id", props.vehicleId)
      .select()
      .maybeSingle();

    if (error) throw error;

    vehicle.value = updated;
    modalOpen.value = false;
  } catch (err) {
    errorMessage.value =
      err?.code === "23505"
        ? "Nomor polisi sudah terdaftar pada armada lain."
        : (err?.message ?? "Gagal menyimpan perubahan armada.");
  } finally {
    saving.value = false;
  }
}

// ==========================================
// HAPUS UNIT KENDARAAN
// ==========================================
async function handleDelete() {
  const confirmed = window.confirm(
    `PERINGATAN: Hapus unit ${vehicle.value?.name} (${vehicle.value?.license_plate})?\n\nSeluruh riwayat sewa unit ini akan ikut terhapus secara permanen.`,
  );
  if (!confirmed) return;

  deleting.value = true;
  errorMessage.value = "";

  const { error } = await supabase
    .from("vehicles")
    .delete()
    .eq("id", props.vehicleId);

  if (error) {
    errorMessage.value = error.message;
    deleting.value = false;
  } else {
    router.replace({ name: "admin-vehicles" });
  }
}

// Buka KTP Customer
async function openKtp(booking) {
  if (!booking.ktp_image_url) return;

  const { data, error } = await supabase.storage
    .from(KTP_BUCKET)
    .createSignedUrl(booking.ktp_image_url, 120);

  if (error) {
    window.alert("Gagal memuat dokumen KTP: " + error.message);
    return;
  }

  window.open(data.signedUrl, "_blank", "noopener");
}

onMounted(loadData);
</script>

<template>
  <div class="space-y-6">
    <!-- Navigasi kembali & Aksi Utama -->
    <div class="flex flex-wrap items-center justify-between gap-4">
      <RouterLink
        :to="{ name: 'admin-vehicles' }"
        class="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 transition-colors hover:text-blue-600 cursor-pointer"
      >
        <ArrowLeft class="h-4 w-4" />
        Kembali ke Manajemen Armada
      </RouterLink>

      <div v-if="vehicle && !loading" class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          class="inline-flex items-center gap-1.5 rounded-xl border border-slate-300 bg-white px-3.5 py-2 text-xs font-semibold text-slate-700 shadow-xs transition-colors hover:bg-slate-50 cursor-pointer"
          @click="openEdit"
        >
          <Pencil class="h-4 w-4 text-slate-500" />
          Ubah Data Armada
        </button>

        <button
          type="button"
          :disabled="deleting"
          class="inline-flex items-center gap-1.5 rounded-xl border border-red-200 bg-white px-3.5 py-2 text-xs font-semibold text-red-600 shadow-xs transition-colors hover:bg-red-50 disabled:opacity-60 cursor-pointer"
          @click="handleDelete"
        >
          <LoaderCircle v-if="deleting" class="h-4 w-4 animate-spin" />
          <Trash2 v-else class="h-4 w-4" />
          Hapus Unit
        </button>
      </div>
    </div>

    <!-- Alert error jika ada -->
    <p
      v-if="errorMessage && !modalOpen"
      class="flex items-start gap-2 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
    >
      <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
      <span>{{ errorMessage }}</span>
    </p>

    <!-- State Loading -->
    <div
      v-if="loading"
      class="flex items-center justify-center gap-2 rounded-2xl border border-slate-200 bg-white py-20 text-sm text-slate-500"
    >
      <LoaderCircle class="h-5 w-5 animate-spin" />
      Memuat data armada &amp; riwayat sewa...
    </div>

    <template v-else-if="vehicle">
      <!-- Header Ringkasan Unit -->
      <section
        class="flex flex-col justify-between gap-4 rounded-2xl border border-slate-200 bg-white p-5 shadow-xs md:flex-row md:items-center sm:p-6"
      >
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <span
              class="rounded bg-blue-50 px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider text-blue-600"
            >
              {{ typeMeta.label }}
            </span>
          </div>

          <h1 class="mt-2 text-2xl font-extrabold text-slate-800">
            {{ vehicle.name }}
          </h1>
          <p class="text-sm font-semibold text-slate-500">
            {{ vehicle.license_plate }} ·
            <span class="text-blue-600">{{
              rupiah(vehicle.price_per_day)
            }}</span>
            <span class="text-xs font-normal text-slate-400">/hari</span>
          </p>
        </div>
      </section>

      <!-- KPI Kartu Statistik Armada -->
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-2">
        <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-xs">
          <p class="text-xs font-medium text-slate-500">Total Booking</p>
          <p class="mt-1 text-2xl font-extrabold text-slate-800">
            {{ stats.total }}
          </p>
          <p class="text-[11px] text-slate-400">Sepanjang waktu</p>
        </div>
        <div class="rounded-2xl border border-slate-200 bg-white p-4 shadow-xs">
          <p class="text-xs font-medium text-slate-500">
            Total Pendapatan Unit
          </p>
          <p class="mt-1 text-2xl font-extrabold text-blue-600">
            {{ rupiah(stats.revenue) }}
          </p>
          <p class="text-[11px] text-slate-400">Dari sewa selesai</p>
        </div>
      </div>

      <!-- Layout 2 Kolom: Detail Armada (Kiri) & Riwayat Sewa (Kanan) -->
      <div class="grid grid-cols-1 gap-6 lg:grid-cols-12">
        <!-- Kolom Kiri: Informasi Armada & Galeri Foto (5 kolom) -->
        <div class="space-y-6 lg:col-span-5">
          <!-- Foto & Galeri -->
          <section
            class="overflow-hidden rounded-2xl border border-slate-200 bg-white shadow-xs"
          >
            <div
              class="relative flex h-60 items-center justify-center bg-slate-900 sm:h-72"
            >
              <img
                v-if="activePhoto"
                :src="activePhoto"
                :alt="vehicle.name"
                class="h-full w-full object-contain"
              />
              <span v-else class="text-7xl">{{ typeMeta.emoji }}</span>

              <span
                v-if="activePhoto && activePhotoIndex === 0"
                class="absolute bottom-3 left-3 rounded-md bg-slate-900/80 px-2 py-1 text-[10px] font-bold uppercase tracking-wider text-white backdrop-blur-xs"
              >
                Thumbnail Utama
              </span>

              <span
                v-if="allPhotos.length > 1"
                class="absolute bottom-3 right-3 rounded-full bg-slate-900/75 px-2.5 py-0.5 text-xs font-semibold text-white backdrop-blur-xs"
              >
                {{ activePhotoIndex + 1 }} / {{ allPhotos.length }}
              </span>
            </div>

            <!-- Galeri Foto Armada (Inline) -->
            <div class="p-4 space-y-3">
              <div class="flex items-center justify-between">
                <div>
                  <h3
                    class="flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-slate-700"
                  >
                    <Images class="h-4 w-4 text-blue-600" />
                    Galeri Foto Armada
                  </h3>
                  <p class="text-[11px] text-slate-400">
                    Foto pertama otomatis menjadi thumbnail unit di katalog.
                  </p>
                </div>
                <span
                  class="rounded bg-blue-50 px-2 py-0.5 text-[10px] font-semibold text-blue-700"
                >
                  {{ galleryImages.length }} foto
                </span>
              </div>

              <!-- Alert error jika upload/hapus galeri gagal -->
              <p
                v-if="galleryError"
                class="flex items-start gap-1.5 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700"
              >
                <TriangleAlert class="mt-0.5 h-3.5 w-3.5 shrink-0" />
                <span>{{ galleryError }}</span>
              </p>

              <!-- Grid Galeri Foto + Card Kosong Icon Plus -->
              <div class="grid grid-cols-3 gap-2.5 sm:grid-cols-4">
                <!-- Setiap gambar di galeri -->
                <div
                  v-for="(img, idx) in galleryImages"
                  :key="img.id"
                  class="group relative aspect-4/3 overflow-hidden rounded-xl border-2 transition-all cursor-pointer"
                  :class="
                    idx === activePhotoIndex
                      ? 'border-blue-600 ring-2 ring-blue-100 shadow-xs'
                      : 'border-slate-200 hover:border-slate-300'
                  "
                  @click="activePhotoIndex = idx"
                >
                  <img
                    :src="img.image_url"
                    :alt="`Foto ${idx + 1}`"
                    class="h-full w-full object-cover transition-transform duration-200 group-hover:scale-105"
                  />

                  <!-- Badge Thumbnail untuk foto pertama -->
                  <span
                    v-if="idx === 0"
                    class="pointer-events-none absolute bottom-1 left-1 rounded bg-slate-900/80 px-1.5 py-0.5 text-[8px] font-bold uppercase tracking-wider text-white backdrop-blur-xs"
                  >
                    Thumbnail
                  </span>

                  <!-- Button dengan logo hapus di pojok kanan atas -->
                  <button
                    type="button"
                    title="Hapus foto ini dari galeri"
                    class="absolute right-1 top-1 flex h-6 w-6 items-center justify-center rounded-full bg-white/90 text-red-600 shadow-sm backdrop-blur-xs transition-colors hover:bg-red-600 hover:text-white cursor-pointer"
                    @click.stop="removeGalleryImage(img)"
                  >
                    <Trash2 class="h-3 w-3" />
                  </button>
                </div>

                <!-- Card kosong dengan icon plus untuk menambah/upload foto -->
                <div
                  class="relative aspect-4/3 flex cursor-pointer flex-col items-center justify-center gap-1.5 rounded-xl border-2 border-dashed border-slate-300 bg-slate-50 p-2 text-center transition-colors hover:border-blue-500 hover:bg-blue-50/60"
                  :class="{
                    'pointer-events-none opacity-60': galleryUploading,
                  }"
                  title="Tambah foto ke galeri"
                  @click="galleryFileInput?.click()"
                >
                  <LoaderCircle
                    v-if="galleryUploading"
                    class="h-5 w-5 animate-spin text-blue-600"
                  />
                  <template v-else>
                    <div
                      class="flex h-7 w-7 items-center justify-center rounded-full bg-blue-100 text-blue-600 shadow-2xs"
                    >
                      <Plus class="h-4 w-4" />
                    </div>
                    <span class="text-[10px] font-semibold text-slate-600"
                      >Tambah Foto</span
                    >
                  </template>
                </div>
              </div>

              <!-- Input file tersembunyi (otomatis upload saat file dipilih) -->
              <input
                ref="galleryFileInput"
                type="file"
                accept="image/*"
                multiple
                class="hidden"
                @change="handleGalleryUpload"
              />
            </div>
          </section>

          <!-- Spesifikasi & Fasilitas (Tags) -->
          <section
            class="rounded-2xl border border-slate-200 bg-white p-5 shadow-xs space-y-4"
          >
            <h2
              class="text-sm font-bold uppercase tracking-wider text-slate-700"
            >
              Spesifikasi &amp; Fasilitas
            </h2>

            <div v-if="vehicleTags.length" class="flex flex-wrap gap-2">
              <span
                v-for="tag in vehicleTags"
                :key="tag"
                class="inline-flex items-center gap-1.5 rounded-lg border border-blue-200/80 bg-blue-50/70 px-3 py-1.5 text-xs font-semibold text-blue-800"
              >
                <Check class="h-3.5 w-3.5 text-blue-600" />
                {{ tag }}
              </span>
            </div>
            <p v-else class="text-xs italic text-slate-400">
              Belum ada tags fasilitas yang ditambahkan untuk unit ini.
            </p>

            <div class="border-t border-slate-100 pt-3 space-y-2 text-xs">
              <div class="flex justify-between">
                <span class="text-slate-400">Nomor Polisi</span>
                <span class="font-bold text-slate-700">{{
                  vehicle.license_plate
                }}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-slate-400">Jenis Kendaraan</span>
                <span class="font-bold text-slate-700">{{
                  typeMeta.label
                }}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-slate-400">Status Operasional</span>
                <span class="font-bold text-slate-700">{{
                  vehicle.status
                }}</span>
              </div>
              <div class="flex justify-between">
                <span class="text-slate-400">Tarif / Hari</span>
                <span class="font-bold text-blue-600">{{
                  rupiah(vehicle.price_per_day)
                }}</span>
              </div>
            </div>

            <div
              v-if="vehicle.description"
              class="border-t border-slate-100 pt-3"
            >
              <p class="text-xs text-slate-400 mb-1">Deskripsi Tambahan</p>
              <p class="text-xs text-slate-600 leading-relaxed">
                {{ vehicle.description }}
              </p>
            </div>
          </section>
        </div>

        <!-- Kolom Kanan: Data Sewa & Riwayat Booking (7 kolom) -->
        <div class="space-y-4 lg:col-span-7">
          <div class="space-y-3">
            <div class="flex flex-wrap items-center justify-between gap-3">
              <div>
                <h2 class="text-base font-bold text-slate-800">
                  Data &amp; Riwayat Sewa
                </h2>
                <p class="text-xs text-slate-500">
                  Seluruh transaksi dan riwayat sewa khusus unit ini.
                </p>
              </div>

              <!-- Filter Status (Dropdown) -->
              <div class="flex items-center gap-2">
                <label
                  for="status-filter"
                  class="text-xs font-semibold text-slate-500"
                >
                  Status:
                </label>
                <select
                  id="status-filter"
                  v-model="statusFilter"
                  class="rounded-xl border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-2xs focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 cursor-pointer"
                >
                  <option value="ALL">Semua Status</option>
                  <option value="ACTIVE">Sedang Disewa</option>
                  <option value="APPROVED">Disetujui</option>
                  <option value="COMPLETED">Selesai</option>
                  <option value="PENDING">Menunggu Verifikasi</option>
                  <option value="CANCELLED">Dibatalkan</option>
                </select>
              </div>
            </div>

            <!-- Filter Periode Waktu Transaksi (Bulanan, Mingguan, Harian, Custom) -->
            <div
              class="flex flex-wrap items-center justify-between gap-2 rounded-xl border border-slate-200 bg-white p-2.5 shadow-2xs"
            >
              <div class="flex flex-wrap items-center gap-1.5">
                <span
                  class="mr-1 flex items-center gap-1 text-[11px] font-bold uppercase tracking-wider text-slate-400"
                >
                  <Calendar class="h-3.5 w-3.5 text-slate-400" />
                  Periode:
                </span>
                <button
                  type="button"
                  class="rounded-lg px-2.5 py-1 text-xs transition-colors cursor-pointer"
                  :class="
                    timeFilter === 'ALL'
                      ? 'bg-blue-600 font-semibold text-white shadow-2xs'
                      : 'bg-slate-50 font-medium text-slate-600 hover:bg-slate-100'
                  "
                  @click="timeFilter = 'ALL'"
                >
                  Semua
                </button>
                <button
                  type="button"
                  class="rounded-lg px-2.5 py-1 text-xs transition-colors cursor-pointer"
                  :class="
                    timeFilter === 'MONTH'
                      ? 'bg-blue-600 font-semibold text-white shadow-2xs'
                      : 'bg-slate-50 font-medium text-slate-600 hover:bg-slate-100'
                  "
                  @click="timeFilter = 'MONTH'"
                >
                  Bulanan
                </button>
                <button
                  type="button"
                  class="rounded-lg px-2.5 py-1 text-xs transition-colors cursor-pointer"
                  :class="
                    timeFilter === 'WEEK'
                      ? 'bg-blue-600 font-semibold text-white shadow-2xs'
                      : 'bg-slate-50 font-medium text-slate-600 hover:bg-slate-100'
                  "
                  @click="timeFilter = 'WEEK'"
                >
                  Mingguan
                </button>
                <button
                  type="button"
                  class="rounded-lg px-2.5 py-1 text-xs transition-colors cursor-pointer"
                  :class="
                    timeFilter === 'DAILY'
                      ? 'bg-blue-600 font-semibold text-white shadow-2xs'
                      : 'bg-slate-50 font-medium text-slate-600 hover:bg-slate-100'
                  "
                  @click="timeFilter = 'DAILY'"
                >
                  Harian
                </button>
                <button
                  type="button"
                  class="rounded-lg px-2.5 py-1 text-xs transition-colors cursor-pointer"
                  :class="
                    timeFilter === 'CUSTOM'
                      ? 'bg-blue-600 font-semibold text-white shadow-2xs'
                      : 'bg-slate-50 font-medium text-slate-600 hover:bg-slate-100'
                  "
                  @click="timeFilter = 'CUSTOM'"
                >
                  Custom
                </button>
              </div>

              <!-- Badge info jumlah -->
              <span class="text-[11px] font-medium text-slate-500">
                {{ filteredBookings.length }} transaksi
              </span>
            </div>

            <!-- Input Rentang Tanggal Custom -->
            <div
              v-if="timeFilter === 'CUSTOM'"
              class="flex flex-wrap items-center gap-2 rounded-xl border border-blue-100 bg-blue-50/50 p-3 text-xs"
            >
              <div class="flex items-center gap-1.5">
                <span class="font-semibold text-slate-600">Dari:</span>
                <input
                  v-model="customStartDate"
                  type="date"
                  class="rounded-lg border border-slate-300 bg-white px-2.5 py-1 text-xs text-slate-700 shadow-2xs focus:border-blue-600 focus:outline-none"
                />
              </div>
              <div class="flex items-center gap-1.5">
                <span class="font-semibold text-slate-600">Sampai:</span>
                <input
                  v-model="customEndDate"
                  type="date"
                  class="rounded-lg border border-slate-300 bg-white px-2.5 py-1 text-xs text-slate-700 shadow-2xs focus:border-blue-600 focus:outline-none"
                />
              </div>
              <button
                v-if="customStartDate || customEndDate"
                type="button"
                class="ml-auto rounded-lg px-2 py-1 text-[11px] font-semibold text-blue-700 hover:bg-blue-100 cursor-pointer"
                @click="
                  customStartDate = '';
                  customEndDate = '';
                "
              >
                Reset Tanggal
              </button>
            </div>
          </div>

          <!-- Kosong -->
          <div
            v-if="filteredBookings.length === 0"
            class="space-y-3 rounded-2xl border border-dashed border-slate-300 bg-white py-16 text-center text-sm text-slate-500"
          >
            <p>Belum ada data transaksi sewa yang sesuai dengan filter.</p>
            <button
              v-if="
                timeFilter !== 'ALL' ||
                statusFilter !== 'ALL' ||
                customStartDate ||
                customEndDate
              "
              type="button"
              class="inline-flex items-center gap-1 rounded-lg border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-2xs hover:bg-slate-50 cursor-pointer"
              @click="resetFilters"
            >
              Reset Filter
            </button>
          </div>

          <!-- Daftar Riwayat Sewa -->
          <div v-else class="space-y-3.5">
            <article
              v-for="booking in filteredBookings"
              :key="booking.id"
              class="overflow-hidden rounded-2xl border border-slate-200 bg-white p-5 shadow-xs space-y-4"
            >
              <!-- Customer & Status -->
              <div
                class="flex flex-wrap items-start justify-between gap-3 border-b border-slate-100 pb-3"
              >
                <div class="flex items-center gap-3">
                  <div
                    class="flex h-10 w-10 shrink-0 items-center justify-center overflow-hidden rounded-full bg-blue-100 text-sm font-bold text-blue-700"
                  >
                    <img
                      v-if="booking.customer?.avatar_url"
                      :src="booking.customer.avatar_url"
                      :alt="booking.customer?.full_name ?? 'Customer'"
                      class="h-full w-full object-cover"
                    />
                    <span v-else>
                      {{
                        (
                          booking.customer?.full_name ??
                          booking.customer?.email ??
                          "?"
                        )
                          .charAt(0)
                          .toUpperCase()
                      }}
                    </span>
                  </div>
                  <div>
                    <h3 class="text-sm font-bold text-slate-800">
                      {{ booking.customer?.full_name ?? "Tanpa Nama" }}
                    </h3>
                    <p class="text-xs text-slate-500">
                      {{ booking.customer?.email }} ·
                      {{ booking.customer?.phone_number || "Tanpa No. HP" }}
                    </p>
                  </div>
                </div>

                <StatusBadge :value="booking.status" />
              </div>

              <!-- Detail Jadwal & Biaya -->
              <div class="grid grid-cols-2 gap-3 text-xs sm:grid-cols-4">
                <div>
                  <p class="text-slate-400">Mulai Sewa</p>
                  <p class="font-semibold text-slate-700">
                    {{ formatDateTime(booking.start_date) }}
                  </p>
                </div>
                <div>
                  <p class="text-slate-400">Selesai Sewa</p>
                  <p class="font-semibold text-slate-700">
                    {{ formatDateTime(booking.end_date) }}
                  </p>
                </div>
                <div>
                  <p class="text-slate-400">Durasi</p>
                  <p class="font-semibold text-slate-700">
                    {{ rentalDays(booking.start_date, booking.end_date) }} Hari
                  </p>
                </div>
                <div>
                  <p class="text-slate-400">Total Biaya</p>
                  <p class="font-bold text-blue-600">
                    {{ rupiah(booking.total_price) }}
                  </p>
                </div>
              </div>

              <!-- Info Pengembalian jika selesai -->
              <div
                v-if="booking.return_info"
                class="rounded-xl bg-slate-50 p-3 text-xs space-y-1.5 border border-slate-100"
              >
                <div
                  class="flex items-center justify-between text-slate-700 font-semibold"
                >
                  <span class="flex items-center gap-1 text-emerald-700">
                    <CheckCircle2 class="h-3.5 w-3.5" />
                    Unit Dikembalikan:
                    {{ formatDateTime(booking.return_info.return_date) }}
                  </span>
                  <span class="text-slate-800 font-bold">
                    Total Akhir: {{ rupiah(booking.return_info.final_price) }}
                  </span>
                </div>
                <div class="flex gap-4 text-slate-500 text-[11px]">
                  <span
                    >Denda Telat:
                    {{ rupiah(booking.return_info.late_fee) }}</span
                  >
                  <span
                    >Kerusakan:
                    {{ rupiah(booking.return_info.damage_fee) }}</span
                  >
                  <span v-if="booking.return_info.admin_notes">
                    Catatan: {{ booking.return_info.admin_notes }}
                  </span>
                </div>
              </div>

              <!-- Action KTP & Catatan -->
              <div class="flex items-center justify-between pt-1 text-xs">
                <p
                  v-if="booking.notes"
                  class="text-slate-500 italic text-[11px]"
                >
                  Catatan: "{{ booking.notes }}"
                </p>
                <span v-else></span>

                <button
                  v-if="booking.ktp_image_url"
                  type="button"
                  class="inline-flex items-center gap-1.5 rounded-lg border border-slate-200 bg-white px-2.5 py-1 text-xs font-semibold text-slate-700 shadow-2xs hover:bg-slate-50 cursor-pointer"
                  @click="openKtp(booking)"
                >
                  <IdCard class="h-3.5 w-3.5 text-blue-600" />
                  Lihat KTP
                </button>
              </div>
            </article>
          </div>
        </div>
      </div>
    </template>

    <!-- Modal Form Edit Armada -->
    <AppModal
      :open="modalOpen"
      title="Ubah Data Armada"
      @close="modalOpen = false"
    >
      <form class="space-y-4" @submit.prevent="handleSave">
        <div>
          <label
            for="edit-name"
            class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
          >
            Nama Kendaraan
          </label>
          <input
            id="edit-name"
            v-model="form.name"
            type="text"
            required
            class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label
              for="edit-type"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Jenis
            </label>
            <select
              id="edit-type"
              v-model="form.type"
              class="w-full rounded-xl border border-slate-300 bg-white px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            >
              <option value="CAR">Mobil</option>
              <option value="MOTORCYCLE">Motor</option>
            </select>
          </div>

          <div>
            <label
              for="edit-plate"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Nomor Polisi
            </label>
            <input
              id="edit-plate"
              v-model="form.license_plate"
              type="text"
              required
              class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm uppercase text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <div>
            <label
              for="edit-price"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Tarif / Hari (Rp)
            </label>
            <input
              id="edit-price"
              v-model="form.price_per_day"
              type="number"
              min="0"
              step="1000"
              required
              class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <div>
            <label
              for="edit-status"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Status Operasional
            </label>
            <select
              id="edit-status"
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
            for="edit-description"
            class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
          >
            Deskripsi
          </label>
          <textarea
            id="edit-description"
            v-model="form.description"
            rows="2"
            class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          ></textarea>
        </div>

        <!-- Tags Spesifikasi & Fasilitas -->
        <div class="rounded-xl border border-slate-200 p-4 space-y-3">
          <div class="flex items-center justify-between">
            <label
              for="edit-tag-select"
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

          <!-- Select option dropdown -->
          <div>
            <select
              id="edit-tag-select"
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

          <!-- Input tag kustom -->
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

          <!-- Tag Terpilih -->
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
              Belum ada tag dipilih.
            </p>
          </div>

          <!-- Rekomendasi Cepat -->
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

        <p
          v-if="errorMessage"
          class="flex items-start gap-2 rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs font-medium text-red-700"
        >
          <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
          <span>{{ errorMessage }}</span>
        </p>

        <div class="flex gap-3 pt-2">
          <button
            type="button"
            class="flex-1 rounded-xl border border-slate-300 px-4 py-2.5 text-sm font-semibold text-slate-600 transition-colors hover:bg-slate-50 cursor-pointer"
            @click="modalOpen = false"
          >
            Batal
          </button>
          <button
            type="submit"
            :disabled="saving"
            class="flex flex-1 items-center justify-center gap-2 rounded-xl bg-blue-600 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-blue-700 disabled:opacity-60 cursor-pointer"
          >
            <LoaderCircle v-if="saving" class="h-4 w-4 animate-spin" />
            {{ saving ? "Menyimpan..." : "Simpan Perubahan" }}
          </button>
        </div>
      </form>
    </AppModal>
  </div>
</template>
