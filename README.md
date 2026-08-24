# grimmory.koplugin

> [!WARNING]
> This is ALPHA software and WILL have bugs or other inadvertent behaviors.
> 
> Beware, that makes you an ALPHA tester.  This software may require you to
> erase data on your device, or on your Grimmory server.
>
> Please report any bugs or issues.

Read your books from Grimmory, sync your shelves, and track reading
progress automatically.

## Installation

Download the [latest release][latest-plugin] file and extract it to
your KOReader plugin folder.  Then, restart KOReader.

The Grimmory plugin is under "Tools" (🛠️) for configuration.

## Updating

Updating can either be done manually by replacing the plugin folder
in KOReader with the [latest release][latest-plugin] or by using the
built-in updater.

The updater may be found at:

**Tools** -> **Grimmory** -> **About Grimmory Sync**

From that menu you may **Check for Updates** and update the plugin
to the latest release.

> [!TIP]
> You must restart KOReader to see the updates apply.

## Reading Sessions

Reading sessions record how long you read a book, and how far you got, and
push them to Grimmory so your reading statistics stay up to date.

The settings live under:

**Tools** -> **Grimmory** -> **Sync Reading Sessions**

Sessions are collected from page turns while you read and are only sent
once a session has ended, so a session that is still in progress is never
reported twice.

The pages you started and finished on are sent as the session location,
which Grimmory shows in the reading session list.

Short sessions can be filtered out with:

**Tools** -> **Grimmory** -> **Reading Session Thresholds**

- **Minimum Session Seconds** — sessions shorter than this are skipped
  (30 seconds by default).
- **Minimum Session Pages** — sessions covering fewer pages than this are
  skipped (disabled by default).

Skipped sessions are dropped permanently and are not retried on the next
sync.

## Uploading Books

KOReader can save a Wikipedia article as an EPUB, and those files always
land in the same folder on the device.  The plugin can watch that folder,
upload anything it finds to Grimmory, and delete the local copy once
Grimmory has processed the book.

Turn it on with:

**Tools** -> **Grimmory** -> **Upload Books**

Then configure it under:

**Tools** -> **Grimmory** -> **Upload Configuration**

- **Upload Folder** — the folder that is watched for new books.  Point it
  at the folder KOReader saves Wikipedia articles into.  It cannot be the
  download folder, otherwise downloaded books would be sent straight back.
- **Target Library** — the Grimmory library (and library path) the books
  are uploaded into.
- **Target Shelf** — an optional shelf the uploaded books are added to.
- **Delete Local Copy After Upload** — removes the file from the device
  once the book exists in Grimmory (enabled by default).

Uploads happen as part of a normal sync.  Only book files are uploaded
(EPUB, PDF, CBZ, CBR, CB7, MOBI, AZW, AZW3, FB2 and DJVU), and files that
were written moments ago are left for the next sync so a half-written
file is never sent.

A local copy is only deleted after Grimmory has finished processing the
book and, when a shelf is configured, after the book has been added to
that shelf.  Anything else keeps the file on the device so the next sync
can try again.

## License

Distributed under the terms of the [AGPL-3.0 License](./LICENSE).

[latest-plugin]: https://github.com/guerrerotook/grimmory.koplugin/releases/latest/download/grimmory.koplugin.zip
