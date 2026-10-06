# BeatBox skins

A skin is a folder with two files:

- `skin.ini`: its name and description.

  ```ini
  [Skin]
  Name=My Skin
  Name[es]=Mi skin
  Description=What it looks like.
  Author=You
  ```

  - `Native=true` drops BeatBox's own look (the Classic skin, `data/theme.css`) so only the GTK theme and `skin.css` apply (see `skins/native`).
  - `Theme=Adwaita` uses that GTK theme instead of the desktop's; `Dark=true` asks for its dark variant (see `skins/adwaita` and `skins/adwaita-dark`).
  - `MenuIcon=square` shows the square app icon on the menu button (top right) instead of the round one.

- `skin.css`: GTK 3 CSS. Unless the skin is native it is loaded on top of the Classic look (`data/theme.css`).

The default skin is Adwaita: plain GTK with its own theme. The bundled ones:

| Skin | Kind | Look |
| --- | --- | --- |
| Adwaita (default) | native | GTK's own theme, no custom styling |
| Adwaita dark | native | the same, dark |
| Native | native | the desktop's GTK theme |
| Classic | over `theme.css` | aluminium chrome, blue accents, green LCD |
| Graphite | over Classic | Classic in grey |
| Midnight | over Classic | dark chrome and lists, blue LCD |
| Vinyl | over Classic | walnut chrome, cream lists, amber LCD |
| High contrast | over Classic | black and white, yellow selections and LCD |

To install a skin, copy its folder to `~/.local/share/beatbox/skins/`, then pick it in Preferences › Appearance. "Open Skins Folder" in that section creates and opens the folder.

## Recoloring

The simplest skin (over Classic) only redefines the palette. Every rule of the Classic look uses these colors, so it follows them:

| Color | Used for |
| --- | --- |
| `bb_chrome_top`, `bb_chrome_mid`, `bb_chrome_bottom`, `bb_chrome_border` | top bar gradient |
| `bb_accent`, `bb_accent_light` | selection, pressed buttons |
| `bb_sidebar_top`, `bb_sidebar_bottom`, `bb_sidebar_border`, `bb_sidebar_text`, `bb_sidebar_heading` | source list |
| `bb_row_a`, `bb_row_b` | zebra stripes of the track lists |
| `bb_detail_bg`, `bb_detail_border` | album band of the inline grid |
| `bb_lcd_top`, `bb_lcd_mid`, `bb_lcd_bottom`, `bb_lcd_border`, `bb_lcd_text`, `bb_lcd_dim` | LCD display |

`skins/graphite` is an example of a palette-only skin. `skins/midnight` also restyles widgets.

## Useful selectors

| Selector | Widget |
| --- | --- |
| `window.beatbox` | main window |
| `toolbar.app-header` | top bar |
| `toolbutton.transport-button > button` | previous, play and next buttons |
| `button.round-menu` | app menu button |
| `.app-name` | app name next to the window buttons |
| `.lcd` | LCD display |
| `.lcd scale slider` | position diamond |
| `entry.search-bar` | search box |
| `treeview.sidebar` | source list |
| `treeview.tracklist` | track lists |
| `iconview.albumgrid` | cover grid in popup mode |
| `.albumwall` | cover grid in inline mode |
| `.album-detail` | album band in inline mode |
| `.track-report` | information panel at the right of the lists |
| `.coverflow` | Cover Flow |
| `.source-actions` | button bar above Podcasts and Internet Radio |
| `.source-page` | welcome screens and empty-list messages |
| `actionbar.app-statusbar` | bottom bar |
| `button.traffic-light.close`, `.minimize`, `.maximize` | window buttons |

To reference images, put them inside the skin folder and use a relative `url("image.png")`.

To try changes, pick another skin and then yours again; BeatBox reloads the CSS each time.
