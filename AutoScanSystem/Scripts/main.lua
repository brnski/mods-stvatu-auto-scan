-- AutoScanSystem v1.2
-- Scans all POIs in a solar system automatically when the player scans any one of them.
-- Compatible with UE4SS experimental build for UE 5.6.
-- Author: see Nexus Mods page

local function log(s) print("[AutoScanSystem] " .. s .. "\n") end

local function safeGet(fn)
    local ok, v = pcall(fn)
    return ok and v or nil
end

local function vecDist(a, b)
    if not a or not b then return math.huge end
    local dx = (a.X or 0) - (b.X or 0)
    local dy = (a.Y or 0) - (b.Y or 0)
    local dz = (a.Z or 0) - (b.Z or 0)
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

-- ── Module state ──────────────────────────────────────────────────────────────
local guardActive       = false
local poiCache          = {}
local sysCheckActive    = false
local cacheBuilding     = false
local cachedSystemName  = ""
local propagateGen      = 0   -- incremented on startSystem to cancel in-flight scans
local cachedPawn        = nil -- cached to avoid repeated FindAllOf("STVSectorPawn") calls
local cachedSystems     = nil -- avoids FindAllOf("STVSolarSystem") every 10 s
local startSystem  -- forward declaration; assigned below

-- ── Propagation ───────────────────────────────────────────────────────────────

local function propagate(pawn)
    local myGen = propagateGen  -- capture; if startSystem fires, gen increments and we stop

    local queue = {}
    for _, entry in ipairs(poiCache) do
        if safeGet(function() return entry.poi:IsValid() end) and
           safeGet(function() return entry.owner:IsValid() end) then
            local bScanned = safeGet(function()
                local info = entry.owner:GetPoiInfo()
                return info ~= nil and info.bWasScanned == true
            end)
            if not bScanned then
                table.insert(queue, entry)
            end
        end
    end

    log("Auto-scanning " .. #queue .. " POIs in system")
    if #queue == 0 then
        poiCache = {}
        guardActive = false
        return
    end

    local idx = 0
    local function scanNext()
        if propagateGen ~= myGen then return end  -- system changed; abort
        idx = idx + 1
        if idx > #queue then
            log("Auto-scan complete")
            poiCache = {}   -- drop actor refs; game may destroy POI actors on system-complete
            guardActive = false
            return
        end
        local entry = queue[idx]
        pcall(function()
            if entry.poi:IsValid() and pawn:IsValid() then
                pawn:TryToScanPOI(entry.poi)
            end
        end)
        ExecuteWithDelay(150, scanNext)
    end

    ExecuteWithDelay(100, scanNext)
end

local function findPawn()
    if cachedPawn and safeGet(function() return cachedPawn:IsValid() end) then
        return cachedPawn
    end
    local pawns = FindAllOf("STVSectorPawn")
    if not pawns then cachedPawn = nil; return nil end
    for _, p in ipairs(pawns) do
        if safeGet(function() return p:IsValid() end) then
            cachedPawn = p
            return p
        end
    end
    cachedPawn = nil
    return nil
end

-- ── Cache build ───────────────────────────────────────────────────────────────

local function buildPoiCache()
    poiCache = {}

    local pawn = findPawn()
    if not pawn then log("buildPoiCache: no pawn yet"); return end
    local pawnLoc = safeGet(function() return pawn:K2_GetActorLocation() end)
    if not pawnLoc then log("buildPoiCache: no pawn location"); return end

    local systems = FindAllOf("STVSolarSystem")
    if not systems or #systems == 0 then log("buildPoiCache: no systems found"); return end
    cachedSystems = systems

    -- Find player's current system.
    local currentSys, pawnDistToSys = nil, math.huge
    for _, sys in ipairs(systems) do
        if safeGet(function() return sys:IsValid() end) then
            local loc = safeGet(function() return sys:K2_GetActorLocation() end)
            if loc then
                local d = vecDist(pawnLoc, loc)
                if d < pawnDistToSys then pawnDistToSys, currentSys = d, sys end
            end
        end
    end
    if not currentSys then log("buildPoiCache: no current system"); return end
    local currentSysName = safeGet(function() return currentSys:GetFullName() end) or ""
    cachedSystemName = currentSysName

    local allPois = FindAllOf("STVPointOfInterestBase")
    if not allPois then log("buildPoiCache: no POIs found yet"); return end

    for _, poi in ipairs(allPois) do
        local outerCls = safeGet(function() return poi:GetOuter():GetClass():GetFName():ToString() end)
        if not outerCls or outerCls == "Package" then goto continue end
        if not safeGet(function() return poi:IsValid() end) then goto continue end

        local owner = safeGet(function() return poi:GetOwner() end)
        if not owner or not safeGet(function() return owner:IsValid() end) then goto continue end

        -- Skip POIs owned directly by a solar system actor.
        local ownerCls = safeGet(function() return owner:GetClass():GetFName():ToString() end) or ""
        if ownerCls:find("SolarSystem") then goto continue end

        -- Only include POIs whose nearest system is the current system.
        local ownerLoc = safeGet(function() return owner:K2_GetActorLocation() end)
        if not ownerLoc then goto continue end

        local nearestSysName, nearestDist = "", math.huge
        for _, sys in ipairs(systems) do
            if safeGet(function() return sys:IsValid() end) then
                local loc = safeGet(function() return sys:K2_GetActorLocation() end)
                if loc then
                    local d = vecDist(ownerLoc, loc)
                    if d < nearestDist then
                        nearestDist = d
                        nearestSysName = safeGet(function() return sys:GetFullName() end) or ""
                    end
                end
            end
        end
        if nearestSysName ~= currentSysName then goto continue end

        local fullName = safeGet(function() return poi:GetFullName() end)
        if not fullName then goto continue end

        table.insert(poiCache, {poi = poi, owner = owner, fullName = fullName})
        ::continue::
    end
    log("POI cache built: " .. #poiCache .. " POIs in current system")
end

-- ── System-change fallback check (10 s) ──────────────────────────────────────
-- Primary detection for system changes is OnMovementEnded_BP hook.
-- This runs every 10 s as a fallback for edge cases (hook not yet registered,
-- player zooms into a system view without traveling, etc.).

local function checkSystemChange()
    if not sysCheckActive then return end
    ExecuteWithDelay(10000, checkSystemChange)
    if not cachedSystems then return end
    local pawn = findPawn()
    if not pawn then return end
    local pawnLoc = safeGet(function() return pawn:K2_GetActorLocation() end)
    if not pawnLoc then return end
    local nearestName, nearestDist = "", math.huge
    for _, sys in ipairs(cachedSystems) do
        if safeGet(function() return sys:IsValid() end) then
            local loc = safeGet(function() return sys:K2_GetActorLocation() end)
            if loc then
                local d = vecDist(pawnLoc, loc)
                if d < nearestDist then
                    nearestDist = d
                    nearestName = safeGet(function() return sys:GetFullName() end) or ""
                end
            end
        end
    end
    if nearestName ~= "" and nearestName ~= cachedSystemName then
        log("Entered new system, rebuilding cache")
        startSystem()
    end
end

startSystem = function()
    if cacheBuilding then return end
    cacheBuilding = true
    sysCheckActive = false
    guardActive = false
    propagateGen = propagateGen + 1  -- cancel any in-flight propagation from prior system
    cachedPawn = nil
    cachedSystems = nil
    local function tryBuild()
        buildPoiCache()
        if #poiCache > 0 then
            cacheBuilding = false
            sysCheckActive = true
            ExecuteWithDelay(10000, checkSystemChange)
        else
            ExecuteWithDelay(2000, tryBuild)
        end
    end
    tryBuild()
end

local function tryRegisterHooks()
    local ok = pcall(function()
        -- OnSectorCompletelyLoaded: fires when a sector finishes loading
        -- (save load / new game; would also cover sector-to-sector travel if it exists).
        -- Note: UE4SS experimental only fires pre-hooks reliably for Blueprint functions.
        RegisterHook("/Game/STVoyager/JourneyGenerator/Blueprints/BP_STVSolarSystem.BP_STVSolarSystem_C:OnSectorCompletelyLoaded",
            function(self) startSystem() end,
            function(self) end
        )
        -- ReceiveBeginPlay on pawn: fires when a game session starts (load save, new game).
        -- Cache the pawn from `self` immediately — FindAllOf("STVSectorPawn") can lag
        -- up to ~2 minutes behind BeginPlay on some save loads.
        RegisterHook("/Game/STVoyager/JourneyGenerator/Blueprints/BP_SectorPawn.BP_SectorPawn_C:ReceiveBeginPlay",
            function(self)
                pcall(function()
                    local p = self:get()
                    if p and p:IsValid() then cachedPawn = p end
                end)
                startSystem()
            end,
            function(self) end
        )
        -- OnMovementEnded_BP: fires when inter-system travel completes.
        -- Immediately rebuilds the POI cache for the new system instead of
        -- waiting for the 10 s fallback check.
        RegisterHook("/Game/STVoyager/JourneyGenerator/Blueprints/BP_SectorPawn.BP_SectorPawn_C:OnMovementEnded_BP",
            function(self) startSystem() end,
            function(self) end
        )
        -- AudioPassConfirmScan: fires when any scan completes (manual or auto).
        -- guardActive is true during auto-scans, so only manual player scans trigger
        -- propagation. Replaces the 250 ms poll for scan detection.
        RegisterHook("/Game/STVoyager/JourneyGenerator/Blueprints/BP_SectorPawn.BP_SectorPawn_C:AudioPassConfirmScan",
            function(self)
                if guardActive or cacheBuilding or #poiCache == 0 then return end
                local pawn = findPawn()
                if not pawn then return end
                guardActive = true
                ExecuteWithDelay(50, function()
                    propagate(pawn)
                end)
            end,
            function(self) end
        )
    end)
    if ok then
        log("Hooks registered")
    else
        ExecuteWithDelay(2000, tryRegisterHooks)
    end
end

-- Start cache building immediately, independent of hook registration.
-- Hooks can take tens of seconds to register; startSystem retries internally
-- every 2 s (via tryBuild) until the pawn and POIs are available.
ExecuteWithDelay(1000, function()
    startSystem()
    tryRegisterHooks()
end)

log("v1.2 loaded")
