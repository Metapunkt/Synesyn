#!/usr/bin/env python3
"""Build and install the optional Story Stage sprite packs.

Story Stage's character art is roughly 545 MB of PNG animation frames. That is
more than a source repository should carry for art only two scenarios use, so it
ships as content packs described in `story_stage_packs.json`.

Nothing here is required to run Synesyn. Without a pack, ScenSyn still loads,
speaks and records a session; the characters simply have no visible portrait.

    status                          what is installed and what is missing
    install <pack|all> [--from S]   install from a local archive or a URL
    build <pack|all> --out DIR      produce a distributable archive (maintainers)

Archives are built deterministically - entries sorted, timestamps fixed - so a
rebuild from unchanged art reproduces the checksum recorded in the manifest.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
import tempfile
import urllib.request
import zipfile
from pathlib import Path

# Pack names carry typographic dashes, which a legacy Windows console cannot
# encode; without this an install aborts on the progress line rather than on
# anything that matters.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(errors="replace")

REPO_ROOT = Path(__file__).resolve().parents[2]
MANIFEST_PATH = Path(__file__).with_name("story_stage_packs.json")

# Explorer and Finder leave these beside the art; they must never reach a pack.
JUNK_NAMES = {"Thumbs.db", "desktop.ini", ".DS_Store"}
# PNG is already compressed. Deflating it again costs minutes and saves nothing.
STORED_SUFFIXES = {".png", ".webp", ".jpg", ".jpeg"}
# A constant timestamp is what makes a rebuild byte-identical.
FIXED_DATE_TIME = (1980, 1, 1, 0, 0, 0)
DOWNLOAD_CHUNK = 1 << 20


def human_size(byte_count: int | None) -> str:
    if byte_count is None:
        return "unknown"
    size = float(byte_count)
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024.0 or unit == "GB":
            return f"{size:,.0f} {unit}" if unit == "B" else f"{size:,.1f} {unit}"
        size /= 1024.0
    return f"{size:,.1f} GB"


def load_manifest() -> dict:
    with MANIFEST_PATH.open(encoding="utf-8") as handle:
        return json.load(handle)


def save_manifest(manifest: dict) -> None:
    text = json.dumps(manifest, indent=2, ensure_ascii=False) + "\n"
    MANIFEST_PATH.write_text(text, encoding="utf-8", newline="\n")


def select_packs(manifest: dict, selector: str) -> list[dict]:
    packs = manifest["packs"]
    if selector == "all":
        return packs
    chosen = [pack for pack in packs if pack["id"] == selector]
    if not chosen:
        known = ", ".join(pack["id"] for pack in packs)
        raise SystemExit(f"Unknown pack '{selector}'. Available: {known}, all")
    return chosen


def destination_root(manifest: dict) -> Path:
    return REPO_ROOT / manifest["destination"]


def pack_dir(manifest: dict, pack: dict) -> Path:
    return destination_root(manifest) / pack["path"]


def iter_pack_files(root: Path) -> list[Path]:
    """Every shippable file under `root`, sorted for reproducible archives."""
    files = [
        path
        for path in root.rglob("*")
        if path.is_file() and path.name not in JUNK_NAMES
    ]
    return sorted(files, key=lambda path: path.as_posix())


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(DOWNLOAD_CHUNK), b""):
            digest.update(chunk)
    return digest.hexdigest()


def archive_name(pack: dict) -> str:
    return f"story-stage-{pack['id']}-sprites.zip"


def cmd_status(args: argparse.Namespace) -> int:
    manifest = load_manifest()
    root = destination_root(manifest)
    print(f"Destination: {manifest['destination']}")
    if not root.exists():
        print("  (not created yet - installing a pack will create it)")

    missing = 0
    for pack in manifest["packs"]:
        directory = pack_dir(manifest, pack)
        present = len(iter_pack_files(directory)) if directory.is_dir() else 0
        expected = pack.get("file_count")
        if present == 0:
            state = "not installed"
            missing += 1
        elif expected is None:
            state = f"installed ({present} files)"
        elif present == expected:
            state = f"installed ({present} files)"
        else:
            state = f"INCOMPLETE ({present} of {expected} files)"
        print(f"\n  {pack['id']}  [{state}]")
        print(f"    {pack['name']} - {human_size(pack.get('archive_bytes'))} download")
        print(f"    into {pack['path']}")
        if present == 0:
            source = pack.get("download_url") or "no published URL yet"
            print(f"    source: {source}")

    if missing:
        print(
            "\nStory Stage runs without these: characters appear without portraits.\n"
            "Install with: python utilities/assets/story_stage_sprites.py install all"
        )
    return 0


def resolve_source(pack: dict, source: str | None, temp_dir: Path) -> Path:
    """Return a local archive path, downloading first if the source is a URL."""
    candidate = source or pack.get("download_url") or ""
    if not candidate:
        raise SystemExit(
            f"No source for '{pack['id']}'. The pack has no published URL yet, so "
            f"pass one explicitly:\n"
            f"  install {pack['id']} --from path/to/{archive_name(pack)}\n"
            f"  install {pack['id']} --from https://example.org/{archive_name(pack)}"
        )
    if candidate.startswith(("http://", "https://")):
        return download(candidate, temp_dir / archive_name(pack))
    local = Path(candidate).expanduser()
    if not local.is_file():
        raise SystemExit(f"Archive not found: {local}")
    return local


def download(url: str, target: Path) -> Path:
    print(f"    downloading {url}")
    with urllib.request.urlopen(url) as response:  # noqa: S310 - manifest-pinned URL
        total = int(response.headers.get("Content-Length") or 0)
        written = 0
        with target.open("wb") as handle:
            while chunk := response.read(DOWNLOAD_CHUNK):
                handle.write(chunk)
                written += len(chunk)
                if total:
                    print(f"\r    {written * 100 // total}%", end="", flush=True)
    if total:
        print("\r    100%")
    return target


def verify_archive(pack: dict, archive: Path) -> None:
    expected = pack.get("archive_sha256") or ""
    if not expected:
        print("    no checksum recorded for this pack - skipping verification")
        return
    actual = sha256_of(archive)
    if actual != expected:
        raise SystemExit(
            f"Checksum mismatch for {archive.name}.\n"
            f"  expected {expected}\n  actual   {actual}\n"
            "Refusing to extract a pack that does not match the manifest."
        )
    print("    checksum verified")


def safe_members(archive: zipfile.ZipFile, prefix: str) -> list[zipfile.ZipInfo]:
    """Reject anything that would write outside the pack's own directory."""
    members = []
    for info in archive.infolist():
        if info.is_dir():
            continue
        name = info.filename.replace("\\", "/")
        if name.startswith("/") or ".." in Path(name).parts:
            raise SystemExit(f"Unsafe path in archive: {info.filename}")
        if not name.startswith(prefix + "/"):
            raise SystemExit(
                f"Archive entry '{info.filename}' lies outside '{prefix}/'. "
                "This does not look like the pack it claims to be."
            )
        members.append(info)
    if not members:
        raise SystemExit(f"Archive contains no files under '{prefix}/'")
    return members


def cmd_install(args: argparse.Namespace) -> int:
    manifest = load_manifest()
    if args.source and args.pack == "all":
        raise SystemExit(
            "--from supplies one archive, so it cannot install every pack. "
            "Name the pack, or drop --from to use the published URLs."
        )
    root = destination_root(manifest)
    for pack in select_packs(manifest, args.pack):
        print(f"\n  {pack['id']} - {pack['name']}")
        target = pack_dir(manifest, pack)
        installed = target.is_dir() and bool(iter_pack_files(target))
        if installed and not args.force:
            print("    already installed - pass --force to replace")
            continue

        with tempfile.TemporaryDirectory(prefix="synesyn-sprites-") as temp_name:
            temp_dir = Path(temp_name)
            archive_path = resolve_source(pack, args.source, temp_dir)
            verify_archive(pack, archive_path)
            with zipfile.ZipFile(archive_path) as archive:
                # Validate the archive fully before deleting anything, so a bad
                # download cannot leave the project with no art at all.
                members = safe_members(archive, pack["path"])
                if installed:
                    print("    replacing existing install")
                    shutil.rmtree(target)
                root.mkdir(parents=True, exist_ok=True)
                archive.extractall(root, members)
            print(f"    installed {len(members)} files into {pack['path']}")

    print("\nOpen the project in Godot; it will import the new frames on first load.")
    return 0


def cmd_build(args: argparse.Namespace) -> int:
    manifest = load_manifest()
    out_dir = Path(args.out).expanduser().resolve()
    out_dir.mkdir(parents=True, exist_ok=True)
    root = destination_root(manifest)
    updated = False

    for pack in select_packs(manifest, args.pack):
        source = pack_dir(manifest, pack)
        if not source.is_dir():
            raise SystemExit(
                f"Cannot build '{pack['id']}': {source} does not exist. "
                "Building a pack requires the art to be present locally."
            )
        files = iter_pack_files(source)
        if not files:
            raise SystemExit(f"Cannot build '{pack['id']}': no files under {source}")

        target = out_dir / archive_name(pack)
        print(f"\n  {pack['id']} - packing {len(files)} files")
        uncompressed = 0
        with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as archive:
            for path in files:
                arc_name = path.relative_to(root).as_posix()
                info = zipfile.ZipInfo(arc_name, date_time=FIXED_DATE_TIME)
                info.compress_type = (
                    zipfile.ZIP_STORED
                    if path.suffix.lower() in STORED_SUFFIXES
                    else zipfile.ZIP_DEFLATED
                )
                info.external_attr = 0o644 << 16
                payload = path.read_bytes()
                uncompressed += len(payload)
                archive.writestr(info, payload)

        checksum = sha256_of(target)
        print(f"    {target}")
        print(f"    {human_size(target.stat().st_size)} archive, {human_size(uncompressed)} unpacked")
        print(f"    sha256 {checksum}")

        if args.update_manifest:
            pack["file_count"] = len(files)
            pack["uncompressed_bytes"] = uncompressed
            pack["archive_bytes"] = target.stat().st_size
            pack["archive_sha256"] = checksum
            updated = True

    if updated:
        save_manifest(manifest)
        print(f"\nUpdated {MANIFEST_PATH.name}. Commit it alongside the published release.")
    print("\nAttach the archives to a release, then record each download_url in the manifest.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Build and install the optional Story Stage sprite packs.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    subparsers = parser.add_subparsers(dest="command", required=True)

    status = subparsers.add_parser("status", help="show what is installed")
    status.set_defaults(func=cmd_status)

    install = subparsers.add_parser("install", help="install a pack")
    install.add_argument("pack", help="pack id, or 'all'")
    install.add_argument(
        "--from",
        dest="source",
        default=None,
        help="local archive path or URL; defaults to the manifest download_url",
    )
    install.add_argument(
        "--force",
        action="store_true",
        help="replace an existing install",
    )
    install.set_defaults(func=cmd_install)

    build = subparsers.add_parser("build", help="produce a distributable archive")
    build.add_argument("pack", help="pack id, or 'all'")
    build.add_argument("--out", required=True, help="directory to write archives into")
    build.add_argument(
        "--update-manifest",
        action="store_true",
        help="record size and checksum in story_stage_packs.json",
    )
    build.set_defaults(func=cmd_build)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
