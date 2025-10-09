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
    
    -- Event Connections
    BackpackConnection = nil,
    ChildAddedConnections = {},
    
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

-- Check if item name matches plant format: [XX.X kg] Name
local function IsPlantFormat(itemName)
    -- Check if name starts with [XX.X kg] pattern
    return string.match(itemName, "^%[%d+%.?%d* kg%]") ~= nil
end

-- Get plant info from backpack item
function AutoPlace.GetPlantInfo(plantModel)
    local success, info = pcall(function()
        local name = plantModel.Name
        
        -- Check if it matches plant format
        if not IsPlantFormat(name) then
            return nil
        end
        
        return {
            Name = name,
            ID = plantModel:GetAttribute("ID"),
            Damage = plantModel:GetAttribute("Damage") or 0
        }
    end)
    
    if success and info and info.ID then
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

-- Find all available spots in player's plot
function AutoPlace.FindAvailableSpots()
    local spots = {}
    local plotNum = AutoPlace.GetOwnedPlot()
    
    if not plotNum then
        return spots
    end
    
    local success, result = pcall(function()
        local plot = workspace.Plots:FindFirstChild(plotNum)
        if not plot then
            return
        end
        
        local rows = plot:FindFirstChild("Rows")
        if not rows then
            return
        end
        
        -- Loop through all rows
        for _, row in ipairs(rows:GetChildren()) do
            local grass = row:FindFirstChild("Grass")
            if grass then
                -- Loop through all grass spots
                for _, spot in ipairs(grass:GetChildren()) do
                    local canPlace = spot:GetAttribute("CanPlace")
                    if canPlace == true then
                        table.insert(spots, {
                            Floor = spot,
                            CFrame = spot.CFrame
                        })
                    end
                end
            end
        end
    end)
    
    return spots
end

-- Equip plant from backpack
function AutoPlace.EquipPlant(plantInfo)
    local success, err = pcall(function()
        AutoPlace.References.EquipItemRemote:Fire(plantInfo.Name, plantInfo.ID)
    end)
    
    if not success then
        warn("[AutoPlace] Failed to equip plant:", plantInfo.Name, err)
    end
    
    return success
end

-- Place plant at specific spot
function AutoPlace.PlacePlant(plantInfo, spot)
    local success, err = pcall(function()
        local args = {
            [1] = {
                ["ID"] = plantInfo.ID,
                ["CFrame"] = spot.CFrame,
                ["Item"] = plantInfo.Name,
                ["Floor"] = spot.Floor
            }
        }
        
        AutoPlace.References.PlaceItemRemote:FireServer(unpack(args))
    end)
    
    if success then
        AutoPlace.TotalPlacements = AutoPlace.TotalPlacements + 1
        print("[AutoPlace] Placed:", plantInfo.Name, "| DMG:", FormatNumber(plantInfo.Damage))
        return true
    else
        warn("[AutoPlace] Failed to place plant:", plantInfo.Name, err)
        return false
    end
end

-- Process single plant from backpack
function AutoPlace.ProcessPlant(plantModel)
    if not AutoPlace.IsRunning or not AutoPlace.Settings.AutoPlaceEnabled then
        return false
    end
    
    -- Get plant info
    local plantInfo = AutoPlace.GetPlantInfo(plantModel)
    if not plantInfo then
        warn("[AutoPlace] Could not read plant info:", plantModel.Name)
        return false
    end
    
    -- Check if should place this plant
    if not AutoPlace.ShouldPlacePlant(plantInfo) then
        return false
    end
    
    -- Find available spots
    local spots = AutoPlace.FindAvailableSpots()
    if #spots == 0 then
        warn("[AutoPlace] No available spots! All plots full.")
        return false
    end
    
    -- Pick random spot
    local randomSpot = spots[math.random(1, #spots)]
    
    -- Equip plant
    local equipped = AutoPlace.EquipPlant(plantInfo)
    if not equipped then
        warn("[AutoPlace] Could not equip plant:", plantInfo.Name)
        return false
    end
    
    -- Wait a bit for equip to register
    task.wait(0.1)
    
    -- Place plant
    local placed = AutoPlace.PlacePlant(plantInfo, randomSpot)
    
    return placed
end

-- Process all plants in backpack
function AutoPlace.ProcessAllPlants()
    if not AutoPlace.IsRunning or not AutoPlace.Settings.AutoPlaceEnabled then
        return 0
    end
    
    local placed = 0
    
    for _, item in ipairs(AutoPlace.References.Backpack:GetChildren()) do
        -- Only process items that match plant format [XX.X kg] Name
        if item:IsA("Model") and IsPlantFormat(item.Name) then
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
        -- Only process items that match plant format [XX.X kg] Name
        if item:IsA("Model") and IsPlantFormat(item.Name) and AutoPlace.Settings.AutoPlaceEnabled and AutoPlace.IsRunning then
            task.wait(0.1) -- Small delay to let item fully load
            
            print("[AutoPlace] New plant detected in backpack:", item.Name)
            
            task.spawn(function()
                AutoPlace.ProcessPlant(item)
            end)
        end
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
    
    -- Setup event-driven system
    AutoPlace.SetupEventListeners()
    
    -- Initial scan of existing plants in backpack
    task.spawn(function()
        task.wait(0.5)
        print("[AutoPlace] Scanning existing plants in backpack...")
        local placed = AutoPlace.ProcessAllPlants()
        if placed > 0 then
            print("[AutoPlace] Placed", placed, "existing plants")
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

