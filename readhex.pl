#!/usr/bin/perl

use strict;
use warnings;

use Device::SerialPort;
# use Win32::SerialPort;		# Use instead for Windows

STDOUT->autoflush(1);

my $port=Device::SerialPort->new($ARGV[0]);
$port->baudrate($ARGV[1]);
$port->databits(8);
$port->parity("none");
$port->stopbits(1);
 
$port->read_char_time(0);		# don't wait for each character
$port->read_const_time(1);	# 1 millisecond per unfulfilled "read" call
 
while (1) {
	my ($count,$buffer)=$port->read(1024);
	if ($count > 0) {
		foreach my $char (split //, $buffer) {
			my $binval = ord $char;
			if ($binval != 0) {
				printf "%02lx", $binval;
			}
		}
	}
}
