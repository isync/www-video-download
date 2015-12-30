#!/usr/bin/perl

##
## Donwload people videos found at http://www.lumerias.com/browse/persons
##
## Implemented as a simple wrapper script around youtube-dl,
## it parses all videos from a Lumerias.com person appearances page, and calls
## youtube-dl to download these videos, prefixed with the date they were recorded
##

use strict;
use warnings;

use LWP::UserAgent;
use URI;
use Path::Tiny;
use JSON;

# use POSIX;
# use HTTP::Date;

my $xattr = eval {
	require File::ExtAttr;
	1;
};

die "Please supply a Lumerias Person URL on command-line" unless @ARGV;

our $ua = LWP::UserAgent->new;
$ua->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

while( my $person_url = shift(@ARGV) ){
	print "WWW::Video::Download: $person_url \n";

	unless($person_url =~ /lumerias\.com\/person\//){
		print " This doesn't look like a valid Lumerias person URL. Skipped. \n";
		next;
	}

	my @videos = parse_lumerias_person($person_url);
	my $count = scalar(@videos);
	print "WWW::Video::Download: found ". $count ." videos \n";

	my ($cnt, $errors) = (0,0);
	while( my $video = shift(@videos) ){
		$cnt++;
		print "WWW::Video::Download:  downloading $cnt of $count: $video->{url} \n";
		my $command = 'youtube-dl -o "'. $video->{date} .'_%(title)s_%(id)s.%(ext)s" --restrict-filenames --add-metadata --xattrs '. $video->{url};
		my $output = `${command}`;
		my ($outfile) = $output =~ /\QAdding metadata to '\E([^']+)'/;

		unless($outfile){ $errors++; next; }

		print "WWW::Video::Download:  output file: $outfile \n";

		next unless $xattr;

		print "WWW::Video::Download:  adding xattr: lumerias.date.recorded: $video->{date}\n";
		File::ExtAttr::setfattr($outfile, 'lumerias.date.recorded', $video->{date}, { namespace => 'user' });
	}

	print "WWW::Video::Download: done downloading $person_url: $count videos, $errors errors \n";
}

# expects a Lumerias Person videos appearances page,
# returns an array of hashes
sub parse_lumerias_person {
	print "WWW::Video::Download: (HTML page) GET:$_[0] \n";
	my $response = $ua->get(shift);
 
	die unless $response->is_success;

	my $html = $response->decoded_content;

	my @lines = split(/\n/,$html);
	my @videos;
	for my $i (0 .. $#lines){
		if( my ($url) = $lines[$i] =~ /\Q<li class='event' href="\E([^"]+)"\Q data-video-url="\E/ ){
			if( my ($date) = $lines[$i+1] =~ /\Q<div>\E([^<]+)\Q<\/div>\E/ ){
				push(@videos, { url => $url, date => $date });
			}
		}
	}

	return @videos;
}

#	my @urls = $html =~ /\Q<li class='event' href="\E([^"]+)"\Q data-video-url="\E/g;
#	for(@urls){
#		print "$_ \n";
#	}

#	# we need two variables: video guid (a number), and theplatform's feed id (a string)
#	my $url = $response->request->uri->as_string;
#
#	$url =~ /video=(\d+)/;
#	my $guid = $1;
#	die "Could not extract video guid" unless $1;
#
#
#	my $feed_url = 'http://www.cnbc.com/vapi/videoservice/rssvideosearch.do?callback=mobileVideoServiceJSON&action=videos&ids='. $guid .'&output=json&partnerId=6008'; # 6008 seems to be CNBC's thePlatform partner id
#
#	print "WWW::Video::Download: (per-video RSS/JSON feed) GET:$feed_url \n";
#
#	$response = $ua->get($feed_url);
#
#	die unless $response->is_success;
#
#	# from entries > content > url (a SMIL21 playlist)
#	my $json = $response->decoded_content;
#	my $feed_data = decode_json($json);
#
#	die "WWW::Video::Download: feed data not in format we'd expected" unless $feed_data->{rss} && $feed_data->{rss}->{channel} && $feed_data->{rss}->{channel}->{item} && $feed_data->{rss}->{channel}->{item} && $feed_data->{rss}->{channel}->{item}->{'metadata:formatLink'} && ref($feed_data->{rss}->{channel}->{item}->{'metadata:formatLink'}) eq 'ARRAY';
#
#	my $title = $feed_data->{rss}->{channel}->{item}->{title};
#
#	## here we deviate from established workings:
#	# we return a variants_playlist instead of our usual hashref
#	my @variants_playlist;
#	for(@{ $feed_data->{rss}->{channel}->{item}->{'metadata:formatLink'} }){
#		my ($meta,$uri) = split(/\|/,$_);
#		my ($container,$bandwidth,$transport) = split(/_/,$meta);
#		next unless $transport =~ /Download/i;
#		push(@variants_playlist, {
#			bandwidth	=> $bandwidth,
#		#	%{$meta},
#		#	path		=> $line,
#			uri		=> $uri,
#			title		=> $title,
#		});
#	}
#
#	# use Data::Dumper;
#	# print Dumper(\@variants_playlist);
#
##	print "WWW::Video::Download::parse_cnbc: smil:". ($urls->{smil}||'') ." \n";
#	print "WWW::Video::Download::parse_cnbc: variants_playlist:". scalar(@variants_playlist) ." items \n";
#	return @variants_playlist;

