// Helper format & label bersama untuk seluruh halaman.

const rupiahFormatter = new Intl.NumberFormat("id-ID", {
  style: "currency",
  currency: "IDR",
  maximumFractionDigits: 0,
});

const dateTimeFormatter = new Intl.DateTimeFormat("id-ID", {
  dateStyle: "medium",
  timeStyle: "short",
});

const dateFormatter = new Intl.DateTimeFormat("id-ID", { dateStyle: "medium" });

export function rupiah(value) {
  return rupiahFormatter.format(Number(value) || 0);
}

export function formatDateTime(value) {
  if (!value) return "-";
  return dateTimeFormatter.format(new Date(value));
}

export function formatDate(value) {
  if (!value) return "-";
  return dateFormatter.format(new Date(value));
}

/** Menghitung jumlah hari sewa (dibulatkan ke atas, minimal 1 hari). */
export function rentalDays(start, end) {
  if (!start || !end) return 0;
  const startMs = new Date(start).getTime();
  const endMs = new Date(end).getTime();
  if (Number.isNaN(startMs) || Number.isNaN(endMs) || endMs <= startMs)
    return 0;
  return Math.max(1, Math.ceil((endMs - startMs) / (1000 * 60 * 60 * 24)));
}

/** Selisih durasi dalam bentuk teks, mis. "2 hari 3 jam". */
export function formatDuration(ms) {
  const totalMinutes = Math.max(0, Math.floor(Math.abs(ms) / 60000));
  const days = Math.floor(totalMinutes / 1440);
  const hours = Math.floor((totalMinutes % 1440) / 60);
  const minutes = totalMinutes % 60;

  const parts = [];
  if (days) parts.push(`${days} hari`);
  if (hours) parts.push(`${hours} jam`);
  if (!days && minutes) parts.push(`${minutes} menit`);
  return parts.length ? parts.join(" ") : "0 menit";
}

export const BOOKING_STATUS = {
  PENDING: { label: "Menunggu Verifikasi", tone: "amber" },
  APPROVED: { label: "Disetujui", tone: "blue" },
  ACTIVE: { label: "Sedang Disewa", tone: "indigo" },
  COMPLETED: { label: "Selesai", tone: "emerald" },
  CANCELLED: { label: "Dibatalkan", tone: "slate" },
};

export const VEHICLE_STATUS = {
  AVAILABLE: { label: "Tersedia", tone: "emerald" },
  BOOKED: { label: "Disewa", tone: "slate" },
  MAINTENANCE: { label: "Maintenance", tone: "amber" },
};

export const VEHICLE_TYPE = {
  CAR: { label: "Mobil", emoji: "🚗" },
  MOTORCYCLE: { label: "Motor", emoji: "🛵" },
};

/**
 * Mendapatkan URL gambar thumbnail kendaraan dari gambar pertama di vehicle_images.
 * Jika tidak ada gambar di vehicle_images, mengembalikan null (tidak ada gambar).
 */
export function getVehicleThumbnail(vehicle) {
  if (!vehicle) return null;
  const list = vehicle.vehicle_images || vehicle.images;
  if (Array.isArray(list) && list.length > 0) {
    const sorted = [...list].sort((a, b) => {
      if (a.created_at && b.created_at) {
        return new Date(a.created_at) - new Date(b.created_at);
      }
      return 0;
    });
    return sorted[0]?.image_url || null;
  }
  return null;
}

/** Menormalkan data tags dari database menjadi array of string. */
export function parseVehicleTags(rawTags) {
  if (!rawTags) return [];
  if (Array.isArray(rawTags)) return rawTags.map(String).map((t) => t.trim()).filter(Boolean);
  if (typeof rawTags === "string") {
    const trimmed = rawTags.trim();
    if (!trimmed) return [];
    if (trimmed.startsWith("[") && trimmed.endsWith("]")) {
      try {
        const parsed = JSON.parse(trimmed);
        return Array.isArray(parsed)
          ? parsed.map(String).map((t) => t.trim()).filter(Boolean)
          : [];
      } catch {
        // fallback parsing string biasa
      }
    }
    // Jika format Postgres array text `{a,b,c}`
    if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
      return trimmed
        .slice(1, -1)
        .split(",")
        .map((s) => s.replace(/^"|"$/g, "").trim())
        .filter(Boolean);
    }
    return trimmed
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
  }
  return [];
}

/** Opsi tag spesifikasi & fasilitas rental mobil dan motor. */
export const VEHICLE_TAG_PRESETS = {
  CAR: [
    {
      category: "Transmisi",
      options: ["Matic (Automatic)", "Manual"],
    },
    {
      category: "Kapasitas Kursi",
      options: ["4 Kursi", "5 Kursi", "7 Kursi", "8+ Kursi"],
    },
    {
      category: "Fasilitas & Kenyamanan",
      options: [
        "AC Dingin",
        "Double Blower",
        "Audio Bluetooth",
        "Port USB Charger",
        "Kamera Mundur",
        "Sensor Parkir",
        "Android Auto / CarPlay",
      ],
    },
    {
      category: "Bahan Bakar & Mesin",
      options: ["Bensin", "Diesel / Solar", "Mobil Listrik (EV)", "Irit BBM"],
    },
    {
      category: "Layanan & Kebijakan",
      options: ["Lepas Kunci", "Bisa + Sopir", "Bebas Asap Rokok"],
    },
  ],
  MOTORCYCLE: [
    {
      category: "Transmisi",
      options: ["Matic", "Manual / Bebek", "Kopling"],
    },
    {
      category: "Kelengkapan & Fasilitas",
      options: [
        "Include 2 Helm",
        "Include Jas Hujan",
        "Phone Holder",
        "Keyless Smart Key",
        "Bagasi Luas",
        "Port USB Charger",
      ],
    },
    {
      category: "Bahan Bakar",
      options: ["Bensin", "Irit BBM"],
    },
    {
      category: "Layanan",
      options: ["Lepas Kunci"],
    },
  ],
};

/** Kelas Tailwind untuk badge status booking. */
export function statusTone(tone) {
  const map = {
    amber: "bg-amber-50 text-amber-700 border-amber-200",
    blue: "bg-blue-50 text-blue-700 border-blue-200",
    indigo: "bg-indigo-50 text-indigo-700 border-indigo-200",
    emerald: "bg-emerald-50 text-emerald-700 border-emerald-200",
    slate: "bg-slate-100 text-slate-600 border-slate-200",
    red: "bg-red-50 text-red-700 border-red-200",
  };
  return map[tone] ?? map.slate;
}

/** Mengubah nilai input datetime-local menjadi ISO string. */
export function toIso(localDateTimeValue) {
  if (!localDateTimeValue) return null;
  return new Date(localDateTimeValue).toISOString();
}

/** Mengubah ISO string menjadi nilai untuk input datetime-local. */
export function toLocalInput(isoValue) {
  if (!isoValue) return "";
  const date = new Date(isoValue);
  const offset = date.getTimezoneOffset();
  return new Date(date.getTime() - offset * 60000).toISOString().slice(0, 16);
}

/** Field wajib profil penyewa untuk verifikasi rental kendaraan */
export const REQUIRED_PROFILE_FIELDS = {
  full_name: "Nama Lengkap (KTP)",
  phone_number: "Nomor WhatsApp / HP",
  nik: "NIK KTP (16 Digit)",
  sim_number: "Nomor SIM (SIM A / SIM C)",
  ktp_image_url: "Foto Dokumen KTP Asli",
  address: "Alamat Lengkap Domisili",
  city: "Kota / Kabupaten",
  emergency_contact_name: "Nama Kontak Darurat",
  emergency_contact_phone: "Nomor HP Kontak Darurat",
};

/** Memeriksa apakah data profil pelanggan sudah lengkap untuk menyewa unit */
export function isProfileComplete(profile) {
  if (!profile) return false;
  const detail = profile.detail_user || profile;

  // Cek field tabel users
  const hasName = Boolean(profile.full_name && String(profile.full_name).trim());
  const hasPhone = Boolean(profile.phone_number && String(profile.phone_number).trim());

  // Cek field tabel detail_user
  const detailKeys = [
    "nik",
    "sim_number",
    "ktp_image_url",
    "address",
    "city",
    "emergency_contact_name",
    "emergency_contact_phone",
  ];
  const hasDetail = detailKeys.every((key) => {
    const val = detail[key] || profile[key];
    return typeof val === "string" && val.trim().length > 0;
  });

  return hasName && hasPhone && hasDetail;
}

/** Mengambil daftar nama field profil yang belum diisi oleh pelanggan */
export function getMissingProfileFields(profile) {
  if (!profile) return Object.values(REQUIRED_PROFILE_FIELDS);
  const detail = profile.detail_user || profile;

  const missing = [];
  if (!profile.full_name || !String(profile.full_name).trim()) {
    missing.push(REQUIRED_PROFILE_FIELDS.full_name);
  }
  if (!profile.phone_number || !String(profile.phone_number).trim()) {
    missing.push(REQUIRED_PROFILE_FIELDS.phone_number);
  }

  const detailKeys = [
    "nik",
    "sim_number",
    "ktp_image_url",
    "address",
    "city",
    "emergency_contact_name",
    "emergency_contact_phone",
  ];
  for (const k of detailKeys) {
    const val = detail[k] || profile[k];
    if (!val || typeof val !== "string" || !val.trim()) {
      missing.push(REQUIRED_PROFILE_FIELDS[k]);
    }
  }

  return missing;
}

