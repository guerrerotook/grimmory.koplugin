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

Short sessions can be filtered out with:

**Tools** -> **Grimmory** -> **Reading Session Thresholds**

- **Minimum Session Seconds** — sessions shorter than this are skipped
  (30 seconds by default).
- **Minimum Session Pages** — sessions covering fewer pages than this are
  skipped (disabled by default).

Skipped sessions are dropped permanently and are not retried on the next
sync.

## License

Distributed under the terms of the [AGPL-3.0 License](./LICENSE).

[latest-plugin]: https://github.com/grimmory-tools/grimmory.koplugin/releases/latest/download/grimmory.koplugin.zip
