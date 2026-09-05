#!/usr/bin/env python3
"""Control the Aether theme family: status, rotation timer, favorite sync."""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from collections import Counter
from pathlib import Path

HOME = Path.home()
PLUGIN = HOME / ".config/omarchy/plugins/3v4ng3li0n00.themes"
CONFIG = HOME / ".config/omarchy/theme-rotation.json"
STATE = HOME / ".local/state/omarchy/theme-rotation"
THEMES = HOME / ".config/omarchy/themes"
CURRENT_DIR = HOME / ".local/state/omarchy/current"
THEME_NAME_FILE = CURRENT_DIR / "theme.name"
BACKGROUND_LINK = CURRENT_DIR / "background"
CURRENT_THEME_BGS = CURRENT_DIR / "theme" / "backgrounds"
FAVORITES = HOME / ".config/aether/favorites.json"
WALLHAVEN_CONF = HOME / ".config/aether/wallhaven.json"
SYSTEMD_USER = HOME / ".config/systemd/user"
UNIT = "omarchy-theme-rotate"
UA = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/128.0.0.0 Safari/537.36"
IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".gif", ".bmp", ".webp"}
FAMILY_PREFIX = "aether-"

DEFAULT_SCENE = {
    "map_active": False,
    "chroma_active": False,
    "density": 0.5,
    "key": 0.5,
    "chroma": 0.5,
    "radius": 0.32,
}

DEFAULT_CONFIG = {
    "enabled": False,
    "interval_minutes": 15,
    "scene": json.loads(json.dumps(DEFAULT_SCENE)),
    "themes": {},
}

DENSITY_CALM_MAX = 0.40
DENSITY_PACKED_MIN = 0.70


def dump(obj) -> None:
    json.dump(obj, sys.stdout, indent=2, ensure_ascii=False)
    sys.stdout.write("\n")


def fail(message: str, code: int = 1) -> None:
    dump({"ok": False, "error": message})
    raise SystemExit(code)


def load_config() -> dict:
    if not CONFIG.exists():
        return json.loads(json.dumps(DEFAULT_CONFIG))
    try:
        data = json.loads(CONFIG.read_text())
    except (OSError, json.JSONDecodeError):
        return json.loads(json.dumps(DEFAULT_CONFIG))
    if not isinstance(data, dict):
        return json.loads(json.dumps(DEFAULT_CONFIG))
    out = json.loads(json.dumps(DEFAULT_CONFIG))
    out.update({k: data[k] for k in ("enabled", "interval_minutes", "themes") if k in data})
    if not isinstance(out.get("themes"), dict):
        out["themes"] = {}
    try:
        out["interval_minutes"] = max(1, int(out.get("interval_minutes") or 15))
    except (TypeError, ValueError):
        out["interval_minutes"] = 15
    out["enabled"] = bool(out.get("enabled"))
    scene = json.loads(json.dumps(DEFAULT_SCENE))
    raw_scene = data.get("scene")
    if isinstance(raw_scene, dict):
        scene.update({k: raw_scene[k] for k in DEFAULT_SCENE if k in raw_scene})
        if "map_active" not in raw_scene and raw_scene.get("active"):
            scene["map_active"] = True
            scene["chroma_active"] = True
    scene["map_active"] = bool(scene.get("map_active"))
    scene["chroma_active"] = bool(scene.get("chroma_active"))
    try:
        scene["radius"] = max(0.08, min(1.0, float(scene.get("radius") or 0.32)))
        for axis in ("density", "key", "chroma"):
            scene[axis] = max(0.0, min(1.0, float(scene.get(axis) or 0.5)))
    except (TypeError, ValueError):
        scene = json.loads(json.dumps(DEFAULT_SCENE))
    out["scene"] = scene
    return out


def save_config(cfg: dict) -> None:
    CONFIG.parent.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
    tmp.replace(CONFIG)


def display_name(slug: str) -> str:
    return re.sub(r"(^|-)([a-z])", lambda m: (" " if m.group(1) else "") + m.group(2).upper(), slug).replace("-", " ")


def current_theme() -> str:
    try:
        return THEME_NAME_FILE.read_text().strip()
    except OSError:
        return ""


def current_background_name() -> str:
    try:
        return Path(os.path.realpath(BACKGROUND_LINK)).name
    except OSError:
        return ""


def theme_dir(slug: str) -> Path:
    user = THEMES / slug
    if user.is_dir():
        return user
    return Path()


def parse_accent(colors_path: Path) -> str:
    if not colors_path.is_file():
        return "#888888"
    for line in colors_path.read_text().splitlines():
        if line.strip().startswith("accent"):
            match = re.search(r"#[0-9A-Fa-f]{6}", line)
            if match:
                return match.group(0)
    return "#888888"


def density_label(score: float) -> str:
    if score < DENSITY_CALM_MAX:
        return "calm"
    if score >= DENSITY_PACKED_MIN:
        return "packed"
    return "mid"


def key_label(score: float) -> str:
    if score < 0.35:
        return "dark"
    if score >= 0.65:
        return "light"
    return "dusk"


def chroma_label(score: float) -> str:
    if score < 0.22:
        return "mute"
    if score >= 0.45:
        return "vivid"
    return "tint"


def scene_score(path: Path) -> dict:
    """Three 0–1 axes from the same thumbnail.

    density: 8×8 occupancy of edges (calm → packed)
    key: mean luma (dark → light)
    chroma: mean HSV saturation (mute → vivid)
    """
    from PIL import Image, ImageFilter

    empty = {
        "density": 0.0,
        "occupancy": 0.0,
        "key": 0.0,
        "chroma": 0.0,
        "density_label": "calm",
        "key_label": "dark",
        "chroma_label": "mute",
        "label": "calm",
    }
    try:
        rgb = Image.open(path).convert("RGB")
    except OSError:
        return empty
    rgb.thumbnail((320, 320), Image.Resampling.LANCZOS)
    gray = rgb.convert("L")
    grid = gray.filter(ImageFilter.FIND_EDGES).resize((8, 8), Image.Resampling.BOX)
    cells = [p / 255.0 for p in grid.getdata()]
    occupancy = sum(1 for v in cells if v >= 0.04) / max(len(cells), 1)
    edge_mean = sum(cells) / max(len(cells), 1)
    density = max(0.0, min(1.0, 0.7 * occupancy + 0.3 * min(edge_mean * 8.0, 1.0)))
    luma = list(gray.getdata())
    key = (sum(luma) / max(len(luma), 1)) / 255.0
    sats = [p[1] for p in rgb.convert("HSV").getdata()]
    chroma = (sum(sats) / max(len(sats), 1)) / 255.0
    return {
        "density": round(density, 3),
        "occupancy": round(occupancy, 3),
        "key": round(key, 3),
        "chroma": round(chroma, 3),
        "density_label": density_label(density),
        "key_label": key_label(key),
        "chroma_label": chroma_label(chroma),
        "label": density_label(density),
    }


def density_cache_load() -> dict:
    path = STATE / "density.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError):
        return {}
    return data if isinstance(data, dict) else {}


def density_cache_save(cache: dict) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    tmp = STATE / "density.json.tmp"
    tmp.write_text(json.dumps(cache) + "\n")
    tmp.replace(STATE / "density.json")


def density_for(path: Path, cache: dict | None = None) -> dict:
    try:
        st = path.stat()
        key = f"{path}:{st.st_mtime_ns}:{st.st_size}"
    except OSError:
        return {
            "density": 0.0,
            "occupancy": 0.0,
            "key": 0.0,
            "chroma": 0.0,
            "density_label": "calm",
            "key_label": "dark",
            "chroma_label": "mute",
            "label": "calm",
        }
    store = cache if cache is not None else density_cache_load()
    hit = store.get(key)
    if isinstance(hit, dict) and "density" in hit and "key" in hit and "chroma" in hit:
        return hit
    scored = scene_score(path)
    store[key] = scored
    if cache is None:
        density_cache_save(store)
    return scored


def scene_radius(scene: dict) -> float:
    try:
        return max(0.08, min(1.0, float(scene.get("radius") or 0.32)))
    except (TypeError, ValueError):
        return 0.32


def in_chroma(axes: dict, scene: dict) -> bool:
    if not scene.get("chroma_active"):
        return True
    dc = float(axes.get("chroma") or 0) - float(scene.get("chroma") or 0.5)
    return abs(dc) <= scene_radius(scene)


def in_map(axes: dict, scene: dict) -> bool:
    if not scene.get("map_active"):
        return True
    dd = float(axes.get("density") or 0) - float(scene.get("density") or 0.5)
    dk = float(axes.get("key") or 0) - float(scene.get("key") or 0.5)
    return (dd * dd + dk * dk) ** 0.5 <= scene_radius(scene)


def scene_matches(axes: dict, scene: dict) -> bool:
    return in_chroma(axes, scene) and in_map(axes, scene)


def parse_palette(colors_path: Path) -> list[tuple[int, int, int]]:
    colors: list[tuple[int, int, int]] = []
    if not colors_path.is_file():
        return colors
    for line in colors_path.read_text().splitlines():
        match = re.search(r"#([0-9A-Fa-f]{6})", line)
        if not match:
            continue
        raw = match.group(1)
        colors.append((int(raw[0:2], 16), int(raw[2:4], 16), int(raw[4:6], 16)))
    return colors


def background_files(slug: str) -> list[Path]:
    folder = theme_dir(slug) / "backgrounds"
    if not folder.is_dir():
        return []
    files = [
        p
        for p in folder.iterdir()
        if p.is_file() and p.suffix.lower() in IMAGE_EXTS
    ]
    return sorted(files, key=lambda p: p.name)


def label_for(filename: str) -> str:
    stem = Path(filename).stem
    stem = re.sub(r"^\d+-", "", stem)
    stem = re.sub(r"^wallhaven-", "", stem)
    stem = re.sub(r"_\d+x\d+$", "", stem)
    return stem or filename


def wallhaven_id_from_name(filename: str) -> str | None:
    match = re.search(r"wallhaven-([a-z0-9]+)", filename, re.I)
    return match.group(1).lower() if match else None


def enabled_names(cfg: dict, slug: str, filenames: list[str]) -> set[str]:
    entry = cfg.get("themes", {}).get(slug, {})
    if not isinstance(entry, dict) or "include" not in entry:
        return set(filenames)
    include = entry.get("include") or []
    if not isinstance(include, list):
        return set(filenames)
    return {name for name in include if isinstance(name, str)}


def list_user_themes() -> list[str]:
    if not THEMES.is_dir():
        return []
    slugs = []
    for path in sorted(THEMES.iterdir()):
        if path.is_dir() and (path / "backgrounds").is_dir():
            slugs.append(path.name)
    family = [s for s in slugs if s.startswith(FAMILY_PREFIX)]
    rest = [s for s in slugs if not s.startswith(FAMILY_PREFIX)]
    return family + rest


def status() -> dict:
    cfg = load_config()
    current = current_theme()
    current_bg = current_background_name()
    cache = density_cache_load()
    themes = []
    for slug in list_user_themes():
        files = background_files(slug)
        names = [p.name for p in files]
        enabled = enabled_names(cfg, slug, names)
        directory = theme_dir(slug)
        backgrounds = []
        for path in files:
            dens = density_for(path, cache)
            backgrounds.append(
                {
                    "file": path.name,
                    "label": label_for(path.name),
                    "enabled": path.name in enabled,
                    "active": slug == current and path.name == current_bg,
                    "path": str(path),
                    "density": dens["density"],
                    "key": dens.get("key", 0),
                    "chroma": dens.get("chroma", 0),
                    "density_label": dens.get("density_label") or dens.get("label") or "mid",
                    "key_label": dens.get("key_label") or "dusk",
                    "chroma_label": dens.get("chroma_label") or "tint",
                    "in_chroma": in_chroma(dens, cfg.get("scene") or DEFAULT_SCENE),
                    "in_map": in_map(dens, cfg.get("scene") or DEFAULT_SCENE),
                    "in_scene": scene_matches(dens, cfg.get("scene") or DEFAULT_SCENE),
                }
            )
        themes.append(
            {
                "id": slug,
                "name": display_name(slug),
                "accent": parse_accent(directory / "colors.toml"),
                "preview": str(directory / "preview.jpg")
                if (directory / "preview.jpg").is_file()
                else (str(files[0]) if files else ""),
                "current": slug == current,
                "backgrounds": backgrounds,
            }
        )
    density_cache_save(cache)
    sync_state = {}
    sync_file = STATE / "sync.json"
    if sync_file.is_file():
        try:
            sync_state = json.loads(sync_file.read_text())
        except (OSError, json.JSONDecodeError):
            sync_state = {}
    return {
        "ok": True,
        "current": current,
        "current_name": display_name(current) if current else "",
        "current_bg": current_bg,
        "timer": {
            "enabled": bool(cfg.get("enabled")),
            "interval_minutes": int(cfg.get("interval_minutes") or 15),
            "scene": cfg.get("scene") or json.loads(json.dumps(DEFAULT_SCENE)),
        },
        "sync": {
            "message": sync_state.get("message", ""),
            "added": sync_state.get("added", 0),
            "at": sync_state.get("at", ""),
        },
        "themes": themes,
    }


def run_omarchy(*args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["omarchy", *args],
        capture_output=True,
        text=True,
        check=False,
    )


def set_theme(slug: str) -> dict:
    if not theme_dir(slug).is_dir():
        fail(f"theme not found: {slug}")
    result = run_omarchy("theme", "set", slug)
    if result.returncode != 0:
        fail(result.stderr.strip() or result.stdout.strip() or f"theme set failed: {slug}")
    out = status()
    out["message"] = f"Tema {display_name(slug)}"
    return out


def toggle_bg(slug: str, filename: str) -> dict:
    files = [p.name for p in background_files(slug)]
    if filename not in files:
        fail(f"background not in {slug}: {filename}")
    cfg = load_config()
    enabled = enabled_names(cfg, slug, files)
    if filename in enabled:
        enabled.discard(filename)
    else:
        enabled.add(filename)
    ordered = [name for name in files if name in enabled]
    cfg.setdefault("themes", {}).setdefault(slug, {})["include"] = ordered
    save_config(cfg)
    out = status()
    out["message"] = f"{label_for(filename)} {'on' if filename in enabled else 'off'}"
    return out


def write_units() -> None:
    SYSTEMD_USER.mkdir(parents=True, exist_ok=True)
    ctl = PLUGIN / "scripts" / "ctl.py"
    service = SYSTEMD_USER / f"{UNIT}.service"
    timer = SYSTEMD_USER / f"{UNIT}.timer"
    service.write_text(
        "\n".join(
            [
                "[Unit]",
                "Description=Omarchy theme background rotation",
                "",
                "[Service]",
                "Type=oneshot",
                f"ExecStart=/usr/bin/python3 {ctl} next",
                "",
            ]
        )
    )
    timer.write_text(
        "\n".join(
            [
                "[Unit]",
                "Description=Omarchy theme background rotation timer",
                "",
                "[Timer]",
                "OnStartupSec=1min",
                "OnUnitActiveSec=1min",
                "Persistent=false",
                "AccuracySec=15s",
                "",
                "[Install]",
                "WantedBy=timers.target",
                "",
            ]
        )
    )
    subprocess.run(["systemctl", "--user", "daemon-reload"], check=False, capture_output=True)


def set_timer(enabled: bool | None = None, minutes: int | None = None) -> dict:
    cfg = load_config()
    if minutes is not None:
        cfg["interval_minutes"] = max(1, int(minutes))
    if enabled is not None:
        cfg["enabled"] = bool(enabled)
        if enabled:
            (STATE / "last").unlink(missing_ok=True)
    save_config(cfg)
    write_units()
    if cfg["enabled"]:
        subprocess.run(
            ["systemctl", "--user", "enable", "--now", f"{UNIT}.timer"],
            check=False,
            capture_output=True,
        )
    else:
        subprocess.run(
            ["systemctl", "--user", "disable", "--now", f"{UNIT}.timer"],
            check=False,
            capture_output=True,
        )
    out = status()
    out["message"] = "Rodízio ligado" if cfg["enabled"] else "Rodízio desligado"
    return out


def set_scene(*args: str) -> dict:
    cfg = load_config()
    scene = cfg.setdefault("scene", json.loads(json.dumps(DEFAULT_SCENE)))
    if not args or args[0] in ("off", "reset", "all"):
        scene["map_active"] = False
        scene["chroma_active"] = False
        save_config(cfg)
        out = status()
        out["message"] = "Cena livre"
        return out
    kind = args[0]
    try:
        if kind == "map" and len(args) >= 2 and args[1] in ("off", "reset"):
            scene["map_active"] = False
            save_config(cfg)
            out = status()
            out["message"] = "Mapa livre"
            return out
        if kind == "chroma" and len(args) >= 2 and args[1] in ("off", "reset"):
            scene["chroma_active"] = False
            save_config(cfg)
            out = status()
            out["message"] = "Chroma livre"
            return out
        if kind == "map" and len(args) >= 3:
            scene["density"] = max(0.0, min(1.0, float(args[1])))
            scene["key"] = max(0.0, min(1.0, float(args[2])))
            scene["map_active"] = True
            save_config(cfg)
            out = status()
            out["message"] = f"{density_label(scene['density'])} · {key_label(scene['key'])}"
            return out
        if kind == "chroma" and len(args) >= 2:
            scene["chroma"] = max(0.0, min(1.0, float(args[1])))
            scene["chroma_active"] = True
            save_config(cfg)
            out = status()
            out["message"] = chroma_label(scene["chroma"])
            return out
        if kind.replace(".", "", 1).isdigit() and len(args) >= 2:
            scene["density"] = max(0.0, min(1.0, float(args[0])))
            scene["key"] = max(0.0, min(1.0, float(args[1])))
            scene["map_active"] = True
            if len(args) >= 3:
                scene["chroma"] = max(0.0, min(1.0, float(args[2])))
                scene["chroma_active"] = True
            save_config(cfg)
            out = status()
            out["message"] = f"{density_label(scene['density'])} · {key_label(scene['key'])}"
            return out
    except ValueError:
        fail("scene axes must be numbers 0..1")
    fail("usage: ctl.py set-scene map <density> <key> | chroma <value> | map off | chroma off | off")


def rotate(force: bool = False) -> dict:
    cfg = load_config()
    if not cfg.get("enabled") and not force:
        return {"ok": True, "skipped": "disabled"}
    STATE.mkdir(parents=True, exist_ok=True)
    last_file = STATE / "last"
    now = time.time()
    interval = max(1, int(cfg.get("interval_minutes") or 15)) * 60
    if not force and last_file.is_file():
        try:
            last = float(last_file.read_text().strip())
        except (OSError, ValueError):
            last = 0
        if now - last < interval:
            return {"ok": True, "skipped": "interval"}
    slug = current_theme()
    if not slug:
        return {"ok": True, "skipped": "no-theme"}
    live_dir = CURRENT_THEME_BGS if CURRENT_THEME_BGS.is_dir() else theme_dir(slug) / "backgrounds"
    extras = HOME / ".config/omarchy/backgrounds" / slug
    files: list[Path] = []
    for folder in (extras, live_dir):
        if not folder.is_dir():
            continue
        for path in folder.iterdir():
            if path.is_file() and path.suffix.lower() in IMAGE_EXTS:
                files.append(path)
    files.sort(key=lambda p: p.name)
    names = [p.name for p in background_files(slug)] or [p.name for p in files]
    enabled = enabled_names(cfg, slug, names)
    scene = cfg.get("scene") or DEFAULT_SCENE
    cache = density_cache_load()
    candidates = []
    for path in files:
        if path.name not in enabled:
            continue
        if not scene_matches(density_for(path, cache), scene):
            continue
        candidates.append(path)
    density_cache_save(cache)
    if not candidates:
        return {"ok": True, "skipped": "none-enabled"}
    current_name = current_background_name()
    index = -1
    for i, path in enumerate(candidates):
        if path.name == current_name:
            index = i
            break
    nxt = candidates[0] if index < 0 else candidates[(index + 1) % len(candidates)]
    result = run_omarchy("theme", "bg", "set", str(nxt))
    last_file.write_text(str(now) + "\n")
    if result.returncode != 0:
        fail(result.stderr.strip() or "bg set failed")
    return {"ok": True, "background": nxt.name, "theme": slug}


def write_sync_state(payload: dict) -> None:
    STATE.mkdir(parents=True, exist_ok=True)
    (STATE / "sync.json").write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")


def existing_wallhaven_ids() -> set[str]:
    ids: set[str] = set()
    for slug in list_user_themes():
        for path in background_files(slug):
            wid = wallhaven_id_from_name(path.name)
            if wid:
                ids.add(wid)
    return ids


def wallhaven_api_key() -> str:
    if not WALLHAVEN_CONF.is_file():
        return ""
    try:
        data = json.loads(WALLHAVEN_CONF.read_text())
    except (OSError, json.JSONDecodeError):
        return ""
    return str(data.get("apiKey") or "")


def http_json(url: str) -> dict:
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode())


def download_file(url: str, dest: Path) -> None:
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    cmd = [
        "curl",
        "-fL",
        "--retry",
        "3",
        "--retry-delay",
        "2",
        "-A",
        UA,
        "--connect-timeout",
        "20",
        "-o",
        str(tmp),
        url,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0 or not tmp.is_file() or tmp.stat().st_size < 10_000:
        tmp.unlink(missing_ok=True)
        raise RuntimeError(f"download failed: {dest.name}")
    tmp.replace(dest)


def image_palette(path: Path) -> list[tuple[int, int, int, float]]:
    from PIL import Image

    image = Image.open(path).convert("RGB")
    image = image.resize((64, 64), Image.Resampling.BOX)
    quantized = image.quantize(colors=12, method=Image.Quantize.MEDIANCUT)
    palette = quantized.getpalette() or []
    counts = Counter(quantized.getdata())
    total = sum(counts.values()) or 1
    colors = []
    for idx, count in counts.most_common(8):
        r, g, b = palette[idx * 3 : idx * 3 + 3]
        colors.append((r, g, b, count / total))
    return colors


def color_distance(a: tuple[int, int, int], b: tuple[int, int, int]) -> float:
    return ((a[0] - b[0]) ** 2 + (a[1] - b[1]) ** 2 + (a[2] - b[2]) ** 2) ** 0.5


def assign_theme(thumb: Path, family: dict[str, list[tuple[int, int, int]]]) -> str:
    colors = image_palette(thumb)
    chromatic = [c for c in colors if max(c[0], c[1], c[2]) - min(c[0], c[1], c[2]) > 18 and (c[0] + c[1] + c[2]) / 3 > 18]
    if not chromatic:
        chromatic = colors[:3]
    best_slug = next(iter(family))
    best_score = 1e9
    for slug, palette in family.items():
        if not palette:
            continue
        score = 0.0
        weight = 0.0
        for r, g, b, frac in chromatic:
            nearest = min(color_distance((r, g, b), swatch) for swatch in palette)
            score += nearest * frac
            weight += frac
        score = score / (weight or 1)
        if score < best_score:
            best_score = score
            best_slug = slug
    return best_slug


def next_index(slug: str) -> int:
    highest = 0
    for path in background_files(slug):
        match = re.match(r"^(\d+)-", path.name)
        if match:
            highest = max(highest, int(match.group(1)))
    return highest + 1


def copy_into_current_if_needed(slug: str, src: Path) -> None:
    if current_theme() != slug or not CURRENT_THEME_BGS.is_dir():
        return
    dest = CURRENT_THEME_BGS / src.name
    if dest.exists():
        return
    try:
        os.link(src, dest)
    except OSError:
        shutil.copy2(src, dest)


def sync_favorites() -> dict:
    if not FAVORITES.is_file():
        fail("Aether favorites.json not found")
    try:
        favorites = json.loads(FAVORITES.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        fail(f"favorites unreadable: {exc}")
    if not isinstance(favorites, list):
        fail("favorites.json is not a list")

    family_slugs = [s for s in list_user_themes() if s.startswith(FAMILY_PREFIX)]
    if not family_slugs:
        fail("no aether-* themes to allocate into")
    family_palettes = {slug: parse_palette(theme_dir(slug) / "colors.toml") for slug in family_slugs}
    known = existing_wallhaven_ids()
    api_key = wallhaven_api_key()
    staging = Path("/tmp/omarchy-theme-sync")
    staging.mkdir(exist_ok=True)

    added: list[dict] = []
    skipped = 0
    errors: list[str] = []

    for item in favorites:
        if not isinstance(item, dict):
            continue
        wid = str(item.get("id") or "").lower()
        if not wid:
            continue
        if wid in known:
            skipped += 1
            continue
        url = str(item.get("path") or "")
        try:
            meta_url = f"https://wallhaven.cc/api/v1/w/{wid}"
            if api_key:
                meta_url += f"?apikey={api_key}"
            meta = http_json(meta_url).get("data") or {}
            url = str(meta.get("path") or url)
            thumbs = meta.get("thumbs") or {}
            thumb_url = str(thumbs.get("large") or thumbs.get("small") or "")
            if not url:
                raise RuntimeError("no wallpaper url")
            ext = Path(url).suffix.lower() or ".jpg"
            thumb_path = staging / f"{wid}-thumb.jpg"
            if thumb_url:
                try:
                    download_file(thumb_url.replace("/small/", "/lg/"), thumb_path)
                except RuntimeError:
                    download_file(thumb_url, thumb_path)
            else:
                # fall back to a tiny sample of the original
                download_file(url, staging / f"{wid}{ext}")
                thumb_path = staging / f"{wid}{ext}"
            slug = assign_theme(thumb_path, family_palettes)
            dest_dir = theme_dir(slug) / "backgrounds"
            dest_dir.mkdir(parents=True, exist_ok=True)
            dest = dest_dir / f"{next_index(slug)}-wallhaven-{wid}{ext}"
            if thumb_path.name.endswith(ext) and thumb_path.stat().st_size > 200_000:
                shutil.copy2(thumb_path, dest)
            else:
                download_file(url, dest)
            copy_into_current_if_needed(slug, dest)
            preview = theme_dir(slug) / "preview.jpg"
            if not preview.exists() and thumb_path.exists():
                shutil.copy2(thumb_path, preview)
            known.add(wid)
            added.append({"id": wid, "theme": slug, "file": dest.name})
            time.sleep(0.35)
        except Exception as exc:  # noqa: BLE001 — keep going through the rest of the list
            errors.append(f"{wid}: {exc}")

    message = f"{len(added)} novos" if added else "nada novo"
    if errors:
        message += f", {len(errors)} falhas"
    payload = {
        "ok": True,
        "added": len(added),
        "skipped": skipped,
        "items": added,
        "errors": errors[:8],
        "message": message,
        "at": time.strftime("%Y-%m-%d %H:%M"),
    }
    write_sync_state(payload)
    if any(item["theme"] == current_theme() for item in added):
        run_omarchy("theme", "bg", "cache")
    out = status()
    out["message"] = message
    out["added_items"] = added
    out["errors"] = errors[:8]
    return out


def main(argv: list[str]) -> None:
    if not argv:
        dump(status())
        return
    cmd = argv[0]
    if cmd in ("status", "show"):
        dump(status())
        return
    if cmd == "set-theme":
        if len(argv) < 2:
            fail("usage: ctl.py set-theme <slug>")
        dump(set_theme(argv[1]))
        return
    if cmd == "toggle-bg":
        if len(argv) < 3:
            fail("usage: ctl.py toggle-bg <slug> <filename>")
        dump(toggle_bg(argv[1], argv[2]))
        return
    if cmd == "set-scene":
        dump(set_scene(*argv[1:]))
        return
    if cmd == "set-timer":
        enabled = None
        minutes = None
        for arg in argv[1:]:
            if arg in ("on", "true", "1"):
                enabled = True
            elif arg in ("off", "false", "0"):
                enabled = False
            elif arg.isdigit():
                minutes = int(arg)
            else:
                fail(f"unknown set-timer arg: {arg}")
        dump(set_timer(enabled, minutes))
        return
    if cmd == "next":
        dump(rotate(force="--force" in argv[1:]))
        return
    if cmd in ("sync", "update"):
        dump(sync_favorites())
        return
    fail(f"unknown command: {cmd}")


if __name__ == "__main__":
    main(sys.argv[1:])
