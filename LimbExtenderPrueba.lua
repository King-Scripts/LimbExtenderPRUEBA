local Players = game:GetService("Players")
local localPlayer = Players.LocalPlayer

local DEFAULTS = {
    TOGGLE = "L",
    TARGET_LIMB = "HumanoidRootPart",
    LIMB_SIZE = 15,
    LIMB_TRANSPARENCY = 0.9,
    LIMB_CAN_COLLIDE = false,
    MOBILE_BUTTON = false,
    LISTEN_FOR_INPUT = true,
    TEAM_CHECK = true,
    FORCEFIELD_CHECK = true,
    RESET_LIMB_ON_DEATH2 = false,
    USE_HIGHLIGHT = true,
    DEPTH_MODE = "AlwaysOnTop",
    HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255,233,201),
    HIGHLIGHT_FILL_TRANSPARENCY = 0.7,
    HIGHLIGHT_OUTLINE_COLOR = Color3.fromRGB(138,169,255),
    HIGHLIGHT_OUTLINE_TRANSPARENCY = 0,
}

local limbExtenderData = getgenv().limbExtenderData or {}
getgenv().limbExtenderData = limbExtenderData

if limbExtenderData.terminateOldProcess and type(limbExtenderData.terminateOldProcess) == "function" then
    limbExtenderData.terminateOldProcess("FullKill")
    limbExtenderData.terminateOldProcess = nil
end

if not limbExtenderData.ConnectionManager then
    limbExtenderData.ConnectionManager = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/ConnectionManager.lua'))()
end

local ConnectionManager = limbExtenderData.ConnectionManager

local function mergeSettings(user)
    local s = {}
    for k,v in pairs(DEFAULTS) do s[k] = v end
    if user then
        for k,v in pairs(user) do s[k] = v end
    end
    return s
end

local function watchProperty(instance, prop, callback)
    if not instance or type(prop) ~= "string" or type(callback) ~= "function" then return nil end
    local signal = instance:GetPropertyChangedSignal(prop)
    if signal then
        return signal:Connect(function() callback(instance) end)
    end
    return nil
end

local function makeHighlight(settings)
    local hiFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Limb Extender Highlights Folder")
    if not hiFolder then
        hiFolder = Instance.new("Folder")
        hiFolder.Name = "Limb Extender Highlights Folder"
        hiFolder.Parent = game:GetService("ReplicatedStorage")
    end
    local hi = Instance.new("Highlight")
    hi.Name = "LimbHighlight"
    if settings.DEPTH_MODE then hi.DepthMode = Enum.HighlightDepthMode[settings.DEPTH_MODE] end
    if settings.HIGHLIGHT_FILL_COLOR then hi.FillColor = settings.HIGHLIGHT_FILL_COLOR end
    if settings.HIGHLIGHT_FILL_TRANSPARENCY then hi.FillTransparency = settings.HIGHLIGHT_FILL_TRANSPARENCY end
    if settings.HIGHLIGHT_OUTLINE_COLOR then hi.OutlineColor = settings.HIGHLIGHT_OUTLINE_COLOR end
    if settings.HIGHLIGHT_OUTLINE_TRANSPARENCY then hi.OutlineTransparency = settings.HIGHLIGHT_OUTLINE_TRANSPARENCY end
    hi.Enabled = true
    hi.Parent = hiFolder
    return hi
end

local PlayerData = {}
PlayerData.__index = PlayerData

function PlayerData.new(parent, player)
    local self = setmetatable({
        _parent = parent,
        player = player,
        conns = ConnectionManager.new(),
        highlight = nil,
        PartStreamable = nil,
        _charDelay = nil,
        _destroyed = false,
    }, PlayerData)

    if player.CharacterAdded then
        self.conns:Connect(player.CharacterAdded, function(c) self:onCharacter(c) end)
    end

    local character = player.Character or workspace:FindFirstChild(player.Name)
    self:onCharacter(character)
    return self
end

function PlayerData:saveLimbProperties(limb)
    local parent = self._parent
    if not limb then return end
    parent._limbStore[limb] = {
        OriginalSize = limb.Size,
        OriginalTransparency = limb.Transparency,
        OriginalCanCollide = limb.CanCollide,
        OriginalMassless = limb.Massless,
    }
end

function PlayerData:restoreLimbProperties(limb)
    local parent = self._parent
    if not limb then return end
    local p = parent._limbStore[limb]
    if not p then return end
    if limb and limb.Parent then
        limb.Size = p.OriginalSize
        limb.Transparency = p.OriginalTransparency
        limb.CanCollide = p.OriginalCanCollide
        limb.Massless = p.OriginalMassless
    end
    parent._limbStore[limb] = nil
    if limbExtenderData.limbs then limbExtenderData.limbs[limb] = nil end
end

function PlayerData:modifyLimbProperties(limb)
    local parent = self._parent
    if not limb or parent._limbStore[limb] then return end
    self:saveLimbProperties(limb)

    local entry = parent._limbStore[limb]
    local sizeVal = parent._settings.LIMB_SIZE or DEFAULTS.LIMB_SIZE
    local newSize = Vector3.new(sizeVal, sizeVal, sizeVal)
    local canCollide = parent._settings.LIMB_CAN_COLLIDE
    local transparency = parent._settings.LIMB_TRANSPARENCY

    entry.SizeConnection = watchProperty(limb, "Size", function(l) l.Size = newSize end)
    entry.TransparencyConnection = watchProperty(limb, "Transparency", function(l) l.Transparency = transparency end)
    entry.CollisionConnection = watchProperty(limb, "CanCollide", function(l) l.CanCollide = canCollide end)

    if limb and limb.Parent then
        limb.Size = newSize
        limb.Transparency = transparency
        limb.CanCollide = canCollide
        limb.Massless = true
        limb.AssemblyLinearVelocity = Vector3.new(0,0,0)
        limb.AssemblyAngularVelocity = Vector3.new(0,0,0)
    end

    if limbExtenderData.limbs then
        limbExtenderData.limbs[limb] = parent._limbStore[limb]
    end
end

function PlayerData:spoofSize(part)
    if not part then return end
    local saved = part.Size
    local name = part.Name
    if limbExtenderData._spoofTarget == name then return end
    limbExtenderData._spoofTarget = name

    pcall(function()
        local mt = getrawmetatable(game)
        setreadonly(mt, false)
        local old = mt.__index
        mt.__index = function(Self, Key)
            if tostring(Self) == name and Key == "Size" and not checkcaller() then
                return saved
            end
            return old(Self, Key)
        end
        setreadonly(mt, true)
    end)
end

local function forceNoTorsoCollision(character)
    if not character or not character.Parent then return end
    local upper = character:FindFirstChild("UpperTorso") or character:WaitForChild("UpperTorso", 5)
    local lower = character:FindFirstChild("LowerTorso") or character:WaitForChild("LowerTorso", 5)
    if not (upper and lower) then return end
    if upper:FindFirstChild("NoTorsoCollideTag") then return end

    local RunService = game:GetService("RunService")
    local conn1 = RunService.Stepped:Connect(function()
        pcall(function()
            if upper.Parent then upper.CanCollide = false end
            if lower.Parent then lower.CanCollide = false end
        end)
    end)
    local conn2 = RunService.Heartbeat:Connect(function()
        pcall(function()
            if upper.Parent then upper.CanCollide = false end
            if lower.Parent then lower.CanCollide = false end
        end)
    end)

    local tag = Instance.new("BoolValue")
    tag.Name = "NoTorsoCollideTag"
    tag.Parent = upper

    local function cleanup()
        if conn1 then conn1:Disconnect() end
        if conn2 then conn2:Disconnect() end
    end

    character.AncestryChanged:Connect(function()
        if not character:IsDescendantOf(game) then cleanup() end
    end)
    tag.Destroying:Connect(cleanup)
end

-- ====================== ANTI-FLOAT FUERTE ======================
local function handleVehicleExit(character)
    if not character or not character.Parent then return end
    
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    if not (humanoid and rootPart) then return end

    local bigSize = nil

    local sitConnection
    sitConnection = humanoid:GetPropertyChangedSignal("Sit"):Connect(function()
        if humanoid.Sit == false then  -- Bajó del vehículo
            if sitConnection then
                sitConnection:Disconnect()
                sitConnection = nil
            end

            bigSize = rootPart.Size

            -- FIX ULTRA
            rootPart.Size = Vector3.new(2, 2, 1)
            rootPart.CanCollide = false
            rootPart.Massless = true
            rootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
            rootPart.AssemblyAngularVelocity = Vector3.new(0,0,0)

            local wasAnchored = rootPart.Anchored
            rootPart.Anchored = true

            -- Empujón fuerte hacia arriba
            rootPart.CFrame = rootPart.CFrame + Vector3.new(0, 1, 0)

            -- Restauramos después de más tiempo
            task.delay(0.65, function()
                if rootPart and rootPart.Parent then
                    rootPart.Anchored = wasAnchored
                    rootPart.Size = bigSize or Vector3.new(15, 15, 15)
                    rootPart.CanCollide = DEFAULTS.LIMB_CAN_COLLIDE
                    rootPart.AssemblyLinearVelocity = Vector3.new(0,0,0)
                    rootPart.AssemblyAngularVelocity = Vector3.new(0,0,0)
                end
            end)
        end
    end)

    character.AncestryChanged:Once(function()
        if sitConnection then sitConnection:Disconnect() end
    end)
end

function PlayerData:setupCharacter(char)
    local parent = self._parent
    if not char or not parent or not self.player then return end

    if parent:_isTeam(self.player) then return end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return end

    if self.PartStreamable then self.PartStreamable:Destroy() self.PartStreamable = nil end

    if parent._Streamable and parent._Streamable.new then
        self.PartStreamable = parent._Streamable.new(char, parent._settings.TARGET_LIMB)
        if self.PartStreamable.Observe then
            self.PartStreamable:Observe(function(part, trove)
                if self._destroyed or not part then return end
                self:spoofSize(part)
                self:modifyLimbProperties(part)

                if parent._settings.USE_HIGHLIGHT then
                    if not self.highlight then self.highlight = makeHighlight(parent._settings) end
                    self.highlight.Adornee = part
                end

                if self.player.CharacterRemoving then
                    self.conns:Connect(self.player.CharacterRemoving, function()
                        self:restoreLimbProperties(part)
                    end)
                end

                local deathEvent = parent._settings.RESET_LIMB_ON_DEATH2 and humanoid.HealthChanged or humanoid.Died
                if deathEvent then
                    self.conns:Connect(deathEvent, function(hp)
                        if hp and hp <= 0 then self:restoreLimbProperties(part) end
                    end)
                end

                if trove and trove.Add then
                    trove:Add(function() self:restoreLimbProperties(part) end)
                end
            end)
        end
    end

    task.delay(0.8, function()
        if self._destroyed then return end
        if char and char.Parent then
            forceNoTorsoCollision(char)
            handleVehicleExit(char)   -- Anti-float
        end
    end)
end

function PlayerData:onCharacter(char)
    if not char then return end
    if self._charDelay then task.cancel(self._charDelay) end
    self._charDelay = task.delay(0.1, function()
        if self._destroyed then return end
        if self._parent._settings.FORCEFIELD_CHECK then
            local ff = char:FindFirstChildOfClass("ForceField")
            if ff then
                self.conns:Connect(ff.Destroying, function() self:setupCharacter(char) end)
                return
            end
        end
        self:setupCharacter(char)
    end)
end

function PlayerData:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    if self.conns then self.conns:DisconnectAll() end
    if self.highlight then self.highlight:Destroy() end
    if self.PartStreamable then self.PartStreamable:Destroy() end
    if self._charDelay then task.cancel(self._charDelay) end
    setmetatable(self, nil)
    for k in pairs(self) do self[k] = nil end
end

-- ====================== MAIN LIMB EXTENDER ======================
local LimbExtender = {}
LimbExtender.__index = LimbExtender

function LimbExtender.new(userSettings)
    local self = setmetatable({
        _settings = mergeSettings(userSettings),
        _playerTable = limbExtenderData.playerTable or {},
        _limbStore = limbExtenderData.limbs or {},
        _Streamable = limbExtenderData.Streamable,
        _CAU = limbExtenderData.CAU,
        _connections = ConnectionManager.new(),
        _running = limbExtenderData.running or false,
        _destroyed = false,
    }, LimbExtender)

    limbExtenderData.playerTable = self._playerTable
    limbExtenderData.limbs = self._limbStore
    limbExtenderData.Streamable = self._Streamable
    limbExtenderData.CAU = self._CAU
    limbExtenderData.running = self._running
    limbExtenderData.terminateOldProcess = function() self:Destroy() end

    self._Streamable = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/Streamable.lua'))()

    if self._settings.LISTEN_FOR_INPUT then
        self._CAU = loadstring(game:HttpGet('https://raw.githubusercontent.com/AAPVdev/modules/refs/heads/main/ContextActionUtility.lua'))()
    end

    return self
end

function LimbExtender:_isTeam(player)
    return self._settings.TEAM_CHECK and localPlayer and localPlayer.Team == player.Team
end

function LimbExtender:Start()
    if self._running then return end
    self._running = true
    limbExtenderData.running = true

    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= localPlayer and not self._playerTable[p.Name] then
            self._playerTable[p.Name] = PlayerData.new(self, p)
        end
    end

    self._connections:Connect(Players.PlayerAdded, function(p)
        if p ~= localPlayer and not self._playerTable[p.Name] then
            self._playerTable[p.Name] = PlayerData.new(self, p)
        end
    end)

    self._connections:Connect(Players.PlayerRemoving, function(p)
        local pd = self._playerTable[p.Name]
        if pd then pd:Destroy() end
        self._playerTable[p.Name] = nil
    end)
end

function LimbExtender:Stop()
    self._running = false
    limbExtenderData.running = false
    self._connections:DisconnectAll()

    for _, pd in pairs(self._playerTable) do
        if pd then pd:Destroy() end
    end
    self._playerTable = {}
end

function LimbExtender:Toggle()
    self._running = not self._running
    if self._running then self:Start() else self:Stop() end
end

function LimbExtender:Destroy()
    if self._destroyed then return end
    self._destroyed = true
    self:Stop()
    limbExtenderData.terminateOldProcess = nil
end

return setmetatable({}, { 
    __call = function(_, settings) 
        return LimbExtender.new(settings) 
    end 
})
