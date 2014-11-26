#!/usr/bin/perl -w

use strict;
use warnings;

use LWP::UserAgent;
use POSIX;
use HTTP::Date;
use Path::Tiny;

my $url = shift(@ARGV) || 'http://www.n24.de/n24/Nachrichten/Wetter/';

	print "WWW::Video::Download: $url \n";

	unless($url =~ /www\.n24\.de/){
		print " This doesn't look like a valid N24 URL. Skipped. \n";
		exit;
	}


my $ua = LWP::UserAgent->new;
my $response = $ua->get($url);
 
die "Error fetching URL:$url" unless $response->is_success;

if($response->decoded_content =~ /\Q_n24VideoCfg.html5.videoMp4Source = "\E([^"]+)\Q";\E/){
	my $playlist_url = $1;
	print "Playlist: $playlist_url \n";

	$response = $ua->get($1);

	die unless $response->is_success;

	print "Playlist: ".$response->decoded_content."\n";

	my @lines = split(/\n/,$response->decoded_content);
	my $filename;
	for(@lines){
		$filename = $_;
		last if $_ =~ /_1000/;
	}

	my $filename_beginning = substr($filename,0,5);

	my ($url_fragment) = split(/$filename_beginning/,$playlist_url);

	print "$url_fragment $filename \n";

	$response = $ua->get($url_fragment . $filename);

	die unless $response->is_success;

	@lines = split(/\n/,$response->decoded_content);
	# print "Playlist items: \n".join("\n",@lines);
	my @files;
	for(@lines){
		next if $_ =~ /^#/;
		print " dl: $_ \n";

		$response = $ua->get($url_fragment . $_, ':content_file' => $_);
		push(@files, $_);
	}

	my $output_filename;
	if($url =~ /n24\/Nachrichten\/Wetter\//){
		my $stamp = $response->header('Date');
		$stamp = HTTP::Date::str2time($stamp);
		$stamp = POSIX::strftime("%Y_%m_%d", localtime($stamp));

		$output_filename = "N24-Wetter_$stamp.mp4";
	}else{
		$output_filename = path($url)->basename(qr/.html/) . '.mp4';
	}

	print "WWW::Video::Download: writing to file $output_filename \n";
	system("cat @files > $output_filename");

	for(@files){
		print " remove: $_ \n";
		unlink($_) or die "$!";
	}
}
