--[[
    ========================================
    🌱 AutoPlace Module - Plant Vs Brainrot
    ========================================
    
    Purpose: Automatically place plants from backpack to available plots
    Architecture: Event-driven + polling hybrid for efficiency
    
    Author: AI Assistant
    Version: 1.0.0
]]

local AutoPlace = {
    Version = "2.0.0",
    
    -- State
    IsRunning = false,
    TotalPlacements = 0,
    IsProcessing = false,
    
    -- Cached Spots
    CachedSpots = {},
    SpotsCacheValid = false,
    
    -- OPTIMIZED: Row Count Cache (O(1) lookup instead of O(n) scan)
    RowCounts = {},  -- {["1"] = 3, ["2"] = 5, ...} - Instant count!
    FullRows = {},   -- {["2"] = true, ["5"] = true} - Skip full rows instantly
    MaxPlantsPerRow = 5,
    
    -- Used CFrames (prevent placing in same spot twice)
    UsedCFrames = {},
    
    -- OPTIMIZED: Available Plants Cache (O(1) check instead of scanning backpack)
    AvailablePlants = {},  -- {[tool] = true} - Track what's available
    
    -- Plant Data Cache (avoid repeated ReplicatedStorage reads)
    PlantDataCache = nil,
    PlantNamesList = {},
    
    -- OPTIMIZED: Selected plants as a set for O(1) lookup
    SelectedPlantsSet = {},
    
    -- Auto Pick Up State
    TotalPickUps = 0,
    PlantMonitorConnections = {},
    
    -- Event Connections
    BackpackConnection = nil,
    ChildAddedConnections = {},
    PlotAttributeConnections = {},
    
    -- OPTIMIZED: Event Debouncing (prevent spam processing)
    LastEventTime = 0,
    EventDebounceInterval = 0.15,  -- Minimum time between event triggers
    
    -- OPTIMIZED: Processing Queue (batch multiple placements)
    PlacementQueue = {},
    IsProcessingQueue = false,
    
    -- Task Management (spam toggle prevention with zero-cost generation)
    StartGeneration = 0,  -- Increment on each Start(), tasks check if they're outdated
    
    -- Dependencies (Set by Main.lua)
    Services = nil,
    References = nil,
    Settings = nil,
    Brain = nil
}

--[[
    ========================================
    Initialization
    ========================================
--]]

-- Rebuild selected plants set for O(1) lookup
function AutoPlace.RebuildPlantsSet()
    AutoPlace.SelectedPlantsSet = {}
    
    if not AutoPlace.Settings then
        return
    end
    
    local selectedPlants = AutoPlace.Settings.SelectedPlants
    if selectedPlants and type(selectedPlants) == "table" then
        for _, plantName in ipairs(selectedPlants) do
            if plantName and type(plantName) == "string" then
                AutoPlace.SelectedPlantsSet[plantName] = true
            end
        end
    end
end

function AutoPlace.Init(services, references, settings, brain)
    AutoPlace.Services = services
    AutoPlace.References = references
    AutoPlace.Settings = settings
    AutoPlace.Brain = brain
    
    return true
end

--[[
    ========================================
    Helper Functions
    ========================================
--]]

-- Format numbers with suffixes (1K, 1M, 1B, etc.)
local function FormatNumber(num)
    if num >= 1000000000000 then
        return string.format("%.2fT", num / 1000000000000)
    elseif num >= 1000000000 then
        return string.format("%.2fB", num / 1000000000)
    elseif num >= 1000000 then
        return string.format("%.2fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.2fK", num / 1000)
    else
        return tostring(math.floor(num))
    end
end

-- Get player's owned plot number
function AutoPlace.GetOwnedPlot()
    local success, plotNum = pcall(function()
        return AutoPlace.References.LocalPlayer:GetAttribute("Plot")
    end)
    
    if success and plotNum then
        return tostring(plotNum)
    end
    
    return nil
end

-- Get all plant names from ReplicatedStorage (cached)
function AutoPlace.GetAllPlants()
    if AutoPlace.PlantDataCache then
        return AutoPlace.PlantDataCache
    end
    
    local plants = {}
    
    pcall(function()
        for _, plant in ipairs(AutoPlace.References.Plants:GetChildren()) do
            table.insert(plants, {
                Name = plant.Name,
                Damage = plant:GetAttribute("Damage") or 0
            })
        end
    end)
    
    table.sort(plants, function(a, b)
        return a.Damage > b.Damage
    end)
    
    AutoPlace.PlantDataCache = plants
    
    -- Build name list for faster lookup
    for _, plant in ipairs(plants) do
        table.insert(AutoPlace.PlantNamesList, plant.Name:lower())
    end
    
    return plants
end

-- Extract plant name from backpack item name (format: "[XX.X kg] PlantName")
local function ExtractPlantName(itemName)
    -- Pattern: "[XX.X kg] Name" -> extract "Name"
    local plantName = itemName:match("%]%s*(.+)$")
    if plantName then
        return plantName:match("^%s*(.-)%s*$") -- Trim whitespace
    end
    return itemName -- Fallback to full name
end

-- Calculate string similarity (0-1, higher = more similar)
local function StringSimilarity(str1, str2)
    str1 = str1:lower()
    str2 = str2:lower()
    
    -- Exact match
    if str1 == str2 then
        return 1.0
    end
    
    -- Length check: If difference > 50%, can't be 80% similar
    local len1, len2 = #str1, #str2
    if math.abs(len1 - len2) > math.max(len1, len2) * 0.5 then
        return 0.0
    end
    
    -- Contains check
    if str1:find(str2, 1, true) or str2:find(str1, 1, true) then
        return 0.9
    end
    
    -- Character comparison with early exit
    local matches = 0
    local minLen = math.min(len1, len2)
    local maxLen = math.max(len1, len2)
    
    for i = 1, minLen do
        if str1:sub(i, i) == str2:sub(i, i) then
            matches = matches + 1
        else
            -- Early exit: Can't reach 80% threshold
            local remaining = minLen - i
            if (matches + remaining) / maxLen < 0.8 then
                return 0.0
            end
        end
    end
    
    return matches / maxLen
end

-- Check if plant name matches any known plant (80% similarity, cached)
function AutoPlace.IsValidPlantName(itemName)
    -- CRITICAL: Reject seeds (they end with " Seed")
    local cleanName = ExtractPlantName(itemName)
    if #cleanName >= 5 and string.sub(cleanName, -5) == " Seed" then
        return false  -- This is a seed, not a plant!
    end
    
    -- Ensure cache is built
    if #AutoPlace.PlantNamesList == 0 then
        AutoPlace.GetAllPlants()
    end
    
    -- Quick lookup against cached names
    for _, plantName in ipairs(AutoPlace.PlantNamesList) do
        if StringSimilarity(cleanName, plantName) >= 0.8 then
            return true
        end
    end
    
    return false
end

-- Get plant info from backpack Tool
function AutoPlace.GetPlantInfo(plantTool)
    local success, info = pcall(function()
        local itemName = plantTool.Name
        local extractedName = ExtractPlantName(itemName)
        
        return {
            Name = extractedName,
            OriginalName = itemName,
            ID = plantTool:GetAttribute("ID"),
            Damage = plantTool:GetAttribute("Damage") or 0
        }
    end)
    
    if success and info.ID then
        return info
    end
    
    return nil
end

-- Check if plant matches user's filter
function AutoPlace.ShouldPlacePlant(plantInfo)
    if not AutoPlace.Settings.AutoPlaceEnabled then
        return false
    end
    
    local damageFilter = AutoPlace.Settings.PlantDamageFilter or 0
    
    -- Check filters
    local hasPlantFilter = next(AutoPlace.SelectedPlantsSet) ~= nil
    local hasDamageFilter = damageFilter > 0
    
    if hasPlantFilter and hasDamageFilter then
        -- Both filters: Plant name must match AND damage >= filter
        local isSelected = AutoPlace.SelectedPlantsSet[plantInfo.Name] == true
        local meetsMinDamage = plantInfo.Damage >= damageFilter
        return isSelected and meetsMinDamage
    elseif hasPlantFilter then
        -- Only name filter: O(1) set lookup
        return AutoPlace.SelectedPlantsSet[plantInfo.Name] == true
    elseif hasDamageFilter then
        -- Only damage filter: Plant damage >= filter
        return plantInfo.Damage >= damageFilter
    else
        -- No filter: Place all plants
        return true
    end
end

--[[
    ========================================
    OPTIMIZED: Row Count Management
    ========================================
    Instead of scanning ALL items every time (O(n)),
    we cache counts and update them when events fire (O(1))!
--]]

-- Update row count cache and full row status
function AutoPlace.UpdateRowCount(rowName, delta)
    rowName = tostring(rowName)
    
    -- Initialize if not exists
    if not AutoPlace.RowCounts[rowName] then
        AutoPlace.RowCounts[rowName] = 0
    end
    
    -- Update count
    AutoPlace.RowCounts[rowName] = math.max(0, AutoPlace.RowCounts[rowName] + delta)
    
    -- Update full row status
    if AutoPlace.RowCounts[rowName] >= AutoPlace.MaxPlantsPerRow then
        AutoPlace.FullRows[rowName] = true
    else
        AutoPlace.FullRows[rowName] = nil
    end
end

-- Get row count (from cache, O(1) instant!)
function AutoPlace.GetRowCount(rowName)
    return AutoPlace.RowCounts[tostring(rowName)] or 0
end

-- Check if row is full (from cache, O(1) instant!)
function AutoPlace.IsRowFull(rowName)
    return AutoPlace.FullRows[tostring(rowName)] == true
end

-- Initialize row counts from actual game state (only called on Start)
function AutoPlace.InitializeRowCounts()
    AutoPlace.RowCounts = {}
    AutoPlace.FullRows = {}
    
    local plotNum = AutoPlace.GetOwnedPlot()
    if not plotNum then return end
    
    local totalCount = 0
    
    -- Count plants from workspace.Plots[plotNum].Plants
    pcall(function()
        local plot = workspace.Plots:FindFirstChild(tostring(plotNum))
        if plot then
            local plants = plot:FindFirstChild("Plants")
            if plants then
                for _, plant in ipairs(plants:GetChildren()) do
                    local rowNum = plant:GetAttribute("Row")
                    if rowNum then
                        AutoPlace.UpdateRowCount(rowNum, 1)
                        totalCount = totalCount + 1
                    end
                end
            end
        end
    end)
    
    -- Count seeds from workspace.ScriptedMap.Countdowns
    pcall(function()
        local scriptedMap = workspace:FindFirstChild("ScriptedMap")
        if scriptedMap then
            local countdowns = scriptedMap:FindFirstChild("Countdowns")
            if countdowns then
                for _, seed in ipairs(countdowns:GetChildren()) do
                    local rowNum = seed:GetAttribute("Row")
                    if rowNum then
                        AutoPlace.UpdateRowCount(rowNum, 1)
                        totalCount = totalCount + 1
                    end
                end
            end
        end
    end)
    
end

-- Invalidate spots cache (call when CanPlace changes)
function AutoPlace.InvalidateCache()
    AutoPlace.SpotsCacheValid = false
    -- DON'T clear RowCounts - they're updated by events!
    -- DON'T clear UsedCFrames - items are still physically placed!
end

-- Find all available spots in player's plot (with caching)
function AutoPlace.FindAvailableSpots(forceRescan)
    -- Return cached spots if valid and not forcing rescan
    if AutoPlace.SpotsCacheValid and not forceRescan then
        return AutoPlace.CachedSpots
    end
    
    local spots = {}
    local plotNum = AutoPlace.GetOwnedPlot()
    
    if not plotNum then
        return spots
    end
    
    local success = pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then return end
        
        local rows = plot:FindFirstChild("Rows")
        if not rows then return end
        
        -- Loop through all rows (sorted by name)
        local rowsList = rows:GetChildren()
        table.sort(rowsList, function(a, b)
            return tonumber(a.Name) < tonumber(b.Name)
        end)
        
        for _, row in ipairs(rowsList) do
            -- SUPER OPTIMIZED: Skip full rows instantly with cached status!
            if not AutoPlace.IsRowFull(row.Name) then
                local grass = row:FindFirstChild("Grass")
                if grass then
                    for _, spot in ipairs(grass:GetChildren()) do
                        local canPlace = spot:GetAttribute("CanPlace")
                        if canPlace == true then
                            table.insert(spots, {
                                Floor = spot,
                                CFrame = spot.CFrame,
                                PivotOffset = spot.PivotOffset,
                                RowName = row.Name,
                                SpotName = spot.Name
                            })
                        end
                    end
                end
            end
        end
    end)
    
    -- Cache the results
    AutoPlace.CachedSpots = spots
    AutoPlace.SpotsCacheValid = true
    
    return spots
end

-- Move plant tool from backpack to character in workspace
function AutoPlace.MovePlantToCharacter(plantTool)
    local success = pcall(function()
        local character = AutoPlace.References.LocalPlayer.Character
        local backpack = AutoPlace.References.Backpack
        
        if not character or not plantTool:IsA("Tool") then
            return
        end
        
        -- Unequip any currently equipped tools
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") then
                tool.Parent = backpack
            end
        end
        
        -- Equip the plant tool
        plantTool.Parent = character
    end)
    
    return success
end

-- Place plant at specific spot (centered)
function AutoPlace.PlacePlant(plantInfo, spot)
    local success = pcall(function()
        local position = spot.Floor.CFrame.Position
        local x, y, z = position.X, position.Y, position.Z
        
        -- Get rotation from PivotOffset
        local pivot = spot.PivotOffset
        local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = pivot:GetComponents()
        
        if not pivot or pivot == CFrame.new() then
            r00, r01, r02 = 1, 0, 0
            r10, r11, r12 = 0, 1, 0
            r20, r21, r22 = 0, 0, 1
        end
        
        local placementCFrame = CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
        
        AutoPlace.References.PlaceItemRemote:FireServer({
            ["ID"] = plantInfo.ID,
            ["CFrame"] = placementCFrame,
            ["Item"] = plantInfo.Name,
            ["Floor"] = spot.Floor
        })
    end)
    
    if success then
        AutoPlace.TotalPlacements = AutoPlace.TotalPlacements + 1
        
        -- OPTIMIZED: Update cached row count immediately
        AutoPlace.UpdateRowCount(spot.RowName, 1)
    end
    
    return success
end

-- Process single plant tool from backpack
function AutoPlace.ProcessPlant(plantTool)
    -- Wait if already processing (one by one)
    while AutoPlace.IsProcessing do
        task.wait(0.1)
    end
    
    AutoPlace.IsProcessing = true
    
    if not AutoPlace.IsRunning or not AutoPlace.Settings.AutoPlaceEnabled then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Validate plant name (80% similarity)
    local isValid = AutoPlace.IsValidPlantName(plantTool.Name)
    if not isValid then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Get plant info
    local plantInfo = AutoPlace.GetPlantInfo(plantTool)
    if not plantInfo then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Check filter
    if not AutoPlace.ShouldPlacePlant(plantInfo) then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Find available spots (uses cache)
    local spots = AutoPlace.FindAvailableSpots()
    if #spots == 0 then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- OPTIMIZED: Pick first available spot using cached counts (O(1) instead of O(n)!)
    local selectedSpot = nil
    
    for _, spot in ipairs(spots) do
        -- Check if this CFrame position is already used
        local cframeKey = tostring(spot.Floor.CFrame.Position)
        
        if not AutoPlace.UsedCFrames[cframeKey] then
            -- SUPER FAST: O(1) cached count lookup instead of O(n) scan!
            if not AutoPlace.IsRowFull(spot.RowName) then
                local itemCount = AutoPlace.GetRowCount(spot.RowName)
                selectedSpot = spot
                -- Mark this CFrame as used
                AutoPlace.UsedCFrames[cframeKey] = true
                break
            end
        end
    end
    
    if not selectedSpot then
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Equip plant
    if not AutoPlace.MovePlantToCharacter(plantTool) then
        AutoPlace.IsProcessing = false
        return false
    end
    
    task.wait(0.1)  -- Reduced: Just enough for server sync
    
    -- Place plant
    local placed = AutoPlace.PlacePlant(plantInfo, selectedSpot)
    
    if placed then
        -- Invalidate cache IMMEDIATELY so next placement rescans all rows
        AutoPlace.InvalidateCache()
        
        -- Small wait for server to process
        task.wait(0.15)
    end
    
    AutoPlace.IsProcessing = false
    return placed
end

-- Process all plants in backpack
function AutoPlace.ProcessAllPlants()
    if not AutoPlace.IsRunning or not AutoPlace.Settings.AutoPlaceEnabled then
        return 0
    end
    
    local placed = 0
    
    for _, item in ipairs(AutoPlace.References.Backpack:GetChildren()) do
        if item:IsA("Tool") then
            local success = AutoPlace.ProcessPlant(item)
            if success then
                placed = placed + 1
                task.wait(0.2) -- Small delay between placements
            end
        end
    end
    
    return placed
end

--[[
    ========================================
    Event System (Event-Driven)
    ========================================
--]]

-- Update cache incrementally when a spot becomes available/unavailable
function AutoPlace.UpdateSpotInCache(spot, isAvailable, rowName)
    if isAvailable then
        table.insert(AutoPlace.CachedSpots, {
            Floor = spot,
            CFrame = spot.CFrame,
            PivotOffset = spot.PivotOffset,
            RowName = rowName,
            SpotName = spot.Name
        })
    else
        for i, cachedSpot in ipairs(AutoPlace.CachedSpots) do
            if cachedSpot.Floor == spot then
                table.remove(AutoPlace.CachedSpots, i)
                break
            end
        end
    end
end

-- Setup Row-Level Model tracking (efficient monitoring)
function AutoPlace.SetupPlotMonitoring()
    -- Disconnect old plot attribute connections
    for _, conn in ipairs(AutoPlace.PlotAttributeConnections) do
        conn:Disconnect()
    end
    AutoPlace.PlotAttributeConnections = {}
    
    local plotNum = AutoPlace.GetOwnedPlot()
    if not plotNum then
        return
    end
    
    pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then return end
        
        local rows = plot:FindFirstChild("Rows")
        if not rows then return end
        
        for _, row in ipairs(rows:GetChildren()) do
            local grass = row:FindFirstChild("Grass")
            if grass then
                -- Monitor each Floor spot for real-time CFrame tracking
                for _, spot in ipairs(grass:GetChildren()) do
                    if spot:IsA("Model") and spot.Name == "Floor" then
                        -- Track when items added to THIS spot
                        local addedConn = spot.ChildAdded:Connect(function(child)
                            if child:IsA("Model") then
                                -- Mark this CFrame as used IMMEDIATELY
                                local cframeKey = tostring(spot.CFrame.Position)
                                AutoPlace.UsedCFrames[cframeKey] = true
                                
                                -- OPTIMIZED: Update cached row count (+1)
                                AutoPlace.UpdateRowCount(row.Name, 1)
                            end
                        end)
                        
                        -- Track when items removed from THIS spot
                        local removedConn = spot.ChildRemoved:Connect(function(child)
                            if child:IsA("Model") then
                                -- Check if spot is now completely empty
                                local isEmpty = true
                                for _, remaining in ipairs(spot:GetChildren()) do
                                    if remaining:IsA("Model") then
                                        isEmpty = false
                                        break
                                    end
                                end
                                
                                -- If empty, unmark this CFrame (spot available again!)
                                if isEmpty then
                                    local cframeKey = tostring(spot.CFrame.Position)
                                    AutoPlace.UsedCFrames[cframeKey] = nil
                                end
                                
                                -- OPTIMIZED: Update cached row count (-1)
                                AutoPlace.UpdateRowCount(row.Name, -1)
                            end
                        end)
                        
                        table.insert(AutoPlace.PlotAttributeConnections, addedConn)
                        table.insert(AutoPlace.PlotAttributeConnections, removedConn)
                    end
                end
            end
        end
    end)
end

function AutoPlace.SetupEventListeners()
    -- Disconnect old connections
    if AutoPlace.BackpackConnection then
        AutoPlace.BackpackConnection:Disconnect()
        AutoPlace.BackpackConnection = nil
    end
    
    for _, conn in ipairs(AutoPlace.ChildAddedConnections) do
        conn:Disconnect()
    end
    AutoPlace.ChildAddedConnections = {}
    
    -- Listen for new items added to backpack
    AutoPlace.BackpackConnection = AutoPlace.References.Backpack.ChildAdded:Connect(function(item)
        if not item:IsA("Tool") or not AutoPlace.Settings.AutoPlaceEnabled or not AutoPlace.IsRunning then
            return
        end
        
        if not AutoPlace.IsValidPlantName(item.Name) then
            return
        end
        
        task.spawn(function()
            task.wait(0.05)  -- Minimal delay for item to load
            AutoPlace.ProcessPlant(item)
        end)
    end)
end

--[[
    ========================================
    Main Control
    ========================================
--]]

-- Scan plot and rebuild UsedCFrames from actually placed items
function AutoPlace.RebuildUsedCFrames()
    AutoPlace.UsedCFrames = {}
    
    local plotNum = AutoPlace.GetOwnedPlot()
    if not plotNum then return end
    
    local plot = workspace.Plots:FindFirstChild(plotNum)
    if not plot or not plot:FindFirstChild("Rows") then return end
    
    -- Scan all rows and grass spots
    for _, row in ipairs(plot.Rows:GetChildren()) do
        local grass = row:FindFirstChild("Grass")
        if grass then
            for _, spot in ipairs(grass:GetChildren()) do
                if spot:IsA("Model") and spot.Name == "Floor" then
                    -- Check if this spot has any items placed
                    local hasItem = false
                    for _, child in ipairs(spot:GetChildren()) do
                        if child:IsA("Model") then
                            hasItem = true
                            break
                        end
                    end
                    
                    -- If spot has item, mark its CFrame as used
                    if hasItem then
                        local cframeKey = tostring(spot.CFrame.Position)
                        AutoPlace.UsedCFrames[cframeKey] = true
                    end
                end
            end
        end
    end
end

function AutoPlace.Start()
    if AutoPlace.IsRunning then
        return
    end
    
    -- Increment generation FIRST (invalidates all old tasks instantly, zero-cost!)
    AutoPlace.StartGeneration = AutoPlace.StartGeneration + 1
    local myGeneration = AutoPlace.StartGeneration
    
    AutoPlace.IsRunning = true
    
    -- OPTIMIZED: Build plants set for fast lookups
    AutoPlace.RebuildPlantsSet()
    
    -- OPTIMIZED: Initialize row counts from actual game state
    AutoPlace.InitializeRowCounts()
    
    -- SMART: Rebuild UsedCFrames from what's already placed
    AutoPlace.RebuildUsedCFrames()
    
    -- Setup plot monitoring FIRST (real-time CFrame tracking & row count updates)
    AutoPlace.SetupPlotMonitoring()
    
    -- Setup event system IMMEDIATELY (catch new plants)
    AutoPlace.SetupEventListeners()
    
    -- Initial scan and process existing plants (with generation check)
    task.spawn(function()
        -- OPTIMIZED: Single number check (faster than task.cancel())
        if AutoPlace.StartGeneration ~= myGeneration then return end
        
        AutoPlace.FindAvailableSpots(true)
        
        if AutoPlace.StartGeneration ~= myGeneration then return end
        task.wait(0.05)
        
        if AutoPlace.StartGeneration ~= myGeneration then return end
        AutoPlace.ProcessAllPlants()
        
        -- Monitor workspace.Plots[X].Plants (when plants removed, spots open!)
        -- Monitor workspace.ScriptedMap.Countdowns (when seeds removed, spots open!)
        local plotNum = AutoPlace.GetOwnedPlot()
        if plotNum then
            local plot = workspace.Plots:FindFirstChild(tostring(plotNum))
            if plot then
                local plants = plot:FindFirstChild("Plants")
                local scriptedMap = workspace:FindFirstChild("ScriptedMap")
                local countdowns = scriptedMap and scriptedMap:FindFirstChild("Countdowns")
                
                -- OPTIMIZED: Debounced event handler (prevents spam processing)
                local function TryProcessPlants(reason)
                    if AutoPlace.StartGeneration ~= myGeneration then return end
                    
                    -- Debounce: Only process if enough time has passed
                    task.defer(function()
                        local now = tick()
                        if now - AutoPlace.LastEventTime < AutoPlace.EventDebounceInterval then
                            return -- Skip duplicate triggers
                        end
                        AutoPlace.LastEventTime = now
                        
                        task.wait(0.05) -- Minimal delay for replication
                        if AutoPlace.StartGeneration ~= myGeneration then return end
                        
                        AutoPlace.InvalidateCache()
                        AutoPlace.ProcessAllPlants()
                    end)
                end
                
                -- When a PLANT is removed, a spot opens up!
                if plants then
                    local plantRemovedConn = plants.ChildRemoved:Connect(function(removed)
                        local rowNum = removed:GetAttribute("Row")
                        if rowNum then
                            -- Row count already updated by SetupPlotMonitoring!
                            TryProcessPlants("plant_removed")
                        end
                    end)
                    table.insert(AutoPlace.PlotAttributeConnections, plantRemovedConn)
                end
                
                -- When a SEED countdown ends, a spot opens up!
                if countdowns then
                    local seedRemovedConn = countdowns.ChildRemoved:Connect(function(removed)
                        local rowNum = removed:GetAttribute("Row")
                        if rowNum then
                            -- Update row count manually (seeds aren't in Floor spots)
                            AutoPlace.UpdateRowCount(rowNum, -1)
                            TryProcessPlants("seed_expired")
                        end
                    end)
                    table.insert(AutoPlace.PlotAttributeConnections, seedRemovedConn)
                end
                
            end
        end
    end)
end

function AutoPlace.Stop()
    if not AutoPlace.IsRunning then
        return
    end
    
    AutoPlace.IsRunning = false
    
    -- Increment generation (all old tasks become invalid instantly, no cancellation needed!)
    AutoPlace.StartGeneration = AutoPlace.StartGeneration + 1
    
    if AutoPlace.BackpackConnection then
        AutoPlace.BackpackConnection:Disconnect()
        AutoPlace.BackpackConnection = nil
    end
    
    for _, conn in ipairs(AutoPlace.ChildAddedConnections) do
        conn:Disconnect()
    end
    AutoPlace.ChildAddedConnections = {}
    
    for _, conn in ipairs(AutoPlace.PlotAttributeConnections) do
        conn:Disconnect()
    end
    AutoPlace.PlotAttributeConnections = {}
    
    AutoPlace.CachedSpots = {}
    AutoPlace.SpotsCacheValid = false
    AutoPlace.RowCounts = {}
    AutoPlace.FullRows = {}
    AutoPlace.AvailablePlants = {}
    -- DON'T clear UsedCFrames - only clear when actually removing items from plot
end

function AutoPlace.GetStatus()
    return {
        IsRunning = AutoPlace.IsRunning,
        AutoPlaceEnabled = AutoPlace.Settings.AutoPlaceEnabled,
        TotalPlacements = AutoPlace.TotalPlacements,
        TotalPickUps = AutoPlace.TotalPickUps,
        SelectedPlants = AutoPlace.Settings.SelectedPlants or {},
        DamageFilter = AutoPlace.Settings.PlantDamageFilter or 0
    }
end

--[[
    ========================================
    Auto Pick Up System (Event-Driven)
    ========================================
--]]

-- Check if plant should be picked up based on damage filter
function AutoPlace.ShouldPickUpPlant(plantModel)
    if not AutoPlace.Settings.AutoPickUpEnabled then
        return false
    end
    
    local pickupFilter = AutoPlace.Settings.PickUpDamageFilter or 0
    local damage = plantModel:GetAttribute("Damage") or 0
    
    -- If filter is 0, pick up ALL plants
    if pickupFilter == 0 then
        return true
    end
    
    -- Otherwise, pick up plants with damage <= filter
    return damage <= pickupFilter
end

-- Pick up a single plant
function AutoPlace.PickUpPlant(plantModel)
    local id = plantModel:GetAttribute("ID")
    if not id then return false end
    
    local damage = plantModel:GetAttribute("Damage") or 0
    
    local success = pcall(function()
        AutoPlace.References.RemoveItemRemote:FireServer(id)
    end)
    
    if success then
        AutoPlace.TotalPickUps = AutoPlace.TotalPickUps + 1
    end
    
    return success
end

-- Setup event-driven monitoring for planted items
function AutoPlace.SetupPickUpMonitoring()
    -- Disconnect old connections
    for _, conn in ipairs(AutoPlace.PlantMonitorConnections) do
        conn:Disconnect()
    end
    AutoPlace.PlantMonitorConnections = {}
    
    if not AutoPlace.Settings.AutoPickUpEnabled then
        return
    end
    
    local plotNum = AutoPlace.GetOwnedPlot()
    if not plotNum then return end
    
    pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then return end
        
        local plants = plot:FindFirstChild("Plants")
        if not plants then return end
        
        -- Monitor existing plants
        for _, plantModel in ipairs(plants:GetChildren()) do
            if plantModel:IsA("Model") then
                -- Check immediately
                if AutoPlace.ShouldPickUpPlant(plantModel) then
                    task.spawn(function()
                        task.wait(0.1)  -- Small delay to ensure attributes loaded
                        AutoPlace.PickUpPlant(plantModel)
                    end)
                else
                    -- Monitor for Damage attribute changes
                    local conn = plantModel:GetAttributeChangedSignal("Damage"):Connect(function()
                        if AutoPlace.ShouldPickUpPlant(plantModel) then
                            AutoPlace.PickUpPlant(plantModel)
                        end
                    end)
                    table.insert(AutoPlace.PlantMonitorConnections, conn)
                end
            end
        end
        
        -- Monitor NEW plants being added
        local addedConn = plants.ChildAdded:Connect(function(plantModel)
            if not plantModel:IsA("Model") then return end
            
            task.wait(0.1)  -- Wait for attributes to load
            
            -- Check if should pick up immediately
            if AutoPlace.ShouldPickUpPlant(plantModel) then
                AutoPlace.PickUpPlant(plantModel)
            else
                -- Monitor for future damage changes
                local damageConn = plantModel:GetAttributeChangedSignal("Damage"):Connect(function()
                    if AutoPlace.ShouldPickUpPlant(plantModel) then
                        AutoPlace.PickUpPlant(plantModel)
                    end
                end)
                table.insert(AutoPlace.PlantMonitorConnections, damageConn)
            end
        end)
        
        table.insert(AutoPlace.PlantMonitorConnections, addedConn)
    end)
end

-- Start Auto Pick Up
function AutoPlace.StartPickUp()
    AutoPlace.SetupPickUpMonitoring()
end

-- Stop Auto Pick Up
function AutoPlace.StopPickUp()
    for _, conn in ipairs(AutoPlace.PlantMonitorConnections) do
        conn:Disconnect()
    end
    AutoPlace.PlantMonitorConnections = {}
end

return AutoPlace

