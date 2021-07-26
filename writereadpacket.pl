#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

use Device::SerialPort;
# use Win32::SerialPort;		# Use instead for Windows

STDOUT->autoflush(1);

my %args = (
	dev => "/dev/ttyUSB0",
	baud => "115200",
	txHeader => "7478",
	txData => "0102030405060708",
	rxHeader => "7278",
	rxLength => 8,
	@ARGV
);


my $port=Device::SerialPort->new($args{dev});
$port->baudrate($args{baud});
$port->databits(8);
$port->parity("none");
$port->stopbits(1);
 
$port->read_char_time(0);		# don't wait for each character
$port->read_const_time(1);	# 1 millisecond per unfulfilled "read" call


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

sub writeByte {
	my $byte = ((shift) & 255);
	my $count = $port->write(chr($byte));
	warn "\nERROR: unable to write $byte" if ( $count != 1 );
	return $byte;
}

sub writePacket {
	my $checkSum = 0;
	my $header = shift;
	my $data = shift;
	my $hexStr = $header.$data; # all we do here is recombine them
#	my $hexLength = int(length($hexStr)/2);
#	for my $i (0..$hexLength-1) {
#		my $hexVal = substr($hexStr,($i*2),2);
#		my $binVal = hex($hexVal);
#		$checkSum += writeByte($binVal);
#	}
	my @bytesArray = hexToBytes($hexStr);
	foreach my $binVal ( @bytesArray ) {
		$checkSum += writeByte($binVal);
	}
	my $checkSumByte = ($checkSum & 255);
	writeByte($checkSumByte);
	return $checkSumByte;
}

sub compareHeader {
	my $headerRef = shift;
	my @header = @{$headerRef};
	my $packetRef = shift;
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
	my $header = shift;
	my @headerArray = hexToBytes($header);
	my $dataLength = shift;
	my $checkSum = 0;
	my @packet;
	READ_LOOP:
	while (1) {
		my ($count,$buffer)=$port->read(1024);
		if ($count > 0) {
			foreach my $char (split //, $buffer) {
				my $binVal = ord $char;
				push(@packet, $binVal);
				if (compareHeader(\@headerArray, \@packet) and $binVal == ($checkSum & 255)) {
					last READ_LOOP;
				}
				$checkSum += $binVal;
				shift(@packet) if (scalar(@packet) > scalar(@headerArray) + $dataLength);
			}
			warn Dumper( \@packet );
		}
	}
	return @packet;
}



my $checkSumByte = sprintf(
	"%X",
	writePacket( $args{txHeader}, $args{txData} )
);
warn
	"device:      $args{dev}\n".
	"baudrate:    $args{baud}\n".
	"TX header:   $args{txHeader}\n".
	"TX data:     $args{txData}\n".
	"TX checksum: 0x$checkSumByte\n".
	"RX header:   $args{rxHeader}\n".
	"RX length:   $args{rxLength}\n".
	"RX data:     (sent to STDOUT)\n";

my @packet = readPacket($args{rxHeader},$args{rxLength});
foreach my $binVal (@packet) {
	printf "%02lx", $binVal; # only this RX data goes to STDOUT...
}
print "\n"; # ...plus a return.
#warn Dumper( \@packet );

