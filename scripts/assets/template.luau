local Lucide = {}
local SPRITE_DIRECTORY = "lucide-icons/sprites-" .. (VERSION):gsub("[^%w%-]", "")

local IS_GETCUSTOMASSET_BROKEN = false

if writefile and isfolder and makefolder and getcustomasset then
	if not isfolder("lucide-icons") then
		makefolder("lucide-icons")
	end

	if not isfolder(SPRITE_DIRECTORY) then
		makefolder(SPRITE_DIRECTORY)
	end

	for spritesheet = 1, DATA_SPRITESHEETS do
		if isfile(`{SPRITE_DIRECTORY}/{spritesheet}.png`) then
			continue
		end

		writefile(
			`{SPRITE_DIRECTORY}/{spritesheet}.png`,
			game:HttpGet(
				`https://raw.githubusercontent.com/notpoiu/lucide-roblox-direct/refs/heads/main/spritesheets/{spritesheet}.png`
			)
		)
	end

	local Success, _Error = pcall(function()
		return getcustomasset(`{SPRITE_DIRECTORY}/1.png`)
	end)

	IS_GETCUSTOMASSET_BROKEN = not Success
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

if type(getcustomasset) == "function" then
	local fontCodepoints = DATA_FONT_MAPPINGS
	local fontVersion = DATA_FONT_HASH
	local fontFace

	function Lucide.GetFontAsset(name: string)
		local codepoint = fontCodepoints[name]
		if not codepoint then
			return nil
		end

		if not fontFace then
			assert(writefile and isfile and isfolder and makefolder, "Custom fonts require filesystem support")
			local directory = `lucide-icons/font-{fontVersion}`
			if not isfolder("lucide-icons") then
				makefolder("lucide-icons")
			end
			if not isfolder(directory) then
				makefolder(directory)
			end

			local ttfPath = `{directory}/lucide.ttf`
			if not isfile(ttfPath) then
				writefile(ttfPath, game:HttpGet("https://raw.githubusercontent.com/notpoiu/lucide-roblox-direct/refs/heads/main/fonts/lucide.ttf"))
			end

			local familyPath = `{directory}/lucide.font`
			writefile(familyPath, game:GetService("HttpService"):JSONEncode({
				name = "Lucide",
				faces = {
					{ name = "Regular", weight = 400, style = "normal", assetId = getcustomasset(ttfPath) },
				},
			}))
			fontFace = Font.new(getcustomasset(familyPath))
		end

		return { FontFace = fontFace, Text = utf8.char(codepoint) }
	end
end

return Lucide
