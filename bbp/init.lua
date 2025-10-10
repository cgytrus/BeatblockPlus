local bbp = {}

bbp.utils = require("bbp.utils")
bbp.patcher = require("bbp.patcher")
bbp.gui = require("bbp.gui")
bbp.loader = require("bbp.loader")

bbp.mods = {}

-- TODO: remove this later due to deprecation
mods = bbp.mods

bbp.config = setmetatable({}, {
    __index = function(_, k)
        return bbp.mods[k].config
    end,
    -- this doesn't work without changing the lua runtime binary but keep it anyway
    __len = function(_)
        return #bbp.mods
    end
})

return setmetatable({}, {
    __index = function(_, k)
        return bbp[k]
    end,
    __newindex = function (_, _, _)
        error("Cannot set members of 'bbp'")
    end
})
