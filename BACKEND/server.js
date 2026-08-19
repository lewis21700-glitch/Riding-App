const express = require("express");
const mysql = require("mysql2");
const cors = require("cors");
const jwt = require("jsonwebtoken");

require("dotenv").config();

const app = express();

// =========================
// MIDDLEWARE
// =========================

app.use(cors());
app.use(express.json());

// =========================
// MYSQL CONNECTION
// =========================

const db = mysql.createConnection({
  host: "localhost",
  user: "root",
  password: "1234",
  database: "ride_app"
});

db.connect((err) => {
  if (err) {
    console.log("MySQL connection failed:", err.message);
  } else {
    console.log("MySQL connected successfully!");
  }
});

// =========================
// HOME
// =========================

app.get("/", (req, res) => {
  res.send("Ride App Backend is running!");
});

// =========================
// LOGIN
// =========================

app.post("/api/login", (req, res) => {
  const { email, password } = req.body;

  if (!email || !password) {
    return res.status(400).json({
      error: "Email and password are required"
    });
  }

  const sql = `
    SELECT id, name, email, phone, password, role, created_at
    FROM users
    WHERE email = ?
    LIMIT 1
  `;

  db.query(sql, [email], (err, results) => {
    if (err) {
      console.log("Login database error:", err);

      return res.status(500).json({
        error: "Login failed"
      });
    }

    if (results.length === 0) {
      return res.status(401).json({
        error: "Invalid email or password"
      });
    }

    const user = results[0];

    if (user.password !== password) {
      return res.status(401).json({
        error: "Invalid email or password"
      });
    }

    const token = jwt.sign(
      {
        id: user.id,
        email: user.email,
        role: user.role
      },
      "ride_app_secret",
      {
        expiresIn: "1h"
      }
    );

    res.json({
      message: "Login successful",

      token: token,

      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        phone: user.phone,
        role: user.role
      }
    });
  });
});

// =========================
// GET ALL USERS
// =========================

app.get("/api/users", (req, res) => {
  const sql = `
    SELECT
      id,
      name,
      email,
      phone,
      role,
      created_at
    FROM users
    ORDER BY id DESC
  `;

  db.query(sql, (err, results) => {
    if (err) {
      console.log("Error getting users:", err);

      return res.status(500).json({
        error: "Failed to get users"
      });
    }

    res.json(results);
  });
});

// =========================
// ADD USER
// =========================

app.post("/api/users", (req, res) => {
  const {
    name,
    email,
    phone,
    password,
    role
  } = req.body;

  if (!name || !email || !password) {
    return res.status(400).json({
      error: "Name, email and password are required"
    });
  }

  const sql = `
    INSERT INTO users
    (name, email, phone, password, role)
    VALUES (?, ?, ?, ?, ?)
  `;

  db.query(
    sql,
    [
      name,
      email,
      phone || "",
      password,
      role || "rider"
    ],
    (err, result) => {
      if (err) {
        console.log("Error adding user:", err);

        return res.status(500).json({
          error: "Failed to add user"
        });
      }

      res.status(201).json({
        message: "User added successfully",
        id: result.insertId
      });
    }
  );
});

// =========================
// UPDATE USER
// =========================

app.put("/api/users/:id", (req, res) => {
  const { id } = req.params;

  const {
    name,
    email,
    phone,
    role
  } = req.body;

  const sql = `
    UPDATE users
    SET
      name = ?,
      email = ?,
      phone = ?,
      role = ?
    WHERE id = ?
  `;

  db.query(
    sql,
    [
      name,
      email,
      phone,
      role,
      id
    ],
    (err, result) => {
      if (err) {
        console.log("Error updating user:", err);

        return res.status(500).json({
          error: "Failed to update user"
        });
      }

      res.json({
        message: "User updated successfully"
      });
    }
  );
});

// =========================
// DELETE USER
// =========================

app.delete("/api/users/:id", (req, res) => {
  const { id } = req.params;

  const sql = "DELETE FROM users WHERE id = ?";

  db.query(sql, [id], (err, result) => {
    if (err) {
      console.log("Error deleting user:", err);

      return res.status(500).json({
        error: "Failed to delete user"
      });
    }

    res.json({
      message: "User deleted successfully"
    });
  });
});

// =========================
// GET ALL RIDES
// =========================

app.get("/api/rides", (req, res) => {
  const sql = `
    SELECT
      rides.id,
      rides.rider_id,
      rider.name AS rider_name,
      rides.driver_id,
      driver.name AS driver_name,
      rides.pickup_location,
      rides.destination,
      rides.fare,
      rides.status,
      rides.created_at

    FROM rides

    LEFT JOIN users AS rider
      ON rides.rider_id = rider.id

    LEFT JOIN users AS driver
      ON rides.driver_id = driver.id

    ORDER BY rides.id DESC
  `;

  db.query(sql, (err, results) => {
    if (err) {
      console.log("Error getting rides:", err);

      return res.status(500).json({
        error: "Failed to get rides"
      });
    }

    res.json(results);
  });
});

// =========================
// GET ALL PAYMENTS
// =========================

app.get("/api/payments", (req, res) => {
  const sql = `
    SELECT
      payments.id,
      payments.ride_id,
      rider.name AS rider_name,
      payments.amount,
      payments.status,
      payments.created_at

    FROM payments

    LEFT JOIN rides
      ON payments.ride_id = rides.id

    LEFT JOIN users AS rider
      ON rides.rider_id = rider.id

    ORDER BY payments.id DESC
  `;

  db.query(sql, (err, results) => {
    if (err) {
      console.log("Error getting payments:", err);

      return res.status(500).json({
        error: "Failed to get payments"
      });
    }

    res.json(results);
  });
});

// =========================
// GET ALL VEHICLES
// =========================

app.get("/api/vehicles", (req, res) => {
  const sql = `
    SELECT
      id,
      driver_id,
      vehicle_type,
      vehicle_model,
      plate_number

    FROM vehicles

    ORDER BY id DESC
  `;

  db.query(sql, (err, results) => {
    if (err) {
      console.log("Error getting vehicles:", err);

      return res.status(500).json({
        error: "Failed to get vehicles"
      });
    }

    res.json(results);
  });
});

// =========================
// START SERVER
// =========================

const PORT = 3000;

app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
