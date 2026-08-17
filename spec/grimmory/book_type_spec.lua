local assert = require 'luassert'

package.path = "grimmory.koplugin/?.lua;" .. package.path

local GrimmoryBookType = require("grimmory/book_type")

describe("GrimmoryBookType", function()
    describe("fromPath", function()
        it("maps known extensions to the Grimmory book type", function()
            local expected_types = {
                ["/books/book.epub"] = "EPUB",
                ["/books/book.pdf"] = "PDF",
                ["/books/book.cbz"] = "CBX",
                ["/books/book.cbr"] = "CBX",
                ["/books/book.cb7"] = "CBX",
                ["/books/book.fb2"] = "FB2",
                ["/books/book.mobi"] = "MOBI",
                ["/books/book.azw"] = "AZW3",
                ["/books/book.azw3"] = "AZW3",
                ["/books/book.m4b"] = "AUDIOBOOK",
                ["/books/book.m4a"] = "AUDIOBOOK",
                ["/books/book.mp3"] = "AUDIOBOOK",
                ["/books/book.opus"] = "AUDIOBOOK",
            }

            for book_path, expected_type in pairs(expected_types) do
                assert.are.equal(expected_type, GrimmoryBookType.fromPath(book_path))
            end
        end)

        it("is case insensitive", function()
            assert.are.equal("EPUB", GrimmoryBookType.fromPath("/books/Book.EPUB"))
            assert.are.equal("CBX", GrimmoryBookType.fromPath("/books/Book.CbZ"))
        end)

        it("handles paths with dots in the name", function()
            assert.are.equal("EPUB", GrimmoryBookType.fromPath("/books/v1.2 book.epub"))
        end)

        it("returns nil for unknown or missing extensions", function()
            assert.is_nil(GrimmoryBookType.fromPath("/books/book.txt"))
            assert.is_nil(GrimmoryBookType.fromPath("/books/book"))
            assert.is_nil(GrimmoryBookType.fromPath(nil))
        end)
    end)
end)
