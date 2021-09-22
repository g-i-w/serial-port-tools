#!/usr/bin/perl

# referenced code from https://github.com/ReneNyffenegger/perl-webserver/blob/master/adp-gmbh/webserver.pl and http://www.wellho.net/resources/ex.php4?item=p402/miniserver.pl

use warnings;
use strict;

use Data::Dumper;

use Time::HiRes qw(usleep);

use IO::Socket;

use Device::SerialPort; # UNIX
# use Win32::SerialPort; # Windows
STDOUT->autoflush(1);



my %args = (
	port => 7007,
	device => "/dev/ttyUSB0",
	baud => "115200",
	@ARGV
);

# web server
my $server = new IO::Socket::INET(
	Proto => 'tcp',
	LocalPort => $args{port},
	Listen => SOMAXCONN,
	Reuse => 1
) or die $!;

# serial-port device
my $device = Device::SerialPort->new($args{device}) or die $!;

$device->baudrate($args{baud});
$device->databits(8);
$device->parity("none");
$device->stopbits(1);

$device->read_char_time(0);	# don't wait for each character
$device->read_const_time(1);	# 1 millisecond per unfulfilled "read" call




sub hexToBytes {
	my $hexStr = shift;
	my $hexLength = int(length($hexStr)/2);
	my @byteArray;
	for my $i (0..$hexLength-1) {
		my $byte = ( hex(substr($hexStr,($i*2),2)) & 255 );
		push( @byteArray, $byte );
	}
	return @byteArray;
}

sub bytesToHex {
	my $byteStr = "";
	foreach my $byte ( @_ ) {
		$byteStr .= sprintf("%02lx", $byte);
	}
	return $byteStr;
}

sub writeByte {
	my $handle = shift;
	my $byte = ((shift) & 255);
	my $count = $handle->write(chr($byte));
	warn "\nERROR: unable to write $byte" if ( $count != 1 );
	return $byte;
}

sub writePacket {
	my ( $handle, $header, $data ) = ( @_ );
	my $checkSum = 0;
	my $hexStr = $header.$data; # all we do here is recombine them
	my @bytesArray = hexToBytes($hexStr);
	foreach my $binVal ( @bytesArray ) {
		$checkSum += writeByte($handle, $binVal);
	}
	my $checkSumByte = ($checkSum & 255);
	writeByte($handle, $checkSumByte);
	return $checkSumByte;
}

sub compareHeader {
	my ( $headerRef, $packetRef ) = ( @_ );
	my @header = @{$headerRef};
	my @packet = @{$packetRef};
	if (scalar(@packet) < scalar(@header)) {
		return 0;
	}
	for my $i (0..scalar(@header)-1) {
		if ($header[$i] != $packet[$i]) {
			return 0;
		}
	}
	return 1;
}

sub readPacket {
	my ( $handle, $header, $dataLength, $timeout ) = ( @_ );
	my @headerArray = hexToBytes($header);
	my $checkSum = 0;
	my @packet;
	my $start_time = Time::HiRes::time();
	READ_LOOP:
	while (1) {
		my ($count,$buffer) = $handle->read(1024);
		if ($count > 0) {
			foreach my $char (split //, $buffer) {
				my $binVal = ord $char;
				push(@packet, $binVal);
				if (compareHeader(\@headerArray, \@packet) and $binVal == ($checkSum & 255) and scalar(@packet) == scalar(@headerArray)+$dataLength+1) {
					last READ_LOOP;
				}
				$checkSum += $binVal;
				shift(@packet) if (scalar(@packet) > scalar(@headerArray) + $dataLength);
			}
			warn Dumper( \@packet );
		}
		last if Time::HiRes::time() - $start_time > $timeout;
	}
	#print Dumper(\@packet);
	my @data_field = ( @packet[scalar(@headerArray)..$#packet-1] );
	#print Dumper(\@data_field);
	return ( \@data_field, ($checkSum & 255) );
}

sub cgi_data {
	my $line = shift;
	my %data = ();
	if (defined $line and $line ne "") {
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

sub http_request {
	my $client = shift;
	$client->autoflush(1);
	my %req;
	local $/ = Socket::CRLF;
	while(my $line = <$client>) {
		#print $line;
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
			warn "Unable to process request:'\n'$line'\n";
		}
	}
	$req{data} = cgi_data $req{body};
	return \%req;
}

sub http_response {
	my ( $client, $request ) = ( @_ );
	my $packet_ref;
	my $txChecksum;
	my $rxChecksum;
	#print Dumper($request);

	# overlay settings from HTTP cgi-data onto default settings
	my %settings = ( 
		txHeader => "7478", # 't','x'
		txData => "0102030405060708",
		rxHeader => "7278", # 'r','x'
		#rxLength => 8,
		rxTimeout => 2.0, # seconds
		%{$request->{data}}
	);
	if (not defined($settings{rxLength})) {
		$settings{rxLength} = length($settings{txData})/2;
	}
	#print Dumper(\%settings);

	$request->{meta}{path} =~ /\/write/ and do {
		$txChecksum = writePacket( $device, $settings{txHeader}, $settings{txData} );
	};

	$request->{meta}{path} =~ /\/read/ and do {
		($packet_ref, $rxChecksum) = readPacket( $device, $settings{rxHeader}, $settings{rxLength}, $settings{rxTimeout} );
	};

	$request->{meta}{path} =~ /\/verbose/ and do {
		# display settings via STDERR
		warn
			"device:      $args{device}\n".
			"baudrate:    $args{baud}\n".
			"TX header:   0x$settings{txHeader}\n".
			"TX data:     0x$settings{txData}\n".
			"TX checksum: 0x".bytesToHex($txChecksum)."\n".
			"RX header:   0x$settings{rxHeader}\n".
			"RX data:     0x".bytesToHex(@{$packet_ref})."\n".
			"RX checksum: 0x".bytesToHex($rxChecksum)."\n".
			"RX length:   $settings{rxLength}\n"
		;
	};
	
	$request->{meta}{path} =~ /\/hex/ and do {
		print bytesToHex(@{$packet_ref}), "\n";
	};

	$request->{meta}{path} =~ /\/dump/ and do {
		print Dumper([ $settings{rxHeader}, $packet_ref, $rxChecksum ]);
	};

	# JSON if requested...
	if ($request->{meta}{path} =~ /\/json/) {
		print $client
			"HTTP/1.0 200 OK\r\n".
			"Content-type: application/json\r\n".
			"\r\n".
			"{\"tx\":\"$settings{txData}\",\"rx\":\"".bytesToHex(@{$packet_ref})."\"}"
		;

	# ...HTML by default
	} else {
		print $client
			"HTTP/1.0 200 OK\r\n".
			"Content-type: text/html\r\n".
			"\r\n".
			"<html><head></head><body>\n".
			"<b>$args{device}:</b><br><br>\n".
			"<table>\n".
			"<tr>\n".
			( $request->{meta}{path} =~ /\/write/ ? 
				"<td>Tx:</td>".
				"<td bgcolor='lightblue'>0x$settings{txHeader}</td>".
				"<td>0x$settings{txData}</td>".
				"<td bgcolor='blue'>0x".bytesToHex($txChecksum)."</td>"
			: "" ).
			"\n</tr>\n".
			"<tr>\n".
			( $request->{meta}{path} =~ /\/read/ ?
				"<td>Rx:</td>".
				"<td bgcolor='lightgreen'>0x$settings{rxHeader}</td>".
				"<td>0x".bytesToHex(@{$packet_ref})."</td>".
				"<td bgcolor='green'>0x".bytesToHex($rxChecksum)."</td>"
			: "").
			"\n</body></html>\n"
		;
	}

}




################################ main loop ################################

while (my $client = $server->accept()) {
	my $request = http_request($client);
	http_response($client, $request);
	close $client;
}




