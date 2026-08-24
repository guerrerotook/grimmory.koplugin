-- Timestamp helpers shared by the Grimmory API and the KOReader sidecar.
--
-- `os.time` always interprets the table it is given as *local* time, so
-- calendar fields that are known to be UTC cannot be handed to it or
-- every inbound timestamp ends up skewed by the device's offset.

local GrimmoryDateTime = {}

local SECONDS_PER_DAY = 86400

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

-- Days between a civil date and 1970-01-01, using Howard Hinnant's
-- calendar algorithm.  Doing the arithmetic here keeps the conversion
-- away from the device's timezone, which `os.time` cannot be told to
-- ignore and which is ambiguous during a daylight saving change.
---@param year number
---@param month number
---@param day number
---@return number days
local function days_from_civil(year, month, day)
    -- March is treated as the first month of the year so that a leap day
    -- lands at the end of it.
    year = month <= 2 and year - 1 or year

    local era = math.floor(year / 400)
    local year_of_era = year - era * 400
    local day_of_year = math.floor((153 * (month + (month > 2 and -3 or 9)) + 2) / 5) + day - 1
    local day_of_era =
        year_of_era * 365 +
        math.floor(year_of_era / 4) -
        math.floor(year_of_era / 100) +
        day_of_year

    return era * 146097 + day_of_era - 719468
end

-- Converts calendar fields that represent UTC into a timestamp.
---@param fields table
---@return number | nil timestamp
function GrimmoryDateTime.fromUTC(fields)
    fields = to_numeric_fields(fields)

    if not is_complete(fields) then
        return nil
    end

    local days = days_from_civil(fields.year, fields.month, fields.day)

    return
        days * SECONDS_PER_DAY +
        fields.hour * 3600 +
        fields.min * 60 +
        fields.sec
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
