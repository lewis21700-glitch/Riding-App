const express = require("express");
const mysql = require("mysql2");
const cors = require("cors");
const jwt = require("jsonwebtoken");
require("dotenv").config();

const app = express();
const PORT = Number(process.env.PORT || 3000);
const JWT_SECRET = process.env.JWT_SECRET || "ride_app_secret";

app.use(cors());
app.use(express.json());

const db = mysql.createConnection({
  host: process.env.DB_HOST || "localhost",
  user: process.env.DB_USER || "root",
  password: process.env.DB_PASSWORD || "1234",
  database: process.env.DB_NAME || "ride_app",
});

const query = (sql, params = []) => new Promise((resolve, reject) => {
  db.query(sql, params, (err, rows) => err ? reject(err) : resolve(rows));
});

function auth(req, res, next) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7) : null;
  if (!token) return res.status(401).json({ error: "Authentication required" });
  try {
    req.user = jwt.verify(token, JWT_SECRET);
    next();
  } catch {
    res.status(401).json({ error: "Invalid or expired token" });
  }
}

function adminOnly(req, res, next) {
  if (req.user?.role !== "admin") return res.status(403).json({ error: "Admin access required" });
  next();
}

function riderOnly(req, res, next) {
  if (req.user?.role !== "rider") return res.status(403).json({ error: "Rider access required" });
  next();
}

function driverOnly(req, res, next) {
  if (req.user?.role !== "driver") return res.status(403).json({ error: "Driver access required" });
  next();
}

async function ensureColumn(table, column, definition) {
  const rows = await query(
    `SELECT COUNT(*) AS count FROM INFORMATION_SCHEMA.COLUMNS
     WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? AND COLUMN_NAME = ?`,
    [table, column]
  );
  if (!rows[0].count) await query(`ALTER TABLE ${table} ADD COLUMN ${column} ${definition}`);
}

async function ensureSchema() {
  await ensureColumn("users", "availability", "ENUM('online','offline','busy') NULL DEFAULT 'offline' AFTER role");
  await ensureColumn("rides", "ride_type", "VARCHAR(50) NULL AFTER destination");
  await ensureColumn("rides", "distance_km", "DECIMAL(10,2) NULL AFTER ride_type");
  await ensureColumn("rides", "pickup_lat", "DECIMAL(10,7) NULL AFTER distance_km");
  await ensureColumn("rides", "pickup_lng", "DECIMAL(10,7) NULL AFTER pickup_lat");
  await ensureColumn("payments", "payment_method", "VARCHAR(30) NULL AFTER amount");
  await query("ALTER TABLE rides MODIFY fare DECIMAL(10,2) NULL");

  await query(`CREATE TABLE IF NOT EXISTS notifications (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NULL,
    title VARCHAR(255) NOT NULL,
    message TEXT NOT NULL,
    type VARCHAR(50) DEFAULT 'system',
    is_read TINYINT(1) DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_notifications_user (user_id)
  ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4`);

  await query("UPDATE users SET availability = 'offline' WHERE role = 'driver' AND availability IS NULL");
}

app.get("/", (req, res) => res.send("Ride App Backend is running!"));

// =========================
// AUTH
// =========================
app.post("/api/login", async (req, res) => {
  const { email, password } = req.body;
  if (!email || !password) return res.status(400).json({ error: "Email and password are required" });
  try {
    const rows = await query(`SELECT id,name,email,phone,password,role,created_at FROM users WHERE email=? LIMIT 1`, [email.trim()]);
    if (!rows.length || rows[0].password !== password) return res.status(401).json({ error: "Invalid email or password" });
    const user = rows[0];
    const token = jwt.sign({ id: user.id, email: user.email, role: user.role }, JWT_SECRET, { expiresIn: "8h" });
    res.json({ message: "Login successful", token, user: { id:user.id, name:user.name, email:user.email, phone:user.phone, role:user.role } });
  } catch (err) {
    console.error(err);
    res.status(500).json({ error: "Login failed" });
  }
});

// =========================
// USERS / RIDERS - SPRINT 2
// =========================
app.get("/api/users", auth, adminOnly, async (req,res) => {
  try { res.json(await query(`SELECT id,name,email,phone,role,created_at FROM users ORDER BY id DESC`)); }
  catch (err) { console.error(err); res.status(500).json({error:"Failed to get users"}); }
});

app.post("/api/users", auth, adminOnly, async (req,res) => {
  const {name,email,phone,password,role="rider"}=req.body;
  if(!name?.trim()||!email?.trim()||!password) return res.status(400).json({error:"Name, email and password are required"});
  if(!["rider","driver"].includes(role)) return res.status(400).json({error:"Role must be rider or driver"});
  try {
    const r=await query(`INSERT INTO users(name,email,phone,password,role,availability) VALUES(?,?,?,?,?,?)`,[name.trim(),email.trim(),phone||"",password,role,role==="driver"?"offline":null]);
    if(role==="driver") await query(`INSERT INTO notifications(user_id,title,message,type) VALUES(?,?,?,?)`,[r.insertId,"Driver account created",`Driver ${name.trim()} was registered.`,"driver"]);
    res.status(201).json({message:"User added successfully",id:r.insertId});
  } catch(err) { console.error(err); res.status(err.code==="ER_DUP_ENTRY"?409:500).json({error:err.code==="ER_DUP_ENTRY"?"Email already exists":"Failed to add user"}); }
});

app.put("/api/users/:id", auth, adminOnly, async (req,res) => {
  const id=Number(req.params.id); const {name,email,phone,role,password}=req.body;
  if(!name?.trim()||!email?.trim()||!["rider","driver","admin"].includes(role)) return res.status(400).json({error:"Name, email and valid role are required"});
  try {
    const fields=["name=?","email=?","phone=?","role=?"]; const values=[name.trim(),email.trim(),phone||"",role];
    if(password){fields.push("password=?");values.push(password);} values.push(id);
    const r=await query(`UPDATE users SET ${fields.join(",")} WHERE id=?`,values);
    if(!r.affectedRows) return res.status(404).json({error:"User not found"});
    res.json({message:"User updated successfully"});
  } catch(err){console.error(err);res.status(err.code==="ER_DUP_ENTRY"?409:500).json({error:err.code==="ER_DUP_ENTRY"?"Email already exists":"Failed to update user"});}
});

app.delete("/api/users/:id", auth, adminOnly, async (req,res) => {
  const id=Number(req.params.id); if(id===req.user.id)return res.status(400).json({error:"You cannot delete the logged-in admin"});
  try{const r=await query("DELETE FROM users WHERE id=?",[id]);if(!r.affectedRows)return res.status(404).json({error:"User not found"});res.json({message:"User deleted successfully"});}
  catch(err){console.error(err);res.status(409).json({error:"This user is linked to vehicles or rides and cannot be deleted."});}
});

// =========================
// DRIVERS / AVAILABILITY - SPRINT 2
// =========================
app.get("/api/drivers", auth, adminOnly, async (req,res)=>{
  try{res.json(await query(`SELECT u.id,u.name,u.email,u.phone,COALESCE(u.availability,'offline') AS availability,v.id AS vehicle_id,v.vehicle_type,v.vehicle_model,v.plate_number FROM users u LEFT JOIN vehicles v ON v.driver_id=u.id WHERE u.role='driver' ORDER BY u.id DESC`));}
  catch(err){console.error(err);res.status(500).json({error:"Failed to get drivers"});}
});

app.post("/api/drivers", auth, adminOnly, async (req,res)=>{
  const {name,email,phone,password,availability="offline"}=req.body;
  if(!name?.trim()||!email?.trim()||!password)return res.status(400).json({error:"Name, email and password are required"});
  if(!["online","offline","busy"].includes(availability))return res.status(400).json({error:"Invalid availability"});
  try{const r=await query(`INSERT INTO users(name,email,phone,password,role,availability) VALUES(?,?,?,?, 'driver',?)`,[name.trim(),email.trim(),phone||"",password,availability]);await query(`INSERT INTO notifications(user_id,title,message,type) VALUES(?,?,?,?)`,[r.insertId,"Driver added",`Driver ${name.trim()} was added to RideApp.`,"driver"]);res.status(201).json({message:"Driver added successfully",id:r.insertId});}
  catch(err){console.error(err);res.status(err.code==="ER_DUP_ENTRY"?409:500).json({error:err.code==="ER_DUP_ENTRY"?"Email already exists":"Failed to add driver"});}
});

app.put("/api/drivers/:id", auth, adminOnly, async (req,res)=>{
  const id=Number(req.params.id);const {name,email,phone,availability,password}=req.body;
  if(!name?.trim()||!email?.trim()||!["online","offline","busy"].includes(availability))return res.status(400).json({error:"Name, email and valid availability are required"});
  try{const fields=["name=?","email=?","phone=?","availability=?"];const values=[name.trim(),email.trim(),phone||"",availability];if(password){fields.push("password=?");values.push(password);}values.push(id);const r=await query(`UPDATE users SET ${fields.join(",")} WHERE id=? AND role='driver'`,values);if(!r.affectedRows)return res.status(404).json({error:"Driver not found"});res.json({message:"Driver updated successfully"});}
  catch(err){console.error(err);res.status(err.code==="ER_DUP_ENTRY"?409:500).json({error:err.code==="ER_DUP_ENTRY"?"Email already exists":"Failed to update driver"});}
});

app.delete("/api/drivers/:id", auth, adminOnly, async (req,res)=>{
  try{const r=await query("DELETE FROM users WHERE id=? AND role='driver'",[Number(req.params.id)]);if(!r.affectedRows)return res.status(404).json({error:"Driver not found"});res.json({message:"Driver deleted successfully"});}
  catch(err){console.error(err);res.status(409).json({error:"This driver is linked to a vehicle or ride and cannot be deleted."});}
});

// =========================
// VEHICLES - SPRINT 2
// =========================
app.get("/api/vehicles", auth, adminOnly, async (req,res)=>{
  try{res.json(await query(`SELECT v.id,v.driver_id,u.name AS driver_name,v.vehicle_type,v.vehicle_model,v.plate_number FROM vehicles v LEFT JOIN users u ON v.driver_id=u.id ORDER BY v.id DESC`));}
  catch(err){console.error(err);res.status(500).json({error:"Failed to get vehicles"});}
});

app.post("/api/vehicles", auth, adminOnly, async (req,res)=>{
  const {driver_id,vehicle_type,vehicle_model,plate_number}=req.body;
  if(!driver_id||!vehicle_type?.trim()||!vehicle_model?.trim()||!plate_number?.trim())return res.status(400).json({error:"Driver, vehicle type, model and plate number are required"});
  try{const d=await query("SELECT id FROM users WHERE id=? AND role='driver'",[driver_id]);if(!d.length)return res.status(400).json({error:"Selected driver does not exist"});const r=await query(`INSERT INTO vehicles(driver_id,vehicle_type,vehicle_model,plate_number) VALUES(?,?,?,?)`,[driver_id,vehicle_type.trim(),vehicle_model.trim(),plate_number.trim()]);await query(`INSERT INTO notifications(user_id,title,message,type) VALUES(?,?,?,?)`,[driver_id,"Vehicle registered",`A ${vehicle_type.trim()} ${vehicle_model.trim()} was registered to your account.`,"vehicle"]);res.status(201).json({message:"Vehicle added successfully",id:r.insertId});}
  catch(err){console.error(err);res.status(err.code==="ER_DUP_ENTRY"?409:500).json({error:err.code==="ER_DUP_ENTRY"?"This plate number or vehicle assignment already exists":"Failed to add vehicle"});}
});

app.put("/api/vehicles/:id", auth, adminOnly, async (req,res)=>{
  const {driver_id,vehicle_type,vehicle_model,plate_number}=req.body;const id=Number(req.params.id);
  if(!driver_id||!vehicle_type?.trim()||!vehicle_model?.trim()||!plate_number?.trim())return res.status(400).json({error:"Driver, vehicle type, model and plate number are required"});
  try{const d=await query("SELECT id FROM users WHERE id=? AND role='driver'",[driver_id]);if(!d.length)return res.status(400).json({error:"Selected driver does not exist"});const r=await query(`UPDATE vehicles SET driver_id=?,vehicle_type=?,vehicle_model=?,plate_number=? WHERE id=?`,[driver_id,vehicle_type.trim(),vehicle_model.trim(),plate_number.trim(),id]);if(!r.affectedRows)return res.status(404).json({error:"Vehicle not found"});res.json({message:"Vehicle updated successfully"});}
  catch(err){console.error(err);res.status(err.code==="ER_DUP_ENTRY"?409:500).json({error:err.code==="ER_DUP_ENTRY"?"This plate number or vehicle assignment already exists":"Failed to update vehicle"});}
});

app.delete("/api/vehicles/:id", auth, adminOnly, async (req,res)=>{try{const r=await query("DELETE FROM vehicles WHERE id=?",[Number(req.params.id)]);if(!r.affectedRows)return res.status(404).json({error:"Vehicle not found"});res.json({message:"Vehicle deleted successfully"});}catch(err){console.error(err);res.status(500).json({error:"Failed to delete vehicle"});}});

// =========================
// FARE ENGINE - SPRINT 3
// =========================
const FARE_RULES={
  "Car": {base:1.50, perKm:0.75, minimum:2.50},
  "Tuk Tuk": {base:1.00, perKm:0.55, minimum:2.00},
  "Motorbike": {base:0.75, perKm:0.40, minimum:1.50},
  "Direct Ride": {base:0, perKm:0, minimum:0},
};
function calculateFare(type,distance){const rule=FARE_RULES[type]||FARE_RULES.Car;return Math.max(rule.minimum,rule.base+rule.perKm*distance);}

app.post("/api/fare/estimate", auth, riderOnly, async (req,res)=>{
  const type=String(req.body.ride_type||"Car");const distance=Number(req.body.distance_km);
  if(type==="Direct Ride")return res.json({ride_type:type,estimated_fare:null,direct:true,message:"Final fare will be set when the ride is completed."});
  if(!Number.isFinite(distance)||distance<0)return res.status(400).json({error:"A valid distance in km is required"});
  res.json({ride_type:type,distance_km:distance,estimated_fare:Number(calculateFare(type,distance).toFixed(2))});
});

// =========================
// RIDES - SPRINT 3
// Admin can VIEW only. Ride updates belong to the ride workflow.
// =========================
app.get("/api/rides", auth, adminOnly, async (req,res)=>{
  try{res.json(await query(`SELECT r.id,r.rider_id,rider.name AS rider_name,r.driver_id,driver.name AS driver_name,r.pickup_location,r.destination,r.ride_type,r.distance_km,r.pickup_lat,r.pickup_lng,r.fare,r.status,r.created_at FROM rides r LEFT JOIN users rider ON r.rider_id=rider.id LEFT JOIN users driver ON r.driver_id=driver.id ORDER BY r.id DESC`));}
  catch(err){console.error(err);res.status(500).json({error:"Failed to get rides"});}
});

app.post("/api/rides", auth, riderOnly, async (req,res)=>{
  const {ride_type="Car",pickup_location,destination="",distance_km,pickup_lat,pickup_lng}=req.body;
  if(!pickup_location?.trim())return res.status(400).json({error:"Pickup location is required"});
  if(ride_type!=="Direct Ride"&&!destination?.trim())return res.status(400).json({error:"Destination is required"});
  let fare=null;
  const distance=distance_km==null||distance_km===""?null:Number(distance_km);
  if(ride_type!=="Direct Ride"){
    if(!Number.isFinite(distance)||distance<0)return res.status(400).json({error:"Valid distance is required"});
    fare=Number(calculateFare(ride_type,distance).toFixed(2));
  }
  try{
    const r=await query(`INSERT INTO rides(rider_id,driver_id,pickup_location,destination,ride_type,distance_km,pickup_lat,pickup_lng,fare,status) VALUES(?,NULL,?,?,?,?,?,?,?,?)`,[req.user.id,pickup_location.trim(),destination?.trim()||"",ride_type,distance,pickup_lat??null,pickup_lng??null,fare,"requested"]);
    const drivers=await query(`SELECT id FROM users WHERE role='driver' AND availability='online'`);
    for(const d of drivers) await query(`INSERT INTO notifications(user_id,title,message,type) VALUES(?,?,?,?)`,[d.id,"New ride request",`Ride #${r.insertId} is waiting for a driver.`,"ride"]);
    res.status(201).json({message:"Ride requested successfully",ride_id:r.insertId,estimated_fare:fare,direct:ride_type==="Direct Ride"});
  }catch(err){console.error(err);res.status(500).json({error:"Failed to create ride"});}
});

app.get("/api/my-rides", auth, riderOnly, async (req,res)=>{
  try{res.json(await query(`SELECT r.id,r.pickup_location,r.destination,r.ride_type,r.distance_km,r.fare,r.status,r.created_at,d.name AS driver_name FROM rides r LEFT JOIN users d ON r.driver_id=d.id WHERE r.rider_id=? ORDER BY r.id DESC`,[req.user.id]));}
  catch(err){console.error(err);res.status(500).json({error:"Failed to get your rides"});}
});

app.get("/api/driver-rides", auth, driverOnly, async (req,res)=>{
  try{res.json(await query(`SELECT r.id,r.rider_id,u.name AS rider_name,r.pickup_location,r.destination,r.ride_type,r.distance_km,r.fare,r.status,r.created_at FROM rides r LEFT JOIN users u ON r.rider_id=u.id WHERE r.driver_id=? OR (r.status='requested' AND r.driver_id IS NULL) ORDER BY r.id DESC`,[req.user.id]));}
  catch(err){console.error(err);res.status(500).json({error:"Failed to get driver rides"});}
});

app.put("/api/driver-rides/:id", auth, driverOnly, async (req,res)=>{
  const id=Number(req.params.id);const {status,final_fare}=req.body;const allowed=["accepted","ongoing","completed","cancelled"];
  if(!allowed.includes(status))return res.status(400).json({error:"Invalid ride status"});
  try{
    const rows=await query(`SELECT * FROM rides WHERE id=? LIMIT 1`,[id]);if(!rows.length)return res.status(404).json({error:"Ride not found"});const ride=rows[0];
    if(status==="accepted"){
      if(ride.driver_id&&Number(ride.driver_id)!==Number(req.user.id))return res.status(409).json({error:"This ride is already assigned"});
      await query(`UPDATE rides SET driver_id=?,status='accepted' WHERE id=? AND (driver_id IS NULL OR driver_id=?)`,[req.user.id,id,req.user.id]);
    } else {
      if(Number(ride.driver_id)!==Number(req.user.id))return res.status(403).json({error:"This ride is not assigned to you"});
      if(status==="completed"){
        if(ride.ride_type==="Direct Ride"){
          const f=Number(final_fare);if(!Number.isFinite(f)||f<0)return res.status(400).json({error:"Final fare is required for Direct Ride"});
          await query(`UPDATE rides SET status='completed',fare=? WHERE id=? AND driver_id=?`,[Number(f.toFixed(2)),id,req.user.id]);
        } else await query(`UPDATE rides SET status='completed' WHERE id=? AND driver_id=?`,[id,req.user.id]);
      } else await query(`UPDATE rides SET status=? WHERE id=? AND driver_id=?`,[status,id,req.user.id]);
    }
    const updated=await query(`SELECT r.id,r.fare,r.status,r.rider_id FROM rides r WHERE r.id=?`,[id]);
    const u=updated[0];
    if(u) await query(`INSERT INTO notifications(user_id,title,message,type) VALUES(?,?,?,?)`,[u.rider_id,"Ride updated",`Ride #${id} is now ${u.status}${u.fare!=null?` — fare $${Number(u.fare).toFixed(2)}`:""}.`,"ride"]);
    res.json({message:"Ride updated successfully",fare:u?.fare??null,status:u?.status});
  }catch(err){console.error(err);res.status(500).json({error:"Failed to update ride"});}
});

// =========================
// PAYMENTS
// =========================
app.get("/api/payments", auth, adminOnly, async (req,res)=>{
  try{res.json(await query(`SELECT p.id,p.ride_id,rider.name AS rider_name,p.amount,p.payment_method,p.status,p.created_at FROM payments p LEFT JOIN rides r ON p.ride_id=r.id LEFT JOIN users rider ON r.rider_id=rider.id ORDER BY p.id DESC`));}
  catch(err){console.error(err);res.status(500).json({error:"Failed to get payments"});}
});

app.post("/api/payments", auth, riderOnly, async (req,res)=>{
  const {ride_id,payment_method="cash"}=req.body; if(!ride_id)return res.status(400).json({error:"Ride ID is required"});
  try{
    const rides=await query(`SELECT id,rider_id,fare,status FROM rides WHERE id=? AND rider_id=? LIMIT 1`,[ride_id,req.user.id]);if(!rides.length)return res.status(404).json({error:"Ride not found"});
    const ride=rides[0];if(ride.fare==null)return res.status(400).json({error:"Final fare is not available yet"});
    const existing=await query(`SELECT id FROM payments WHERE ride_id=? LIMIT 1`,[ride_id]);if(existing.length)return res.json({message:"Payment already exists",payment_id:existing[0].id});
    const r=await query(`INSERT INTO payments(ride_id,amount,payment_method,status) VALUES(?,?,?,'paid')`,[ride_id,ride.fare,payment_method]);res.status(201).json({message:"Payment recorded",payment_id:r.insertId,amount:ride.fare});
  }catch(err){console.error(err);res.status(500).json({error:"Failed to record payment"});}
});

// =========================
// NOTIFICATIONS - SPRINT 2
// =========================
app.get("/api/notifications", auth, adminOnly, async (req,res)=>{
  try{res.json(await query(`SELECT id,user_id,title,message,type,is_read,created_at FROM notifications ORDER BY id DESC LIMIT 100`));}
  catch(err){console.error(err);res.status(500).json({error:"Failed to get notifications"});}
});

app.get("/api/my-notifications", auth, async (req,res)=>{
  try{res.json(await query(`SELECT id,title,message,type,is_read,created_at FROM notifications WHERE user_id=? ORDER BY id DESC LIMIT 100`,[req.user.id]));}
  catch(err){console.error(err);res.status(500).json({error:"Failed to get notifications"});}
});

// Availability is used by the driver workflow; admin can also use the same endpoint.
async function driverOrAdmin(req,res,next){
  if(req.user?.role!=="driver"&&req.user?.role!=="admin")return res.status(403).json({error:"Driver or admin access required"});
  next();
}

app.put("/api/drivers/:id/availability", auth, driverOrAdmin, async (req,res)=>{
  const id=Number(req.params.id); const {availability}=req.body;
  if(!["online","offline","busy"].includes(availability))return res.status(400).json({error:"Invalid availability"});
  if(req.user.role==="driver"&&Number(req.user.id)!==id)return res.status(403).json({error:"You can only change your own availability"});
  try{const r=await query(`UPDATE users SET availability=? WHERE id=? AND role='driver'`,[availability,id]);if(!r.affectedRows)return res.status(404).json({error:"Driver not found"});res.json({message:"Availability updated",availability});}
  catch(err){console.error(err);res.status(500).json({error:"Failed to update availability"});}
});

// Start only after schema compatibility checks.
db.connect(async (err)=>{
  if(err){console.error("MySQL connection failed:",err.message);return;}
  console.log("MySQL connected successfully!");
  try { await ensureSchema(); console.log("Sprint 2 + Sprint 3 schema ready."); }
  catch(e){ console.error("Schema preparation failed:",e.message); }
});

app.listen(PORT,()=>console.log(`Server running on http://localhost:${PORT}`));
