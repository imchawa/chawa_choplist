Config = {}

Config.Debug = false

Config.DiscordWebhook = ""

-- Checks player and npc distance check
Config.MaxDistance = 30.0

-- Toggle between automated stripping (true), manual third-eye targeting (false), or player choice ("manual")
Config.AutoWalk = "manual"

-- "model" ex: futo.. bison, "class" ex: sports.. off-road, or "random"
Config.ListType = "model"
Config.MaxList = 5 -- if more than 5 add more vehicles in tier list or it will bug out
Config.NpcModel = `mp_m_waremech_01`

-- The maximum time (in hours) a player has to complete their next list before their streak resets
Config.StreakTimeout = 48.0

Config.RefreshMode = "reboot" -- Options: "hours" or "reboot" --list will refresh on reboot, if "reboot" ignore Config.RefreshHours 
Config.RefreshHours = 24.0     -- How many hours before the list and NPC force a refresh

Config.NPCLocations = {
    vec4(258.26, -1801.21, 26.11, 49.2),
    vec4(-469.71, -1719.76, 17.69, 285.91),
    vec4(575.29, 132.01, 98.47, 246.87)
}

Config.ScrapDuration = 7500 --(1000 when testing)

Config.VehiclePool = { -- this will only show if player doesn't have a current streak min 2+ 
    "sultan", "banshee", "krieger", "coquette", "futo", "comet2", "zentorno", "bison","sentinel", "fusilade", "cheetah2"
}

Config.ClassPool = {
    "Sports", "SUV", "Muscle", "Super", "Off-Road", "Coupes", "Sedans"
}

Config.RewardModifiers = {
    ["auto"] = {
        chanceModifier = 0,       -- Added or subtracted directly from the base drop percentage
        amountMultiplier = 1.0    -- Multiplies the final dropped item count
    },
    ["manual"] = {
        chanceModifier = 15,      -- +15% better chance to get items because they did the physical work
        amountMultiplier = 1.5    -- 1.5x more items dropped per successful roll
    }
}

Config.ScrapRewards = {
    ["wheel"] = {
        { item = "rubber", min = 1, max = 4, percentage = 80 },
        { item = "steel", min = 1, max = 2, percentage = 40 }
    },
    ["door"] = {
        { item = "metalscrap", min = 2, max = 5, percentage = 100 }, 
        { item = "glass", min = 1, max = 2, percentage = 50 }
    },
    ["hood"] = {
        { item = "metalscrap", min = 3, max = 6, percentage = 100 },
        { item = "steel", min = 1, max = 2, percentage = 50 } 
    },
    ["trunk"] = {
        { item = "metalscrap", min = 3, max = 5, percentage = 100 },
        { item = "plastic", min = 1, max = 4, percentage = 60 }
    },
    ["crush"] = {
        { item = "money", min = 250, max = 500, percentage = 100 },
        { item = "steel", min = 10, max = 20, percentage = 100 },
        { item = "iron", min = 5, max = 15, percentage = 60 },
        { item = "copper", min = 2, max = 6, percentage = 30 }
    }
}

Config.Tiers = { 
    ["low"] = { minStreak = 2, multiplier = 1.0, pool = {"brawler", "issi2", "blista", "kanjo", "asbo"} },
    ["mid"] = { minStreak = 4, multiplier = 1.3, pool = {"banshee", "sultan", "elegy", "jester", "massacro"} },
    ["high"] = { minStreak = 6, multiplier = 1.6, pool = {"krieger", "tezeract", "t20", "italirsx", "thrax"} },
    ["elite"] = { minStreak = 8, isDelivery = true }
}

Config.EliteDelivery = {
    MaxMissions = 1,
    Models = { "t20", "osiris", "nero" }, -- High-end cars for the mission
    Reward = { item = "money", min = 5000, max = 10000 },
    Pickups = {
        vec4(-1415.5, -956.67, 6.24, 55.25),
        vec4(-737.88, 374.63, 86.87, 87.69),
        vec4(-938.29, -2641.02, 38.11, 240.98),
        vec4(1249.37, -523.47, 67.97, 256.15)
    },
    Dropoffs = {
        vec4(501.57, -1335.85, 28.32, 221.69),
        vec4(-212.16, -1359.38, 30.2, 127.36),
        vec4(-360.1, -77.31, 44.66, 34.58),
        vec4(87.93, 183.68, 103.66, 334.42)
    }
}

Config.PoliceAlert = {
    MinTime = 5,           -- Minimum tracking time in minutes
    MaxTime = 10,          -- Maximum tracking time in minutes
    UpdateInterval = 30000 -- 30 seconds between map pings
}