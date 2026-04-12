"""Pytest fixtures shared across the test suite.

Most tests don't need Claude or the embedding model running for real —
we patch those out at import time so tests stay fast and offline.
"""

from __future__ import annotations

import sys
from pathlib import Path

# Make the `app/` directory importable so tests can `from main import ...`
APP_ROOT = Path(__file__).resolve().parent.parent
if str(APP_ROOT) not in sys.path:
    sys.path.insert(0, str(APP_ROOT))
