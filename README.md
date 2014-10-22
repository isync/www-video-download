# WWW::Video::Download

Scripts to download web videos from websites not (yet) supported by [youtube-dl](https://github.com/rg3/youtube-dl) or [p5-www-youtube-download](https://github.com/xaicron/p5-www-youtube-download).

#### ntv-downloader.pl

RTL Television's n-tv website offers web videos primarily as RTMP streams, but also as low quality mp4 and Apple HTTP-Streaming formatted mp4-ts fragments.

Throw any n-tv.de URL with /mediathek/ or /video/ as part of its path at it, and it will download the highest quality mp4 to the current directory.

Implements a simple M3U parser (M3U8), as I couldn't find a good/fitting parser implementation on CPAN.

#### n24-wetter-downloader.pl

Somehow, weather videos are treated differently on N24's website - they never pop up in the Mediathek. So this script does only what its name implies: download today's weather forecast video.

This script preceded the n-tv-download script - that's why the code is less organized.

