import { useEffect, useState } from "react";
import "./App.css";

const API = "http://localhost:3000";

function App() {
  // =========================
  // LOGIN
  // =========================

  const [loggedIn, setLoggedIn] = useState(
    !!localStorage.getItem("token")
  );

  const [loginEmail, setLoginEmail] = useState("");
  const [loginPassword, setLoginPassword] = useState("");
  const [loginError, setLoginError] = useState("");
  const [loginLoading, setLoginLoading] = useState(false);

  const savedUser = localStorage.getItem("user");

  const [adminUser, setAdminUser] = useState(
    savedUser ? JSON.parse(savedUser) : null
  );

  // =========================
  // DASHBOARD
  // =========================

  const [active, setActive] = useState("Dashboard");

  const [users, setUsers] = useState([]);
  const [rides, setRides] = useState([]);
  const [payments, setPayments] = useState([]);
  const [vehicles, setVehicles] = useState([]);

  const [search, setSearch] = useState("");

  // =========================
  // ADD USER
  // =========================

  const [showAddUser, setShowAddUser] = useState(false);

  const [newUser, setNewUser] = useState({
    name: "",
    email: "",
    phone: "",
    password: "",
    role: "rider",
  });

  // =========================
  // LOGIN FUNCTION
  // =========================

  const handleLogin = async () => {
  setLoginError("");

  if (!loginEmail || !loginPassword) {
    setLoginError("Please enter email and password.");
    return;
  }

  try {
    const response = await fetch("http://localhost:3000/api/login", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        email: loginEmail,
        password: loginPassword,
      }),
    });

    const data = await response.json();

    if (!response.ok) {
      setLoginError(data.error || "Login failed.");
      return;
    }

    // Make sure only admin can enter
    if (data.user.role !== "admin") {
      setLoginError("Access denied. Admin account required.");
      return;
    }

    // Save login information
    localStorage.setItem("token", data.token);
    localStorage.setItem("user", JSON.stringify(data.user));

    setLoggedIn(true);
    setLoginError("");
  } catch (error) {
    console.error("LOGIN ERROR:", error);

    setLoginError(
      "Cannot connect to server. Make sure backend is running on port 3000."
    );
  }
};
  // =========================
  // LOGOUT
  // =========================

  const logout = () => {
    localStorage.removeItem("token");
    localStorage.removeItem("user");

    setLoggedIn(false);
    setAdminUser(null);
    setActive("Dashboard");
  };

  // =========================
  // LOAD USERS
  // =========================

  const loadUsers = async () => {
    try {
      const response = await fetch(`${API}/api/users`);
      const data = await response.json();

      if (response.ok) {
        setUsers(data);
      }
    } catch (error) {
      console.error("Error loading users:", error);
    }
  };

  // =========================
  // LOAD RIDES
  // =========================

  const loadRides = async () => {
    try {
      const response = await fetch(`${API}/api/rides`);
      const data = await response.json();

      if (response.ok) {
        setRides(data);
      }
    } catch (error) {
      console.error("Error loading rides:", error);
    }
  };

  // =========================
  // LOAD PAYMENTS
  // =========================

  const loadPayments = async () => {
    try {
      const response = await fetch(`${API}/api/payments`);
      const data = await response.json();

      if (response.ok) {
        setPayments(data);
      }
    } catch (error) {
      console.error("Error loading payments:", error);
    }
  };

  // =========================
  // LOAD VEHICLES
  // =========================

  const loadVehicles = async () => {
    try {
      const response = await fetch(`${API}/api/vehicles`);
      const data = await response.json();

      if (response.ok) {
        setVehicles(data);
      }
    } catch (error) {
      console.error("Error loading vehicles:", error);
    }
  };

  // =========================
  // LOAD ALL DATA
  // =========================

  useEffect(() => {
    if (loggedIn) {
      loadUsers();
      loadRides();
      loadPayments();
      loadVehicles();
    }
  }, [loggedIn]);

  // =========================
  // ADD USER
  // =========================

  const addUser = async () => {
    if (
      !newUser.name ||
      !newUser.email ||
      !newUser.password
    ) {
      alert("Please fill in name, email and password.");
      return;
    }

    try {
      const response = await fetch(`${API}/api/users`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify(newUser),
      });

      const data = await response.json();

      if (!response.ok) {
        alert(data.error || "Failed to add user.");
        return;
      }

      alert("User added successfully!");

      setNewUser({
        name: "",
        email: "",
        phone: "",
        password: "",
        role: "rider",
      });

      setShowAddUser(false);

      loadUsers();
    } catch (error) {
      console.error("Error adding user:", error);
      alert("Cannot connect to server.");
    }
  };

  // =========================
  // DELETE USER
  // =========================

  const deleteUser = async (id, type = "user") => {
    const confirmed = window.confirm(
      `Delete this ${type}?`
    );

    if (!confirmed) {
      return;
    }

    try {
      const response = await fetch(
        `${API}/api/users/${id}`,
        {
          method: "DELETE",
        }
      );

      const data = await response.json();

      if (!response.ok) {
        alert(data.error || "Failed to delete.");
        return;
      }

      alert(
        `${
          type.charAt(0).toUpperCase() + type.slice(1)
        } deleted successfully!`
      );

      loadUsers();
    } catch (error) {
      console.error("Delete error:", error);
      alert("Cannot connect to server.");
    }
  };

  // =========================
  // EDIT USER
  // =========================

  const editUser = async (user) => {
    const name = window.prompt(
      "Enter new name:",
      user.name || ""
    );

    if (name === null) return;

    const email = window.prompt(
      "Enter new email:",
      user.email || ""
    );

    if (email === null) return;

    const phone = window.prompt(
      "Enter new phone:",
      user.phone || ""
    );

    if (phone === null) return;

    let role = user.role;

    if (user.role !== "admin") {
      role = window.prompt(
        "Enter role (rider/driver):",
        user.role
      );

      if (role === null) return;

      role = role.toLowerCase();

      if (
        role !== "rider" &&
        role !== "driver"
      ) {
        alert("Role must be rider or driver.");
        return;
      }
    }

    try {
      const response = await fetch(
        `${API}/api/users/${user.id}`,
        {
          method: "PUT",
          headers: {
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            name,
            email,
            phone,
            role,
          }),
        }
      );

      const data = await response.json();

      if (!response.ok) {
        alert(data.error || "Failed to update user.");
        return;
      }

      alert("User updated successfully!");

      loadUsers();
    } catch (error) {
      console.error("Update error:", error);
      alert("Cannot connect to server.");
    }
  };

  // =========================
  // MENU
  // =========================

  const menu = [
    {
      name: "Dashboard",
      icon: "⌂",
    },
    {
      name: "Users",
      icon: "♙",
    },
    {
      name: "Drivers",
      icon: "D",
    },
    {
      name: "Rides",
      icon: "↗",
    },
    {
      name: "Payments",
      icon: "$",
    },
    {
      name: "Vehicles",
      icon: "▣",
    },
  ];

  // =========================
  // LOGIN SCREEN
  // =========================

  if (!loggedIn) {
    return (
      <div className="login-page">
        <div className="login-box">

          <div className="login-logo">
            🚕
          </div>

          <h1>Ride Admin</h1>

          <p className="login-label">
            MANAGEMENT SYSTEM
          </p>

          <h2>Welcome Back</h2>

          <p className="login-description">
            Sign in to access the admin dashboard.
          </p>

          <input
            type="email"
            placeholder="Email"
            value={loginEmail}
            onChange={(e) =>
              setLoginEmail(e.target.value)
            }
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                handleLogin();
              }
            }}
          />

          <input
            type="password"
            placeholder="Password"
            value={loginPassword}
            onChange={(e) =>
              setLoginPassword(e.target.value)
            }
            onKeyDown={(e) => {
              if (e.key === "Enter") {
                handleLogin();
              }
            }}
          />

          {loginError && (
            <div className="login-error">
              {loginError}
            </div>
          )}

          <button
            className="login-button"
            onClick={handleLogin}
            disabled={loginLoading}
          >
            {loginLoading ? "Logging in..." : "Login"}
          </button>

        </div>
      </div>
    );
  }

  // =========================
  // DASHBOARD
  // =========================

  return (
    <div className="app">

      {/* SIDEBAR */}

      <aside className="sidebar">

        <div className="brand">

          <div className="brand-icon">
            🚕
          </div>

          <div>
            <h2>Ride Admin</h2>
            <span>MANAGEMENT SYSTEM</span>
          </div>

        </div>

        <p className="section-title">
          MAIN MENU
        </p>

        <nav>
          {menu.map((item) => (
            <button
              key={item.name}
              className={`menu-item ${
                active === item.name
                  ? "active"
                  : ""
              }`}
              onClick={() => {
                setActive(item.name);
                setSearch("");
              }}
            >
              <span className="menu-icon">
                {item.icon}
              </span>

              <span>{item.name}</span>
            </button>
          ))}
        </nav>

        <div className="sidebar-bottom">

          <div className="online">
            <span></span>
            System Online
          </div>

          <div className="admin">

            <div className="avatar">
              A
            </div>

            <div>
              <strong>
                {adminUser?.name ||
                  "Administrator"}
              </strong>

              <small>
                Super Admin
              </small>
            </div>

          </div>

          <button
            className="logout-button"
            onClick={logout}
          >
            Logout
          </button>

        </div>

      </aside>

      {/* MAIN */}

      <main className="main">

        {/* TOP BAR */}

        <header className="topbar">

          <div>
            <p className="welcome-small">
              WELCOME BACK
            </p>

            <h1>{active}</h1>
          </div>

          <div className="top-right">

            <button className="bell">
              🔔
            </button>

            <div className="admin-mini">

              <div className="avatar small">
                A
              </div>

              <div>
                <strong>
                  {adminUser?.name ||
                    "Administrator"}
                </strong>

                <small>
                  Online
                </small>
              </div>

            </div>

          </div>

        </header>

        {/* =========================
            DASHBOARD
        ========================= */}

        {active === "Dashboard" && (
          <>
            <section className="hero">

              <div>
                <span>
                  RIDE APP MANAGEMENT
                </span>

                <h2>
                  Everything under control.
                </h2>

                <p>
                  Monitor users, drivers, rides
                  and payments from one place.
                </p>
              </div>

              <div className="hero-car">
                🚕
              </div>

            </section>

            <section className="stats">

              <div className="card">

                <div className="card-top">
                  <span>
                    Registered Users
                  </span>

                  <b className="blue">
                    ♙
                  </b>
                </div>

                <h2>
                  {
                    users.filter(
                      (u) =>
                        u.role === "rider"
                    ).length
                  }
                </h2>

                <p className="up">
                  Current registered riders
                </p>

              </div>

              <div className="card">

                <div className="card-top">
                  <span>
                    Active Drivers
                  </span>

                  <b className="green">
                    🚗
                  </b>
                </div>

                <h2>
                  {
                    users.filter(
                      (u) =>
                        u.role === "driver"
                    ).length
                  }
                </h2>

                <p className="up">
                  Registered drivers
                </p>

              </div>

              <div className="card">

                <div className="card-top">
                  <span>
                    Total Rides
                  </span>

                  <b className="orange">
                    ↗
                  </b>
                </div>

                <h2>
                  {rides.length}
                </h2>

                <p className="up">
                  Rides recorded
                </p>

              </div>

              <div className="card">

                <div className="card-top">
                  <span>
                    Total Payments
                  </span>

                  <b className="purple">
                    $
                  </b>
                </div>

                <h2>
                  {payments.length}
                </h2>

                <p className="up">
                  Payment records
                </p>

              </div>

            </section>

            <section className="lower">

              <div className="panel">

                <div className="panel-title">

                  <div>
                    <h3>
                      Recent Rides
                    </h3>

                    <p>
                      Latest activity from
                      your platform
                    </p>
                  </div>

                  <button
                    onClick={() =>
                      setActive("Rides")
                    }
                  >
                    View All
                  </button>

                </div>

                {rides.length === 0 ? (
                  <div className="empty">
                    No rides available.
                  </div>
                ) : (
                  rides
                    .slice(0, 5)
                    .map((ride) => (
                      <div
                        className="ride-row"
                        key={ride.id}
                      >

                        <span className="ride-avatar blue-bg">
                          {(
                            ride.rider_name ||
                            "R"
                          )
                            .charAt(0)
                            .toUpperCase()}
                        </span>

                        <div className="ride-info">

                          <strong>
                            Ride #{ride.id}
                          </strong>

                          <small>
                            {ride.pickup_location ||
                              "-"}{" "}
                            →{" "}
                            {ride.destination ||
                              "-"}
                          </small>

                        </div>

                        <span
                          className={`status ${
                            ride.status || ""
                          }`}
                        >
                          {ride.status ||
                            "Unknown"}
                        </span>

                        <strong>
                          $
                          {Number(
                            ride.fare || 0
                          ).toFixed(2)}
                        </strong>

                      </div>
                    ))
                )}

              </div>

              <div className="panel drivers-panel">

                <div className="panel-title">

                  <div>
                    <h3>
                      Driver Overview
                    </h3>

                    <p>
                      Current driver status
                    </p>
                  </div>

                </div>

                <div className="driver-number">

                  <strong>
                    {
                      users.filter(
                        (u) =>
                          u.role ===
                          "driver"
                      ).length
                    }
                  </strong>

                  <span>
                    Registered Drivers
                  </span>

                </div>

                <div className="driver-list">

                  <div>
                    <span className="dot green-dot"></span>
                    Drivers
                    <strong>
                      {
                        users.filter(
                          (u) =>
                            u.role ===
                            "driver"
                        ).length
                      }
                    </strong>
                  </div>

                  <div>
                    <span className="dot orange-dot"></span>
                    Vehicles
                    <strong>
                      {vehicles.length}
                    </strong>
                  </div>

                  <div>
                    <span className="dot gray-dot"></span>
                    Rides
                    <strong>
                      {rides.length}
                    </strong>
                  </div>

                </div>

              </div>

            </section>
          </>
        )}

        {/* =========================
            USERS
        ========================= */}

        {active === "Users" && (
          <section className="users-page">

            <div className="page-header">

              <div>
                <span className="page-label">
                  USER MANAGEMENT
                </span>

                <h2>
                  Registered Users
                </h2>

                <p>
                  View and manage users
                  registered on the platform.
                </p>
              </div>

              <div className="user-count">

                <strong>
                  {
                    users.filter(
                      (user) =>
                        user.role ===
                        "rider"
                    ).length
                  }
                </strong>

                <span>
                  Total Users
                </span>

              </div>

              <button
                className="add-user-btn"
                onClick={() =>
                  setShowAddUser(true)
                }
              >
                + Add User
              </button>

            </div>

            <div className="user-search">

              <input
                type="text"
                placeholder="Search users..."
                value={search}
                onChange={(e) =>
                  setSearch(e.target.value)
                }
              />

            </div>

            {/* ADD USER */}

            {showAddUser && (
              <div className="add-user-form">

                <h3>
                  Add New User
                </h3>

                <input
                  type="text"
                  placeholder="Name"
                  value={newUser.name}
                  onChange={(e) =>
                    setNewUser({
                      ...newUser,
                      name: e.target.value,
                    })
                  }
                />

                <input
                  type="email"
                  placeholder="Email"
                  value={newUser.email}
                  onChange={(e) =>
                    setNewUser({
                      ...newUser,
                      email: e.target.value,
                    })
                  }
                />

                <input
                  type="text"
                  placeholder="Phone"
                  value={newUser.phone}
                  onChange={(e) =>
                    setNewUser({
                      ...newUser,
                      phone: e.target.value,
                    })
                  }
                />

                <input
                  type="password"
                  placeholder="Password"
                  value={newUser.password}
                  onChange={(e) =>
                    setNewUser({
                      ...newUser,
                      password: e.target.value,
                    })
                  }
                />

                <select
                  value={newUser.role}
                  onChange={(e) =>
                    setNewUser({
                      ...newUser,
                      role: e.target.value,
                    })
                  }
                >
                  <option value="rider">
                    Rider
                  </option>

                  <option value="driver">
                    Driver
                  </option>
                </select>

                <button onClick={addUser}>
                  Save User
                </button>

                <button
                  onClick={() =>
                    setShowAddUser(false)
                  }
                >
                  Cancel
                </button>

              </div>
            )}

            {/* USERS TABLE */}

            <div className="users-table">

              <div className="table-header">

                <span>ID</span>
                <span>Name</span>
                <span>Email</span>
                <span>Phone</span>
                <span>Role</span>
                <span>Actions</span>

              </div>

              {users
                .filter(
                  (user) =>
                    user.role ===
                    "rider"
                )
                .filter((user) =>
                  `${user.name || ""} ${
                    user.email || ""
                  } ${
                    user.phone || ""
                  }`
                    .toLowerCase()
                    .includes(
                      search.toLowerCase()
                    )
                )
                .map((user) => (

                  <div
                    className="table-row"
                    key={user.id}
                  >

                    <span>
                      #{user.id}
                    </span>

                    <strong>
                      {user.name}
                    </strong>

                    <span>
                      {user.email}
                    </span>

                    <span>
                      {user.phone || "-"}
                    </span>

                    <span className="role-badge">
                      {user.role}
                    </span>

                    <div className="user-actions">

                      <button
                        onClick={() =>
                          editUser(user)
                        }
                      >
                        Edit
                      </button>

                      <button
                        onClick={() =>
                          deleteUser(
                            user.id,
                            "user"
                          )
                        }
                      >
                        Delete
                      </button>

                    </div>

                  </div>
                ))}

            </div>

          </section>
        )}

        {/* =========================
            DRIVERS
        ========================= */}

        {active === "Drivers" && (
          <section className="users-page">

            <div className="page-header">

              <div>
                <span className="page-label">
                  DRIVER MANAGEMENT
                </span>

                <h2>
                  Registered Drivers
                </h2>

                <p>
                  View and manage drivers
                  registered on the platform.
                </p>
              </div>

              <div className="user-count">

                <strong>
                  {
                    users.filter(
                      (user) =>
                        user.role ===
                        "driver"
                    ).length
                  }
                </strong>

                <span>
                  Total Drivers
                </span>

              </div>

            </div>

            <div className="user-search">

              <input
                type="text"
                placeholder="Search drivers..."
                value={search}
                onChange={(e) =>
                  setSearch(e.target.value)
                }
              />

            </div>

            <div className="users-table">

              <div className="table-header">

                <span>ID</span>
                <span>Name</span>
                <span>Email</span>
                <span>Phone</span>
                <span>Role</span>
                <span>Actions</span>

              </div>

              {users
                .filter(
                  (user) =>
                    user.role ===
                    "driver"
                )
                .filter((user) =>
                  `${user.name || ""} ${
                    user.email || ""
                  } ${
                    user.phone || ""
                  }`
                    .toLowerCase()
                    .includes(
                      search.toLowerCase()
                    )
                )
                .map((user) => (

                  <div
                    className="table-row"
                    key={user.id}
                  >

                    <span>
                      #{user.id}
                    </span>

                    <strong>
                      {user.name}
                    </strong>

                    <span>
                      {user.email}
                    </span>

                    <span>
                      {user.phone || "-"}
                    </span>

                    <span className="role-badge">
                      {user.role}
                    </span>

                    <div className="user-actions">

                      <button
                        onClick={() =>
                          editUser(user)
                        }
                      >
                        Edit
                      </button>

                      <button
                        onClick={() =>
                          deleteUser(
                            user.id,
                            "driver"
                          )
                        }
                      >
                        Delete
                      </button>

                    </div>

                  </div>
                ))}

            </div>

          </section>
        )}

        {/* =========================
            RIDES
        ========================= */}

        {active === "Rides" && (
          <section className="users-page">

            <div className="page-header">

              <div>
                <span className="page-label">
                  RIDE MANAGEMENT
                </span>

                <h2>
                  Registered Rides
                </h2>

                <p>
                  View rides registered
                  on the platform.
                </p>
              </div>

              <div className="user-count">

                <strong>
                  {rides.length}
                </strong>

                <span>
                  Total Rides
                </span>

              </div>

            </div>

            <div className="user-search">

              <input
                type="text"
                placeholder="Search rides..."
                value={search}
                onChange={(e) =>
                  setSearch(e.target.value)
                }
              />

            </div>

            <div className="users-table">

              <div className="table-header">

                <span>ID</span>
                <span>Rider</span>
                <span>Driver</span>
                <span>Pickup</span>
                <span>Destination</span>
                <span>Fare</span>
                <span>Status</span>

              </div>

              {rides
                .filter((ride) =>
                  `${ride.rider_name || ""} ${
                    ride.driver_name || ""
                  } ${
                    ride.pickup_location ||
                    ""
                  } ${
                    ride.destination || ""
                  }`
                    .toLowerCase()
                    .includes(
                      search.toLowerCase()
                    )
                )
                .map((ride) => (

                  <div
                    className="table-row"
                    key={ride.id}
                  >

                    <span>
                      #{ride.id}
                    </span>

                    <strong>
                      {ride.rider_name ||
                        "-"}
                    </strong>

                    <span>
                      {ride.driver_name ||
                        "-"}
                    </span>

                    <span>
                      {ride.pickup_location ||
                        "-"}
                    </span>

                    <span>
                      {ride.destination ||
                        "-"}
                    </span>

                    <span>
                      $
                      {Number(
                        ride.fare || 0
                      ).toFixed(2)}
                    </span>

                    <span
                      className={`status ${
                        ride.status || ""
                      }`}
                    >
                      {ride.status ||
                        "-"}
                    </span>

                  </div>
                ))}

            </div>

          </section>
        )}

        {/* =========================
            PAYMENTS
        ========================= */}

        {active === "Payments" && (
          <section className="users-page">

            <div className="page-header">

              <div>
                <span className="page-label">
                  PAYMENT MANAGEMENT
                </span>

                <h2>
                  Registered Payments
                </h2>

                <p>
                  View payments made on
                  the platform.
                </p>
              </div>

              <div className="user-count">

                <strong>
                  {payments.length}
                </strong>

                <span>
                  Total Payments
                </span>

              </div>

            </div>

            <div className="users-table">

              <div className="table-header">

                <span>ID</span>
                <span>Ride ID</span>
                <span>Rider</span>
                <span>Amount</span>
                <span>Status</span>
                <span>Created At</span>

              </div>

              {payments.map(
                (payment) => (

                  <div
                    className="table-row"
                    key={payment.id}
                  >

                    <span>
                      #{payment.id}
                    </span>

                    <span>
                      #{payment.ride_id}
                    </span>

                    <span>
                      {payment.rider_name ||
                        "-"}
                    </span>

                    <span>
                      $
                      {Number(
                        payment.amount || 0
                      ).toFixed(2)}
                    </span>

                    <span
                      className={`status ${
                        payment.status ||
                        ""
                      }`}
                    >
                      {payment.status ||
                        "-"}
                    </span>

                    <span>
                      {payment.created_at
                        ? new Date(
                            payment.created_at
                          ).toLocaleString(
                            "en-GB",
                            {
                              day: "2-digit",
                              month: "short",
                              year: "numeric",
                              hour: "2-digit",
                              minute: "2-digit",
                            }
                          )
                        : "-"}
                    </span>

                  </div>
                )
              )}

            </div>

          </section>
        )}

        {/* =========================
            VEHICLES
        ========================= */}

        {active === "Vehicles" && (
          <section className="users-page">

            <div className="page-header">

              <div>
                <span className="page-label">
                  VEHICLE MANAGEMENT
                </span>

                <h2>
                  Registered Vehicles
                </h2>

                <p>
                  View vehicles registered
                  on the platform.
                </p>
              </div>

              <div className="user-count">

                <strong>
                  {vehicles.length}
                </strong>

                <span>
                  Total Vehicles
                </span>

              </div>

            </div>

            <div className="users-table">

              <div className="table-header">

                <span>ID</span>
                <span>Driver ID</span>
                <span>Vehicle Type</span>
                <span>Vehicle Model</span>
                <span>Plate Number</span>

              </div>

              {vehicles.map(
                (vehicle) => (

                  <div
                    className="table-row"
                    key={vehicle.id}
                  >

                    <span>
                      #{vehicle.id}
                    </span>

                    <span>
                      #{vehicle.driver_id}
                    </span>

                    <span>
                      {vehicle.vehicle_type ||
                        "-"}
                    </span>

                    <span>
                      {vehicle.vehicle_model ||
                        "-"}
                    </span>

                    <span>
                      {vehicle.plate_number ||
                        "-"}
                    </span>

                  </div>
                )
              )}

            </div>

          </section>
        )}

      </main>

    </div>
  );
}

export default App;
