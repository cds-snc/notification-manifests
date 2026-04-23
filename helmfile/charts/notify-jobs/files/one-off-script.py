#!/usr/bin/env python3
import os
import socket
import time
from datetime import datetime, timezone


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


print(f"[one-off-python] start: {now_iso()}")
print(f"[one-off-python] host: {socket.gethostname()}")

for env_name in [
    "NOTIFY_ENVIRONMENT",
    "API_HOST_NAME",
    "AWS_REGION",
    "REDIS_ENABLED",
    "FF_ENABLE_OTEL",
]:
    print(f"[one-off-python] env {env_name}={os.getenv(env_name, 'unset')}")

for secret_name in [
    "SQLALCHEMY_DATABASE_URI",
    "SECRET_KEY",
    "ADMIN_CLIENT_SECRET",
    "REDIS_URL",
    "WAF_SECRET",
]:
    is_set = bool(os.getenv(secret_name))
    print(f"[one-off-python] secret {secret_name} is {'set' if is_set else 'MISSING'}")

sleep_seconds = int(os.getenv("DUMMY_SLEEP_SECONDS", "120"))
heartbeat = 30
elapsed = 0

print(f"[one-off-python] simulating long-running work for {sleep_seconds}s")
while elapsed < sleep_seconds:
    remaining = sleep_seconds - elapsed
    print(f"[one-off-python] heartbeat elapsed={elapsed}s remaining={remaining}s")
    step = min(heartbeat, remaining)
    time.sleep(step)
    elapsed += step

print(f"[one-off-python] complete: {now_iso()}")
