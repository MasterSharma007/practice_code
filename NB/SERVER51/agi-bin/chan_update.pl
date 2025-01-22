#!/usr/bin/perl

use LWP::UserAgent;
use HTTP::Request::Common qw(POST);

use Asterisk::AGI;
my $AGI = new Asterisk::AGI;
my $ua = LWP::UserAgent->new;
my ($sid,$leadid,$number,$prin,$ctime) = @ARGV;

my $url = "http://crm.nivabupa.com/api/v1/dialer_call/add_call_history";
$AGI->exec("NoOp",$url);

my $json_data = '{"call_id" : "'.$sid.'", "lead" : "'.$leadid.'","mobile_number" : "'.$number.'","call_date_time" : "'.$ctime.'","pri_number" : "'.$prin.'"}';
$AGI->exec("NoOp",$json_data);

my $req = POST($url, 'Content-Type' => 'application/json',Content => $json_data);
my $response = $ua->request($req);

if($response->is_success){
	my $res = $response->decoded_content;
	$AGI->exec("NoOp",$res);
}else{

	my $res = $response->status_line;
	$AGI->exec("NoOp",$res);
}
