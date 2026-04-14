"""Pytest proof that the CodeGuard-guided implementation holds up.

Each test exercises one CodeGuard rule from ``path_traversal.py`` and
asserts the function rejects (or accepts) the input as designed.
"""

from __future__ import annotations

from pathlib import Path

import pytest

from tests.demos.codeguard import path_traversal as pt


@pytest.fixture()
def base_dir(tmp_path, monkeypatch) -> Path:
    """Point the module at a throwaway base dir for each test."""
    safe = tmp_path / "safe_files"
    safe.mkdir()
    monkeypatch.setattr(pt, "_BASE_DIR", safe)
    return safe


def test_happy_path_reads_file(base_dir: Path) -> None:
    (base_dir / "hello.txt").write_text("hi, honey", encoding="utf-8")
    assert pt.read_user_file("hello.txt") == "hi, honey"


def test_subdirectory_read_allowed(base_dir: Path) -> None:
    sub = base_dir / "docs"
    sub.mkdir()
    (sub / "note.md").write_text("nested", encoding="utf-8")
    assert pt.read_user_file("docs/note.md") == "nested"


def test_parent_traversal_blocked(base_dir: Path) -> None:
    with pytest.raises(pt.UnsafePathError, match="escapes"):
        pt.read_user_file("../../../etc/passwd")


def test_absolute_path_blocked(base_dir: Path) -> None:
    with pytest.raises(pt.UnsafePathError, match="absolute"):
        pt.read_user_file("/etc/passwd")


def test_empty_name_blocked(base_dir: Path) -> None:
    with pytest.raises(pt.UnsafePathError):
        pt.read_user_file("")


def test_non_string_name_blocked(base_dir: Path) -> None:
    with pytest.raises(pt.UnsafePathError):
        pt.read_user_file(None)  # type: ignore[arg-type]


def test_symlink_escape_blocked(base_dir: Path, tmp_path: Path) -> None:
    secret = tmp_path / "secret.txt"
    secret.write_text("do not leak", encoding="utf-8")
    link = base_dir / "escape.txt"
    link.symlink_to(secret)

    with pytest.raises(pt.UnsafePathError, match="escapes"):
        pt.read_user_file("escape.txt")


def test_missing_file_raises_not_found(base_dir: Path) -> None:
    with pytest.raises(FileNotFoundError):
        pt.read_user_file("nope.txt")


def test_size_cap_blocks_large_file(base_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setattr(pt, "_MAX_BYTES", 16)
    (base_dir / "big.txt").write_text("x" * 1024, encoding="utf-8")
    with pytest.raises(pt.UnsafePathError, match="exceeds"):
        pt.read_user_file("big.txt")


def test_directory_rejected_as_not_a_file(base_dir: Path) -> None:
    (base_dir / "sub").mkdir()
    with pytest.raises(FileNotFoundError):
        pt.read_user_file("sub")
