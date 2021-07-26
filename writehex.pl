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

sub writeHexByte {
		my $hexValue = shift;
		my $count = $port->write(chr(hex($hexValue)));
		warn "\nERROR: unable to write $hexValue" if ( $count != 1 );
}
 
while (1) {
	my $hexData = <STDIN>;
	chomp $hexData;
	print "writing";
	for my $i (0..int(length($hexData)/2)-1) {
		my $hexVal = substr($hexData,($i*2),2);
		print " $hexVal";
		#my $binVal = hex($hexVal);
		#my $count = $port->write(chr($binVal));
		#warn "\nERROR: unable to write $binVal" if ( $count != 1 );
		writeHexByte $hexVal;
	}
	print "\n";
}
