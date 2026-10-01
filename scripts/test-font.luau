local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local LuaEncode = require("./utils/LuaEncode")

local data = serde.decode("json", fs.readFile("fonts/codepoints.json"))
local template = fs.readFile("scripts/assets/template.luau")
local values = {
	DATA_SPRITESHEETS = "1",
	DATA_ICON_MAPPINGS = '{{"moon"},{"rbxassetid://123"},{[48]={{1,{24,24},{775,375}}}}}',
	DATA_FONT_MAPPINGS = LuaEncode(data.icons),
	DATA_FONT_HASH = `"{data.version}"`,
	VERSION = '"2026-09-30T010000Z"',
}
for key, value in values do
	template = template:gsub(key, function() return value end)
end

local function check(source, verifySprites)
	local revision = assert(source:match("https://raw%.githubusercontent%.com/notpoiu/lucide%-roblox%-direct/(.-)/spritesheets/"))
	local assetBase = `https://raw.githubusercontent.com/notpoiu/lucide-roblox-direct/{revision}/`
	local base = { Vector2 = { new = function(x, y) return { x, y } end } }
	local plain = luau.load(source, { environment = base })()
	assert(plain.GetFontAsset == nil)
	assert(plain.GetAsset("moon"))
	assert(plain.GetAsset("not-an-icon") == nil)

	local files = { ["lucide-icons/version.txt"] = "test", ["lucide-icons/1.png"] = "stale" }
	local folders = { ["lucide-icons"] = true }
	local previousFont = "lucide-icons/font-" .. string.rep("1", 64)
	local previousSprite = "lucide-icons/sprites-2026-09-29T010000Z"
	local olderFont = "lucide-icons/font-" .. string.rep("2", 64)
	local olderSprite = "lucide-icons/sprites-2026-09-28T010000Z"
	for _, directory in { previousFont, previousSprite, olderFont, olderSprite, "lucide-icons/font-notes", "lucide-icons/sprites-notes" } do
		folders[directory] = true
	end
	files["lucide-icons/font-cache.txt"] = previousFont .. "\n" .. olderFont
	files["lucide-icons/sprites-cache.txt"] = previousSprite .. "\n" .. olderSprite
	local downloads, registrations, creations = 0, 0, 0
	local boundsFailure = false
	local face = {}
	local environment = table.clone(base)
	environment.isfile = function(name) return files[name] ~= nil end
	environment.isfolder = function(name) return folders[name] == true end
	environment.makefolder = function(name) folders[name] = true end
	environment.readfile = function(name) return assert(files[name]) end
	environment.writefile = function(name, contents) files[name] = contents end
	environment.listfiles = function(directory)
		assert(directory == "lucide-icons")
		local entries = {}
		for name in folders do
			if name ~= directory then table.insert(entries, (name:gsub("/", "\\"))) end
		end
		return entries
	end
	environment.delfolder = function(directory)
		assert(directory:find("lucide-icons/", 1, true) == 1 and folders[directory])
		assert(directory ~= "lucide-icons/font-notes" and directory ~= "lucide-icons/sprites-notes")
		folders[directory] = nil
		for name in files do
			if name:find(directory .. "/", 1, true) == 1 then files[name] = nil end
		end
	end
	environment.getcustomasset = function(name)
		registrations += 1
		assert(files[name] ~= nil)
		return `custom://{name}`
	end
	environment.Font = { new = function(asset)
		local family = serde.decode("json", assert(files[asset:sub(10)]))
		assert(family.faces[1].assetId == asset:gsub("/[^/]+$", "/lucide.ttf"))
		assert(family.faces[1].weight == 400 and family.faces[1].style == "normal")
		creations += 1
		return face
	end }
	environment.Instance = { new = function(name)
		assert(name == "GetTextBoundsParams")
		return { Destroy = function() end }
	end }
	environment.game = {
		HttpGet = function(_, url)
			assert(url:find(assetBase, 1, true) == 1)
			downloads += 1
			return if url:match("%.ttf$") then fs.readFile("fonts/lucide.ttf") else fs.readFile(`spritesheets/{assert(url:match("/spritesheets/(%d+)%.png$"))}.png`)
		end,
		GetService = function(_, name)
			if name == "TextService" then
				return { GetTextBoundsAsync = function(_, params)
					assert(params.Font == face and utf8.len(params.Text) == 1)
					assert(params.Size == 24 and params.Width == 100)
					if boundsFailure then error("font unavailable") end
					return { X = 24, Y = 24 }
				end }
			end
			assert(name == "HttpService")
			return { JSONEncode = function(_, value) return serde.encode("json", value) end }
		end,
	}
	local custom = luau.load(source, { environment = environment })()
	assert(type(custom.GetFontAsset) == "function")
	assert(folders[previousSprite] and not folders[olderSprite])
	if verifySprites then
		local spritePath = custom.GetAsset("moon").Url:sub(10)
		assert(spritePath:find("lucide-icons/sprites-", 1, true) == 1)
		assert(files[spritePath] and files[spritePath] ~= "stale")
		if fs.isFile("build/outputs/mappings.lua") then
			local mappings = fs.readFile("build/outputs/mappings.lua"):gsub("repeat = {", '["repeat"] = {')
			local sprites = luau.load(mappings, { environment = base })().formatted_icons
			local count = 0
			for name, expected in sprites do
				local actual = assert(custom.GetAsset(name))
				assert(actual.Url:match("/(%d+)%.png$") == expected.Image:match("(%d+)$"), `Wrong sheet: {name}`)
				for axis = 1, 2 do
					assert(actual.ImageRectSize[axis] == expected.ImageRectSize[axis], `Wrong size: {name}`)
					assert(actual.ImageRectOffset[axis] == expected.ImageRectOffset[axis], `Wrong offset: {name}`)
				end
				assert(data.icons[name], `Missing font mapping: {name}`)
				count += 1
			end
			assert(count == #custom.Icons)
			print(`Cross-checked {count} spritesheet entries against generated mappings`)
		end
	end
	local before = downloads
	assert(custom.GetFontAsset("not-an-icon") == nil and downloads == before)
	local moon = custom.GetFontAsset("moon")
	assert(moon.FontFace == face and moon.Text == utf8.char(data.icons.moon))
	assert(custom.GetFontAsset("mountain").Text == utf8.char(data.icons.mountain))
	assert(downloads == before + 1 and creations == 1)
	assert(folders[previousFont] and not folders[olderFont])
	assert(folders["lucide-icons/font-notes"] and folders["lucide-icons/sprites-notes"])
	local cached = luau.load(source, { environment = environment })()
	assert(cached.GetFontAsset("moon").FontFace == face and downloads == before + 1)
	assert(creations == 2 and registrations > 0)
	assert(folders[previousFont] and folders[previousSprite])
	local marker = files["lucide-icons/font-cache.txt"]
	boundsFailure = true
	local nextVersion = string.rep("4", 64)
	local failed = luau.load(source:gsub(data.version, nextVersion), { environment = environment })()
	local loaded, failure = pcall(failed.GetFontAsset, "moon")
	assert(not loaded and tostring(failure):find("Lucide font failed to load:", 1, true))
	assert(files["lucide-icons/font-cache.txt"] == marker and folders[previousFont])
	boundsFailure = false
	assert(failed.GetFontAsset("moon").FontFace == face)
	assert(not folders[previousFont] and folders[`lucide-icons/font-{data.version}`])
	assert(files["lucide-icons/font-cache.txt"] == `lucide-icons/font-{nextVersion}\nlucide-icons/font-{data.version}`)
	local withoutCleanup = table.clone(environment)
	withoutCleanup.listfiles, withoutCleanup.delfolder = nil, nil
	assert(luau.load(source, { environment = withoutCleanup })().GetFontAsset("moon"))
end

check(template)
check(fs.readFile("source.lua"), true)
print("Font loader: capability gating, glyph lookup, bounded caches, failed loads, and retries passed")
