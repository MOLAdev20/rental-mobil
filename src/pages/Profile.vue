<script setup lang="js">
import {
  AlertCircle,
  ArrowLeft,
  Building2,
  CheckCircle2,
  ExternalLink,
  Eye,
  HeartHandshake,
  IdCard,
  ImagePlus,
  LoaderCircle,
  MapPin,
  RefreshCw,
  Save,
  ShieldCheck,
  TriangleAlert,
  UploadCloud,
  X,
} from "@lucide/vue";
import { computed, onMounted, reactive, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuth } from "../composables/useAuth";
import {
  getMissingProfileFields,
  isProfileComplete,
  REQUIRED_PROFILE_FIELDS,
} from "../lib/format";
import { KTP_BUCKET, supabase } from "../lib/supabase-client";

const route = useRoute();
const router = useRouter();
const { profile, updateProfile, refreshProfile, isAdmin } = useAuth();

const saving = ref(false);
const saveError = ref("");
const saveSuccess = ref(false);

const ktpFile = ref(null);
const ktpPreview = ref("");
const existingKtpPath = ref("");
const existingKtpSignedUrl = ref("");
const loadingKtpPreview = ref(false);
const ktpFileInput = ref(null);

const form = reactive({
  full_name: "",
  phone_number: "",
  nik: "",
  sim_number: "",
  address: "",
  city: "",
  emergency_contact_name: "",
  emergency_contact_phone: "",
  emergency_contact_relation: "Orang Tua",
  job_title: "",
  social_media: "",
});

const isRedirectedFromBooking = computed(() => route.query.required === "1");
const redirectTarget = computed(() => {
  const r = route.query.redirect;
  return typeof r === "string" && r.startsWith("/") ? r : null;
});

const missingFields = computed(() => getMissingProfileFields(profile.value));
const isComplete = computed(() => isProfileComplete(profile.value));

async function loadExistingKtpUrl(path) {
  if (!path) {
    existingKtpSignedUrl.value = "";
    return;
  }
  loadingKtpPreview.value = true;
  try {
    const { data, error } = await supabase.storage
      .from(KTP_BUCKET)
      .createSignedUrl(path, 3600);
    if (!error && data?.signedUrl) {
      existingKtpSignedUrl.value = data.signedUrl;
    }
  } catch (err) {
    console.error("Gagal memuat URL KTP:", err);
  } finally {
    loadingKtpPreview.value = false;
  }
}

function handleKtpFileChange(event) {
  const selected = event.target.files?.[0] ?? null;
  if (!selected) return;

  if (selected.size > 5 * 1024 * 1024) {
    saveError.value = "Ukuran file KTP maksimal 5 MB.";
    return;
  }

  saveError.value = "";
  ktpFile.value = selected;
  if (ktpPreview.value) {
    URL.revokeObjectURL(ktpPreview.value);
  }
  ktpPreview.value = URL.createObjectURL(selected);
}

function removeSelectedKtp() {
  if (ktpPreview.value) {
    URL.revokeObjectURL(ktpPreview.value);
  }
  ktpPreview.value = "";
  ktpFile.value = null;
  if (ktpFileInput.value) {
    ktpFileInput.value.value = "";
  }
}

function fillFormFromProfile() {
  if (!profile.value) return;
  const p = profile.value;
  const d = p.detail_user || p;

  form.full_name = p.full_name ?? "";
  form.phone_number = p.phone_number ?? "";
  form.nik = d.nik ?? p.nik ?? "";
  form.sim_number = d.sim_number ?? p.sim_number ?? "";
  form.address = d.address ?? p.address ?? "";
  form.city = d.city ?? p.city ?? "";
  form.emergency_contact_name =
    d.emergency_contact_name ?? p.emergency_contact_name ?? "";
  form.emergency_contact_phone =
    d.emergency_contact_phone ?? p.emergency_contact_phone ?? "";
  form.emergency_contact_relation =
    d.emergency_contact_relation ?? p.emergency_contact_relation ?? "Orang Tua";
  form.job_title = d.job_title ?? p.job_title ?? "";
  form.social_media = d.social_media ?? p.social_media ?? "";

  existingKtpPath.value = d.ktp_image_url ?? p.ktp_image_url ?? "";
  if (existingKtpPath.value) {
    loadExistingKtpUrl(existingKtpPath.value);
  }
}

async function handleSave() {
  saveError.value = "";
  saveSuccess.value = false;

  // Validasi format NIK minimal 16 angka jika diisi
  const cleanedNik = form.nik.trim();
  if (cleanedNik && !/^\d{16}$/.test(cleanedNik)) {
    saveError.value =
      "NIK (Nomor Induk Kependudukan) harus berupa 16 digit angka.";
    return;
  }

  // Validasi KTP wajib diunggah
  const hasKtp = Boolean(ktpFile.value || existingKtpPath.value);
  if (!hasKtp) {
    saveError.value = "Foto dokumen KTP wajib diunggah untuk verifikasi rental.";
    return;
  }

  saving.value = true;

  try {
    let finalKtpPath = existingKtpPath.value;

    // Jika ada file KTP baru yang dipilih, upload ke Supabase Storage
    if (ktpFile.value) {
      const userId = profile.value?.id;
      if (!userId) throw new Error("Sesi pengguna tidak valid.");

      const extension =
        ktpFile.value.name.split(".").pop()?.toLowerCase() || "jpg";
      const storagePath = `${userId}/ktp-${Date.now()}.${extension}`;

      const { error: uploadErr } = await supabase.storage
        .from(KTP_BUCKET)
        .upload(storagePath, ktpFile.value, {
          cacheControl: "3600",
          upsert: true,
          contentType: ktpFile.value.type || "image/jpeg",
        });

      if (uploadErr) throw uploadErr;
      finalKtpPath = storagePath;
      existingKtpPath.value = storagePath;
    }

    const payload = {
      full_name: form.full_name.trim(),
      phone_number: form.phone_number.trim(),
      nik: cleanedNik,
      sim_number: form.sim_number.trim(),
      ktp_image_url: finalKtpPath || null,
      address: form.address.trim(),
      city: form.city.trim(),
      emergency_contact_name: form.emergency_contact_name.trim(),
      emergency_contact_phone: form.emergency_contact_phone.trim(),
      emergency_contact_relation:
        form.emergency_contact_relation.trim() || null,
      job_title: form.job_title.trim() || null,
      social_media: form.social_media.trim() || null,
    };

    await updateProfile(payload);
    saveSuccess.value = true;

    if (finalKtpPath) {
      loadExistingKtpUrl(finalKtpPath);
      ktpFile.value = null;
      if (ktpPreview.value) {
        URL.revokeObjectURL(ktpPreview.value);
        ktpPreview.value = "";
      }
    }

    // Jika user datang karena dialihkan dari proses sewa, arahkan kembali setelah simpan
    if (redirectTarget.value) {
      setTimeout(() => {
        router.push(redirectTarget.value);
      }, 1200);
    }
  } catch (err) {
    saveError.value = err?.message ?? "Gagal menyimpan data profil.";
  } finally {
    saving.value = false;
  }
}

onMounted(async () => {
  await refreshProfile();
  if (isAdmin.value) {
    router.replace({ name: "admin-bookings" });
    return;
  }
  fillFormFromProfile();
});
</script>

<template>
  <div class="mx-auto max-w-3xl space-y-6">
    <!-- Header & Navigasi Balik -->
    <div class="flex items-center justify-between">
      <button
        type="button"
        class="inline-flex items-center gap-1.5 text-xs font-semibold text-slate-500 transition-colors hover:text-blue-600 cursor-pointer"
        @click="router.back()"
      >
        <ArrowLeft class="h-4 w-4" />
        Kembali
      </button>

      <!-- Badge Status Kelengkapan Data -->
      <span
        v-if="isComplete"
        class="inline-flex items-center gap-1.5 rounded-full bg-emerald-50 px-3 py-1 text-xs font-bold text-emerald-700 border border-emerald-200"
      >
        <ShieldCheck class="h-4 w-4 text-emerald-600" />
        Profil Lengkap &amp; Terverifikasi
      </span>
      <span
        v-else
        class="inline-flex items-center gap-1.5 rounded-full bg-amber-50 px-3 py-1 text-xs font-bold text-amber-700 border border-amber-200"
      >
        <AlertCircle class="h-4 w-4 text-amber-600" />
        Profil Belum Lengkap
      </span>
    </div>

    <!-- Alert Khusus Jika Dialihkan Dari Tombol Sewa -->
    <div
      v-if="isRedirectedFromBooking && !saveSuccess"
      class="rounded-2xl border-2 border-amber-300 bg-amber-50/90 p-5 shadow-xs space-y-2"
    >
      <div class="flex items-center gap-2 text-amber-900 font-bold text-sm">
        <TriangleAlert class="h-5 w-5 text-amber-600 shrink-0" />
        <span>Harap Lengkapi Data Diri Terlebih Dahulu</span>
      </div>
    </div>

    <!-- Alert Berhasil Simpan -->
    <div
      v-if="saveSuccess"
      class="flex items-center gap-3 rounded-2xl border border-emerald-200 bg-emerald-50 p-4 text-emerald-800 text-sm shadow-xs"
    >
      <CheckCircle2 class="h-5 w-5 text-emerald-600 shrink-0" />
      <div>
        <p class="font-bold">Data pribadi Anda berhasil disimpan!</p>
        <p v-if="redirectTarget" class="text-xs text-emerald-700 mt-0.5">
          Mengarahkan Anda kembali ke formulir sewa kendaraan...
        </p>
      </div>
    </div>

    <!-- Alert Error Simpan -->
    <div
      v-if="saveError"
      class="flex items-start gap-2.5 rounded-2xl border border-red-200 bg-red-50 p-4 text-red-700 text-xs shadow-xs"
    >
      <TriangleAlert class="h-4 w-4 text-red-600 shrink-0 mt-0.5" />
      <span>{{ saveError }}</span>
    </div>

    <!-- Form Data Pribadi Penyewa -->
    <form class="space-y-6" @submit.prevent="handleSave">
      <!-- 1. Identitas Pokok Penyewa -->
      <section
        class="rounded-2xl border border-slate-200 bg-white p-5 shadow-xs space-y-4 sm:p-6"
      >
        <div class="border-b border-slate-100 pb-3">
          <h2
            class="flex items-center gap-2 text-base font-bold text-slate-800"
          >
            <IdCard class="h-5 w-5 text-blue-600" />
            Identitas Pokok (Sesuai KTP)
          </h2>
          <p class="text-xs text-slate-400">
            Informasi identitas resmi sesuai dengan kartu tanda penduduk Anda.
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <!-- Nama Lengkap -->
          <div>
            <label
              for="full_name"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Nama Lengkap <span class="text-red-500">*</span>
            </label>
            <input
              id="full_name"
              v-model="form.full_name"
              type="text"
              required
              placeholder="Contoh: Budi Santoso"
              class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <!-- NIK KTP -->
          <div>
            <label
              for="nik"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              NIK KTP (16 Digit) <span class="text-red-500">*</span>
            </label>
            <input
              id="nik"
              v-model="form.nik"
              type="text"
              required
              maxlength="16"
              placeholder="Contoh: 3171012345670001"
              class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm font-mono text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <!-- Email (Readonly) -->
          <div>
            <label
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-400"
            >
              Email Akun
            </label>
            <input
              :value="profile?.email || '-'"
              type="email"
              disabled
              class="w-full rounded-xl border border-slate-200 bg-slate-50 px-3.5 py-2.5 text-sm text-slate-500 cursor-not-allowed"
            />
          </div>

          <!-- Nomor WhatsApp / HP -->
          <div>
            <label
              for="phone_number"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Nomor WhatsApp / HP <span class="text-red-500">*</span>
            </label>
            <input
              id="phone_number"
              v-model="form.phone_number"
              type="tel"
              required
              placeholder="Contoh: 081234567890"
              class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
            <p class="mt-1 text-[11px] text-slate-400">
              Digunakan admin untuk konfirmasi booking dan serah terima unit.
            </p>
          </div>

          <!-- Upload Dokumen Foto KTP (Disimpan di tabel detail_user) -->
          <div class="col-span-full border-t border-slate-100 pt-4">
            <div class="flex items-center justify-between mb-1.5">
              <label class="block text-xs font-bold uppercase tracking-wider text-slate-700">
                Foto Dokumen KTP Asli <span class="text-red-500">*</span>
              </label>
              <span
                v-if="existingKtpPath || ktpPreview"
                class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-0.5 text-[11px] font-semibold text-emerald-700"
              >
                <CheckCircle2 class="h-3.5 w-3.5" />
                KTP Terunggah
              </span>
            </div>
            <p class="text-xs text-slate-400 mb-3">
              Foto KTP disimpan sekali di profil Anda. Anda tidak perlu menguploadnya lagi saat menyewa unit.
            </p>

            <input
              ref="ktpFileInput"
              type="file"
              accept="image/jpeg,image/png,image/webp"
              class="hidden"
              @change="handleKtpFileChange"
            />

            <!-- Preview KTP Jika Ada -->
            <div
              v-if="ktpPreview || existingKtpSignedUrl"
              class="relative overflow-hidden rounded-2xl border border-slate-200 bg-slate-50 p-4"
            >
              <div class="flex flex-col gap-4 sm:flex-row sm:items-center">
                <div
                  class="relative h-32 w-full shrink-0 overflow-hidden rounded-xl border border-slate-200 bg-slate-200 shadow-xs sm:w-52"
                >
                  <img
                    :src="ktpPreview || existingKtpSignedUrl"
                    alt="Dokumen KTP"
                    class="h-full w-full object-cover"
                  />
                  <div
                    v-if="loadingKtpPreview"
                    class="absolute inset-0 flex items-center justify-center bg-white/70"
                  >
                    <LoaderCircle class="h-5 w-5 animate-spin text-blue-600" />
                  </div>
                </div>

                <div class="flex-1 space-y-2">
                  <div class="flex items-center gap-2">
                    <p class="text-sm font-bold text-slate-800">
                      {{ ktpFile ? ktpFile.name : 'Dokumen KTP Tersimpan' }}
                    </p>
                    <span
                      v-if="ktpFile"
                      class="rounded-md bg-blue-100 px-2 py-0.5 text-[10px] font-bold text-blue-700"
                    >
                      File Baru
                    </span>
                  </div>
                  <p class="text-xs text-slate-500">
                    Pastikan foto tidak buram, NIK dan nama jelas terbaca untuk memudahkan verifikasi saat menyewa.
                  </p>

                  <div class="flex flex-wrap gap-2 pt-1">
                    <button
                      type="button"
                      class="inline-flex items-center gap-1.5 rounded-xl border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 transition-colors hover:bg-slate-50 cursor-pointer"
                      @click="ktpFileInput?.click()"
                    >
                      <RefreshCw class="h-3.5 w-3.5" />
                      Ganti Foto KTP
                    </button>

                    <a
                      v-if="existingKtpSignedUrl || ktpPreview"
                      :href="ktpPreview || existingKtpSignedUrl"
                      target="_blank"
                      rel="noopener noreferrer"
                      class="inline-flex items-center gap-1.5 rounded-xl border border-slate-200 bg-white px-3 py-1.5 text-xs font-semibold text-blue-600 transition-colors hover:bg-blue-50"
                    >
                      <ExternalLink class="h-3.5 w-3.5" />
                      Buka Dokumen
                    </a>

                    <button
                      v-if="ktpFile"
                      type="button"
                      class="inline-flex items-center gap-1 rounded-xl border border-red-200 bg-white px-2.5 py-1.5 text-xs font-semibold text-red-600 transition-colors hover:bg-red-50 cursor-pointer"
                      title="Batalkan file baru"
                      @click="removeSelectedKtp"
                    >
                      <X class="h-3.5 w-3.5" />
                      Batal
                    </button>
                  </div>
                </div>
              </div>
            </div>

            <!-- Jika Belum Ada KTP -->
            <button
              v-else
              type="button"
              class="flex w-full flex-col items-center justify-center gap-2 rounded-2xl border-2 border-dashed border-slate-300 bg-slate-50/50 p-6 text-center transition-colors hover:border-blue-500 hover:bg-blue-50/40 cursor-pointer"
              @click="ktpFileInput?.click()"
            >
              <div
                class="flex h-12 w-12 items-center justify-center rounded-2xl bg-blue-100 text-blue-600 shadow-xs"
              >
                <ImagePlus class="h-6 w-6" />
              </div>
              <div>
                <p class="text-sm font-bold text-slate-800">
                  Klik untuk mengunggah foto KTP Anda
                </p>
                <p class="text-xs text-slate-400">
                  Format JPG, PNG, atau WebP (Maksimal 5 MB)
                </p>
              </div>
            </button>
          </div>
        </div>
      </section>

      <!-- 2. Legalitas Mengemudi & Alamat Domisili -->
      <section
        class="rounded-2xl border border-slate-200 bg-white p-5 shadow-xs space-y-4 sm:p-6"
      >
        <div class="border-b border-slate-100 pb-3">
          <h2
            class="flex items-center gap-2 text-base font-bold text-slate-800"
          >
            <MapPin class="h-5 w-5 text-blue-600" />
            Legalitas Mengemudi &amp; Domisili
          </h2>
          <p class="text-xs text-slate-400">
            Nomor izin mengemudi dan alamat tempat tinggal Anda saat ini.
          </p>
        </div>

        <div class="space-y-4">
          <div class="grid gap-4 sm:grid-cols-2">
            <!-- Nomor SIM -->
            <div>
              <label
                for="sim_number"
                class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >
                Nomor SIM (SIM A / SIM C) <span class="text-red-500">*</span>
              </label>
              <input
                id="sim_number"
                v-model="form.sim_number"
                type="text"
                required
                placeholder="Contoh: 1234-5678-901234"
                class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm font-mono text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
              />
              <p class="mt-1 text-[11px] text-slate-400">
                Wajib memiliki SIM aktif yang masih berlaku saat berkendara.
              </p>
            </div>

            <!-- Kota / Kabupaten -->
            <div>
              <label
                for="city"
                class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >
                Kota / Kabupaten Domisili <span class="text-red-500">*</span>
              </label>
              <input
                id="city"
                v-model="form.city"
                type="text"
                required
                placeholder="Contoh: Jakarta Selatan"
                class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
              />
            </div>
          </div>

          <!-- Alamat Lengkap -->
          <div>
            <label
              for="address"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Alamat Lengkap Domisili Saat Ini
              <span class="text-red-500">*</span>
            </label>
            <textarea
              id="address"
              v-model="form.address"
              rows="3"
              required
              placeholder="Contoh: Jl. Melati No. 12, RT 02/RW 05, Kel. Tebet Timur, Kec. Tebet"
              class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            ></textarea>
          </div>
        </div>
      </section>

      <!-- 3. Kontak Darurat (Emergency Contact) -->
      <section
        class="rounded-2xl border border-slate-200 bg-white p-5 shadow-xs space-y-4 sm:p-6"
      >
        <div class="border-b border-slate-100 pb-3">
          <div class="flex items-center justify-between">
            <h2
              class="flex items-center gap-2 text-base font-bold text-slate-800"
            >
              <HeartHandshake class="h-5 w-5 text-rose-500" />
              Kontak Darurat (Keluarga / Kerabat)
            </h2>
            <span
              class="rounded bg-rose-50 px-2 py-0.5 text-[10px] font-bold text-rose-600"
            >
              Krusial
            </span>
          </div>
          <p class="text-xs text-slate-400">
            Dihubungi hanya jika terjadi situasi mendesak/darurat (seperti
            kecelakaan atau unit kendala di jalan).
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-3">
          <!-- Nama Kontak Darurat -->
          <div>
            <label
              for="emergency_name"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Nama Lengkap <span class="text-red-500">*</span>
            </label>
            <input
              id="emergency_name"
              v-model="form.emergency_contact_name"
              type="text"
              required
              placeholder="Contoh: Siti Rahma"
              class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <!-- No. HP Kontak Darurat -->
          <div>
            <label
              for="emergency_phone"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Nomor Telepon / HP <span class="text-red-500">*</span>
            </label>
            <input
              id="emergency_phone"
              v-model="form.emergency_contact_phone"
              type="tel"
              required
              placeholder="Contoh: 081987654321"
              class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <!-- Hubungan -->
          <div>
            <label
              for="emergency_relation"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Hubungan
            </label>
            <select
              id="emergency_relation"
              v-model="form.emergency_contact_relation"
              class="w-full rounded-xl border border-slate-300 bg-white px-3.5 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 cursor-pointer"
            >
              <option value="Orang Tua">Orang Tua</option>
              <option value="Pasangan (Suami/Istri)">
                Pasangan (Suami/Istri)
              </option>
              <option value="Saudara Kandung">Saudara Kandung</option>
              <option value="Anak">Anak</option>
              <option value="Kerabat / Rekan Kerja">
                Kerabat / Rekan Kerja
              </option>
            </select>
          </div>
        </div>
      </section>

      <!-- 4. Informasi Tambahan (Screening Rental) -->
      <section
        class="rounded-2xl border border-slate-200 bg-white p-5 shadow-xs space-y-4 sm:p-6"
      >
        <div class="border-b border-slate-100 pb-3">
          <div class="flex items-center justify-between">
            <h2
              class="flex items-center gap-2 text-base font-bold text-slate-800"
            >
              <Building2 class="h-5 w-5 text-slate-600" />
              Informasi Tambahan (Opsional)
            </h2>
            <span class="text-xs text-slate-400">Verifikasi Tambahan</span>
          </div>
          <p class="text-xs text-slate-400">
            Membantu mempercepat proses verifikasi booking sewa armada oleh
            admin.
          </p>
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <!-- Pekerjaan / Perusahaan -->
          <div>
            <label
              for="job_title"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Pekerjaan / Instansi
            </label>
            <input
              id="job_title"
              v-model="form.job_title"
              type="text"
              placeholder="Contoh: Karyawan Swasta / Wiraswasta"
              class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>

          <!-- Akun Media Sosial -->
          <div>
            <label
              for="social_media"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >
              Akun Media Sosial
            </label>
            <input
              id="social_media"
              v-model="form.social_media"
              type="text"
              placeholder="Contoh: @budisantoso (Instagram / LinkedIn)"
              class="w-full rounded-xl border border-slate-300 px-3.5 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>
        </div>
      </section>

      <!-- Tombol Aksi Simpan -->
      <div class="flex flex-wrap items-center justify-between gap-3 pt-2">
        <p class="text-xs text-slate-400">
          <span class="text-red-500 font-bold">*</span> Menandakan kolom wajib
          diisi untuk verifikasi sewa.
        </p>

        <div class="flex items-center gap-2">
          <button
            type="submit"
            :disabled="saving"
            class="inline-flex items-center justify-center gap-2 rounded-xl bg-blue-600 px-6 py-2.5 text-sm font-semibold text-white shadow-md shadow-blue-500/20 transition-all hover:bg-blue-700 disabled:opacity-60 cursor-pointer"
          >
            <LoaderCircle v-if="saving" class="h-4 w-4 animate-spin" />
            <Save v-else class="h-4 w-4" />
            {{ saving ? "Menyimpan Data..." : "Simpan Informasi Pribadi" }}
          </button>
        </div>
      </div>
    </form>
  </div>
</template>
