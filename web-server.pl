#!/usr/bin/perl

# referenced code tips from https://github.com/ReneNyffenegger/perl-webserver/blob/master/adp-gmbh/webserver.pl and http://www.wellho.net/resources/ex.php4?item=p402/miniserver.pl

use warnings;
use strict;

use IO::Socket;
use Data::Dumper;

my $port = 7007;

sub cgi_data {
	my $line = shift;
	my %data = ();
	if ($line ne "") {
		foreach my $part (split '&', $line) {
			if ($part =~ /^(.*)=(.*)$/) {
				my $n = $1;
				my $v = $2;
				$n =~ s/%(..)/chr(hex($1))/eg;
				$v =~ s/%(..)/chr(hex($1))/eg;
				$data{$n}=$v;
			} else {
				$data{$part} = "";
			}
		}
	}
	return \%data;
}


my $server = new IO::Socket::INET(
	Proto => 'tcp',
	LocalPort => $port,
	Listen => SOMAXCONN,
	Reuse => 1
) or die $!;


while (my $client = $server->accept()) {
	$client->autoflush(1);
	my %req;
	local $/ = Socket::CRLF;
	while(my $line = <$client>) {
		print $line;
		chomp $line;
		# first line
		if ($line =~ /\s*(\w+)\s+(\S+)\s+HTTP\/(\d.\d)/) {
			$req{meta} = {
				method => uc($1),
				path => $2,
				version => $3,
			};
			# check for data following a '?'
			if ($req{meta}{path} =~ /.+\?(\S+)/) {
				$req{body} = $1;
			}
			# exit early if it's only a GET request
			if ($req{meta}{method} eq "GET") {
				last;
			}
		# HTTP header lines
		} elsif ($line =~ /(\w+):\s*(\S+)/) {
			 $req{header}{$1} = $2;
		# break line between header and data
		} elsif (
			$line eq "" and
			exists $req{header}{"Content-Length"} and
			defined $req{header}{"Content-Length"}
		) {
			my $bytes_read = read ( $client, my $bytes, $req{header}{"Content-Length"} );
			$req{body} = $bytes;
		# error
		} else {
			print "Unable to process request:'\n'$line'\n";
		}
	}
	if (defined $req{body}) {
		$req{data} = cgi_data $req{body};
	}
	print Dumper(\%req);
	print $client "HTTP/1.0 200 OK\r\nContent-type: text/html\r\n\r\n";
	print $client "<h1>It works!</h1>".Dumper(\%req);
	close $client;
}


