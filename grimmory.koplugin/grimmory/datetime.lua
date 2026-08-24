-- Timestamp helpers shared by the Grimmory API and the KOReader sidecar.
--
-- `os.time` always interprets the table it is given as *local* time, so
-- calendar fields that are known to be UTC have to be corrected by the
-- device's offset from UTC or every inbound timestamp ends up skewed.

local GrimmoryDateTime = {}

---@param fields table
---@return table
local function to_numeric_fields(fields)
    return {
        year = tonumber(fields.year),
        month = tonumber(fields.month),
        day = tonumber(fields.day),
        hour = tonumber(fields.hour),
        min = tonumber(fields.min),
        sec = tonumber(fields.sec),
    }
end

---@param fields table
---@return boolean
local function is_complete(fields)
    return
        fields.year ~= nil and
        fields.month ~= nil and
        fields.day ~= nil and
        fields.hour ~= nil and
        fields.min ~= nil and
        fields.sec ~= nil
end

-- The device's offset from UTC, in seconds, at a given instant.  The UTC
-- calendar fields of `reference` are fed back through `os.time`, which
-- reads them as local time, so the difference between the two is the
-- offset that was applied.
---@param reference number
---@return number offset_seconds
local function utc_offset(reference)
    local utc_fields = os.date("!*t", reference)

    -- Keep the daylight saving flag of the local zone so the offset
    -- stays correct during summer time.
    utc_fields.isdst = os.date("*t", reference).isdst

    return os.difftime(reference, os.time(utc_fields))
end

-- Converts calendar fields that represent UTC into a timestamp.
---@param fields table
---@return number | nil timestamp
function GrimmoryDateTime.fromUTC(fields)
    fields = to_numeric_fields(fields)

    if not is_complete(fields) then
        return nil
    end

    -- `os.time` reads these UTC fields as local time, which lands us the
    -- offset away from the real instant.
    local local_timestamp = os.time(fields)

    if local_timestamp == nil then
        return nil
    end

    return local_timestamp + utc_offset(local_timestamp)
end

-- Converts calendar fields that represent local time into a timestamp.
---@param fields table
---@return number | nil timestamp
function GrimmoryDateTime.fromLocal(fields)
    fields = to_numeric_fields(fields)

    if not is_complete(fields) then
        return nil
    end

    return os.time(fields)
end

return GrimmoryDateTime
