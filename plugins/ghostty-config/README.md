# ghostty-config

Ghostty terminal config + custom GTK CSS for tab bar styling.

## Files

- `config` — main Ghostty config (theme, font, tabs, bell, padding)
- `ghostty-custom.css` — GTK CSS for tab bar colors (dark Ayu theme with blue active tab)
- `install.sh` — symlinks both files into `~/.config/ghostty/`

## Install

```sh
./plugins/ghostty-config/install.sh
```

Idempotent — backs up existing files before symlinking.

## Customizing tab colors

Edit `ghostty-custom.css` — the `tabbar tab:checked` block controls the active tab:

```css
tabbar tab:checked {
  background-color: #1e3a5f;  /* active tab bg */
  color: #7ec4ff;             /* active tab text */
}
```

Restart Ghostty (or open a new window) to pick up CSS changes.
