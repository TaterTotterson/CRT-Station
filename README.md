# 240-MP

240-MP is a retro VCR-style Emby/Jellyfin media frontend for a Raspberry Pi 4 connected to a CRT over composite video.

This fork is focused on one appliance-style setup:

- Raspberry Pi 4
- CRT display over composite output
- Ready-to-flash SD card image
- Boot screen and automatic launch straight into 240-MP
- Argon IR remote support through a GPIO IR receiver on GPIO23
- Local Emby/Jellyfin browsing and playback
- No Plex support

The easiest way to use it is to download the ready-to-flash `.img.xz` from the latest GitHub release, flash it to an SD card, and boot the Pi.

## Features

### Emby/Jellyfin
- Local Emby/Jellyfin server sign in
- Movies, TV Shows, and Other Videos library browsing
- Continue Watching and Resume
- Autoplay next episode
- Playlist and Collection support
- Audio and subtitle track selection
- Auto direct play with AV1-to-H.264 fallback
- Forced transcode quality options

### Local Files
- Browse folders on the Pi
- Play common video formats
- `m3u` and `m3u8` playlist support
- Loop and shuffle playback

### Appliance Image
- Boots straight into 240-MP
- CRT/composite NTSC defaults
- 240-MP boot screen
- SSH enabled for debugging
- Argon IR remote defaults
- GPIO IR receiver default: GPIO23, physical pin 16
- Analog audio defaults for the Pi composite/3.5mm setup

### Controls
- Keyboard navigation
- USB remote/controller navigation
- Argon IR remote support
- Media keys during playback
- Local HTTP playback-control API for companion apps

## Install

- [Flash the ready-to-flash Raspberry Pi image](INSTALL.md#flash-the-ready-to-flash-image)
- [Build a custom image](INSTALL.md#build-a-custom-image)
- [Development builds](BUILDING.md)

## Hardware Target

This project targets one setup: a Raspberry Pi 4 connected to a CRT over composite video, with Emby/Jellyfin media playback and Argon IR remote control.

## License

This project is licensed under the GNU General Public License v3.0. See [LICENSE](LICENSE) for the full text.

You are free to use, study, and modify this code. If you distribute a modified version, you must also distribute it under GPL-3.0 and make the source available.

## Credits

This project started as a fork of [anthonycaccese/240-MP](https://github.com/anthonycaccese/240-MP). This fork is focused on Raspberry Pi 4 composite CRT use with Emby/Jellyfin support and Argon IR remote defaults.
