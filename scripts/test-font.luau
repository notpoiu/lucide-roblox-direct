local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local LuaEncode = require("./utils/LuaEncode")

local data = serde.decode("json", fs.readFile("fonts/codepoints.json"))
local template = fs.readFile("scripts/assets/template.luau")
local values = {
	DATA_SPRITESHEETS = "0",
	DATA_ICON_MAPPINGS = '{{"moon"},{"rbxassetid://123"},{[48]={{1,{24,24},{775,375}}}}}',
	DATA_FONT_MAPPINGS = LuaEncode(data.icons),
	DATA_FONT_HASH = `"{data.version}"`,
	VERSION = '"test"',
}
for key, value in values do
	template = template:gsub(key, function() return value end)
end

local function check(source)
	local base = { Vector2 = { new = function(x, y) return { x, y } end } }
	local plain = luau.load(source, { environment = base })()
	assert(plain.GetFontAsset == nil)
	assert(plain.GetAsset("moon"))
	assert(plain.GetAsset("not-an-icon") == nil)

	local files, folders = {}, {}
	local downloads, registrations, creations = 0, 0, 0
	local face = {}
	local environment = table.clone(base)
	environment.isfile = function(name) return files[name] ~= nil end
	environment.isfolder = function(name) return folders[name] == true end
	environment.makefolder = function(name) folders[name] = true end
	environment.readfile = function(name) return assert(files[name]) end
	environment.writefile = function(name, contents) files[name] = contents end
	environment.getcustomasset = function(name)
		registrations += 1
		assert(files[name] ~= nil)
		return `custom://{name}`
	end
	environment.Font = { new = function(asset)
		local family = serde.decode("json", assert(files[asset:sub(10)]))
		assert(family.faces[1].assetId == `custom://lucide-icons/font-{data.version}/lucide.ttf`)
		assert(family.faces[1].weight == 400 and family.faces[1].style == "normal")
		creations += 1
		return face
	end }
	environment.game = {
		HttpGet = function(_, url)
			downloads += 1
			return if url:match("%.ttf$") then fs.readFile("fonts/lucide.ttf") else "sprite"
		end,
		GetService = function(_, name)
			assert(name == "HttpService")
			return { JSONEncode = function(_, value) return serde.encode("json", value) end }
		end,
	}
	local custom = luau.load(source, { environment = environment })()
	assert(type(custom.GetFontAsset) == "function")
	local before = downloads
	assert(custom.GetFontAsset("not-an-icon") == nil and downloads == before)
	local moon = custom.GetFontAsset("moon")
	assert(moon.FontFace == face and moon.Text == utf8.char(data.icons.moon))
	assert(custom.GetFontAsset("mountain").Text == utf8.char(data.icons.mountain))
	assert(downloads == before + 1 and creations == 1)
	local cached = luau.load(source, { environment = environment })()
	assert(cached.GetFontAsset("moon").FontFace == face and downloads == before + 1)
	assert(creations == 2 and registrations > 0)
end

check(template)
check(fs.readFile("source.lua"))
print("Font loader: capability gating, lazy loading, glyph lookup, and cache checks passed")
