#!/usr/bin/env python3
from datetime import datetime, timezone
import os


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


print(f"[dummy-report-a] start={now_iso()}")
print(f"[dummy-report-a] env={os.getenv('NOTIFY_ENVIRONMENT', 'unset')}")
print(f"[dummy-report-a] api={os.getenv('API_HOST_NAME', 'unset')}")
print(f"[dummy-report-a] end={now_iso()}")
