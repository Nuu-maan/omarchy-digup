# DigUp for Omarchy

Search your files by what's in them, from a panel in the Omarchy shell. Describe a photo, a page, a moment in a
recording or video, or what some code does, and it finds the file and takes you to the page, moment or line.

It's a front end for [DigUp](https://github.com/ARahim3/DigUp) by Abdur Rahim, which does the reading and searching
with Google DeepMind's EmbeddingGemma 2. Everything runs on your computer.

## Install

```sh
omarchy plugin add https://github.com/Nuu-maan/omarchy-digup.git
~/.config/omarchy/plugins/io.github.nuu-maan.digup/bin/install-helper
omarchy plugin enable io.github.nuu-maan.digup
```

`install-helper` downloads DigUp's Linux engine (about 140 MB) into `~/.local/share/digup/helper`. If DigUp's `.deb`
is installed, you can skip it: the plugin finds that one too. On first start the plugin downloads the model (865 MB,
once), then starts reading your folders.

Add a key and turn off the layer animation, so the panel opens instantly like the other Omarchy menus. In
`~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + D", "DigUp", "omarchy-shell shell toggle io.github.nuu-maan.digup '{}'")
```

and in `~/.config/hypr/looknfeel.lua`:

```lua
hl.layer_rule({ match = { namespace = "^omarchy-digup$" }, no_anim = true, animation = "none" })
```

## Using it

| Key | What it does |
|---|---|
| Super D | Opens the panel |
| ↑ ↓ | Moves through the results |
| Enter | Opens the result: PDFs at the page, recordings and videos at the moment, code at the line |
| Ctrl Enter | Shows it in your file manager |
| Ctrl C | Copies the file |
| Esc | Clears the search, then closes |

Start a search with `code:` to search your code. To open the panel with a search already typed:

```sh
omarchy-shell shell summon io.github.nuu-maan.digup '{"query":"code: "}'
```

PDFs open at the page in Evince, Papers, Zathura or Okular, recordings and videos at the moment in mpv, and code at
the line in your Omarchy editor. Anything else opens in its default app.

## Folders

The plugin reads the folders in `~/.config/omarchy/digup.json`, and writes this one the first time:

```json
{
  "folders": ["~/Documents", "~/Pictures"],
  "code": []
}
```

Add folders to `folders`, and your projects to `code` to turn on code search. Changes apply as soon as you save.

The first pass is slow on a processor alone, a few seconds per picture, so start small. The panel's footer shows how
far it has got. After that, new files are picked up within ten minutes.

## How it works

`Service.qml` starts with the shell and runs three of DigUp's commands: `search-service`, which keeps the index open
and the model warm, `index-service`, which reads new and changed files, and `download-model` on first start.
`Search.qml` is the panel. It asks for a word match on every keystroke and a meaning match once you pause, and shows
whichever is newest. `bin/digup-open` opens results in your apps.

Tests for the result model: `node tests/model.test.js`.

## Uninstall

```sh
omarchy plugin remove io.github.nuu-maan.digup
rm -rf ~/.local/share/digup ~/.config/omarchy/digup.json
```

## License

MIT. DigUp is MIT, and EmbeddingGemma 2 is Apache 2.0.
