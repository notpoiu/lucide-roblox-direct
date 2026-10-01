--// Lune stuff \\--
local DateTime = require("@lune/datetime")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local task = require("@lune/task")
local process = require("@lune/process")
local stdio = require("@lune/stdio")
local serde = require("@lune/serde")

--// Types \\--
type UploadAssetOptions = {
	path: string,
	name: string,
	description: string?,
}

--// Constants \\--
local BUILD_VERSION = DateTime.now():toIsoDate()
local ROBLOX_API_TOKEN = process.env["ROBLOX_API_TOKEN"]
local ROBLOX_CREATOR_ID = process.env["ROBLOX_CREATOR_ID"]

--// Serialization \\--
local LuaEncode = require("./utils/LuaEncode")

--// Utility functions \\--
function ReplaceScriptGlobals(script: string, replacements: { [string]: string }): string
	for key, value in replacements do
		script = script:gsub(key, value)
	end
	return script
end

function RunCommand(cmd: string, cwd: string?, check: boolean?): any
	local checkFlag = if check == nil then true else check

	local options = {}
	if cwd then
		options.cwd = cwd
	end

	local result = process.exec("sh", { "-c", cmd }, options)

	if checkFlag and not result.ok then
		stdio.ewrite(`Error running command: {cmd}\n`)
		stdio.ewrite(`Exit code: {result.code}\nOutput:{result.stdout}\n{result.stderr}`)
	end

	return result
end

function UploadImageAssetToRoblox(options: UploadAssetOptions): string
	assert(ROBLOX_API_TOKEN, "ROBLOX_API_TOKEN environment variable is not set")

	local Result = RunCommand(
		`python scripts/utils/Upload.py {options.path} --name "{options.name}" --description "{options.description or ""}" --auth "{ROBLOX_API_TOKEN}" --creator-id {ROBLOX_CREATOR_ID}`,
		nil,
		true
	)

	if not Result.ok then
		stdio.ewrite(`Failed to upload image asset: {Result.stderr}\n`)
		process.exit(1)
	end

	local CleanedOutput = Result.stdout:gsub("\n", ""):gsub("\r", "")
	CleanedOutput = CleanedOutput:gsub(" ", "")

	return CleanedOutput
end

--// Setup functions \\--
function SetupDirectories()
	print("Setting up directories...")

	if not fs.isDir("build") then
		fs.writeDir("build")
	end

	if fs.isDir(".tarmac-debug") then
		fs.removeDir(".tarmac-debug")
	end

	if fs.isDir("build/outputs") then
		fs.removeDir("build/outputs")
	end

	fs.writeDir("build/outputs")
	fs.writeDir("build/outputs/formatted_icons")
end

function SetupLucide()
	if not fs.isDir("build/lucide") then
		print("Cloning Lucide repository...")
		RunCommand("git clone --filter=blob:none --sparse https://github.com/lucide-icons/lucide.git", "build")
	end

	RunCommand("git sparse-checkout set --no-cone /icons/ /LICENSE", "build/lucide")
	RunCommand("git pull origin main", "build/lucide")
end

--// Conversion and Processing Functions \\--
function ConvertSvgsToPngs()
	local function ConvertSvgToPng(svgFile: string): string
		local svgPath = svgFile:match("([^/]+)%.svg$") or svgFile
		local pngFilename = svgPath .. ".png"
		local outputPath = `build/outputs/formatted_icons/{pngFilename}`

		local cmd =
			`inkscape "{svgFile}" --export-type="png" --export-filename="{outputPath}" --export-width=24 --export-height=24 --export-background-opacity=0`

		local result = RunCommand(cmd, nil, false)
		if result.ok then
			return `✓ Converted {svgFile:match("[^/]+$")}`
		else
			return `✗ Failed to convert {svgFile:match("[^/]+$")}: Exit code {result.code}`
		end
	end

	print("Converting SVG files to PNG...")

	local svgFiles = {}
	if fs.isDir("build/lucide/icons") then
		for _, file in fs.readDir("build/lucide/icons") do
			if file:match("%.svg$") then
				table.insert(svgFiles, `build/lucide/icons/{file}`)
			end
		end
	end

	if #svgFiles == 0 then
		print("No SVG files found!")
		return
	end

	print(`Found {#svgFiles} SVG files to convert...`)

	local completed = 0
	for i, svgFile in ipairs(svgFiles) do
		task.spawn(function()
			local message = ConvertSvgToPng(svgFile)
			completed += 1

			print(`[{completed}/{#svgFiles}] {message}`)
		end)

		if i % 10 == 0 then
			task.wait(0.4)
		end
	end

	repeat
		task.wait(0.1)
	until completed == #svgFiles
end

function ProcessPngs()
	local function ProcessPng(pngFile: string): string
		local cmd =
			`magick "{pngFile}" -channel RGB -negate +channel -alpha on -type TrueColorAlpha -colorspace sRGB -define png:color-type=6 "{pngFile}"`

		local result = RunCommand(cmd, nil, false)
		if result.ok then
			return `✓ Processed {pngFile:match("[^/]+$")}`
		else
			return `✗ Failed to process {pngFile:match("[^/]+$")}: Exit code {result.code}`
		end
	end

	print("Processing PNG files with ImageMagick...")

	local pngFiles = {}
	if fs.isDir("build/outputs/formatted_icons") then
		for _, file in fs.readDir("build/outputs/formatted_icons") do
			if file:match("%.png$") then
				table.insert(pngFiles, `build/outputs/formatted_icons/{file}`)
			end
		end
	end

	if #pngFiles == 0 then
		print("No PNG files found to process!")
		return
	end

	print(`Found {#pngFiles} PNG files to process...`)

	-- Create tasks for concurrent processing
	local completed = 0

	for i, pngFile in ipairs(pngFiles) do
		task.spawn(function()
			local result = ProcessPng(pngFile)
			completed += 1

			print(`[{completed}/{#pngFiles}] {result}`)
		end)

		if i % 100 == 0 then
			task.wait(0.65)
		end
	end

	repeat
		task.wait(0.1)
	until completed == #pngFiles
end

--// Main \\--
print("Starting Lucide icon update script...")

SetupDirectories()
SetupLucide()

assert(RunCommand("npm run build:font").ok, "Failed to generate Lucide font")
local FontData = serde.decode("json", fs.readFile("fonts/codepoints.json"))

ConvertSvgsToPngs()
ProcessPngs()

-- Create spritesheet
print("Creating spritesheet...")
local SpriteSheetResult = RunCommand("tarmac sync --target debug")
if not SpriteSheetResult.ok then
	print("Error occured while creating spritesheet via tarmac")
	process.exit(1)
end

-- Fetch icon mappings
local TarmacIconMappings = {}
do
	local Vector2Library = [[local Vector2 = {}

function Vector2.new(x: number, y: number)
    return { x, y }
end]]

	local CorrectedMappings = fs.readFile("build/outputs/mappings.lua"):gsub("repeat = {", '["repeat"] = {')
	TarmacIconMappings = luau.load(table.concat({
		Vector2Library,
		CorrectedMappings,
	}, "\n"))()["formatted_icons"]
end

-- Move Sprites to spritesheets directory
local SpritesheetFiles = fs.readDir(".tarmac-debug")
if fs.isDir("spritesheets") then
	fs.removeDir("spritesheets")
end
fs.writeDir("spritesheets")

for _, file in SpritesheetFiles do
	fs.copy(`.tarmac-debug/{file}`, `spritesheets/{file}.png`)
end

-- Generate icon data
local IconData = {}
local InsertedIds = {}
do
	local IconNames = {}
	local ImageAssets = {}
	local RectInfo = {}

	for name, data in TarmacIconMappings do
		local id = data.Image:gsub("rbxassetid://", "")
		id = tonumber(id)

		if not InsertedIds[id] then
			InsertedIds[id] = true
			ImageAssets[id] = data.Image
		end

		table.insert(IconNames, name)

		table.insert(RectInfo, {
			tonumber(id),
			data.ImageRectSize,
			data.ImageRectOffset,
		})
	end

	IconData = { IconNames, ImageAssets, { [48] = RectInfo } }
end

local SerializedData = LuaEncode(IconData)

local RealRobloxContentID = {}
for id, _ in InsertedIds do
	local assetId = UploadImageAssetToRoblox({
		path = `spritesheets/{id}.png`,
		name = `Lucide Spritesheet {id}`,
		description = `Spritesheet for all lucide icons. Built at {BUILD_VERSION}.`,
	})

	print("Successfully uploaded a Lucide Spritesheet with Content ID:", assetId)

	RealRobloxContentID[id] = assetId
end

for id, _ in InsertedIds do
	SerializedData = SerializedData:gsub(
		`"rbxassetid://{id}"`,
		`if USE_CUSTOM_SPRITES then AssetManager.GetAsset(ASSET_FOLDER .. "/{id}.png") else "rbxassetid://{RealRobloxContentID[id]}"`
	)
end

-- Hash every generated asset so the loader caches each build in its own folder
local AssetHashes = { FontData.version }
table.sort(SpritesheetFiles)
for _, file in SpritesheetFiles do
	table.insert(AssetHashes, serde.hash("sha256", fs.readFile(`spritesheets/{file}.png`)))
end
local AssetHash = serde.hash("sha256", table.concat(AssetHashes, "\n"))

-- Updating source.lua
local Template = fs.readFile("scripts/assets/template.luau")

fs.writeFile(
	"source.lua",
	ReplaceScriptGlobals(Template, {
		["DATA_SPRITESHEETS"] = #SpritesheetFiles,
		["DATA_ICON_MAPPINGS"] = SerializedData,
		["DATA_FONT_MAPPINGS"] = LuaEncode(FontData.icons),
		["DATA_ASSET_HASH"] = `"{AssetHash}"`,
	})
)

print("Lucide icon update script completed successfully!")
