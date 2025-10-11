--[[
    🎯 Plant Vs Brainrot - Auto Turn In Module
    Automatically turn in wanted brainrots for prison rewards
    
    Features:
    - Monitor wanted brainrot name
    - Check if player owns it
    - Auto turn in when conditions met
]]

local AutoTurnIn = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    TotalTurnIns = 0,
    CurrentWanted = nil,
    CurrentIndex = 1, -- Track which brainrot in the list we're on
    WantedList = {}, -- Cached list from EventTracks.Prison
    
    -- Settings
    Settings = {
        AutoTurnInEnabled = false,
        CheckInterval = 2, -- Check every 2 seconds
    },
    
    -- Dependencies
    Services = nil,
    References = nil,
    Brain = nil,
    
    -- Cached Data
    TurnInRemote = nil,
    EventTrackModule = nil,
    PlayerDataModule = nil,
    BrainrotRegistry = nil,
}

--[[
    ========================================
    Initialization
    ========================================
]]

function AutoTurnIn.Init(services, references, brain)
    AutoTurnIn.Services = services
    AutoTurnIn.References = references
    AutoTurnIn.Brain = brain
    
    -- Cache remote and wanted list
    pcall(function()
        AutoTurnIn.TurnInRemote = AutoTurnIn.Services.ReplicatedStorage
            :WaitForChild("Remotes", 5)
            :WaitForChild("Events", 5)
            :WaitForChild("Prison", 5)
            :WaitForChild("Interact", 5)
        
        -- Load wanted list from EventTracks.Prison
        local modules = AutoTurnIn.Services.ReplicatedStorage:FindFirstChild("Modules")
        if modules then
            local library = modules:FindFirstChild("Library")
            if library then
                local eventTracks = library:FindFirstChild("EventTracks")
                if eventTracks then
                    local prisonTrack = eventTracks:FindFirstChild("Prison")
                    if prisonTrack then
                        local wantedList = require(prisonTrack)
                        if wantedList and type(wantedList) == "table" then
                            AutoTurnIn.WantedList = wantedList
                            print("[AutoTurnIn] ✅ Loaded", #wantedList, "wanted brainrots")
                        end
                    end
                end
            end
        end
    end)
    
    -- Listen for turn in success to increment index
    if AutoTurnIn.TurnInRemote then
        AutoTurnIn.TurnInRemote.OnClientEvent:Connect(function(eventType, data)
            if eventType == "Success" and data and data.GoalStage then
                -- Update our progress
                AutoTurnIn.CurrentIndex = data.GoalStage + 1
                print("[AutoTurnIn] 🎉 Progress updated! Now on wanted #" .. AutoTurnIn.CurrentIndex)
            end
        end)
    end
    
    -- Sync current index based on imprisoned brainrots
    task.spawn(function()
        task.wait(1) -- Wait for workspace to load
        AutoTurnIn.SyncProgressFromPrison()
    end)
    
    return true
end

--[[
    ========================================
    Helper Functions
    ========================================
]]

-- Sync progress by checking imprisoned brainrots
function AutoTurnIn.SyncProgressFromPrison()
    local success, result = pcall(function()
        -- Find the prison in workspace
        local prison = workspace:FindFirstChild("ScriptedMap")
        if not prison then return end
        
        prison = prison:FindFirstChild("Prison")
        if not prison then return end
        
        local imprisonedFolder = prison:FindFirstChild("ImprisonedBrainrot")
        if not imprisonedFolder then return end
        
        -- Check if wanted list is loaded
        if not AutoTurnIn.WantedList or #AutoTurnIn.WantedList == 0 then
            warn("[AutoTurnIn] ⚠️ Cannot sync - wanted list not loaded")
            return
        end
        
        -- Get all imprisoned brainrot names
        local imprisoned = {}
        for _, child in ipairs(imprisonedFolder:GetChildren()) do
            if child:IsA("Model") then
                imprisoned[child.Name] = true
            end
        end
        
        -- Count how many from the list have been turned in
        local turnedInCount = 0
        for i, wantedName in ipairs(AutoTurnIn.WantedList) do
            if imprisoned[wantedName] then
                turnedInCount = i
            else
                -- First one not found means we're on this one
                break
            end
        end
        
        -- Update current index (next one to turn in)
        AutoTurnIn.CurrentIndex = turnedInCount + 1
        
        print(string.format("[AutoTurnIn] 🔄 Synced progress: %d/%d completed", 
            turnedInCount, #AutoTurnIn.WantedList))
        
        if turnedInCount > 0 then
            print("[AutoTurnIn] 📋 Last turned in:", AutoTurnIn.WantedList[turnedInCount])
        end
        
        if AutoTurnIn.CurrentIndex <= #AutoTurnIn.WantedList then
            print("[AutoTurnIn] 🎯 Next wanted:", AutoTurnIn.WantedList[AutoTurnIn.CurrentIndex])
        else
            print("[AutoTurnIn] ✅ All wanted brainrots completed!")
        end
    end)
    
    if not success then
        warn("[AutoTurnIn] ⚠️ Failed to sync progress:", result)
    end
end

-- Get current wanted brainrot name from the list
function AutoTurnIn.GetWantedBrainrot()
    -- Check if we have the wanted list
    if not AutoTurnIn.WantedList or #AutoTurnIn.WantedList == 0 then
        warn("[AutoTurnIn] ⚠️ Wanted list not loaded!")
        return nil
    end
    
    -- Make sure index is valid
    if AutoTurnIn.CurrentIndex < 1 or AutoTurnIn.CurrentIndex > #AutoTurnIn.WantedList then
        print("[AutoTurnIn] ✅ All wanted brainrots completed!")
        return nil
    end
    
    -- Return the current wanted brainrot
    return AutoTurnIn.WantedList[AutoTurnIn.CurrentIndex]
end

-- Find the wanted brainrot tool (returns the tool instance)
function AutoTurnIn.FindWantedBrainrot(wantedName)
    if not wantedName then return nil end
    
    local character = AutoTurnIn.References.LocalPlayer.Character
    local backpack = AutoTurnIn.References.LocalPlayer:FindFirstChild("Backpack")
    
    if not character and not backpack then return nil end
    
    -- Check character first
    if character then
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                -- Check exact match or if the tool name contains the wanted name
                -- (handles cases like "[19.2 kg] Orcalero Orcala" matching "Orcalero Orcala")
                if child.Name == wantedName or child.Name:find(wantedName, 1, true) then
                    return child
                end
            end
        end
    end
    
    -- Check backpack
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                -- Check exact match or if the tool name contains the wanted name
                if child.Name == wantedName or child.Name:find(wantedName, 1, true) then
                    return child
                end
            end
        end
    end
    
    return nil
end

-- Equip the brainrot to character (move from backpack to character)
function AutoTurnIn.EquipBrainrot(brainrotTool)
    if not brainrotTool then return false end
    
    local character = AutoTurnIn.References.LocalPlayer.Character
    if not character then return false end
    
    -- If already in character, we're good
    if brainrotTool.Parent == character then
        return true
    end
    
    -- Try to equip it
    local success = pcall(function()
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            humanoid:EquipTool(brainrotTool)
        end
    end)
    
    -- Wait a moment for it to equip
    task.wait(0.2)
    
    -- Verify it's equipped
    return brainrotTool.Parent == character
end

-- Turn in the wanted brainrot
function AutoTurnIn.TurnIn()
    if not AutoTurnIn.TurnInRemote then
        return false
    end
    
    local success = pcall(function()
        AutoTurnIn.TurnInRemote:FireServer("TurnIn")
        AutoTurnIn.TotalTurnIns = AutoTurnIn.TotalTurnIns + 1
    end)
    
    return success
end

--[[
    ========================================
    Main Check Loop
    ========================================
]]

function AutoTurnIn.CheckLoop()
    task.spawn(function()
        print("[AutoTurnIn] ✅ Check loop started!")
        
        while AutoTurnIn.IsRunning and AutoTurnIn.Settings.AutoTurnInEnabled do
            -- Get current wanted brainrot
            local wantedName = AutoTurnIn.GetWantedBrainrot()
            AutoTurnIn.CurrentWanted = wantedName
            
            if wantedName then
                local totalWanted = #AutoTurnIn.WantedList
                print(string.format("[AutoTurnIn] 🎯 Wanted [%d/%d]: %s", 
                    AutoTurnIn.CurrentIndex, totalWanted, wantedName))
                
                -- Find the brainrot tool
                local brainrotTool = AutoTurnIn.FindWantedBrainrot(wantedName)
                
                if brainrotTool then
                    local location = brainrotTool.Parent.Name
                    print("[AutoTurnIn] ✅ Found wanted brainrot in:", location)
                    
                    -- Equip it to character if needed
                    if brainrotTool.Parent ~= AutoTurnIn.References.LocalPlayer.Character then
                        print("[AutoTurnIn] 📦 Equipping from backpack to character...")
                        local equipped = AutoTurnIn.EquipBrainrot(brainrotTool)
                        
                        if not equipped then
                            warn("[AutoTurnIn] ⚠️ Failed to equip brainrot!")
                            task.wait(2)
                            -- Skip to next iteration to retry
                            task.wait(AutoTurnIn.Settings.CheckInterval)
                            continue
                        end
                        
                        print("[AutoTurnIn] ✅ Equipped to character!")
                    end
                    
                    -- Now turn it in
                    print("[AutoTurnIn] 📤 Turning in...")
                    local success = AutoTurnIn.TurnIn()
                    
                    if success then
                        print("[AutoTurnIn] 🎉 Turned in successfully! Total:", AutoTurnIn.TotalTurnIns)
                        
                        -- Increment index for next one
                        AutoTurnIn.CurrentIndex = AutoTurnIn.CurrentIndex + 1
                    else
                        warn("[AutoTurnIn] ⚠️ Failed to turn in!")
                    end
                    
                    -- Wait a bit longer after turning in
                    task.wait(3)
                else
                    print("[AutoTurnIn] ❌ Don't own", wantedName)
                end
            else
                if #AutoTurnIn.WantedList == 0 then
                    warn("[AutoTurnIn] ⚠️ Wanted list not loaded! Retrying...")
                    
                    -- Try to reload the list
                    pcall(function()
                        local modules = AutoTurnIn.Services.ReplicatedStorage:FindFirstChild("Modules")
                        if modules then
                            local library = modules:FindFirstChild("Library")
                            if library then
                                local eventTracks = library:FindFirstChild("EventTracks")
                                if eventTracks then
                                    local prisonTrack = eventTracks:FindFirstChild("Prison")
                                    if prisonTrack then
                                        local wantedList = require(prisonTrack)
                                        if wantedList and type(wantedList) == "table" then
                                            AutoTurnIn.WantedList = wantedList
                                            print("[AutoTurnIn] ✅ Reloaded", #wantedList, "wanted brainrots")
                                        end
                                    end
                                end
                            end
                        end
                    end)
                else
                    print("[AutoTurnIn] ✅ All wanted brainrots completed!")
                end
            end
            
            -- Wait before next check
            task.wait(AutoTurnIn.Settings.CheckInterval)
        end
        
        print("[AutoTurnIn] ⏹️ Check loop stopped")
    end)
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
]]

function AutoTurnIn.Start()
    if AutoTurnIn.IsRunning then return false end
    
    -- Validate remote
    if not AutoTurnIn.TurnInRemote then
        -- Try to cache it again
        pcall(function()
            AutoTurnIn.TurnInRemote = AutoTurnIn.Services.ReplicatedStorage
                :WaitForChild("Remotes", 5)
                :WaitForChild("Events", 5)
                :WaitForChild("Prison", 5)
                :WaitForChild("Interact", 5)
        end)
        
        if not AutoTurnIn.TurnInRemote then
            warn("[AutoTurnIn] ⚠️ Failed to find turn in remote!")
            warn("[AutoTurnIn] ⚠️ Make sure you're in the Prison area!")
            return false
        end
    end
    
    -- Sync progress before starting
    AutoTurnIn.SyncProgressFromPrison()
    
    AutoTurnIn.IsRunning = true
    AutoTurnIn.TotalTurnIns = 0
    AutoTurnIn.CheckLoop()
    
    return true
end

function AutoTurnIn.Stop()
    if not AutoTurnIn.IsRunning then return false end
    
    AutoTurnIn.IsRunning = false
    AutoTurnIn.CurrentWanted = nil
    return true
end

--[[
    ========================================
    Status Functions
    ========================================
]]

function AutoTurnIn.GetStatus()
    local progress = "0/0"
    if #AutoTurnIn.WantedList > 0 then
        progress = AutoTurnIn.CurrentIndex .. "/" .. #AutoTurnIn.WantedList
    end
    
    return {
        IsRunning = AutoTurnIn.IsRunning,
        TotalTurnIns = AutoTurnIn.TotalTurnIns,
        CurrentWanted = AutoTurnIn.CurrentWanted or "None",
        Progress = progress,
        CurrentIndex = AutoTurnIn.CurrentIndex
    }
end

return AutoTurnIn

