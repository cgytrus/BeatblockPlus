local patcher = {
    patches = {}
}

function patcher.patch()
    local upfunc = debug.getinfo(2, 'f').func
    local upmod = nil
    local i = 1
    while true do
        local upname, upvalue = debug.getupvalue(upfunc, i)
        if upname == nil then
            break
        elseif upname == "mod" then
            upmod = upvalue
            break
        end
        i = i + 1
    end

    local module
    local with
    local location, before, at, after
    local mod
    local match
    local literal, pattern, luapattern, regex

    function module(self, path)
        self.module = path
        return self
    end

    function with(self, replacer)
        if type(self.module) == "function" then
            self.module = nil
        end

        local patchers
        if self.module == nil then
            patchers = patcher.patches
        elseif type(self.module) == "string" then
            if not patcher.patches[self.module] then
                patcher.patches[self.module] = {}
            end
            patchers = patcher.patches[self.module]
        else
            error("'module' can only be nil or string")
        end

        self.module = nil
        self.before = nil
        self.at = nil
        self.after = nil
        self.with = nil
        self.replacer = replacer

        table.insert(patchers, self)
    end

    function location(self, x)
        if type(self.module) == "function" then
            self.module = nil
        end

        self.before = nil
        self.at = nil
        self.after = nil
        self.with = nil
        self.mod = function(id) return mod(self, x, id) end
        self.literal = function(what) return match(self, x, literal, what) end
        self.pattern = function(what) return match(self, x, pattern, what) end
        self.luapattern = function(what) return match(self, x, luapattern, what) end
        self.regex = function(what) return match(self, x, regex, what) end
        return self
    end
    function before(self)
        return location(self, -1)
    end
    function at(self)
        return location(self, 0)
    end
    function after(self)
        return location(self, 1)
    end

    function mod(self, order, id)
        table.insert(self.priorities, {
            order = order,
            mod = id
        })
        if self.module == nil then
            self.module = module
        end
        self.before = before
        self.at = at
        self.after = after
        self.with = with
        return self
    end

    function match(self, loc, type, what)
        self.mod = nil
        self.literal = nil
        self.pattern = nil
        self.luapattern = nil
        self.regex = nil
        self.times = function(n)
            self.times = nil
            self.to = function(x)
                type(self, loc, what, n, x)
            end
        end
        self.to = function(x)
            self.times = nil
            self.to = nil
            type(self, loc, what, nil, x)
        end
        return self
    end

    function literal(self, loc, what, n, replacement)
        luapattern(self, loc, what:gsub("(%W)","%%%1"), n, replacement:gsub("%%","%%%%"))
    end

    function pattern(self, loc, what, n, replacement)
        -- TODO
    end

    function luapattern(self, loc, what, n, replacement)
        with(self, function(_, data)
            local repl = replacement
            if loc < 0 then
                repl = repl .. '%0'
            elseif loc > 0 then
                repl = '%0' .. repl
            end
            print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!! replacing '" .. what .. "' with '" .. repl)
            return data:gsub(what, repl, n)
        end)
    end

    function regex(self, loc, what, n, replacement)
        -- TODO
    end

    return {
        source = upmod,
        priorities = {},
        module = module,
        before = before,
        at = at,
        after = after,
        with = with
    }
end

function patcher.applyPatches(module, data)
    -- TODO: priority sorting
    local patches = {}
    for _, patch in ipairs(patcher.patches) do
        table.insert(patches, patch)
    end
    if patcher.patches[module] then
        for _, patch in ipairs(patcher.patches[module]) do
            table.insert(patches, patch)
        end
    end

    for _, patch in ipairs(patches) do
        data = patch.replacer(module, data)
    end

    return data
end

-- patch that applies lovely patches
patcher.patch():before().mod(nil):with(function(module, data)
    return lovely.apply_patches('@' .. module, data)
end)

-- replace love fs load with our own
-- TODO: implement mode parameter
love.filesystem.load = function(path)
    print('!!!!!!!! loading ' .. path .. ' !!!!!!!!')
    local data = love.filesystem.read(path)
    --local fun, errormsg = loadstring(data, '@' .. path)
    --data = lovely.apply_patches('@' .. path, data)
    data = patcher.applyPatches(path, data)
    return loadstring(data, '[bb+ patched "' .. path .. '"]')
end

-- TODO: replace load, loadfile, loadstring

-- replace lua loader with our own
-- there might be stuff in preload but we cant do anything about that
package.loaders[2] = function(name)
    local hasSlash = name:contains('/')
    name = name:gsub('%.', '/')

    local paths = love.filesystem.getRequirePath():gsub('%?', name)
    for path in paths:gmatch("([^;]+)") do
        local info = love.filesystem.getInfo(path)
        if info and info.type ~= 'directory' then
            if hasSlash then
                print("Deprecated character in require string (forward slashes), use dots instead.")
            end
            local data = love.filesystem.read(path)
            --local fun, errormsg = loadstring(data, '@' .. path)
            --data = lovely.apply_patches('@' .. path, data)
            data = patcher.applyPatches(path, data)
            local fun, errormsg = love.filesystem.load(path)
            if fun == nil then
                return errormsg
            end
            return setfenv(fun, _G)
        end
    end

    return ("\n\tno '%s' in LOVE game directories."):format(name)
end

--for k, _ in pairs(package.loaded) do
--    print("!!!!!!!! '" .. k .. "' is already loaded !!!!!!!!")
--end
--for k, _ in pairs(package.preload) do
--    print("!!!!!!!! '" .. k .. "' has preload !!!!!!!!")
--end

return patcher
