use Time::HiRes qw( gettimeofday tv_interval );

use Device::SerialPort;
# use Win32::SerialPort;		# Use instead for Windows

my $port=Device::SerialPort->new($ARGV[0]);
$port->baudrate($ARGV[1]);
$port->databits(8);
$port->parity("none");
$port->stopbits(1);
 
$port->read_char_time(0);		# don't wait for each character
$port->read_const_time(1);	# 1 millisecond per unfulfilled "read" call
 
my $total=0;
my $timestamp = [gettimeofday];
while (1) {
	my ($count,$buffer)=$port->read(1024);
	if ($count > 0) {
		$total+=$count;
		foreach $char (split //, $buffer) {
			$binval = ord $char;
			if ($binval != 0) {
				printf "%02lx", $binval;
				#print "\n";
			}
		}
	}
#	if ($total >= 255) {
#		$timedelta = tv_interval( $timestamp );
#		$timestamp = [gettimeofday];
#		print "256 bytes received in $timedelta\n";
#		$total = 0;
#	}
}
