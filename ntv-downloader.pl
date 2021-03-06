#!/usr/bin/perl -w

use strict;
use warnings;

use LWP::UserAgent;
use URI;
use Path::Tiny;

# use POSIX;
# use HTTP::Date;

die "Please supply a n-tv URL on command-line" unless @ARGV;

our $ua = LWP::UserAgent->new;
$ua->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

while( my $url = shift(@ARGV) ){
	print "WWW::Video::Download: $url \n";

	unless($url =~ /videos|mediathek/){
		print " This doesn't look like a valid n-tv video URL. Skipped. \n";
		next;
	}

	my $urls = parse_ntv($url);

	## dl m3u8
	my $response = $ua->get($urls->{m3u});
	die "Error fetching playlist index ". $response->status_line unless $response->is_success;
	my $variants_playlist = $response->decoded_content;

	my @variants_playlist = parse_m3u($variants_playlist, $urls->{m3u});

	my @by_bandwidth = reverse sort { $a->{bandwidth} <=> $b->{bandwidth} } @variants_playlist;

	my $selected = shift(@by_bandwidth);

	## n-tv switched to AES encrypted HLS streaming, so:
	my $filename = path($url)->basename('.html') . '.mp4';
	# print "WWW::Video::Download: best m3u8 URL: $selected->{uri} \n";
	# print " example: \$ avconv -i $selected->{uri} -acodec copy -absf aac_adtstoasc -vcodec copy $filename \n";
	# print " example: \$ cvlc $selected->{uri} :demux=dump :demuxdump-file=$filename \n";

	if(-f '/usr/bin/avconv'){
		print "WWW::Video::Download: downloading with avconv to file $filename \n";
# http://lists.infradead.org/pipermail/get_iplayer/2012-April/002772.html
# "Unrecognized option 'absf'" unless invoked as ffmpeg
		system("ffmpeg -i $selected->{uri} -acodec copy -absf aac_adtstoasc -vcodec copy $filename");
		next;
	}else{
		$response = $ua->get($urls->{mp4}, ':content_file' => $filename );
		die "Could not get mp4" unless $response->is_success();
		next;
	}

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

# expects a n-tv URL,
# returns a hashref with absolute video URLs and playlists
sub parse_ntv {
	print "WWW::Video::Download: GET:$_[0] \n";
	my $response = $ua->get(shift);
 
	die unless $response->is_success;

	my $html = $response->decoded_content;

	#		video: "/2014/10/WetterNama2_00000000.f4v",
	#		
	#			html5VideoPoster: "http://bilder4.n-tv.de/img/incoming/crop13828831/00000000-cImg_16_9-w670/00000000.jpg",
	#		
	#		videoMp4: "/mobile/WetterNama2_000000000-mob5.mp4",
	#		videoM3u8: "/apple/WetterNama2_000000000-ipad.m3u8"

	$html =~ /\QvideoM3u8: "\E([^"]+)\Q"\E/;

	die "Could not extract playlist URL" unless $1;

	my $urls = {
		m3u	=> ($1 =~ /^\/'/ ? 'http://video.n-tv.de'. $1 : $1),
	};

	## look for extra formats:
        $html =~ /\QvideoMp4: "\E([^"]+)\Q",\E/; # trailing comma
	if($1){
		$urls->{mp4} = ($1 =~ /^\/'/ ? 'http://video.n-tv.de'. $1 : $1);
	}

	print "WWW::Video::Download::parse_ntv: m3u:$urls->{m3u} mp4:$urls->{mp4} \n";
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
