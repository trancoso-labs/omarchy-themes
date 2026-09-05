# Themes

An Omarchy bar widget for switching user themes, choosing which wallpapers
rotate, and pulling new [Aether](https://github.com/omacom/aether) / Wallhaven
favorites into the closest palette.

Omarchy ships theme switching and `omarchy theme bg next`. It does not ship a
bar control, a timer, or per-wallpaper opt-in. This plugin adds those on top of
the same commands.

## What it does

- Lists your user themes (`~/.config/omarchy/themes/`) as one-click buttons.
- Lets you enable or disable each background in that theme's rotation.
- Optional slideshow via a user systemd timer (`omarchy-theme-rotate.timer`).
  Off until you flip the switch in the panel.
- A **density** axis, independent of palette: how much of the frame holds
  local detail (`quiet` / `open` / `packed`). A lived-in room scores packed;
  a red void or empty night scores quiet. The timer can filter on that.
- **Update themes** reads Aether favorites, skips wallpapers already in a
  palette, and copies new ones into the nearest `aether-*` family theme.

Built as a first-class Omarchy shell plugin (`kind: bar-widget`), so it uses
the same panel kit, colors, and bar slot as Bluetooth or Power.

## Install

```bash
omarchy plugin add https://github.com/trancoso-labs/omarchy-themes.git --enable
omarchy bar put 3v4ng3li0n00.themes --section left
```

If the widget does not appear after add, rescan and enable:

```bash
omarchy-shell shell rescanPlugins
omarchy plugin enable 3v4ng3li0n00.themes --section left
```

## Use

- Left click the palette icon: open the panel.
- Right click: jump to the next enabled wallpaper of the current theme.
- Middle click: run favorite sync.

In the panel, the top switch starts/stops the timer. Interval chips are 5 / 10
/ 15 / 30 / 60 minutes. Background toggles only affect rotation; they do not
delete files.

State lives in `~/.config/omarchy/theme-rotation.json`. The timer unit is
written on first toggle to `~/.config/systemd/user/omarchy-theme-rotate.timer`.

## Family palettes

This plugin was built around a user-made `aether-*` theme family (crimson,
moss, cyan, ink, magenta, amber). Sync assigns new favorites into those slugs
when they exist. Other user themes still appear in the switcher.

## Remove

```bash
omarchy plugin remove 3v4ng3li0n00.themes
systemctl --user disable --now omarchy-theme-rotate.timer
```
