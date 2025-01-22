#!/usr/bin/perl

use LWP::UserAgent;


$ua = LWP::UserAgent->new;


my $url = "";


my $resp = $ua->get($url);

if($resp->is_success){
	my $cc 0;

}else{

	
}
