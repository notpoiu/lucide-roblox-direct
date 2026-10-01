# lucide-roblox-direct

lucide-roblox-direct is a script that directly gives you a standalone file that contains all the Lucide icons in Roblox. (Found in source.lua)

## Usage

Example module found [here](https://github.com/notpoiu/cobalt/blob/main/Src/Utils/UI/Icons.luau)

### Icon font

`source.lua` also exposes `GetFontAsset` when `getcustomasset` is available. The font loads on the first valid lookup.

```lua
local icon = Lucide.GetFontAsset("moon")
label.FontFace = icon.FontFace
label.Text = icon.Text
label.TextSize = 24
```

Unknown icon names return `nil`. Environments without `getcustomasset` do not expose `GetFontAsset`. `GetAsset` continues to return spritesheet data.

CI generates `fonts/lucide.ttf` and `fonts/codepoints.json` alongside the spritesheets, then checks font glyphs and loader behavior before committing them. Loader downloads are pinned to the asset commit so cached source and images cannot mix versions. Glyph codepoints remain stable across updates.

Generated workspace caches retain the current and previous versions of each asset type when `readfile`, `listfiles`, and `delfolder` are available. Cleanup runs after registration for sprites and after Roblox loads the font for a text-bounds check. Failed loads leave the retained caches untouched. This does not clear copies managed separately by the executor inside Roblox's content folder.

To build only the font, install Node.js 24, run `npm ci`, then run `npm run build:font` after the Lucide SVGs are available in `build/lucide/icons`. Run `npm test` after generating `source.lua`.

## Building

To build lucide-roblox-direct, you need to have Python 3 installed on your system. You can download it from [python.org](https://www.python.org/downloads/). Once you have Python installed, you can run the following command in your terminal:

```bash
pip install -r requirements.txt
```

This will install all the required dependencies for the script.

Additionally, you will need install [rokit](https://github.com/rojo-rbx/rokit).
then open Powershell or the command-line shell of your liking and [cd to this repository](https://www.quora.com/What-does-it-mean-to-CD-into-a-directory-and-how-can-I-do-that-Can-someone-explain-it-in-a-laymans-term)

Run `rokit install` and wait for it to install all the dependencies

Before running the script, you need to setup your environement variables. Create a file named `.env` in the root directory of the project and add the following lines:

```
ROBLOX_API_KEY=your_api_key_here
ROBLOX_USER_ID=your_user_id_here
```

Replace `your_api_key_here` with your actual Roblox API key and `your_user_id_here` with your Roblox user ID.
(ROBLOX_API_KEY should have read & write permissions to the assets in roblox open cloud permissions and manage permissions for the legacy-assets)

and finally, run the following command to build the script:

```bash
sh scripts/build.sh
```
