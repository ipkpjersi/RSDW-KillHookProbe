-- KillHookProbe - RuneScape: Dragonwilds diagnostic
--
-- Finds out which game functions actually run when something dies, for mods that need a death or
-- kill event. Many likely-looking functions (ProgressComponent:OnAIKilled, for one) are called
-- straight from C++ and never reach a Lua hook. This finds every reflected function whose name
-- mentions death or kills, hooks them all, and logs each one that actually runs, with its object
-- and first arguments. Kill something, then read the [KillHookProbe] FIRED lines in UE4SS.log.
--
-- The scan runs a few seconds after each map load (blueprint classes such as a creature's only
-- exist once something has loaded them) and again with Ctrl+F12. Functions already hooked are
-- skipped. Remove this mod once the right hook is known.

local TAG = "[KillHookProbe] "
local function log(msg) print(TAG .. tostring(msg) .. "\n") end

local NAME_MATCH = { "death", "died", "dead", "kill", "slain", "defeat" }
-- Names that match the words above but have nothing to do with a creature dying
local NAME_SKIP = { "deadzone", "deadband", "pendingkill", "particle", "killz", "deadblending",
                    "delegatesignature", "onrep_", "killsweetener", "deadend", "killallpopup",
                    "__entrypoint" }
local MAX_HOOKS = 150
local MAX_LOGS_PER_FUNCTION = 20

local hooked = {}       -- function path -> true
local hookCount = 0
local fired = {}        -- function path -> times logged

local function lower(s) return s:lower() end

-- Hooking these is unsafe or pointless: blueprint event graphs (ExecuteUbergraph_*) crash UE4SS
-- when hooked, and getters/queries run every frame without meaning anything died
local PREFIX_SKIP = { "executeubergraph", "get", "is", "has", "can", "should" }

local function interesting(name)
    -- "Skill" contains "kill"; hooking every skill function (and a skill widget's event graph)
    -- crashed the game while a world was loading, so drop the word before matching
    local n = lower(name):gsub("skill", "")
    for _, s in ipairs(PREFIX_SKIP) do
        if n:sub(1, #s) == s then return false end
    end
    for _, s in ipairs(NAME_SKIP) do
        if n:find(s, 1, true) then return false end
    end
    for _, s in ipairs(NAME_MATCH) do
        if n:find(s, 1, true) then return true end
    end
    return false
end

-- Short description of a hook parameter: an object's class and name, or a plain value
local function describe(param)
    local okG, v = pcall(function() return param:get() end)
    if not okG then return "?" end
    if type(v) ~= "userdata" then return tostring(v) end
    local okN, full = pcall(function() return v:GetFullName() end)
    if okN and type(full) == "string" then return full end
    local okS, s = pcall(function() return v:ToString() end)
    if okS and type(s) == "string" then return s end
    return "userdata"
end

local function hookFunction(path)
    if hooked[path] or hookCount >= MAX_HOOKS then return end
    hooked[path] = true
    local ok = pcall(RegisterHook, path, function(self, ...)
        local n = (fired[path] or 0) + 1
        fired[path] = n
        if n > MAX_LOGS_PER_FUNCTION then return end
        local parts = { "FIRED " .. path, "self=" .. describe(self) }
        for i, p in ipairs({ ... }) do
            if i > 4 then break end
            parts[#parts + 1] = "arg" .. i .. "=" .. describe(p)
        end
        log(table.concat(parts, "  "))
    end)
    if ok then
        hookCount = hookCount + 1
        log("hooked " .. path)
    end
end

local function scan()
    local started = os.clock()
    local found = {}
    local okE, err = pcall(ForEachUObject, function(obj)
        local okC, cls = pcall(function() return obj:GetClass():GetFName():ToString() end)
        if not okC or cls ~= "Function" then return end
        local okN, name = pcall(function() return obj:GetFName():ToString() end)
        if not okN or not interesting(name) then return end
        local okF, full = pcall(function() return obj:GetFullName() end)
        if not okF or type(full) ~= "string" then return end
        -- "Function /Script/Dominion.AiDeathComponent:HandleDeath" -> "/Script/Dominion.AiDeathComponent:HandleDeath"
        local path = full:match("^%S+%s+(.+)$")
        if not path or path:find("Default__", 1, true) then return end
        -- Engine and editor-only modules are noise; the game's own code is Dominion, Redpoint and /Game blueprints
        if path:sub(1, 6) == "/Game/" or path:find("^/Script/Dominion") or path:find("^/Script/Redpoint")
            or path:find("^/Script/GameplayAbilities") then
            found[#found + 1] = path
        end
    end)
    if not okE then
        log("ForEachUObject failed: " .. tostring(err))
        return
    end
    table.sort(found)
    local before = hookCount
    for _, path in ipairs(found) do hookFunction(path) end
    log(string.format("scan: %d matching functions, %d newly hooked, %d hooked in total, %.2f s",
        #found, hookCount - before, hookCount, os.clock() - started))
end

local function scanSoon(ms)
    ExecuteWithDelay(ms, function() ExecuteInGameThread(scan) end)
end

pcall(RegisterLoadMapPostHook, function() scanSoon(8000) end)
pcall(RegisterKeyBind, Key.F12, { ModifierKey.CONTROL }, function() ExecuteInGameThread(scan) end)
scanSoon(15000)
log("loaded. Kill something, then look for FIRED lines. Ctrl+F12 rescans.")
