#!/usr/bin/perl -w

use strict;
use warnings;

use LWP::UserAgent;
use URI;
use Path::Tiny;

# use POSIX;
# use HTTP::Date;

die "Please supply a Collider.com URL on command-line" unless @ARGV;

our $ua = LWP::UserAgent->new;
$ua->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

while( my $url = shift(@ARGV) ){
	print "WWW::Video::Download: $url \n";

	unless($url =~ /collider\.com/){
		print " This doesn't look like a valid collider.com video URL. Skipped. \n";
		next;
	}

	my $video = parse_collider($url);

	unless($video){
		print " No video on this page, as it seems. Skipped. \n";
		next;
	}

	## fabricate output filename
	# my $stamp = $response->header('Date');
	# $stamp = HTTP::Date::str2time($stamp);
	# $stamp = POSIX::strftime("%Y_%m_%d", localtime($stamp));

	# my $output_filename = path($url)->basename(qr/.html/) . '.mp4'; # Path::Tiny removes '.html' only with version > 0.054

	my $output_filename = $video->{title}; $output_filename =~ s/\//_/g; $output_filename .= '.flv';

	print "WWW::Video::Download: writing to file $output_filename \n";

	my $response = $ua->get($video->{url}, ':content_file' => $output_filename );
	die "Could not get video file" unless $response->is_success();
	next;
}

# expects a n-tv URL,
# returns a hashref with absolute video URLs and playlists
sub parse_collider {
	print "WWW::Video::Download: GET:$_[0] \n";
	my $response = $ua->get(shift);
 
	die unless $response->is_success;

	my $html = $response->decoded_content;

	if( my ($cdn_id) = $html =~ /springboard\.gorillanation\.com\/xml_feeds_advanced\/index\/\d+\/\d+\/(\d+)\/\&amp;/ ){
		my ($title) = $html =~ /\Q<meta property="og:title" content="\E([^"]+)"\s+\/>/;

		print "WWW::Video::Download: cdn_id:$cdn_id, title:$title \n";

		return {
			title	=> $title,
			url => "http://cdn.springboardplatform.com/storage/collider.com/conversion/". $cdn_id .".flv"
		};
	}

	return undef;
}
