-- Equipment Box space, for the summary line. Pure Lua.

local capacity = {}

capacity.WARN_FREE = 50       -- yellow from here
capacity.CRITICAL_FREE = 10   -- red from here

-- `used` and `total` box entries, and how many a planned sale would free.
-- Returns nil when the box size is unknown.
function capacity.of(used, total, selling)
    if type(used) ~= "number" or type(total) ~= "number" or total <= 0 then return nil end
    local free = math.max(0, total - used)
    local level = "ok"
    if free <= capacity.CRITICAL_FREE then
        level = "critical"
    elseif free <= capacity.WARN_FREE then
        level = "warn"
    end
    local sold = math.max(0, math.min(selling or 0, used))
    return {
        used = used, total = total, free = free, level = level,
        used_after_sale = used - sold, free_after_sale = free + sold,
    }
end

return capacity
