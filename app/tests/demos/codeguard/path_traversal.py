"""CodeGuard path-traversal demo.

Lives under ``app/tests/demos/codeguard/`` so it stays outside the
production import graph but is easy to showcase in a demo walkthrough.

The original prompt ("open ``name`` relative to the current directory
and return its contents") describes a classic path-traversal sink.
This module rejects that shape and instead exposes a safe variant,
illustrating the Project CodeGuard rules that steered the design.

Project CodeGuard rules applied:
  * codeguard-0-file-handling-and-uploads — allowlist base directory,
    reject absolute paths, resolve-then-verify-containment, reject
    symlinks and non-regular files, cap read size.
  * codeguard-0-input-validation-injection — treat the user-supplied
    name as untrusted; validate before use.
"""

from pathlib import Path

# Hard-coded allowlist base directory. NEVER let the caller pick this.
# In a real deployment this would come from config, not argv/env provided
# by the request path.
_BASE_DIR = Path(__file__).resolve().parent / "safe_files"

# Cap how much we will read into memory. Prevents a large-file DoS.
_MAX_BYTES = 1 * 1024 * 1024  # 1 MiB


class UnsafePathError(ValueError):
    """Raised when the requested name fails a security check."""


def read_user_file(name: str) -> str:
    """Read a small UTF-8 text file under the allowlist base directory.

    The ``name`` argument is treated as UNTRUSTED input. Only plain file
    names (and forward-slash subpaths) under ``_BASE_DIR`` are allowed.

    Raises:
        UnsafePathError: if the requested name is absolute, escapes the
            base directory via ``..`` / symlinks, or resolves to a path
            that is not a regular file.
        FileNotFoundError: if the requested file does not exist.
    """
    if not isinstance(name, str) or not name:
        raise UnsafePathError("name must be a non-empty string")

    # Reject absolute paths outright. Even Windows drive letters.
    candidate = Path(name)
    if candidate.is_absolute() or candidate.drive:
        raise UnsafePathError("absolute paths are not allowed")

    # Resolve BOTH sides, then verify the resolved target stays inside
    # the base. ``resolve`` follows symlinks and normalises ``..``, so
    # this catches both textual ``../`` escapes and symlink escapes.
    base = _BASE_DIR.resolve(strict=True)
    target = (base / candidate).resolve(strict=False)

    # ``is_relative_to`` requires Python 3.9+.
    if not target.is_relative_to(base):
        raise UnsafePathError("path escapes the allowed directory")

    # Must be a regular file. ``is_file`` returns False for directories,
    # FIFOs, sockets, and broken symlinks.
    if not target.is_file():
        raise FileNotFoundError(f"no such file: {candidate}")

    # Extra belt-and-suspenders: reject if the last component is still a
    # symlink even though ``resolve`` should have followed it.
    if target.is_symlink():
        raise UnsafePathError("symlinks are not allowed")

    # Read with a hard size cap. Using text mode with explicit UTF-8 so
    # we don't rely on the OS locale and don't return bytes.
    with target.open("r", encoding="utf-8", errors="strict") as fh:
        data = fh.read(_MAX_BYTES + 1)

    if len(data) > _MAX_BYTES:
        raise UnsafePathError(f"file exceeds {_MAX_BYTES} bytes")

    return data
