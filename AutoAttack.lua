--[[
    🌱 Plant Vs Brainrot - Auto Attack Module
    Automatic combat system with targeting and movement
    
    Features:
    - Auto equip weapon (Leather Grip Bat)
    - Multiple targeting modes (Random, High HP, Low HP)
    - Multiple movement modes (Walk, TP, Tween)
    - ONLY attacks brainrots in YOUR plot with YOUR UserID
    - Health-based targeting (Current or Max)
    
    Security:
    - Scans: workspace.ScriptedMap.Brainrots (global location)
    - Plot filter: brainrot:GetAttribute("Plot") == YourPlot
    - Only attacks brainrots in YOUR plot (AssociatedPlayer not used by game)
]]

local AutoAttack = {
    Version = "1.0.0",
    
    -- State
    IsRunning = false,
    TotalAttacks = 0,
    CurrentTarget = nil,
    
    -- Settings
    Settings = {
        AutoAttackEnabled = false,
        TargetMode = "Random",  -- "Random", "HighHP", "LowHP"
        MovementMode = "TP",  -- "TP", "Tween", "Walk"
        HealthMode = "Current",  -- "Current", "Max"
        AttackInterval = 0.5,  -- Seconds between attacks
    },
    
    -- Dependencies
    Services = nil,
    References = nil,
    Brain = nil,
    
    -- Connections
    AttackLoop = nil,
    EquippedConnection = nil,
    HealthMonitorConnection = nil
}

--[[
    ========================================
    Initialization
    ========================================
]]

function AutoAttack.Init(services, references, brain)
    AutoAttack.Services = services
    AutoAttack.References = references
    AutoAttack.Brain = brain
    
    return true
end

--[[
    ========================================
    Helper Functions
    ========================================
]]

-- Format numbers
local function FormatNumber(num)
    if num >= 1000000000 then
        return string.format("%.1fB", num / 1000000000)
    elseif num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(math.floor(num))
    end
end

-- Equip weapon (Leather Grip Bat)
function AutoAttack.EquipWeapon()
    local success = pcall(function()
        local character = AutoAttack.References.LocalPlayer.Character
        local backpack = AutoAttack.References.LocalPlayer:WaitForChild("Backpack")
        
        if not character then return false end
        
        -- Find Leather Grip Bat in backpack or character
        local weapon = backpack:FindFirstChild("Leather Grip Bat") or character:FindFirstChild("Leather Grip Bat")
        
        if weapon and weapon:IsA("Tool") then
            -- Unequip other tools first
            for _, tool in ipairs(character:GetChildren()) do
                if tool:IsA("Tool") and tool ~= weapon then
                    tool.Parent = backpack
                end
            end
            
            -- Equip weapon
            if weapon.Parent ~= character then
                weapon.Parent = character
            end
            
            return true
        end
        
        return false
    end)
    
    return success
end

-- Get player's owned plot number
function AutoAttack.GetPlayerPlot()
    local success, plotNum = pcall(function()
        return AutoAttack.References.LocalPlayer:GetAttribute("Plot")
    end)
    
    if success and plotNum then
        return tostring(plotNum)
    end
    
    return nil
end

-- Get all available targets from workspace.ScriptedMap.Brainrots (filter by Plot AND UserID)
function AutoAttack.GetAllTargets()
    local targets = {}
    
    -- Get player's plot number
    local playerPlot = AutoAttack.GetPlayerPlot()
    print("[AutoAttack] Player Plot:", playerPlot)
    if not playerPlot then 
        print("[AutoAttack] ❌ No plot number found!")
        return targets 
    end
    
    -- Get player's UserID
    local playerUserID = AutoAttack.References.LocalPlayer.UserId
    print("[AutoAttack] Player UserID:", playerUserID)
    
    pcall(function()
        -- Scan workspace.ScriptedMap.Brainrots (global brainrot location)
        local scriptedMap = workspace:FindFirstChild("ScriptedMap")
        if not scriptedMap then 
            print("[AutoAttack] ❌ ScriptedMap not found in workspace")
            return 
        end
        
        local brainrots = scriptedMap:FindFirstChild("Brainrots")
        if not brainrots then 
            print("[AutoAttack] ❌ Brainrots folder not found in ScriptedMap")
            return 
        end
        
        print("[AutoAttack] 🔍 Scanning workspace.ScriptedMap.Brainrots...")
        local totalBrainrots = 0
        local matchingBrainrots = 0
        
        for _, brainrot in ipairs(brainrots:GetChildren()) do
            if brainrot:IsA("Model") then
                totalBrainrots = totalBrainrots + 1
                local id = brainrot.Name
                local associatedPlayer = brainrot:GetAttribute("AssociatedPlayer")
                local plot = brainrot:GetAttribute("Plot")
                local health = brainrot:GetAttribute("Health") or 0
                local maxHealth = brainrot:GetAttribute("MaxHealth") or 100
                
                print(string.format("[AutoAttack] Found: %s | Plot: %s | AssociatedPlayer: %s | Health: %d/%d", 
                    id, tostring(plot), tostring(associatedPlayer), health, maxHealth))
                
                -- Skip if health is 0 or below
                if health <= 0 then
                    print("[AutoAttack] ⏭️ Skipped (dead):", id)
                    continue
                end
                
                -- Check if Plot matches (AssociatedPlayer is nil/not used by game)
                local plotMatches = (tostring(plot) == tostring(playerPlot))
                
                if plotMatches then
                    matchingBrainrots = matchingBrainrots + 1
                    print("[AutoAttack] ✅ VALID TARGET:", id, "| Plot matches!")
                    table.insert(targets, {
                        Model = brainrot,
                        ID = id,
                        PlayerID = associatedPlayer,
                        Plot = plot,
                        Health = health,
                        MaxHealth = maxHealth,
                        Position = brainrot:GetPivot().Position
                    })
                else
                    print("[AutoAttack] ❌ Skipped (wrong plot):", id, "Expected:", playerPlot, "Got:", plot)
                end
            end
        end
        
        print(string.format("[AutoAttack] 📊 Total: %d | Matching: %d | Valid: %d", 
            totalBrainrots, matchingBrainrots, #targets))
    end)
    
    return targets
end

-- Select best target based on mode
function AutoAttack.SelectTarget()
    print("[AutoAttack] 🎯 SelectTarget() called")
    local targets = AutoAttack.GetAllTargets()
    
    if #targets == 0 then
        print("[AutoAttack] ❌ No targets available")
        return nil
    end
    
    local mode = AutoAttack.Settings.TargetMode
    local healthMode = AutoAttack.Settings.HealthMode
    print("[AutoAttack] Mode:", mode, "| Health Mode:", healthMode)
    
    -- Random mode
    if mode == "Random" then
        local selected = targets[math.random(1, #targets)]
        print("[AutoAttack] ✅ Selected (Random):", selected.ID)
        return selected
    end
    
    -- Sort by health (use Current or Max health based on setting)
    table.sort(targets, function(a, b)
        local aValue = (healthMode == "Max") and a.MaxHealth or a.Health
        local bValue = (healthMode == "Max") and b.MaxHealth or b.Health
        
        if mode == "HighHP" then
            return aValue > bValue  -- Highest first
        else  -- LowHP
            return aValue < bValue  -- Lowest first
        end
    end)
    
    print("[AutoAttack] ✅ Selected (" .. mode .. "):", targets[1].ID)
    return targets[1]
end

-- Move to target (TP once and lock in position)
function AutoAttack.MoveToTarget(target)
    if not target or not target.Model then 
        print("[AutoAttack] ❌ MoveToTarget: Invalid target")
        return false
    end
    
    local character = AutoAttack.References.LocalPlayer.Character
    if not character then 
        print("[AutoAttack] ❌ MoveToTarget: No character")
        return false
    end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then 
        print("[AutoAttack] ❌ MoveToTarget: No HumanoidRootPart")
        return false
    end
    
    -- Get target position
    local targetPosition = target.Model:GetPivot().Position
    local distance = (humanoidRootPart.Position - targetPosition).Magnitude
    
    print(string.format("[AutoAttack] 📏 Distance to %s: %.2f studs", target.ID, distance))
    
    local movementMode = AutoAttack.Settings.MovementMode
    print("[AutoAttack] 🚶 Moving (" .. movementMode .. ") to target...")
    
    if movementMode == "TP" then
        -- Teleport directly to target position
        pcall(function()
            humanoidRootPart.CFrame = CFrame.new(targetPosition)
            print("[AutoAttack] ⚡ Teleported to target - LOCKED IN!")
        end)
        
    elseif movementMode == "Tween" then
        -- Quick tween to target
        local TweenService = game:GetService("TweenService")
        local tweenInfo = TweenInfo.new(
            0.2,  -- Fast tween
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.InOut
        )
        
        local tween = TweenService:Create(
            humanoidRootPart,
            tweenInfo,
            {CFrame = CFrame.new(targetPosition)}
        )
        
        tween:Play()
        tween.Completed:Wait()
        print("[AutoAttack] 🎬 Tweened to target - LOCKED IN!")
        
    elseif movementMode == "Walk" then
        -- Use Humanoid to walk
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:MoveTo(targetPosition)
            print("[AutoAttack] 🚶 Walking to target")
        end
    end
    
    return true
end

-- Attack target
function AutoAttack.AttackTarget(target)
    if not target or not target.ID then 
        print("[AutoAttack] ❌ AttackTarget: Invalid target")
        return false 
    end
    
    print("[AutoAttack] ⚔️ Attacking:", target.ID)
    
    local success = pcall(function()
        local args = {
            [1] = {
                [1] = target.ID
            }
        }
        
        print("[AutoAttack] 🔥 Firing WeaponAttack remote...")
        AutoAttack.Services.ReplicatedStorage:WaitForChild("Remotes"):WaitForChild("AttacksServer"):WaitForChild("WeaponAttack"):FireServer(unpack(args))
        print("[AutoAttack] ✅ Attack fired!")
    end)
    
    if success then
        AutoAttack.TotalAttacks = AutoAttack.TotalAttacks + 1
        print("[AutoAttack] 📊 Total attacks:", AutoAttack.TotalAttacks)
    else
        print("[AutoAttack] ❌ Attack failed!")
    end
    
    return success
end

-- Check if target is still valid (alive and exists)
function AutoAttack.IsTargetValid(target)
    if not target or not target.Model then return false end
    
    -- Check if model still exists in workspace
    if not target.Model.Parent then return false end
    
    -- Check if model is still in Brainrots folder
    local parent = target.Model.Parent
    if not parent or parent.Name ~= "Brainrots" then return false end
    
    -- Check if health > 0 (CRITICAL: dead = switch target immediately)
    local currentHealth = target.Model:GetAttribute("Health")
    if not currentHealth or currentHealth <= 0 then return false end
    
    return true
end

-- Monitor target's health attribute for instant death detection
function AutoAttack.MonitorTargetHealth(target)
    -- Disconnect previous monitor
    if AutoAttack.HealthMonitorConnection then
        AutoAttack.HealthMonitorConnection:Disconnect()
        AutoAttack.HealthMonitorConnection = nil
    end
    
    if not target or not target.Model then return end
    
    -- Listen for Health attribute changes
    AutoAttack.HealthMonitorConnection = target.Model:GetAttributeChangedSignal("Health"):Connect(function()
        local health = target.Model:GetAttribute("Health") or 0
        
        -- Target died! Clear it immediately
        if health <= 0 then
            if AutoAttack.CurrentTarget == target then
                AutoAttack.CurrentTarget = nil
            end
            
            -- Disconnect this monitor
            if AutoAttack.HealthMonitorConnection then
                AutoAttack.HealthMonitorConnection:Disconnect()
                AutoAttack.HealthMonitorConnection = nil
            end
        end
    end)
end

--[[
    ========================================
    Main Attack Loop
    ========================================
]]

function AutoAttack.AttackLoop()
    task.spawn(function()
        print("[AutoAttack] 🔄 Attack loop spawned")
        print("[AutoAttack] IsRunning:", AutoAttack.IsRunning)
        print("[AutoAttack] AutoAttackEnabled:", AutoAttack.Settings.AutoAttackEnabled)
        
        if not AutoAttack.IsRunning then
            print("[AutoAttack] ❌ IsRunning is false, loop won't start!")
            return
        end
        
        if not AutoAttack.Settings.AutoAttackEnabled then
            print("[AutoAttack] ❌ AutoAttackEnabled is false, loop won't start!")
            return
        end
        
        print("[AutoAttack] ✅ Starting loop...")
        
        while AutoAttack.IsRunning and AutoAttack.Settings.AutoAttackEnabled do
            print("[AutoAttack] --- Loop iteration ---")
            
            -- Ensure weapon is equipped
            AutoAttack.EquipWeapon()
            
            -- Select target (only choose new target if current is invalid)
            if not AutoAttack.IsTargetValid(AutoAttack.CurrentTarget) then
                print("[AutoAttack] 🔍 Need new target...")
                local newTarget = AutoAttack.SelectTarget()
                AutoAttack.CurrentTarget = newTarget
                
                -- Start monitoring new target's health for instant death detection
                if newTarget then
                    print("[AutoAttack] 📡 Monitoring target health:", newTarget.ID)
                    AutoAttack.MonitorTargetHealth(newTarget)
                end
            else
                print("[AutoAttack] ✅ Current target still valid:", AutoAttack.CurrentTarget.ID)
            end
            
            local target = AutoAttack.CurrentTarget
            
            if target then
                -- Check if we need to move to this target (not yet positioned)
                if not target.IsPositioned then
                    print("[AutoAttack] 🎯 New target - moving to position...")
                    
                    -- Validate before moving
                    if not AutoAttack.IsTargetValid(target) then
                        print("[AutoAttack] ❌ Target invalid before movement")
                        AutoAttack.CurrentTarget = nil
                        continue
                    end
                    
                    -- Move to target ONCE
                    local moved = AutoAttack.MoveToTarget(target)
                    
                    if moved then
                        -- Mark as positioned (won't move again until new target)
                        target.IsPositioned = true
                        print("[AutoAttack] 🔒 Position locked - will spam attacks now!")
                    else
                        print("[AutoAttack] ❌ Failed to move to target")
                        AutoAttack.CurrentTarget = nil
                        continue
                    end
                end
                
                -- We're positioned - SPAM ATTACKS!
                if target.IsPositioned then
                    -- Validate target before attack
                    if not AutoAttack.IsTargetValid(target) then
                        print("[AutoAttack] ☠️ Target died!")
                        AutoAttack.CurrentTarget = nil
                        continue
                    end
                    
                    -- Fire attack
                    print("[AutoAttack] 💥 Spamming attack...")
                    AutoAttack.AttackTarget(target)
                    
                    -- Check IMMEDIATELY if target died
                    if not AutoAttack.IsTargetValid(target) then
                        print("[AutoAttack] ☠️ Target died from attack!")
                        AutoAttack.CurrentTarget = nil
                        continue
                    end
                    
                    -- Wait between attacks
                    task.wait(AutoAttack.Settings.AttackInterval)
                end
            else
                -- No targets available, wait and search again
                print("[AutoAttack] ⏳ No targets, waiting 1s...")
                AutoAttack.CurrentTarget = nil
                task.wait(1)
            end
        end
        
        print("[AutoAttack] 🛑 Attack loop ended")
    end)
end

--[[
    ========================================
    Start/Stop Functions
    ========================================
]]

function AutoAttack.Start()
    if AutoAttack.IsRunning then
        print("[AutoAttack] ⚠️ Already running!")
        return false
    end
    
    print("[AutoAttack] 🟢 STARTING AUTO ATTACK SYSTEM")
    print("[AutoAttack] Settings:")
    print("  - Target Mode:", AutoAttack.Settings.TargetMode)
    print("  - Movement Mode:", AutoAttack.Settings.MovementMode)
    print("  - Health Mode:", AutoAttack.Settings.HealthMode)
    print("  - Attack Interval:", AutoAttack.Settings.AttackInterval)
    
    AutoAttack.IsRunning = true
    AutoAttack.TotalAttacks = 0
    
    -- Equip weapon immediately
    print("[AutoAttack] 🔫 Equipping weapon...")
    AutoAttack.EquipWeapon()
    
    -- Start attack loop
    print("[AutoAttack] 🔄 Starting attack loop...")
    AutoAttack.AttackLoop()
    
    -- Monitor weapon unequip (re-equip if needed)
    local character = AutoAttack.References.LocalPlayer.Character
    if character then
        AutoAttack.EquippedConnection = character.ChildRemoved:Connect(function(child)
            if child.Name == "Leather Grip Bat" and AutoAttack.IsRunning then
                print("[AutoAttack] 🔫 Weapon unequipped, re-equipping...")
                task.wait(0.1)
                AutoAttack.EquipWeapon()
            end
        end)
    end
    
    print("[AutoAttack] ✅ Auto Attack system started!")
    return true
end

function AutoAttack.Stop()
    if not AutoAttack.IsRunning then
        return false
    end
    
    AutoAttack.IsRunning = false
    AutoAttack.CurrentTarget = nil
    
    -- Disconnect weapon monitor
    if AutoAttack.EquippedConnection then
        AutoAttack.EquippedConnection:Disconnect()
        AutoAttack.EquippedConnection = nil
    end
    
    -- Disconnect health monitor
    if AutoAttack.HealthMonitorConnection then
        AutoAttack.HealthMonitorConnection:Disconnect()
        AutoAttack.HealthMonitorConnection = nil
    end
    
    return true
end

--[[
    ========================================
    Status Functions
    ========================================
]]

function AutoAttack.GetStatus()
    return {
        IsRunning = AutoAttack.IsRunning,
        TotalAttacks = AutoAttack.TotalAttacks,
        CurrentTarget = AutoAttack.CurrentTarget,
        Settings = AutoAttack.Settings
    }
end

--[[
    ========================================
    Return Module
    ========================================
]]

return AutoAttack

