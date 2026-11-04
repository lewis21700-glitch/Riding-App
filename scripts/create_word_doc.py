import docx
from pathlib import Path
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT, WD_ALIGN_VERTICAL
from docx.oxml import parse_xml, OxmlElement
from docx.oxml.ns import nsdecls, qn

def create_document():
    doc = docx.Document()

    # Page setup - 1 inch margins
    sections = doc.sections
    for section in sections:
        section.top_margin = Inches(1.0)
        section.bottom_margin = Inches(1.0)
        section.left_margin = Inches(1.0)
        section.right_margin = Inches(1.0)

    # Palette
    COLOR_PRIMARY = RGBColor(11, 58, 205)     # #0B3ACD
    COLOR_DARK = RGBColor(30, 41, 59)         # #1E293B
    COLOR_MUTED = RGBColor(100, 116, 139)     # #64748B
    HEX_PRIMARY = "0B3ACD"
    HEX_LIGHT_BG = "F1F5F9"
    HEX_CALLOUT_BG = "EEF4FF"

    # Helpers
    def set_cell_background(cell, hex_color):
        shading = parse_xml(f'<w:shd {nsdecls("w")} w:fill="{hex_color}"/>')
        cell._tc.get_or_add_tcPr().append(shading)

    def set_cell_margins(cell, top=100, bottom=100, left=150, right=150):
        tcPr = cell._tc.get_or_add_tcPr()
        tcMar = parse_xml(
            f'<w:tcMar {nsdecls("w")}>'
            f'<w:top w:w="{top}" w:type="dxa"/>'
            f'<w:bottom w:w="{bottom}" w:type="dxa"/>'
            f'<w:left w:w="{left}" w:type="dxa"/>'
            f'<w:right w:w="{right}" w:type="dxa"/>'
            f'</w:tcMar>'
        )
        tcPr.append(tcMar)

    def style_header_cell(cell, text, width=None):
        set_cell_background(cell, HEX_PRIMARY)
        set_cell_margins(cell, top=140, bottom=140, left=160, right=160)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        run = p.add_run(text)
        run.bold = True
        run.font.name = "Calibri"
        run.font.size = Pt(10.5)
        run.font.color.rgb = RGBColor(255, 255, 255)
        if width:
            cell.width = width

    def style_body_cell(cell, text, bold_first_word=False, is_alt=False, width=None):
        if is_alt:
            set_cell_background(cell, HEX_LIGHT_BG)
        set_cell_margins(cell, top=110, bottom=110, left=160, right=160)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        run = p.add_run(text)
        run.font.name = "Calibri"
        run.font.size = Pt(10)
        run.font.color.rgb = COLOR_DARK
        if width:
            cell.width = width

    def add_custom_heading(text, level=1):
        p = doc.add_paragraph()
        p.paragraph_format.keep_with_next = True
        run = p.add_run(text)
        run.bold = True
        run.font.name = "Calibri"
        if level == 1:
            p.paragraph_format.space_before = Pt(18)
            p.paragraph_format.space_after = Pt(6)
            run.font.size = Pt(18)
            run.font.color.rgb = COLOR_PRIMARY
        elif level == 2:
            p.paragraph_format.space_before = Pt(14)
            p.paragraph_format.space_after = Pt(4)
            run.font.size = Pt(14)
            run.font.color.rgb = COLOR_DARK
        elif level == 3:
            p.paragraph_format.space_before = Pt(10)
            p.paragraph_format.space_after = Pt(3)
            run.font.size = Pt(12)
            run.font.color.rgb = COLOR_PRIMARY
        return p

    def add_callout(title, text):
        tbl = doc.add_table(rows=1, cols=1)
        tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
        cell = tbl.cell(0, 0)
        cell.width = Inches(6.5)
        set_cell_background(cell, HEX_CALLOUT_BG)
        set_cell_margins(cell, top=140, bottom=140, left=180, right=180)
        # Left border line
        tcPr = cell._tc.get_or_add_tcPr()
        borders = parse_xml(
            f'<w:tcBorders {nsdecls("w")}>'
            f'<w:left w:val="single" w:sz="24" w:space="0" w:color="{HEX_PRIMARY}"/>'
            f'<w:top w:val="none"/>'
            f'<w:right w:val="none"/>'
            f'<w:bottom w:val="none"/>'
            f'</w:tcBorders>'
        )
        tcPr.append(borders)
        p = cell.paragraphs[0]
        p.paragraph_format.space_after = Pt(2)
        r_title = p.add_run(title + "\n")
        r_title.bold = True
        r_title.font.name = "Calibri"
        r_title.font.size = Pt(10.5)
        r_title.font.color.rgb = COLOR_PRIMARY
        r_text = p.add_run(text)
        r_text.font.name = "Calibri"
        r_text.font.size = Pt(9.5)
        r_text.font.color.rgb = COLOR_DARK
        doc.add_paragraph().paragraph_format.space_after = Pt(4)

    # ==========================
    # TITLE & HEADER
    # ==========================
    title_p = doc.add_paragraph()
    title_p.paragraph_format.space_before = Pt(0)
    title_p.paragraph_format.space_after = Pt(2)
    r_main = title_p.add_run("RideApp Cambodia")
    r_main.bold = True
    r_main.font.name = "Calibri"
    r_main.font.size = Pt(26)
    r_main.font.color.rgb = COLOR_PRIMARY

    sub_p = doc.add_paragraph()
    sub_p.paragraph_format.space_after = Pt(14)
    r_sub = sub_p.add_run("Complete System Architecture, Technical Operations & Implementation Manual")
    r_sub.font.name = "Calibri"
    r_sub.font.size = Pt(13)
    r_sub.font.color.rgb = COLOR_MUTED

    add_callout(
        "Executive Summary",
        "RideApp is an enterprise-grade on-demand ride-hailing and fleet management platform tailored for Cambodia. "
        "It features cross-platform passenger and driver applications, road-following navigation along Phnom Penh streets, "
        "dual-currency pricing (USD & KHR), NBC Bakong KHQR digital payments, and a centralized web operations dashboard."
    )

    # ==========================
    # 1. SYSTEM ARCHITECTURE
    # ==========================
    add_custom_heading("1. High-Level Architecture", level=1)
    doc.add_paragraph(
        "The platform follows a modern, decoupled three-tier architecture ensuring high performance, scalability, "
        "and clear separation of concerns:"
    )

    arch_bullets = [
        ("Client Tier (Mobile & Web):", " A high-performance Flutter application supporting both Passenger and Driver modes, plus a React 19 / Vite Web Portal for operational dispatchers and administrators."),
        ("Application & API Tier:", " A fast asynchronous REST API built with FastAPI (Python 3.12), Pydantic v2 data validation, Argon2id security hashing, and real-time street routing via OSRM."),
        ("Data & Services Tier:", " A relational MySQL 8.0 database engine with connection pooling, Nominatim place search, and OpenStreetMap/CartoDB map tile rendering."),
    ]
    for b_title, b_desc in arch_bullets:
        bp = doc.add_paragraph(style='List Bullet')
        bp.paragraph_format.space_after = Pt(3)
        r1 = bp.add_run(b_title)
        r1.bold = True
        r1.font.name = "Calibri"
        r1.font.size = Pt(10.5)
        r1.font.color.rgb = COLOR_DARK
        r2 = bp.add_run(b_desc)
        r2.font.name = "Calibri"
        r2.font.size = Pt(10.5)
        r2.font.color.rgb = COLOR_DARK

    # Table: Component Overview
    t_comp = doc.add_table(rows=4, cols=3)
    t_comp.alignment = WD_TABLE_ALIGNMENT.CENTER
    headers = ["Subsystem", "Technology Stack", "Core Responsibility"]
    col_w = [Inches(1.8), Inches(1.8), Inches(2.9)]
    for i, h in enumerate(headers):
        style_header_cell(t_comp.cell(0, i), h, col_w[i])

    rows_data = [
        ("Mobile Client (MOBILE/mobile)", "Flutter 3.x, Dart, flutter_map", "Passenger ride booking, fare estimate, street navigation, live GPS driver tracking, trip history."),
        ("Admin Portal (admin)", "React 19, Vite, Tailwind CSS", "Live trip radar, driver status approval, revenue & commission charts, fleet vehicles, payouts."),
        ("API Backend (BACKEND/fastapi)", "FastAPI, SQLAlchemy, PyMySQL", "REST endpoints (:3000), JWT auth, OSRM road coordinates, dual-currency fare math, dispatch engine."),
    ]
    for r_idx, r in enumerate(rows_data, start=1):
        is_alt = (r_idx % 2 == 0)
        for c_idx, val in enumerate(r):
            style_body_cell(t_comp.cell(r_idx, c_idx), val, is_alt=is_alt, width=col_w[c_idx])

    # ==========================
    # 2. DATABASE SCHEMA
    # ==========================
    add_custom_heading("2. Database Architecture (MySQL 8.0)", level=1)
    doc.add_paragraph(
        "The relational database schema is hosted on MySQL 8.0 under the database name 'ride_app'. "
        "It maintains complete referential integrity, indexing for spatial lookups, and transactional audit trails:"
    )

    t_db = doc.add_table(rows=11, cols=3)
    t_db.alignment = WD_TABLE_ALIGNMENT.CENTER
    db_headers = ["Table Name", "Primary Key & Indexes", "Key Fields & Descriptions"]
    db_widths = [Inches(1.8), Inches(1.8), Inches(2.9)]
    for i, h in enumerate(db_headers):
        style_header_cell(t_db.cell(0, i), h, db_widths[i])

    tables_info = [
        ("users", "id (PK)\nemail (Unique)", "Stores credentials, Argon2id password hash, role ('rider', 'driver', 'admin'), availability ('offline', 'available', 'on_ride')."),
        ("vehicles", "id (PK)\nplate_number (Unique)", "Registered driver assets (driver_id, vehicle_type, vehicle_model, plate_number)."),
        ("rides", "id (PK)\nstatus, rider_id, driver_id", "Master trip records: pickup/dest coordinates, road distance, fare, status ('requested' -> 'completed')."),
        ("driver_locations", "driver_id (PK)\nride_id (Index)", "Real-time GPS telemetry: latitude, longitude, heading, updated_at timestamp."),
        ("ride_offers", "ride_id, driver_id (Composite PK)", "Dispatch queue tracking matching offers dispatched to nearby drivers ('offered', 'rejected', 'accepted')."),
        ("ride_events", "id (PK)\nride_id (Index)", "Immutable audit event log tracking actor_id, event_type ('requested', 'accepted', 'completed'), and JSON details."),
        ("ratings", "id (PK)\nuq_ride_rater (Unique)", "Post-trip passenger and driver reviews (score 1-5 stars, optional text comment)."),
        ("notifications", "id (PK)\nuser_id (Index)", "In-app notification inbox messages for trips, driver updates, and administrative alerts."),
        ("push_tokens", "id (PK)\ntoken (Unique)", "Device FCM registration tokens mapped to user accounts for background push delivery."),
        ("payment_intents", "id (PK)\nride_id (Index)", "Bakong NBC KHQR payment intent payloads, QR MD5 hashes, currency, and verification status."),
    ]
    for r_idx, r in enumerate(tables_info, start=1):
        is_alt = (r_idx % 2 == 0)
        for c_idx, val in enumerate(r):
            style_body_cell(t_db.cell(r_idx, c_idx), val, is_alt=is_alt, width=db_widths[c_idx])

    # ==========================
    # 3. CORE BUSINESS WORKFLOWS
    # ==========================
    add_custom_heading("3. Core Business Workflows", level=1)

    # 3.1 Auth
    add_custom_heading("3.1 Authentication & Security (Argon2id + JWT)", level=2)
    doc.add_paragraph(
        "User registration and session management follow zero-trust modern standards:\n"
        "1. Registration (POST /api/register): Normalizes email, validates password length (minimum 8 characters), "
        "and hashes the secret using Argon2id. The user account is saved to MySQL, and an HMAC-SHA256 JWT is returned.\n"
        "2. Login (POST /api/login): Authenticates credentials against Argon2id hashes. Includes automatic backward compatibility "
        "and one-way upgrade for legacy bcrypt entries.\n"
        "3. Role Authorization: Endpoints enforce strict role checks (require_role('admin'), require_role('driver'), or require_role('rider'))."
    )

    # 3.2 Routing & Fare Math
    add_custom_heading("3.2 Street-by-Street Routing & Fare Estimation", level=2)
    doc.add_paragraph(
        "Unlike basic implementations that draw straight lines across buildings, RideApp integrates the Open Source Routing Machine (OSRM) "
        "to calculate true street-level driving directions along Phnom Penh avenues and boulevards:"
    )

    steps_routing = [
        ("Place Search & Landmark Geocoding:", " Passengers type place names (e.g., 'Aeon', 'Central Market') or pick GPS points. The system resolves coordinates via offline landmarks or Nominatim."),
        ("OSRM Road Navigation Engine:", " The backend queries OSRM driving routes (/route/v1/driving/) and receives 75+ exact road-following polyline coordinates, accurate driving distance, and real-time travel duration."),
        ("Dual-Currency Fare Calculation:", " Base fare and per-km pricing are calculated across vehicle types (Car, Comfort, Premium, Tuk Tuk, Motorbike). USD is converted to Cambodian Riel (KHR) at the 4,100 KHR/USD benchmark rate, rounded to the nearest 100 Riel."),
        ("Enhanced Map Styling:", " The Flutter client displays an 8px dark casing border and a vibrant primary navigation gradient pointing towards the red destination marker."),
    ]
    for s_title, s_desc in steps_routing:
        bp = doc.add_paragraph(style='List Bullet')
        bp.paragraph_format.space_after = Pt(2)
        r1 = bp.add_run(s_title)
        r1.bold = True
        r1.font.name = "Calibri"
        r1.font.size = Pt(10)
        r2 = bp.add_run(s_desc)
        r2.font.name = "Calibri"
        r2.font.size = Pt(10)

    # 3.3 Dispatch & Trip Lifecycle
    add_custom_heading("3.3 Spatial Matching & The Complete Ride Lifecycle", level=2)
    doc.add_paragraph(
        "When a passenger requests a ride, the dispatch engine executes a multi-step spatial discovery process:"
    )

    lifecycle_p = doc.add_paragraph()
    lifecycle_p.paragraph_format.space_after = Pt(4)
    steps_txt = (
        "1. Filter Online Drivers: Identifies drivers with availability = 'available' and an approved vehicle matching the ride type.\n"
        "2. 10 km Spatial Haversine Filter: Calculates great-circle distance between driver GPS telemetry and the passenger's pickup location.\n"
        "3. Trip Offer: Creates ride offers. The first eligible driver to accept is assigned the trip.\n"
        "4. Lifecycle Transitions: The ride transitions through: requested -> accepted -> arrived -> ongoing -> completed.\n"
        "5. Live Tracking: The driver's device periodically transmits coordinates to /api/driver-location. The passenger's tracking screen polls /api/rides/{id}/track and updates the taxi icon along the road."
    )
    lifecycle_p.add_run(steps_txt).font.size = Pt(10)

    # 3.4 Payments & Ratings
    add_custom_heading("3.4 Payments (Cash & NBC Bakong KHQR) and Ratings", level=2)
    doc.add_paragraph(
        "Upon arriving at the destination, the trip is finalized via two supported payment mechanisms:\n"
        "• Cash Settlement: The passenger pays in USD or KHR. The driver confirms payment collection and completes the ride.\n"
        "• Bakong KHQR: The backend generates an official NBC KHQR payload and QR code. The passenger scans via ABA Mobile, Wing, or Bakong to settle funds digitally.\n"
        "• Rating & Feedback: Passengers submit a 1 to 5 star rating with optional written feedback, recorded in the MySQL ratings table."
    )

    # ==========================
    # 4. ACCESSIBLE PORTALS & ACCOUNTS
    # ==========================
    add_custom_heading("4. Accessible Web Portals & Test Accounts", level=1)

    t_portals = doc.add_table(rows=5, cols=3)
    t_portals.alignment = WD_TABLE_ALIGNMENT.CENTER
    port_headers = ["Interface Name", "Access URL", "Operational Capabilities"]
    port_w = [Inches(1.8), Inches(1.8), Inches(2.9)]
    for i, h in enumerate(port_headers):
        style_header_cell(t_portals.cell(0, i), h, port_w[i])

    portals_data = [
        ("Admin Web Portal", "http://localhost:5173", "Live dispatch monitor, active trip radar, revenue/income charts, driver approval, fleet vehicles, and payouts."),
        ("Mobile Client (Web)", "http://localhost:57496 (or start_mobile_web.bat)", "Complete mobile app experience in Edge/Chrome. Passenger booking, driver toggle, live road tracking, and receipts."),
        ("Swagger API Docs", "http://127.0.0.1:3000/docs", "Interactive OpenAPI documentation playground for executing and testing all backend endpoints."),
        ("Backend Health Check", "http://127.0.0.1:3000/api/health", "Live service probe verifying FastAPI uptime and MySQL connection status ({'status':'ok','database':'connected'})."),
    ]
    for r_idx, r in enumerate(portals_data, start=1):
        is_alt = (r_idx % 2 == 0)
        for c_idx, val in enumerate(r):
            style_body_cell(t_portals.cell(r_idx, c_idx), val, is_alt=is_alt, width=port_w[c_idx])

    doc.add_paragraph().paragraph_format.space_after = Pt(4)
    doc.add_paragraph("Pre-configured accounts ready for immediate testing in MySQL:")

    t_users = doc.add_table(rows=5, cols=4)
    t_users.alignment = WD_TABLE_ALIGNMENT.CENTER
    u_headers = ["Role", "Account Email", "Password", "Recommended Interface"]
    u_w = [Inches(1.3), Inches(2.0), Inches(1.4), Inches(1.8)]
    for i, h in enumerate(u_headers):
        style_header_cell(t_users.cell(0, i), h, u_w[i])

    users_data = [
        ("Administrator", "admin@rideapp.com", "admin123456", "Admin Portal (:5173)"),
        ("Driver", "driver.sokha@rideapp.com", "driver123456", "Mobile App (Driver Mode)"),
        ("Rider (Passenger)", "rider.chenda@rideapp.com", "rider123456", "Mobile App (Rider Mode)"),
        ("Rider (Passenger)", "rider.david@rideapp.com", "rider123456", "Mobile App (Rider Mode)"),
    ]
    for r_idx, r in enumerate(users_data, start=1):
        is_alt = (r_idx % 2 == 0)
        for c_idx, val in enumerate(r):
            style_body_cell(t_users.cell(r_idx, c_idx), val, is_alt=is_alt, width=u_w[c_idx])

    # ==========================
    # 5. HOW TO RUN & TEST
    # ==========================
    add_custom_heading("5. Quick-Start & Verification Commands", level=1)

    add_callout(
        "Starting All Services (1-Click)",
        "Simply double-click start_all.bat in the project root folder. This opens independent Windows Command Prompt windows "
        "for the FastAPI Backend (:3000) and the Vite Admin Portal (:5173). To open the Flutter mobile client in Edge, "
        "double-click start_mobile_web.bat."
    )

    doc.add_paragraph("Automated Testing and Verification Suites:")
    code_samples = [
        ("Backend Unit Tests (Pytest):", "cd BACKEND\\fastapi\npython -m pytest tests/test_api.py -v"),
        ("Live MySQL End-to-End Smoke Test:", "cd BACKEND\\fastapi\npython scripts/e2e_smoke.py --allow-writes"),
        ("Flutter Code Analysis:", "cd MOBILE\\mobile\nflutter analyze --no-fatal-infos"),
    ]
    for c_title, c_code in code_samples:
        p = doc.add_paragraph()
        p.paragraph_format.space_after = Pt(1)
        r = p.add_run(c_title)
        r.bold = True
        r.font.name = "Calibri"
        r.font.size = Pt(10.5)

        # Code block style
        cp = doc.add_paragraph()
        cp.paragraph_format.left_indent = Inches(0.25)
        cp.paragraph_format.space_after = Pt(6)
        rc = cp.add_run(c_code)
        rc.font.name = "Consolas"
        rc.font.size = Pt(9.5)
        rc.font.color.rgb = COLOR_PRIMARY

    # Save
    out_path = Path(__file__).resolve().parents[1] / "docs" / "HOW_IT_WORKS.docx"
    doc.save(out_path)
    print(f"Successfully generated: {out_path}")

if __name__ == "__main__":
    create_document()
