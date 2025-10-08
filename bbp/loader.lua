local loader = {
	localeNames = {},
	events = {}
}

local pre = {
	sprites = {},
	sounds = {},
	shaders = {},
	animations = {},
	locales = {},
	states = {},
	entities = {},
	events = {},
	mains = {}
}

local function setModChunkEnvironment(chunk, mod, setDeprecated)
	local env = setmetatable({}, {
		__index = function(t, k)
			if k == "mod" then
				return mod
			end

			-- TODO: remove this later due to deprecation
			-- all of this information is accessible through 'mod'
			if setDeprecated then
				if k == "modId" then
					print("[BB+] The mod " .. mod.id ..
						      " is using the deprecated 'modId' variable which will be removed in a future version. You should use 'mod.id' instead!")
					return mod.id
				end
				if k == "modPath" then
					print("[BB+] The mod " .. mod.id ..
						      " is using the deprecated 'modPath' variable which will be removed in a future version. You should use 'mod.path' instead!")
					return mod.path
				end
				if k == "modData" then
					print("[BB+] The mod " .. mod.id ..
						      " is using the deprecated 'modData' variable which will be removed in a future version. You should use 'mod' instead!")
					return mod
				end
			end

			return _G[k]
		end,
		__newindex = _G
	})
	return setfenv(chunk, env)
end

local function getModConfigRenderer(mod)
	if mod._configRenderer == false then
		return nil
	end

	local path = mod.path .. "/config.lua"
	if not love.filesystem.getInfo(path, 'file') then
		rawset(mod, '_configRenderer', false)
		return nil
	end

	local chunk, errormsg = love.filesystem.load(path)
	if errormsg then
		print("[BB+] Error while loading the config renderer of " .. mod.name .. ". " .. errormsg)
		rawset(mod, '_configRenderer', false)
		return nil
	end

	rawset(mod, '_configRenderer', setModChunkEnvironment(chunk, mod, true))
	if mod._configRenderer == nil then
		print("[BB+] Error while loading the config renderer of " .. mod.name .. ". Unknown error.")
		rawset(mod, '_configRenderer', false)
		return nil
	end

	return mod._configRenderer
end

local function setModEnabled(mod, enabled)
	if enabled == nil then
		enabled = true
	end

	local createFilePath = mod.path .. (enabled and "/.nolovelyignore" or "/.lovelyignore")
	local deleteFilePath = mod.path .. (enabled and "/.lovelyignore" or "/.nolovelyignore")
	local success = true

	if not love.filesystem.getInfo(createFilePath, 'file') then
		success = success and love.filesystem.write(createFilePath, "")
	end

	if love.filesystem.getInfo(deleteFilePath, 'file') then
		success = success and love.filesystem.remove(deleteFilePath)
	end

	if not success then
		return
	end

	rawset(mod, '_enabled', enabled)
end

function loader.loadMods() -- loads mod data, assets, mod icons etc.
	if #bbp.mods ~= 0 then
		print("[BB+] trying to load mods twice..?")
		return
	end

	local modsPath = "Mods"
	local success = love.filesystem.getInfo(modsPath, 'directory')

	if not success then
		print("[BB+] Failed to find Mods directory. Mods won't be loaded.")
		return
	end

	local json = require("lib.json")
	local helpers = require("lib.helpers")
	package.loaded["lib.json"] = nil
	package.loaded["lib.helpers"] = nil

	for _, modDir in ipairs(love.filesystem.getDirectoryItems(modsPath)) do
		if modDir == "lovely" then
			goto continue
		end

		local mod = {
			path = modsPath .. "/" .. modDir,
			id = modDir,
			name = modDir,
			author = "Unknown",
			description = "",
			version = "1.0.0",
			icon = nil,
			defaultConfig = {},
			config = {}
		}
		setmetatable(mod, {
			__index = function(t, k)
				if k == "enabled" then
					return t._enabled
				elseif k == "configRenderer" then
					return getModConfigRenderer(t)
				end
				return rawget(t, k)
			end,
			__newindex = function(t, k, v)
				if k == "enabled" then
					setModEnabled(t, v)
				end
			end
		})

		if not love.filesystem.getInfo(mod.path, 'directory') then
			goto continue
		end

		local lovelyignore = love.filesystem.getInfo(mod.path .. "/.lovelyignore", 'file')
		local nolovelyignore = love.filesystem.getInfo(mod.path .. "/.nolovelyignore", 'file')
		if lovelyignore ~= nil then
			mod.enabled = false
		elseif nolovelyignore ~= nil then
			mod.enabled = true
		end

		if love.filesystem.getInfo(mod.path .. "/mod.json", 'file') then
			local modData = json.decode(love.filesystem.read(mod.path .. "/mod.json"))
			mod.id = modData.id or mod.id
			mod.name = modData.name or mod.name
			mod.author = modData.author or mod.author
			mod.description = modData.description or mod.description
			mod.version = modData.version or mod.version
			mod.defaultConfig = modData.config or mod.defaultConfig
			mod.config = helpers.copytable(mod.defaultConfig)

			-- TODO: deprecated
			if modData.enabled ~= nil then
				print("[BB+] '" .. mod.path .. "/mod.json" .. "': 'enabled' is deprecated in favor of the .lovelyignore file")
				if mod.enabled == nil then
					mod.enabled = modData.enabled
					if modData.enabled == false then
						local disabledPath = "Mods/disabled/" .. mod.id .. "/lovely/"
						if love.filesystem.getInfo(disabledPath, 'directory') then
							bbp.utils.moveDirectory(disabledPath, mod.path .. "/lovely/")
						end
					end
				end
			end
		end
		if mod.enabled == nil then
			mod.enabled = true
		end

		if love.filesystem.getInfo(mod.path .. "/config.json", 'file') then
			local modConfig = json.decode(love.filesystem.read(mod.path .. "/config.json"))
			if modConfig then
				-- a shallow copy is enough in this case
				for k, v in pairs(modConfig) do
					mod.config[k] = v
				end
			end
		end

		bbp.mods[mod.id] = mod
		print("[BB+] Registered mod '" .. mod.name .. "' by " .. mod.author .. ".")

		if not mod.enabled then
			goto continue
		end

		local assetsPath = mod.path .. "/assets"
		if love.filesystem.getInfo(assetsPath, 'directory') then
			pre.sprites[mod] = assetsPath .. "/textures"
			pre.sounds[mod] = assetsPath .. "/sounds"
			pre.shaders[mod] = assetsPath .. "/shaders"
			pre.animations[mod] = assetsPath .. "/animations"
			pre.locales[mod] = assetsPath .. "/lang"
		end

		if love.filesystem.getInfo(mod.path .. "/states", 'directory') then
			pre.states[mod] = mod.path .. "/states"
		end

		if love.filesystem.getInfo(mod.path .. "/entities", 'directory') then
			pre.entities[mod] = mod.path .. "/entities"
		end

		if love.filesystem.getInfo(mod.path .. "/events", 'directory') then
			pre.events[mod] = mod.path .. "/events"
		end

		if love.filesystem.getInfo(mod.path .. "/main.lua") then
			local chunk, errormsg = love.filesystem.load(mod.path .. "/main.lua")
			if errormsg then
				print("[BB+] Error while loading the main.lua file of '" .. mod.id .. "': " .. errormsg)
			else
				table.insert(pre.mains, setModChunkEnvironment(chunk, mod, true))
			end
		end

		if love.filesystem.getInfo(mod.path .. "/load.lua") then
			local chunk, errormsg = love.filesystem.load(mod.path .. "/load.lua")
			if errormsg then
				print("[BB+] Error while loading the load.lua file of '" .. mod.id .. "': " .. errormsg)
			else
				setModChunkEnvironment(chunk, mod, false)()
			end
		end

		::continue::
	end

	print("[BB+] Finished loading all mods! :D")
end

function loader.loadSprites(sprites)
	for _, v in pairs(pre.sprites) do
		bbp.utils.loopFiles(sprites, v, function(tbl, path, fileName)
			print("[BB+] injecting sprite " .. path .. "...")
			tbl[fileName] = love.graphics.newImage(path)
		end)
	end
	bbp.utils.printTable(sprites, "Sprites:")
	pre.sprites = nil
end

function loader.loadSounds(sounds)
	for _, v in pairs(pre.sounds) do
		bbp.utils.loopFiles(sounds, v, function(tbl, path, fileName)
			print("[BB+] injecting sound " .. path .. "...")
			tbl[fileName] = love.sound.newSoundData(path)
		end)
	end
	bbp.utils.printTable(sounds, "Sounds:")
	pre.sounds = nil
end

function loader.loadShaders(shaders)
	for _, v in pairs(pre.shaders) do
		bbp.utils.loopFiles(shaders, v, function(tbl, path, fileName)
			print("[BB+] injecting shader " .. path .. "...")
			tbl[fileName] = love.graphics.newShader(path)
		end)
	end
	bbp.utils.printTable(shaders, "Shaders:")
	pre.shaders = nil
end

function loader.loadAnimations(animations)
	for _, v in pairs(pre.animations) do
		bbp.utils.loopFiles(animations, v, function(tbl, path, fileName)
			if not path:endswith(".png") then
				return
			end
			print("[BB+] injecting animation " .. path .. "...")
			local data = bbp.utils.getFileParent(path) .. "data.json"
			if not love.filesystem.getInfo(data, 'file') then
				print("[BB+] Error while injecting animation '" .. path .. "'. The '" .. data .. "' file is missing!")
			end
			tbl[fileName] = ez.newjson(path, data)
		end)
	end
	bbp.utils.printTable(animations, "Animations:")
	pre.animations = nil
end

function loader.loadLocales()
	for _, v in pairs(pre.locales) do
		bbp.utils.loopFiles({}, v, function(_, path, _)
			print("[BB+] injecting locale " .. path .. "...")
			local locale = json.decode(love.filesystem.read(path))
			for key, locs in pairs(locale) do
				for lang, text in pairs(locs) do
					if not loader.localeNames[lang] then
						loader.localeNames[lang] = true
					end
					if not loc.json[key] then
						loc.json[key] = {}
					end
					if not loc.json[key][lang] then
						loc.json[key][lang] = {}
					end
					loc.json[key][lang] = text
				end
			end
		end)
	end
	pre.locales = nil
end

function loader.loadStates()
	for mod, v in pairs(pre.states) do
		bbp.utils.loopFiles({}, v, function(_, path, fileName)
			print("[BB+] injecting state " .. path .. "...")
			bs.fromPath(fileName, path)
			if bs.states[fileName] then
				setModChunkEnvironment(bs.states[fileName], mod)
			end
		end)
	end
	pre.states = nil
end

function loader.loadEntities()
	for mod, v in pairs(pre.entities) do
		bbp.utils.loopFiles({}, v, function(_, path, fileName)
			print("[BB+] injecting entity " .. path .. "...")
			em.new(path, fileName)
			if em.entities[fileName] then
				setModChunkEnvironment(bs.states[fileName], mod)
			end
		end)
	end
	pre.entities = nil
end

function loader.loadEvents(findFiles)
	for _, v in pairs(pre.events) do
		print("[BB+] Finding events inside " .. v)
		findFiles(v)
		table.insert(bbp.loader.events, v)
	end
	pre.events = nil
end

function loader.loadIcons()
	for _, mod in pairs(bbp.mods) do
		if love.filesystem.getInfo(mod.path .. "/icon.png", 'file') then
			local icon = love.graphics.newImage(mod.path .. "/icon.png")
			local width, height = icon:getDimensions()
			if width ~= 73 or height ~= 33 then
				print("[BB+] Mod " .. mod.id .. " has invalid icon size. Mod icons must be 73x33.")
			else
				rawset(mod, "icon", icon)
			end
		end
	end
end

function loader.runMains()
	for _, main in ipairs(pre.mains) do
		main()
	end
	pre.mains = nil
end

return loader
