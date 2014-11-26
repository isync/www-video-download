# WWW::Video::Download

Scripts to download web videos from websites not (yet) supported by [youtube-dl](https://github.com/rg3/youtube-dl) or [p5-www-youtube-download](https://github.com/xaicron/p5-www-youtube-download).

#### ntv-downloader.pl

RTL Television's n-tv website offers web videos primarily as RTMP streams, but also as low quality mp4 and Apple HTTP-Streaming formatted mp4-ts fragments.

Throw any n-tv.de URL with /mediathek/ or /video/ as part of its path at it, and it will download the highest quality mp4 to the current directory.

Implements a simple M3U parser (M3U8), as I couldn't find a good/fitting parser implementation on CPAN.

#### n24-downloader.pl

Categories in N24's Mediathek are somehow messed up: Videos filed under 'Nachrichten', or the special category 'Wetter', either are buried so deep in 'Mediathek' you'll never find them there or they don't show up at all. Anyway, this script downloads N24 videos, once you were able to find a specific one.

This script preceded the n-tv-download script - that's why the code is less organized.

#### euronews-downloader.pl

Very simple automation script: parses the HTML of a typical Euronews video page and extracts the mp4 link. LWP then downloads it to cwd.
