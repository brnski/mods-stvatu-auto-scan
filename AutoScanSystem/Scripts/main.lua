-- AutoScanSystem v1.1
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

-- ── Propagation ───────────────────────────────────────────────────────────────
local guardActive = false

local function propagate(pawn, scannedPoi)
    local scannedOwner = safeGet(function() return scannedPoi:GetOwner() end)
    if not scannedOwner or not safeGet(function() return scannedOwner:IsValid() end) then
        log("Cannot get scanned owner – aborting")
        return
    end

    local scannedLoc = safeGet(function() return scannedOwner:K2_GetActorLocation() end)
    if not scannedLoc then
        log("Cannot get scanned actor location – aborting")
        return
    end

    -- Find the nearest solar system actor to the scanned POI.
    local systems = FindAllOf("STVSolarSystem")
    if not systems or #systems == 0 then
        log("No solar systems found – aborting")
        return
    end

    local bestSystem, bestDist = nil, math.huge
    for _, sys in ipairs(systems) do
        if safeGet(function() return sys:IsValid() end) then
            local loc = safeGet(function() return sys:K2_GetActorLocation() end)
            if loc then
                local d = vecDist(scannedLoc, loc)
                if d < bestDist then bestDist, bestSystem = d, sys end
            end
        end
    end

    if not bestSystem then
        log("No valid solar system found – aborting")
        return
    end

    -- Radius = 3× distance from scanned POI to system centre, minimum 100 000 units.
    -- This scales naturally with any system size.
    local sysLoc = safeGet(function() return bestSystem:K2_GetActorLocation() end) or scannedLoc
    local radius = math.max(bestDist * 3.0, 100000)

    -- Enumerate all STVPointOfInterestBase instances.
    -- Skip CDOs (their outer is a UPackage, not an actor) to avoid crashes.
    local allPois = FindAllOf("STVPointOfInterestBase")
    if not allPois then
        log("No POI instances found – aborting")
        return
    end

    local queue = {}
    for _, poi in ipairs(allPois) do
        -- ① Skip CDOs.
        local outerCls = safeGet(function()
            return poi:GetOuter():GetClass():GetFName():ToString()
        end)
        if not outerCls or outerCls == "Package" then goto skip end

        if not safeGet(function() return poi:IsValid() end) then goto skip end

        -- ② Get owner actor.
        local owner = safeGet(function() return poi:GetOwner() end)
        if not owner or not safeGet(function() return owner:IsValid() end) then goto skip end

        -- ③ Skip system-level POIs (sector-map "scan system" action).
        local ownerCls = safeGet(function() return owner:GetClass():GetFName():ToString() end) or ""
        if ownerCls:find("SolarSystem") then goto skip end

        -- ④ Distance filter: keep only POIs within this system's radius.
        local loc = safeGet(function() return owner:K2_GetActorLocation() end)
        if not loc or vecDist(sysLoc, loc) > radius then goto skip end

        -- ⑤ Skip the POI just scanned.
        if safeGet(function() return poi:GetFullName() end) ==
           safeGet(function() return scannedPoi:GetFullName() end) then goto skip end

        -- ⑥ Skip already-scanned POIs.
        local bScanned = safeGet(function()
            local info = owner:GetPoiInfo()
            return info ~= nil and info.bWasScanned == true
        end)
        if bScanned then goto skip end

        table.insert(queue, poi)
        ::skip::
    end

    log("Auto-scanning " .. #queue .. " POIs in system")
    if #queue == 0 then
        guardActive = false
        return
    end

    -- Process queue one POI at a time with a short delay to let the game settle.
    local idx = 0
    local function scanNext()
        idx = idx + 1
        if idx > #queue then
            log("Auto-scan complete")
            ExecuteWithDelay(1000, function() guardActive = false end)
            return
        end
        local poi = queue[idx]
        pcall(function()
            if poi and poi:IsValid() and pawn and pawn:IsValid() then
                pawn:TryToScanPOI(poi)
            end
        end)
        ExecuteWithDelay(150, scanNext)
    end

    ExecuteWithDelay(100, scanNext)
end

-- ── Detection loop ────────────────────────────────────────────────────────────
local lastPoiName = ""
local savedPoiRef = nil

local function doPoll()
    pcall(function()
        local pawns = FindAllOf("STVSectorPawn")
        if not pawns or #pawns == 0 then goto done end
        local pawn = pawns[1]
        if not safeGet(function() return pawn:IsValid() end) then goto done end

        local poi     = safeGet(function() return pawn.PoiSelectedForScanning end)
        local poiName = poi and safeGet(function() return poi:IsValid() and poi:GetFullName() end) or "nil"

        if poiName ~= lastPoiName then
            if poiName ~= "nil" then
                -- Scan started — check for system-level scan and skip it.
                local ownerCls = safeGet(function()
                    local owner = poi:GetOwner()
                    return owner and owner:IsValid() and owner:GetClass():GetFName():ToString()
                end) or ""

                if ownerCls:find("SolarSystem") then
                    savedPoiRef = nil  -- system-level scan; do not propagate
                else
                    savedPoiRef = poi
                end
            else
                -- Scan ended — propagate if we have a saved POI and guard is free.
                if savedPoiRef and not guardActive then
                    guardActive = true
                    local capturedPoi  = savedPoiRef
                    local capturedPawn = pawn
                    savedPoiRef = nil
                    ExecuteWithDelay(50, function()
                        propagate(capturedPawn, capturedPoi)
                    end)
                else
                    savedPoiRef = nil
                end
            end
            lastPoiName = poiName
        end
        ::done::
    end)

    ExecuteWithDelay(500, doPoll)
end

pcall(function() ExecuteWithDelay(2000, doPoll) end)
log("v1.1 loaded")
