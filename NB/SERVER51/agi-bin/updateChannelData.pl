#!/usr/bin/perl

use DBI;
use Asterisk::AGI;

my $AGI = new Asterisk::AGI;


my($action,$callid,$extrachannel,$campaign,$leadid,$tagentid) = @ARGV;

my $driver = "mysql"; 
my $database = "asterisk";
my $dsn = "DBI:$driver:database=$database";
my $userid = "root";
my $password = "Sify\@123";
my $filename = "/tmp/ast.log";
my $dbh = DBI->connect($dsn, $userid, $password ) or die $DBI::errstr;
open(FH, '>', $filename) or die $!;
$sql = "UPDATE conf_nway SET extrachannel = '$extrachannel' WHERE callid = $callid;";
print FH $sql;
my $sth = $dbh->prepare($sql);

$result = $sth->execute();
print FH $result;
$sth->finish();
