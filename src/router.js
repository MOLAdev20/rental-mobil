import { createRouter, createWebHistory } from "vue-router";
import { useAuth } from "./composables/useAuth";
import AppLayout from "./layouts/AppLayout.vue";

const routes = [
  {
    path: "/auth",
    name: "auth",
    component: () => import("./pages/Auth.vue"),
    meta: { guestOnly: true },
  },
  {
    path: "/",
    component: AppLayout,
    meta: { requiresAuth: true },
    children: [
      {
        path: "",
        redirect: () => {
          const { isAdmin } = useAuth();
          return { name: isAdmin.value ? "admin-bookings" : "catalog" };
        },
      },
      {
        path: "dashboard",
        name: "catalog",
        component: () => import("./pages/Dashboard.vue"),
        meta: { customerOnly: true },
      },
      {
        path: "vehicles/:vehicleId",
        name: "vehicle-detail",
        component: () => import("./pages/VehicleDetail.vue"),
        props: true,
      },
      {
        path: "booking/:vehicleId",
        name: "booking",
        component: () => import("./pages/Booking.vue"),
        props: true,
      },
      {
        path: "orders",
        name: "orders",
        component: () => import("./pages/Orders.vue"),
      },
      {
        path: "admin",
        redirect: { name: "admin-bookings" },
      },
      {
        path: "admin/bookings",
        name: "admin-bookings",
        component: () => import("./pages/admin/Bookings.vue"),
        meta: { requiresAdmin: true },
      },
      {
        path: "admin/vehicles",
        name: "admin-vehicles",
        component: () => import("./pages/admin/Fleet.vue"),
        meta: { requiresAdmin: true },
      },
      {
        path: "admin/vehicles/:vehicleId",
        name: "admin-vehicle-detail",
        component: () => import("./pages/admin/FleetDetail.vue"),
        props: true,
        meta: { requiresAdmin: true },
      },
      {
        path: "admin/returns",
        name: "admin-returns",
        component: () => import("./pages/admin/Returns.vue"),
        meta: { requiresAdmin: true },
      },
      {
        path: "admin/reports",
        name: "admin-reports",
        component: () => import("./pages/admin/Reports.vue"),
        meta: { requiresAdmin: true },
      },
    ],
  },
  {
    path: "/:pathMatch(.*)*",
    redirect: () => {
      const { isAdmin } = useAuth();
      return { name: isAdmin.value ? "admin-bookings" : "catalog" };
    },
  },
];

const router = createRouter({
  history: createWebHistory(),
  routes,
  scrollBehavior: () => ({ top: 0 }),
});

router.beforeEach(async (to) => {
  const { session, profile, isAdmin, ready, refreshProfile } = useAuth();

  // Tunggu pengecekan session awal selesai sebelum memutuskan.
  await ready();

  if (to.meta.requiresAuth && !session.value) {
    return { name: "auth", query: { redirect: to.fullPath } };
  }

  if (session.value && !profile.value) {
    await refreshProfile();
  }

  if (to.meta.guestOnly && session.value) {
    return isAdmin.value ? { name: "admin-bookings" } : { name: "catalog" };
  }

  if (to.meta.requiresAdmin) {
    if (!isAdmin.value) return { name: "catalog" };
  }

  // Role ADMIN tidak diizinkan mengakses halaman katalog customer
  if (isAdmin.value && (to.name === "catalog" || to.meta.customerOnly)) {
    return { name: "admin-bookings" };
  }

  return true;
});

export default router;
