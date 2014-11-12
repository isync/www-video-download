#!/usr/bin/perl -w

use strict;
use warnings;

use LWP::UserAgent;
use URI;
use Path::Tiny;

# use POSIX;
# use HTTP::Date;

die "Please supply a Euronews URL on command-line" unless @ARGV;

our $ua = LWP::UserAgent->new;

while( my $url = shift(@ARGV) ){
	print "WWW::Video::Download: $url \n";

	unless($url =~ /euronews\.com/){
		print " This doesn't look like a valid Euronews URL. Skipped. \n";
		next;
	}

	my $urls = parse_euronews($url);

	die "Video URL not found" unless $urls->{mp4};

	print " dl: $urls->{mp4} \n";

	my $filename = $url;
	chop($filename); # Euronews URLs end in a slash
	$filename = path($filename)->basename .'.mp4';
	my $response = $ua->get($urls->{mp4}, ':content_file' => $filename );
}

# expects a Euronews URL,
# returns a hashref with absolute video URLs and playlists
sub parse_euronews {
	my $response = $ua->get(shift);
 
	die unless $response->is_success;

	my $html = $response->decoded_content;

	# playlist: [{
        #		image: "http://static.euronews.com/articles/<id>/<thumburl>",
        #		sources: [{file: "http://video-mp4.euronews.com/mp4/<some url>", label: "320p"}],
	#			mediaid: <numeric id>        
    	#	}]

	# never seen it, but Euronews may provide higher bitrate versions in "sources"
	# requiring us to use a more elaborate regex/parser

	$html =~ /\Qsources: [{file: "\E([^"]+)\Q"\E/;

	die "Could not extract video file URL" unless $1;

	my $urls = {
		mp4	=> $1,
	};

	print "WWW::Video::Download::parse_euronews: mp4:$urls->{mp4} \n";
	return $urls;
}
