<script setup lang="js">
import {
  AlertCircle,
  Briefcase,
  Check,
  Copy,
  ExternalLink,
  IdCard,
  Image,
  LoaderCircle,
  Mail,
  MapPin,
  Phone,
  Share2,
  ShieldCheck,
  User,
} from "@lucide/vue";
import { computed, ref, watch } from "vue";
import { KTP_BUCKET, supabase } from "../lib/supabase-client";
import AppModal from "./AppModal.vue";

const props = defineProps({
  open: { type: Boolean, default: false },
  customer: { type: Object, default: null },
});

const emit = defineEmits(["close"]);

const copiedField = ref("");
const loadingKtp = ref(false);

const detail = computed(() => {
  if (!props.customer) return {};
  if (Array.isArray(props.customer.detail_user)) {
    return props.customer.detail_user[0] || {};
  }
  return props.customer.detail_user || {};
});

async function openCustomerKtp() {
  const ktpPath = detail.value.ktp_image_url;
  if (!ktpPath) {
    alert("Customer belum mengunggah dokumen KTP di profil.");
    return;
  }
  loadingKtp.value = true;
  try {
    const { data, error } = await supabase.storage
      .from(KTP_BUCKET)
      .createSignedUrl(ktpPath, 180);
    if (error) throw error;
    if (data?.signedUrl) {
      window.open(data.signedUrl, "_blank", "noopener");
    }
  } catch (err) {
    alert(err?.message || "Gagal memuat dokumen KTP.");
  } finally {
    loadingKtp.value = false;
  }
}

const cleanPhone = computed(() => {
  const p = props.customer?.phone_number || "";
  return p.replace(/[^0-9]/g, "");
});

const waLink = computed(() => {
  let num = cleanPhone.value;
  if (!num) return "";
  if (num.startsWith("0")) {
    num = "62" + num.slice(1);
  }
  return `https://wa.me/${num}`;
});

const emergencyWaLink = computed(() => {
  const p = detail.value.emergency_contact_phone || "";
  let num = p.replace(/[^0-9]/g, "");
  if (!num) return "";
  if (num.startsWith("0")) {
    num = "62" + num.slice(1);
  }
  return `https://wa.me/${num}`;
});

function copyToClipboard(text, fieldName) {
  if (!text) return;
  navigator.clipboard.writeText(text);
  copiedField.value = fieldName;
  setTimeout(() => {
    if (copiedField.value === fieldName) {
      copiedField.value = "";
    }
  }, 2000);
}
</script>

<template>
  <AppModal
    :open="open"
    title="Detail Informasi Customer"
    @close="emit('close')"
  >
    <div v-if="customer" class="space-y-6">
      <!-- Header Profil Customer -->
      <div class="flex items-center gap-4 rounded-2xl bg-slate-50 p-4 border border-slate-100">
        <div
          class="flex h-16 w-16 shrink-0 items-center justify-center overflow-hidden rounded-full border-2 border-white bg-blue-100 text-xl font-bold text-blue-700 shadow-sm"
        >
          <img
            v-if="customer.avatar_url"
            :src="customer.avatar_url"
            :alt="customer.full_name ?? 'Customer'"
            class="h-full w-full object-cover"
          />
          <span v-else>{{
            (customer.full_name ?? customer.email ?? "?")
              .charAt(0)
              .toUpperCase()
          }}</span>
        </div>

        <div class="min-w-0 flex-1">
          <div class="flex items-center gap-2">
            <h4 class="truncate font-extrabold text-slate-800 text-lg">
              {{ customer.full_name || "Tanpa Nama" }}
            </h4>
            <span
              class="inline-flex items-center gap-1 rounded-full bg-emerald-100 px-2.5 py-0.5 text-[11px] font-semibold text-emerald-700"
            >
              <ShieldCheck class="h-3 w-3" />
              Customer
            </span>
          </div>

          <p class="truncate text-xs text-slate-500">
            {{ customer.email }}
          </p>

          <div class="mt-2 flex flex-wrap gap-2">
            <a
              v-if="waLink"
              :href="waLink"
              target="_blank"
              rel="noopener noreferrer"
              class="inline-flex items-center gap-1 rounded-lg bg-emerald-600 px-2.5 py-1 text-xs font-semibold text-white transition-colors hover:bg-emerald-700 shadow-sm shadow-emerald-500/20"
            >
              <Phone class="h-3 w-3" />
              Chat WhatsApp
            </a>
            <a
              v-if="customer.phone_number"
              :href="`tel:${cleanPhone}`"
              class="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2.5 py-1 text-xs font-semibold text-slate-700 transition-colors hover:bg-slate-100"
            >
              Telepon
            </a>
          </div>
        </div>
      </div>

      <!-- Bagian 1: Identitas Resmi (NIK & SIM) -->
      <div>
        <h5 class="text-xs font-bold uppercase tracking-wider text-slate-400 mb-3 flex items-center gap-1.5">
          <IdCard class="h-3.5 w-3.5 text-blue-600" />
          Dokumen Identitas
        </h5>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <!-- NIK -->
          <div class="rounded-xl border border-slate-200 bg-white p-3.5">
            <span class="text-[11px] font-medium text-slate-400">Nomor Induk Kependudukan (NIK)</span>
            <div class="mt-1 flex items-center justify-between">
              <span class="font-mono text-sm font-bold text-slate-800 tracking-wider">
                {{ detail.nik || "Belum diisi" }}
              </span>
              <button
                v-if="detail.nik"
                type="button"
                class="rounded-lg p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-600"
                title="Salin NIK"
                @click="copyToClipboard(detail.nik, 'nik')"
              >
                <Check v-if="copiedField === 'nik'" class="h-4 w-4 text-emerald-600" />
                <Copy v-else class="h-4 w-4" />
              </button>
            </div>
          </div>

          <!-- SIM -->
          <div class="rounded-xl border border-slate-200 bg-white p-3.5">
            <span class="text-[11px] font-medium text-slate-400">Nomor Surat Izin Mengemudi (SIM)</span>
            <div class="mt-1 flex items-center justify-between">
              <span class="font-mono text-sm font-bold text-slate-800 tracking-wider">
                {{ detail.sim_number || "Belum diisi" }}
              </span>
              <button
                v-if="detail.sim_number"
                type="button"
                class="rounded-lg p-1 text-slate-400 hover:bg-slate-100 hover:text-slate-600"
                title="Salin No. SIM"
                @click="copyToClipboard(detail.sim_number, 'sim')"
              >
                <Check v-if="copiedField === 'sim'" class="h-4 w-4 text-emerald-600" />
                <Copy v-else class="h-4 w-4" />
              </button>
            </div>
          </div>

          <!-- Dokumen Fisik KTP (Span 2) -->
          <div class="sm:col-span-2 rounded-xl border border-slate-200 bg-slate-50 p-3.5 flex items-center justify-between">
            <div class="flex items-center gap-2.5">
              <div class="flex h-9 w-9 items-center justify-center rounded-lg bg-blue-100 text-blue-700">
                <IdCard class="h-5 w-5" />
              </div>
              <div>
                <p class="text-xs font-bold text-slate-800">Dokumen Foto KTP Asli</p>
                <p class="text-[11px] text-slate-500">
                  {{ detail.ktp_image_url ? 'Dokumen KTP tersedia di profil' : 'Customer belum mengunggah foto KTP' }}
                </p>
              </div>
            </div>

            <button
              v-if="detail.ktp_image_url"
              type="button"
              :disabled="loadingKtp"
              class="inline-flex items-center gap-1.5 rounded-xl bg-blue-600 px-3 py-1.5 text-xs font-semibold text-white transition-colors hover:bg-blue-700 disabled:opacity-60 cursor-pointer shadow-xs"
              @click="openCustomerKtp"
            >
              <LoaderCircle v-if="loadingKtp" class="h-3.5 w-3.5 animate-spin" />
              <ExternalLink v-else class="h-3.5 w-3.5" />
              Buka Foto KTP
            </button>
            <span v-else class="text-[11px] font-semibold text-rose-500 bg-rose-50 px-2.5 py-1 rounded-lg border border-rose-200">
              Belum Diunggah
            </span>
          </div>
        </div>
      </div>

      <!-- Bagian 2: Kontak & Domisili -->
      <div>
        <h5 class="text-xs font-bold uppercase tracking-wider text-slate-400 mb-3 flex items-center gap-1.5">
          <MapPin class="h-3.5 w-3.5 text-blue-600" />
          Alamat Domisili & Kontak
        </h5>
        <div class="rounded-xl border border-slate-200 bg-white p-4 space-y-3">
          <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
            <div>
              <p class="text-[11px] font-medium text-slate-400">Nomor Telepon / WhatsApp</p>
              <p class="mt-0.5 text-sm font-semibold text-slate-800">
                {{ customer.phone_number || "-" }}
              </p>
            </div>
            <div>
              <p class="text-[11px] font-medium text-slate-400">Kota / Kabupaten</p>
              <p class="mt-0.5 text-sm font-semibold text-slate-800">
                {{ detail.city || "-" }}
              </p>
            </div>
          </div>

          <div class="border-t border-slate-100 pt-3">
            <p class="text-[11px] font-medium text-slate-400">Alamat Lengkap</p>
            <p class="mt-0.5 text-sm text-slate-700 leading-relaxed">
              {{ detail.address || "Belum mengisi alamat lengkap" }}
            </p>
          </div>
        </div>
      </div>

      <!-- Bagian 3: Kontak Darurat -->
      <div>
        <h5 class="text-xs font-bold uppercase tracking-wider text-slate-400 mb-3 flex items-center gap-1.5">
          <AlertCircle class="h-3.5 w-3.5 text-rose-600" />
          Kontak Darurat (Emergency Contact)
        </h5>
        <div class="rounded-xl border border-rose-100 bg-rose-50/40 p-4">
          <div v-if="detail.emergency_contact_phone" class="space-y-3">
            <div class="flex items-start justify-between gap-2">
              <div>
                <p class="text-xs text-rose-600 font-medium">Nama Kontak Darurat</p>
                <p class="text-sm font-bold text-slate-800">
                  {{ detail.emergency_contact_name || "-" }}
                  <span
                    v-if="detail.emergency_contact_relation"
                    class="ml-1 inline-block rounded-md bg-rose-100 px-2 py-0.5 text-[11px] font-medium text-rose-700"
                  >
                    {{ detail.emergency_contact_relation }}
                  </span>
                </p>
              </div>

              <a
                v-if="emergencyWaLink"
                :href="emergencyWaLink"
                target="_blank"
                rel="noopener noreferrer"
                class="inline-flex items-center gap-1 rounded-lg border border-rose-200 bg-white px-2.5 py-1 text-xs font-semibold text-rose-700 transition-colors hover:bg-rose-100"
              >
                <Phone class="h-3 w-3" />
                Hubungi
              </a>
            </div>

            <div class="border-t border-rose-100 pt-2 flex items-center justify-between">
              <span class="text-xs text-slate-600 font-mono">
                {{ detail.emergency_contact_phone }}
              </span>
              <button
                type="button"
                class="rounded-md p-1 text-rose-600 hover:bg-rose-100"
                title="Salin Kontak Darurat"
                @click="copyToClipboard(detail.emergency_contact_phone, 'emg')"
              >
                <Check v-if="copiedField === 'emg'" class="h-3.5 w-3.5 text-emerald-600" />
                <Copy v-else class="h-3.5 w-3.5" />
              </button>
            </div>
          </div>
          <p v-else class="text-xs text-slate-500 italic">
            Belum ada informasi kontak darurat yang didaftarkan.
          </p>
        </div>
      </div>

      <!-- Bagian 4: Data Tambahan (Pekerjaan & Media Sosial) -->
      <div>
        <h5 class="text-xs font-bold uppercase tracking-wider text-slate-400 mb-3 flex items-center gap-1.5">
          <Briefcase class="h-3.5 w-3.5 text-blue-600" />
          Informasi Tambahan
        </h5>
        <div class="grid grid-cols-1 gap-3 sm:grid-cols-2">
          <div class="rounded-xl border border-slate-200 bg-white p-3.5">
            <span class="text-[11px] font-medium text-slate-400 flex items-center gap-1">
              <Briefcase class="h-3 w-3" />
              Pekerjaan / Profesi
            </span>
            <p class="mt-1 text-sm font-semibold text-slate-800">
              {{ detail.job_title || "-" }}
            </p>
          </div>

          <div class="rounded-xl border border-slate-200 bg-white p-3.5">
            <span class="text-[11px] font-medium text-slate-400 flex items-center gap-1">
              <Share2 class="h-3 w-3" />
              Media Sosial (Instagram/LinkedIn)
            </span>
            <p class="mt-1 text-sm font-semibold text-slate-800 truncate">
              {{ detail.social_media || "-" }}
            </p>
          </div>
        </div>
      </div>

      <!-- Footer Modal -->
      <div class="flex justify-end pt-2 border-t border-slate-100">
        <button
          type="button"
          class="rounded-xl bg-slate-800 px-5 py-2.5 text-xs font-semibold text-white transition-colors hover:bg-slate-900"
          @click="emit('close')"
        >
          Tutup
        </button>
      </div>
    </div>
  </AppModal>
</template>
