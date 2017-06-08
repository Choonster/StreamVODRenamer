## Stream VOD Renamer

Replaces the literal text `GAME` in the file names of stream VOD downloads with the actual game name (detected from the file name) and adds separators to dates. Also fixes AAC streams so Windows can display the videos' lengths and thumbnails.

Designed to rename VODs downloaded by [twitch_vod_fetch](https://github.com/Choonster/fgtk#twitch-vod-fetch).

This script was created for my own use, it may or may not be of any use to you.

### Requirements

- Requires Windows. Unix support may be added on request.
- Requires [WinAPI](https://github.com/stevedonovan/winapi) and [Penlight](https://github.com/stevedonovan/Penlight).
- Requires [ffmpeg](https://ffmpeg.org/) on the `PATH`.

### Configuration
The **games.lua** file contains the replacements for the `GAME` placeholder in the VOD file names.
The copy included in this repository has been populated through my own personal use, it's not meant to be an exhaustive list.

The **config.lua** file contains the other configuration options.


### Example Usage
```batch
@echo off

REM Download the VODs
REM I recommend downloading the temporary files to an SSD (the DownloadTemp directory) and outputting the final VOD to a larger HDD (the LivestreamDownloads directory)
python twitch_vod_fetch.py --ytdl-output-format "C:\Users\USER\Downloads\LivestreamDownloads\%%(uploader)s\%%(upload_date)s - GAME - %%(title)s - %%(id)s.%%(ext)s" ^
	https://www.twitch.tv/bob/v/12344321 "DownloadTemp/Bob" ^
	https://www.twitch.tv/fred/v/43211234 "DownloadTemp/Fred"

echo.
echo.

REM Rename the VODs
lua StreamVODRenamer.lua
```
