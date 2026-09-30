"""Shared test helper: connect to the warehouse using the same env vars as dlt/dbt, or skip the test."""

import os

import psycopg
import pytest


def connect_or_skip(role: str = "admin") -> psycopg.Connection:
    env = os.environ
    user_key, pw_key = (
        ("POSTGRES_ADMIN_USER", "POSTGRES_ADMIN_PASSWORD")
        if role == "admin"
        else ("POSTGRES_READER_USER", "POSTGRES_READER_PASSWORD")
    )
    if not env.get(pw_key):
        pytest.skip(f"{pw_key} not set: warehouse tests need `make test` with a .env")
    try:
        return psycopg.connect(
            host=env.get("POSTGRES_HOST", "localhost"),
            port=int(env.get("POSTGRES_PORT", "5433")),
            dbname=env.get("POSTGRES_DB", "juan"),
            user=env[user_key],
            password=env[pw_key],
            connect_timeout=5,
        )
    except psycopg.OperationalError as exc:
        pytest.skip(f"warehouse unreachable: {exc}")
