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
    - Plot filter: workspace.Plots[YourPlot].Brainrots
    - UserID filter: AssociatedPlayer == LocalPlayer.UserId
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

-- Get all available targets from workspace (only in player's plot AND matching player's UserID)
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
        -- Get brainrots in player's plot
        local plot = workspace.Plots:FindFirstChild(playerPlot)
        if not plot then 
            print("[AutoAttack] ❌ Plot folder not found:", playerPlot)
            return 
        end
        
        local brainrots = plot:FindFirstChild("Brainrots")
        if not brainrots then 
            print("[AutoAttack] ❌ Brainrots folder not found in plot")
            return 
        end
        
        print("[AutoAttack] 🔍 Scanning Brainrots folder...")
        local totalBrainrots = 0
        local matchingBrainrots = 0
        
        for _, brainrot in ipairs(brainrots:GetChildren()) do
            if brainrot:IsA("Model") then
                totalBrainrots = totalBrainrots + 1
                local id = brainrot.Name
                local associatedPlayer = brainrot:GetAttribute("AssociatedPlayer")
                local health = brainrot:GetAttribute("Health") or 0
                local maxHealth = brainrot:GetAttribute("MaxHealth") or 100
                
                print(string.format("[AutoAttack] Found: %s | AssociatedPlayer: %s | Health: %d/%d", 
                    id, tostring(associatedPlayer), health, maxHealth))
                
                -- Skip if health is 0 or below
                if health <= 0 then
                    print("[AutoAttack] ⏭️ Skipped (dead):", id)
                    continue
                end
                
                -- CRITICAL: Only target brainrots where AssociatedPlayer == My UserID
                -- This ensures we only attack OUR OWN brainrots in OUR plot
                if associatedPlayer == playerUserID then
                    matchingBrainrots = matchingBrainrots + 1
                    print("[AutoAttack] ✅ VALID TARGET:", id)
                    table.insert(targets, {
                        Model = brainrot,
                        ID = id,
                        PlayerID = associatedPlayer,
                        Health = health,
                        MaxHealth = maxHealth,
                        Position = brainrot:GetPivot().Position
                    })
                else
                    print("[AutoAttack] ❌ Skipped (wrong UserID):", id, "Expected:", playerUserID, "Got:", associatedPlayer)
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

-- Move to target based on movement mode (returns current distance)
function AutoAttack.MoveToTarget(target)
    if not target or not target.Model then 
        print("[AutoAttack] ❌ MoveToTarget: Invalid target")
        return math.huge 
    end
    
    local character = AutoAttack.References.LocalPlayer.Character
    if not character then 
        print("[AutoAttack] ❌ MoveToTarget: No character")
        return math.huge 
    end
    
    local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
    if not humanoidRootPart then 
        print("[AutoAttack] ❌ MoveToTarget: No HumanoidRootPart")
        return math.huge 
    end
    
    -- Get LIVE position from model
    local targetPosition = target.Model:GetPivot().Position
    local distance = (humanoidRootPart.Position - targetPosition).Magnitude
    
    print(string.format("[AutoAttack] 📏 Distance to %s: %.2f studs", target.ID, distance))
    
    -- Already very close (within 1 stud for attacking)
    if distance <= 1 then
        print("[AutoAttack] ✅ In attack range!")
        return distance
    end
    
    local movementMode = AutoAttack.Settings.MovementMode
    print("[AutoAttack] 🚶 Moving (" .. movementMode .. ") to target...")
    
    if movementMode == "TP" then
        -- Teleport close to target (1 stud away)
        pcall(function()
            local offset = (humanoidRootPart.Position - targetPosition).Unit * 1
            humanoidRootPart.CFrame = CFrame.new(targetPosition + offset)
            print("[AutoAttack] ⚡ Teleported to target")
        end)
        
    elseif movementMode == "Tween" then
        -- Quick tween to target
        local TweenService = game:GetService("TweenService")
        local tweenInfo = TweenInfo.new(
            0.3,  -- Fast tween (0.3 seconds)
            Enum.EasingStyle.Linear,
            Enum.EasingDirection.InOut
        )
        
        local offset = (humanoidRootPart.Position - targetPosition).Unit * 1
        local tween = TweenService:Create(
            humanoidRootPart,
            tweenInfo,
            {CFrame = CFrame.new(targetPosition + offset)}
        )
        
        tween:Play()
        print("[AutoAttack] 🎬 Tweening to target")
        
    elseif movementMode == "Walk" then
        -- Use Humanoid to walk
        local humanoid = character:FindFirstChild("Humanoid")
        if humanoid then
            humanoid:MoveTo(targetPosition)
            print("[AutoAttack] 🚶 Walking to target")
        end
    end
    
    -- Return current distance
    local newDistance = (humanoidRootPart.Position - targetPosition).Magnitude
    print(string.format("[AutoAttack] 📏 New distance: %.2f studs", newDistance))
    return newDistance
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
        print("[AutoAttack] 🔄 Attack loop started")
        
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
                -- Double-check target is still valid BEFORE moving
                if not AutoAttack.IsTargetValid(target) then
                    print("[AutoAttack] ❌ Target invalid before movement")
                    AutoAttack.CurrentTarget = nil
                    continue  -- Skip to next iteration to find new target
                end
                
                -- CONTINUOUSLY move to target (stick to it)
                local distance = AutoAttack.MoveToTarget(target)
                
                -- Check if target died/disappeared during movement
                if not AutoAttack.IsTargetValid(target) then
                    print("[AutoAttack] ❌ Target died during movement")
                    AutoAttack.CurrentTarget = nil
                    continue  -- Immediately find new target (no wait)
                end
                
                -- Attack if within 1 stud
                if distance <= 1 then
                    AutoAttack.AttackTarget(target)
                    
                    -- Check IMMEDIATELY after attack if target is still alive
                    if not AutoAttack.IsTargetValid(target) then
                        print("[AutoAttack] ☠️ Target died from attack!")
                        AutoAttack.CurrentTarget = nil
                        continue  -- Target died, find new one NOW
                    end
                    
                    -- Wait between attacks (fast spam if interval is low)
                    task.wait(AutoAttack.Settings.AttackInterval)
                else
                    print("[AutoAttack] ⏳ Not in range yet, waiting 0.1s...")
                    -- Not in range yet, keep moving (check more frequently)
                    task.wait(0.1)
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

