local Lucide = {}

--// Helpers \\--
local function Check(...)
	for index = 1, select("#", ...) do
		if typeof((select(index, ...))) ~= "function" then return false end
	end
	return true
end

local AssetManager = {}
do
	local BASE_PATH = "lucide-icons"

	AssetManager.Supported = Check(isfile, isfolder, makefolder, readfile, writefile, getcustomasset)
	AssetManager.CanDelete = AssetManager.Supported and Check(listfiles, delfolder)

	function AssetManager.Path(relative: string?): string
		return if relative then `{BASE_PATH}/{relative}` else BASE_PATH
	end

	function AssetManager.EnsureFolder(relative: string?)
		local current = ""
		for _, part in string.split(AssetManager.Path(relative), "/") do
			current = if current == "" then part else `{current}/{part}`
			if not isfolder(current) then
				makefolder(current)
			end
		end
	end

	function AssetManager.IsFile(relative: string): boolean
		local success, result = pcall(isfile, AssetManager.Path(relative))
		return success and result == true
	end

	function AssetManager.IsFolder(relative: string): boolean
		local success, result = pcall(isfolder, AssetManager.Path(relative))
		return success and result == true
	end

	function AssetManager.Read(relative: string): string?
		return if AssetManager.IsFile(relative) then readfile(AssetManager.Path(relative)) else nil
	end

	function AssetManager.Write(relative: string, data: string)
		writefile(AssetManager.Path(relative), data)
	end

	-- Downloads `url` into `relative` unless it is already cached.
	-- `validate` rejects bad responses so they are never cached.
	function AssetManager.Download(relative: string, url: string, validate: ((string) -> boolean)?)
		if AssetManager.IsFile(relative) then return end

		local data = game:HttpGet(url)
		assert(not validate or validate(data), `Invalid download for {relative}`)
		AssetManager.Write(relative, data)
	end

	-- Names of the entries directly inside BASE_PATH
	function AssetManager.ListNames(): { string }
		local names = {}
		for _, entry in listfiles(BASE_PATH) do
			local name = entry:gsub("\\", "/"):gsub("/$", ""):match("([^/]+)$")
			if name then
				table.insert(names, name)
			end
		end
		return names
	end

	function AssetManager.DeleteFolder(relative: string)
		if AssetManager.CanDelete and AssetManager.IsFolder(relative) then
			pcall(delfolder, AssetManager.Path(relative))
		end
	end

	function AssetManager.GetAsset(relative: string): string
		return getcustomasset(AssetManager.Path(relative))
	end
end

-- Only folders matching these are ever deleted, so unrelated folders stay untouched
local CACHE_FOLDER_PATTERNS = {
	"^" .. string.rep("%x", 64) .. "$",
	-- Layouts from older builds
	"^font%-" .. string.rep("%x", 64) .. "$",
	"^sprites%-%d%d%d%d%-%d%d%-%d%dT%d+Z?$",
}

local function IsCacheFolder(name: string): boolean
	for _, pattern in CACHE_FOLDER_PATTERNS do
		if name:match(pattern) then return true end
	end
	return false
end

local function PruneCache(currentFolder: string)
	if not AssetManager.CanDelete then return end

	local markerFile = "cache.txt"
	local current = AssetManager.Path(currentFolder)
	local lines = string.split(AssetManager.Read(markerFile) or "", "\n")
	local previous = if lines[1] == current then lines[2] else lines[1]

	for _, name in AssetManager.ListNames() do
		local path = AssetManager.Path(name)
		if IsCacheFolder(name) and path ~= current and path ~= previous then
			AssetManager.DeleteFolder(name)
		end
	end

	AssetManager.Write(markerFile, current .. "\n" .. (previous or ""))
end

--// Constants \\--
local ASSET_BASE_URL = "https://raw.githubusercontent.com/notpoiu/lucide-roblox-direct/refs/heads/main/"
local ASSET_FOLDER = DATA_ASSET_HASH

--// Sprites \\--
local USE_CUSTOM_SPRITES = false
if AssetManager.Supported then
	USE_CUSTOM_SPRITES = pcall(function()
		AssetManager.EnsureFolder(ASSET_FOLDER)
		for spritesheet = 1, DATA_SPRITESHEETS do
			AssetManager.Download(`{ASSET_FOLDER}/{spritesheet}.png`, `{ASSET_BASE_URL}spritesheets/{spritesheet}.png`, function(data)
				return data:sub(1, 8) == "\137PNG\r\n\26\n" -- PNG header
			end)
		end
		AssetManager.GetAsset(`{ASSET_FOLDER}/1.png`)
	end)
	if USE_CUSTOM_SPRITES then
		pcall(PruneCache, ASSET_FOLDER)
	end
end

local icons = DATA_ICON_MAPPINGS
local iconIndices: { string } = icons[1]
local idIndices: { string } = icons[2]
local iconRegistry: { [number]: { number | { number } } } = icons[3]

Lucide.Icons = iconIndices
function Lucide.GetAsset(name: string)
	local size = 48

	local iconIndex = table.find(iconIndices, name)

	if not iconIndex then
		return nil
	end

	local currentDifference = math.huge
	local currentSize = size

	for registrySize, _ in iconRegistry do
		local diff = math.abs(size - registrySize)

		if diff < currentDifference then
			currentDifference = diff
			currentSize = registrySize
		end
	end

	local icon = iconRegistry[currentSize][iconIndex]
	if icon then
		return {
			IconName = name,
			Url = idIndices[icon[1]],
			ImageRectSize = Vector2.new(icon[2][1], icon[2][2]),
			ImageRectOffset = Vector2.new(icon[3][1], icon[3][2]),
		}
	end

	return nil
end

--// Font \\--
if AssetManager.Supported then
	local fontCodepoints = DATA_FONT_MAPPINGS
	local fontFace

	function Lucide.GetFontAsset(name: string)
		if not fontCodepoints[name] then
			return nil
		end

		if not fontFace then
			local ttfFile = `{ASSET_FOLDER}/lucide.ttf`
			local familyFile = `{ASSET_FOLDER}/lucide.font`

			AssetManager.EnsureFolder(ASSET_FOLDER)
			AssetManager.Download(ttfFile, `{ASSET_BASE_URL}fonts/lucide.ttf`, function(data)
				return data:sub(1, 4) == "\0\1\0\0" -- TrueType header
			end)
			AssetManager.Write(familyFile, game:GetService("HttpService"):JSONEncode({
				name = "Lucide",
				loadStrategy = "sameFamilyOnly",
				faces = {
					{ name = "Regular", weight = 400, style = "normal", assetId = AssetManager.GetAsset(ttfFile) },
				},
			}))

			fontFace = Font.new(AssetManager.GetAsset(familyFile))
		end

		return { FontFace = fontFace, Text = name }
	end
end

return Lucide
