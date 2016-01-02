# WWW::Video::Download

Download web videos from websites not (yet) supported by [youtube-dl](https://github.com/rg3/youtube-dl) or [p5-www-youtube-download](https://github.com/xaicron/p5-www-youtube-download).

This distribution started as a collection of scripts, one script for each site. This design is currently being phased out in favor of a Perl module/library model, with a central OO module which uses a backend of "plugins" for each site and is called, for example, with the (soon) included *video-dl* script. The deprecated "per-site" scripts are still included in this distribution.

#### cnbc-downloader.pl

CNBC offers segments from their programming for Video-on-demand viewing on their website. Save these videos for later with this script.

Note that CNBC offers most of their videos also via YouTube, although usually a few hours later. But in case this script here fails, you might want use a script for YouTube downloads and save a video from there.

Implements a simple SMIL parser - which ended up being unused, as the video URIs found there are not usuable without some additional URL parameter or so.

#### bloomberg-downloader.pl

Bloomberg Television offers full shows and segments from their programming for Video-on-demand viewing on their website. Save these videos for later with this script.

Implements a simple M3U parser, actually the same one as found in the n24 and n-tv scripts. It's about time to massage this here into a proper library...

The Bloomberg script is the first now to faciliate a "resume" scheme - in case a 500+ segment video download fails somewhere in the middle, the script will be able to re-use already downloaded segments and continue from there. (Works by tapping into LWP hooks, and writing to temp files)

#### euronews-downloader.pl

Very simple automation script: parses the HTML of a typical Euronews video page and extracts the mp4 link. LWP then downloads it to cwd.

#### ntv-downloader.pl

RTL Television's n-tv website offers web videos primarily as RTMP streams, but also as low quality mp4 and Apple HTTP-Streaming formatted mp4-ts fragments.

Throw any n-tv.de URL with /mediathek/ or /video/ as part of its path at it, and it will download the highest quality mp4 to the current directory.

Implements a simple M3U parser (M3U8), as I couldn't find a good/fitting parser implementation on CPAN.

#### n24-downloader.pl

Categories in N24's Mediathek are somehow messed up: Videos filed under 'Nachrichten', or the special category 'Wetter', either are buried so deep in 'Mediathek' you'll never find them there or they don't show up at all. Anyway, this script downloads N24 videos, once you were able to find a specific one.

Implements a simple M3U parser (M3U8), as I couldn't find a good/fitting parser implementation on CPAN.

#### lumerias-person-downloader.pl

This script parses Lumerias person appearances video collections, as found on http://www.lumerias.com/browse/persons and calls youtube-dl to download these videos, prefixed with date recorded.

#### collider-downloader.pl

Parses collider articles, and if a video is embedded, downloads this video from collider.com's CDN. Doesn't work on newer collider embed code.
