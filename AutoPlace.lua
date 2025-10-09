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
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    TotalPlacements = 0,
    IsProcessing = false,  -- NEW: Prevent concurrent processing
    
    -- Cached Spots
    CachedSpots = {},
    SpotsCacheValid = false,
    
    -- Event Connections
    BackpackConnection = nil,
    ChildAddedConnections = {},
    PlotAttributeConnections = {},
    
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

function AutoPlace.Init(services, references, settings, brain)
    AutoPlace.Services = services
    AutoPlace.References = references
    AutoPlace.Settings = settings
    AutoPlace.Brain = brain
    
    print("✅ [AutoPlace] Module initialized successfully!")
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

-- Get all plant names from ReplicatedStorage
function AutoPlace.GetAllPlants()
    local plants = {}
    
    local success, result = pcall(function()
        for _, plant in ipairs(AutoPlace.References.Plants:GetChildren()) do
            local damage = plant:GetAttribute("Damage") or 0
            table.insert(plants, {
                Name = plant.Name,
                Damage = damage
            })
        end
    end)
    
    if success then
        -- Sort by damage (highest first)
        table.sort(plants, function(a, b)
            return a.Damage > b.Damage
        end)
        return plants
    end
    
    return {}
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
    
    -- Contains check
    if str1:find(str2, 1, true) or str2:find(str1, 1, true) then
        return 0.9
    end
    
    -- Levenshtein distance approximation
    local len1, len2 = #str1, #str2
    local maxLen = math.max(len1, len2)
    
    if maxLen == 0 then
        return 1.0
    end
    
    -- Count matching characters
    local matches = 0
    local minLen = math.min(len1, len2)
    
    for i = 1, minLen do
        if str1:sub(i, i) == str2:sub(i, i) then
            matches = matches + 1
        end
    end
    
    return matches / maxLen
end

-- Check if plant name matches any known plant (80% similarity)
function AutoPlace.IsValidPlantName(itemName)
    local extractedName = ExtractPlantName(itemName)
    
    -- Get all known plant names
    local knownPlants = AutoPlace.GetAllPlants()
    
    for _, plant in ipairs(knownPlants) do
        local similarity = StringSimilarity(extractedName, plant.Name)
        if similarity >= 0.8 then
            return true, plant.Name
        end
    end
    
    return false, nil
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
    
    local selectedPlants = AutoPlace.Settings.SelectedPlants or {}
    local damageFilter = AutoPlace.Settings.PlantDamageFilter or 0
    
    -- If specific plants selected, check if this plant is in the list
    local hasPlantFilter = #selectedPlants > 0
    local hasDamageFilter = damageFilter > 0
    
    if hasPlantFilter and hasDamageFilter then
        -- Both filters: Plant name must match AND damage >= filter
        local isSelected = table.find(selectedPlants, plantInfo.Name) ~= nil
        local meetsMinDamage = plantInfo.Damage >= damageFilter
        return isSelected and meetsMinDamage
    elseif hasPlantFilter then
        -- Only name filter: Plant must be in selected list
        return table.find(selectedPlants, plantInfo.Name) ~= nil
    elseif hasDamageFilter then
        -- Only damage filter: Plant damage >= filter
        return plantInfo.Damage >= damageFilter
    else
        -- No filter: Place all plants
        return true
    end
end

-- Invalidate spots cache (call when CanPlace changes)
function AutoPlace.InvalidateCache()
    AutoPlace.SpotsCacheValid = false
    print("[AutoPlace] Cache invalidated - will rescan on next placement")
end

-- Find all available spots in player's plot (with caching)
function AutoPlace.FindAvailableSpots(forceRescan)
    -- Return cached spots if valid and not forcing rescan
    if AutoPlace.SpotsCacheValid and not forceRescan then
        print("[AutoPlace] Using cached spots:", #AutoPlace.CachedSpots)
        return AutoPlace.CachedSpots
    end
    
    local spots = {}
    local plotNum = AutoPlace.GetOwnedPlot()
    
    if not plotNum then
        warn("[AutoPlace] Could not find owned plot number!")
        return spots
    end
    
    print("[AutoPlace] 🔄 Scanning plot #" .. plotNum .. " for available spots...")
    
    local success, result = pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then
            warn("[AutoPlace] Plot not found in workspace:", plotNum)
            return
        end
        
        local rows = plot:FindFirstChild("Rows")
        if not rows then
            warn("[AutoPlace] Rows folder not found in plot:", plotNum)
            return
        end
        
        print("[AutoPlace] Found Rows folder, scanning...")
        
        -- Loop through all rows (sorted by name)
        local rowsList = rows:GetChildren()
        table.sort(rowsList, function(a, b)
            return tonumber(a.Name) < tonumber(b.Name)
        end)
        
        for _, row in ipairs(rowsList) do
            print("[AutoPlace] Checking Row:", row.Name)
            
            local grass = row:FindFirstChild("Grass")
            if grass then
                print("[AutoPlace] Found Grass folder in Row " .. row.Name)
                
                -- Loop through all grass spots
                local grassSpots = grass:GetChildren()
                local availableInRow = 0
                
                for _, spot in ipairs(grassSpots) do
                    local canPlace = spot:GetAttribute("CanPlace")
                    if canPlace == true then
                        table.insert(spots, {
                            Floor = spot,
                            CFrame = spot.CFrame,
                            PivotOffset = spot.PivotOffset,
                            RowName = row.Name,
                            SpotName = spot.Name
                        })
                        availableInRow = availableInRow + 1
                    end
                end
                
                print("[AutoPlace] Row " .. row.Name .. ": " .. availableInRow .. " available spots")
            else
                print("[AutoPlace] No Grass folder in Row " .. row.Name)
            end
        end
    end)
    
    if not success then
        warn("[AutoPlace] Error scanning plots:", result)
    end
    
    -- Cache the results
    AutoPlace.CachedSpots = spots
    AutoPlace.SpotsCacheValid = true
    print("[AutoPlace] ✅ Cache updated with " .. #spots .. " spots")
    
    return spots
end

-- Move plant tool from backpack to character in workspace
function AutoPlace.MovePlantToCharacter(plantTool)
    local success, err = pcall(function()
        local character = AutoPlace.References.LocalPlayer.Character
        local backpack = AutoPlace.References.Backpack
        
        if not character then
            error("Character not found")
        end
        
        -- Verify it's a Tool
        if not plantTool:IsA("Tool") then
            error("Item is not a Tool")
        end
        
        -- First, unequip any tool currently equipped (like Shovel)
        for _, tool in ipairs(character:GetChildren()) do
            if tool:IsA("Tool") then
                print("[AutoPlace] Unequipping:", tool.Name)
                tool.Parent = backpack  -- Move back to backpack
            end
        end
        
        -- Now equip the plant Tool
        plantTool.Parent = character
        
        print("[AutoPlace] Equipped plant to character:", plantTool.Name)
    end)
    
    if not success then
        warn("[AutoPlace] Failed to equip plant to character:", err)
    end
    
    return success
end

-- Place plant at specific spot (centered)
function AutoPlace.PlacePlant(plantInfo, spot)
    local success, err = pcall(function()
        -- Get Floor's CFrame (center of the spot)
        local floorCFrame = spot.Floor.CFrame
        
        -- Extract center position from Floor
        local position = floorCFrame.Position
        local x, y, z = position.X, position.Y, position.Z
        
        -- Get rotation components from PivotOffset
        -- PivotOffset format: CFrame with rotation matrix
        local pivot = spot.PivotOffset
        local _, _, _, r00, r01, r02, r10, r11, r12, r20, r21, r22 = pivot:GetComponents()
        
        -- If pivot is identity or nil, default to identity rotation
        if not pivot or pivot == CFrame.new() then
            r00, r01, r02 = 1, 0, 0
            r10, r11, r12 = 0, 1, 0
            r20, r21, r22 = 0, 0, 1
        end
        
        -- Construct CFrame with center position from Floor and rotation from PivotOffset
        local placementCFrame = CFrame.new(x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22)
        
        print("[AutoPlace] Placing at center: (" .. math.floor(x) .. ", " .. math.floor(y) .. ", " .. math.floor(z) .. ")")
        
        local args = {
            [1] = {
                ["ID"] = plantInfo.ID,
                ["CFrame"] = placementCFrame,
                ["Item"] = plantInfo.Name,
                ["Floor"] = spot.Floor
            }
        }
        
        AutoPlace.References.PlaceItemRemote:FireServer(unpack(args))
    end)
    
    if success then
        AutoPlace.TotalPlacements = AutoPlace.TotalPlacements + 1
        print("[AutoPlace] ✅ Placed:", plantInfo.Name, "| DMG:", FormatNumber(plantInfo.Damage))
        return true
    else
        warn("[AutoPlace] ❌ Failed to place plant:", plantInfo.Name, err)
        return false
    end
end

-- Process single plant tool from backpack
function AutoPlace.ProcessPlant(plantTool)
    -- Wait if already processing another plant (ONE BY ONE)
    while AutoPlace.IsProcessing do
        task.wait(0.1)
    end
    
    AutoPlace.IsProcessing = true
    
    if not AutoPlace.IsRunning or not AutoPlace.Settings.AutoPlaceEnabled then
        print("[AutoPlace] Skipped - System not running or disabled")
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Quick validation: Check if item name matches any known plant (80% similarity)
    local isValid, matchedName = AutoPlace.IsValidPlantName(plantTool.Name)
    if not isValid then
        -- Skip silently - not a plant or doesn't match any known plants
        print("[AutoPlace] Skipped - Not a valid plant:", plantTool.Name)
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Get plant info
    local plantInfo = AutoPlace.GetPlantInfo(plantTool)
    if not plantInfo then
        warn("[AutoPlace] Could not read plant info:", plantTool.Name)
        AutoPlace.IsProcessing = false
        return false
    end
    
    print("[AutoPlace] Processing:", plantInfo.Name, "| ID:", plantInfo.ID, "| DMG:", plantInfo.Damage)
    
    -- Check if should place this plant
    if not AutoPlace.ShouldPlacePlant(plantInfo) then
        print("[AutoPlace] Skipped - Does not match filter:", plantInfo.Name)
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Find available spots (uses cache if valid)
    print("[AutoPlace] Finding available spots...")
    local spots = AutoPlace.FindAvailableSpots()
    print("[AutoPlace] Found", #spots, "available spots")
    
    if #spots == 0 then
        warn("[AutoPlace] ❌ No available spots! All plots full.")
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Pick first available spot (predictable, orderly placement)
    local selectedSpot = spots[1]
    print("[AutoPlace] Selected Row " .. selectedSpot.RowName .. ", Spot " .. selectedSpot.SpotName)
    
    -- Equip plant tool to character (move from backpack to character)
    print("[AutoPlace] Equipping plant tool to character...")
    local equipped = AutoPlace.MovePlantToCharacter(plantTool)
    if not equipped then
        warn("[AutoPlace] ❌ Could not equip plant to character:", plantInfo.Name)
        AutoPlace.IsProcessing = false
        return false
    end
    
    -- Wait a bit for equip to register
    task.wait(0.2)
    
    -- Place plant
    print("[AutoPlace] Placing plant...")
    local placed = AutoPlace.PlacePlant(plantInfo, selectedSpot)
    
    if placed then
        -- No need to invalidate cache - Row-Level monitoring will update it automatically!
        
        -- Wait a bit before allowing next plant
        task.wait(0.3)
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
        -- Add spot to cache
        local spotData = {
            Floor = spot,
            CFrame = spot.CFrame,
            PivotOffset = spot.PivotOffset,
            RowName = rowName,
            SpotName = spot.Name
        }
        table.insert(AutoPlace.CachedSpots, spotData)
        print("[AutoPlace] ➕ Added spot to cache: Row " .. rowName .. ", Spot " .. spot.Name .. " | Total: " .. #AutoPlace.CachedSpots)
    else
        -- Remove spot from cache
        for i, cachedSpot in ipairs(AutoPlace.CachedSpots) do
            if cachedSpot.Floor == spot then
                table.remove(AutoPlace.CachedSpots, i)
                print("[AutoPlace] ➖ Removed spot from cache: Row " .. rowName .. ", Spot " .. spot.Name .. " | Total: " .. #AutoPlace.CachedSpots)
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
    
    local success = pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then return end
        
        local rows = plot:FindFirstChild("Rows")
        if not rows then return end
        
        print("[AutoPlace] 🔍 Setting up Row-Level monitoring...")
        
        for _, row in ipairs(rows:GetChildren()) do
            local grass = row:FindFirstChild("Grass")
            if grass then
                -- Monitor ChildAdded in Grass (plant placed → spot occupied)
                local addedConn = grass.ChildAdded:Connect(function(child)
                    if child:IsA("Model") then
                        -- Find the corresponding spot (parent of where plant was placed)
                        local spot = child.Parent
                        if spot then
                            print("[AutoPlace] 🌱 Plant placed in Row " .. row.Name .. ", Spot " .. spot.Name)
                            AutoPlace.UpdateSpotInCache(spot, false, row.Name)
                        end
                    end
                end)
                
                -- Monitor ChildRemoved in Grass (plant removed → spot available)
                local removedConn = grass.ChildRemoved:Connect(function(child)
                    if child:IsA("Model") then
                        -- Plant removed, spot might be available again
                        local spot = child.Parent
                        if spot then
                            local canPlace = spot:GetAttribute("CanPlace")
                            if canPlace == true then
                                print("[AutoPlace] 🗑️ Plant removed from Row " .. row.Name .. ", Spot " .. spot.Name)
                                AutoPlace.UpdateSpotInCache(spot, true, row.Name)
                            end
                        end
                    end
                end)
                
                table.insert(AutoPlace.PlotAttributeConnections, addedConn)
                table.insert(AutoPlace.PlotAttributeConnections, removedConn)
            end
        end
        
        print("[AutoPlace] ✅ Monitoring " .. (#AutoPlace.PlotAttributeConnections / 2) .. " rows (ChildAdded/Removed)")
    end)
    
    if not success then
        warn("[AutoPlace] Failed to setup plot monitoring")
    end
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
        print("[AutoPlace] Item added to backpack:", item.Name, "| Type:", item.ClassName)
        
        if not item:IsA("Tool") then
            print("[AutoPlace] Skipped - Not a Tool")
            return
        end
        
        if not AutoPlace.Settings.AutoPlaceEnabled then
            print("[AutoPlace] Skipped - Auto-place disabled")
            return
        end
        
        if not AutoPlace.IsRunning then
            print("[AutoPlace] Skipped - System not running")
            return
        end
        
        -- Quick pre-check: Is this a valid plant name?
        local isValid, matchedName = AutoPlace.IsValidPlantName(item.Name)
        if not isValid then
            -- Skip - not a plant or doesn't match any known plants
            print("[AutoPlace] Skipped - Name doesn't match any plant:", item.Name)
            return
        end
        
        task.wait(0.1) -- Small delay to let item fully load
        
        print("[AutoPlace] ✅ New plant detected:", item.Name, "→", matchedName)
        
        task.spawn(function()
            AutoPlace.ProcessPlant(item)
        end)
    end)
    
    print("✅ [AutoPlace] Event listeners setup!")
end

--[[
    ========================================
    Main Control
    ========================================
--]]

function AutoPlace.Start()
    if AutoPlace.IsRunning then
        return
    end
    
    AutoPlace.IsRunning = true
    print("[AutoPlace] System starting...")
    
    -- Initial scan of available plots (force rescan to build cache)
    task.spawn(function()
        print("="..string.rep("=", 50))
        print("[AutoPlace] 🔍 INITIAL PLOT SCAN")
        print("="..string.rep("=", 50))
        
        local spots = AutoPlace.FindAvailableSpots(true)
        
        print("="..string.rep("=", 50))
        print("[AutoPlace] 📊 SCAN RESULTS:")
        print("[AutoPlace] Total available spots:", #spots)
        
        if #spots > 0 then
            print("[AutoPlace] ✅ Plots ready for placement!")
            print("[AutoPlace] Sample spots:")
            for i = 1, math.min(5, #spots) do
                local spot = spots[i]
                print("  - Row " .. spot.RowName .. ", Spot " .. spot.SpotName .. ": " .. spot.Floor:GetFullName())
            end
            if #spots > 5 then
                print("  ... and " .. (#spots - 5) .. " more spots")
            end
        else
            warn("[AutoPlace] ⚠️ No available spots found!")
            warn("[AutoPlace] Possible issues:")
            warn("  1. All plots are full")
            warn("  2. No CanPlace=true attributes found")
            warn("  3. Player doesn't own a plot")
        end
        print("="..string.rep("=", 50))
    end)
    
    -- Setup event-driven system
    AutoPlace.SetupEventListeners()
    
    -- Setup plot monitoring (CanPlace attribute changes)
    task.spawn(function()
        task.wait(1) -- Wait for initial scan to complete
        AutoPlace.SetupPlotMonitoring()
    end)
    
    -- Initial scan of existing plants in backpack
    task.spawn(function()
        task.wait(0.5)
        print("[AutoPlace] Scanning existing plants in backpack...")
        local placed = AutoPlace.ProcessAllPlants()
        if placed > 0 then
            print("[AutoPlace] Placed", placed, "existing plants")
        else
            print("[AutoPlace] No plants in backpack to place")
        end
    end)
    
    print("✅ [AutoPlace] System started!")
end

function AutoPlace.Stop()
    if not AutoPlace.IsRunning then
        return
    end
    
    AutoPlace.IsRunning = false
    
    -- Disconnect all events
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
    
    -- Clear cache
    AutoPlace.CachedSpots = {}
    AutoPlace.SpotsCacheValid = false
    
    print("[AutoPlace] System stopped!")
end

function AutoPlace.GetStatus()
    return {
        IsRunning = AutoPlace.IsRunning,
        AutoPlaceEnabled = AutoPlace.Settings.AutoPlaceEnabled,
        TotalPlacements = AutoPlace.TotalPlacements,
        SelectedPlants = AutoPlace.Settings.SelectedPlants or {},
        DamageFilter = AutoPlace.Settings.PlantDamageFilter or 0
    }
end

return AutoPlace

