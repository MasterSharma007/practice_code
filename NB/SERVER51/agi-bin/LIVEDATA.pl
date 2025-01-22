#!/usr/bin/perl

use DBI;
use Asterisk::AGI;
my $AGI = new Asterisk::AGI;

my($action,$callid,$phone,$calltype,$cust_chan,$rec) = @ARGV;

my $driver = "mysql";
my $database = "asterisk";
my $dsn = "DBI:$driver:database=$database;host=localhost";
my $userid = "root";
my $password = "Sify\@123";

if(lc($action) eq "add"){
	
	my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
	$sql = "insert into livecall values('','$callid','$phone','$calltype','$cust_chan','$rec',now());";
	$AGI->exec("NoOp",$sql);
	my $sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$sth->finish();


}elsif(lc($action) eq "get"){

	my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
	if ($cust_chan == 0){
	$sql = "select phone,call_type,recname,clid from livecall where cust_chan = '$callid';";
	$AGI->exec("NoOp",$sql);
	#print "$sql";
	my $sth = $dbh->prepare($sql);
	$sth1 = $sth->execute();
	while (my @row = $sth->fetchrow_array()) {
  		 my ($phone,$calltype,$rec,$cust_chan ) = @row;
			$AGI->set_variable("phone",$phone);
			$AGI->set_variable("call_type",$calltype);
			$AGI->set_variable("CALLFILENAME",$rec);
			$AGI->set_variable("call_id",$cust_chan);
		}
	$sth->finish();
	}else{

	
	$sql = "update livecall set clid = $callid where cust_chan = $cust_chan;";
	$AGI->exec("NoOp",$sql);
	my $sth = $dbh->prepare($sql);
	$result = $sth->execute();
	$sth->finish();

	}

}else{

	$AGI->set_variable("STATUS","INVALID");

}



