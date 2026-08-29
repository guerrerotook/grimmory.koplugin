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
    return (tostring(path or ""):gsub("/+$", ""))
end

-- The download directory may be stored relative to KOReader while the
-- upload directory always comes from the path chooser, so both have to be
-- resolved before they can be compared.
---@param path string | nil
---@return string
local function resolve_directory(path)
    path = tostring(path or "")

    if path == "" then
        return ""
    end

    local resolved = nil

    if util.realpath ~= nil then
        local ok, result = pcall(util.realpath, path)

        if ok then
            resolved = result
        end
    end

    return normalize_directory(resolved or path)
end

---@param path string
---@param directory string
---@return boolean
local function is_within(path, directory)
    if directory == "" or path == "" then
        return false
    end

    return path == directory or path:sub(1, #directory + 1) == directory .. "/"
end

-- Uploading from the folder books are downloaded into would send every
-- downloaded book straight back to Grimmory.
---@param upload_directory string | nil
---@param download_directory string | nil
---@return boolean
local function is_download_directory(upload_directory, download_directory)
    return is_within(
        resolve_directory(upload_directory),
        resolve_directory(download_directory)
    )
end

---@class GrimmoryUpload
---@field settings GrimmorySettings
---@field api GrimmoryAPI
---@field doc_metadata GrimmoryDocMetadata
---@field library_refreshed boolean | nil
local GrimmoryUpload = {}

function GrimmoryUpload:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

GrimmoryUpload.isDownloadDirectory = is_download_directory

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

---@param directory string
---@param excluded_directory string | nil
---@return string[] paths
function GrimmoryUpload:findUploadableFiles(directory, excluded_directory)
    local paths = {}

    util.findFiles(
        directory,
        function(path)
            if excluded_directory ~= nil and is_within(path, excluded_directory) then
                -- A book that lives in the download folder came from
                -- Grimmory in the first place.
                return
            end

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
---@param strict boolean | nil
---@return Book | nil book
function GrimmoryUpload:waitForProcessedBook(title, filename, strict)
    for attempt = 1, PROCESSING_ATTEMPTS do
        local ok, book = self.api:findBook(title, filename, strict)

        if ok and book ~= nil then
            return book
        end

        if attempt < PROCESSING_ATTEMPTS then
            ffiutil.sleep(PROCESSING_DELAY_SECONDS)
        end
    end

    return nil
end

-- Grimmory only turns a file into a book when its watcher sees the file
-- being written, and that watcher misses a file that was already on disk
-- when it started.  An upload the server refuses because the file is
-- there while no book of it exists is exactly that leftover, and only a
-- rescan of the library makes Grimmory read it.  One rescan covers every
-- leftover in the library, so it is only asked for once per run.
---@return boolean requested
function GrimmoryUpload:refreshLibrary()
    if self.library_refreshed then
        return false
    end

    self.library_refreshed = true

    local library = self.settings:getUploadLibrary()

    if library == nil or library.id == nil then
        return false
    end

    logger:info("Asking Grimmory to rescan library:", library.id)

    local ok, message = self.api:refreshLibrary(library.id)

    if not ok then
        logger:err("Failed to ask Grimmory to rescan library:", library.id, "-", message)
        return false
    end

    return true
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

    -- A 409 means Grimmory refused the file because the library already
    -- holds a file under the name it would be stored as.  That is what an
    -- upload whose book has not been created yet looks like on a retry,
    -- but it is also what an unrelated book that ends up with the same
    -- name looks like, so the book it refers to has to match this file
    -- before the local copy is removed.
    local is_duplicate = not upload_ok and code == 409

    if not upload_ok and not is_duplicate then
        logger:err("Failed to upload book:", path, "-", message)

        callback({
            state = "book-upload-error",
            book_path = path,
            message = message,
        })

        return
    end

    local book = self:waitForProcessedBook(title, filename, is_duplicate)

    if book == nil and self:refreshLibrary() then
        -- The rescan reads whatever the watcher missed, so the book the
        -- upload was waiting for can turn up after it.
        book = self:waitForProcessedBook(title, filename, is_duplicate)
    end

    if book == nil then
        if is_duplicate then
            -- Grimmory stores a file under this name but no book of this
            -- title exists even after a rescan, so there is nothing to
            -- remove locally.  The file stays where it is.
            logger:err(
                "Grimmory stores a file with this name but has no book for it even after a rescan:",
                path
            )

            callback({
                state = "book-upload-error",
                book_path = path,
                message = message,
            })

            return
        end

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

    self.library_refreshed = false

    local directory = resolve_directory(self.settings:getUploadDirectory())

    if directory == "" then
        logger:err("Book upload skipped because the upload directory is not set")
        return
    end

    local download_directory = resolve_directory(self.settings:getDownloadDirectory())

    if is_within(directory, download_directory) then
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

    for _, path in ipairs(self:findUploadableFiles(directory, download_directory)) do
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
