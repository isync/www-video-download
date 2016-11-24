#!/usr/bin/perl -w

use strict;
use warnings;

use LWP::UserAgent;
use POSIX;
use HTTP::Date;
use Path::Tiny;

die "Please supply a N24 URL on command-line" unless @ARGV;

our $ua = LWP::UserAgent->new;
# $ua->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

while( my $url = shift(@ARGV) ){
	print "WWW::Video::Download: $url \n";

	unless($url =~ /welt\.de\/|www\.n24\.de/){
		print " This doesn't look like a valid N24/Welt.de URL. Skipped. \n";
		exit;
	}

	my ($urls,$hint) = parse_n24($url);

	## return early with a slighly different logic for welt.de videos
	if( $hint eq 'welt.de' ){
		## fabricate output filename
		my $output_filename = $urls->{title} . '.mp4';

		print "WWW::Video::Download: writing to file $output_filename \n";
		my $response = $ua->get($urls->{file}, ':content_file' => $output_filename );

		if($url =~ /maira-|susanne-/i){ # wft!? weather videos are on the weather anchor's profile pages...
			my $stamp = $response->header('Date');
			$stamp = HTTP::Date::str2time($stamp);
			$stamp = POSIX::strftime("%Y_%m_%d", localtime($stamp));

			print "Seems to be a weather video. Rename according to our legacy behaviour \n";
			rename($output_filename, "N24-Wetter_$stamp.mp4");
		}

		exit;
	}

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
	for(@playlist){
		print " dl: $_->{uri} \n";

		my $filename = path($_->{path})->basename;
		$response = $ua->get($_->{uri}, ':content_file' => $filename );

		if($response->is_success){
			push(@done, $filename);
		}
	}

	## fabricate output filename
	my $output_filename;
	if($url =~ /n24\/Nachrichten\/Wetter\//){
		my $stamp = $response->header('Date');
		$stamp = HTTP::Date::str2time($stamp);
		$stamp = POSIX::strftime("%Y_%m_%d", localtime($stamp));

		$output_filename = "N24-Wetter_$stamp.mp4";
	}else{
		$output_filename = path($url)->basename(qr/.html/) . '.mp4'; # Path::Tiny removes '.html' only with version > 0.054
	}

	print "WWW::Video::Download: writing to file $output_filename \n";
	system("cat @done > $output_filename");

	for(@done){
		# print " remove: $_ \n";
		unlink($_) or die "$!";
	}

	die "Some fragments were not downloaded properly" unless @done == @playlist;
}

# expects a N24 URL,
# returns a hashref with absolute video URLs and playlists
sub parse_n24 {
	print "WWW::Video::Download: GET:$_[0] \n";
	my $response = $ua->get(shift);
 
	die unless $response->is_success;

	my $html = $response->decoded_content;

	## return early on newer welt.de layout
	if( $html =~ / funkotron / ){
		print "welt.de layout detected\n";
		require JSON;
		require Data::Dumper;

		my $line;
		for( split("\n", $html) ){
			if($_ =~ /sectionVideoAd/){
				$line = $_;
				last;
			}
		}

		# print $line;

		my $json = JSON->new->relaxed;
		my $ref = $json->decode('{'.$line.'}') or die $!;

		# n24/welt provides 4 versions, with 720p being the best, and one dynamic m3u8 playlist with .ts files
		# where the "sources ref" is array element 1, or element 0 sometimes...
		my $sources_ref;
		for( @{ $ref->{page}->{content}->{media} } ){
			$sources_ref = $_;
			last if $sources_ref->{sources};
		}

		# print Data::Dumper::Dumper( $sources_ref );

		die "Could not extract JSON data" unless $ref && $sources_ref;

		my $urls = {
			title	=> $sources_ref->{title},
			file	=> $sources_ref->{file},
		};

		print "WWW::Video::Download::parse_n24: file:$urls->{file} \n";
		return ($urls, 'welt.de'); # second return value is a hint to tell our processing logic to treat returned data as coming from welt.de
	}

	## legacy n24

	#				_n24VideoCfg.html5.videoMp4Source = "http://n24video-vod.dcp.adaptive.level3.net/cm2013/cmp/dd ...";
	#				_n24VideoCfg.html5.videoOgvSource = "---";
	#				_n24VideoCfg.html5.videoWebmSurce = "---";

	$html =~ /\Q_n24VideoCfg.html5.videoMp4Source = "\E([^"]+)\Q";\E/;

	die "Could not extract playlist URL" unless $1;

	my $urls = {
		m3u	=> $1,
	};

	print "WWW::Video::Download::parse_n24: m3u:$urls->{m3u} \n";
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
