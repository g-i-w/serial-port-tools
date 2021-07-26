#!/usr/bin/perl

use strict;
use warnings;

use Device::SerialPort;
# use Win32::SerialPort;		# Use instead for Windows

my $port=Device::SerialPort->new($ARGV[0]);
$port->baudrate($ARGV[1]);
$port->databits(8);
$port->parity("none");
$port->stopbits(1);
$port->stty_icrnl(1);
 
$port->read_char_time(0);		# don't wait for each character
$port->read_const_time(1);	# 1 millisecond per unfulfilled "read" call

sub writeByte {
		my $byte = ((shift) & 255);
		my $count = $port->write(chr($byte));
		warn "\nERROR: unable to write $byte" if ( $count != 1 );
		return $byte;
}

my $hexData = $ARGV[2];
my $checkSum = 0;

chomp $hexData;
print "writing";
for my $i (0..int(length($hexData)/2)-1) {
	my $hexVal = substr($hexData,($i*2),2);
	print " $hexVal";
	my $binVal = hex($hexVal);
	$checkSum += writeByte($binVal);
}
print "\n";

my $checkSumByte = ($checkSum & 255);
writeByte $checkSumByte;

my $hexCheckSum = sprintf("%X", $checkSumByte);
print "writing checksum: $hexCheckSum\n";
