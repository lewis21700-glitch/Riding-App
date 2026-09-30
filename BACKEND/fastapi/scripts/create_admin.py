from __future__ import annotations

import getpass
import re

from app.main import engine, password_hash
from sqlalchemy import text


def main() -> None:
    email = input("Admin email: ").strip().lower()
    name = input("Admin name: ").strip()
    password = getpass.getpass("Admin password (minimum 12 characters): ")
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", email):
        raise SystemExit("Enter a valid email address.")
    if len(name) < 2 or len(password) < 12:
        raise SystemExit("Name must be at least 2 characters; password must be at least 12.")
    with engine.begin() as conn:
        existing = conn.execute(
            text("SELECT id,role FROM users WHERE email=:email"), {"email": email}
        ).mappings().first()
        if existing:
            raise SystemExit(f"That email already belongs to a {existing['role']}; nothing changed.")
        conn.execute(
            text("INSERT INTO users(name,email,phone,password,role,availability) "
                 "VALUES(:name,:email,'',:password,'admin',NULL)"),
            {"name": name, "email": email, "password": password_hash.hash(password)},
        )
    print("Admin account created.")


if __name__ == "__main__":
    main()
