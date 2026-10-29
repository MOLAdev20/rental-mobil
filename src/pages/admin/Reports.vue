<script setup lang="js">
import {
  Calendar,
  CalendarRange,
  Car,
  CheckCircle2,
  Clock,
  Download,
  ExternalLink,
  Eye,
  Filter,
  Images,
  LoaderCircle,
  Printer,
  RefreshCw,
  Search,
  TrendingUp,
  TriangleAlert,
  User,
  X,
} from "@lucide/vue";
import {
  CategoryScale,
  Chart,
  Filler,
  Legend,
  LinearScale,
  LineController,
  LineElement,
  PointElement,
  Title,
  Tooltip,
} from "chart.js";
import { computed, nextTick, onBeforeUnmount, onMounted, ref, watch } from "vue";
import AppModal from "../../components/AppModal.vue";
import StatusBadge from "../../components/StatusBadge.vue";
import {
  BOOKING_STATUS,
  formatDate,
  formatDateTime,
  getVehicleThumbnail,
  rentalDays,
  rupiah,
  VEHICLE_TYPE,
} from "../../lib/format";
import { supabase } from "../../lib/supabase-client";

// Registrasi modul-modul Chart.js yang dibutuhkan
Chart.register(
  LineController,
  LineElement,
  PointElement,
  LinearScale,
  CategoryScale,
  Title,
  Tooltip,
  Legend,
  Filler,
);

// State Data Transaksi
const bookings = ref([]);
const loading = ref(true);
const errorMessage = ref("");

// State Filter Utama
// Opsi periode: '1_MONTH' | '1_WEEK' | '1_DAY' | 'CUSTOM' | 'ALL'
const periodFilter = ref("1_MONTH");
const customStartDate = ref("");
const customEndDate = ref("");
const statusFilter = ref("ALL");
const searchQuery = ref("");

// State Detail Modal Transaksi
const detailModalOpen = ref(false);
const selectedBooking = ref(null);

// Chart Reference & Instance
const chartCanvas = ref(null);
let chartInstance = null;

// Pilihan Periode Filter Sesuai Request User
const periodOptions = [
  { value: "1_MONTH", label: "1 Bulan yang Lalu" },
  { value: "1_WEEK", label: "1 Minggu yang Lalu" },
  { value: "1_DAY", label: "1 Hari yang Lalu" },
  { value: "CUSTOM", label: "Rentang Tanggal" },
  { value: "ALL", label: "Semua Waktu" },
];

// Opsi Status Filter Dropdown
const statusOptions = [
  { value: "ALL", label: "Semua Status" },
  { value: "COMPLETED", label: "Selesai" },
  { value: "ACTIVE", label: "Sedang Disewa" },
  { value: "APPROVED", label: "Disetujui" },
  { value: "PENDING", label: "Menunggu Verifikasi" },
  { value: "CANCELLED", label: "Dibatalkan" },
];

// Load seluruh data booking beserta relasinya
async function loadReportsData() {
  loading.value = true;
  errorMessage.value = "";

  try {
    const { data, error } = await supabase
      .from("bookings")
      .select(
        "*, vehicle:vehicles(*, vehicle_images(id, image_url, created_at)), customer:users(id, email, full_name, phone_number, avatar_url), return_info:returns(*)",
      )
      .order("created_at", { ascending: false });

    if (error) throw error;
    bookings.value = data ?? [];
  } catch (err) {
    errorMessage.value = err?.message ?? "Gagal memuat data transaksi sewa.";
  } finally {
    loading.value = false;
    await nextTick();
    renderChart();
  }
}

// Menentukan batas tanggal awal & akhir berdasarkan periodFilter
const dateRangeBounds = computed(() => {
  const now = new Date();

  if (periodFilter.value === "1_DAY") {
    // 24 jam terakhir / hari ini
    const start = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 0, 0, 0);
    const end = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59);
    return { start, end };
  }

  if (periodFilter.value === "1_WEEK") {
    // 7 hari terakhir
    const start = new Date(now);
    start.setDate(now.getDate() - 6);
    start.setHours(0, 0, 0, 0);
    const end = new Date(now);
    end.setHours(23, 59, 59, 999);
    return { start, end };
  }

  if (periodFilter.value === "1_MONTH") {
    // 30 hari terakhir
    const start = new Date(now);
    start.setDate(now.getDate() - 29);
    start.setHours(0, 0, 0, 0);
    const end = new Date(now);
    end.setHours(23, 59, 59, 999);
    return { start, end };
  }

  if (periodFilter.value === "CUSTOM") {
    const start = customStartDate.value
      ? new Date(customStartDate.value + "T00:00:00")
      : null;
    const end = customEndDate.value
      ? new Date(customEndDate.value + "T23:59:59")
      : null;
    return { start, end };
  }

  return { start: null, end: null };
});

// Data booking yang telah terfilter untuk Tabel & Chart
const filteredBookings = computed(() => {
  const { start, end } = dateRangeBounds.value;
  const q = searchQuery.value.trim().toLowerCase();

  return bookings.value.filter((b) => {
    // 1. Filter Status
    if (statusFilter.value !== "ALL" && b.status !== statusFilter.value) {
      return false;
    }

    // 2. Filter Periode Tanggal Transaksi
    if (start || end) {
      const bDate = new Date(b.created_at || b.start_date);
      if (isNaN(bDate.getTime())) return false;
      if (start && bDate < start) return false;
      if (end && bDate > end) return false;
    }

    // 3. Filter Pencarian Text
    if (q) {
      const matchVehicle =
        b.vehicle?.name?.toLowerCase().includes(q) ||
        b.vehicle?.license_plate?.toLowerCase().includes(q);
      const matchCustomer =
        b.customer?.full_name?.toLowerCase().includes(q) ||
        b.customer?.email?.toLowerCase().includes(q) ||
        b.customer?.phone_number?.toLowerCase().includes(q);
      if (!matchVehicle && !matchCustomer) return false;
    }

    return true;
  });
});

// Agregasi Data Harian untuk Grafik Garis Chart.js
const dailyChartData = computed(() => {
  // Peta data per tanggal string 'YYYY-MM-DD'
  const dayMap = new Map();

  // Tentukan rentang hari yang akan ditampilkan pada sumbu X
  const { start, end } = dateRangeBounds.value;
  let datesList = [];

  if (start && end) {
    const cur = new Date(start);
    while (cur <= end) {
      const key = cur.toISOString().split("T")[0];
      dayMap.set(key, { count: 0, revenue: 0, dateObj: new Date(cur) });
      cur.setDate(cur.getDate() + 1);
    }
  }

  // Agregasikan seluruh transaksi terfilter ke dalam tanggal harian
  for (const b of filteredBookings.value) {
    const rawDate = b.created_at || b.start_date;
    if (!rawDate) continue;
    const key = new Date(rawDate).toISOString().split("T")[0];

    // Hitung nominal transaksi (jika sewa selesai dan ada denda, pakai final_price)
    const amount = Number(b.return_info?.final_price ?? b.total_price ?? 0);
    // Transaksi yang dibatalkan tidak dimasukkan ke kalkulasi pendapatan
    const revenueToAdd = b.status === "CANCELLED" ? 0 : amount;

    if (!dayMap.has(key)) {
      dayMap.set(key, {
        count: 1,
        revenue: revenueToAdd,
        dateObj: new Date(rawDate),
      });
    } else {
      const cur = dayMap.get(key);
      cur.count += 1;
      cur.revenue += revenueToAdd;
    }
  }

  // Urutkan berdasarkan tanggal ASC
  const sortedKeys = Array.from(dayMap.keys()).sort();

  const labels = [];
  const transactionCounts = [];
  const totalRevenues = [];

  for (const key of sortedKeys) {
    const item = dayMap.get(key);
    // Format label tanggal ringkas: '29 Okt'
    const labelFormatted = new Intl.DateTimeFormat("id-ID", {
      day: "numeric",
      month: "short",
    }).format(item.dateObj);

    labels.push(labelFormatted);
    transactionCounts.push(item.count);
    totalRevenues.push(item.revenue);
  }

  return { labels, transactionCounts, totalRevenues };
});

// Render atau update Chart.js
function renderChart() {
  if (!chartCanvas.value) return;

  const { labels, transactionCounts, totalRevenues } = dailyChartData.value;

  if (chartInstance) {
    chartInstance.destroy();
    chartInstance = null;
  }

  const ctx = chartCanvas.value.getContext("2d");
  if (!ctx) return;

  // Background gradient lembut untuk pendapatan
  const revenueGradient = ctx.createLinearGradient(0, 0, 0, 320);
  revenueGradient.addColorStop(0, "rgba(16, 185, 129, 0.22)");
  revenueGradient.addColorStop(1, "rgba(16, 185, 129, 0.01)");

  chartInstance = new Chart(ctx, {
    type: "line",
    data: {
      labels,
      datasets: [
        {
          label: "Total Pendapatan (Rp)",
          data: totalRevenues,
          borderColor: "#10b981", // Emerald 500
          backgroundColor: revenueGradient,
          fill: true,
          tension: 0.35,
          borderWidth: 2.5,
          pointRadius: 4,
          pointHoverRadius: 6,
          pointBackgroundColor: "#10b981",
          pointBorderColor: "#ffffff",
          pointBorderWidth: 2,
          yAxisID: "yRevenue",
        },
        {
          label: "Jumlah Transaksi",
          data: transactionCounts,
          borderColor: "#3b82f6", // Blue 500
          backgroundColor: "rgba(59, 130, 246, 0.1)",
          fill: false,
          tension: 0.35,
          borderWidth: 2.5,
          pointRadius: 4,
          pointHoverRadius: 6,
          pointBackgroundColor: "#3b82f6",
          pointBorderColor: "#ffffff",
          pointBorderWidth: 2,
          yAxisID: "yCount",
        },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: {
        mode: "index",
        intersect: false,
      },
      plugins: {
        legend: {
          display: true,
          position: "top",
          align: "end",
          labels: {
            boxWidth: 12,
            boxHeight: 12,
            usePointStyle: true,
            pointStyle: "circle",
            font: { size: 12, weight: "600" },
            color: "#475569",
          },
        },
        tooltip: {
          backgroundColor: "rgba(15, 23, 42, 0.92)",
          titleColor: "#ffffff",
          bodyColor: "#f1f5f9",
          padding: 12,
          cornerRadius: 10,
          boxPadding: 4,
          callbacks: {
            label(context) {
              const datasetLabel = context.dataset.label || "";
              const value = context.parsed.y;
              if (context.dataset.yAxisID === "yRevenue") {
                return ` ${datasetLabel}: ${rupiah(value)}`;
              }
              return ` ${datasetLabel}: ${value} transaksi`;
            },
          },
        },
      },
      scales: {
        x: {
          grid: { display: false },
          ticks: {
            color: "#64748b",
            font: { size: 11 },
            maxRotation: 45,
          },
        },
        yCount: {
          type: "linear",
          display: true,
          position: "left",
          title: {
            display: true,
            text: "Jumlah Transaksi",
            color: "#3b82f6",
            font: { size: 11, weight: "600" },
          },
          ticks: {
            color: "#64748b",
            font: { size: 11 },
            stepSize: 1,
            precision: 0,
          },
          grid: {
            color: "#f1f5f9",
          },
          beginAtZero: true,
        },
        yRevenue: {
          type: "linear",
          display: true,
          position: "right",
          title: {
            display: true,
            text: "Pendapatan (Rp)",
            color: "#10b981",
            font: { size: 11, weight: "600" },
          },
          ticks: {
            color: "#64748b",
            font: { size: 10 },
            callback(val) {
              if (val >= 1000000) return `Rp ${(val / 1000000).toFixed(1)}jt`;
              if (val >= 1000) return `Rp ${(val / 1000).toFixed(0)}rb`;
              return `Rp ${val}`;
            },
          },
          grid: { display: false },
          beginAtZero: true,
        },
      },
    },
  });
}

// Watch data dan filter untuk re-render chart
watch([dailyChartData], () => {
  nextTick(() => {
    renderChart();
  });
});

// Reset semua filter ke kondisi awal
function resetAllFilters() {
  periodFilter.value = "1_MONTH";
  customStartDate.value = "";
  customEndDate.value = "";
  statusFilter.value = "ALL";
  searchQuery.value = "";
}

// Buka modal rincian transaksi
function openDetail(booking) {
  selectedBooking.value = booking;
  detailModalOpen.value = true;
}

// Export data tabel transaksi ke format CSV
function exportToCSV() {
  if (!filteredBookings.value.length) {
    alert("Tidak ada data transaksi untuk diekspor.");
    return;
  }

  const headers = [
    "ID Booking",
    "Unit Kendaraan",
    "Tipe",
    "Nomor Polisi",
    "Nama Penyewa",
    "Email Penyewa",
    "No. Telepon",
    "Tanggal Booking",
    "Tanggal Mulai Sewa",
    "Tanggal Selesai Sewa",
    "Durasi (Hari)",
    "Tarif Per Hari (Rp)",
    "Total Transaksi (Rp)",
    "Status Sewa",
  ];

  const rows = filteredBookings.value.map((b) => {
    const days = rentalDays(b.start_date, b.end_date);
    const finalAmount = b.return_info?.final_price ?? b.total_price;
    const statusLabel = BOOKING_STATUS[b.status]?.label ?? b.status;

    return [
      `"${b.id}"`,
      `"${(b.vehicle?.name || "").replace(/"/g, '""')}"`,
      `"${b.vehicle?.type || ""}"`,
      `"${b.vehicle?.license_plate || ""}"`,
      `"${(b.customer?.full_name || "Tanpa Nama").replace(/"/g, '""')}"`,
      `"${b.customer?.email || ""}"`,
      `"${b.customer?.phone_number || ""}"`,
      `"${formatDateTime(b.created_at)}"`,
      `"${formatDate(b.start_date)}"`,
      `"${formatDate(b.end_date)}"`,
      days,
      b.vehicle?.price_per_day || 0,
      finalAmount || 0,
      `"${statusLabel}"`,
    ];
  });

  const csvContent =
    "data:text/csv;charset=utf-8,\uFEFF" +
    [headers.join(","), ...rows.map((r) => r.join(","))].join("\n");

  const encodedUri = encodeURI(csvContent);
  const link = document.createElement("a");
  link.setAttribute("href", encodedUri);
  link.setAttribute(
    "download",
    `laporan-transaksi-rental-${new Date().toISOString().slice(0, 10)}.csv`,
  );
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}

onMounted(() => {
  loadReportsData();
});

onBeforeUnmount(() => {
  if (chartInstance) {
    chartInstance.destroy();
    chartInstance = null;
  }
});
</script>

<template>
  <div class="space-y-6">
    <!-- Header Halaman Laporan -->
    <div class="flex flex-wrap items-center justify-between gap-4">
      <div>
        <h1 class="text-2xl font-extrabold text-slate-800">
          Laporan Transaksi &amp; Sewa
        </h1 >
        <p class="text-sm text-slate-500">
          Analisis grafik transaksi harian, pendapatan rental, dan rincian data sewa armada.
        </p>
      </div>

      <div class="flex flex-wrap items-center gap-2">
        <button
          type="button"
          :disabled="loading"
          class="inline-flex items-center gap-1.5 rounded-xl border border-slate-300 bg-white px-3.5 py-2 text-xs font-semibold text-slate-700 shadow-xs transition-colors hover:bg-slate-50 disabled:opacity-60 cursor-pointer"
          @click="loadReportsData"
        >
          <RefreshCw class="h-4 w-4" :class="{ 'animate-spin': loading }" />
          Segarkan Data
        </button>

        <button
          type="button"
          :disabled="!filteredBookings.length"
          class="inline-flex items-center gap-1.5 rounded-xl border border-emerald-300 bg-emerald-50 px-3.5 py-2 text-xs font-semibold text-emerald-800 shadow-xs transition-colors hover:bg-emerald-100 disabled:opacity-50 cursor-pointer"
          @click="exportToCSV"
        >
          <Download class="h-4 w-4 text-emerald-600" />
          Ekspor CSV / Excel
        </button>
      </div>
    </div>

    <!-- Alert error jika gagal memuat -->
    <p
      v-if="errorMessage"
      class="flex items-start gap-2 rounded-2xl border border-red-200 bg-red-50 px-4 py-3 text-sm text-red-700"
    >
      <TriangleAlert class="mt-0.5 h-4 w-4 shrink-0" />
      <span>{{ errorMessage }}</span>
    </p>

    <!-- ================================================================= -->
    <!-- FILTER BAR (Di Atas Dari Seluruh Komponen Sesuai Permintaan)       -->
    <!-- 1 bulan yang lalu, 1 minggu yang lalu, 1 hari yang lalu & custom   -->
    <!-- ================================================================= -->
    <section class="rounded-2xl border border-slate-200 bg-white p-4 shadow-xs space-y-3.5 sm:p-5">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <!-- Pilihan Periode Waktu -->
        <div class="flex flex-wrap items-center gap-1.5">
          <span class="mr-1 flex items-center gap-1.5 text-xs font-bold uppercase tracking-wider text-slate-500">
            <Calendar class="h-4 w-4 text-blue-600" />
            Periode:
          </span>
          <button
            v-for="opt in periodOptions"
            :key="opt.value"
            type="button"
            class="rounded-xl px-3 py-1.5 text-xs transition-all cursor-pointer"
            :class="
              periodFilter === opt.value
                ? 'bg-blue-600 font-bold text-white shadow-xs'
                : 'bg-slate-100 font-medium text-slate-600 hover:bg-slate-200'
            "
            @click="periodFilter = opt.value"
          >
            {{ opt.label }}
          </button>
        </div>

        <!-- Filter Status Transaksi (Dropdown) -->
        <div class="flex items-center gap-2">
          <label for="report-status" class="text-xs font-semibold text-slate-500">
            Status:
          </label>
          <select
            id="report-status"
            v-model="statusFilter"
            class="rounded-xl border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-2xs focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100 cursor-pointer"
          >
            <option
              v-for="opt in statusOptions"
              :key="opt.value"
              :value="opt.value"
            >
              {{ opt.label }}
            </option>
          </select>
        </div>
      </div>

      <!-- Baris Input Tambahan: Datepicker Kustom & Search Box -->
      <div class="flex flex-wrap items-center justify-between gap-3 border-t border-slate-100 pt-3">
        <!-- Datepicker Custom Range (Aktif bila periodFilter === 'CUSTOM') -->
        <div
          v-if="periodFilter === 'CUSTOM'"
          class="flex flex-wrap items-center gap-2 rounded-xl border border-blue-200 bg-blue-50/60 px-3 py-1.5 text-xs"
        >
          <span class="font-bold text-blue-800">Rentang Tanggal:</span>
          <div class="flex items-center gap-1">
            <span class="text-slate-500">Dari</span>
            <input
              v-model="customStartDate"
              type="date"
              class="rounded-lg border border-slate-300 bg-white px-2 py-1 text-xs text-slate-700 focus:border-blue-600 focus:outline-none"
            />
          </div>
          <div class="flex items-center gap-1">
            <span class="text-slate-500">Sampai</span>
            <input
              v-model="customEndDate"
              type="date"
              class="rounded-lg border border-slate-300 bg-white px-2 py-1 text-xs text-slate-700 focus:border-blue-600 focus:outline-none"
            />
          </div>
          <button
            v-if="customStartDate || customEndDate"
            type="button"
            class="text-[11px] font-semibold text-blue-700 hover:underline cursor-pointer"
            @click="customStartDate = ''; customEndDate = ''"
          >
            Reset
          </button>
        </div>

        <div v-else class="text-xs text-slate-400">
          Menampilkan transaksi berdasarkan waktu dibuatnya sewa.
        </div>

        <!-- Kotak Pencarian -->
        <div class="relative min-w-[240px] flex-1 sm:max-w-xs">
          <Search class="absolute left-3 top-2.5 h-4 w-4 text-slate-400" />
          <input
            v-model="searchQuery"
            type="text"
            placeholder="Cari armada, nopol, customer..."
            class="w-full rounded-xl border border-slate-300 bg-white py-1.5 pl-9 pr-3 text-xs text-slate-800 placeholder-slate-400 focus:border-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-100"
          />
        </div>
      </div>
    </section>

    <!-- ================================================================= -->
    <!-- SCORE CARD (PENDING: Sesuai request belum diimplementasikan dulu) -->
    <!-- ================================================================= -->
    <!-- Slot Score Card di sini nantinya jika sudah ditentukan metriknya -->

    <!-- ================================================================= -->
    <!-- CHART (GRAFIK GARIS TRANSAKSI & PENDAPATAN HARIAN DENGAN CHART.JS) -->
    <!-- ================================================================= -->
    <section class="rounded-2xl border border-slate-200 bg-white p-5 shadow-xs sm:p-6 space-y-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="flex items-center gap-2 text-base font-bold text-slate-800">
            <TrendingUp class="h-5 w-5 text-emerald-600" />
            Grafik Garis Transaksi &amp; Pendapatan Harian
          </h2>
          <p class="text-xs text-slate-400">
            Setiap titik menampilkan akumulasi jumlah transaksi sewa dan total nominal pendapatan pada hari tersebut.
          </p>
        </div>

        <!-- Indikator Data Terpilih -->
        <div class="flex items-center gap-3 text-xs">
          <span class="inline-flex items-center gap-1.5 font-semibold text-slate-600">
            <span class="h-2.5 w-2.5 rounded-full bg-blue-500"></span>
            Transaksi
          </span>
          <span class="inline-flex items-center gap-1.5 font-semibold text-slate-600">
            <span class="h-2.5 w-2.5 rounded-full bg-emerald-500"></span>
            Pendapatan
          </span>
        </div>
      </div>

      <!-- Area Canvas Grafik Chart.js -->
      <div class="relative h-72 sm:h-80 w-full">
        <canvas ref="chartCanvas"></canvas>
      </div>
    </section>

    <!-- ================================================================= -->
    <!-- TABEL DATA TRANSAKSI                                              -->
    <!-- Menampilkan: unit, tgl transaksi, jumlah hari, total, status       -->
    <!-- ================================================================= -->
    <section class="rounded-2xl border border-slate-200 bg-white shadow-xs overflow-hidden">
      <!-- Header Tabel -->
      <div class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-100 p-5">
        <div>
          <h2 class="text-base font-bold text-slate-800">
            Daftar Data Transaksi Sewa
          </h2>
          <p class="text-xs text-slate-400">
            Daftar transaksi armada yang sesuai dengan parameter filter di atas.
          </p>
        </div>

        <span class="rounded-lg bg-blue-50 px-2.5 py-1 text-xs font-bold text-blue-700">
          {{ filteredBookings.length }} Transaksi
        </span>
      </div>

      <!-- State Loading -->
      <div
        v-if="loading"
        class="flex items-center justify-center gap-2 py-16 text-sm text-slate-500"
      >
        <LoaderCircle class="h-5 w-5 animate-spin text-blue-600" />
        Memuat data transaksi...
      </div>

      <!-- State Kosong -->
      <div
        v-else-if="filteredBookings.length === 0"
        class="py-16 text-center text-sm text-slate-500 space-y-3"
      >
        <p>Tidak ada transaksi sewa yang sesuai dengan filter yang dipilih.</p>
        <button
          type="button"
          class="inline-flex items-center gap-1 rounded-xl border border-slate-300 bg-white px-3 py-1.5 text-xs font-semibold text-slate-700 shadow-2xs hover:bg-slate-50 cursor-pointer"
          @click="resetAllFilters"
        >
          Reset Filter
        </button>
      </div>

      <!-- Tabel Responsif -->
      <div v-else class="overflow-x-auto">
        <table class="w-full border-collapse text-left text-xs">
          <thead class="border-b border-slate-200 bg-slate-50/75 text-[11px] font-bold uppercase tracking-wider text-slate-600">
            <tr>
              <th scope="col" class="py-3.5 pl-5 pr-3">No</th>
              <th scope="col" class="py-3.5 px-3">Unit Kendaraan</th>
              <th scope="col" class="py-3.5 px-3">Penyewa (Customer)</th>
              <th scope="col" class="py-3.5 px-3">Tanggal Transaksi</th>
              <th scope="col" class="py-3.5 px-3 text-center">Durasi (Hari)</th>
              <th scope="col" class="py-3.5 px-3 text-right">Total Transaksi</th>
              <th scope="col" class="py-3.5 px-3 text-center">Status</th>
              <th scope="col" class="py-3.5 pl-3 pr-5 text-right">Aksi</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-slate-100 text-slate-700">
            <tr
              v-for="(booking, idx) in filteredBookings"
              :key="booking.id"
              class="transition-colors hover:bg-slate-50/80"
            >
              <!-- No Urut -->
              <td class="py-3.5 pl-5 pr-3 font-semibold text-slate-400">
                {{ idx + 1 }}
              </td>

              <!-- Unit Kendaraan (Thumbnail, Nama, Nopol) -->
              <td class="py-3.5 px-3">
                <div class="flex items-center gap-2.5">
                  <div class="h-10 w-14 shrink-0 overflow-hidden rounded-lg border border-slate-200 bg-slate-100">
                    <img
                      v-if="getVehicleThumbnail(booking.vehicle)"
                      :src="getVehicleThumbnail(booking.vehicle)"
                      :alt="booking.vehicle?.name"
                      class="h-full w-full object-cover"
                    />
                    <div
                      v-else
                      class="flex h-full w-full items-center justify-center text-base"
                    >
                      {{ VEHICLE_TYPE[booking.vehicle?.type]?.emoji ?? "🚗" }}
                    </div>
                  </div>
                  <div>
                    <RouterLink
                      :to="{
                        name: 'admin-vehicle-detail',
                        params: { vehicleId: booking.vehicle?.id ?? '' },
                      }"
                      class="font-bold text-slate-800 hover:text-blue-600 line-clamp-1 cursor-pointer"
                    >
                      {{ booking.vehicle?.name ?? "Unit Dihapus" }}
                    </RouterLink>
                    <p class="text-[11px] text-slate-400">
                      {{ booking.vehicle?.license_plate }} ·
                      {{ VEHICLE_TYPE[booking.vehicle?.type]?.label ?? "Kendaraan" }}
                    </p>
                  </div>
                </div>
              </td>

              <!-- Pelanggan / Customer -->
              <td class="py-3.5 px-3">
                <p class="font-bold text-slate-800 line-clamp-1">
                  {{ booking.customer?.full_name ?? "Tanpa Nama" }}
                </p>
                <p class="text-[11px] text-slate-400">
                  {{ booking.customer?.phone_number || booking.customer?.email }}
                </p>
              </td>

              <!-- Tanggal Transaksi & Rentang Sewa -->
              <td class="py-3.5 px-3">
                <p class="font-semibold text-slate-800">
                  {{ formatDate(booking.created_at) }}
                </p>
                <p class="text-[11px] text-slate-400">
                  Sewa: {{ formatDate(booking.start_date) }} - {{ formatDate(booking.end_date) }}
                </p>
              </td>

              <!-- Durasi / Kuantitas Hari -->
              <td class="py-3.5 px-3 text-center">
                <span class="inline-flex items-center rounded-lg bg-slate-100 px-2 py-0.5 text-xs font-bold text-slate-700">
                  {{ rentalDays(booking.start_date, booking.end_date) }} Hari
                </span>
                <p class="mt-0.5 text-[10px] text-slate-400">
                  @ {{ rupiah(booking.vehicle?.price_per_day) }}/hr
                </p>
              </td>

              <!-- Total Transaksi -->
              <td class="py-3.5 px-3 text-right">
                <p class="font-bold text-slate-900">
                  {{ rupiah(booking.return_info?.final_price ?? booking.total_price) }}
                </p>
                <span
                  v-if="booking.return_info?.late_fee || booking.return_info?.damage_fee"
                  class="text-[10px] text-amber-600 font-semibold"
                >
                  Termasuk Denda
                </span>
              </td>

              <!-- Status Sewa -->
              <td class="py-3.5 px-3 text-center">
                <StatusBadge :value="booking.status" kind="booking" />
              </td>

              <!-- Aksi Detail -->
              <td class="py-3.5 pl-3 pr-5 text-right">
                <button
                  type="button"
                  title="Lihat Rincian Transaksi"
                  class="inline-flex items-center gap-1 rounded-lg border border-slate-200 bg-white px-2.5 py-1 text-xs font-semibold text-slate-700 shadow-2xs hover:border-blue-300 hover:bg-blue-50 hover:text-blue-700 cursor-pointer"
                  @click="openDetail(booking)"
                >
                  <Eye class="h-3.5 w-3.5" />
                  Rincian
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- ================================================================= -->
    <!-- MODAL RINCIAN TRANSAKSI SEWA                                      -->
    <!-- ================================================================= -->
    <AppModal
      :open="detailModalOpen"
      title="Rincian Transaksi Sewa"
      @close="detailModalOpen = false"
    >
      <div v-if="selectedBooking" class="space-y-4">
        <!-- Informasi Unit -->
        <div class="flex items-center gap-3 rounded-xl border border-slate-200 bg-slate-50 p-3">
          <div class="h-14 w-20 shrink-0 overflow-hidden rounded-lg border border-slate-200 bg-white">
            <img
              v-if="getVehicleThumbnail(selectedBooking.vehicle)"
              :src="getVehicleThumbnail(selectedBooking.vehicle)"
              :alt="selectedBooking.vehicle?.name"
              class="h-full w-full object-cover"
            />
            <div v-else class="flex h-full w-full items-center justify-center text-2xl">
              {{ VEHICLE_TYPE[selectedBooking.vehicle?.type]?.emoji ?? "🚗" }}
            </div>
          </div>
          <div>
            <span class="rounded bg-blue-100 px-1.5 py-0.5 text-[9px] font-bold uppercase text-blue-700">
              {{ VEHICLE_TYPE[selectedBooking.vehicle?.type]?.label ?? "Kendaraan" }}
            </span>
            <h3 class="font-bold text-slate-800 text-sm mt-0.5">
              {{ selectedBooking.vehicle?.name }}
            </h3>
            <p class="text-xs text-slate-500">
              {{ selectedBooking.vehicle?.license_plate }} ·
              {{ rupiah(selectedBooking.vehicle?.price_per_day) }}/hari
            </p>
          </div>
        </div>

        <!-- Rincian Penyewa & Sewa -->
        <div class="rounded-xl border border-slate-200 p-3 space-y-2 text-xs">
          <div class="flex justify-between">
            <span class="text-slate-400">Penyewa</span>
            <span class="font-bold text-slate-800">{{ selectedBooking.customer?.full_name ?? "Tanpa Nama" }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-slate-400">No. WhatsApp / HP</span>
            <span class="font-bold text-slate-800">{{ selectedBooking.customer?.phone_number || "-" }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-slate-400">Email</span>
            <span class="font-bold text-slate-800">{{ selectedBooking.customer?.email }}</span>
          </div>
          <div class="border-t border-slate-100 pt-2 flex justify-between">
            <span class="text-slate-400">Waktu Transaksi</span>
            <span class="font-bold text-slate-800">{{ formatDateTime(selectedBooking.created_at) }}</span>
          </div>
          <div class="flex justify-between">
            <span class="text-slate-400">Jadwal Sewa</span>
            <span class="font-bold text-slate-800">
              {{ formatDate(selectedBooking.start_date) }} - {{ formatDate(selectedBooking.end_date) }}
            </span>
          </div>
          <div class="flex justify-between">
            <span class="text-slate-400">Durasi Sewa</span>
            <span class="font-bold text-blue-600">
              {{ rentalDays(selectedBooking.start_date, selectedBooking.end_date) }} Hari
            </span>
          </div>
          <div class="flex justify-between items-center">
            <span class="text-slate-400">Status Sewa</span>
            <StatusBadge :value="selectedBooking.status" kind="booking" />
          </div>
        </div>

        <!-- Rincian Biaya & Pembayaran -->
        <div class="rounded-xl border border-slate-200 bg-slate-50/50 p-3 space-y-2 text-xs">
          <div class="flex justify-between">
            <span class="text-slate-500">Tarif Sewa Pokok</span>
            <span class="font-semibold text-slate-800">{{ rupiah(selectedBooking.total_price) }}</span>
          </div>

          <template v-if="selectedBooking.return_info">
            <div v-if="Number(selectedBooking.return_info.late_fee)" class="flex justify-between text-amber-600">
              <span>Denda Keterlambatan</span>
              <span class="font-semibold">+ {{ rupiah(selectedBooking.return_info.late_fee) }}</span>
            </div>
            <div v-if="Number(selectedBooking.return_info.damage_fee)" class="flex justify-between text-amber-600">
              <span>Biaya Kerusakan</span>
              <span class="font-semibold">+ {{ rupiah(selectedBooking.return_info.damage_fee) }}</span>
            </div>
          </template>

          <div class="border-t border-slate-200 pt-2 flex justify-between text-sm font-extrabold">
            <span class="text-slate-800">Total Transaksi</span>
            <span class="text-blue-600">
              {{ rupiah(selectedBooking.return_info?.final_price ?? selectedBooking.total_price) }}
            </span>
          </div>
        </div>

        <div class="flex gap-2 pt-2">
          <button
            type="button"
            class="flex-1 rounded-xl border border-slate-300 px-4 py-2 text-xs font-semibold text-slate-700 hover:bg-slate-50 cursor-pointer"
            @click="detailModalOpen = false"
          >
            Tutup
          </button>
        </div>
      </div>
    </AppModal>
  </div>
</template>
