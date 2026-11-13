"""Role catalog and hardware gating for ARK.

Hard limits are deterministic on purpose: a wrong guess here means OOM or a
dead service on a machine nobody can debug. Advice on top of that (what to
choose, what will be slow) is a separate layer and may be LLM-based later.
"""
import json
import os
import pathlib

ROLES_PATH = pathlib.Path(os.environ.get("ARK_ROLES_PATH", "/etc/ark/roles.json"))


def load_catalog(path=ROLES_PATH):
    return json.loads(pathlib.Path(path).read_text())


def _has(hw, req):
    usb = hw["usb"]
    if req == "sdr":
        return bool(usb["sdr"])
    if req == "gps":
        return bool(usb["gps"])
    if req == "serial":
        return bool(usb["serial"] or hw["tty"])
    if req == "serial_or_sdr":
        return bool(usb["serial"] or hw["tty"] or usb["sdr"])
    if req == "avx2":
        return bool(hw["cpu"]["avx2"])
    return False


def evaluate(role, hw, available_packs=()):
    """Return {'status': 'ok'|'warn'|'blocked', 'reasons': [...]} for one role."""
    blocked, warns = [], []
    if hw["ram_gb"] < role["min_ram_gb"]:
        blocked.append(f"RAM {hw['ram_gb']} ГБ < {role['min_ram_gb']} ГБ")
    if role["min_disk_gb"] and hw["max_data_disk_gb"] < role["min_disk_gb"]:
        blocked.append(
            f"нужен диск данных >= {role['min_disk_gb']} ГБ, есть {hw['max_data_disk_gb']} ГБ"
        )
    for req in role["requires"]:
        if not _has(hw, req):
            blocked.append(f"не найдено: {req}")
    for pref in role["prefers"]:
        if pref == "gpu" and hw["gpu"] == "none":
            warns.append("нет GPU, будет медленно")
        elif pref != "gpu" and not _has(hw, pref):
            warns.append(f"желательно: {pref}")
    for pack in role["packs"]:
        if pack not in available_packs:
            warns.append(f"пак '{pack}' не подключён")
    if blocked:
        return {"status": "blocked", "reasons": blocked + warns}
    return {"status": "warn" if warns else "ok", "reasons": warns}


def evaluate_all(catalog, hw, available_packs=()):
    return {r["id"]: evaluate(r, hw, available_packs) for r in catalog["roles"]}
