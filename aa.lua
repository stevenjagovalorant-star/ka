-- ============================================================================
--  ROOXHUB - LICENSE GUARD  (sumber bersih, siap di-obfuscate)
-- ============================================================================
--  Dipakai oleh TemplateUi.lua:
--      local factory = loadstring(game:HttpGet(GUARD_URL))()
--      factory(ctx, cfg)
--
--  Tugas: setiap cfg.CHECK_INTERVAL detik, panggil Junkie.check_key(key) dengan
--  key dari cache file (ditulis loader). Bila server bilang key expired /
--  invalidated, langsung Kick player dengan pesan custom. TANPA stop hub.
--
--  Catatan untuk obfuscator:
--    * Tanpa loadstring ganda di dalam modul (SDK dimuat sekali via HttpGet).
--    * Tanpa trik _G / setfenv aneh; cukup closure standar.
--    * Semua operasi jaringan / I/O dibungkus pcall.
-- ============================================================================

return function(ctx, cfg)
    cfg = type(cfg) == "table" and cfg or {}

    local loadFn = loadstring
    if type(loadFn) ~= "function" then
        loadFn = rawget(_G, "load")
    end

    local CONFIG = {
        KeyCacheFile   = cfg.KeyCacheFile or "RooxHub_key.txt",
        SDK_URL        = cfg.SDK_URL or "https://jnkie.com/sdk/library.lua",
        SERVICE        = cfg.SERVICE or "104136",
        IDENTIFIER     = cfg.IDENTIFIER or "1219288",
        CHECK_INTERVAL = tonumber(cfg.CHECK_INTERVAL) or 3600,
        KICK_MESSAGE   = cfg.KICK_MESSAGE
            or "[RooxHub] Key kamu sudah expired. Ambil key baru di https://rooxhub.my.id/key lalu jalankan ulang script.",
        KICK_ON        = type(cfg.KICK_ON) == "table"
            and cfg.KICK_ON
            or { KEY_EXPIRED = true, KEY_INVALIDATED = true },
    }

    local M = { active = false, stopped = false }

    local function stop()
        M.stopped = true
        M.active = false
    end

    -- Anti-dobel: bila guard lama sudah jalan, hentikan dulu.
    local genv = (type(getgenv) == "function" and getgenv()) or _G
    local registryKey = "__RooxHub_LicenseGuard"
    local prev = genv[registryKey]
    if type(prev) == "table" and type(prev.stop) == "function" then
        pcall(prev.stop)
    end
    genv[registryKey] = M

    local function readKey()
        if type(readfile) ~= "function" then return nil end
        local ok, data = pcall(readfile, CONFIG.KeyCacheFile)
        if not ok or type(data) ~= "string" then return nil end
        local key = data:gsub("%s+", "")
        if #key > 0 then return key end
        return nil
    end

    local function loadSdk()
        if type(game.HttpGet) ~= "function" then return nil end
        local okFetch, src = pcall(function() return game:HttpGet(CONFIG.SDK_URL) end)
        if not okFetch or type(src) ~= "string" or #src == 0 then return nil end
        if type(loadFn) ~= "function" then return nil end
        local okCompile, fn = pcall(loadFn, src)
        if not okCompile or type(fn) ~= "function" then return nil end
        local okInit, lib = pcall(fn)
        if not okInit or type(lib) ~= "table" then return nil end
        pcall(function()
            lib.service = CONFIG.SERVICE
            lib.identifier = CONFIG.IDENTIFIER
        end)
        return lib
    end

    local function kick()
        local player = ctx.LocalPlayer
        if not player then return end
        pcall(function() player:Kick(CONFIG.KICK_MESSAGE) end)
        warn("[RooxHub] Key expired / invalidated. Player kicked.")
    end

    -- Bila key cache tidak ada, guard tidak aktif (hindari salah kick).
    local key = readKey()
    if not key then return M end

    local Junkie = loadSdk()
    if not Junkie or type(Junkie.check_key) ~= "function" then return M end

    M.active = true

    task.spawn(function()
        while not M.stopped do
            if type(ctx.alive) == "function" and not ctx.alive() then break end
            task.wait(CONFIG.CHECK_INTERVAL)
            if M.stopped then break end
            if type(ctx.alive) == "function" and not ctx.alive() then break end

            local ok, result = pcall(Junkie.check_key, key)
            if ok and type(result) == "table" then
                if result.valid == true then
                    -- belum expired, lanjut
                else
                    local errCode = tostring(result.error)
                    if CONFIG.KICK_ON[errCode] then
                        kick()
                        M.active = false
                        return
                    end
                    -- error transien / bukan kick-on: abaikan, cek periode berikutnya
                end
            end
            -- pcall gagal (jaringan / exception): abaikan
        end
        M.active = false
    end)

    return M
end
