#!/usr/bin/perl

use DBI;
use Asterisk::AGI;
my $AGI = new Asterisk::AGI;

my $filename = "/var/log/agent_api.log";
open(FH, '>>', $filename) or die $!;

my ($res,$count) = @ARGV;
print FH "Recieve $res,$count\n";
$res =~ s/{//;
$res =~ s/}//;
@allagents = split(":",$res);
$len = scalar @allagents;
@agents = split(",",$allagents[1]);
$agent = $agents[$count];
if ($len-1 > $count){
	$count = $count+1;
}
$AGI->set_variable("agent_code",$agent);
$AGI->set_variable("pricount",$count);
print FH "Return $agent, $count\n";


