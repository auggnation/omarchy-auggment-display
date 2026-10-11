# Auggment Display

Full monitor control for Omarchy — resolution, arrangement, refresh rate, scale,
rotation, mirroring, VRR, HDR and brightness, per display — plus wallpaper
rotation, a screen-off timer and wallpaper-derived color matching.

This is a fork of [**Advanced Displays**](https://github.com/Fluffet/omarchy-advanced-displays)
by [Fredrik Öhrström (Fluffet)](https://github.com/Fluffet), used and extended
under the MIT license. All of the display configuration is their work; the
Auggment additions are the background/power/color section. Thanks, Fluffet.

<p align="center">
  <img src="preview.png" alt="Display panel" height="360">
  <img src="screenshots/arrange.png" alt="Arrange window" height="360">
</p>

## Install

```bash
omarchy plugin add https://github.com/auggnation/omarchy-auggment-display --enable
omarchy plugin disable omarchy.monitor
```

The second line hides the built-in Display widget, so you don't get two icons.
Click the new icon in your bar.

### Optional dependencies

The Auggment extras use a few helpers and degrade gracefully if they are missing:

- **`hypridle`** — required for the *Screen off* timer (`yay -S hypridle` or `pacman -S hypridle`).
- **`pywal`/`wal`** (`pywal16`) — required for *Auto color match*.
- **`jq`** — required when changing the screensaver timeout.

## What the Auggment section adds

Below the per-monitor controls, the panel gains:

- **Background** — rotate through the current theme's wallpapers on an interval,
  randomly and without repeating recent picks.
- **Screensaver** — how long before the screensaver starts (writes `idle.screensaver`).
- **Screen off** — turn the display off after N minutes via `hypridle` (dpms), and
  back on when you return. Generates `~/.config/hypr/hypridle.conf` and reloads the daemon.
- **Auto color match** — derive the whole theme palette from the current wallpaper
  with `pywal` and apply it live, window borders included.

The helper scripts live in `bin/` inside this plugin and are called directly, so
there is no service to install. Settings are stored under `~/.config/auggment/`.

## Two things to know

**Changes apply live, but revert after 15 seconds.** Press **Keep** to save.

**Keep writes to `~/.config/hypr/monitors.lua`.**

Settings are stored per monitor, not per port. Move the cable, settings follow.

## Rebind SUPER + CTRL + D

That key opened the built-in panel, which is now off. Point it here instead, in
`~/.config/hypr/bindings.lua`:

```lua
hl.unbind("SUPER + CTRL + D")
o.bind("SUPER + CTRL + D", "Display", "omarchy-shell io.github.auggnation.auggment-display toggle")
o.bind("SUPER + CTRL + SHIFT + D", "Arrange displays", "omarchy-shell shell toggle io.github.auggnation.auggment-display")
```

## Uninstall

```bash
omarchy plugin remove io.github.auggnation.auggment-display
```

Press **Forget saved layout** first if you also want your monitor settings gone.
Otherwise the block in `monitors.lua` stays.

To remove the Auggment state as well:

```bash
rm -rf ~/.config/auggment ~/.config/hypr/hypridle.conf
```

<details>
<summary>Small print</summary>

- HDR only appears if the monitor's EDID says it supports it.
- VRR shows the EDID refresh range as a hint.
- Brightness uses the backlight on laptops, DDC on desktop monitors.
- Move the widget like any other: `omarchy bar move io.github.auggnation.auggment-display --section right`

</details>

<details>
<summary>Scripting (IPC)</summary>

```bash
omarchy-shell io.github.auggnation.auggment-display toggle
omarchy-shell io.github.auggnation.auggment-display state
omarchy-shell io.github.auggnation.auggment-display select DP-3
omarchy-shell io.github.auggnation.auggment-display change '{"hz":60}'   # keys: width height hz scale transform mirror vrr hdr disabled
omarchy-shell io.github.auggnation.auggment-display keep
omarchy-shell io.github.auggnation.auggment-display revert
omarchy-shell io.github.auggnation.auggment-display forget
```

</details>

<details>
<summary>Hacking on it</summary>

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/io.github.auggnation.auggment-display
omarchy plugin enable io.github.auggnation.auggment-display
node --test test/model.test.js
bash test/monitors-lua.test.sh
shellcheck monitors-lua.sh
qmllint -I "$OMARCHY_PATH/shell" Panel.qml
```

Hot reload through a symlinked plugin dir is unreliable. `omarchy restart shell` always works.

</details>

## Credits & license

- Original **Advanced Displays** © 2026 Fredrik Öhrström (Fluffet) — MIT.
- **Auggment** additions © 2026 Auggment — MIT.

See [LICENSE](LICENSE) for the full text.
