-- Local MySQL 8+ schema for a fresh RideApp installation.
CREATE DATABASE IF NOT EXISTS ride_app CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE ride_app;

CREATE TABLE IF NOT EXISTS users (
  id INT AUTO_INCREMENT PRIMARY KEY,
  name VARCHAR(100) NOT NULL,
  email VARCHAR(150) NOT NULL UNIQUE,
  phone VARCHAR(30) NOT NULL DEFAULT '',
  password VARCHAR(255) NOT NULL,
  role ENUM('rider','driver','admin') NOT NULL DEFAULT 'rider',
  availability ENUM('offline','available','on_ride') NULL DEFAULT 'offline',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_users_role_availability (role,availability)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS vehicles (
  id INT AUTO_INCREMENT PRIMARY KEY,
  driver_id INT NOT NULL,
  vehicle_type VARCHAR(50) NOT NULL,
  vehicle_model VARCHAR(100) NOT NULL,
  plate_number VARCHAR(30) NOT NULL UNIQUE,
  CONSTRAINT fk_vehicle_driver FOREIGN KEY (driver_id) REFERENCES users(id),
  INDEX idx_vehicle_driver (driver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS rides (
  id INT AUTO_INCREMENT PRIMARY KEY,
  rider_id INT NOT NULL,
  driver_id INT NULL,
  pickup_location VARCHAR(255) NOT NULL,
  destination VARCHAR(255) NOT NULL DEFAULT '',
  ride_type VARCHAR(50) NOT NULL DEFAULT 'Car',
  distance_km DECIMAL(10,2) NULL,
  estimated_fare DECIMAL(10,2) NULL,
  fare DECIMAL(10,2) NULL,
  pickup_lat DECIMAL(10,7) NULL,
  pickup_lng DECIMAL(10,7) NULL,
  destination_lat DECIMAL(10,7) NULL,
  destination_lng DECIMAL(10,7) NULL,
  status ENUM('requested','accepted','ongoing','completed','cancelled') NOT NULL DEFAULT 'requested',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_ride_rider FOREIGN KEY (rider_id) REFERENCES users(id),
  CONSTRAINT fk_ride_driver FOREIGN KEY (driver_id) REFERENCES users(id) ON DELETE SET NULL,
  INDEX idx_rides_status_driver (status,driver_id),
  INDEX idx_rides_rider (rider_id,created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS payments (
  id INT AUTO_INCREMENT PRIMARY KEY,
  ride_id INT NOT NULL,
  amount DECIMAL(10,2) NOT NULL,
  payment_method VARCHAR(50) NOT NULL DEFAULT 'cash',
  status ENUM('pending','paid','failed') NOT NULL DEFAULT 'pending',
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_payment_ride FOREIGN KEY (ride_id) REFERENCES rides(id),
  UNIQUE KEY uq_payment_ride (ride_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS notifications (
  id INT AUTO_INCREMENT PRIMARY KEY,
  user_id INT NULL,
  title VARCHAR(255) NOT NULL,
  message TEXT NOT NULL,
  type VARCHAR(50) DEFAULT 'system',
  is_read TINYINT(1) DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX idx_notifications_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
