#!/usr/bin/env python3
from datetime import datetime, timezone
import os


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


print(f"[dummy-report-b] start={now_iso()}")
for key in ["AWS_REGION", "FF_ENABLE_OTEL", "REDIS_ENABLED"]:
    print(f"[dummy-report-b] {key}={os.getenv(key, 'unset')}")
print(f"[dummy-report-b] end={now_iso()}")
