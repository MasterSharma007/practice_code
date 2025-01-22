#!/usr/bin/perl

use strict;
use warnings;
use Net::Telnet;
use Time::HiRes qw(time);

# AMI Connection Settings
my $host = '127.0.0.1';  # Change to your Asterisk server IP
my $port = 5038;         # Default AMI port
my $username = 'max_mbhi'; # AMI username
my $password = 'mbhi_max'; # AMI password

# Connect to AMI
my $telnet = Net::Telnet->new(Timeout => 10, Port => $port);
$telnet->open($host);
$telnet->waitfor('/Asterisk Call Manager/');
$telnet->print("Action: Login\nUsername: $username\nSecret: $password\n\n");

# Fetch active channels
$telnet->print("Action: Command\nCommand: core show channels\n\n");
my @response = $telnet->waitfor('/Asterisk Call Manager/');

# Calculate bandwidth usage
my $bandwidth_usage = 0;
my $codec_map = {
    'g722' => 16,    # G.722 (16 kbps)
    'g711' => 64,    # G.711 (64 kbps)
    'g729' => 8,     # G.729 (8 kbps)
    'opus' => 12,    # Opus (12 kbps, average)
};

foreach my $line (@response) {
    if ($line =~ /Channel:.*?\[(.*?)\]/) {
        my $channel = $1;
        if ($channel =~ /^(.*?)(\/\d+)/) {
            my $endpoint = $1;

            # Assume the codec used is at the end of the channel name
            if ($endpoint =~ /(\w+)$/) {
                my $codec = lc($1);
                if (exists $codec_map->{$codec}) {
                    $bandwidth_usage += $codec_map->{$codec};
                }
            }
        }
    }
}

# Display bandwidth usage
print "Estimated Bandwidth Usage: ${bandwidth_usage} kbps\n";

# Logout from AMI
$telnet->print("Action: Logoff\n\n");
$telnet->close();


