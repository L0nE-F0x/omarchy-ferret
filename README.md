# Ferret

Type-to-open file search for Omarchy. Press the hotkey, start typing, press
**Enter** — the file opens in whatever app owns it.

## Install

Omarchy 4.x (Quattro). From a terminal:

```bash
omarchy plugin add https://github.com/L0nE-F0x/omarchy-ferret.git --enable
```

Ferret does not write your config. Bind a key yourself in
`~/.config/hypr/bindings.lua`. Super+Z is a good default if nothing else
uses it:

```lua
o.bind("SUPER + Z", "File search", "omarchy-shell shell toggle lonefox.ferret")
```

You can also open it without a bind:

```bash
omarchy-shell shell toggle lonefox.ferret
```

## Remove

```bash
omarchy plugin remove lonefox.ferret --yes
```

Then delete the `o.bind` line you added. That is the only config Ferret
asks you to touch, and only if you added it.

## Dependencies

All local. Ferret does not phone home.

| Need | Used for |
|---|---|
| `python3` | `ferret-search` |
| `plocate` | indexed whole-disk search |
| `fd` | live walk of `$HOME` (falls back to `fdfind`) |
| `xdg-mime`, `xdg-open` | open a file in its default app |
| `uwsm-app` | preferred launcher on Omarchy; skipped if missing |

`plocate` is only as fresh as the last `plocate-updatedb.timer` run. `fd`
covers files created since then, under `$HOME`.

## Keys

| Key | Does |
|---|---|
| your bind (example: `Super+Z`) | Open Ferret |
| type | Search as you go |
| `↑` `↓` (or `Tab` / `Ctrl+N` / `Ctrl+P`) | Move through results |
| `PgUp` `PgDn` | Jump a page |
| `Enter` | Open in the default app |
| `Ctrl+Enter` | Open the containing folder instead |
| `Esc` | Clear the text, or close if already empty |
| click / right-click | Open / open its folder |

Escape is the way out. The overlay takes an exclusive keyboard grab while it
is up, so the summon key does not reach the compositor to toggle it back off.

## How the search works

Two sources are merged on every query:

- **plocate** — the whole disk, from the system index. ~20 ms. As fresh as the
  last `plocate-updatedb.timer` run.
- **fd** — a live walk of `$HOME`. ~100 ms warm. Covers anything made since
  that index was built, so a file you saved a minute ago is findable.

Results are merged, deduped, and scored: exact name beats prefix beats
substring beats a path-only match; your own files outrank the system's;
`node_modules`, `.cache`, build output and browser state are pushed down;
recently-modified files get a nudge. If a literal search comes back thin, the
query is retried as an abbreviation (`lknfl` finds `looknfeel.lua`).

Whole-word queries AND together, so `shell json` matches paths containing both.

## Files

```
manifest.json    plugin metadata; kind "overlay", keepLoaded
Ferret.qml       the overlay — field, list, keys. Theme comes from [menu] tokens
FerretModel.js   glyphs by file type, path/size/age formatting
ferret-search    the backend: search, rank, and open. Usable on its own
```

The backend runs standalone, which is the quickest way to check ranking:

```bash
./ferret-search "budget xlsx" | jq -r '.[] | "\(.score)  \(.path)"'
./ferret-search --open  /path/to/file      # launch in its default app
./ferret-search --reveal /path/to/file     # open its folder
```

`jq` is only for that example. The plugin itself does not need it.

## Tuning

Ranking lives in `ferret-search`:

- `NOISE` — path fragments to push down, with their penalties.
- `PRIME` — directories to favour (`Documents`, `Projects`, …).
- `RESULT_LIMIT` — how many rows reach the UI (default 60).
- `score()` — the weights themselves.

Editing `ferret-search` takes effect on the next search; it is a subprocess.
After changing the QML, rescan or restart the shell:

```bash
omarchy-shell shell rescanPlugins
```

## License

MIT. See `LICENSE`.

## Not indexed

`/etc/updatedb.conf` usually prunes `/mnt` and `/media`, so files on an
external drive are not in the plocate index. They are still reachable if they
live under `$HOME` (the `fd` pass covers that); otherwise add the mount point
to `updatedb.conf` and re-run `updatedb`.
