#!/usr/bin/perl

use DBI;
use Asterisk::AGI;
my $AGI = new Asterisk::AGI;

my($action,$agent,$agentchannel,$custchannel,$callid) = @ARGV;

my $driver = "mysql";
my $database = "asterisk";
my $dsn = "DBI:$driver:database=$database";
my $userid = "root";
my $password = "Sify\@123";

if ($custchannel =~/$agent/){
	
	$AGI->set_variable("CUSTOMERCHANNEL",$agentchannel);
	$AGI->set_variable("AGENTCHANNEL",$custchannel);
	my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
	$sql = "UPDATE conf_nway SET dstchannel = '$agentchannel',channel = '$custchannel' WHERE callid = $callid;";
	my $sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$sth->finish();
	if($action eq "CONF"){
	$sql = "UPDATE livecall SET clid = $callid where cust_chan = '$custchannel';";
	my $sth1 = $dbh->prepare($sql);
	$result1 = $sth1->execute();
	$sth1->finish();
	$sql = "UPDATE livecall SET cust_chan = '$agentchannel' WHERE clid = $callid;";
	my $sth2 = $dbh->prepare($sql);
	$result2 = $sth2->execute();
	$sth2->finish();
	}

}else{
	if($action eq "CONF"){
	my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
	$sql = "UPDATE livecall SET cust_chan = '$custchannel' WHERE clid = $callid;";
	print $sql;
	my $sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$sth->finish();
	}


}



