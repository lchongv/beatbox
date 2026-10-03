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

- `skin.css`: GTK 3 CSS loaded on top of the built-in iTunes look (`data/itunes.css`).

To install a skin, copy its folder to `~/.local/share/beatbox/skins/`, then pick it in Preferences › Behavior › Appearance. "Open Skins Folder" in that section creates and opens the folder.

## Recoloring

The simplest skin only redefines the palette. Every rule of the base theme uses these colors, so it follows them:

| Color | Used for |
| --- | --- |
| `it7_chrome_top`, `it7_chrome_mid`, `it7_chrome_bottom`, `it7_chrome_border` | top bar gradient |
| `it7_accent`, `it7_accent_light` | selection, pressed buttons |
| `it7_sidebar_top`, `it7_sidebar_bottom`, `it7_sidebar_border`, `it7_sidebar_text`, `it7_sidebar_heading` | source list |
| `it7_row_a`, `it7_row_b` | zebra stripes of the track lists |
| `it7_detail_bg`, `it7_detail_border` | album band of the inline grid |
| `it7_lcd_top`, `it7_lcd_mid`, `it7_lcd_bottom`, `it7_lcd_border`, `it7_lcd_text`, `it7_lcd_dim` | LCD display |

`skins/graphite` is an example of a palette-only skin. `skins/midnight` also restyles widgets.

## Useful selectors

| Selector | Widget |
| --- | --- |
| `window.beatbox` | main window |
| `toolbar.itunes-header` | top bar |
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
| `actionbar.itunes-statusbar` | bottom bar |
| `button.traffic-light.close`, `.minimize`, `.maximize` | window buttons |

To reference images, put them inside the skin folder and use a relative `url("image.png")`.

To try changes, pick another skin and then yours again; BeatBox reloads the CSS each time.
