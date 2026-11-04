-- =============================================================================
-- RideApp Complete MySQL Database Schema & Seed Data
-- Database Engine: MySQL 8.0+ / MariaDB 10.5+
-- Compatible with: RideApp FastAPI Backend & React Admin Dashboard
-- Palette Theme: #0B3ACD, #264399, #2E3C66, #212633, #2B2D33
-- =============================================================================

CREATE DATABASE IF NOT EXISTS `ride_app`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE `ride_app`;

-- -----------------------------------------------------------------------------
-- 1. USERS TABLE
-- Stores riders, drivers, and system administrators
-- Supports Argon2, bcrypt, and plaintext migration
-- -----------------------------------------------------------------------------
DROP TABLE IF EXISTS `push_tokens`;
DROP TABLE IF EXISTS `ratings`;
DROP TABLE IF EXISTS `payment_intents`;
DROP TABLE IF EXISTS `payments`;
DROP TABLE IF EXISTS `ride_events`;
DROP TABLE IF EXISTS `ride_offers`;
DROP TABLE IF EXISTS `driver_locations`;
DROP TABLE IF EXISTS `notifications`;
DROP TABLE IF EXISTS `rides`;
DROP TABLE IF EXISTS `vehicles`;
DROP TABLE IF EXISTS `users`;

CREATE TABLE `users` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(100) NOT NULL,
  `email` VARCHAR(150) NOT NULL UNIQUE,
  `phone` VARCHAR(30) NOT NULL DEFAULT '',
  `password` VARCHAR(255) NOT NULL,
  `role` ENUM('rider', 'driver', 'admin') NOT NULL DEFAULT 'rider',
  `availability` ENUM('offline', 'available', 'on_ride') NULL DEFAULT 'offline',
  `is_deleted` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_users_role_availability` (`role`, `availability`),
  INDEX `idx_users_email` (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 2. VEHICLES TABLE
-- Links vehicles directly to registered drivers
-- -----------------------------------------------------------------------------
CREATE TABLE `vehicles` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `driver_id` INT NOT NULL,
  `vehicle_type` VARCHAR(50) NOT NULL,
  `vehicle_model` VARCHAR(100) NOT NULL,
  `plate_number` VARCHAR(30) NOT NULL UNIQUE,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_vehicle_driver` FOREIGN KEY (`driver_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  INDEX `idx_vehicle_driver` (`driver_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 3. RIDES TABLE
-- Ride booking records, routes, fares, and lifecycle status
-- -----------------------------------------------------------------------------
CREATE TABLE `rides` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `rider_id` INT NOT NULL,
  `driver_id` INT NULL,
  `pickup_location` VARCHAR(255) NOT NULL,
  `destination` VARCHAR(255) NOT NULL DEFAULT '',
  `ride_type` VARCHAR(50) NOT NULL DEFAULT 'Car',
  `distance_km` DECIMAL(10,2) NULL,
  `estimated_fare` DECIMAL(10,2) NULL,
  `fare` DECIMAL(10,2) NULL,
  `pickup_lat` DECIMAL(10,7) NULL,
  `pickup_lng` DECIMAL(10,7) NULL,
  `destination_lat` DECIMAL(10,7) NULL,
  `destination_lng` DECIMAL(10,7) NULL,
  `status` ENUM('requested', 'accepted', 'ongoing', 'completed', 'cancelled') NOT NULL DEFAULT 'requested',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_ride_rider` FOREIGN KEY (`rider_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_ride_driver` FOREIGN KEY (`driver_id`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  INDEX `idx_rides_status_driver` (`status`, `driver_id`),
  INDEX `idx_rides_rider` (`rider_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 4. DRIVER LOCATIONS TABLE
-- Real-time telemetry, GPS tracking and trip association
-- -----------------------------------------------------------------------------
CREATE TABLE `driver_locations` (
  `driver_id` INT PRIMARY KEY,
  `ride_id` INT NULL,
  `latitude` DECIMAL(10,7) NOT NULL,
  `longitude` DECIMAL(10,7) NOT NULL,
  `heading` DECIMAL(7,2) NULL,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT `fk_location_driver` FOREIGN KEY (`driver_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  INDEX `idx_location_ride` (`ride_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 5. RIDE OFFERS TABLE
-- Dispatch queue connecting ride requests to candidate drivers
-- -----------------------------------------------------------------------------
CREATE TABLE `ride_offers` (
  `ride_id` INT NOT NULL,
  `driver_id` INT NOT NULL,
  `status` ENUM('offered', 'rejected', 'accepted') NOT NULL DEFAULT 'offered',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`ride_id`, `driver_id`),
  INDEX `idx_offer_driver_status` (`driver_id`, `status`),
  CONSTRAINT `fk_offer_ride` FOREIGN KEY (`ride_id`) REFERENCES `rides` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_offer_driver` FOREIGN KEY (`driver_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 6. RIDE EVENTS TABLE
-- Audit log of status transitions and state changes
-- -----------------------------------------------------------------------------
CREATE TABLE `ride_events` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `ride_id` INT NOT NULL,
  `actor_id` INT NULL,
  `event_type` VARCHAR(40) NOT NULL,
  `details` JSON NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_ride_event` (`ride_id`, `id`),
  CONSTRAINT `fk_event_ride` FOREIGN KEY (`ride_id`) REFERENCES `rides` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 7. PAYMENTS TABLE
-- Settlement records for completed rides (Cash / KHQR)
-- -----------------------------------------------------------------------------
CREATE TABLE `payments` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `ride_id` INT NOT NULL,
  `amount` DECIMAL(10,2) NOT NULL,
  `payment_method` VARCHAR(50) NOT NULL DEFAULT 'cash',
  `status` ENUM('pending', 'paid', 'failed') NOT NULL DEFAULT 'pending',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_payment_ride` FOREIGN KEY (`ride_id`) REFERENCES `rides` (`id`) ON DELETE CASCADE,
  UNIQUE KEY `uq_payment_ride` (`ride_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 8. PAYMENT INTENTS TABLE
-- Dynamic USD Bakong KHQR intents and digital settlement verification
-- -----------------------------------------------------------------------------
CREATE TABLE `payment_intents` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `ride_id` INT NOT NULL,
  `rider_id` INT NOT NULL,
  `provider` VARCHAR(30) NOT NULL DEFAULT 'bakong',
  `amount` DECIMAL(10,2) NOT NULL,
  `currency` CHAR(3) NOT NULL DEFAULT 'USD',
  `qr_payload` TEXT NOT NULL,
  `qr_md5` CHAR(32) NOT NULL,
  `status` VARCHAR(20) NOT NULL DEFAULT 'pending',
  `expires_at` DATETIME NOT NULL,
  `provider_transaction_hash` VARCHAR(128) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_payment_qr_md5` (`qr_md5`),
  UNIQUE KEY `uq_payment_intent_ride` (`ride_id`),
  CONSTRAINT `fk_payment_intent_ride` FOREIGN KEY (`ride_id`) REFERENCES `rides` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_payment_intent_rider` FOREIGN KEY (`rider_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 9. RATINGS TABLE
-- 5-star ratings and feedback comments between riders and drivers
-- -----------------------------------------------------------------------------
CREATE TABLE `ratings` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `ride_id` INT NOT NULL,
  `rater_id` INT NOT NULL,
  `ratee_id` INT NOT NULL,
  `score` TINYINT NOT NULL,
  `comment` VARCHAR(500) NULL,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_ride_rater` (`ride_id`, `rater_id`),
  INDEX `idx_ratee` (`ratee_id`),
  CONSTRAINT `fk_rating_ride` FOREIGN KEY (`ride_id`) REFERENCES `rides` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_rating_rater` FOREIGN KEY (`rater_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_rating_ratee` FOREIGN KEY (`ratee_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 10. NOTIFICATIONS TABLE
-- Real-time in-app alerts and notifications
-- -----------------------------------------------------------------------------
CREATE TABLE `notifications` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NULL,
  `title` VARCHAR(255) NOT NULL,
  `message` TEXT NOT NULL,
  `type` VARCHAR(50) DEFAULT 'system',
  `is_read` TINYINT(1) DEFAULT 0,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_notifications_user` (`user_id`),
  CONSTRAINT `fk_notification_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- -----------------------------------------------------------------------------
-- 11. PUSH TOKENS TABLE
-- FCM Device push registration tokens
-- -----------------------------------------------------------------------------
CREATE TABLE `push_tokens` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT NOT NULL,
  `token` VARCHAR(512) NOT NULL,
  `platform` VARCHAR(20) NOT NULL DEFAULT 'android',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_push_token` (`token`),
  INDEX `idx_push_user` (`user_id`),
  CONSTRAINT `fk_push_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- SEED DATA FOR IMMEDIATE LOCAL DEMO & TESTING
-- Passwords below are automatically accepted and upgraded to Argon2 upon login.
-- Admin Credentials: admin@rideapp.com / admin123456
-- =============================================================================

INSERT INTO `users` (`id`, `name`, `email`, `phone`, `password`, `role`, `availability`) VALUES
(1, 'Super Administrator', 'admin@rideapp.com', '012345678', 'admin123456', 'admin', NULL),
(2, 'Sokha Chan', 'driver.sokha@rideapp.com', '012888999', 'driver123456', 'driver', 'available'),
(3, 'Vireak Meng', 'driver.vireak@rideapp.com', '098777666', 'driver123456', 'driver', 'available'),
(4, 'Bopha Pich', 'driver.bopha@rideapp.com', '088111222', 'driver123456', 'driver', 'offline'),
(5, 'David Kem', 'rider.david@rideapp.com', '077222333', 'rider123456', 'rider', 'offline'),
(6, 'Dara Sam', 'rider.dara@rideapp.com', '085444555', 'rider123456', 'rider', 'offline'),
(7, 'Chenda Meas', 'rider.chenda@rideapp.com', '012999888', 'rider123456', 'rider', 'offline');

INSERT INTO `vehicles` (`id`, `driver_id`, `vehicle_type`, `vehicle_model`, `plate_number`) VALUES
(1, 2, 'Car', 'Toyota Prius 2018 (Silver)', '2BP-1928'),
(2, 3, 'Car', 'Mazda 3 2022 (Blue)', '2BD-8891'),
(3, 4, 'Tuk Tuk', 'Bajaj RE 2021 (Yellow)', '1Q-4452');

INSERT INTO `driver_locations` (`driver_id`, `ride_id`, `latitude`, `longitude`, `heading`) VALUES
(2, NULL, 11.5564000, 104.9282000, 45.00),
(3, NULL, 11.5621000, 104.9160000, 180.00);

INSERT INTO `rides` (`id`, `rider_id`, `driver_id`, `pickup_location`, `destination`, `ride_type`, `distance_km`, `estimated_fare`, `fare`, `pickup_lat`, `pickup_lng`, `destination_lat`, `destination_lng`, `status`, `created_at`) VALUES
(1, 5, 2, 'Aeon Mall 1 (Samdach Sothearos Blvd)', 'Wat Phnom Historical Park', 'Car', 4.80, 5.10, 5.10, 11.5475000, 104.9351000, 11.5762000, 104.9230000, 'completed', NOW() - INTERVAL 2 HOUR),
(2, 6, 3, 'Independence Monument', 'Royal Palace Phnom Penh', 'Car', 2.30, 3.23, 3.23, 11.5564000, 104.9282000, 11.5638000, 104.9317000, 'completed', NOW() - INTERVAL 1 HOUR),
(3, 5, 2, 'Phnom Penh Railway Station', 'Russian Market (Toul Tom Poung)', 'Car', 3.90, 4.43, NULL, 11.5739000, 104.9169000, 11.5408000, 104.9142000, 'ongoing', NOW() - INTERVAL 15 MINUTE),
(4, 6, NULL, 'Tuol Sleng Genocide Museum', 'Central Market (Phsar Thmey)', 'Car', 3.20, 3.90, NULL, 11.5494000, 104.9174000, 11.5696000, 104.9213000, 'requested', NOW() - INTERVAL 5 MINUTE);

INSERT INTO `payments` (`id`, `ride_id`, `amount`, `payment_method`, `status`, `created_at`) VALUES
(1, 1, 5.10, 'cash', 'paid', NOW() - INTERVAL 115 MINUTE),
(2, 2, 3.23, 'bakong_khqr', 'paid', NOW() - INTERVAL 50 MINUTE);

INSERT INTO `ratings` (`id`, `ride_id`, `rater_id`, `ratee_id`, `score`, `comment`, `created_at`) VALUES
(1, 1, 5, 2, 5, 'Very polite driver and smooth ride. Car was spotless!', NOW() - INTERVAL 110 MINUTE),
(2, 2, 6, 3, 5, 'Arrived very quickly and knew the best shortcuts.', NOW() - INTERVAL 45 MINUTE);

INSERT INTO `notifications` (`id`, `user_id`, `title`, `message`, `type`, `is_read`, `created_at`) VALUES
(1, 1, 'System Ready', 'RideApp core services and database initialized.', 'system', 0, NOW() - INTERVAL 3 HOUR),
(2, 5, 'Ride Completed', 'Your trip with driver Sokha Chan was completed. Total: $5.10.', 'ride', 1, NOW() - INTERVAL 115 MINUTE),
(3, 6, 'KHQR Payment Confirmed', 'Payment of $3.23 confirmed via Bakong KHQR.', 'payment', 1, NOW() - INTERVAL 50 MINUTE),
(4, 2, 'New Ride Assigned', 'You were assigned to Ride #3 with David Kem.', 'ride', 0, NOW() - INTERVAL 15 MINUTE);
