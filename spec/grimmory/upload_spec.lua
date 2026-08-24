local assert = require 'luassert'
local spy = require 'luassert.spy'

package.path = "grimmory.koplugin/?.lua;" .. package.path

local fake_logger = {
    err = spy.new(function() end),
    warn = spy.new(function() end),
    info = spy.new(function() end),
    dbg = spy.new(function() end),
}

package.preload["grimmory/logger"] = function()
    return {
        new = function()
            return fake_logger
        end
    }
end

local fake_files = {}
local fake_modification_times = {}
local removed_files = {}

package.preload["ffi/util"] = function()
    return {
        sleep = function() end,
    }
end

package.preload["libs/libkoreader-lfs"] = function()
    return {
        attributes = function(path, attribute)
            if attribute ~= "modification" then
                return nil
            end

            return fake_modification_times[path]
        end,
    }
end

package.preload["util"] = function()
    return {
        directoryExists = function() return true end,
        getFileNameSuffix = function(filename)
            return filename:match("%.([^%.]+)$")
        end,
        findFiles = function(_, callback)
            for _, path in ipairs(fake_files) do
                callback(path)
            end
        end,
        removeFile = function(path)
            table.insert(removed_files, path)
            return true
        end,
    }
end

local GrimmoryUpload = require("grimmory/upload")

local function make_settings(overrides)
    local settings = {
        getUploadBooks = function() return true end,
        getUploadDirectory = function() return "/mnt/onboard/wikipedia" end,
        getDownloadDirectory = function() return "/mnt/onboard/grimmory" end,
        getUploadLibrary = function() return { id = 1, name = "Books", path_id = 2 } end,
        getUploadTargetShelf = function() return { id = 7, name = "Wikipedia" } end,
        getUploadRemoveBooks = function() return true end,
    }

    for key, value in pairs(overrides or {}) do
        settings[key] = value
    end

    return settings
end

local function make_upload(api_overrides, settings_overrides)
    local api = {
        uploadBook = spy.new(function() return true, 204, nil end),
        findBook = spy.new(function() return true, { id = 42 } end),
        assignShelves = spy.new(function() return true, nil end),
    }

    for key, value in pairs(api_overrides or {}) do
        api[key] = value
    end

    local upload = GrimmoryUpload:new({
        settings = make_settings(settings_overrides),
        api = api,
        doc_metadata = {
            getTitle = function() return "An Article" end,
            purge = function() end,
        },
    })

    return upload, api
end

local function collect_states(callback_states)
    return function(state)
        table.insert(callback_states, state)
    end
end

describe("GrimmoryUpload", function()
    before_each(function()
        fake_files = { "/mnt/onboard/wikipedia/article.epub" }
        fake_modification_times = {}
        removed_files = {}
    end)

    describe("isUploadableFile", function()
        it("accepts a supported book", function()
            local upload = make_upload()
            assert.is_true(upload:isUploadableFile("/books/article.epub"))
        end)

        it("rejects an unsupported extension", function()
            local upload = make_upload()
            assert.is_false(upload:isUploadableFile("/books/notes.txt"))
        end)

        it("rejects sidecar contents", function()
            local upload = make_upload()
            assert.is_false(upload:isUploadableFile("/books/article.sdr/metadata.epub.lua"))
        end)

        it("rejects hidden files", function()
            local upload = make_upload()
            assert.is_false(upload:isUploadableFile("/books/.article.epub"))
        end)

        it("rejects a file that was just written", function()
            local upload = make_upload()
            fake_modification_times["/books/article.epub"] = os.time()

            assert.is_false(upload:isUploadableFile("/books/article.epub"))
        end)
    end)

    describe("uploadBooks", function()
        it("uploads, shelves and removes the local copy", function()
            local upload, api = make_upload()
            local states = {}

            upload:uploadBooks(collect_states(states))

            assert.spy(api.uploadBook).was_called_with(
                api, "/mnt/onboard/wikipedia/article.epub", 1, 2
            )
            assert.spy(api.assignShelves).was_called_with(api, { 42 }, { 7 })
            assert.are.same({ "/mnt/onboard/wikipedia/article.epub" }, removed_files)
            assert.are.equal("book-uploaded", states[1].state)
        end)

        it("keeps the local copy when removal is disabled", function()
            local upload = make_upload(nil, {
                getUploadRemoveBooks = function() return false end,
            })

            upload:uploadBooks(collect_states({}))

            assert.are.same({}, removed_files)
        end)

        it("keeps the local copy when the book is not processed yet", function()
            local upload = make_upload({
                findBook = spy.new(function() return true, nil end),
            })
            local states = {}

            upload:uploadBooks(collect_states(states))

            assert.are.same({}, removed_files)
            assert.are.equal("book-upload-pending", states[1].state)
        end)

        it("keeps the local copy when the upload fails", function()
            local upload, api = make_upload({
                uploadBook = spy.new(function() return false, 400, "Invalid" end),
            })
            local states = {}

            upload:uploadBooks(collect_states(states))

            assert.spy(api.findBook).was_not_called()
            assert.are.same({}, removed_files)
            assert.are.equal("book-upload-error", states[1].state)
        end)

        it("removes the local copy of a duplicate only after a strict match", function()
            local upload, api = make_upload({
                uploadBook = spy.new(function() return false, 409, "File already exists" end),
            })
            local states = {}

            upload:uploadBooks(collect_states(states))

            assert.spy(api.findBook).was_called_with(
                api, "An Article", "article.epub", true
            )
            assert.are.same({ "/mnt/onboard/wikipedia/article.epub" }, removed_files)
            assert.are.equal("book-uploaded", states[1].state)
        end)

        it("keeps the local copy when a different book owns the name", function()
            local upload = make_upload({
                uploadBook = spy.new(function() return false, 409, "File already exists" end),
                findBook = spy.new(function() return true, nil end),
            })
            local states = {}

            upload:uploadBooks(collect_states(states))

            assert.are.same({}, removed_files)
            assert.are.equal("book-upload-error", states[1].state)
        end)

        it("keeps the local copy when the shelf cannot be assigned", function()
            local upload = make_upload({
                assignShelves = spy.new(function() return false, "Nope" end),
            })
            local states = {}

            upload:uploadBooks(collect_states(states))

            assert.are.same({}, removed_files)
            assert.are.equal("book-upload-error", states[1].state)
        end)

        it("skips shelf assignment when no shelf is selected", function()
            local upload, api = make_upload(nil, {
                getUploadTargetShelf = function() return nil end,
            })

            upload:uploadBooks(collect_states({}))

            assert.spy(api.assignShelves).was_not_called()
            assert.are.same({ "/mnt/onboard/wikipedia/article.epub" }, removed_files)
        end)

        it("does nothing when the feature is disabled", function()
            local upload, api = make_upload(nil, {
                getUploadBooks = function() return false end,
            })

            upload:uploadBooks(collect_states({}))

            assert.spy(api.uploadBook).was_not_called()
        end)

        it("does nothing without an upload directory", function()
            local upload, api = make_upload(nil, {
                getUploadDirectory = function() return "" end,
            })

            upload:uploadBooks(collect_states({}))

            assert.spy(api.uploadBook).was_not_called()
        end)

        it("does nothing when the upload directory is the download directory", function()
            local upload, api = make_upload(nil, {
                getUploadDirectory = function() return "/mnt/onboard/grimmory/" end,
            })

            upload:uploadBooks(collect_states({}))

            assert.spy(api.uploadBook).was_not_called()
        end)

        it("does nothing when the upload directory is inside the download directory", function()
            local upload, api = make_upload(nil, {
                getUploadDirectory = function() return "/mnt/onboard/grimmory/wikipedia" end,
            })

            upload:uploadBooks(collect_states({}))

            assert.spy(api.uploadBook).was_not_called()
        end)

        it("skips books that live in the download directory", function()
            fake_files = {
                "/mnt/onboard/grimmory/downloaded.epub",
                "/mnt/onboard/article.epub",
            }

            local upload, api = make_upload(nil, {
                getUploadDirectory = function() return "/mnt/onboard" end,
            })

            upload:uploadBooks(collect_states({}))

            assert.spy(api.uploadBook).was_called(1)
            assert.spy(api.uploadBook).was_called_with(api, "/mnt/onboard/article.epub", 1, 2)
            assert.are.same({ "/mnt/onboard/article.epub" }, removed_files)
        end)

        it("does nothing without a library", function()
            local upload, api = make_upload(nil, {
                getUploadLibrary = function() return nil end,
            })

            upload:uploadBooks(collect_states({}))

            assert.spy(api.uploadBook).was_not_called()
        end)
    end)
end)
