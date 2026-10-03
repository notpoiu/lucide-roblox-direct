local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")
local LuaEncode = require("./utils/LuaEncode")

local data = serde.decode("json", fs.readFile("fonts/codepoints.json"))
local template = fs.readFile("scripts/assets/template.luau")
local values = {
	DATA_SPRITESHEETS = "1",
	DATA_ICON_MAPPINGS = '{{"moon","mountain"},{"rbxassetid://123"},{[48]={{1,{24,24},{775,375}},{1,{24,24},{0,0}}}}}',
	DATA_FONT_MAPPINGS = LuaEncode(data.icons),
	DATA_ASSET_HASH = `"{string.rep("a", 64)}"`,
}
for key, value in values do
	template = template:gsub(key, function() return value end)
end

local function check(source, verifySprites)
	local eager = source:find("Lucide.GetFontAsset = Lucide.GetAsset", 1, true) ~= nil
	local revision = assert(source:match("https://raw%.githubusercontent%.com/notpoiu/lucide%-roblox%-direct/([^/]+)/"))
	local assetBase = `https://raw.githubusercontent.com/notpoiu/lucide-roblox-direct/{revision}/`
	local base = { Vector2 = { new = function(x, y) return { x, y } end } }
	local plain = luau.load(source, { environment = base })()
	assert(plain.GetFontAsset == nil)
	assert(plain.GetAsset("moon"))
	assert(plain.GetAsset("not-an-icon") == nil)

	local assetHash = assert(source:match('local ASSET_FOLDER = "(%x+)"'))
	local current = `lucide-icons/{assetHash}`
	local files = { ["lucide-icons/version.txt"] = "test", ["lucide-icons/1.png"] = "stale" }
	local folders = { ["lucide-icons"] = true }
	local previous = "lucide-icons/" .. string.rep("1", 64)
	local older = "lucide-icons/" .. string.rep("2", 64)
	local legacyFont = "lucide-icons/font-" .. string.rep("3", 64)
	local legacySprites = "lucide-icons/sprites-2026-09-28T010000Z"
	local unrelated = { "lucide-icons/notes", "lucide-icons/font-notes", "lucide-icons/sprites-notes" }
	for _, directory in { previous, older, legacyFont, legacySprites, table.unpack(unrelated) } do
		folders[directory] = true
	end
	files["lucide-icons/cache.txt"] = previous .. "\n" .. older
	local downloads, registrations, creations = 0, 0, 0
	local badDownload = false
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
		assert(family.loadStrategy == "sameFamilyOnly")
		creations += 1
		return face
	end }
	environment.game = {
		HttpGet = function(_, url)
			assert(url:find(assetBase, 1, true) == 1)
			downloads += 1
			if badDownload and url:match("%.ttf$") then return "<html>404</html>" end
			return if url:match("%.ttf$") then fs.readFile("fonts/lucide.ttf") else fs.readFile(`spritesheets/{assert(url:match("/spritesheets/(%d+)%.png$"))}.png`)
		end,
		GetService = function(_, name)
			assert(name == "HttpService")
			return { JSONEncode = function(_, value) return serde.encode("json", value) end }
		end,
	}
	local custom = luau.load(source, { environment = environment })()
	assert(type(custom.GetFontAsset) == "function")
	assert(creations == (if eager then 1 else 0))
	if eager then
		assert(custom.GetFontAsset == custom.GetAsset)
		assert(custom.GetAsset("moon").FontFace == face)
	end
	assert(folders[previous] and not folders[older], "Previous build kept, older build pruned")
	assert(not folders[legacyFont] and not folders[legacySprites], "Old folder layouts pruned")
	for _, directory in unrelated do
		assert(folders[directory], `Unrelated folder deleted: {directory}`)
	end
	if verifySprites then
		local spritePath = custom.GetAsset("moon").Url:sub(10)
		assert(spritePath:find(current .. "/", 1, true) == 1)
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
	assert(moon.FontFace == face and moon.Text == "moon")
	assert(custom.GetFontAsset("mountain").Text == "mountain")
	local expectedDownloads = before + (if eager then 0 else 1)
	assert(downloads == expectedDownloads and creations == 1)
	assert(files[`{current}/lucide.ttf`] and files[`{current}/1.png`], "Font and spritesheets share one folder")
	local cached = luau.load(source, { environment = environment })()
	assert(cached.GetFontAsset("moon").FontFace == face and downloads == expectedDownloads)
	assert(creations == 2 and registrations > 0)
	assert(folders[previous], "Reloading the same build keeps the previous build")

	local nextHash = string.rep("4", 64)
	local nextFont = `lucide-icons/{nextHash}/lucide.ttf`
	local nextSource = source:gsub(assetHash, nextHash)
	badDownload = eager
	local updated = luau.load(nextSource, { environment = environment })()
	assert(not folders[previous] and folders[current], "Update keeps only the build before it")
	assert(files["lucide-icons/cache.txt"] == `lucide-icons/{nextHash}\n{current}`)
	if eager then
		assert(updated.GetFontAsset == nil, "Failed font does not expose GetFontAsset")
		local sprite = assert(updated.GetAsset("moon"))
		assert(sprite.FontFace == nil and sprite.Url, "Failed font keeps sprites available")
	else
		badDownload = true
		local loaded, failure = pcall(updated.GetFontAsset, "moon")
		assert(not loaded and tostring(failure):find("Invalid download", 1, true))
	end
	assert(files[nextFont] == nil, "Bad download not cached")
	badDownload = false
	if eager then
		updated = luau.load(nextSource, { environment = environment })()
	end
	assert(updated.GetFontAsset("moon").FontFace == face and files[nextFont])
	local withoutCleanup = table.clone(environment)
	withoutCleanup.listfiles, withoutCleanup.delfolder = nil, nil
	assert(luau.load(source, { environment = withoutCleanup })().GetFontAsset("moon"))
end

check(template)
check(fs.readFile("source.lua"), true)
print("Font loader: capability gating, glyph lookup, bounded caches, bad downloads, and retries passed")
