---@alias GrimmoryBookType
---| "PDF"
---| "EPUB"
---| "CBX"
---| "FB2"
---| "MOBI"
---| "AZW3"
---| "AUDIOBOOK"

-- Maps a file extension to the Grimmory `BookFileType` enum.
-- Extensions that Grimmory doesn't know about are left unmapped so the
-- (optional) book type can be omitted from the request instead of being
-- reported incorrectly.
local EXTENSION_MAP = {
    pdf = "PDF",

    epub = "EPUB",

    cbz = "CBX",
    cbr = "CBX",
    cb7 = "CBX",

    fb2 = "FB2",

    mobi = "MOBI",

    azw = "AZW3",
    azw3 = "AZW3",

    m4b = "AUDIOBOOK",
    m4a = "AUDIOBOOK",
    mp3 = "AUDIOBOOK",
    opus = "AUDIOBOOK",
}

local GrimmoryBookType = {}

---@param book_path string | nil
---@return GrimmoryBookType | nil book_type
function GrimmoryBookType.fromPath(book_path)
    if type(book_path) ~= "string" then
        return nil
    end

    local extension = book_path:match("%.([%a%d]+)$")

    if extension == nil then
        return nil
    end

    return EXTENSION_MAP[extension:lower()]
end

return GrimmoryBookType
