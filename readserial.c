// based on https://stackoverflow.com/questions/6947413/how-to-open-read-and-write-from-serial-port-in-c

#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <termios.h>
#include <unistd.h>

//#define DISPLAY_HEX_ASCII


// Set interface attributes
int set_interface_attribs(int fd, int speed)
{
    struct termios tty;

    if (tcgetattr(fd, &tty) < 0) {
        printf("Error from tcgetattr: %s\n", strerror(errno));
        return -1;
    }

    cfsetospeed(&tty, (speed_t)speed);
    cfsetispeed(&tty, (speed_t)speed);

    tty.c_cflag |= (CLOCAL | CREAD);    /* ignore modem controls */
    tty.c_cflag &= ~CSIZE;
    tty.c_cflag |= CS8;         /* 8-bit characters */
    tty.c_cflag &= ~PARENB;     /* no parity bit */
    tty.c_cflag &= ~CSTOPB;     /* only need 1 stop bit */
    tty.c_cflag &= ~CRTSCTS;    /* no hardware flowcontrol */

    /* setup for non-canonical mode */
    tty.c_iflag &= ~(IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON);
    tty.c_lflag &= ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN);
    tty.c_oflag &= ~OPOST;

    /* fetch bytes as they become available */
    tty.c_cc[VMIN] = 1;
    tty.c_cc[VTIME] = 1;

    if (tcsetattr(fd, TCSANOW, &tty) != 0) {
        printf("Error from tcsetattr: %s\n", strerror(errno));
        return -1;
    }
    return 0;
}

// Open the interface and read to stdout
int main(int argc, char *argv[])
{
    int fd;
    int wlen;
	int brate;
	char *portname;
	int buflen;

	// Get serial port device name
    if (argc > 1) {
    	portname = argv[1];
    } else {
    	printf("*** Reads serial device to stdout. ***\n");
    	printf("Usage: ./readserial <device> <baud> <buffer_len>\n");
    	printf("defaults: baud=9600, buffer_len=32\n");
    	exit(1);
    }

	// Try to open serial port
    fd = open(portname, O_RDONLY | O_NOCTTY | O_SYNC);
    if (fd < 0) {
        printf("Error opening %s: %s\n", portname, strerror(errno));
        return -1;
    }
    
    // Get baudrate (8 bits, no parity, 1 stop bit)
    // Default: 9600
    brate = B9600;
	if (argc > 2) {
		switch(strtol(argv[2], NULL, 10)) {
			case 4800:   brate=B4800;   break;
			case 9600:   brate=B9600;   break;
			case 19200:  brate=B19200;  break;
			case 38400:  brate=B38400;  break;
			case 57600:  brate=B57600;  break;
			case 115200: brate=B115200; break;
		}
	}
	set_interface_attribs(fd, brate);

	// Get buffer length
	// Default: 32
    if (argc > 3) {
    	buflen = strtol(argv[3], NULL, 10);
    	if (buflen < 2) {
    		buflen = 2;
    	}
    	// printf("Buffer length: %d\n", buflen);
    } else {
    	buflen = 32;
    }

    // Read loop
    while(1) {
        unsigned char buf[buflen];
        int rdlen;

        //rdlen = read(fd, buf, sizeof(buf) - 1);
        rdlen = read(fd, buf, sizeof(buf));
        if (rdlen > 0) {
#ifdef DISPLAY_HEX_ASCII
            unsigned char   *p;
            printf("Read %d:", rdlen);
            for (p = buf; rdlen-- > 0; p++)
                printf(" 0x%x", *p);
            printf("\n");
#else
	    	//fwrite(buf, 1, sizeof(buf), stdout);
	    	fwrite(buf, 1, rdlen, stdout);
#endif
	    	fflush( stdout );
        } else if (rdlen < 0) {
            printf("Error from read: %d: %s\n", rdlen, strerror(errno));
        } else {  /* rdlen == 0 */
            printf("Timeout from read\n");
        }
    }
}
