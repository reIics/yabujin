if getgenv().UnlockAllLoaded then return end
getgenv().UnlockAllLoaded = true

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local player = Players.LocalPlayer
local playerScripts = player.PlayerScripts
local controllers = playerScripts.Controllers
local EnumLibrary = require(ReplicatedStorage.Modules:WaitForChild("EnumLibrary", 10))
if EnumLibrary then EnumLibrary:WaitForEnumBuilder() end
pcall(function()
    for _, v in getgc() do
        if typeof(v) == "thread" and string.find(debug.info(v, 1, "s") or "", "AnalyticsPipelineController") then
            task.cancel(v)
        end
    end
end)
pcall(function()
    local remote = ReplicatedStorage:FindFirstChild("Remotes")
    remote = remote and remote:FindFirstChild("AnalyticsPipeline")
    remote = remote and remote:FindFirstChild("RemoteEvent")
    if remote then
        for _, conn in getconnections(remote.OnClientEvent) do
            conn:Disable()
        end
    end
end)

local CosmeticLibrary = require(ReplicatedStorage.Modules:WaitForChild("CosmeticLibrary", 10))
local ItemLibrary = require(ReplicatedStorage.Modules:WaitForChild("ItemLibrary", 10))
local ShopLibrary = require(ReplicatedStorage.Modules:WaitForChild("ShopLibrary", 10))
local PlayerDataUtility = require(ReplicatedStorage.Modules:WaitForChild("PlayerDataUtility", 10))
local DataController = require(controllers:WaitForChild("PlayerDataController", 10))
repeat task.wait() until CosmeticLibrary.Cosmetics
local equipped, favorites = {}, {}
local constructingWeapon, viewingProfile = nil, nil
local lastUsedWeapon = nil
local isReplicating = false
local lastSaveTime = 0
local cachedInventoryProxy = nil
local function cloneCosmetic(name, cosmeticType, options)
    local base = CosmeticLibrary.Cosmetics[name]
    if not base then return nil end
    local data = {}
    for key, value in pairs(base) do data[key] = value end
    data.Name = name
    data.Type = data.Type or cosmeticType
    data.Seed = data.Seed or math.random(1, 1000000)
    if EnumLibrary then
        local success, enumId = pcall(EnumLibrary.ToEnum, EnumLibrary, name)
        if success and enumId then data.Enum, data.ObjectID = enumId, data.ObjectID or enumId end
    end
    if options then
        if options.inverted ~= nil then data.Inverted = options.inverted end
        if options.favoritesOnly ~= nil then data.OnlyUseFavorites = options.favoritesOnly end
    end
    return data
end
local saveFile = "unlockall/config.json"
local function saveConfig()
    if not writefile or tick() - lastSaveTime < 1 then return end
    lastSaveTime = tick()
    pcall(function()
        local config = {equipped = {}, favorites = favorites}
        for weapon, cosmetics in pairs(equipped) do
            config.equipped[weapon] = {}
            for cosmeticType, cosmeticData in pairs(cosmetics) do
                if cosmeticData and cosmeticData.Name then
                    config.equipped[weapon][cosmeticType] = {
                        name = cosmeticData.Name, seed = cosmeticData.Seed, inverted = cosmeticData.Inverted
                    }
                end
            end
        end
        makefolder("unlockall")
        writefile(saveFile, HttpService:JSONEncode(config))
    end)
end
local function loadConfig()
    if not readfile or not isfile or not isfile(saveFile) then return end
    pcall(function()
        local config = HttpService:JSONDecode(readfile(saveFile))
        if config.equipped then
            for weapon, cosmetics in pairs(config.equipped) do
                equipped[weapon] = {}
                for cosmeticType, cosmeticData in pairs(cosmetics) do
                    local cloned = cloneCosmetic(cosmeticData.name, cosmeticType, {inverted = cosmeticData.inverted})
                    if cloned then cloned.Seed = cosmeticData.seed equipped[weapon][cosmeticType] = cloned end
                end
            end
        end
        favorites = config.favorites or {}
    end)
end
local originalOwnsCosmetic = hookfunction(CosmeticLibrary.OwnsCosmetic, function(self, inventory, name, weapon)
    if name and name:find("MISSING_") then return false end
    return true
end)
hookfunction(CosmeticLibrary.OwnsCosmeticNormally, function() return true end)
hookfunction(CosmeticLibrary.OwnsCosmeticUniversally, function() return true end)
hookfunction(CosmeticLibrary.OwnsCosmeticForWeapon, function() return true end)

local origGet = DataController.Get
local cachedWeaponInventory = nil
local cachedOwnableSet = nil
DataController.Get = function(self, key, ...)
    local result = origGet(self, key, ...)
    if key == "CosmeticInventory" then
        if not cachedInventoryProxy then
            cachedInventoryProxy = setmetatable({}, {__index = function() return true end})
        end
        return cachedInventoryProxy
    end
    if key == "WeaponInventory" then
        if cachedWeaponInventory then return cachedWeaponInventory end
        local fake = {}
        if result then for k, v in pairs(result) do fake[k] = v end end
        if not cachedOwnableSet then
            cachedOwnableSet = {}
            if ShopLibrary.OwnableWeapons then
                for _, name in pairs(ShopLibrary.OwnableWeapons) do cachedOwnableSet[name] = true end
            end
        end
        for name, data in pairs(ItemLibrary.Items) do
            if data.Class and cachedOwnableSet[name] and not fake[name] then
                fake[name] = {
                    Name = name,
                    Owned = true,
                    Class = data.Class,
                    Unlocked = true,
                    Level = 1,
                    XP = 0,
                    IsFavorited = false
                }
            end
        end
        cachedWeaponInventory = fake
        return fake
    end
    if key == "FavoritedCosmetics" then
        local res = result and table.clone(result) or {}
        for weapon, favs in pairs(favorites) do
            res[weapon] = res[weapon] or {}
            for n, isFav in pairs(favs) do res[weapon][n] = isFav end
        end
        return res
    end
    return result
end

local origUnlocked = DataController.GetUnlockedWeapons
local cachedUnlockedWeapons = nil
DataController.GetUnlockedWeapons = function(self, ...)
    if cachedUnlockedWeapons then return cachedUnlockedWeapons end
    local result = origUnlocked(self, ...)
    local all = {}
    if result then for k, v in pairs(result) do all[k] = v end end
    if ShopLibrary.OwnableWeapons then
        for _, name in pairs(ShopLibrary.OwnableWeapons) do
            all[name] = true
        end
    end
    cachedUnlockedWeapons = all
    return all
end

local origWeaponData = DataController.GetWeaponData
local weaponDataCache = {}
DataController.GetWeaponData = function(self, weaponName, ...)
    local result = origWeaponData(self, weaponName, ...)
    if result then
        if equipped[weaponName] then
            for cosmeticType, cosmeticData in pairs(equipped[weaponName]) do
                result[cosmeticType] = cosmeticData
            end
        end
        return result
    end
    if weaponDataCache[weaponName] then
        local cached = weaponDataCache[weaponName]
        if equipped[weaponName] then
            for cosmeticType, cosmeticData in pairs(equipped[weaponName]) do
                cached[cosmeticType] = cosmeticData
            end
        end
        return cached
    end
    local data = ItemLibrary.Items[weaponName]
    if not cachedOwnableSet then
        cachedOwnableSet = {}
        if ShopLibrary.OwnableWeapons then
            for _, name in pairs(ShopLibrary.OwnableWeapons) do cachedOwnableSet[name] = true end
        end
    end
    if data and data.Class and cachedOwnableSet[weaponName] then
        local fake = {
            Name = weaponName,
            Class = data.Class,
            Owned = true,
            Unlocked = true,
            Level = 1,
            XP = 0,
            IsFavorited = false
        }
        if equipped[weaponName] then
            for cosmeticType, cosmeticData in pairs(equipped[weaponName]) do
                fake[cosmeticType] = cosmeticData
            end
        end
        weaponDataCache[weaponName] = fake
        return fake
    end
    return result
end

local origShop = ShopLibrary.GetReleasedOwnableWeapons
local cachedReleasedWeapons = nil
ShopLibrary.GetReleasedOwnableWeapons = function(self, ...)
    if cachedReleasedWeapons then return cachedReleasedWeapons end
    local result = origShop(self, ...)
    cachedReleasedWeapons = result
    return result
end
local FighterController
pcall(function() FighterController = require(controllers:WaitForChild("FighterController", 10)) end)
local weaponIdCache = {}
if hookmetamethod then
    local remotes = ReplicatedStorage:FindFirstChild("Remotes")
    local dataRemotes = remotes and remotes:FindFirstChild("Data")
    local equipRemote = dataRemotes and dataRemotes:FindFirstChild("EquipCosmetic")
    local favoriteRemote = dataRemotes and dataRemotes:FindFirstChild("FavoriteCosmetic")
    local replicationRemotes = remotes and remotes:FindFirstChild("Replication")
    local fighterRemotes = replicationRemotes and replicationRemotes:FindFirstChild("Fighter")
    local useItemRemote = fighterRemotes and fighterRemotes:FindFirstChild("UseItem")
    if equipRemote then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
            if getnamecallmethod() ~= "FireServer" then return oldNamecall(self, ...) end
            local args = {...}
            if useItemRemote and self == useItemRemote then
                local objectID = args[1]
                if weaponIdCache[objectID] then
                    lastUsedWeapon = weaponIdCache[objectID]
                elseif FighterController then
                    local fighter = FighterController:GetFighter(player)
                    if fighter and fighter.Items then
                        for _, item in pairs(fighter.Items) do
                            local id = item:Get("ObjectID")
                            weaponIdCache[id] = item.Name
                        end
                        lastUsedWeapon = weaponIdCache[objectID] or lastUsedWeapon
                    end
                end
            end            
            if self == equipRemote then
                local weaponName, cosmeticType, cosmeticName, options = args[1], args[2], args[3], args[4] or {}                
                if cosmeticName and cosmeticName ~= "None" and cosmeticName ~= "" then
                    local inventory = origGet(DataController, "CosmeticInventory")
                    if inventory and rawget(inventory, cosmeticName) then return oldNamecall(self, ...) end
                end                
                equipped[weaponName] = equipped[weaponName] or {}                
                if not cosmeticName or cosmeticName == "None" or cosmeticName == "" then
                    equipped[weaponName][cosmeticType] = nil
                    if not next(equipped[weaponName]) then equipped[weaponName] = nil end
                else
                    local cloned = cloneCosmetic(cosmeticName, cosmeticType, {inverted = options.IsInverted, favoritesOnly = options.OnlyUseFavorites})
                    if cloned then equipped[weaponName][cosmeticType] = cloned end
                end                
                task.defer(function()
                    if isReplicating then return end
                    isReplicating = true
                    pcall(function() DataController.CurrentData:Replicate("WeaponInventory") end)
                    task.wait(0.5)
                    isReplicating = false
                    saveConfig()
                end)
                return
            end            
            if self == favoriteRemote then
                favorites[args[1]] = favorites[args[1]] or {}
                favorites[args[1]][args[2]] = args[3] or nil
                saveConfig()
                pcall(function() DataController.CurrentData:Replicate("FavoritedCosmetics") end)
                return
            end            
            return oldNamecall(self, ...)
        end))
    end
end
local ClientItem
pcall(function() ClientItem = require(player.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem) end)
if ClientItem and ClientItem._CreateViewModel then
    local originalCreateViewModel = ClientItem._CreateViewModel
    ClientItem._CreateViewModel = function(self, viewmodelRef)
        local weaponName = self.Name
        local weaponPlayer = self.ClientFighter and self.ClientFighter.Player
        constructingWeapon = (weaponPlayer == player) and weaponName or nil    
        if weaponPlayer == player and equipped[weaponName] and equipped[weaponName].Skin and viewmodelRef then
            local dataKey, skinKey, nameKey = self:ToEnum("Data"), self:ToEnum("Skin"), self:ToEnum("Name")
            if viewmodelRef[dataKey] then
                viewmodelRef[dataKey][skinKey] = equipped[weaponName].Skin
                viewmodelRef[dataKey][nameKey] = equipped[weaponName].Skin.Name
            elseif viewmodelRef.Data then
                viewmodelRef.Data.Skin = equipped[weaponName].Skin
                viewmodelRef.Data.Name = equipped[weaponName].Skin.Name
            end
        end
        local result = originalCreateViewModel(self, viewmodelRef)
        constructingWeapon = nil
        return result
    end
end
local viewModelModule = player.PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem:FindFirstChild("ClientViewModel")
if viewModelModule then
    local ClientViewModel = require(viewModelModule)
    if ClientViewModel.GetWrap then
        local originalGetWrap = ClientViewModel.GetWrap
        ClientViewModel.GetWrap = function(self)
            local weaponName = self.ClientItem and self.ClientItem.Name
            local weaponPlayer = self.ClientItem and self.ClientItem.ClientFighter and self.ClientItem.ClientFighter.Player
            if weaponName and weaponPlayer == player and equipped[weaponName] and equipped[weaponName].Wrap then
                return equipped[weaponName].Wrap
            end
            return originalGetWrap(self)
        end
    end
    local originalNew = ClientViewModel.new
    ClientViewModel.new = function(replicatedData, clientItem)
        local weaponPlayer = clientItem.ClientFighter and clientItem.ClientFighter.Player
        local weaponName = constructingWeapon or clientItem.Name
        if weaponPlayer == player and equipped[weaponName] then
            local ReplicatedClass = require(ReplicatedStorage.Modules.ReplicatedClass)
            local dataKey = ReplicatedClass:ToEnum("Data")
            replicatedData[dataKey] = replicatedData[dataKey] or {}
            local cosmetics = equipped[weaponName]
            if cosmetics.Skin then replicatedData[dataKey][ReplicatedClass:ToEnum("Skin")] = cosmetics.Skin end
            if cosmetics.Wrap then replicatedData[dataKey][ReplicatedClass:ToEnum("Wrap")] = cosmetics.Wrap end
            if cosmetics.Charm then replicatedData[dataKey][ReplicatedClass:ToEnum("Charm")] = cosmetics.Charm end
        end
        local result = originalNew(replicatedData, clientItem)
        if weaponPlayer == player and equipped[weaponName] and equipped[weaponName].Wrap and result._UpdateWrap then
            result:_UpdateWrap()
            task.delay(0.1, function() if not result._destroyed then result:_UpdateWrap() end end)
        end
        return result
    end
end
local originalGetViewModelImage = ItemLibrary.GetViewModelImageFromWeaponData
ItemLibrary.GetViewModelImageFromWeaponData = function(self, weaponData, highRes)
    if not weaponData then return originalGetViewModelImage(self, weaponData, highRes) end
    local weaponName = weaponData.Name
    local shouldShowSkin = (weaponData.Skin and equipped[weaponName] and weaponData.Skin == equipped[weaponName].Skin) or (viewingProfile == player and equipped[weaponName] and equipped[weaponName].Skin)
    if shouldShowSkin and equipped[weaponName] and equipped[weaponName].Skin then
        local skinInfo = self.ViewModels[equipped[weaponName].Skin.Name]
        if skinInfo then return skinInfo[highRes and "ImageHighResolution" or "Image"] or skinInfo.Image end
    end
    return originalGetViewModelImage(self, weaponData, highRes)
end
pcall(function()
    local ViewProfile = require(player.PlayerScripts.Modules.Pages.ViewProfile)
    if ViewProfile and ViewProfile.Fetch then
        local originalFetch = ViewProfile.Fetch
        ViewProfile.Fetch = function(self, targetPlayer)
            viewingProfile = targetPlayer
            return originalFetch(self, targetPlayer)
        end
    end
end)
local ClientEntity
pcall(function() ClientEntity = require(player.PlayerScripts.Modules.ClientReplicatedClasses.ClientEntity) end)
if ClientEntity then
    if ClientEntity._PlayFinisher then
        local originalPlayFinisher = ClientEntity._PlayFinisher
        ClientEntity._PlayFinisher = function(self, finisherName, isFinal, eliminator, serial)
            local v50 = self.Humanoid or self.RootPart
            if v50 and v50:IsDescendantOf(workspace) then
                if self._current_finisher then
                    self._current_finisher:Destroy()
                end
                local Finishers = ReplicatedStorage.Modules.Finishers
                local finisherModule = Finishers:FindFirstChild(finisherName)
                if finisherModule then
                    self._current_finisher = require(finisherModule).new(v50, isFinal, eliminator)
                    self._current_finisher:SetSerial(serial)
                    pcall(self._current_finisher.PlayServer, self._current_finisher)
                    pcall(self._current_finisher.PlayClient, self._current_finisher)
                end
            end
        end
    end
    if ClientEntity.ReplicateFromServer then
        local originalReplicateFromServer = ClientEntity.ReplicateFromServer
        ClientEntity.ReplicateFromServer = function(self, action, ...)
            if action == "FinisherEffect" then
                local args = {...}
                local killerName = args[3]
                local decodedKiller = killerName
                if type(killerName) == "userdata" and EnumLibrary and EnumLibrary.FromEnum then
                    local ok, decoded = pcall(EnumLibrary.FromEnum, EnumLibrary, killerName)
                    if ok and decoded then decodedKiller = decoded end
                end
                local isOurKill = tostring(decodedKiller) == player.Name or tostring(decodedKiller):lower() == player.Name:lower()
                if isOurKill and lastUsedWeapon and equipped[lastUsedWeapon] and equipped[lastUsedWeapon].Finisher then
                    local finisherData = equipped[lastUsedWeapon].Finisher
                    local finisherEnum = finisherData.Enum
                    if not finisherEnum and EnumLibrary then
                        local ok, result = pcall(EnumLibrary.ToEnum, EnumLibrary, finisherData.Name)
                        if ok and result then finisherEnum = result end
                    end
                    if finisherEnum then
                        args[1] = finisherEnum
                        return originalReplicateFromServer(self, action, table.unpack(args))
                    end
                end
            end
            return originalReplicateFromServer(self, action, ...)
        end
    end
end
loadConfig()
if queue_on_teleport then
    pcall(function()
        queue_on_teleport([[
            task.wait(1)
            loadstring(game:HttpGet("https://raw.githubusercontent.com/reIics/yabujin/refs/heads/main/yabujin.lua"))()
        ]])
    end)
end
