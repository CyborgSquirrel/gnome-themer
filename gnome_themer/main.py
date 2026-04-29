import logging
import subprocess
import sys
import tomllib
from pathlib import Path

CONFIG_PATH = Path("~/.config/gnome-themer/config.toml").expanduser()

log = logging.getLogger(__name__)


def load_config(path: Path) -> list[dict]:
    with open(path, "rb") as f:
        data = tomllib.load(f)
    return data.get("link", [])


def parse_scheme(raw: str) -> str:
    value = raw.strip().strip("'\"")
    if value == "prefer-dark":
        return "dark"
    if value not in ("default", "prefer-light"):
        log.warning("unknown color-scheme value %r, treating as light", value)
    return "light"


def get_current_scheme() -> str:
    result = subprocess.run(
        ["gsettings", "get", "org.gnome.desktop.interface", "color-scheme"],
        capture_output=True,
        text=True,
        check=True,
    )
    return parse_scheme(result.stdout.strip())


def apply_links(links: list[dict], scheme: str) -> None:
    logging.info("applying scheme %r", scheme)
    for link in links:
        target = Path(link["target"]).expanduser()
        source = Path(link[scheme]).expanduser()

        if not source.exists():
            log.warning("source %r does not exist, skipping", source)
            continue

        if target.exists() and not target.is_symlink():
            log.warning("%r is a regular file, skipping", target)
            continue

        tmp = target.with_name(target.name + ".tmp")
        tmp.symlink_to(source)
        tmp.replace(target)

        if post_apply := link.get("post_apply"):
            log.info("running post_apply hook: %r", post_apply)
            subprocess.run(post_apply, shell=True, check=False)


def watch(links: list[dict]) -> None:
    proc = subprocess.Popen(
        ["gsettings", "monitor", "org.gnome.desktop.interface", "color-scheme"],
        stdout=subprocess.PIPE,
        text=True,
    )
    try:
        for line in proc.stdout:
            line = line.strip()
            if not line or ":" not in line:
                continue
            _, value = line.split(":", 1)
            apply_links(links, parse_scheme(value.strip()))
    finally:
        proc.terminate()
        proc.wait()

    log.error("gsettings monitor exited unexpectedly")
    sys.exit(1)


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s: %(message)s")
    links = load_config(CONFIG_PATH)
    apply_links(links, get_current_scheme())
    watch(links)


if __name__ == "__main__":
    main()
