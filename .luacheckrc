std = "lua51"

-- Addon globals
globals = { "AutoPIExtended", "AutoPIExtendedDB" }

ignore = {
    "111",  -- setting non-standard global (WoW addon pattern)
    "112",  -- mutating non-standard global
    "113",  -- accessing undefined variable (WoW API: CreateFrame, C_Timer, etc.)
    "631",  -- line too long (style, not correctness)
}
