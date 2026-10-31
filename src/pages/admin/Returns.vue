<script setup lang="js">
import {
  CheckCircle2,
  LoaderCircle,
  Package,
  TriangleAlert,
} from "@lucide/vue";
import { computed, onMounted, onUnmounted, reactive, ref } from "vue";
import AppModal from "../../components/AppModal.vue";
import CustomerDetailModal from "../../components/CustomerDetailModal.vue";
import {
  formatDateTime,
  formatDuration,
  getVehicleThumbnail,
  rupiah,
  toIso,
  toLocalInput,
} from "../../lib/format";
import { supabase } from "../../lib/supabase-client";

const activeBookings = ref([]);
const returns = ref([]);
const loading = ref(true);
const errorMessage = ref("");
const saving = ref(false);

const customerModalOpen = ref(false);
const selectedCustomer = ref(null);

function viewCustomerDetail(customer) {
  if (!customer) return;
  selectedCustomer.value = customer;
  customerModalOpen.value = true;
}

const modalOpen = ref(false);
const selectedBooking = ref(null);
const now = ref(Date.now());

const form = reactive({
  return_date: "",
  late_fee: "0",
  damage_fee: "0",
  admin_notes: "",
});

let clock;

const finalPrice = computed(() => {
  const base = Number(selectedBooking.value?.total_price ?? 0);
  return base + Number(form.late_fee || 0) + Number(form.damage_fee || 0);
});

const suggestedLateFee = computed(() => {
  if (!selectedBooking.value) return 0;
  const diff = now.value - new Date(selectedBooking.value.end_date).getTime();
  if (diff <= 0) return 0;
  const lateDays = Math.ceil(diff / (1000 * 60 * 60 * 24));
  return lateDays * Number(selectedBooking.value.vehicle?.price_per_day ?? 0);
});

function overdueLabel(booking) {
  const diff = now.value - new Date(booking.end_date).getTime();
  return diff > 0 ? `Terlambat ${formatDuration(diff)}` : "Tepat waktu";
}

function isOverdue(booking) {
  return new Date(booking.end_date).getTime() < now.value;
}

async function loadData() {
  loading.value = true;
  errorMessage.value = "";

  const [activeResult, returnsResult] = await Promise.all([
    supabase
      .from("bookings")
      .select(
        "*, vehicle:vehicles(*, vehicle_images(id, image_url, created_at)), customer:users(*, detail_user(*))",
      )
      .eq("status", "ACTIVE")
      .order("end_date", { ascending: true }),
    supabase
      .from("returns")
      .select(
        "*, booking:bookings(id, start_date, end_date, total_price, vehicle:vehicles(*, vehicle_images(id, image_url, created_at)), customer:users(*, detail_user(*)))",
      )
      .order("created_at", { ascending: false })
      .limit(20),
  ]);

  if (activeResult.error) errorMessage.value = activeResult.error.message;
  if (returnsResult.error) errorMessage.value = returnsResult.error.message;

  activeBookings.value = activeResult.data ?? [];
  returns.value = returnsResult.data ?? [];

  loading.value = false;
}

function openReturnModal(booking) {
  selectedBooking.value = booking;
  form.return_date = toLocalInput(new Date().toISOString());
  form.late_fee = "0";
  form.damage_fee = "0";
  form.admin_notes = "";
  errorMessage.value = "";
  modalOpen.value = true;
}

function applySuggestedLateFee() {
  form.late_fee = String(suggestedLateFee.value);
}

async function handleSubmit() {
  if (!selectedBooking.value) return;

  errorMessage.value = "";
  saving.value = true;

  const booking = selectedBooking.value;

  try {
    const { error: insertError } = await supabase.from("returns").insert({
      booking_id: booking.id,
      return_date: toIso(form.return_date) ?? new Date().toISOString(),
      late_fee: Number(form.late_fee || 0),
      damage_fee: Number(form.damage_fee || 0),
      final_price: finalPrice.value,
      admin_notes: form.admin_notes.trim() || null,
    });

    if (insertError) throw insertError;

    const { error: updateError } = await supabase
      .from("bookings")
      .update({ status: "COMPLETED" })
      .eq("id", booking.id);

    if (updateError) throw updateError;

    modalOpen.value = false;
    selectedBooking.value = null;
    await loadData();
  } catch (error) {
    errorMessage.value =
      error?.code === "23505"
        ? "Booking ini sudah pernah diproses pengembaliannya."
        : (error?.message ?? "Gagal memproses pengembalian.");
  } finally {
    saving.value = false;
  }
}

onMounted(() => {
  loadData();
  clock = setInterval(() => {
    now.value = Date.now();
  }, 30000);
});
onUnmounted(() => clearInterval(clock));
</script>

<template>
  <div class="space-y-6">
    <div>
      <h1 class="text-xl font-extrabold text-slate-800">
        Pengembalian Kendaraan
      </h1>
      <p class="text-sm text-slate-500">
        Catat pengembalian unit, denda keterlambatan, dan biaya kerusakan.
      </p>
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
      Memuat data...
    </div>

    <template v-else>
      <!-- Unit yang sedang disewa -->
      <section class="space-y-4">
        <h2 class="text-lg font-bold text-slate-800">Unit Sedang Disewa</h2>

        <div
          v-if="activeBookings.length === 0"
          class="rounded-2xl border border-dashed border-slate-300 bg-white py-12 text-center text-sm text-slate-500"
        >
          Tidak ada kendaraan yang sedang disewa saat ini.
        </div>

        <div v-else class="space-y-4">
          <article
            v-for="booking in activeBookings"
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
                  <Package v-else class="h-6 w-6 text-slate-300" />
                </div>
                <div>
                  <h3 class="font-bold text-slate-800">
                    {{ booking.vehicle?.name }}
                  </h3>
                  <p class="text-xs text-slate-500">
                    {{ booking.vehicle?.license_plate }} ·
                    <button
                      type="button"
                      class="font-semibold text-slate-700 hover:text-blue-600 hover:underline cursor-pointer"
                      title="Klik untuk melihat informasi pribadi customer"
                      @click="viewCustomerDetail(booking.customer)"
                    >
                      {{ booking.customer?.full_name ?? booking.customer?.email }}
                    </button>
                  </p>
                </div>
              </div>
              <span
                class="rounded-full border px-2.5 py-1 text-[10px] font-bold uppercase tracking-wide"
                :class="
                  isOverdue(booking)
                    ? 'border-red-200 bg-red-50 text-red-700'
                    : 'border-indigo-200 bg-indigo-50 text-indigo-700'
                "
              >
                {{ overdueLabel(booking) }}
              </span>
            </div>

            <div class="grid gap-3 p-5 text-sm sm:grid-cols-3">
              <div>
                <p class="text-xs text-slate-400">Mulai</p>
                <p class="font-semibold text-slate-700">
                  {{ formatDateTime(booking.start_date) }}
                </p>
              </div>
              <div>
                <p class="text-xs text-slate-400">Jadwal Kembali</p>
                <p class="font-semibold text-slate-700">
                  {{ formatDateTime(booking.end_date) }}
                </p>
              </div>
              <div>
                <p class="text-xs text-slate-400">Biaya Sewa</p>
                <p class="font-bold text-blue-600">
                  {{ rupiah(booking.total_price) }}
                </p>
              </div>
            </div>

            <div class="border-t border-slate-100 p-5 pt-4">
              <button
                type="button"
                class="inline-flex items-center gap-2 rounded-xl bg-slate-800 px-4 py-2.5 text-xs font-semibold text-white transition-colors hover:bg-slate-900"
                @click="openReturnModal(booking)"
              >
                <Package class="h-4 w-4" />
                Proses Pengembalian
              </button>
            </div>
          </article>
        </div>
      </section>

      <!-- Riwayat -->
      <section class="space-y-4">
        <h2 class="text-lg font-bold text-slate-800">Riwayat Pengembalian</h2>

        <div
          v-if="returns.length === 0"
          class="rounded-2xl border border-dashed border-slate-300 bg-white py-12 text-center text-sm text-slate-500"
        >
          Belum ada pengembalian yang tercatat.
        </div>

        <div v-else class="overflow-x-auto rounded-2xl border border-slate-200 bg-white shadow-sm">
          <table class="w-full min-w-[720px] text-left text-sm">
            <thead class="bg-slate-50 text-xs uppercase tracking-wide text-slate-500">
              <tr>
                <th class="px-5 py-3 font-bold">Kendaraan</th>
                <th class="px-5 py-3 font-bold">Customer</th>
                <th class="px-5 py-3 font-bold">Dikembalikan</th>
                <th class="px-5 py-3 font-bold">Denda Telat</th>
                <th class="px-5 py-3 font-bold">Kerusakan</th>
                <th class="px-5 py-3 font-bold">Total Akhir</th>
              </tr>
            </thead>
            <tbody class="divide-y divide-slate-100">
              <tr v-for="item in returns" :key="item.id">
                <td class="px-5 py-3">
                  <div class="flex items-center gap-3">
                    <div
                      class="flex h-10 w-14 shrink-0 items-center justify-center overflow-hidden rounded-lg border border-slate-200 bg-slate-100"
                    >
                      <img
                        v-if="getVehicleThumbnail(item.booking?.vehicle)"
                        :src="getVehicleThumbnail(item.booking?.vehicle)"
                        :alt="item.booking?.vehicle?.name"
                        class="h-full w-full object-cover"
                      />
                      <Package v-else class="h-4 w-4 text-slate-300" />
                    </div>
                    <div>
                      <p class="font-semibold text-slate-700">
                        {{ item.booking?.vehicle?.name ?? "-" }}
                      </p>
                      <p class="text-xs text-slate-400">
                        {{ item.booking?.vehicle?.license_plate ?? "-" }}
                      </p>
                    </div>
                  </div>
                </td>
                <td class="px-5 py-3 text-slate-600">
                  <button
                    type="button"
                    class="font-medium text-slate-700 hover:text-blue-600 hover:underline cursor-pointer"
                    title="Klik untuk melihat informasi pribadi customer"
                    @click="viewCustomerDetail(item.booking?.customer)"
                  >
                    {{ item.booking?.customer?.full_name ?? item.booking?.customer?.email ?? "-" }}
                  </button>
                </td>
                <td class="px-5 py-3 text-slate-600">
                  {{ formatDateTime(item.return_date) }}
                </td>
                <td class="px-5 py-3 text-slate-600">{{ rupiah(item.late_fee) }}</td>
                <td class="px-5 py-3 text-slate-600">{{ rupiah(item.damage_fee) }}</td>
                <td class="px-5 py-3 font-bold text-blue-600">
                  {{ rupiah(item.final_price) }}
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>
    </template>

    <!-- Modal proses pengembalian -->
    <AppModal
      :open="modalOpen"
      title="Proses Pengembalian"
      @close="modalOpen = false"
    >
      <form v-if="selectedBooking" class="space-y-4" @submit.prevent="handleSubmit">
        <div class="rounded-xl bg-slate-50 p-4 text-sm">
          <div class="flex items-center gap-3.5 border-b border-slate-200/60 pb-3">
            <div
              class="flex h-12 w-16 shrink-0 items-center justify-center overflow-hidden rounded-lg border border-slate-200 bg-white"
            >
              <img
                v-if="getVehicleThumbnail(selectedBooking.vehicle)"
                :src="getVehicleThumbnail(selectedBooking.vehicle)"
                :alt="selectedBooking.vehicle?.name"
                class="h-full w-full object-cover"
              />
              <Package v-else class="h-6 w-6 text-slate-300" />
            </div>
            <div class="flex-1">
              <p class="font-bold text-slate-800">
                {{ selectedBooking.vehicle?.name }}
              </p>
              <p class="text-xs text-slate-500">
                {{ selectedBooking.vehicle?.license_plate }} ·
                <button
                  type="button"
                  class="font-semibold text-slate-700 hover:text-blue-600 hover:underline cursor-pointer"
                  title="Klik untuk melihat informasi pribadi customer"
                  @click="viewCustomerDetail(selectedBooking.customer)"
                >
                  {{ selectedBooking.customer?.full_name ?? selectedBooking.customer?.email }}
                </button>
              </p>
            </div>
          </div>
          <div class="mt-3 flex justify-between text-slate-600">
            <span>Jadwal kembali</span>
            <span class="font-semibold">
              {{ formatDateTime(selectedBooking.end_date) }}
            </span>
          </div>
          <div class="flex justify-between text-slate-600">
            <span>Biaya sewa</span>
            <span class="font-semibold">
              {{ rupiah(selectedBooking.total_price) }}
            </span>
          </div>
        </div>

        <div>
          <label
            for="return_date"
            class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >Waktu Pengembalian</label
          >
          <input
            id="return_date"
            v-model="form.return_date"
            type="datetime-local"
            required
            class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
        </div>

        <div class="grid gap-4 sm:grid-cols-2">
          <div>
            <label
              for="late_fee"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >Denda Keterlambatan (Rp)</label
            >
            <input
              id="late_fee"
              v-model="form.late_fee"
              type="number"
              min="0"
              step="1000"
              class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
            <button
              v-if="suggestedLateFee > 0"
              type="button"
              class="mt-1 text-xs font-semibold text-blue-600 hover:underline"
              @click="applySuggestedLateFee"
            >
              Isi otomatis: {{ rupiah(suggestedLateFee) }}
            </button>
          </div>

          <div>
            <label
              for="damage_fee"
              class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
              >Biaya Kerusakan (Rp)</label
            >
            <input
              id="damage_fee"
              v-model="form.damage_fee"
              type="number"
              min="0"
              step="1000"
              class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
            />
          </div>
        </div>

        <div>
          <label
            for="admin_notes"
            class="mb-1 block text-xs font-bold uppercase tracking-wider text-slate-600"
            >Catatan Admin</label
          >
          <textarea
            id="admin_notes"
            v-model="form.admin_notes"
            rows="2"
            placeholder="Kondisi unit, bahan bakar, kelengkapan..."
            class="w-full rounded-xl border border-slate-300 px-4 py-2.5 text-sm text-slate-800 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          ></textarea>
        </div>

        <div
          class="flex items-center justify-between rounded-xl bg-blue-50 px-4 py-3 text-sm"
        >
          <span class="font-semibold text-blue-800">Total yang harus dibayar</span>
          <span class="text-base font-extrabold text-blue-700">
            {{ rupiah(finalPrice) }}
          </span>
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
            class="flex flex-1 items-center justify-center gap-2 rounded-xl bg-slate-800 px-4 py-2.5 text-sm font-semibold text-white transition-colors hover:bg-slate-900 disabled:opacity-60"
          >
            <LoaderCircle v-if="saving" class="h-4 w-4 animate-spin" />
            <CheckCircle2 v-else class="h-4 w-4" />
            {{ saving ? "Menyimpan..." : "Selesaikan Sewa" }}
          </button>
        </div>
      </form>
    </AppModal>

    <!-- Modal Detail Informasi Pribadi Customer -->
    <CustomerDetailModal
      :open="customerModalOpen"
      :customer="selectedCustomer"
      @close="customerModalOpen = false"
    />
  </div>
</template>
