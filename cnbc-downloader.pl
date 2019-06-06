#!/usr/bin/perl -w

use strict;
use warnings;

use LWP::UserAgent;
use URI;
use Path::Tiny;
use JSON;

# use POSIX;
# use HTTP::Date;

die "Please supply a CNBC URL on command-line" unless @ARGV;

our $ua = LWP::UserAgent->new;
$ua->default_header('Accept-Encoding' => scalar HTTP::Message::decodable());

while( my $url = shift(@ARGV) ){
	print "WWW::Video::Download: $url \n";

	unless($url =~ /video\.cnbc\.com|www\.cnbc\.com\/video\//){
		print " This doesn't look like a valid CNBC video URL. Skipped. \n";
		next;
	}

# "SMIL vector": SMIL links seem to lack an additional signature key - not working - abandoned
#	my $urls = parse_cnbc($url);
#
#	## dl smil
#	print "WWW::Video::Download: GET:$urls->{smil} \n";
#	my $response = $ua->get($urls->{smil});
#	die "Error fetching playlist index ". $response->status_line unless $response->is_success;
#	my $variants_playlist = $response->decoded_content;
#
#	my @variants_playlist = parse_smil($variants_playlist, $urls->{smil});
#
#	my @by_bandwidth = reverse sort { $a->{bandwidth} <=> $b->{bandwidth} } @variants_playlist;
#
#	my $output_filename = ( $by_bandwidth[0]->{title} || 'CNBC-Video-'.time() ) . '.mp4';

	my @variants_playlist = parse_cnbc($url);

	my @by_bandwidth = reverse sort { $a->{bandwidth} <=> $b->{bandwidth} } @variants_playlist;

	my $output_filename = ( $by_bandwidth[0]->{title} || 'CNBC-Video-'.time() ) . '.mp4';
	$output_filename =~ s/\W/_/g;

	print "WWW::Video::Download: GET:$by_bandwidth[0]->{uri} \n";
	print "WWW::Video::Download: writing to file $output_filename \n";
	# $ua->default_header()->remove_header('Accept-Encoding');
	delete($ua->{def_headers}->{'accept-encoding'});
	my $response = $ua->get($by_bandwidth[0]->{uri}, ':content_file' => $output_filename );

	die "WWW::Video::Download: error downloading file: ". $response->status_line unless $response->is_success;
}

# expects a CNBC URL,
# returns an array: a @variants_playlist ( - and does NOT return a hashref with absolute video URLs and playlists)
sub parse_cnbc {
	print "WWW::Video::Download: (HTML page) GET:$_[0] \n";
	my $response = $ua->get(shift);
 
	die unless $response->is_success;

	my $html = $response->decoded_content;

	# we need two variables: video guid (a number), and theplatform's feed id (a string)
	my $url = $response->request->uri->as_string;

	$url =~ /video=(\d+)/;
	my $guid = $1;
	die "Could not extract video guid" unless $1;

# "SMIL vector": unused - abandoned
#	$html =~ /tp:feedsServiceURL="http:\/\/feed\.theplatform\.com\/f\/([^\/]+)\/CNBC_prod_global/;
#	my $feedid = $1;
#	die "Could not extract feed id" unless $feedid;
#
#	my $rand = rand(100); $rand =~ s/\.//;
#	my $feed_url = 'http://feed.theplatform.com/f/'. $feedid .'/CNBC_prod_global?byContent=byIsDefault%3Dtrue&sort=added|desc&byGuid='. $guid .'&form=cjson&callback=jQuery111100'. $rand .'_'. time();
#
#	print "WWW::Video::Download: (JSON callback data) GET:$feed_url \n";
#
#	$response = $ua->get($feed_url);
#
#	die unless $response->is_success;
#
#	# from entries > content > url (a SMIL21 playlist)
#	my $json = $response->decoded_content;
#	$json =~ /"url":"([^"]+)"/;
#
#	my $urls = {
#		smil => $1
#	};

	my $feed_url = 'http://www.cnbc.com/vapi/videoservice/rssvideosearch.do?callback=mobileVideoServiceJSON&action=videos&ids='. $guid .'&output=json&partnerId=6008'; # 6008 seems to be CNBC's thePlatform partner id

	print "WWW::Video::Download: (per-video RSS/JSON feed) GET:$feed_url \n";

	$response = $ua->get($feed_url);

	die unless $response->is_success;

	# from entries > content > url (a SMIL21 playlist)
	my $json = $response->decoded_content;
	my $feed_data = decode_json($json);

	die "WWW::Video::Download: feed data not in format we'd expected" unless $feed_data->{rss} && $feed_data->{rss}->{channel} && $feed_data->{rss}->{channel}->{item} && $feed_data->{rss}->{channel}->{item} && $feed_data->{rss}->{channel}->{item}->{'metadata:formatLink'} && ref($feed_data->{rss}->{channel}->{item}->{'metadata:formatLink'}) eq 'ARRAY';

	my $title = $feed_data->{rss}->{channel}->{item}->{title};

	## here we deviate from established workings:
	# we return a variants_playlist instead of our usual hashref
	my @variants_playlist;
	for(@{ $feed_data->{rss}->{channel}->{item}->{'metadata:formatLink'} }){
		my ($meta,$uri) = split(/\|/,$_);
		my ($container,$bandwidth,$transport) = split(/_/,$meta);
		next unless $transport =~ /Download/i;
		push(@variants_playlist, {
			bandwidth	=> $bandwidth,
		#	%{$meta},
		#	path		=> $line,
			uri		=> $uri,
			title		=> $title,
		});
	}

	# use Data::Dumper;
	# print Dumper(\@variants_playlist);

#	print "WWW::Video::Download::parse_cnbc: smil:". ($urls->{smil}||'') ." \n";
	print "WWW::Video::Download::parse_cnbc: variants_playlist:". scalar(@variants_playlist) ." items \n";
	return @variants_playlist;
}

# expects a scalar with a playlist
# returns a AoH with the playlist-entries, keeps order
use XML::Simple ();
sub parse_smil {
	my $playlist = shift;
	my $uri = shift; # to resolve relative paths

	# print "WWW::Video::Download::parse_smil: ".$playlist."\n";
	print "WWW::Video::Download::parse_smil: parsing playlist\n";

	die "WWW::Video::Download::parse_smil: passed playlist does not look to be a properly formatted SMIL file!" unless $playlist =~ /^<smil /i;

	my $ref = XML::Simple::XMLin($playlist);

	my @smil;
	if($ref && $ref->{body} && $ref->{body}->{seq} && $ref->{body}->{seq}->{switch} && $ref->{body}->{seq}->{switch}->{video} && ref($ref->{body}->{seq}->{switch}->{video}) eq 'ARRAY'){
		my $videos = $ref->{body}->{seq}->{switch}->{video};
		my $title = $ref->{body}->{seq}->{switch}->{'ref'} ? $ref->{body}->{seq}->{switch}->{'ref'}->{title} : undef;
		for my $video (@$videos){
			push(@smil, {
				bandwidth	=> $video->{'system-bitrate'},
			#	%{$meta},
			#	path		=> $line,
				uri		=> $video->{src},
				title		=> $title,
			});
		}
	}else{
		die "WWW::Video::Download::parse_smil: paylist is not in the format we'd expected";
	}

	# use Data::Dumper;
	# print Dumper(\@smil);

	return wantarray ? @smil : \@smil;
}
