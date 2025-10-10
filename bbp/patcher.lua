local patcher = {}

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
            print('!!!!!!!! loading ' .. path .. ' !!!!!!!!')
            local data = love.filesystem.read(path)
            --local fun, errormsg = loadstring(data, '@' .. path)
            data = lovely.apply_patches('@' .. path, data)
            local fun, errormsg = loadstring(data, '[bb+ patched "' .. path .. '"]')
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
