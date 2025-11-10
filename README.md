# layoutctl Toolkit

`layoutctl` is a developer toolset for macOS that saves, restores, and shares curated desktop layouts. It ships with two parts:

- The Swift command-line utility `layoutctl` (in `Sources/layoutctl/`) that snapshots and restores window configurations.
- A Raycast extension (in `raycast-extension/layoutctl/`) that provides a friendly UI on top of the utility for quick layout recalls.

Together they let you script layout automation locally and trigger it from Raycast.


## Install

- Clone this repo
- Run this command which will take the precompiled executable from this repo

```sh
sudo install -m 755 .bin/layoutctl /usr/local/bin/layoutctl
```

Then install the raycast extension for the first time

```sh
cd raycast-extension/layoutctl
npx ray dev 
```

(once installed you can close the terminal no need to keep it running). 



## Build and Install the CLI as a Dev

All shell snippets assume you run them from this directory

```sh
swift build -c release
sudo install -m 755 .build/release/layoutctl /usr/local/bin/layoutctl
```

That drops the release binary into `/usr/local/bin/layoutctl` with the correct permissions.

## Set Up the Raycast Extension

From `/Users/joba/Projects/Private/AIChat/macosapp-layout/raycast-extension/layoutctl`:

```sh
npm install
npx ray dev
```

`npx ray dev` launches the Raycast development environment so you can run and iterate on the extension locally.


