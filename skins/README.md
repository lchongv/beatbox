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

  `Native=true` drops the built-in look so only the system's GTK theme and `skin.css` apply (see `skins/native`).

- `skin.css`: GTK 3 CSS loaded on top of the built-in look (`data/theme.css`).

To install a skin, copy its folder to `~/.local/share/beatbox/skins/`, then pick it in Preferences › Behavior › Appearance. "Open Skins Folder" in that section creates and opens the folder.

## Recoloring

The simplest skin only redefines the palette. Every rule of the base theme uses these colors, so it follows them:

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
| `.lcd` | LCD display |
| `.lcd scale slider` | position diamond |
| `entry.search-bar` | search box |
| `treeview.sidebar` | source list |
| `treeview.tracklist` | track lists |
| `iconview.albumgrid` | cover grid in popup mode |
| `.albumwall` | cover grid in inline mode |
| `.album-detail` | album band in inline mode |
| `.coverflow` | Cover Flow |
| `.source-actions` | button bar above Podcasts and Internet Radio |
| `.source-page` | welcome screens and empty-list messages |
| `actionbar.app-statusbar` | bottom bar |
| `button.traffic-light.close`, `.minimize`, `.maximize` | window buttons |

To reference images, put them inside the skin folder and use a relative `url("image.png")`.

To try changes, pick another skin and then yours again; BeatBox reloads the CSS each time.
