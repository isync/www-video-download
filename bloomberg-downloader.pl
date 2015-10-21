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

## Make LWP::UA behave "atomically" on existing+complete downloads
$ua->add_handler( response_header => sub {
	my($response, $ua, $h) = @_;

	if($ua->{hello_ua_next_filename}){ # this tells us the user appended triple dash to the current dl-filename, and we'll handle it atomically
# when current-dl-file and "next_filename" is the same, this here would not work:
# because, when this handler is fired, the file is already truncated to zero size
		if(-f $ua->{hello_ua_next_filename}){
			print STDOUT " file exists ($ua->{hello_ua_next_filename}, ". (-s $ua->{hello_ua_next_filename}) ."): comparing size... ";
			if(-s $ua->{hello_ua_next_filename} == $response->content_length()){	# same as $response->header('Content-Length')
				print STDOUT " file seems complete. Skipping. \n";
				$ua->{discard_download} = 1;
				die();
			}else{
				print STDOUT " file seems incomplete (".(-s $ua->{hello_ua_next_filename}) .' vs '. $response->content_length() ."). Re-downloading. \n";
			}
		}
	}
});
$ua->add_handler( response_done => sub {
	my($response, $ua, $h) = @_;

	if($ua->{hello_ua_next_filename} && $ua->{discard_download}){
		# nothing has been downloaded, the current temp file is empty, just delete it, don't clobber existing file with it
		unlink($ua->{hello_ua_next_filename}.'___');
		delete($ua->{discard_download});
	}else{
		rename($ua->{hello_ua_next_filename}.'___', $ua->{hello_ua_next_filename}) if $ua->{hello_ua_next_filename}; # remedy temp file
	}

	delete($ua->{hello_ua_next_filename}) if $ua->{hello_ua_next_filename};
});

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

# not work: got "405 method not supported", at least with akamaihd servers
#		if(-f $filename){
#			print " file exists: HEAD request to compare size... ";
#			$response = $ua->head($_->{uri});
#			if($response->is_success){
#				if(-s $filename == $response->content_length()){	# same as $response->header('Content-Length')
#					print " file seems complete. Skipping. \n";
#					next;
#				}else{
#					print " file incomplete. Re-downloading.\n";
#				}
#			}else{
#				print " failed: ". $response->status_line ."\n";
#			}
#		}

		# enable "atomic" mode: let's tell $ua the destination filename of the next request (which is also a flag),
		# so we can use that in the response handler callback, if nothing has been downloaded, the temp file will simply be removed
		$ua->{hello_ua_next_filename} = $filename;

		$response = $ua->get($_->{uri}, ':content_file' => $filename.'___' );

		if($response->is_success){
#			if($ua->{discard_download}){
#				# nothing has been downloaded, the current temp file is empty, just delete it, don't clobber existing file with it
#				unlink($filename.'___');
#				delete($ua->{discard_download});
#			}else{
#				rename($filename.'___', $filename); # remedy temp file
#			}
			push(@done, $filename);
		}
#		delete($ua->{hello_ua_next_filename});
		$cnt++;
	}

	## fabricate output filename
	# my $stamp = $response->header('Date');
	# $stamp = HTTP::Date::str2time($stamp);
	# $stamp = POSIX::strftime("%Y_%m_%d", localtime($stamp));

	my $output_filename = path($url)->basename(qr/.html/) . '.mp4'; # Path::Tiny removes '.html' only with version > 0.054

	print "WWW::Video::Download: writing to file $output_filename \n";
	my $error = system("cat @done > $output_filename");

	my @missing;
	unless($error){
		for(@done){
			# print " remove: $_ \n";
			if(-f $_){
				unlink($_) or die "$!";
			}else{
				push(@missing, $_);
			}
		}
	}

#	die "Some fragments were not downloaded properly" unless @done == @playlist;
	if(@missing){
		print "Some fragments were not downloaded properly: \n";
		for(@missing){ print " - $_ \n"; }
		die;
	}
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

	my $json = $response->decoded_content(charset => 'none'); # leave it in utf8
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
