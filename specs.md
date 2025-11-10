# Layout Control – Specs & Feature Log

## Auto-launch missing apps on restore
- When the Swift `layoutctl` tool cannot enumerate windows for a profiled app during restore, it now relaunches that bundle ID, waits for it to spin up, and retries the window query before giving up.

## Raycast layout restore – create profiles inline
- The Raycast `Restore Layout` command now tracks the current search text and, when no existing profiles match, offers an action to create a new profile that runs `layoutctl save <profile>` and refreshes the list on success.

## layoutctl delete command
- The Swift CLI now supports `layoutctl delete <profile>` to remove the stored JSON profile from `~/.layoutctl/layouts`, returning a `profileNotFound` error if the file is missing.

## Raycast restore – delete profiles
- The Raycast `Restore Layout` command now offers a destructive action to delete the selected profile via `layoutctl delete`, with confirmation and list refresh.

