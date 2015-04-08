#!/usr/bin/perl -w

use strict;
use warnings;

use LWP::UserAgent;
use URI;
use Path::Tiny;
use JSON;

# use POSIX;
# use HTTP::Date;

die "Please supply a Bloomberg URL on command-line" unless @ARGV;

our $ua = LWP::UserAgent->new;
$ua->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

while( my $url = shift(@ARGV) ){
	print "WWW::Video::Download: $url \n";

	unless($url =~ /bloomberg\.com/ && $url =~ /\/videos\//){
		print " This doesn't look like a valid Bloomberg video URL. Skipped. \n";
		next;
	}

	my $urls = parse_bloomberg($url);

	## dl m3u8
	my $response = $ua->get($urls->{m3u});
	die "Error fetching playlist index ". $response->status_line unless $response->is_success;
	my $variants_playlist = $response->decoded_content;

	my @variants_playlist = parse_m3u($variants_playlist, $urls->{m3u});

	my @by_bandwidth = reverse sort { $a->{bandwidth} <=> $b->{bandwidth} } @variants_playlist;

	my $selected = shift(@by_bandwidth);

	## dl m3u8
	print "WWW::Video::Download: GET:$selected->{uri} \n";
	$response = undef;
	$response = $ua->get($selected->{uri});
	die "Error fetching playlist ". $response->status_line unless $response->is_success;
	my $playlist = $response->decoded_content;

	my @playlist = parse_m3u($playlist, $selected->{uri});

	## dl fragments to temp files, concatenate them and remove temp files
	# $ua->default_header()->remove_header('Accept-Encoding');
	delete($ua->{def_headers}->{'accept-encoding'});
	my @done;
	my $cnt = 1;
	for(@playlist){
		print " dl ($cnt of ". scalar(@playlist) ."): $_->{uri} \n";

		my $filename = path($_->{path})->basename;
		$response = $ua->get($_->{uri}, ':content_file' => $filename );

		if($response->is_success){
			push(@done, $filename);
		}
		$cnt++;
	}

	## fabricate output filename
	# my $stamp = $response->header('Date');
	# $stamp = HTTP::Date::str2time($stamp);
	# $stamp = POSIX::strftime("%Y_%m_%d", localtime($stamp));

	my $output_filename = path($url)->basename(qr/.html/) . '.mp4'; # Path::Tiny removes '.html' only with version > 0.054

	print "WWW::Video::Download: writing to file $output_filename \n";
	system("cat @done > $output_filename");

	for(@done){
		# print " remove: $_ \n";
		unlink($_) or die "$!";
	}

	die "Some fragments were not downloaded properly" unless @done == @playlist;
}

# expects a bloomberg URL,
# returns a hashref with absolute video URLs and playlists
sub parse_bloomberg {
	print "WWW::Video::Download: (HTML page) GET:$_[0] \n";
	my $response = $ua->get(shift);
 
	die unless $response->is_success;

	my $html = $response->decoded_content;

	$html =~ /"bmmrId":"([^"]+)",/;

	die "Could not extract BMMR id" unless $1;

	my $api_url = 'http://www.bloomberg.com/api/embed?id='. $1 .'&version=v0.8.11&idType=BMMR';

	print "WWW::Video::Download: (JSON embed config) GET:$api_url \n";
	$response = $ua->get($api_url);
 
	die unless $response->is_success;

	my $json = $response->decoded_content;
	my $embed_metadata = decode_json($json);

	my $urls = {
		mp4_low	=> $embed_metadata->{contentLoc},	# a low quality version is simply referenced
	};

	# look for m3u8
	if($embed_metadata && $embed_metadata->{streams} && ref($embed_metadata->{streams}) eq 'ARRAY'){
		for(@{ $embed_metadata->{streams} }){
			if($_->{url} =~ /\.m3u8$/){
				$urls->{m3u} = $_->{url};	# a multi-bitrate m3u8 for iPads is also there
				last;
			}
		}
	}

	# see what else we can get
	my @xml_urls = $embed_metadata->{xml} =~ /<file>([^<]+)<\/file>/g;
	for my $i (0..$#xml_urls){
		my $fragment = $xml_urls[$i];
		$fragment =~ s/^origin:\/\///;
		$urls->{'url_'.$i} = 'http://bloomberg.map.fastly.net/' . $fragment;
	}

	print "WWW::Video::Download::parse_ntv: m3u:$urls->{m3u} mp4_low:$urls->{mp4_low} \n";
	return $urls;
}

# expects a scalar with a playlist
# returns a AoH with the playlist-entries, keeps order
sub parse_m3u {
	my $playlist = shift;
	my $uri = shift; # to resolve relative paths

	# print "WWW::Video::Download::parse_m3u: ".$playlist."\n";
	print "WWW::Video::Download::parse_m3u: parsing playlist\n";

	my @lines = split(/\n/,$playlist);
	die "WWW::Video::Download::parse_m3u: passed playlist does not look to be a properly formatted m3u(8) file!" unless $lines[0] =~ /^#EXTM3U/;
	my @m3u;
	for my $i (0..$#lines){
		my $line = $lines[$i];

		if($line !~ /^#/){
			my $meta_line = $lines[$i - 1];

			my @meta = split(/,\s*/,$meta_line);
			my $meta = {};
			for(@meta){
				my ($key,$val) = split(/=/,$_);
				$meta->{lc($key)} = $val;
			}

			push(@m3u, {
			#	bandwidth	=> $meta->{bandwidth},
				%{$meta},
				path	=> $line,
				uri	=> ''.URI->new_abs($line, $uri),
			});
		}

		$i++;
	}

	# use Data::Dumper;
	# print Dumper(\@m3u);

	return wantarray ? @m3u : \@m3u;
}
