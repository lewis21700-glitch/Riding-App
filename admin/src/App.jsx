import { useState, useEffect, useMemo, useCallback, useRef } from "react";
import {
  LayoutDashboard,
  Users,
  Car,
  Route,
  CreditCard,
  Star,
  Bell,
  Search,
  Plus,
  RefreshCw,
  LogOut,
  Edit2,
  Trash2,
  Eye,
  CheckCircle2,
  Clock,
  XCircle,
  AlertCircle,
  Shield,
  MapPin,
  DollarSign,
  Activity,
  Layers,
  ChevronRight,
  UserCheck,
  LogIn,
  KeyRound,
  TrendingUp,
  Radio,
  Volume2,
  VolumeX,
  Zap,
  Phone,
  Navigation,
  Check,
  ShieldAlert,
} from "lucide-react";
import "./App.css";

// API origin configuration
const API = import.meta.env.VITE_API_URL || "";

// Audio notification chime using Web Audio API (zero external dependencies)
function playDispatchChime() {
  try {
    const AudioContextClass = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextClass) return;
    const ctx = new AudioContextClass();
    const osc1 = ctx.createOscillator();
    const osc2 = ctx.createOscillator();
    const gain = ctx.createGain();

    osc1.type = "sine";
    osc1.frequency.setValueAtTime(587.33, ctx.currentTime); // D5
    osc1.frequency.setValueAtTime(880, ctx.currentTime + 0.12); // A5

    osc2.type = "triangle";
    osc2.frequency.setValueAtTime(440, ctx.currentTime); // A4
    osc2.frequency.setValueAtTime(659.25, ctx.currentTime + 0.12); // E5

    gain.gain.setValueAtTime(0.18, ctx.currentTime);
    gain.gain.exponentialRampToValueAtTime(0.001, ctx.currentTime + 0.5);

    osc1.connect(gain);
    osc2.connect(gain);
    gain.connect(ctx.destination);

    osc1.start();
    osc2.start();
    osc1.stop(ctx.currentTime + 0.5);
    osc2.stop(ctx.currentTime + 0.5);
  } catch {
    // browser audio policies require initial user interaction
  }
}

const formatMoney = (amount, currency = "USD") => {
  const num = Number(amount || 0);
  if (currency === "KHR") {
    return `${new Intl.NumberFormat("en-US").format(Math.round(num))} ៛`;
  }
  return `$${num.toFixed(2)}`;
};

const formatDate = (val) => {
  if (!val) return "—";
  try {
    return new Date(val).toLocaleString("en-GB", {
      day: "2-digit",
      month: "short",
      year: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return String(val);
  }
};

const initialUser = { name: "", email: "", phone: "", password: "", role: "rider" };
const initialDriver = { name: "", email: "", phone: "", password: "", availability: "offline" };
const initialVehicle = { driver_id: "", vehicle_type: "Car", vehicle_model: "", plate_number: "" };

// Fallback preview data so the dashboard UI is immediately rich and interactive even before logging in
const fallbackPreview = {
  riders: [
    { id: 5, name: "David Kem", email: "rider.david@rideapp.com", phone: "077222333", role: "rider" },
    { id: 6, name: "Dara Sam", email: "rider.dara@rideapp.com", phone: "085444555", role: "rider" },
  ],
  drivers: [
    { id: 2, name: "Sokha Chan", email: "driver.sokha@rideapp.com", phone: "012888999", role: "driver", availability: "available", vehicle_id: 1, vehicle_model: "Toyota Prius 2018", plate_number: "2BP-1928" },
    { id: 3, name: "Vireak Meng", email: "driver.vireak@rideapp.com", phone: "098777666", role: "driver", availability: "available", vehicle_id: 2, vehicle_model: "Mazda 3 2022", plate_number: "2BD-8891" },
    { id: 4, name: "Bopha Pich", email: "driver.bopha@rideapp.com", phone: "088111222", role: "driver", availability: "offline", vehicle_id: 3, vehicle_model: "Bajaj RE 2021", plate_number: "1Q-4452" },
  ],
  vehicles: [
    { id: 1, driver_id: 2, driver_name: "Sokha Chan", vehicle_type: "Car", vehicle_model: "Toyota Prius 2018 (Silver)", plate_number: "2BP-1928" },
    { id: 2, driver_id: 3, driver_name: "Vireak Meng", vehicle_type: "Car", vehicle_model: "Mazda 3 2022 (Blue)", plate_number: "2BD-8891" },
    { id: 3, driver_id: 4, driver_name: "Bopha Pich", vehicle_type: "Tuk Tuk", vehicle_model: "Bajaj RE 2021 (Yellow)", plate_number: "1Q-4452" },
  ],
  rides: [
    { id: 1, rider_id: 5, rider_name: "David Kem", driver_id: 2, driver_name: "Sokha Chan", pickup_location: "Aeon Mall 1 (Samdach Sothearos Blvd)", destination: "Wat Phnom Historical Park", ride_type: "Car", distance_km: 4.8, fare: 5.10, status: "completed", created_at: new Date(Date.now() - 7200000).toISOString() },
    { id: 2, rider_id: 6, rider_name: "Dara Sam", driver_id: 3, driver_name: "Vireak Meng", pickup_location: "Independence Monument", destination: "Royal Palace Phnom Penh", ride_type: "Car", distance_km: 2.3, fare: 3.23, status: "completed", created_at: new Date(Date.now() - 3600000).toISOString() },
    { id: 3, rider_id: 5, rider_name: "David Kem", driver_id: 2, driver_name: "Sokha Chan", pickup_location: "Phnom Penh Railway Station", destination: "Russian Market (Toul Tom Poung)", ride_type: "Car", distance_km: 3.9, estimated_fare: 4.43, fare: null, status: "ongoing", created_at: new Date(Date.now() - 900000).toISOString() },
    { id: 4, rider_id: 6, rider_name: "Dara Sam", driver_id: null, driver_name: null, pickup_location: "Tuol Sleng Genocide Museum", destination: "Central Market (Phsar Thmey)", ride_type: "Car", distance_km: 3.2, estimated_fare: 3.90, fare: null, status: "requested", created_at: new Date(Date.now() - 300000).toISOString() },
  ],
  payments: [
    { id: 1, ride_id: 1, rider_name: "David Kem", amount: 5.10, payment_method: "cash", status: "paid", created_at: new Date(Date.now() - 6900000).toISOString() },
    { id: 2, ride_id: 2, rider_name: "Dara Sam", amount: 3.23, payment_method: "bakong_khqr", status: "paid", created_at: new Date(Date.now() - 3000000).toISOString() },
  ],
  ratings: [
    { id: 1, ride_id: 1, rater_name: "David Kem", ratee_name: "Sokha Chan", score: 5, comment: "Very polite driver and smooth ride. Car was spotless!", created_at: new Date(Date.now() - 6600000).toISOString() },
    { id: 2, ride_id: 2, rater_name: "Dara Sam", ratee_name: "Vireak Meng", score: 5, comment: "Arrived very quickly and knew the best shortcuts.", created_at: new Date(Date.now() - 2700000).toISOString() },
  ],
  notifications: [
    { id: 1, user_id: 1, title: "System Ready", message: "RideApp core services and database initialized.", type: "system", is_read: 0, created_at: new Date(Date.now() - 10800000).toISOString() },
    { id: 2, user_id: 5, title: "Ride Completed", message: "Your trip with driver Sokha Chan was completed. Total: $5.10.", type: "ride", is_read: 1, created_at: new Date(Date.now() - 6900000).toISOString() },
  ],
};

export default function App() {
  const [token, setToken] = useState(() => localStorage.getItem("token") || "");
  const [adminUser, setAdminUser] = useState(() => {
    try {
      return JSON.parse(localStorage.getItem("user") || "null");
    } catch {
      return null;
    }
  });
  const isAdminSession = Boolean(token && adminUser?.role === "admin");

  const [activeTab, setActiveTab] = useState("Dashboard");
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("all");
  const [commissionRate, setCommissionRate] = useState(15);
  const [baseFare, setBaseFare] = useState(1.00);
  const [perKmRate, setPerKmRate] = useState(0.75);
  const [settledDrivers, setSettledDrivers] = useState({});
  const [adminStatusUpdating, setAdminStatusUpdating] = useState(false);
  const [loading, setLoading] = useState(false);
  const [refreshing, setRefreshing] = useState(false);
  const [backendOnline, setBackendOnline] = useState(true);
  const [connectionNote, setConnectionNote] = useState("");

  // Dispatch & live alert state
  const [soundEnabled, setSoundEnabled] = useState(() => localStorage.getItem("adminSound") !== "false");
  const [autoSync, setAutoSync] = useState(true);
  const [selectedDispatchDriver, setSelectedDispatchDriver] = useState({});
  const [dispatchingRideId, setDispatchingRideId] = useState(null);
  const prevPendingCountRef = useRef(0);

  const toggleSound = () => {
    setSoundEnabled((prev) => {
      const next = !prev;
      localStorage.setItem("adminSound", String(next));
      if (next) playDispatchChime();
      return next;
    });
  };

  // Data states initialized with preview fallback so UI is immediately rich
  const [users, setUsers] = useState(fallbackPreview.riders);
  const [drivers, setDrivers] = useState(fallbackPreview.drivers);
  const [rides, setRides] = useState(fallbackPreview.rides);
  const [payments, setPayments] = useState(fallbackPreview.payments);
  const [vehicles, setVehicles] = useState(fallbackPreview.vehicles);
  const [ratings, setRatings] = useState(fallbackPreview.ratings);
  const [notifications, setNotifications] = useState(fallbackPreview.notifications);

  // Modals
  const [userModal, setUserModal] = useState(null);
  const [driverModal, setDriverModal] = useState(null);
  const [vehicleModal, setVehicleModal] = useState(null);
  const [rideDetailsModal, setRideDetailsModal] = useState(null);
  const [authPromptModal, setAuthPromptModal] = useState(false);

  // Login form state inside the Account tab
  const [authMode, setAuthMode] = useState("login"); // 'login' or 'register'
  const [loginEmail, setLoginEmail] = useState("");
  const [loginPassword, setLoginPassword] = useState("");
  const [regName, setRegName] = useState("");
  const [regEmail, setRegEmail] = useState("");
  const [regPhone, setRegPhone] = useState("");
  const [regPassword, setRegPassword] = useState("");
  const [authError, setAuthError] = useState("");
  const [authSuccess, setAuthSuccess] = useState("");
  const [loginLoading, setLoginLoading] = useState(false);

  const apiRequest = useCallback(
    async (path, options = {}) => {
      const currentToken = localStorage.getItem("token");
      const res = await fetch(`${API}${path}`, {
        ...options,
        headers: {
          "Content-Type": "application/json",
          ...(currentToken ? { Authorization: `Bearer ${currentToken}` } : {}),
          ...(options.headers || {}),
        },
      });

      let data = {};
      try {
        data = await res.json();
      } catch {
        /* empty response */
      }

      if (res.status === 401) {
        localStorage.removeItem("token");
        localStorage.removeItem("user");
        setToken("");
        setAdminUser(null);
      }
      if (!res.ok) {
        throw new Error(data.error || data.detail || `Request failed (${res.status})`);
      }
      return data;
    },
    []
  );

  const loadData = useCallback(async (silent = false) => {
    if (!silent) setLoading(true);
    setConnectionNote("");
    try {
      const currentToken = localStorage.getItem("token");
      if (!currentToken || !isAdminSession) {
        // Check backend health without loading admin data before sign-in.
        let h = await fetch(`${API}/health`).then((r) => r.json()).catch(() => null);
        if (!h || h.status !== "ok") {
          h = await fetch("http://127.0.0.1:3000/health").then((r) => r.json()).catch(() => null);
        }
        if (!h || h.status !== "ok") {
          h = await fetch(`${API}/api/health`).then((r) => r.json()).catch(() => null);
        }
        if (h && (h.status === "ok" || h.status === "healthy")) {
          setBackendOnline(true);
        } else {
          setBackendOnline(false);
          setConnectionNote("FastAPI service on port 3000 is offline. Start it via start_backend.bat.");
        }
        return;
      }

      const [u, d, r, p, v, notifs, rates] = await Promise.all([
        apiRequest("/api/users"),
        apiRequest("/api/drivers"),
        apiRequest("/api/rides"),
        apiRequest("/api/payments"),
        apiRequest("/api/vehicles"),
        apiRequest("/api/notifications"),
        apiRequest("/api/ratings"),
      ]);

      setUsers(Array.isArray(u) ? u : []);
      setDrivers(Array.isArray(d) ? d : []);
      setRides(Array.isArray(r) ? r : []);
      setPayments(Array.isArray(p) ? p : []);
      setVehicles(Array.isArray(v) ? v : []);
      setNotifications(Array.isArray(notifs) ? notifs : []);
      setRatings(Array.isArray(rates) ? rates : []);
      setBackendOnline(true);
    } catch (err) {
      console.warn("Live API sync issue:", err.message);
      setBackendOnline(false);
      setConnectionNote("Cannot connect to FastAPI backend on port 3000. Showing offline preview data.");
    } finally {
      if (!silent) setLoading(false);
      setRefreshing(false);
    }
  }, [apiRequest, isAdminSession]);

  useEffect(() => {
    loadData();
  }, [token, loadData]);

  // Live 4-second background synchronization
  useEffect(() => {
    if (!autoSync || !isAdminSession) return;
    const interval = setInterval(() => {
      loadData(true);
    }, 4000);
    return () => clearInterval(interval);
  }, [autoSync, isAdminSession, loadData]);

  // Pending incoming bookings tracking & chime trigger
  const pendingRides = useMemo(
    () => rides.filter((r) => r.status === "requested"),
    [rides]
  );

  useEffect(() => {
    const currentCount = pendingRides.length;
    if (currentCount > prevPendingCountRef.current && prevPendingCountRef.current !== 0) {
      if (soundEnabled) {
        playDispatchChime();
      }
    }
    prevPendingCountRef.current = currentCount;
  }, [pendingRides.length, soundEnabled]);

  const handleDispatchRide = async (rideId, driverId) => {
    if (!driverId) {
      alert("Please select an available driver to assign.");
      return;
    }
    setDispatchingRideId(rideId);
    try {
      await apiRequest(`/api/rides/${rideId}/status`, {
        method: "PUT",
        body: JSON.stringify({
          status: "accepted",
          driver_id: Number(driverId),
        }),
      });
      await loadData(true);
    } catch (err) {
      alert("Dispatch failed: " + err.message);
    } finally {
      setDispatchingRideId(null);
    }
  };

  const handleAutoDispatch = async (rideId) => {
    const availableDriver = drivers.find(
      (d) => d.availability === "available" || d.availability === "online"
    );
    if (!availableDriver) {
      alert("No drivers are currently online or available. Please wait for an available driver.");
      return;
    }
    await handleDispatchRide(rideId, availableDriver.id);
  };

  const handleCancelBooking = async (rideId) => {
    if (!confirm(`Are you sure you want to cancel incoming booking #${rideId}?`)) return;
    setDispatchingRideId(rideId);
    try {
      await apiRequest(`/api/rides/${rideId}/status`, {
        method: "PUT",
        body: JSON.stringify({ status: "cancelled" }),
      });
      await loadData(true);
    } catch (err) {
      alert("Cancellation failed: " + err.message);
    } finally {
      setDispatchingRideId(null);
    }
  };

  const handleManualRefresh = () => {
    setRefreshing(true);
    loadData();
  };

  const handleLogin = async (e) => {
    if (e) e.preventDefault();
    setAuthError("");
    setAuthSuccess("");
    if (!loginEmail.trim() || !loginPassword) {
      setAuthError("Please enter both email and password.");
      return;
    }
    setLoginLoading(true);
    try {
      const res = await fetch(`${API}/api/login`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: loginEmail.trim().toLowerCase(), password: loginPassword }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || data.detail || "Authentication failed");
      if (data.user?.role !== "admin") {
        throw new Error("This sign-in page is for administrators. Please use an admin account.");
      }

      localStorage.setItem("token", data.token);
      localStorage.setItem("user", JSON.stringify(data.user));
      setToken(data.token);
      setAdminUser(data.user);
      setLoginPassword("");
      const roleTitle = data.user?.role === "admin" ? "Administrator" : data.user?.role === "driver" ? "Driver" : "Passenger";
      setAuthSuccess(`Welcome, ${data.user?.name || "User"} (${roleTitle})!`);
      setActiveTab("Dashboard");
      setAuthPromptModal(false);
    } catch (err) {
      setAuthError(err.message || "Cannot reach FastAPI server on port 3000. Please start start_backend.bat.");
    } finally {
      setLoginLoading(false);
    }
  };

  const handleRegisterAdmin = async (e) => {
    if (e) e.preventDefault();
    setAuthError("");
    setAuthSuccess("");
    if (!regName.trim() || !regEmail.trim() || !regPassword) {
      setAuthError("Please complete all required fields.");
      return;
    }
    setLoginLoading(true);
    try {
      const res = await fetch(`${API}/api/register`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          name: regName.trim(),
          email: regEmail.trim().toLowerCase(),
          phone: regPhone.trim(),
          password: regPassword,
          role: "admin",
        }),
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || data.detail || "Registration failed");
      localStorage.setItem("token", data.token);
      localStorage.setItem("user", JSON.stringify(data.user));
      setToken(data.token);
      setAdminUser(data.user);
      setAuthSuccess("New administrator account created successfully!");
      setActiveTab("Dashboard");
    } catch (err) {
      setAuthError(err.message || "Registration failed.");
    } finally {
      setLoginLoading(false);
    }
  };

  const handleSettlePayout = (driverId) => {
    setSettledDrivers((prev) => ({
      ...prev,
      [driverId]: !prev[driverId],
    }));
    showToast("Driver payout settlement status updated!");
  };

  const handleAdminUpdateRideStatus = async (rideId, newStatus) => {
    setAdminStatusUpdating(true);
    try {
      if (token) {
        await apiFetch(`/rides/${rideId}/status`, {
          method: "PUT",
          body: JSON.stringify({ status: newStatus }),
        });
      }
      setRides((prev) =>
        prev.map((r) => (r.id === rideId ? { ...r, status: newStatus } : r))
      );
      if (rideDetailsModal && rideDetailsModal.id === rideId) {
        setRideDetailsModal((prev) => ({ ...prev, status: newStatus }));
      }
      showToast(`Ride #${rideId} status changed to ${newStatus}`);
      if (token) fetchData();
    } catch (err) {
      showToast(`Status update failed: ${err.message}`, "error");
    } finally {
      setAdminStatusUpdating(false);
    }
  };

  const fillDemo = (email, password) => {
    setLoginEmail(email);
    setLoginPassword(password);
    setAuthError("");
  };

  const handleLogout = () => {
    localStorage.removeItem("token");
    localStorage.removeItem("user");
    setToken("");
    setAdminUser(null);
    setAuthSuccess("Successfully logged out.");
  };

  // Auth gatekeeper for modifications
  const requireAdmin = (actionCallback) => {
    if (!token) {
      setAuthPromptModal(true);
      return;
    }
    if (adminUser?.role !== "admin") {
      alert(`Administrator privilege is required for create/edit/delete actions. You are currently signed in as ${adminUser?.role || "user"}.`);
      return;
    }
    actionCallback();
  };

  // CRUD actions
  const saveUser = async (formData) => {
    try {
      if (formData.id) {
        await apiRequest(`/api/users/${formData.id}`, { method: "PUT", body: JSON.stringify(formData) });
      } else {
        await apiRequest("/api/users", { method: "POST", body: JSON.stringify(formData) });
      }
      setUserModal(null);
      await loadData();
    } catch (err) {
      alert(`Error saving rider: ${err.message}`);
    }
  };

  const saveDriver = async (formData) => {
    try {
      if (formData.id) {
        await apiRequest(`/api/drivers/${formData.id}`, { method: "PUT", body: JSON.stringify(formData) });
      } else {
        await apiRequest("/api/drivers", { method: "POST", body: JSON.stringify(formData) });
      }
      setDriverModal(null);
      await loadData();
    } catch (err) {
      alert(`Error saving driver: ${err.message}`);
    }
  };

  const quickChangeDriverStatus = async (driver, newStatus) => {
    requireAdmin(async () => {
      try {
        await apiRequest(`/api/drivers/${driver.id}/availability`, {
          method: "PUT",
          body: JSON.stringify({ availability: newStatus }),
        });
        await loadData();
      } catch (err) {
        alert(`Error updating availability: ${err.message}`);
      }
    });
  };

  const saveVehicle = async (formData) => {
    try {
      const payload = { ...formData, driver_id: Number(formData.driver_id) };
      if (formData.id) {
        await apiRequest(`/api/vehicles/${formData.id}`, { method: "PUT", body: JSON.stringify(payload) });
      } else {
        await apiRequest("/api/vehicles", { method: "POST", body: JSON.stringify(payload) });
      }
      setVehicleModal(null);
      await loadData();
    } catch (err) {
      alert(`Error saving vehicle: ${err.message}`);
    }
  };

  const deleteRecord = async (path, label) => {
    requireAdmin(async () => {
      if (!window.confirm(`Are you sure you want to remove this ${label}? Associated trip history will be preserved.`)) {
        return;
      }
      try {
        await apiRequest(path, { method: "DELETE" });
        await loadData();
      } catch (err) {
        alert(`Delete failed: ${err.message}`);
      }
    });
  };

  // Filtered datasets
  const riders = useMemo(() => users.filter((u) => u.role === "rider"), [users]);

  const filteredRiders = useMemo(() => {
    const q = search.toLowerCase().trim();
    if (!q) return riders;
    return riders.filter(
      (r) =>
        r.name?.toLowerCase().includes(q) ||
        r.email?.toLowerCase().includes(q) ||
        r.phone?.toLowerCase().includes(q) ||
        String(r.id).includes(q)
    );
  }, [riders, search]);

  const filteredDrivers = useMemo(() => {
    const q = search.toLowerCase().trim();
    return drivers.filter((d) => {
      const matchesSearch =
        !q ||
        d.name?.toLowerCase().includes(q) ||
        d.email?.toLowerCase().includes(q) ||
        d.phone?.toLowerCase().includes(q) ||
        d.plate_number?.toLowerCase().includes(q) ||
        String(d.id).includes(q);
      const matchesStatus =
        statusFilter === "all" || (d.availability || "offline").toLowerCase() === statusFilter.toLowerCase();
      return matchesSearch && matchesStatus;
    });
  }, [drivers, search, statusFilter]);

  const filteredRides = useMemo(() => {
    const q = search.toLowerCase().trim();
    return rides.filter((r) => {
      const matchesSearch =
        !q ||
        r.rider_name?.toLowerCase().includes(q) ||
        r.driver_name?.toLowerCase().includes(q) ||
        r.pickup_location?.toLowerCase().includes(q) ||
        r.destination?.toLowerCase().includes(q) ||
        String(r.id).includes(q);
      const matchesStatus =
        statusFilter === "all" || (r.status || "").toLowerCase() === statusFilter.toLowerCase();
      return matchesSearch && matchesStatus;
    });
  }, [rides, search, statusFilter]);

  const filteredVehicles = useMemo(() => {
    const q = search.toLowerCase().trim();
    if (!q) return vehicles;
    return vehicles.filter(
      (v) =>
        v.driver_name?.toLowerCase().includes(q) ||
        v.plate_number?.toLowerCase().includes(q) ||
        v.vehicle_model?.toLowerCase().includes(q) ||
        v.vehicle_type?.toLowerCase().includes(q) ||
        String(v.id).includes(q)
    );
  }, [vehicles, search]);

  const filteredPayments = useMemo(() => {
    const q = search.toLowerCase().trim();
    if (!q) return payments;
    return payments.filter(
      (p) =>
        p.rider_name?.toLowerCase().includes(q) ||
        p.payment_method?.toLowerCase().includes(q) ||
        p.status?.toLowerCase().includes(q) ||
        String(p.ride_id).includes(q)
    );
  }, [payments, search]);

  // Total revenue calculation
  const totalRevenue = useMemo(() => {
    return payments
      .filter((p) => p.status === "paid")
      .reduce((acc, curr) => acc + Number(curr.amount || 0), 0);
  }, [payments]);

  // NAVIGATION MENU
  const navItems = [
    { name: "Dashboard", icon: LayoutDashboard, badge: null },
    {
      name: "Dispatch",
      icon: Radio,
      badge: pendingRides.length > 0 ? `${pendingRides.length} incoming` : null,
      highlight: pendingRides.length > 0,
    },
    { name: "Income", icon: DollarSign, badge: formatMoney(totalRevenue) },
    { name: "Riders", icon: Users, badge: riders.length },
    { name: "Drivers", icon: Car, badge: drivers.length },
    { name: "Vehicles", icon: Layers, badge: vehicles.length },
    { name: "Rides", icon: Route, badge: rides.length },
    { name: "Payments", icon: CreditCard, badge: payments.length },
    { name: "Ratings", icon: Star, badge: ratings.length },
    { name: "Notifications", icon: Bell, badge: notifications.filter((n) => !n.is_read).length },
    { name: "Account", icon: KeyRound, badge: token ? "Admin" : "Sign In" },
  ];

  // Admin pages are private: visitors must sign in before seeing the dashboard.
  if (!isAdminSession) {
    return (
      <main className="login-wrapper admin-login-page">
        <div className="login-backdrop-glow" />
        <section className="login-card admin-login-card" aria-labelledby="admin-login-title">
          <div className="brand-badge"><Car size={30} /></div>
          <h1 className="brand-title" id="admin-login-title">RideApp Admin</h1>
          <p className="brand-subtitle">Sign in to open the dispatch dashboard</p>

          {authError && (
            <div className="login-error-alert" role="alert">
              <AlertCircle size={16} />
              <span>{authError}</span>
            </div>
          )}

          <form className="login-form" onSubmit={handleLogin}>
            <div className="form-group">
              <label htmlFor="admin-login-email">Administrator email</label>
              <input
                id="admin-login-email"
                type="email"
                autoComplete="username"
                value={loginEmail}
                onChange={(e) => setLoginEmail(e.target.value)}
                placeholder="Enter your admin email"
                required
              />
            </div>
            <div className="form-group">
              <label htmlFor="admin-login-password">Password</label>
              <input
                id="admin-login-password"
                type="password"
                autoComplete="current-password"
                value={loginPassword}
                onChange={(e) => setLoginPassword(e.target.value)}
                placeholder="Enter your password"
                required
              />
            </div>
            <button type="submit" className="btn-primary full-width" disabled={loginLoading}>
              {loginLoading ? <><RefreshCw className="spin" size={18} /> Signing in…</> : "Sign In"}
            </button>
          </form>
          <p className="admin-login-note">Administrator access only. Contact your system administrator if you need an account.</p>
        </section>
      </main>
    );
  }

  return (
    <div className="app-layout">
      {/* SIDEBAR */}
      <aside className="app-sidebar">
        <div className="sidebar-brand">
          <div className="brand-icon-box">
            <Car size={24} color="#F8FAFC" />
          </div>
          <div>
            <h2 className="brand-name">RideApp</h2>
            <span className="brand-env">{token ? "ADMIN ACTIVE" : "GUEST PREVIEW"}</span>
          </div>
        </div>

        <div className="system-pill">
          <span className={`live-pulse ${backendOnline ? "online" : "offline"}`} />
          <span className="system-text">
            {backendOnline ? "FastAPI :3000 • MySQL" : "Backend Offline"}
          </span>
        </div>

        <nav className="sidebar-nav">
          <span className="nav-header">NAVIGATION MENU</span>
          {navItems.map((item) => {
            const Icon = item.icon;
            const isActive = activeTab === item.name;
            return (
              <button
                key={item.name}
                className={`nav-btn ${isActive ? "active" : ""}`}
                onClick={() => {
                  setActiveTab(item.name);
                  setSearch("");
                  setStatusFilter("all");
                }}
              >
                <Icon size={19} className="nav-btn-icon" />
                <span className="nav-btn-text">{item.name}</span>
                {item.badge !== null && (
                  <span className={`nav-badge ${isActive ? "highlight" : ""}`}>{item.badge}</span>
                )}
              </button>
            );
          })}
        </nav>

        <div className="sidebar-footer">
          {token ? (
            <div className="admin-profile-pill">
              <div className="profile-avatar">
                {(adminUser?.name || "A").charAt(0).toUpperCase()}
              </div>
              <div className="profile-info">
                <strong className="profile-name">{adminUser?.name || "Super Administrator"}</strong>
                <small className="profile-role">Admin Access</small>
              </div>
            </div>
          ) : (
            <button className="guest-login-bar" onClick={() => setActiveTab("Account")}>
              <LogIn size={15} /> Sign In to Admin
            </button>
          )}

          {token ? (
            <button className="btn-logout" onClick={handleLogout} title="Sign Out">
              <LogOut size={16} /> Sign Out
            </button>
          ) : null}
        </div>
      </aside>

      {/* MAIN VIEWPORT */}
      <div className="app-main">
        {/* TOP BAR */}
        <header className="topbar">
          <div className="topbar-title-section">
            <span className="breadcrumb">RIDE PLATFORM / {activeTab.toUpperCase()}</span>
            <h1 className="active-title">{activeTab}</h1>
          </div>

          <div className="topbar-actions">
            <button
              className={`btn-sync-toggle ${autoSync ? "active" : ""}`}
              onClick={() => setAutoSync(!autoSync)}
              title={autoSync ? "4-second Live Auto-Sync is Active (Click to pause)" : "Live Auto-Sync is Paused (Click to resume)"}
            >
              <span className={`sync-dot ${autoSync ? "pulse" : ""}`} />
              <span>{autoSync ? "Live 4s" : "Paused"}</span>
            </button>

            <button
              className={`btn-icon ${soundEnabled ? "sound-active" : "sound-muted"}`}
              onClick={toggleSound}
              title={soundEnabled ? "Dispatch Alert Chime: ON (Click to mute)" : "Dispatch Alert Chime: MUTED (Click to enable)"}
            >
              {soundEnabled ? <Volume2 size={18} color="#60A5FA" /> : <VolumeX size={18} color="#94A3B8" />}
            </button>

            <button
              className={`btn-icon ${refreshing ? "refreshing" : ""}`}
              onClick={handleManualRefresh}
              title="Refresh Data"
              disabled={refreshing || loading}
            >
              <RefreshCw size={18} className={refreshing ? "spin" : ""} />
            </button>

            {activeTab === "Riders" && (
              <button className="btn-primary" onClick={() => requireAdmin(() => setUserModal({ ...initialUser }))}>
                <Plus size={16} /> Add Rider
              </button>
            )}
            {activeTab === "Drivers" && (
              <button className="btn-primary" onClick={() => requireAdmin(() => setDriverModal({ ...initialDriver }))}>
                <Plus size={16} /> Add Driver
              </button>
            )}
            {activeTab === "Vehicles" && (
              <button className="btn-primary" onClick={() => requireAdmin(() => setVehicleModal({ ...initialVehicle }))}>
                <Plus size={16} /> Add Vehicle
              </button>
            )}

            <button
              className="btn-icon bell-btn"
              onClick={() => setActiveTab("Notifications")}
              title="View Notifications"
            >
              <Bell size={18} />
              {notifications.some((n) => !n.is_read) && <span className="bell-dot" />}
            </button>

            {!token ? (
              <button className="btn-primary topbar-signin-btn" onClick={() => setActiveTab("Account")}>
                <LogIn size={16} /> Sign In
              </button>
            ) : (
              <div className="topbar-user-badge">
                <UserCheck size={16} color="#34D399" />
                <span>Super Admin</span>
              </div>
            )}
          </div>
        </header>

        {/* LIVE INCOMING BOOKINGS STICKY ALERT BANNER */}
        {pendingRides.length > 0 && (
          <div className="dispatch-alert-banner">
            <div className="alert-content">
              <span className="live-ping-dot" />
              <Radio size={18} className="pulse-icon text-amber" />
              <div>
                <strong>Incoming Booking Alert:</strong> {pendingRides.length} ride request(s) awaiting dispatch / driver assignment!
              </div>
            </div>
            <div className="alert-actions">
              <button className="btn-alert-dispatch" onClick={() => setActiveTab("Dispatch")}>
                Open Dispatch Console ({pendingRides.length}) →
              </button>
            </div>
          </div>
        )}

        {/* CONNECTION BANNER */}
        {connectionNote && (
          <div className="notice-banner">
            <AlertCircle size={18} />
            <span>{connectionNote}</span>
            <button className="btn-retry" onClick={loadData}>Check Connection</button>
          </div>
        )}

        {/* GUEST BANNER */}
        {!token && activeTab !== "Account" && (
          <div className="guest-info-banner">
            <Shield size={16} />
            <span>
              You are exploring in <b>Preview Mode</b>. All features and metrics are visible. Visit the <b>Account</b> menu to sign in as Administrator.
            </span>
            <button className="btn-banner-action" onClick={() => setActiveTab("Account")}>
              Go to Account & Sign In →
            </button>
          </div>
        )}

        {/* CONTENT PANELS */}
        <div className="content-container">
          {/* DASHBOARD TAB */}
          {activeTab === "Dashboard" && (
            <DashboardView
              riders={riders}
              drivers={drivers}
              rides={rides}
              payments={payments}
              vehicles={vehicles}
              totalRevenue={totalRevenue}
              setActiveTab={setActiveTab}
              onInspectRide={(r) => setRideDetailsModal(r)}
              setStatusFilter={setStatusFilter}
            />
          )}

          {/* DISPATCH TAB */}
          {activeTab === "Dispatch" && (
            <DispatchView
              rides={rides}
              drivers={drivers}
              pendingRides={pendingRides}
              onDispatch={handleDispatchRide}
              onAutoDispatch={handleAutoDispatch}
              onCancel={handleCancelBooking}
              dispatchingRideId={dispatchingRideId}
              selectedDrivers={selectedDispatchDriver}
              setSelectedDrivers={setSelectedDispatchDriver}
              soundEnabled={soundEnabled}
              toggleSound={toggleSound}
              formatMoney={formatMoney}
              formatDate={formatDate}
            />
          )}

          {/* INCOME TAB */}
          {activeTab === "Income" && (
            <IncomeView
              totalRevenue={totalRevenue}
              commissionRate={commissionRate}
              setCommissionRate={setCommissionRate}
              baseFare={baseFare}
              setBaseFare={setBaseFare}
              perKmRate={perKmRate}
              setPerKmRate={setPerKmRate}
              drivers={drivers}
              rides={rides}
              payments={payments}
              onSettlePayout={handleSettlePayout}
              settledDrivers={settledDrivers}
            />
          )}

          {/* RIDERS TAB */}
          {activeTab === "Riders" && (
            <div className="view-card">
              <div className="view-header">
                <div>
                  <h2 className="view-heading">Registered Passengers</h2>
                  <p className="view-subheading">View, manage, and update passenger accounts and credentials.</p>
                </div>
                <div className="search-bar">
                  <Search size={16} className="search-icon" />
                  <input
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    placeholder="Search by name, email, phone..."
                  />
                  {search && <button className="clear-btn" onClick={() => setSearch("")}>×</button>}
                </div>
              </div>

              <div className="table-container">
                <table className="custom-table">
                  <thead>
                    <tr>
                      <th style={{ width: "80px" }}>ID</th>
                      <th>RIDER NAME</th>
                      <th>EMAIL ADDRESS</th>
                      <th>PHONE</th>
                      <th>STATUS</th>
                      <th style={{ width: "140px", textAlign: "right" }}>ACTIONS</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredRiders.map((user) => (
                      <tr key={user.id}>
                        <td><span className="mono-id">#{user.id}</span></td>
                        <td>
                          <div className="user-cell">
                            <div className="cell-avatar">{(user.name || "R").charAt(0).toUpperCase()}</div>
                            <strong>{user.name}</strong>
                          </div>
                        </td>
                        <td>{user.email}</td>
                        <td>{user.phone || "—"}</td>
                        <td><span className="badge-pill badge-rider">Rider</span></td>
                        <td style={{ textAlign: "right" }}>
                          <div className="row-actions">
                            <button
                              className="action-btn edit"
                              onClick={() => requireAdmin(() => setUserModal({ ...user, password: "" }))}
                              title="Edit User"
                            >
                              <Edit2 size={15} />
                            </button>
                            <button
                              className="action-btn delete"
                              onClick={() => requireAdmin(() => deleteRecord(`/api/users/${user.id}`, "rider"))}
                              title="Delete User"
                            >
                              <Trash2 size={15} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                    {!filteredRiders.length && (
                      <tr>
                        <td colSpan="6" className="empty-state">
                          No passenger accounts found matching your query.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* DRIVERS TAB */}
          {activeTab === "Drivers" && (
            <div className="view-card">
              <div className="view-header">
                <div>
                  <h2 className="view-heading">Fleet Drivers</h2>
                  <p className="view-subheading">Monitor real-time driver availability, linked vehicles, and ratings.</p>
                </div>
                <div className="filter-group">
                  <div className="filter-chips">
                    {["all", "available", "offline", "on_ride"].map((status) => (
                      <button
                        key={status}
                        className={`filter-chip ${statusFilter === status ? "selected" : ""}`}
                        onClick={() => setStatusFilter(status)}
                      >
                        {status === "all" ? "All Drivers" : status === "available" ? "Online" : status === "on_ride" ? "On Ride" : "Offline"}
                      </button>
                    ))}
                  </div>
                  <div className="search-bar">
                    <Search size={16} className="search-icon" />
                    <input
                      value={search}
                      onChange={(e) => setSearch(e.target.value)}
                      placeholder="Search driver name, phone, plate..."
                    />
                  </div>
                </div>
              </div>

              <div className="table-container">
                <table className="custom-table">
                  <thead>
                    <tr>
                      <th style={{ width: "80px" }}>ID</th>
                      <th>DRIVER</th>
                      <th>CONTACT</th>
                      <th>AVAILABILITY</th>
                      <th>ASSIGNED VEHICLE</th>
                      <th style={{ width: "140px", textAlign: "right" }}>ACTIONS</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredDrivers.map((driver) => (
                      <tr key={driver.id}>
                        <td><span className="mono-id">#{driver.id}</span></td>
                        <td>
                          <div className="user-cell">
                            <div className="cell-avatar driver-avatar">
                              {(driver.name || "D").charAt(0).toUpperCase()}
                            </div>
                            <div>
                              <strong>{driver.name}</strong>
                              <small className="cell-sub">{driver.email}</small>
                            </div>
                          </div>
                        </td>
                        <td>{driver.phone || "—"}</td>
                        <td>
                          <select
                            className={`status-selector ${driver.availability || "offline"}`}
                            value={driver.availability || "offline"}
                            onChange={(e) => quickChangeDriverStatus(driver, e.target.value)}
                          >
                            <option value="available">● Online (Available)</option>
                            <option value="offline">○ Offline</option>
                            <option value="on_ride">▲ On Ride</option>
                          </select>
                        </td>
                        <td>
                          {driver.vehicle_id ? (
                            <span className="vehicle-pill">
                              <Car size={13} /> {driver.vehicle_model || driver.vehicle_type} • <b>{driver.plate_number}</b>
                            </span>
                          ) : (
                            <span className="text-muted-italics">No vehicle assigned</span>
                          )}
                        </td>
                        <td style={{ textAlign: "right" }}>
                          <div className="row-actions">
                            <button
                              className="action-btn edit"
                              onClick={() => requireAdmin(() => setDriverModal({ ...driver, password: "" }))}
                              title="Edit Driver"
                            >
                              <Edit2 size={15} />
                            </button>
                            <button
                              className="action-btn delete"
                              onClick={() => requireAdmin(() => deleteRecord(`/api/drivers/${driver.id}`, "driver"))}
                              title="Delete Driver"
                            >
                              <Trash2 size={15} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                    {!filteredDrivers.length && (
                      <tr>
                        <td colSpan="6" className="empty-state">
                          No drivers found matching current filters.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* VEHICLES TAB */}
          {activeTab === "Vehicles" && (
            <div className="view-card">
              <div className="view-header">
                <div>
                  <h2 className="view-heading">Fleet Vehicles</h2>
                  <p className="view-subheading">Registered vehicle assets assigned to platform drivers.</p>
                </div>
                <div className="search-bar">
                  <Search size={16} className="search-icon" />
                  <input
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    placeholder="Search by model, plate, driver..."
                  />
                </div>
              </div>

              <div className="table-container">
                <table className="custom-table">
                  <thead>
                    <tr>
                      <th style={{ width: "80px" }}>ID</th>
                      <th>VEHICLE TYPE</th>
                      <th>MODEL & MAKE</th>
                      <th>LICENSE PLATE</th>
                      <th>ASSIGNED DRIVER</th>
                      <th style={{ width: "140px", textAlign: "right" }}>ACTIONS</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredVehicles.map((vehicle) => (
                      <tr key={vehicle.id}>
                        <td><span className="mono-id">#{vehicle.id}</span></td>
                        <td>
                          <span className="badge-pill badge-vehicle">{vehicle.vehicle_type}</span>
                        </td>
                        <td><strong>{vehicle.vehicle_model || "—"}</strong></td>
                        <td>
                          <span className="plate-badge">{vehicle.plate_number}</span>
                        </td>
                        <td>
                          {vehicle.driver_name ? (
                            <span>🚗 {vehicle.driver_name} (ID #{vehicle.driver_id})</span>
                          ) : (
                            <span className="text-muted-italics">Unassigned</span>
                          )}
                        </td>
                        <td style={{ textAlign: "right" }}>
                          <div className="row-actions">
                            <button
                              className="action-btn edit"
                              onClick={() => requireAdmin(() => setVehicleModal({ ...vehicle }))}
                              title="Edit Vehicle"
                            >
                              <Edit2 size={15} />
                            </button>
                            <button
                              className="action-btn delete"
                              onClick={() => requireAdmin(() => deleteRecord(`/api/vehicles/${vehicle.id}`, "vehicle"))}
                              title="Delete Vehicle"
                            >
                              <Trash2 size={15} />
                            </button>
                          </div>
                        </td>
                      </tr>
                    ))}
                    {!filteredVehicles.length && (
                      <tr>
                        <td colSpan="6" className="empty-state">
                          No vehicles registered yet. Click &quot;+ Add Vehicle&quot; to assign one.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* RIDES TAB */}
          {activeTab === "Rides" && (
            <div className="view-card">
              <div className="view-header">
                <div>
                  <h2 className="view-heading">Trip Operations</h2>
                  <p className="view-subheading">Track live bookings, matched drivers, pickup routes, and fares.</p>
                </div>
                <div className="filter-group">
                  <div className="filter-chips">
                    {["all", "requested", "accepted", "ongoing", "completed", "cancelled"].map((status) => (
                      <button
                        key={status}
                        className={`filter-chip ${statusFilter === status ? "selected" : ""}`}
                        onClick={() => setStatusFilter(status)}
                      >
                        {status.charAt(0).toUpperCase() + status.slice(1)}
                      </button>
                    ))}
                  </div>
                  <div className="search-bar">
                    <Search size={16} className="search-icon" />
                    <input
                      value={search}
                      onChange={(e) => setSearch(e.target.value)}
                      placeholder="Search rider, driver, route..."
                    />
                  </div>
                </div>
              </div>

              <div className="table-container">
                <table className="custom-table">
                  <thead>
                    <tr>
                      <th style={{ width: "70px" }}>ID</th>
                      <th>PASSENGER</th>
                      <th>DRIVER</th>
                      <th>PICKUP & DESTINATION</th>
                      <th>TYPE</th>
                      <th>FARE</th>
                      <th>STATUS</th>
                      <th style={{ width: "100px", textAlign: "right" }}>INSPECT</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredRides.map((ride) => (
                      <tr key={ride.id}>
                        <td><span className="mono-id">#{ride.id}</span></td>
                        <td><strong>{ride.rider_name || `Rider #${ride.rider_id}`}</strong></td>
                        <td>
                          {ride.driver_name ? (
                            <span>🚗 {ride.driver_name}</span>
                          ) : (
                            <span className="text-muted-italics">Unassigned</span>
                          )}
                        </td>
                        <td>
                          <div className="route-cell">
                            <span className="route-from" title={ride.pickup_location}>
                              <span className="dot pickup" /> {ride.pickup_location || "—"}
                            </span>
                            <span className="route-to" title={ride.destination}>
                              <span className="dot dest" /> {ride.destination || "Flexible / Direct Ride"}
                            </span>
                          </div>
                        </td>
                        <td><span className="badge-pill badge-neutral">{ride.ride_type || "Car"}</span></td>
                        <td>
                          <strong className="fare-highlight">
                            {ride.fare != null ? formatMoney(ride.fare, ride.currency) : ride.estimated_fare != null ? `~${formatMoney(ride.estimated_fare, ride.currency)}` : "Pending"}
                          </strong>
                        </td>
                        <td><StatusBadge status={ride.status} /></td>
                        <td style={{ textAlign: "right" }}>
                          <button
                            className="btn-view"
                            onClick={() => setRideDetailsModal(ride)}
                            title="Inspect Ride Details"
                          >
                            <Eye size={15} /> View
                          </button>
                        </td>
                      </tr>
                    ))}
                    {!filteredRides.length && (
                      <tr>
                        <td colSpan="8" className="empty-state">
                          No rides found matching the selected status or query.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* PAYMENTS TAB */}
          {activeTab === "Payments" && (
            <div className="view-card">
              <div className="view-header">
                <div>
                  <h2 className="view-heading">Settlement & Payments</h2>
                  <p className="view-subheading">Completed cash transactions and Bakong KHQR digital settlements.</p>
                </div>
                <div className="search-bar">
                  <Search size={16} className="search-icon" />
                  <input
                    value={search}
                    onChange={(e) => setSearch(e.target.value)}
                    placeholder="Search ride ID, rider, method..."
                  />
                </div>
              </div>

              <div className="table-container">
                <table className="custom-table">
                  <thead>
                    <tr>
                      <th style={{ width: "80px" }}>ID</th>
                      <th>RIDE #</th>
                      <th>PASSENGER</th>
                      <th>AMOUNT</th>
                      <th>PAYMENT METHOD</th>
                      <th>SETTLEMENT STATUS</th>
                      <th>TIMESTAMP</th>
                    </tr>
                  </thead>
                  <tbody>
                    {filteredPayments.map((p) => (
                      <tr key={p.id}>
                        <td><span className="mono-id">#{p.id}</span></td>
                        <td><span className="mono-id">#{p.ride_id}</span></td>
                        <td><strong>{p.rider_name || `Rider #${p.rider_id || "-"}`}</strong></td>
                        <td>
                          <span className="amount-pill">{formatMoney(p.amount, p.currency)}</span>
                        </td>
                        <td>
                          <span className={`method-badge ${p.payment_method?.toLowerCase()}`}>
                            {p.payment_method?.includes("bakong") || p.payment_method?.includes("khqr") ? "⚡ Bakong KHQR" : "💵 Cash Payment"}
                          </span>
                        </td>
                        <td><StatusBadge status={p.status} /></td>
                        <td className="text-secondary-cell">{formatDate(p.created_at)}</td>
                      </tr>
                    ))}
                    {!filteredPayments.length && (
                      <tr>
                        <td colSpan="7" className="empty-state">
                          No payments recorded yet.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* RATINGS TAB */}
          {activeTab === "Ratings" && (
            <div className="view-card">
              <div className="view-header">
                <div>
                  <h2 className="view-heading">Ratings & Rider Feedback</h2>
                  <p className="view-subheading">Driver performance scores, comments, and customer satisfaction.</p>
                </div>
              </div>

              <div className="table-container">
                <table className="custom-table">
                  <thead>
                    <tr>
                      <th style={{ width: "80px" }}>ID</th>
                      <th>RIDE #</th>
                      <th>RATER (PASSENGER)</th>
                      <th>RATEE (DRIVER)</th>
                      <th>RATING SCORE</th>
                      <th>FEEDBACK / COMMENT</th>
                      <th>SUBMITTED AT</th>
                    </tr>
                  </thead>
                  <tbody>
                    {ratings.map((rate) => (
                      <tr key={rate.id}>
                        <td><span className="mono-id">#{rate.id}</span></td>
                        <td><span className="mono-id">#{rate.ride_id}</span></td>
                        <td><strong>{rate.rater_name || `User #${rate.rater_id}`}</strong></td>
                        <td>🚗 {rate.ratee_name || `Driver #${rate.ratee_id}`}</td>
                        <td>
                          <div className="stars-row">
                            {[1, 2, 3, 4, 5].map((s) => (
                              <Star
                                key={s}
                                size={15}
                                fill={s <= (rate.score || 0) ? "#0B3ACD" : "none"}
                                color={s <= (rate.score || 0) ? "#0B3ACD" : "#2E3C66"}
                              />
                            ))}
                            <span className="star-score">({rate.score}/5)</span>
                          </div>
                        </td>
                        <td>
                          <span className="feedback-text">{rate.comment || "— No written comment —"}</span>
                        </td>
                        <td className="text-secondary-cell">{formatDate(rate.created_at)}</td>
                      </tr>
                    ))}
                    {!ratings.length && (
                      <tr>
                        <td colSpan="7" className="empty-state">
                          No passenger ratings submitted yet.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* NOTIFICATIONS TAB */}
          {activeTab === "Notifications" && (
            <div className="view-card">
              <div className="view-header">
                <div>
                  <h2 className="view-heading">System Notifications</h2>
                  <p className="view-subheading">Live system alerts, dispatch notices, and transaction confirmations.</p>
                </div>
              </div>

              <div className="table-container">
                <table className="custom-table">
                  <thead>
                    <tr>
                      <th style={{ width: "80px" }}>ID</th>
                      <th>RECIPIENT</th>
                      <th>TITLE</th>
                      <th>MESSAGE</th>
                      <th>TYPE</th>
                      <th>STATUS</th>
                      <th>DATE</th>
                    </tr>
                  </thead>
                  <tbody>
                    {notifications.map((n) => (
                      <tr key={n.id}>
                        <td><span className="mono-id">#{n.id}</span></td>
                        <td>{n.user_id ? `User #${n.user_id}` : "Broadcast System"}</td>
                        <td><strong>{n.title}</strong></td>
                        <td><span className="notif-msg">{n.message}</span></td>
                        <td><span className="badge-pill badge-neutral">{n.type}</span></td>
                        <td>
                          <span className={`status-dot-pill ${n.is_read ? "read" : "unread"}`}>
                            {n.is_read ? "Read" : "New"}
                          </span>
                        </td>
                        <td className="text-secondary-cell">{formatDate(n.created_at)}</td>
                      </tr>
                    ))}
                    {!notifications.length && (
                      <tr>
                        <td colSpan="7" className="empty-state">
                          No notifications stored.
                        </td>
                      </tr>
                    )}
                  </tbody>
                </table>
              </div>
            </div>
          )}

          {/* ACCOUNT & PROFILE TAB (Contains the login/register center!) */}
          {activeTab === "Account" && (
            <div className="account-view-container">
              {token ? (
                /* LOGGED IN PROFILE CARD */
                <div className="view-card account-card">
                  <div className="account-hero">
                    <div className="account-avatar-large">
                      {(adminUser?.name || "A").charAt(0).toUpperCase()}
                    </div>
                    <div>
                      <h2>{adminUser?.name || "Super Administrator"}</h2>
                      <p className="account-email">{adminUser?.email || "admin@rideapp.com"}</p>
                      <span className="badge-pill badge-rider">Role: Administrator</span>
                    </div>
                  </div>

                  <div className="account-stats-row">
                    <div className="acc-stat-box">
                      <span>Access Level</span>
                      <strong>{adminUser?.role === "admin" ? "Full Administrator" : adminUser?.role === "driver" ? "Driver Access" : "Passenger Access"}</strong>
                    </div>
                    <div className="acc-stat-box">
                      <span>Service Backend</span>
                      <strong>FastAPI (Port 3000)</strong>
                    </div>
                    <div className="acc-stat-box">
                      <span>Database Engine</span>
                      <strong>MySQL 8.0 (ride_app)</strong>
                    </div>
                  </div>

                  {adminUser?.role !== "admin" && (
                    <div className="role-note-card">
                      <Shield size={16} />
                      <span>Signed in with read access. Switch to an administrator account to add, edit, or delete records.</span>
                    </div>
                  )}

                  <div className="account-actions-box">
                    <button className="btn-secondary" onClick={handleManualRefresh}>
                      <RefreshCw size={15} /> Refresh Live Database Records
                    </button>
                    <button className="btn-logout-large" onClick={handleLogout}>
                      <LogOut size={16} /> Sign Out / Switch Account
                    </button>
                  </div>
                </div>
              ) : (
                /* GUEST SIGN IN / CREATE ACCOUNT CARD */
                <div className="view-card auth-center-card">
                  <div className="auth-tab-switch">
                    <button
                      className={`auth-tab-btn ${authMode === "login" ? "active" : ""}`}
                      onClick={() => { setAuthMode("login"); setAuthError(""); setAuthSuccess(""); }}
                    >
                      <LogIn size={16} /> Sign In
                    </button>
                    <button
                      className={`auth-tab-btn ${authMode === "register" ? "active" : ""}`}
                      onClick={() => { setAuthMode("register"); setAuthError(""); setAuthSuccess(""); }}
                    >
                      <UserCheck size={16} /> Create Account
                    </button>
                  </div>

                  {authError && (
                    <div className="login-error-alert">
                      <AlertCircle size={16} />
                      <span>{authError}</span>
                    </div>
                  )}

                  {authSuccess && (
                    <div className="login-success-alert">
                      <CheckCircle2 size={16} />
                      <span>{authSuccess}</span>
                    </div>
                  )}

                  {authMode === "login" ? (
                    <form className="login-form" onSubmit={handleLogin}>
                      <div className="form-group">
                        <label>Account Email</label>
                        <input
                          type="email"
                          value={loginEmail}
                          onChange={(e) => setLoginEmail(e.target.value)}
                          placeholder="e.g. admin@rideapp.com or driver.sokha@rideapp.com"
                          required
                        />
                      </div>

                      <div className="form-group">
                        <label>Password</label>
                        <input
                          type="password"
                          value={loginPassword}
                          onChange={(e) => setLoginPassword(e.target.value)}
                          placeholder="••••••••••••"
                          required
                        />
                      </div>

                      <button type="submit" className="btn-primary full-width" disabled={loginLoading}>
                        {loginLoading ? (
                          <>
                            <RefreshCw className="spin" size={18} /> Authenticating...
                          </>
                        ) : (
                          "Sign In to RideApp"
                        )}
                      </button>

                      <div className="login-demo-helper">
                        <span>One-Click Test Accounts:</span>
                        <div className="demo-chips-grid">
                          <button type="button" className="demo-chip" onClick={() => fillDemo("admin@rideapp.com", "admin123456")}>
                            🛡️ Admin (admin@rideapp.com)
                          </button>
                          <button type="button" className="demo-chip" onClick={() => fillDemo("driver.sokha@rideapp.com", "driver123456")}>
                            🚖 Driver (driver.sokha@rideapp.com)
                          </button>
                          <button type="button" className="demo-chip" onClick={() => fillDemo("rider.chenda@rideapp.com", "rider123456")}>
                            👤 Rider (rider.chenda@rideapp.com)
                          </button>
                        </div>
                      </div>
                    </form>
                  ) : (
                    <form className="login-form" onSubmit={handleRegisterAdmin}>
                      <div className="form-group">
                        <label>Full Name</label>
                        <input
                          type="text"
                          value={regName}
                          onChange={(e) => setRegName(e.target.value)}
                          placeholder="Admin Name"
                          required
                        />
                      </div>

                      <div className="form-group">
                        <label>Email Address</label>
                        <input
                          type="email"
                          value={regEmail}
                          onChange={(e) => setRegEmail(e.target.value)}
                          placeholder="newadmin@rideapp.com"
                          required
                        />
                      </div>

                      <div className="form-group">
                        <label>Phone Number (Optional)</label>
                        <input
                          type="text"
                          value={regPhone}
                          onChange={(e) => setRegPhone(e.target.value)}
                          placeholder="012 345 678"
                        />
                      </div>

                      <div className="form-group">
                        <label>Password (Min 8 characters)</label>
                        <input
                          type="password"
                          value={regPassword}
                          onChange={(e) => setRegPassword(e.target.value)}
                          placeholder="••••••••••••"
                          required
                        />
                      </div>

                      <button type="submit" className="btn-primary full-width" disabled={loginLoading}>
                        {loginLoading ? (
                          <>
                            <RefreshCw className="spin" size={18} /> Creating Account...
                          </>
                        ) : (
                          "Create Administrator Account"
                        )}
                      </button>
                    </form>
                  )}
                </div>
              )}
            </div>
          )}
        </div>
      </div>

      {/* AUTH REQUIRED PROMPT MODAL */}
      {authPromptModal && (
        <Modal title="Administrator Sign In Required" onClose={() => setAuthPromptModal(false)}>
          <div className="auth-prompt-content">
            <p>You need to sign in with an Administrator account to add, edit, or delete records.</p>
            <div className="modal-footer">
              <button className="btn-secondary" onClick={() => setAuthPromptModal(false)}>
                Stay in Preview
              </button>
              <button
                className="btn-primary"
                onClick={() => {
                  setAuthPromptModal(false);
                  setActiveTab("Account");
                }}
              >
                Go to Sign In Page
              </button>
            </div>
          </div>
        </Modal>
      )}

      {/* USER MODAL */}
      {userModal && (
        <Modal title={userModal.id ? `Edit Rider #${userModal.id}` : "Register New Rider"} onClose={() => setUserModal(null)}>
          <UserForm
            initial={userModal}
            onCancel={() => setUserModal(null)}
            onSubmit={(data) => saveUser(data)}
          />
        </Modal>
      )}

      {/* DRIVER MODAL */}
      {driverModal && (
        <Modal title={driverModal.id ? `Edit Driver #${driverModal.id}` : "Register New Driver"} onClose={() => setDriverModal(null)}>
          <DriverForm
            initial={driverModal}
            onCancel={() => setDriverModal(null)}
            onSubmit={(data) => saveDriver(data)}
          />
        </Modal>
      )}

      {/* VEHICLE MODAL */}
      {vehicleModal && (
        <Modal title={vehicleModal.id ? `Edit Vehicle #${vehicleModal.id}` : "Register Vehicle"} onClose={() => setVehicleModal(null)}>
          <VehicleForm
            initial={vehicleModal}
            drivers={drivers}
            onCancel={() => setVehicleModal(null)}
            onSubmit={(data) => saveVehicle(data)}
          />
        </Modal>
      )}

      {/* RIDE INSPECTOR MODAL */}
      {rideDetailsModal && (
        <Modal title={`Trip #${rideDetailsModal.id} Inspector`} onClose={() => setRideDetailsModal(null)}>
          <div className="ride-inspector">
            <div className="inspector-grid">
              <div className="inspector-box">
                <span className="box-label">PASSENGER</span>
                <strong className="box-val">{rideDetailsModal.rider_name || `ID #${rideDetailsModal.rider_id}`}</strong>
              </div>
              <div className="inspector-box">
                <span className="box-label">ASSIGNED DRIVER</span>
                <strong className="box-val">{rideDetailsModal.driver_name || "Unassigned"}</strong>
              </div>
              <div className="inspector-box">
                <span className="box-label">SERVICE CLASS</span>
                <strong className="box-val">{rideDetailsModal.ride_type || "Car"}</strong>
              </div>
              <div className="inspector-box">
                <span className="box-label">STATUS</span>
                <StatusBadge status={rideDetailsModal.status} />
              </div>
            </div>

            <div className="route-inspector-card">
              <div className="route-step">
                <MapPin size={18} className="icon-pickup" />
                <div>
                  <label>Pickup Location</label>
                  <p>{rideDetailsModal.pickup_location || "—"}</p>
                  {rideDetailsModal.pickup_lat && (
                    <small className="coords">
                      GPS: {rideDetailsModal.pickup_lat}, {rideDetailsModal.pickup_lng}
                    </small>
                  )}
                </div>
              </div>

              <div className="route-step">
                <MapPin size={18} className="icon-dest" />
                <div>
                  <label>Destination</label>
                  <p>{rideDetailsModal.destination || "Direct Ride (Destination not specified)"}</p>
                  {rideDetailsModal.destination_lat && (
                    <small className="coords">
                      GPS: {rideDetailsModal.destination_lat}, {rideDetailsModal.destination_lng}
                    </small>
                  )}
                </div>
              </div>
            </div>

            <div className="financial-inspector-card">
              <div className="fin-row">
                <span>Calculated Distance:</span>
                <strong>{rideDetailsModal.distance_km != null ? `${Number(rideDetailsModal.distance_km).toFixed(2)} km` : "N/A"}</strong>
              </div>
              <div className="fin-row">
                <span>Estimated Fare:</span>
                <strong>{rideDetailsModal.estimated_fare != null ? formatMoney(rideDetailsModal.estimated_fare, rideDetailsModal.currency) : "—"}</strong>
              </div>
              <div className="fin-row total">
                <span>Final Settle Fare:</span>
                <strong className="final-price">
                  {rideDetailsModal.fare != null ? formatMoney(rideDetailsModal.fare, rideDetailsModal.currency) : "Pending Trip Finish"}
                </strong>
              </div>
            </div>

            <div className="admin-trip-controls">
              <h4>Admin Trip Dispatch & Lifecycle Override:</h4>
              <div className="admin-buttons-row">
                <button
                  type="button"
                  className="btn-action-small btn-primary-small"
                  disabled={adminStatusUpdating}
                  onClick={() => handleAdminUpdateRideStatus(rideDetailsModal.id, "accepted")}
                >
                  Set: Going to Pickup
                </button>
                <button
                  type="button"
                  className="btn-action-small btn-outline"
                  disabled={adminStatusUpdating}
                  onClick={() => handleAdminUpdateRideStatus(rideDetailsModal.id, "arrived")}
                >
                  Set: Arrived at Pickup
                </button>
                <button
                  type="button"
                  className="btn-action-small btn-primary-small"
                  style={{ backgroundColor: "#16A34A", borderColor: "#16A34A" }}
                  disabled={adminStatusUpdating}
                  onClick={() => handleAdminUpdateRideStatus(rideDetailsModal.id, "ongoing")}
                >
                  Set: Start Trip
                </button>
                <button
                  type="button"
                  className="btn-action-small btn-primary-small"
                  style={{ backgroundColor: "#264399", borderColor: "#264399" }}
                  disabled={adminStatusUpdating}
                  onClick={() => handleAdminUpdateRideStatus(rideDetailsModal.id, "completed")}
                >
                  Set: Complete Trip
                </button>
                <button
                  type="button"
                  className="btn-action-small btn-outline"
                  style={{ color: "#EF4444", borderColor: "#EF4444" }}
                  disabled={adminStatusUpdating}
                  onClick={() => handleAdminUpdateRideStatus(rideDetailsModal.id, "cancelled")}
                >
                  Cancel Trip
                </button>
              </div>
            </div>

            <div className="modal-footer">
              <button className="btn-secondary" onClick={() => setRideDetailsModal(null)}>
                Close Inspector
              </button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}


// INCOME & FINANCIAL CONTROL VIEW COMPONENT
function IncomeView({
  totalRevenue,
  commissionRate,
  setCommissionRate,
  baseFare,
  setBaseFare,
  perKmRate,
  setPerKmRate,
  drivers,
  rides,
  payments,
  onSettlePayout,
  settledDrivers,
}) {
  const [savedNote, setSavedNote] = useState("");
  const [driverSearch, setDriverSearch] = useState("");

  const completedRides = rides.filter((r) => r.status === "completed");
  const grossRev = totalRevenue || completedRides.reduce((acc, r) => acc + Number(r.fare || 0), 0);
  const platformIncome = grossRev * (commissionRate / 100);
  const driverPayouts = grossRev - platformIncome;

  const cashPayments = payments.filter((p) => p.payment_method?.toLowerCase().includes("cash"));
  const digitalPayments = payments.filter((p) => !p.payment_method?.toLowerCase().includes("cash"));
  const cashAmount = cashPayments.reduce((acc, p) => acc + Number(p.amount || 0), 0);
  const digitalAmount = digitalPayments.reduce((acc, p) => acc + Number(p.amount || 0), 0);

  const driverEarnings = useMemo(() => {
    return drivers.map((driver) => {
      const driverTrips = completedRides.filter((r) => r.driver_id === driver.id || r.driver_name === driver.name);
      const gross = driverTrips.reduce((acc, r) => acc + Number(r.fare || 0), 0);
      const fee = gross * (commissionRate / 100);
      const net = gross - fee;
      const isSettled = settledDrivers[driver.id] || gross === 0;

      return {
        ...driver,
        completedTrips: driverTrips.length,
        gross,
        fee,
        net,
        isSettled,
      };
    });
  }, [drivers, completedRides, commissionRate, settledDrivers]);

  const filteredDriverEarnings = driverEarnings.filter(
    (d) =>
      d.name?.toLowerCase().includes(driverSearch.toLowerCase()) ||
      d.phone?.toLowerCase().includes(driverSearch.toLowerCase())
  );

  const savePricingRules = () => {
    setSavedNote("Pricing & Commission Rules Saved Successfully!");
    setTimeout(() => setSavedNote(""), 3500);
  };

  return (
    <div className="view-card">
      <div className="hero-banner" style={{ background: "linear-gradient(135deg, #0B3ACD 0%, #264399 50%, #212633 100%)" }}>
        <div className="hero-text">
          <span className="hero-tag" style={{ background: "rgba(255,255,255,0.18)", color: "#fff" }}>
            FINANCIAL & REVENUE CONTROL CENTER
          </span>
          <h2>Platform Income, Driver Payouts & Commission</h2>
          <p>
            Control platform commission margins, audit cash vs Bakong KHQR digital collections, and oversee driver settlements.
          </p>
        </div>
        <div className="hero-stats-quick">
          <div className="quick-kpi">
            <span>PLATFORM SHARE</span>
            <strong>{commissionRate}% Commission</strong>
          </div>
          <div className="quick-kpi">
            <span>NET COMMISSION</span>
            <strong>{formatMoney(platformIncome)}</strong>
          </div>
        </div>
      </div>

      <div className="kpi-grid" style={{ marginTop: "18px" }}>
        <div className="kpi-card">
          <div className="kpi-header">
            <span>GROSS PLATFORM VOLUME</span>
            <DollarSign className="kpi-icon" size={20} />
          </div>
          <strong className="kpi-val">{formatMoney(grossRev)}</strong>
          <small className="kpi-note">{completedRides.length} completed trips</small>
        </div>

        <div className="kpi-card" style={{ borderColor: "#0B3ACD" }}>
          <div className="kpi-header">
            <span style={{ color: "#60A5FA" }}>PLATFORM NET INCOME</span>
            <TrendingUp className="kpi-icon" size={20} style={{ color: "#60A5FA" }} />
          </div>
          <strong className="kpi-val" style={{ color: "#60A5FA" }}>{formatMoney(platformIncome)}</strong>
          <small className="kpi-note">{commissionRate}% platform retention</small>
        </div>

        <div className="kpi-card">
          <div className="kpi-header">
            <span>DRIVER PAYOUTS SHARE</span>
            <Car className="kpi-icon" size={20} />
          </div>
          <strong className="kpi-val">{formatMoney(driverPayouts)}</strong>
          <small className="kpi-note highlight-green">{(100 - commissionRate)}% net driver earnings</small>
        </div>

        <div className="kpi-card">
          <div className="kpi-header">
            <span>BAKONG KHQR DIGITAL</span>
            <CreditCard className="kpi-icon" size={20} />
          </div>
          <strong className="kpi-val">{formatMoney(digitalAmount)}</strong>
          <small className="kpi-note">{digitalPayments.length} digital transactions</small>
        </div>

        <div className="kpi-card">
          <div className="kpi-header">
            <span>CASH AT HAND</span>
            <CreditCard className="kpi-icon" size={20} />
          </div>
          <strong className="kpi-val">{formatMoney(cashAmount)}</strong>
          <small className="kpi-note">{cashPayments.length} cash collections</small>
        </div>
      </div>

      <div className="income-control-panel">
        <div className="panel-header">
          <div>
            <h3>Platform Commission & Pricing Rules</h3>
            <p>Adjust system commission rate and standard dispatch fares</p>
          </div>
          {savedNote && <span className="save-badge">{savedNote}</span>}
        </div>

        <div className="pricing-grid">
          <div className="control-box">
            <label>Platform Commission Rate (%):</label>
            <div className="slider-row">
              <input
                type="range"
                min="5"
                max="35"
                step="1"
                value={commissionRate}
                onChange={(e) => setCommissionRate(Number(e.target.value))}
                className="custom-range"
              />
              <span className="rate-bubble">{commissionRate}%</span>
            </div>
            <div className="preset-buttons">
              {[10, 15, 20, 25].map((rate) => (
                <button
                  key={rate}
                  type="button"
                  className={`preset-btn ${commissionRate === rate ? "active" : ""}`}
                  onClick={() => setCommissionRate(rate)}
                >
                  {rate}%
                </button>
              ))}
            </div>
          </div>

          <div className="control-box">
            <label>Standard Base Fare (USD):</label>
            <div className="input-with-symbol">
              <span>$</span>
              <input
                type="number"
                step="0.25"
                min="0.5"
                max="10"
                value={baseFare}
                onChange={(e) => setBaseFare(Number(e.target.value))}
              />
            </div>
          </div>

          <div className="control-box">
            <label>Per Kilometer Rate (USD/km):</label>
            <div className="input-with-symbol">
              <span>$</span>
              <input
                type="number"
                step="0.05"
                min="0.2"
                max="5"
                value={perKmRate}
                onChange={(e) => setPerKmRate(Number(e.target.value))}
              />
            </div>
          </div>

          <div className="control-box action-box">
            <label>&nbsp;</label>
            <button className="btn-primary" onClick={savePricingRules}>
              <CheckCircle2 size={16} /> Save Pricing Rules
            </button>
          </div>
        </div>
      </div>

      <div className="ledger-section">
        <div className="view-header" style={{ marginTop: "24px" }}>
          <div>
            <h3 className="view-heading">Driver Earnings & Payout Settlement</h3>
            <p className="view-subheading">Track gross revenue, platform deduction, and settle driver disbursements.</p>
          </div>
          <div className="search-bar">
            <Search size={16} className="search-icon" />
            <input
              value={driverSearch}
              onChange={(e) => setDriverSearch(e.target.value)}
              placeholder="Search driver name or phone..."
            />
          </div>
        </div>

        <div className="table-container">
          <table className="custom-table">
            <thead>
              <tr>
                <th>DRIVER</th>
                <th>PHONE</th>
                <th>COMPLETED TRIPS</th>
                <th>GROSS GENERATED</th>
                <th>PLATFORM COMMISSION ({commissionRate}%)</th>
                <th>NET DRIVER PAYOUT</th>
                <th>SETTLEMENT STATUS</th>
                <th>ACTION</th>
              </tr>
            </thead>
            <tbody>
              {filteredDriverEarnings.map((d) => (
                <tr key={d.id}>
                  <td><strong>{d.name}</strong></td>
                  <td className="text-secondary-cell">{d.phone || "—"}</td>
                  <td>
                    <span className="badge-pill">{d.completedTrips} trips</span>
                  </td>
                  <td><strong>{formatMoney(d.gross)}</strong></td>
                  <td style={{ color: "#F87171" }}>
                    -{formatMoney(d.fee)}
                  </td>
                  <td>
                    <span className="amount-pill" style={{ background: "rgba(16, 185, 129, 0.15)", color: "#10B981" }}>
                      {formatMoney(d.net)}
                    </span>
                  </td>
                  <td>
                    <span className={`status-badge ${d.isSettled ? "completed" : "pending"}`}>
                      {d.isSettled ? "Settled" : "Pending Payout"}
                    </span>
                  </td>
                  <td>
                    <button
                      className={`btn-action-small ${d.isSettled ? "btn-outline" : "btn-primary-small"}`}
                      onClick={() => onSettlePayout(d.id)}
                    >
                      {d.isSettled ? "Re-open" : "Mark as Settled"}
                    </button>
                  </td>
                </tr>
              ))}
              {!filteredDriverEarnings.length && (
                <tr>
                  <td colSpan="8" className="empty-state">
                    No driver earnings records found.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

// DISPATCH & INCOMING BOOKINGS CONSOLE VIEW COMPONENT
function DispatchView({
  rides,
  drivers,
  pendingRides,
  onDispatch,
  onAutoDispatch,
  onCancel,
  dispatchingRideId,
  selectedDrivers,
  setSelectedDrivers,
  soundEnabled,
  toggleSound,
  formatMoney,
  formatDate,
}) {
  const onlineDrivers = drivers.filter(
    (d) => d.availability === "available" || d.availability === "online"
  );
  const ongoingTrips = rides.filter(
    (r) => r.status === "ongoing" || r.status === "accepted" || r.status === "arrived"
  );

  return (
    <div className="dashboard-layout">
      {/* DISPATCH CONTROL HERO */}
      <div className="hero-banner dispatch-hero">
        <div className="hero-content">
          <span className="hero-tag">OPERATIONAL DISPATCH RADAR</span>
          <h2>Live Booking Queue & Driver Dispatch Center</h2>
          <p>
            Incoming booking requests from passengers appear here in real time. Dispatch available drivers manually or trigger 1-click auto-dispatch to keep fleet latency low.
          </p>
        </div>
        <div className="hero-controls-box">
          <button
            className={`btn-sound-pill ${soundEnabled ? "sound-on" : "sound-off"}`}
            onClick={toggleSound}
          >
            {soundEnabled ? <Volume2 size={16} /> : <VolumeX size={16} />}
            <span>{soundEnabled ? "Chime Audio: ACTIVE" : "Chime Audio: MUTED"}</span>
          </button>
        </div>
      </div>

      {/* DISPATCH METRICS STRIP */}
      <div className="dashboard-stats-grid">
        <div className={`metric-card ${pendingRides.length > 0 ? "highlight-amber" : ""}`}>
          <div className="card-header">
            <span>Incoming Unassigned</span>
            <Radio size={20} className={pendingRides.length > 0 ? "text-amber pulse-icon" : "text-muted"} />
          </div>
          <div className="metric-value text-amber">{pendingRides.length}</div>
          <div className="metric-footer">
            <span>Awaiting driver assignment</span>
          </div>
        </div>

        <div className="metric-card">
          <div className="card-header">
            <span>Online Available Drivers</span>
            <Car size={20} className="text-accent" />
          </div>
          <div className="metric-value text-accent">{onlineDrivers.length}</div>
          <div className="metric-footer">
            <span>Ready for immediate dispatch</span>
          </div>
        </div>

        <div className="metric-card">
          <div className="card-header">
            <span>Trips in Progress</span>
            <Activity size={20} className="text-success" />
          </div>
          <div className="metric-value text-success">{ongoingTrips.length}</div>
          <div className="metric-footer">
            <span>Currently on road with passengers</span>
          </div>
        </div>

        <div className="metric-card">
          <div className="card-header">
            <span>Auto-Dispatch Mode</span>
            <Zap size={20} className="text-accent" />
          </div>
          <div className="metric-value text-accent">Active (4s)</div>
          <div className="metric-footer">
            <span>Background WebSocket / Polling</span>
          </div>
        </div>
      </div>

      {/* HOW COMMON SYSTEM WORKS OPERATIONAL BREAKDOWN */}
      <div className="dispatch-guide-card">
        <div className="guide-title-row">
          <ShieldAlert size={18} className="text-accent" />
          <h3>How Common Ride-Hailing Dispatch Systems Work</h3>
        </div>
        <div className="guide-steps-grid">
          <div className="guide-step-item">
            <span className="step-circle">1</span>
            <div className="step-body">
              <strong>1. Passenger Books Ride</strong>
              <p>Rider inputs pickup & destination in app. System enters booking into database with status <code>requested</code>.</p>
            </div>
          </div>
          <div className="guide-step-item">
            <span className="step-circle">2</span>
            <div className="step-body">
              <strong>2. Dispatch Ping & Alert</strong>
              <p>System rings audible chime on dispatch console and pushes notifications to nearby online drivers.</p>
            </div>
          </div>
          <div className="guide-step-item">
            <span className="step-circle">3</span>
            <div className="step-body">
              <strong>3. Accept & Assign Driver</strong>
              <p>Driver accepts via mobile app, or Admin assigns an online driver below. Status advances to <code>accepted</code>.</p>
            </div>
          </div>
          <div className="guide-step-item">
            <span className="step-circle">4</span>
            <div className="step-body">
              <strong>4. Sequential Trip Fulfillment</strong>
              <p>Driver updates lifecycle: <code>arrived</code> ➔ <code>ongoing</code> ➔ <code>completed</code>. Settle via Cash or KHQR.</p>
            </div>
          </div>
        </div>
      </div>

      {/* PENDING REQUESTS QUEUE */}
      <div className="column-card full-width">
        <div className="card-top">
          <div>
            <h3>Pending Booking Requests Queue ({pendingRides.length})</h3>
            <p>Live unassigned trips. Choose a driver from the dropdown or click Auto-Assign.</p>
          </div>
        </div>

        {pendingRides.length === 0 ? (
          <div className="empty-state dispatch-idle">
            <div className="idle-radar-pulse">
              <Radio size={40} className="pulse-icon text-accent" />
            </div>
            <h4>Dispatch Queue is Clear</h4>
            <p>No unassigned booking requests right now. When a rider requests a trip, an alert chime will sound and the booking card will appear here automatically.</p>
          </div>
        ) : (
          <div className="dispatch-queue-grid">
            {pendingRides.map((ride) => {
              const selectedDriverId =
                selectedDrivers[ride.id] || (onlineDrivers[0] ? onlineDrivers[0].id : "");
              const isDispatching = dispatchingRideId === ride.id;

              return (
                <div key={ride.id} className="dispatch-card">
                  <div className="dispatch-card-header">
                    <div className="card-id-block">
                      <span className="live-pulse" />
                      <strong>TRIP #{ride.id}</strong>
                      <span className="badge-ride-type">{ride.ride_type || "Car"}</span>
                    </div>
                    <div className="card-clock">
                      <Clock size={14} />
                      <span>{formatDate(ride.created_at)}</span>
                    </div>
                  </div>

                  <div className="dispatch-card-content">
                    <div className="dispatch-route">
                      <div className="route-stop">
                        <span className="stop-icon pickup" />
                        <div className="stop-text">
                          <span className="stop-label">PICKUP</span>
                          <strong>{ride.pickup_location || "Current GPS Location"}</strong>
                        </div>
                      </div>
                      <div className="route-line" />
                      <div className="route-stop">
                        <span className="stop-icon destination" />
                        <div className="stop-text">
                          <span className="stop-label">DESTINATION</span>
                          <strong>{ride.destination || "Direct Metered Trip"}</strong>
                        </div>
                      </div>
                    </div>

                    <div className="dispatch-info-grid">
                      <div className="info-pill">
                        <span>Passenger:</span>
                        <strong>{ride.rider_name || `Rider #${ride.rider_id}`}</strong>
                      </div>
                      <div className="info-pill">
                        <span>Road Distance:</span>
                        <strong>{ride.distance_km ? `${ride.distance_km} km` : "Metered"}</strong>
                      </div>
                      <div className="info-pill">
                        <span>Est. Fare:</span>
                        <strong className="text-accent">
                          {formatMoney(ride.fare || ride.estimated_fare || 2.5)}
                        </strong>
                      </div>
                    </div>
                  </div>

                  <div className="dispatch-card-controls">
                    <div className="control-select-col">
                      <label>Select Driver:</label>
                      <select
                        value={selectedDriverId}
                        onChange={(e) =>
                          setSelectedDrivers({
                            ...selectedDrivers,
                            [ride.id]: e.target.value,
                          })
                        }
                      >
                        {onlineDrivers.length === 0 ? (
                          <option value="">No drivers currently online</option>
                        ) : (
                          onlineDrivers.map((d) => (
                            <option key={d.id} value={d.id}>
                              {d.name} ({d.vehicle_type || "Car"} - Available)
                            </option>
                          ))
                        )}
                      </select>
                    </div>

                    <div className="control-btns-row">
                      <button
                        className="btn-dispatch-accept"
                        disabled={!selectedDriverId || isDispatching}
                        onClick={() => onDispatch(ride.id, selectedDriverId)}
                      >
                        {isDispatching ? <RefreshCw size={15} className="spin" /> : <Check size={15} />}
                        <span>Assign & Accept</span>
                      </button>

                      <button
                        className="btn-dispatch-auto"
                        disabled={onlineDrivers.length === 0 || isDispatching}
                        onClick={() => onAutoDispatch(ride.id)}
                        title="Auto-dispatch to the first available driver"
                      >
                        <Zap size={15} />
                        <span>Auto-Assign</span>
                      </button>

                      <button
                        className="btn-dispatch-cancel"
                        disabled={isDispatching}
                        onClick={() => onCancel(ride.id)}
                        title="Cancel this booking"
                      >
                        <XCircle size={15} />
                        <span>Cancel</span>
                      </button>
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </div>
    </div>
  );
}

// DASHBOARD OVERVIEW VIEW COMPONENT
function DashboardView({ riders, drivers, rides, payments, vehicles, totalRevenue, setActiveTab, onInspectRide, setStatusFilter }) {
  const pendingCount = rides.filter((r) => r.status === "requested").length;
  const onlineDrivers = drivers.filter((d) => d.availability === "available" || d.availability === "online").length;
  const activeTrips = rides.filter((r) => r.status === "ongoing" || r.status === "accepted" || r.status === "requested").length;
  const recentRides = rides.slice(0, 5);

  return (
    <div className="dashboard-layout">
      {/* HERO BANNER */}
      <div className="hero-banner">
        <div className="hero-text">
          <span className="hero-tag">OPERATIONAL COMMAND CENTER</span>
          <h2>RideApp Fleet & Dispatch Overview</h2>
          <p>
            Monitor real-time driver availability, passenger trip allocations, and cash/Bakong KHQR transactions.
          </p>
        </div>
        <div className="hero-stats-quick">
          {pendingCount > 0 && (
            <div className="quick-kpi alert-kpi" onClick={() => setActiveTab("Dispatch")} style={{ cursor: "pointer", border: "1px solid rgba(245, 158, 11, 0.4)", background: "rgba(245, 158, 11, 0.12)" }}>
              <span style={{ color: "#FBBF24" }}>INCOMING TRIPS</span>
              <strong style={{ color: "#F59E0B" }}>{pendingCount} Pending →</strong>
            </div>
          )}
          <div className="quick-kpi">
            <span>LIVE DRIVERS</span>
            <strong>{onlineDrivers} Online</strong>
          </div>
          <div className="quick-kpi">
            <span>ACTIVE TRIPS</span>
            <strong>{activeTrips} In Progress</strong>
          </div>
        </div>
      </div>

      {/* KPI METRICS GRID */}
      <div className="kpi-grid">
        <div className="kpi-card" onClick={() => setActiveTab("Riders")}>
          <div className="kpi-header">
            <span>TOTAL PASSENGERS</span>
            <Users className="kpi-icon" size={20} />
          </div>
          <strong className="kpi-val">{riders.length}</strong>
          <small className="kpi-note">Registered passenger accounts</small>
        </div>

        <div className="kpi-card" onClick={() => setActiveTab("Drivers")}>
          <div className="kpi-header">
            <span>FLEET DRIVERS</span>
            <Car className="kpi-icon" size={20} />
          </div>
          <strong className="kpi-val">{drivers.length}</strong>
          <small className="kpi-note highlight-green">{onlineDrivers} currently online</small>
        </div>

        <div className="kpi-card" onClick={() => setActiveTab("Rides")}>
          <div className="kpi-header">
            <span>TOTAL RIDES</span>
            <Route className="kpi-icon" size={20} />
          </div>
          <strong className="kpi-val">{rides.length}</strong>
          <small className="kpi-note">{activeTrips} active bookings</small>
        </div>

        <div className="kpi-card" onClick={() => setActiveTab("Income")} style={{ borderColor: "#0B3ACD" }}>
          <div className="kpi-header">
            <span style={{ color: "#60A5FA" }}>PLATFORM INCOME</span>
            <DollarSign className="kpi-icon" size={20} style={{ color: "#60A5FA" }} />
          </div>
          <strong className="kpi-val" style={{ color: "#60A5FA" }}>{formatMoney(totalRevenue)}</strong>
          <small className="kpi-note highlight-green">Manage Income & Commission →</small>
        </div>

        <div className="kpi-card" onClick={() => setActiveTab("Vehicles")}>
          <div className="kpi-header">
            <span>REGISTERED ASSETS</span>
            <Layers className="kpi-icon" size={20} />
          </div>
          <strong className="kpi-val">{vehicles.length}</strong>
          <small className="kpi-note">Assigned vehicles</small>
        </div>
      </div>

      {/* TWO COLUMN GRID */}
      <div className="dashboard-columns">
        {/* RECENT TRIPS */}
        <div className="column-card">
          <div className="card-top">
            <div>
              <h3>Recent Trip Activity</h3>
              <p>Latest trip dispatches across the platform</p>
            </div>
            <button className="btn-link" onClick={() => setActiveTab("Rides")}>
              View All Trips <ChevronRight size={14} />
            </button>
          </div>

          <div className="activity-list">
            {recentRides.map((ride) => (
              <div className="activity-item" key={ride.id} onClick={() => onInspectRide(ride)}>
                <div className="activity-icon-badge">
                  <Route size={16} />
                </div>
                <div className="activity-details">
                  <div className="activity-row-top">
                    <strong>Trip #{ride.id} • {ride.rider_name || `User #${ride.rider_id}`}</strong>
                    <StatusBadge status={ride.status} />
                  </div>
                  <span className="activity-route">
                    {ride.pickup_location || "—"} → {ride.destination || "Direct Ride"}
                  </span>
                </div>
                <div className="activity-price">
                  {ride.fare != null ? formatMoney(ride.fare, ride.currency) : "—"}
                </div>
              </div>
            ))}
            {!recentRides.length && (
              <div className="empty-state">No trips requested yet.</div>
            )}
          </div>
        </div>

        {/* FLEET CAPACITY OVERVIEW */}
        <div className="column-card">
          <div className="card-top">
            <div>
              <h3>Fleet Status & Health</h3>
              <p>Platform status and readiness report</p>
            </div>
            <Activity size={18} className="text-accent" />
          </div>

          <div className="fleet-bars">
            <div className="fleet-stat-row">
              <span className="stat-label">Online Drivers:</span>
              <strong className="stat-val text-green">{onlineDrivers} / {drivers.length}</strong>
            </div>
            <div className="fleet-progress-bg">
              <div
                className="fleet-progress-fill green"
                style={{ width: `${drivers.length ? (onlineDrivers / drivers.length) * 100 : 0}%` }}
              />
            </div>

            <div className="fleet-stat-row">
              <span className="stat-label">Completed Trips:</span>
              <strong className="stat-val">
                {rides.filter((r) => r.status === "completed").length} / {rides.length}
              </strong>
            </div>
            <div className="fleet-progress-bg">
              <div
                className="fleet-progress-fill blue"
                style={{
                  width: `${rides.length ? (rides.filter((r) => r.status === "completed").length / rides.length) * 100 : 0}%`,
                }}
              />
            </div>

            <div className="system-specs-box">
              <div className="spec-line">
                <span>FastAPI Service</span>
                <span className="badge-spec">Healthy • v0.135</span>
              </div>
              <div className="spec-line">
                <span>Database Engine</span>
                <span className="badge-spec">MySQL 8.0</span>
              </div>
              <div className="spec-line">
                <span>Settlement Protocol</span>
                <span className="badge-spec">Cash + Bakong KHQR</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}

// STATUS BADGE COMPONENT
function StatusBadge({ status }) {
  const s = String(status || "requested").toLowerCase();
  let label = s.toUpperCase();
  let icon = Clock;
  let styleClass = "badge-requested";

  if (s === "completed" || s === "paid") {
    icon = CheckCircle2;
    styleClass = "badge-completed";
  } else if (s === "ongoing") {
    icon = Activity;
    styleClass = "badge-ongoing";
  } else if (s === "accepted") {
    icon = CheckCircle2;
    styleClass = "badge-accepted";
  } else if (s === "cancelled" || s === "failed") {
    icon = XCircle;
    styleClass = "badge-cancelled";
  }

  const IconComp = icon;
  return (
    <span className={`status-pill ${styleClass}`}>
      <IconComp size={12} />
      <span>{label}</span>
    </span>
  );
}

// MODAL SHELL
function Modal({ title, children, onClose }) {
  return (
    <div className="modal-overlay" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal-box">
        <div className="modal-header">
          <h3>{title}</h3>
          <button className="modal-close-btn" onClick={onClose} title="Close">
            ×
          </button>
        </div>
        <div className="modal-body">{children}</div>
      </div>
    </div>
  );
}

// USER FORM
function UserForm({ initial, onCancel, onSubmit }) {
  const [formData, setFormData] = useState(initial);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit(formData);
      }}
    >
      <div className="form-grid">
        <div className="form-group">
          <label>Full Name</label>
          <input
            required
            value={formData.name}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
            placeholder="John Doe"
          />
        </div>
        <div className="form-group">
          <label>Email Address</label>
          <input
            type="email"
            required
            value={formData.email}
            onChange={(e) => setFormData({ ...formData, email: e.target.value })}
            placeholder="john@example.com"
          />
        </div>
        <div className="form-group">
          <label>Phone Number</label>
          <input
            value={formData.phone || ""}
            onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
            placeholder="012 345 678"
          />
        </div>
        <div className="form-group">
          <label>{formData.id ? "New Password (leave empty to keep)" : "Password"}</label>
          <input
            type="password"
            required={!formData.id}
            value={formData.password || ""}
            onChange={(e) => setFormData({ ...formData, password: e.target.value })}
            placeholder="••••••••"
          />
        </div>
      </div>
      <div className="modal-footer">
        <button type="button" className="btn-secondary" onClick={onCancel}>
          Cancel
        </button>
        <button type="submit" className="btn-primary">
          Save Rider
        </button>
      </div>
    </form>
  );
}

// DRIVER FORM
function DriverForm({ initial, onCancel, onSubmit }) {
  const [formData, setFormData] = useState(initial);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit(formData);
      }}
    >
      <div className="form-grid">
        <div className="form-group">
          <label>Driver Full Name</label>
          <input
            required
            value={formData.name}
            onChange={(e) => setFormData({ ...formData, name: e.target.value })}
            placeholder="Sokha Chan"
          />
        </div>
        <div className="form-group">
          <label>Driver Email</label>
          <input
            type="email"
            required
            value={formData.email}
            onChange={(e) => setFormData({ ...formData, email: e.target.value })}
            placeholder="sokha@rideapp.com"
          />
        </div>
        <div className="form-group">
          <label>Phone Contact</label>
          <input
            value={formData.phone || ""}
            onChange={(e) => setFormData({ ...formData, phone: e.target.value })}
            placeholder="098 777 666"
          />
        </div>
        <div className="form-group">
          <label>Availability Status</label>
          <select
            value={formData.availability || "offline"}
            onChange={(e) => setFormData({ ...formData, availability: e.target.value })}
          >
            <option value="available">Online (Available for Matching)</option>
            <option value="offline">Offline</option>
            <option value="on_ride">On Ride</option>
          </select>
        </div>
        <div className="form-group full-col">
          <label>{formData.id ? "New Password (leave empty to keep)" : "Password"}</label>
          <input
            type="password"
            required={!formData.id}
            value={formData.password || ""}
            onChange={(e) => setFormData({ ...formData, password: e.target.value })}
            placeholder="••••••••"
          />
        </div>
      </div>
      <div className="modal-footer">
        <button type="button" className="btn-secondary" onClick={onCancel}>
          Cancel
        </button>
        <button type="submit" className="btn-primary">
          Save Driver
        </button>
      </div>
    </form>
  );
}

// VEHICLE FORM
function VehicleForm({ initial, drivers, onCancel, onSubmit }) {
  const [formData, setFormData] = useState(initial);
  return (
    <form
      onSubmit={(e) => {
        e.preventDefault();
        onSubmit(formData);
      }}
    >
      <div className="form-grid">
        <div className="form-group full-col">
          <label>Assign to Driver</label>
          <select
            required
            value={formData.driver_id || ""}
            onChange={(e) => setFormData({ ...formData, driver_id: e.target.value })}
          >
            <option value="">Select a registered driver...</option>
            {drivers.map((d) => (
              <option key={d.id} value={d.id}>
                {d.name} — #{d.id} ({d.email})
              </option>
            ))}
          </select>
        </div>
        <div className="form-group">
          <label>Vehicle Type</label>
          <select
            value={formData.vehicle_type || "Car"}
            onChange={(e) => setFormData({ ...formData, vehicle_type: e.target.value })}
          >
            <option value="Car">Car (Sedan / Standard)</option>
            <option value="Tuk Tuk">Tuk Tuk / Rickshaw</option>
            <option value="Motorbike">Motorbike</option>
            <option value="Comfort">Comfort (SUV / Premium)</option>
          </select>
        </div>
        <div className="form-group">
          <label>License Plate</label>
          <input
            required
            value={formData.plate_number || ""}
            onChange={(e) => setFormData({ ...formData, plate_number: e.target.value })}
            placeholder="2BP-1928"
          />
        </div>
        <div className="form-group full-col">
          <label>Vehicle Model & Color</label>
          <input
            required
            value={formData.vehicle_model || ""}
            onChange={(e) => setFormData({ ...formData, vehicle_model: e.target.value })}
            placeholder="Toyota Prius 2018 (Silver)"
          />
        </div>
      </div>
      <div className="modal-footer">
        <button type="button" className="btn-secondary" onClick={onCancel}>
          Cancel
        </button>
        <button type="submit" className="btn-primary" disabled={!formData.driver_id}>
          Save Vehicle
        </button>
      </div>
    </form>
  );
}
