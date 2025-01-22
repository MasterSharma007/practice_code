#!/usr/bin/perl

use DBI;
use Asterisk::AGI;
use LWP::UserAgent;
use HTTP::Request::Common qw(POST);
use Data::Dumper;
$AGI = new Asterisk::AGI;

 $AGI->set_variable("phone","phone");
 $AGI->set_variable("phone1","phone1");
 $AGI->set_variable("phone2","phone2");
