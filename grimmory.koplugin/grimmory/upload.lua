local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local util = require("util")

local GrimmoryLogger = require("grimmory/logger")

local logger = GrimmoryLogger:new()

-- Formats Grimmory knows how to store.  Anything else in the watched
-- folder is left alone rather than rejected by the server.
local UPLOAD_EXTENSIONS = {
    azw = true,
    azw3 = true,
    cb7 = true,
    cbr = true,
    cbz = true,
    djvu = true,
    epub = true,
    fb2 = true,
    mobi = true,
    pdf = true,
}

-- A file that was written moments ago may still be growing, so it waits
-- for the next sync instead of being uploaded half finished.
local MINIMUM_FILE_AGE_SECONDS = 15

-- Grimmory stores the file straight away but only creates the book once
-- a watcher has picked it up and read its metadata.
local PROCESSING_ATTEMPTS = 6
local PROCESSING_DELAY_SECONDS = 5

---@param path string
---@return string
local function basename(path)
    return tostring(path):match("([^/\\]+)$") or tostring(path)
end

---@param path string
---@return string
local function normalize_directory(path)
    return tostring(path or ""):gsub("/+$", "")
end

---@class GrimmoryUpload
---@field settings GrimmorySettings
---@field api GrimmoryAPI
---@field doc_metadata GrimmoryDocMetadata
local GrimmoryUpload = {}

function GrimmoryUpload:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

---@param path string
---@return boolean
function GrimmoryUpload:isUploadableFile(path)
    if path:match("%.sdr/") then
        -- Sidecar contents are not books.
        return false
    end

    local filename = basename(path)

    if filename:sub(1, 1) == "." then
        -- Hidden files are usually partial downloads or system files.
        return false
    end

    local extension = util.getFileNameSuffix(filename)

    if extension == nil or not UPLOAD_EXTENSIONS[extension:lower()] then
        return false
    end

    local modification_time = lfs.attributes(path, "modification")

    if type(modification_time) == "number" then
        if os.time() - modification_time < MINIMUM_FILE_AGE_SECONDS then
            logger:dbg("Skipping file that was just written:", path)
            return false
        end
    end

    return true
end

---@return string[] paths
function GrimmoryUpload:findUploadableFiles(directory)
    local paths = {}

    util.findFiles(
        directory,
        function(path)
            if self:isUploadableFile(path) then
                table.insert(paths, path)
            end
        end,
        true
    )

    table.sort(paths)

    return paths
end

---@param path string
---@return string | nil title
function GrimmoryUpload:getTitle(path)
    local ok, title = pcall(function()
        return self.doc_metadata:getTitle(path)
    end)

    if not ok or type(title) ~= "string" or title == "" then
        return nil
    end

    return title
end

-- Waits for Grimmory to turn the uploaded file into a book so the local
-- copy is only removed once the server really has it.
---@param title string | nil
---@param filename string
---@return Book | nil book
function GrimmoryUpload:waitForProcessedBook(title, filename)
    for attempt = 1, PROCESSING_ATTEMPTS do
        local ok, book = self.api:findBook(title, filename)

        if ok and book ~= nil then
            return book
        end

        if attempt < PROCESSING_ATTEMPTS then
            ffiutil.sleep(PROCESSING_DELAY_SECONDS)
        end
    end

    return nil
end

---@param path string
function GrimmoryUpload:removeLocalBook(path)
    logger:info("Removing uploaded book at:", path)

    local ok = util.removeFile(path)

    if not ok then
        logger:err("Failed to remove uploaded book at:", path)
        return false
    end

    -- The sidecar for a book that is gone is only clutter.
    pcall(function()
        self.doc_metadata:purge(path)
    end)

    return true
end

---@param path string
---@param callback function
function GrimmoryUpload:uploadBook(path, callback)
    local library = self.settings:getUploadLibrary()
    local filename = basename(path)
    local title = self:getTitle(path)

    logger:info("Uploading book to Grimmory:", path)

    local upload_ok, code, message = self.api:uploadBook(path, library.id, library.path_id)

    if not upload_ok and code ~= 409 then
        -- A 409 means the server already holds a file with this name, so
        -- the upload has nothing left to do and the book can be looked up
        -- like any other.
        logger:err("Failed to upload book:", path, "-", message)

        callback({
            state = "book-upload-error",
            book_path = path,
            message = message,
        })

        return
    end

    local book = self:waitForProcessedBook(title, filename)

    if book == nil then
        -- The file is on the server but no book exists for it yet.  The
        -- local copy stays put so the next sync can finish the job.
        logger:warn("Grimmory has not processed the uploaded book yet:", path)

        callback({
            state = "book-upload-pending",
            book_path = path,
        })

        return
    end

    local target_shelf = self.settings:getUploadTargetShelf()

    if target_shelf ~= nil and target_shelf.id ~= nil then
        local shelf_ok, shelf_message = self.api:assignShelves(
            { book.id },
            { target_shelf.id }
        )

        if not shelf_ok then
            -- Without the shelf the upload is not finished, so the file
            -- is kept and retried rather than silently dropped.
            logger:err("Failed to add uploaded book to shelf:", path, "-", shelf_message)

            callback({
                state = "book-upload-error",
                book_path = path,
                message = shelf_message,
            })

            return
        end
    end

    if self.settings:getUploadRemoveBooks() then
        self:removeLocalBook(path)
    end

    callback({
        state = "book-uploaded",
        book_id = book.id,
        book_path = path,
    })
end

---@param callback function
function GrimmoryUpload:uploadBooks(callback)
    if not self.settings:getUploadBooks() then
        logger:dbg("Book upload skipped because feature is disabled")
        return
    end

    local directory = normalize_directory(self.settings:getUploadDirectory())

    if directory == "" then
        logger:err("Book upload skipped because the upload directory is not set")
        return
    end

    if directory == normalize_directory(self.settings:getDownloadDirectory()) then
        -- Uploading the folder books are downloaded into would send every
        -- book straight back to the server.
        logger:err("Book upload skipped because the upload directory is the download directory")
        return
    end

    if not util.directoryExists(directory) then
        logger:info("Book upload skipped because the upload directory does not exist:", directory)
        return
    end

    local library = self.settings:getUploadLibrary()

    if library == nil or library.id == nil or library.path_id == nil then
        logger:err("Book upload skipped because no library was selected")
        return
    end

    for _, path in ipairs(self:findUploadableFiles(directory)) do
        local ok, message = pcall(self.uploadBook, self, path, callback)

        if not ok then
            logger:err("Failed to upload book:", path, "-", message)

            callback({
                state = "book-upload-error",
                book_path = path,
                message = message,
            })
        end
    end
end

return GrimmoryUpload
