# gnome-themer — Design Document

## Overview

A lightweight Python daemon that watches the GNOME color-scheme setting and
maintains symlinks so that application theme files always reflect the current
light/dark mode.

---

## Problem

Many applications load their theme from a fixed file path at startup or on
config reload. There is no standard mechanism for them to react to the GNOME
color-scheme setting. By managing symlinks at the right paths, we can give any
application seamless light/dark switching without patching it.

---

## Architecture

```
gsettings monitor          Python daemon          config file (TOML)
org.gnome.desktop  ──────► parse event      ◄───  [[link]] entries
  .interface              apply symlinks
  color-scheme
```

### Components

1. **Config file** — TOML, defines symlink targets and their per-theme sources.
2. **Python script** — reads config, applies symlinks on startup, then enters a
   watch loop reacting to `gsettings monitor` output.
3. **systemd user service** — keeps the script running, restarts on failure.
4. **Home-manager module** — declares the service and generates the config file
   from Nix options.

---

## Config File Format

Location: `~/.config/gnome-themer/config.toml`

```toml
[[link]]
target = "~/.config/alacritty/theme.toml"
dark   = "~/.config/alacritty/themes/catppuccin-mocha.toml"
light  = "~/.config/alacritty/themes/catppuccin-latte.toml"

[[link]]
target = "~/.config/waybar/style.css"
dark   = "~/.config/waybar/themes/dark.css"
light  = "~/.config/waybar/themes/light.css"
```

Rules:
- Paths may use `~` (expanded at runtime).
- `dark` and `light` must be regular files; they are never modified.
- `target` is always a symlink managed exclusively by this tool. If `target`
  exists as a regular file on first run, the service logs a warning and skips
  that entry rather than silently replacing it.

---

## Color Scheme Values

`gsettings get org.gnome.desktop.interface color-scheme` returns one of:

| Value            | Meaning      |
|------------------|--------------|
| `'default'`      | light        |
| `'prefer-light'` | light        |
| `'prefer-dark'`  | dark         |

Anything unrecognised is treated as light (safe default).

---

## Script Behaviour

### Startup sequence

1. Load and validate config (exit with error on malformed TOML or missing
   source files).
2. Read current color scheme via `gsettings get`.
3. Apply all symlinks for the current scheme.
4. Spawn `gsettings monitor org.gnome.desktop.interface color-scheme` as a
   subprocess and begin reading its stdout line by line.

### Watch loop

`gsettings monitor` emits a line of the form:

```
color-scheme: 'prefer-dark'
```

on every change. The script parses the new value and re-applies all symlinks.

### Subprocess death handling

If the `gsettings monitor` subprocess exits unexpectedly, the script logs the
event and exits with a non-zero code. systemd `Restart=on-failure` then
restarts the whole service, which re-applies symlinks on startup — ensuring
correctness is restored automatically.

### Applying a symlink

```
target_path.unlink(missing_ok=True)
target_path.symlink_to(source_path)
```

Atomic enough for this use case (theme files are read at reload time, not
continuously). No lock file needed.

---

## systemd User Service

```ini
[Unit]
Description=GNOME color-scheme symlink manager
After=graphical-session.target

[Service]
Type=simple
ExecStart=/path/to/gnome-themer
Restart=on-failure
RestartSec=3s

[Install]
WantedBy=default.target
```

The service runs as the user (not root). The binary path is managed by
home-manager.

---

## Home-Manager Module

### Options

```nix
services.gnome-themer = {
  enable = lib.mkEnableOption "GNOME color-scheme symlink manager";

  links = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule {
      options = {
        target = lib.mkOption { type = lib.types.str; };
        dark   = lib.mkOption { type = lib.types.str; };
        light  = lib.mkOption { type = lib.types.str; };
      };
    });
    default = [];
    description = "Symlink targets and their per-theme sources.";
  };
};
```

### What the module does

- Renders `links` into `~/.config/gnome-themer/config.toml` via
  `xdg.configFile`, using `(pkgs.formats.toml {}).generate` (backed by
  `remarshal`; handles `[[link]]` arrays of tables correctly).
- Declares a `systemd.user.services.gnome-themer` entry.
- Adds the script to the user's `PATH` (or hardcodes the store path in
  `ExecStart`).

### Example usage

```nix
services.gnome-themer = {
  enable = true;
  links = [
    {
      target = "~/.config/alacritty/theme.toml";
      dark   = "~/.config/alacritty/themes/catppuccin-mocha.toml";
      light  = "~/.config/alacritty/themes/catppuccin-latte.toml";
    }
  ];
};
```

---

## Error Handling Summary

| Situation                          | Behaviour                                      |
|------------------------------------|------------------------------------------------|
| Malformed TOML                     | Exit 1 on startup; systemd will retry          |
| Source file does not exist         | Exit 1 on startup; systemd will retry          |
| Target exists as a regular file    | Log warning, continue (leave file untouched)   |
| `gsettings monitor` subprocess dies| Log error, exit 1; systemd restarts service    |
| Unknown color-scheme value         | Treat as light, log warning                    |

---

## Out of Scope

- Signalling applications to reload after a theme switch (a post-switch hook
  list could be a future addition).
- Supporting non-GNOME desktops.
- Managing anything other than symlinks (e.g. rewriting config file contents).
