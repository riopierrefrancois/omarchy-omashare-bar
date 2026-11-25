# OmaShare bar widget

See shares in progress from Omaedit, Omacut, Omareel, and the command line. Open
the panel for new comments and views, recent shares, links, and thumbnails.
Middle-click the icon or choose **Share a video…** to pick a video and share it
in the background. The upload keeps going when the bar closes or reloads.
Completed shares copy their link and show a notification; failures show an error.

Requires Omarchy Shell, OmaShare **0.3.0 or newer**, `python3`, `systemd-run`,
`wl-copy`, and `omarchy file select`. Sign in with `omashare login` in a terminal.
The widget hides if `omashare` is not installed.

## Install

```sh
ln -s ~/src/omarchy-omashare-bar ~/.config/omarchy/plugins/omashare-share
omarchy bar put omashare.share --section right
```

These are instructions, not steps run by this repo. No setup files are created
by the widget. The symlink name is merely a local folder name; the manifest's
plugin ID is `omashare.share`.

## Checks and privacy

The widget reads OmaShare's local job files every second while sharing or the
panel is open, otherwise every five seconds. It runs `omashare recent --json`
and `omashare activity --json` when you open the panel, when a job finishes,
and every five minutes in the background. The latter check can be turned off
in the bar widget settings with **Check for new activity in the background**
(`checkForActivity`, on by default). Opening the panel still checks. OmaShare
handles sign-in and its own server requests; this plugin does not contact a
server directly. Thumbnails are loaded only from local paths returned by
OmaShare. The bar does not replay notifications for old completed jobs when
it starts.

English strings are in `i18n/en.json`; Omarchy's translation loader uses the
live shell language and falls back to English when no other catalog exists.
