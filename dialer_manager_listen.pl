#!/usr/bin/perl

require("/usr/lib/perl5/vendor_perl/5.8.5/zentrix_configuration.pl");
require("/usr/lib/perl5/vendor_perl/5.8.5/getNewMonitorFileName.pl");

#<TVT> Ensure that all live tables that listener uses have ENGINE=HEAP i.e. inmemory tables.
# agent_live, customer_live, queue_live, crm_live, crm_hangup_live, Rstats

#listener_status, dialer_status needs a review
#call_dial_status needs to be MEMORY

#use strict;
use warnings;

use threads;
use Thread::Semaphore;
use threads::shared;
use IPC::SysV qw(IPC_CREAT IPC_RMID);    #required to use shared memory
use Time::HiRes ('gettimeofday','usleep','sleep');  # necessary to have perl sleep command of less than one second
use POSIX;
use lib "/Czentrix/lib/czentrix";
use lib "/Czentrix/lib/perl";
use Time::ParseDate;
use Time::gmtime;
use Time::Local;
use Net::Telnet ();
use DBI;
no warnings 'deprecated';

my $DB:shared;
my $DB_semaphore= new Thread::Semaphore;
$DB=1;
my $scr_flag=1;

my $filename ="/Czentrix/apps/customer_removal.pl";
if (-e $filename) 
{
   require("/Czentrix/apps/customer_removal.pl");
}

#get signals when the file is killed at the time of system off.
$SIG{'INT'} = 'CLEANUP';
$SIG{'HUP'} = 'CLEANUP';
my $sh_mem_semaphore = new Thread::Semaphore;
my $sh_mem_id : shared;
my $size=100;  #bytes
my $key=1250;  #dialer program will use the same key to read the contents of shared memory

$sh_mem_id = shmget($key,$size,IPC_CREAT | 0666) or error_handler("Unable to create shared memory",__LINE__,"");
my %queueHash : shared=();

my $stateHash_semaphore = new Thread::Semaphore;
my %stateHash : shared=();

my $sendTn_semaphore = new Thread::Semaphore;
my %sendTnHash : shared=();

my $thread_semaphore= new Thread::Semaphore;
my %threadStatusHash : shared=();

my $agentHash_semaphore = new Thread::Semaphore;
my %agentHash : shared=();
my %agentDialTypeHash : shared=();

my $campaignHash_semaphore = new Thread::Semaphore;
my %campaignHash : shared=();

my $campaignNameHash_semaphore = new Thread::Semaphore;
my %campaignNameHash : shared=();

my $campaign_conf_WrapHash_semaphore = new Thread::Semaphore;
my %campaign_conf_WrapHash : shared=();

my $fileFormatHash_semaphore = new Thread::Semaphore;
my %fileFormatHash : shared=();

my $campaignWrapHash_semaphore = new Thread::Semaphore;
my %campaignWrapHash : shared=();

my $campaignSkillHash_semaphore = new Thread::Semaphore;
my %campaignSkillHash : shared=();

my $campaignScreenlHash_semaphore = new Thread::Semaphore;
my %campaignScreenHash : shared=();

my $campaignblendedlookup_semaphore = new Thread::Semaphore;
my %campaignblendedlookup : shared=();

my $providernameHash_semaphore = new Thread::Semaphore;
my %providernameHash : shared=();

my $sip_providernameHash_semaphore = new Thread::Semaphore;
my %sip_providernameHash : shared=();

my $sip_id_providernameHash_semaphore = new Thread::Semaphore;
my %sip_id_providernameHash : shared=();

my $campaignCsatHash_semaphore = new Thread::Semaphore;
my %campaignCsatHash : shared=();

my $ivrCsatHash_semaphore = new Thread::Semaphore;
my %ivrCsatHash : shared=();

my $campaignabandon_action_semaphore = new Thread::Semaphore;
my %campaignabandon_action : shared=();

my $campaigntype_semaphore = new Thread::Semaphore;
my %campaigntype : shared=();

my $campaign_conference_semaphore = new Thread::Semaphore;
my %campaign_conference : shared=();

my $campaignmax_semaphore = new Thread::Semaphore;
my %campaignmax : shared=();

my $MonitorFileFormatManual_semaphore = new Thread::Semaphore;
my %MonitorFileFormatManual : shared=();

my $MonitorFileFormatLead_semaphore = new Thread::Semaphore;
my %MonitorFileFormatLead : shared=();

my $flags_semaphore = new Thread::Semaphore;
my $file_global_flag : shared = 1;

my $ivrinfo_semaphore = new Thread::Semaphore;
my %ivrinfo : shared=();

my $new_monitor_flagHash_semaphore = new Thread::Semaphore;
my %new_monitor_flagHash : shared=();

my $logoutagent_semaphore = new Thread::Semaphore;
my %logoutagent : shared=();

my $agentcount_semaphore = new Thread::Semaphore;
my %agentcount : shared=();

my $camp_agentcount_semaphore = new Thread::Semaphore;
my %camp_agentcount : shared=();

my $pricalleridHash_semaphore = new Thread::Semaphore;
my %pricalleridHash : shared=();

my $customerlookup_semaphore = new Thread::Semaphore;
my %customerlookup : shared=();

my $sticky_campaign_semaphore = new Thread::Semaphore;
my %sticky_campaignhash : shared=();

my $departmenthash_semaphore = new Thread::Semaphore;
my %departmenthash : shared=();

my $ReportingFormatManual_semaphore = new Thread::Semaphore;
my %ReportingFormatManual : shared=();

my $ReportingFormatLead_semaphore = new Thread::Semaphore;
my %ReportingFormatLead : shared=();

my $cust_reporting_flagHash_semaphore = new Thread::Semaphore;
my %cust_reporting_flagHash : shared=();


my $crm_license = 0;
my $ivr_license = 0;
my $ipbx_license = 0;
my $max_agents=0;
my $dialing_date = 0;
my $current_date = 0;

#variables for infinite wrap up work
my %agent_wrapup : shared=();
my $wrapup_semaphore = new Thread::Semaphore;

my @final_wrap_array=([],[]);           #stores the detailed information about agent calls,avg time,etc
my $PREDICTION_CALLS=25;				#start Prediction after 25 calls
my $AVG_BLOCK=5;                        #no of calls in a block to calculate average
#my @weight_array=(.4,.25,.20,.10,.05); #this will be used to calculate the weighted average
my @weight_array=(.8,.5,.4,.2,.1);      #this will be used to calculate the weighted average
my $weight_sum=2;
my @call_duration_array1 : shared=();   #will store the total calls and total wrapup time for different call durations.
my @call_duration_array2 : shared=();   #will store the total calls and total wrapup time for different call durations.
my @call_duration_array3 : shared=();   #will store the total calls and total wrapup time for different call durations.

my @update_avg_block1 : shared=();      #will be used to check whether block average needs to be updated in final_wrap_array
my @update_avg_block2 : shared=();
my @update_avg_block3 : shared=();

my @state_changed : shared=();
my @setmefree_hit : shared=();

my @predict_state_after1 : shared=();
my @predict_state_after2 : shared=();
my @predict_state_after3 : shared=();

my $FIVE_MINUTES=300;
my $TEN_MINUTES=600;
my $INFINITE_WRAPUP_TIME="0";
my $WATERMARK_FOR_PREDICTION=15;
my $node_id = "";
my $cview_update_enabled = '0';

my %dispositionValue: shared=();
my %listRules: shared=();
my %listRules_Type: shared=();
my %phoneMaxValue: shared=();
my %phoneRetryTime: shared=();
my %phoneRetryRule: shared=();
my %phoneRetryValue: shared=();
my %simpleRuleValue: shared=();
my %basic_rule_disposition_time_value_hash: shared=();
my %basic_rule_disposition_action_hash: shared=();
my %strictCalling_dispositionAction: shared=();
my %strictCalling_dispositionValue: shared=();
my $disposition_semaphore = new Thread::Semaphore;

setpriority(0,0,-20);

########fail safe is a function now
fail_safe();

##################################PARSER() FUNCTION START################################################
sub parser()
{
	eval {
		my @params= @_;
		my $thread_type=$params[0];   #it will be a numeric value
		my $thread_group=$params[1];
		my $dbh;
		my $tn;
		my $partial_input_buf;
		my $read_input_buf;
		my $input_buf_length;
		my $input_buf;
		my $partial;
		my $manager_string;
		my $cmd;
		my $time;
		my $database_reconnect =0;
		my $val_eof=0;
#open database connection
		$dbh=DBI->connect("dbi:mysql:$db:$server",$username,$password,{mysql_auto_reconnect => 1}) or die (exit);
#open telnet client
		my $login_group = 2**($thread_group+6);
		$tn = new Net::Telnet(Timeout=>10,Prompt=>'/%/',Host=>"localhost",Port=>"5038",Errmode=>"die");
		$tn->waitfor('/0\n$/');
		$tn->print("Action: Login\nUsername: $telnet_username\nSecret: $telnet_secret\nevents: $login_group\n");
		$tn->waitfor('/Authentication accepted/');
		$tn->buffer_empty;
		$tn->max_buffer_length( 50*1024*1024 );
		$time=time;

		while(1)
		{
			$time=time;
			$thread_semaphore->down;
			$threadStatusHash{$thread_type}=$time;
			$thread_semaphore->up;

			if(($thread_type == 12) ||  ($thread_type == 13) || ($thread_type == 8) || ($thread_type == 9) || ($thread_type == 10) || ($thread_type == 3) || ($thread_type == 5) || ($thread_type == 6))
			{
				usleep(1000);
			}
			elsif(($thread_type == 1) || ($thread_type == 2) )
			{
				usleep(3000);
			}
			elsif(($thread_type == 4) || ($thread_type == 11) || ($thread_type == 7))
			{
				usleep(10000);
			}
			else   #only thread no 6 comes in this leg
			{
				usleep(1000000);
			}
			if($database_reconnect > 10000)
			{
				$database_reconnect =0;
				query_execute("select 1",$dbh,1,__LINE__);

			}
			$database_reconnect++;
			$read_input_buf="";
			$read_input_buf = $tn->get(Errmode=>'return',Timeout=>10);
			$val_eof=$tn->eof;
			if(defined($val_eof) && $val_eof && $val_eof == '1')
			{
				error_handler("thread type $thread_type and thread group $thread_group has died",__LINE__,"");
				$threadStatusHash{$thread_type}=0;
				return;
			}
			if (defined ($read_input_buf))
			{
				$input_buf_length = length($read_input_buf);
				if(($read_input_buf !~ /\n\n/) or ($input_buf_length < 10))
				{
					$input_buf = "$input_buf$read_input_buf";
				}
				else
				{
					$partial=0;
					$partial_input_buf='';
					if ($read_input_buf !~ /\n\n$/)
					{
						$partial_input_buf = $read_input_buf;
						$partial_input_buf =~ s/\n/-----/gi;
						$partial_input_buf =~ s/\*/\\\*/gi;
						$partial_input_buf =~ s/.*----------//gi;
						$partial_input_buf =~ s/-----/\n/gi;
						$read_input_buf =~ s/$partial_input_buf$//gi;
						$partial++;
					}
					$input_buf = "$input_buf$read_input_buf";
					$manager_string = $input_buf;
					$input_buf = "$partial_input_buf";
#call the main parse function to update the database
#main_parse function takes three args : 1)database handler 2)thread type 3)the read buffer
					main_parse($dbh,$thread_type,$manager_string);
				}
			}
		}
		$dbh->disconnect();
		undef($dbh);
		$tn->cmd(String => "Action: Logoff\n\n", Prompt => "/.*/", Errmode => Return, Timeout =>1);
		$tn->close;
		undef($tn);
	};
	if ($@)
	{
		error_handler("Parser Crashed",__LINE__,$@);
		exit;
	}
}
##################################PARSER() FUNCTION END################################################


##################################MAIN PARSE() FUNCTION START################################################
sub main_parse
{
	eval {
		my $ILcount = 0;
		my @params;
		my $input_buf;
		my $dbh;
		my $thread_type;
		my @command_line=();
		my $agent_ext;
		my $agent_id;
		my $temp;
		my $query;
		my $staticIP;
		my $dialerType;
		my $wrapupTime;
		my $campaign_id;
		my $session_id;
		my $state;
		my $zap_channel;
		my $time;
		my $timestamp;
		my $res;
		my $retval;
		my $custphno;
		my $monitor_file_name;
		my $returnvar;
		my @variables=();
		my $lead_id;
		my $campaign_name;
		my $zap_flag;
		my $peer_id;
		my $dialedno;
		my $monitor_file_id;
		my @input_lines;
		my $strict;
		my $channel;
		my $customer_name="";
		my $list_id;
		my $unpause_agent;
		my $agent_state;
		my $interval;
		my $message;
		my $hangup_cause;
		my $mail_box;
		my $duration;
		my $vmail_orig_time;
		my $file_name;
		my $caller_id;
		my $report_query;
		my $unit_cost=0;
		my $zap_type;
		my $ivrs_path;
		my $amd_disp;
		my $q_enter_time=0;
		my $q_leave_time=0;
		my $hold_time=0;
		my $link_date_time;
		my $list_name;
		my $link_time;
		my $agent_name;
		my $alarm;
		my $ip;
		my $shared_key;
		my $value;
		my $remarks="";
		my $cust_disposition="";
		my $call_status="";
		my $campaign_type="";
		my $avg_wrap_time=0;
		my $total_wrap_time=0;
		my $total_calls=0;
		my $disconnect_time=0;
		my $state_change_time=0;
		my $length=0;
		my $i;
		my $barger_id;
		my $barger_type;
		my $agent_exten;
		my $queue_join_time;
		my $tm;
		my $preview_call=0;
		my $transfer_from = "";
		my $transfer_status ="";
		my $transfer_field = "";
		my $skill_id=0;
		my $skill_name="";
		my $did_num="";
		my $dialer_var="";
		my $report_id='';
		my $cust_remove_flag=0;

		if(defined($cust_removal_flag) && $cust_removal_flag){
			   $cust_remove_flag=1;
		}

		@params = @_;
		$dbh = $params[0];
		$thread_type = $params[1];
		$input_buf = $params[2];
		@input_lines = split(/\n\n/, $input_buf);


#initialize the time only once and will be used in every block
		$time=get_time_now();
		$timestamp=time;

		my $table_name=substr($time,0,7);
		$table_name=~s/-/_/g;
   
		if($DB)
		{
			open OUT, ">>/tmp/telnetoutput.txt";
			print OUT "\n----inside main parse----------$time---\n";
			print OUT $input_buf;
			print OUT "\n-----------Buffer-Ends-----------------\n";
			close OUT;
		}
		foreach(@input_lines)
		{
			@command_line=split(/\n/, $input_lines[$ILcount]);
##############PEER STATUS BLOCK START######################################
			if(($thread_type == 4) && ($command_line[0] =~ /Event: PeerStatus/))
			{
				my $possible_clash=0;
				my $ip='';
				my $unregister_reason='';
				$query='';
				if(($command_line[2] =~ /Peer: SIP/)) {
					my $agent_exten=substr($command_line[2],index($command_line[2],"/")+1);

####Registered Packet Information############################################
					if(($command_line[3] eq "PeerStatus: Registered")) {
						$possible_clash=substr($command_line[5],index($command_line[5],":")+1);
						$ip=substr($command_line[4],index($command_line[4],":")+2);
						$query="replace into Rstats (agent_exten,ip,possible_clash,unregister_reason) values('$agent_exten','$ip','$possible_clash','')";
					}
####Unregistered Packet Information##########################################
					elsif(($command_line[3] eq "PeerStatus: Unregistered")) {
						$possible_clash=substr($command_line[5],index($command_line[5],":")+1);
						$unregister_reason=substr($command_line[4],index($command_line[4],":")+1);
						$query="update Rstats set ip='', possible_clash='$possible_clash',unregister_reason='$unregister_reason'  where agent_exten='$agent_exten'";
					}
					elsif(($command_line[3] eq "PeerStatus: Unreachable")) {
						$unregister_reason="Unreachable";
						$query="update Rstats set ip='', possible_clash='$possible_clash',unregister_reason='$unregister_reason'  where agent_exten='$agent_exten'";
					}
					if(($query !~ /^$/ && $query !~ /^[\s]+$/)) {
						query_execute($query,$dbh,0,__LINE__);
					}
				}
			}
##############PEER STATUS BLOCK END######################################
#health field is added in zap table which will tell the health of channel.
#it is a boolean field, 0 means channel healthy and 1 means it is not healthy
##############ALARM BLOCK START######################################
			elsif(($thread_type == 4) && ($command_line[0] =~ /Event: Alarm/))
			{
				my $alarm;
				my $end_channel;
				my $health=0;
				my $channel_range;
				my $event_time;
				my $status;
				my $provider_name;
				my $virtual_group_id;
				my $span_no;
				my $Caller_id;
				my $setstrict_cid;
				my $entrytime=time;


				$alarm = substr($command_line[2],index($command_line[2],":") + 2);
				$channel = (31 * ($alarm -1)) + 1;
				$end_channel=$channel+30;
				$channel_range = $channel."-".$end_channel;
#health is bad
				if($command_line[0] eq "Event: Alarm") {
					$health=1;
					$status='DOWN';
				}
				elsif($command_line[0] eq "Event: AlarmClear") {
#health is good
					$health=0;
					$status='UP';
				}
				$query="update zap set health='$health' where cast((substr(zap_id,5)) as unsigned) between $channel and $end_channel";
				query_execute($query,$dbh,0,__LINE__);

				$query = "select provider_name,virtual_group_id,span_no,Caller_id,setstrict_cid from zap where groupId=$alarm";
				$retval=query_execute($query,$dbh,1,__LINE__);
				$provider_name= ((defined(@$retval[0]))?@$retval[0]:"");
				$virtual_group_id= ((defined(@$retval[1]))?@$retval[1]:"");
				$span_no= ((defined(@$retval[2]))?@$retval[2]:"");
				$Caller_id= ((defined(@$retval[3]))?@$retval[3]:0);
				$setstrict_cid = ((defined(@$retval[4]))?@$retval[4]:0);


				$report_query="insert into line_report (node_id,status,entrytime,call_start_date_time,provider_name,channel,virtual_group_id,span_no,Caller_id,setstrict_cid) values ('$node_id','$status',unix_timestamp(),now(),'$provider_name','$channel_range','$virtual_group_id','$alarm','$Caller_id','setstrict_cid')";
				query_execute($report_query,$dbh,0,__LINE__);

			}


##############ALARM BLOCK END########################################

##############NEWCHANNEL BLOCK START######################################
			elsif(($thread_type == 5) && ($command_line[0] =~ /Event: Newchannel/) && (($command_line[2] =~ /Zap/i) || ($command_line[2] =~ /SIP/i)) && (($command_line[3] =~ /State: Ring/) || ($command_line[3] =~ /State: Rsrvd/)))
			{
				$channel=substr($command_line[2],index($command_line[2],":") + 2);
				$zap_channel=substr($channel,0,index($channel,"-"));
				$session_id=substr($command_line[6],index($command_line[6],":") + 2);
				my $acd_context=substr($command_line[9],index($command_line[9],":") + 2);
				my $sip_gateway_id="";
				my $sth="";

				if($channel =~ /Zap/i)
				{
#XXX if agent is logging on zap and the channel is set as NOTINUSE but agent has logged in at zap 3 what to do
					$query="update zap set status='BUSY',session_id='$session_id',flow_state='0' where zap_id='$zap_channel'";
					query_execute($query,$dbh,0,__LINE__);


					$query="update zap_live set session_id='$session_id',entry_time=unix_timestamp(),live_channel='$channel' where zap_id='$zap_channel'";
					query_execute($query,$dbh,0,__LINE__);

				}

				if($channel =~ /sip/i && (defined($acd_context) && ($acd_context !~ /^$/ && $acd_context !~ /^[\s]+$/)))
				{
					$query="select campaign_id from campaign where campaign_name='$acd_context'";
					$retval=query_execute($query,$dbh,1,__LINE__);
					if(defined(@$retval[0]))
					{
						my @temp_sip=();
						$channel=substr($channel,index($channel,"/")+1);
						$channel=substr($channel,0,index($channel,"-"));
						$query="select sip_gateway.sip_gateway_id from sip_gateway,sip_channel_group where sip_gateway.sip_gateway_id=sip_channel_group.sip_gateway_id and sip_channel_group.campaign_id='$campaign_id' and (sip_gateway_name='$channel' or ipaddress='$channel')";
						$sth = $dbh->prepare($query);
						$sth->execute();

						while (@temp_sip = $sth->fetchrow_array() ) {
							$sip_gateway_id=$sip_gateway_id.",".$temp_sip[0];
						}
						$sip_gateway_id =~ s/^,//g;
						$sth->finish();

						if(defined($sip_gateway_id) && ($sip_gateway_id !~ /^$/ && $sip_gateway_id !~ /^[\s]+$/)) {
							$query="update sip set status='BUSY',session_id='$session_id',flow_state='1' where campaign_id='$campaign_id' and status='FREE' and sip_gateway_id in($sip_gateway_id) limit 1";
							query_execute($query,$dbh,0,__LINE__);
						}
						else {
							$query="update sip set status='BUSY',session_id='$session_id',flow_state='1' where campaign_id='$campaign_id' and status='FREE' limit 1";
							query_execute($query,$dbh,0,__LINE__);
						}
					}
				}
			}
##############NEWCHANNEL BLOCK END######################################

##############NEWSTATE BLOCK START######################################
			elsif(($thread_type == 12) && ($command_line[0] =~ /Event: Newstate/) && ($command_line[2] =~ /Zap/i) && (($command_line[3] =~ /State: Ring/) || ($command_line[3] =~ /State: Rsrvd/)))
			{
				$channel=substr($command_line[2],index($command_line[2],":") + 2);
				$zap_channel=substr($channel,0,index($channel,"-"));
				$session_id=substr($command_line[6],index($command_line[6],":") + 2);

				$query="update zap set status='BUSY',session_id='$session_id',flow_state='0' where zap_id='$zap_channel'";
				query_execute($query,$dbh,0,__LINE__);


				$query="update zap_live set session_id='$session_id',entry_time=unix_timestamp(),live_channel='$channel' where zap_id='$zap_channel'";
				query_execute($query,$dbh,0,__LINE__);

			}
##############NEWSTATE BLOCK END######################################

##############NewPreviewChannel BLOCK START######################################
			elsif(($thread_type == 8) && defined($command_line[3]) && ($command_line[0] =~ /Event: NewPreviewChannel/))
			{
				my $sip_gateway_id="";
				my @temp_sip=();
				my @variables=();
				my $sth="";
				$channel=substr($command_line[2],index($command_line[2],":") + 2);
				$session_id=substr($command_line[6],index($command_line[6],":") + 2);
				$returnvar = substr($command_line[8],index($command_line[8],":") + 1);

#XXX if preview agent is making a call update it in call progress table for it to be updated.
				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					my $caller_id=$variables[0];
					my $agent_id=$variables[1];
					my $lead_id=(defined($variables[2])?$variables[2]:"");
					$query="replace into callProgress (agent_id, phoneNum,lastDial,failureCause,session_id,channel,lead_id) values ('$agent_id','$caller_id',now(),'','$session_id','$channel','$lead_id')";
					query_execute($query,$dbh,0,__LINE__);

					if(($channel =~ /SIP/i))
					{
						my $temp;
						$query="select campaign_id from agent_live where agent_id='$agent_id'";
						$temp=query_execute($query,$dbh,1,__LINE__);
						if(defined(@$temp[0]))
						{
							$channel=substr($channel,index($channel,"/")+1);
							$channel=substr($channel,0,index($channel,"-"));
							$campaign_id=@$temp[0];

							$query="select sip_gateway.sip_gateway_id from sip_gateway,sip_channel_group where sip_gateway.sip_gateway_id=sip_channel_group.sip_gateway_id and sip_channel_group.campaign_id='$campaign_id' and (sip_gateway_name='$channel' or ipaddress='$channel')";
							$sth = $dbh->prepare($query);
							$sth->execute();
							while ( @temp_sip = $sth->fetchrow_array() ) {
								$sip_gateway_id=$sip_gateway_id.",".$temp_sip[0];
							}
							$sip_gateway_id =~ s/^,//g;
							$sth->finish();

							if(defined($sip_gateway_id) && ($sip_gateway_id !~ /^$/ && $sip_gateway_id !~ /^[\s]+$/)) {
								$query="update sip set status='BUSY',session_id='$session_id',flow_state='1' where campaign_id='$campaign_id' and status='FREE' and sip_gateway_id in($sip_gateway_id) limit 1";
								query_execute($query,$dbh,0,__LINE__);
							}
							else {
								$query="update sip set status='BUSY',session_id='$session_id',flow_state='1' where campaign_id='$campaign_id' and status='FREE' limit 1";
								query_execute($query,$dbh,0,__LINE__);
							}
						}
					}
				}
			}
##############NewPreviewChannel BLOCK END######################################


##############NEWEXTEN BLOCK START######################################
			elsif(($thread_type == 3) && ($command_line[0] =~ /Event: Newexten/) && (($command_line[3] =~ /Context: Context_IVR/) || ($command_line[6] =~ /Application: Autoivr/)))
			{
				my @variables=();
				$channel=substr($command_line[2],index($command_line[2],":") + 2);
				$session_id=substr($command_line[8],index($command_line[8],":") + 2);
				$returnvar = substr($command_line[9],index($command_line[9],":") + 1);
				my $temp=substr($channel,index($channel,"/")+1);

				if($ivr_license && (($command_line[3] =~ /Context: Context_IVR/) || ($command_line[6] =~ /Application: Autoivr/)))
				{
					if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
					{
						$returnvar=~ s/\s+//g;
						@variables=split(/,/,$returnvar);
						my $caller_id=$variables[0];
						my $campaign_id=$variables[2];
						if (not exists $campaignHash{$campaign_id}) {
							populateCampaign($campaign_id,$dbh,'0');
						}
						$campaign_name = $campaignHash{$campaign_id};
						$query="insert into ivr_call_dial_status (cust_ph_no,session_id,link_date_time,CampaignTransfer,zap_channel) values ('$caller_id','$session_id',now(),'$campaign_name','$channel')";
					}
					else
					{
						$caller_id=substr($command_line[10],index($command_line[10],":") + 2);
						$query="insert into ivr_call_dial_status (cust_ph_no,session_id,link_date_time,zap_channel) values ('$caller_id','$session_id',now(),'$channel')";
					}
					query_execute($query,$dbh,0,__LINE__);
					init_stateHash($session_id);
					$stateHash_semaphore->down;
					$stateHash{$session_id} = $stateHash{$session_id} | (1<<0);
					$stateHash_semaphore->up;
				}
			}
##############NEWEXTEN BLOCK END######################################

##############BARGESTART BLOCK START######################################
			elsif(($thread_type == 4) && ($command_line[0] =~ /Event: BargeStart/i))
			{
				$channel=substr($command_line[2],index($command_line[2],":") + 2);
				$session_id=substr($command_line[3],index($command_line[3],":") + 2);
				my $agent_exten=substr($command_line[4],index($command_line[4],":") + 2);

				my $temp=substr($channel,index($channel,"/")+1);
				my $agent_id='';
				my $barger_type='';
				my $barger_id=substr($temp,0,index($temp,"-"));
				if($agent_exten =~ /Agent/i) {
					$agent_id=substr($agent_exten,index($agent_exten,"/")+1);
					$barger_type = "Agent";
				}
				else {
					$agent_id=substr($agent_exten,index($agent_exten,"/")+1);
					$agent_id=substr($agent_id,0,index($agent_id,"-"));
					$barger_type = "Channel";
				}

				$query="replace into bargein(barger_id,agent_id,barger_type,session_id,barger_channel)values('$barger_id','$agent_id','$barger_type','$session_id','$channel')";
				query_execute($query,$dbh,0,__LINE__);
			}
##############BARGESTART BLOCK END######################################

##############BARGESTOP BLOCK START######################################
			elsif(($thread_type == 4) && ($command_line[0] =~ /Event: BargeStop/i))
			{
				$session_id=substr($command_line[3],index($command_line[3],":") + 2);
				$query="delete from bargein where session_id=$session_id";
				query_execute($query,$dbh,0,__LINE__);
			}
##############BARGESTOP BLOCK END######################################

##############AGENT LOGIN BLOCK START########################################
			elsif(($thread_type == 2) && (($command_line[0] =~ /Event: Agentlogin/)||($command_line[0] =~ /Event: Agentcallbacklogin/)))
			{
				my $agent_in_conf = "";
				my $agent_in_live=0;
				$agent_id=substr($command_line[2],index($command_line[2],":") + 2);
				$channel=substr($command_line[3],index($command_line[3],":") + 2);
				my $temp="";
				my $agent_session_id=substr($command_line[5],index($command_line[5],":") + 2);
				$agent_in_conf = substr($command_line[6],index($command_line[6],":") + 2);

				if(defined($agent_in_conf) && ($agent_in_conf !~ /^$/ && $agent_in_conf !~ /^[\s]+$/)  && $agent_in_conf != 0)
				{
					$query="update agent_live set agent_in_conf = '0' where agent_session_id = $agent_session_id and agent_id = '$agent_id'";
					query_execute($query,$dbh,0,__LINE__);

					$query = "select campaign_id from agent where agent_id = '$agent_id'";
					my $result=query_execute($query,$dbh,1,__LINE__);
					my $campaign_id = @$result[0];
					if (not exists $campaignHash{$campaign_id}) {
						populateCampaign($campaign_id,$dbh,'1');
					}
					my $campaign_name = $campaignHash{$campaign_id};

					$shared_key = $agent_id."##".$campaign_name;

					$query = "select 1 from agent_live where agent_id='$agent_id'";
					my $al_result=query_execute($query,$dbh,1,__LINE__);
					$agent_in_live = ((defined(@$al_result[0]) && (@$al_result[0] !~ /^$/ && @$al_result[0] !~ /^[\s]+$/))?@$al_result[0]:0);
                          
					if($agent_in_live == '1')
					{ 
						$query = "select dialer_type from agent_live where agent_id='$agent_id'";
					    my $in_conf_result=query_execute($query,$dbh,1,__LINE__);
					    my $in_conf_agent_dialer_type = @$in_conf_result[0];

						my $inbound_calls_in_preview='0';
						if($in_conf_agent_dialer_type =~ /preview/i){
						  $query = "select inbound_calls_in_preview from campaign where campaign_id='$campaign_id'";
						  my $inres=query_execute($query,$dbh,1,__LINE__);
						  $inbound_calls_in_preview = @$inres[0];
						}

						if(($in_conf_agent_dialer_type !~ /preview/i) || ($in_conf_agent_dialer_type =~ /preview/i && $inbound_calls_in_preview == 1))
						{
							$sendTn_semaphore->down;
							$sendTnHash{$shared_key} = "unpause1";
							$sendTn_semaphore->up;
						}
					}
					else
					{
                        if($command_line[0] =~ /Event: Agentcallbacklogin/)
					    {
						  $temp=substr($channel,0,(index($channel,"@")));
						  $agent_ext=$temp;
					    }
					    else
					    {
						  $temp=substr($channel,index($channel,"/")+1);
						  $agent_ext=substr($temp,0,index($temp,"-"));
					    }
					    AgentLoginBlock($agent_id,$agent_ext,$agent_session_id,$dbh,"main","","",$table_name,$channel,"1");
					}
				}
				else
				{
					if($command_line[0] =~ /Event: Agentcallbacklogin/)
					{
						$temp=substr($channel,0,(index($channel,"@")));
						$agent_ext=$temp;
					}
					else
					{
						$temp=substr($channel,index($channel,"/")+1);
						$agent_ext=substr($temp,0,index($temp,"-"));
					}
					AgentLoginBlock($agent_id,$agent_ext,$agent_session_id,$dbh,"main","","",$table_name,$channel,"0");
				}
			}
##############AGENT LOGIN BLOCK END########################################

###########################TRANSFER BLOCK START ############################
			elsif(($thread_type == 10) && ($command_line[0] =~ /Event: Transfer/))
			{
				my $customer_name='';
				my $campaign_name = substr($command_line[3],index($command_line[3],":") + 2);
				my $session_id = substr($command_line[4],index($command_line[4],":") + 2);
				my $agent_id = substr($command_line[5],index($command_line[5],":") + 2);
				my $returnvar = substr($command_line[6],index($command_line[6],":") + 1);
				my $call_type= substr($command_line[7],index($command_line[7],":") + 2);
				my $reportupdate=substr($command_line[8],index($command_line[8],":") + 2);

				$call_type = ($call_type==0?"INBOUND":"OUTBOUND");

				$transfer_status ="";
				if($campaign_name =~ /FeedBack/)
				{
					$transfer_status="FeedBack";
				}
				else{
					if(!defined ($agent_id) || ($agent_id =~ /^$/ || $agent_id =~ /^[\s]+$/)) {
						$transfer_status ="$campaign_name";
						if($transfer_status eq "conf_context") {
							$transfer_status = "Conference";
						}
					}
					else {
						$transfer_status ="$agent_id:$campaign_name";
					}
				}

				$query="update call_dial_status set status='transfer',transfer_to='$transfer_status' where session_id=$session_id";
				$retval=query_execute($query,$dbh,0,__LINE__);

				$query="delete from customer_live where session_id=$session_id and agent_id != '$agent_id'";
				$retval=query_execute($query,$dbh,0,__LINE__);

                                if($reportupdate==1)
				{
					my $table_name=substr($time,0,7);
					$table_name=~s/-/_/g;

                                        if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/)) {
                                          my @variables=split(/,/,$returnvar);
                                          $transfer_from=(defined($variables[6])?$variables[6]:"");
                                        }
				
					$query="update $table_name set transfer_status='$transfer_from' where session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);

					check_cview($query,$dbh,$table_name,1);
					$query =~ s/$table_name/current_report/i;
					query_execute($query,$dbh,0,__LINE__);
				}
			}
###########################TRANSFER BLOCK END ############################


#to write the monitor filename when call is transferred from supervisor
##############MONITOR BLOCK START######################################
			elsif(($thread_type == 7) && ($command_line[0] =~ /Event: Monitor/))
			{
				my $session_id = substr($command_line[9],index($command_line[9],":") + 2);
				my $monitor_filename = substr($command_line[4],index($command_line[4],":") + 2);
				my $monitor_folder = substr($command_line[6],index($command_line[6],":") + 2);
				my $monitor_sub_folder = substr($command_line[7],index($command_line[7],":") + 2);
				my $value = substr($command_line[5],index($command_line[5],":") + 2);

				if(defined($monitor_folder) && ($monitor_folder !~ /^$/ && $monitor_folder !~ /^[\s]+$/) && length($monitor_folder) > 2)
				{
					if($monitor_folder !~ /^\//) {
						$monitor_folder =  "/".$monitor_folder."/";
				}
				if(!defined($monitor_sub_folder) or ($monitor_sub_folder =~ /^$/ && $monitor_sub_folder =~ /^[\s]+$/)) {
					if($monitor_folder !~ /\/$/) {
						$monitor_folder =  $monitor_folder."/";
					}
				}
				}

				if(defined($monitor_sub_folder) && ($monitor_sub_folder !~ /^$/ && $monitor_sub_folder !~ /^[\s]+$/)  && length($monitor_sub_folder) > 2)
				{
					if($monitor_sub_folder !~ /^\// && $monitor_folder !~ /\/$/) {
						$monitor_sub_folder =  "/".$monitor_sub_folder;
				}

				$monitor_folder =  $monitor_folder.$monitor_sub_folder;
				if($monitor_folder !~ /\/$/) {
					$monitor_folder =  $monitor_folder."/";
				}
				}

				if(defined($monitor_filename) && ($monitor_filename !~ /^$/ && $monitor_filename !~ /^[\s]+$/))
				{
#$monitor_filename = $monitor_filename.".wav";
#if call is monitored by agent explicitely
					if(defined $value and $value == 1)
					{
						$query="update customer_live set monitoring=1 where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);

						$query="update call_dial_status set monitor_file_name = '$monitor_filename',monitor_file_path='$monitor_folder' where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);
					}
#supervisor monitor
					else
					{
						$query="update meetme_user set monitor_filename = '$monitor_filename' where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);
					}
				}
			}
##############MONITOR BLOCK END######################################


##############HANGUP BLOCK START######################################
	        elsif(($thread_type == 5) && ((($command_line[0] =~ /Event: Hangup/) && ($command_line[2]!~/Local/)) || (($command_line[0] =~ /Event: Hangup/) && ($command_line[2] =~/VDN/)) || (($command_line[0] =~ /Event: Hangup/) && ($command_line[2] =~ /czreversedial/)) ))
			{
				my $agent_id= '';
				my $agent_name= '';
				my $csat="";
				my $dialer_var_channel_id="";
				my $dialer_var_channel="";
				my @outbound_feedback=();
				if($command_line[2] =~ /sip/i || $command_line[2] =~/zap/i || $command_line[2] =~ /Local/i)
				{
					my $meetmeflag = 0;
					my $ivrs_path = "";
					my $hold_num_time;
					my $cust_category= '';
					my $skill="";
					my $ivr_report=0;
					my $ringing_flag=0;
					my $provider_name="";
					my $did_num;
					my $q_enter_time;
					my $q_leave_time;
					my $meet_me_from="";
					my @meet_me_data=();
					my $check_conference=0;
					my $ivrnodeid="";
					my $appflag="";
					my $hangup_time;
					my $hangup_timestamp;
					my $pbx_flag=0;
					my $ivr_timestamp;
					my $cust_remove="";
					my $skill_id="";
					my $dialer_var="";
					my @dialer_variables=();

					$channel = substr($command_line[2],index($command_line[2],":") + 2);
					$session_id = substr($command_line[3],index($command_line[3],":") + 2);
					$returnvar = substr($command_line[6],index($command_line[6],":") + 1);
					$hangup_cause = substr($command_line[4],index($command_line[4],":") + 2);
					$campaign_type = substr($command_line[8],index($command_line[8],":") + 2);
					$did_num = substr($command_line[9],index($command_line[9],":") + 2);
					$pbx_flag=substr($command_line[10],index($command_line[10],":") + 2);
					$appflag=substr($command_line[12],index($command_line[12],":") + 2);
					$dialer_var = substr($command_line[13],index($command_line[13],":") + 1);
					$skill_id=substr($command_line[14],index($command_line[14],":") + 2);
					$ivrnodeid = substr($command_line[18],index($command_line[18],":") + 2);
                                        my $monitor_sub_folder=substr($command_line[22],index($command_line[22],":") + 2);
                                my $monitor_file_name=substr($command_line[23],index($command_line[23],":") + 2);
                                my $monitor_folder=substr($command_line[24],index($command_line[24],":") + 2);

					if(defined($ivr_license) && $ivr_license ) {
						$ivr_report=1;
					}

					$meet_me_from = substr($command_line[17],index($command_line[17],":") + 2);

					if(defined($meet_me_from) && ($meet_me_from !~ /^$/ && $meet_me_from !~ /^[\s]+$/))
					{
						@meet_me_data = split(/,/,$meet_me_from);
						my $agent_session_id=$meet_me_data[0];
						my  $agent_id = $meet_me_data[1];

						$query="select agent_state,is_paused,is_free,dialer_type,last_login_time,DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as last_login_time_table,pauseDuration,pause_time,unix_timestamp() as pause_cur_time,call_counter,last_activity_time,now(),agent_session_id,wait_duration,ready_time,campaign_id from agent_live where agent_id='$agent_id' and agent_session_id=$agent_session_id";
						$retval=query_execute($query,$dbh,1,__LINE__);

						$hangup_time= @$retval[11];
						$hangup_timestamp = @$retval[8];
						$check_conference = 1;
						if(scalar(@{$retval}) && defined(@$retval[0])) {
							failsafeLogout($dbh,$retval,$agent_id,$table_name,$hangup_time,$check_conference);
						}
						else {
							logoutupdate($agent_id,@$retval[4],"",$agent_session_id,$dbh,@$retval[15]);
						}
					}

					if(defined($dialer_var) && ($dialer_var !~ /^$/ && $dialer_var !~ /^[\s]+$/))
					{
						@dialer_variables=split(/,/,$dialer_var);
						$dialer_var_channel = ((defined($dialer_variables[10]) && ($dialer_variables[10] !~ /^$/ && $dialer_variables[10] !~ /^[\s]+$/))?$dialer_variables[10]:"");
						$dialer_var_channel_id = ((defined($dialer_variables[11]) && ($dialer_variables[11] !~ /^$/ && $dialer_variables[11] !~ /^[\s]+$/))?$dialer_variables[11]:"");
					}

					if(defined($dialer_var_channel_id) && ($dialer_var_channel_id !~ /^$/ && $dialer_var_channel_id !~ /^[\s]+$/))
					{
						$channel = $dialer_var_channel;
						$zap_channel = $dialer_var_channel_id;

						if($channel =~ /Zap/i)
						{
							$zap_channel =~ s/ZAP/Zap/g;
							if($zap_channel)
							{
								if (not exists($providernameHash{$zap_channel})) {
									populateprovider($dbh);
								}
								$provider_name=$providernameHash{$zap_channel};
							}
							$channel="ZAP";
						}
						elsif($channel =~ /SIP/i) 
						{
							if($zap_channel){
								if (not exists($sip_id_providernameHash{$zap_channel}))
								{
									sip_id_populateprovider($dbh);
								}
								$provider_name=$sip_id_providernameHash{$zap_channel};
							}
							$channel = "SIP";
						}
					}
					elsif($channel =~ /Zap/i) {
						$zap_channel=substr($channel,0,index($channel,"-"));
						$zap_channel =~ s/ZAP/Zap/g;
						if($zap_channel)
						{
							if (not exists($providernameHash{$zap_channel})) {
								populateprovider($dbh);
							}
							$provider_name=$providernameHash{$zap_channel};
						}
						$channel="ZAP";
					}
					elsif($channel =~ /SIP/i) {
						$zap_channel=substr($channel,index($channel,"/")+1);
						$zap_channel=substr($zap_channel,0,index($zap_channel,"-"));
						if(match_ip($zap_channel)){
							if (not exists($sip_providernameHash{$zap_channel}))
							{
								sip_populateprovider($dbh);
							}
							$provider_name=$sip_providernameHash{$zap_channel};
						}
						else{
							$provider_name=$zap_channel;
						}
						$zap_channel=$channel;
						$channel = "SIP";
					}
					elsif($channel =~ /Local/i)
					{
						  $zap_channel=$channel;
						  $provider_name="Local";
						  $channel = "Local";
					}
					else
					{
						$zap_channel=$channel;
						$channel = "SIP";
					}

                                        if(defined($monitor_folder) && ($monitor_folder !~ /^$/ && $monitor_folder !~ /^[\s]+$/) && length($monitor_folder) > 2)
                                {
                                        if($monitor_folder !~ /^\//) {
                                                $monitor_folder =  "/".$monitor_folder."/";
                                        }
                                        if(!defined($monitor_sub_folder) or ($monitor_sub_folder =~ /^$/ && $monitor_sub_folder =~ /^[\s]+$/)) {
                                                if($monitor_folder !~ /\/$/) {
                                                        $monitor_folder =  $monitor_folder."/";
                                                }
                                        }
                                }

                                if(defined($monitor_sub_folder) && ($monitor_sub_folder !~ /^$/ && $monitor_sub_folder !~ /^[\s]+$/)  && length($monitor_sub_folder) > 2)
                                {
                                        if($monitor_sub_folder !~ /^\// && $monitor_folder !~ /\/$/) {
                                                $monitor_sub_folder =  "/".$monitor_sub_folder;
                                        }
                                        $monitor_folder =  $monitor_folder.$monitor_sub_folder;
                                        if($monitor_folder !~ /\/$/) {
                                                $monitor_folder =  $monitor_folder."/";
                                        }
                                }

                                if($monitor_file_name !~ /^$/ && $monitor_file_name !~ /^[\s]+$/) {
                                        $monitor_file_name =$monitor_file_name.".wav";
                                }

					if(defined($pbx_flag) && $pbx_flag)
					{
						$query="delete from pbx_live where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);
					}
					else 
					{
						if($ivr_license) {
							$ivrs_path = substr($command_line[7],index($command_line[7],":") + 2);
						}

						if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
						{

							$returnvar=~ s/\s+//g;
							@variables=split(/,/,$returnvar);
							my $dialerType=$variables[5];
							my $transfer_from=$variables[6];

							if(defined($transfer_from) && ($transfer_from !~ /^$/ && $transfer_from !~ /^[\s]+$/))
							{
								if( $transfer_from eq "MEETME") {
									$meetmeflag = 1;
								}
							}
							$campaign_type = ($campaign_type==0?"INBOUND":"OUTBOUND");

							if ($dialerType eq "AUTODIAL")
							{
								if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
								{
									$returnvar=~ s/\s+//g;
									@variables=split(/,/,$returnvar);
									my $custphno=$variables[0];
									my $lead_id=$variables[1];
									my $campaign_id=$variables[2];
									my $list_id=$variables[3];
									my $strict=$variables[4];
									$dialerType=$variables[5];
									$transfer_from=$variables[6];

									if (not exists $campaignHash{$campaign_id}) {
										populateCampaign($campaign_id,$dbh,'0');
									}
									$campaign_name = $campaignHash{$campaign_id};

									$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");

									init_stateHash($session_id);
									if($stateHash{$session_id} >= 2  and $hangup_cause != 125 and $hangup_cause != 126)
									{
										$query = "update $cust_remove set lead_state='0',call_disposition='answered' where lead_id='$lead_id'";
										query_execute($query,$dbh,0,__LINE__);

										$query="update extended_customer_$campaign_id set lead_state='0' where lead_id='$lead_id'";
										query_execute($query,$dbh,0,__LINE__);

										$query="update dial_Lead_lookup_$campaign_id set lead_state='0' where lead_id='$lead_id'";
										query_execute($query,$dbh,0,__LINE__);

										$query="update dial_Lead_$campaign_id set lead_state='0' where lead_id='$lead_id'";
										query_execute($query,$dbh,0,__LINE__);


										if($lead_id) {
											$query="select list_name from list where list_id=$list_id";
											$returnvar=query_execute($query,$dbh,1,__LINE__);
											$list_name=@$returnvar[0];
										}
										else {
											$list_name="";
										}

										my @call_start_time=split("/\./",$session_id);
										$link_date_time= $call_start_time[0];
										$monitor_file_name= '';

										$q_enter_time= @$retval[13];
										$q_leave_time= @$retval[14];
										$hold_time= 0;
										$hold_num_time= 0;
										$cust_disposition= '';
										$cust_category= '';
										$remarks= '';
										$provider_name= '';
										$call_status='answered';
										$ringing_flag=1;

										$report_id='';
										$report_query="insert into $table_name (node_id,lead_id,agent_id,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,campaign_type,campaign_channel,zap_channel,monitor_filename,dialer_type,cust_disposition,q_enter_time,q_leave_time,hold_time,hold_num_time,call_status_disposition,cust_category,call_remarks,transfer_status,transfer_from,provider_name,call_charges,entrytime,skills,ringing_flag) values ('$node_id','$lead_id','$agent_id','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name',from_unixtime('$link_date_time'),'$hangup_time',$hangup_timestamp-$link_date_time,'$campaign_type','$channel','$zap_channel','$monitor_file_name','$dialerType','$cust_disposition','$q_enter_time','$q_leave_time','$hold_time','$hold_num_time','$call_status','$cust_category','$remarks','$transfer_status','$transfer_from','$provider_name','$unit_cost','$link_date_time','$skill_id','$ringing_flag')";
										$report_id=query_execute($report_query,$dbh,3,__LINE__);
#Adding information to current report

										$report_query="insert into $table_name (report_id,node_id,lead_id,agent_id,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,campaign_type,campaign_channel,zap_channel,monitor_filename,dialer_type,cust_disposition,q_enter_time,q_leave_time,hold_time,hold_num_time,call_status_disposition,cust_category,call_remarks,transfer_status,transfer_from,provider_name,call_charges,entrytime,skills,ringing_flag) values ('$report_id','$node_id','$lead_id','$agent_id','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name',from_unixtime('$link_date_time'),'$hangup_time',$hangup_timestamp-$link_date_time,'$campaign_type','$channel','$zap_channel','$monitor_file_name','$dialerType','$cust_disposition','$q_enter_time','$q_leave_time','$hold_time','$hold_num_time','$call_status','$cust_category','$remarks','$transfer_status','$transfer_from','$provider_name','$unit_cost','$link_date_time','$skill_id','$ringing_flag')";
										check_cview($report_query,$dbh,$table_name,1);
										$report_query =~ s/$table_name/current_report/i;
										query_execute($report_query,$dbh,0,__LINE__);
									}
								}
							}
						}

						if($ivr_license) {
#IVRS PATH
							if(defined $ivrs_path && ($ivrs_path !~ /^$/ && $ivrs_path !~ /^[\s]+$/))
							{
								my $leaf_node;
								my @leafval=();
								my $cust_num;
								my $channel;
								my $campaign_name;
								my $link_date_time;
								my $link_end_date_time;
								my $unlink_date_time;
								my $campaignTransfer="";
								my $campaignEnded="";
								my $node_name="";
								my $campaignTransfer_id="";
								my $campaignEnded_id="";
								my $skill_name="";
								my $provider_name ="";

								@leafval = split(/->/,$ivrs_path);
								$leaf_node = pop(@leafval);

								if (!defined($unlink_date_time)) {
									$unlink_date_time= "";
								}
								if (!defined($dialerType)) {
									$dialerType= "";
								}

								$query = "select session_id,link_date_time,if(unlink_date_time='0000-00-00 00:00:00',now(),unlink_date_time) as unlink_date_time,'$ivrs_path' as ivrs_path, cust_ph_no,'$leaf_node' as ivrs_leaf_node,CampaignTransfer,unix_timestamp(if(unlink_date_time='0000-00-00 00:00:00',now(),unlink_date_time)) - unix_timestamp(link_date_time) as duration,'$dialerType' as dialer_type,zap_channel,campaignEnded,unix_timestamp() from ivr_call_dial_status where session_id=$session_id";
								$retval=query_execute($query,$dbh,1,__LINE__);

								if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/))
								{
									$link_date_time= @$retval[1];
									$link_end_date_time= @$retval[2];
									$ivrs_path= @$retval[3];
									$custphno= @$retval[4];
									$leaf_node = @$retval[5];
									$campaignTransfer=(defined(@$retval[6])?@$retval[6]:"");
									$duration= @$retval[7];
									$dialerType= @$retval[8];
									$channel= @$retval[9];
									$campaignEnded=(defined(@$retval[10])?@$retval[10]:"");
									$ivr_timestamp=@$retval[11];
									if(($channel =~ /Zap/i)) {
										$channel=substr($channel,0,index($channel,"-"));
									}
									else {
										$channel = "SIP";
									}

									if((defined($campaignEnded) && ($campaignEnded !~ /^$/ && $campaignEnded !~ /^[\s]+$/)))
									{
										if (not exists $campaignNameHash{$campaignEnded}) {
												populateCampaign($campaignEnded,$dbh,'1');
										}
										$campaignEnded_id = $campaignNameHash{$campaignEnded};
                                                                              
										if(defined($skill_id) && ($skill_id !~ /^$/ && $skill_id !~ /^[\s]+$/) && $skill_id > 0)
										{
											if (not exists($campaignSkillHash{$skill_id."_".$campaignEnded_id})) {
												populateSkill($dbh);
											}
											$skill_name=$campaignSkillHash{$skill_id."_".$campaignEnded_id};
										}
										                                   
									}

									if((defined($campaignTransfer) && ($campaignTransfer !~ /^$/ && $campaignTransfer !~ /^[\s]+$/)))
									{
										if (not exists $campaignNameHash{$campaignTransfer}) {
											populateCampaign($campaignTransfer,$dbh,'1');
										}
										$campaignTransfer_id = $campaignNameHash{$campaignTransfer};
									}

									if((defined($ivrnodeid) && ($ivrnodeid !~ /^$/ && $ivrnodeid !~ /^[\s]+$/)))
									{
										if (not exists($ivrinfo{$ivrnodeid})) {
											populateivrinfo($dbh);
										}
										$node_name=$ivrinfo{$ivrnodeid};
									}

                                 
									$query = "insert into ivr_report_$table_name (node_id,session_id,link_date_time,unlink_date_time,ivrs_path,cust_ph_no,ivrs_leaf_node,CampaignTransfer,duration,dialer_type,zap_channel,CampaignEnded,did_num,skills,provider_name,ivr_node_name,ivr_node_id,campaignEnded_id,CampaignTransfer_id,entrytime,monitor_filename,monitor_file_path) values ('$node_id','$session_id','$link_date_time','$link_end_date_time','$ivrs_path','$custphno','$leaf_node','$campaignTransfer','$duration','$dialerType','$channel','$campaignEnded','$did_num','$skill_name','$provider_name','$node_name','$ivrnodeid','$campaignEnded_id','$campaignTransfer_id','$ivr_timestamp','$monitor_file_name','$monitor_folder')";
									$report_id=query_execute($query,$dbh,3,__LINE__);

									$query = "insert into ivr_report_$table_name (report_id,node_id,session_id,link_date_time,unlink_date_time,ivrs_path,cust_ph_no,ivrs_leaf_node,CampaignTransfer,duration,dialer_type,zap_channel,CampaignEnded,did_num,skills,provider_name,ivr_node_name,ivr_node_id,campaignEnded_id,CampaignTransfer_id,entrytime,monitor_filename,monitor_file_path) values ('$report_id','$node_id','$session_id','$link_date_time','$link_end_date_time','$ivrs_path','$custphno','$leaf_node','$campaignTransfer','$duration','$dialerType','$channel','$campaignEnded','$did_num','$skill_name','$provider_name','$node_name','$ivrnodeid','$campaignEnded_id','$campaignTransfer_id','$ivr_timestamp','$monitor_file_name','$monitor_folder')";

									check_cview($query,$dbh,$table_name,3);
									$query =~ s/$table_name/current_report/i;
									query_execute($query,$dbh,0,__LINE__);

                                                                         if (defined($monitor_file_name) && ($monitor_file_name !~ /^$/ && $monitor_file_name !~ /^[\s]+$/)) {
                                                        $query = "insert into pbx_unmerged_snd_files (monitor_filename,monitor_file_path) values ('$monitor_file_name','$monitor_folder')";
                                                        query_execute($query,$dbh,0,__LINE__,"Hangup");
                                                }

									$query = "delete from ivr_call_dial_status where session_id=$session_id";
									query_execute($query,$dbh,0,__LINE__);
								}
								undef(@leafval);
							}
							if ($appflag < 16)
							{
								if (not exists($ivrCsatHash{$ivrnodeid})) {
									populateCsativr($dbh);
								}
								$csat=$ivrCsatHash{$ivrnodeid};
						
							  if((defined($csat) && ($csat !~ /^$/ && $csat !~ /^[\s]+$/)))
							  {
									@outbound_feedback=split(/_/,$csat);
									my $start_time=$outbound_feedback[0];
									my $end_time=$outbound_feedback[1];
									my $csat_duration=$outbound_feedback[2];
									my $time_rule_flag=$outbound_feedback[3];
									my $ip=$outbound_feedback[4];
									my $ivr_campaign_id=$outbound_feedback[5];
									my $type=$outbound_feedback[6];

									csat_check($dbh,$start_time,$end_time,$time_rule_flag,$ivr_campaign_id,$custphno,$ip,$type,$session_id);
							  }
							}
						}

						$query="delete from customer_live where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);

						if($meetmeflag) {
							$query="delete from crm_meetme_live where agent_id='$agent_id' and session_id=$session_id";
							query_execute($query,$dbh,0,__LINE__);
						}

					}
					if(defined($stateHash{$session_id}))
					{
						$stateHash_semaphore->down;
						$stateHash{$session_id} = $stateHash{$session_id} | 2;
						$stateHash_semaphore->up;
						del_stateHash($session_id);
					}
				   undef(@dialer_variables);
				}
               if((defined($dialer_var_channel_id) && ($dialer_var_channel_id !~ /^$/ && $dialer_var_channel_id !~ /^[\s]+$/)) && ($command_line[2] =~ /czreversedial/i)) {
					if($dialer_var_channel_id =~ /Zap/i) {
						$query="update zap set status='FREE',session_id='0.0000000',flow_state='0' where zap_id='$zap_channel'";
					    query_execute($query,$dbh,0,__LINE__);

					    $query="update zap_live set campaign_id='',agent_id='',skill_id='',department_id='',peer_id='',phone_number='',call_type='',session_id='0.0000000',context='',incoming_phone_number='',service_type='',entry_time='',connect_time='',live_channel='' where zap_id='$zap_channel'";
					    query_execute($query,$dbh,0,__LINE__);
					}
				    elsif($dialer_var_channel_id =~ /sip/i){
					   $query="update sip set status='FREE',session_id='0.000000',flow_state='0' where session_id=$session_id";
					   query_execute($query,$dbh,0,__LINE__);
				   }
				}
				elsif($command_line[2] =~ /zap/i)
				{
					$query="update zap set status='FREE',session_id='0.0000000',flow_state='0' where zap_id='$zap_channel'";
					query_execute($query,$dbh,0,__LINE__);

					$query="update zap_live set campaign_id='',agent_id='',skill_id='',department_id='',peer_id='',phone_number='',call_type='',session_id='0.0000000',context='',incoming_phone_number='',service_type='',entry_time='',connect_time='',live_channel='' where zap_id='$zap_channel'";
					query_execute($query,$dbh,0,__LINE__);
				}
				elsif($command_line[2] =~ /sip/i)
				{
					$query="update sip set status='FREE',session_id='0.000000',flow_state='0' where session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);
				}
			}
##############HANGUP BLOCK END#####################################

##############CDR BLOCK START######################################
		elsif(($thread_type == 6) && ($command_line[0] =~ /Event: Cdr/))
		{
			my $parent_uniqueid="";
			my $monitor_folder="";
			my $monitor_sub_folder="";
			my $provider_caller_id=0;
			my $dialer_inserted_field=0;

			$report_id="";
			$session_id=substr($command_line[18],index($command_line[18],":") + 2);
			$link_date_time=substr($command_line[12],index($command_line[12],":") + 2);
			my $duration=substr($command_line[15],index($command_line[15],":") + 2);
			my $calling_party=substr($command_line[3],index($command_line[3],":") + 2);
			my $custphno=substr($command_line[4],index($command_line[4],":") + 2);
			my $did = substr($command_line[6],index($command_line[6],":") + 2);

			if($custphno =~ /\//) {
				$custphno=substr($custphno,index($custphno,"/") + 1);
			}

			my $monitor_file_name=substr($command_line[20],index($command_line[20],":") + 2);
			$channel=substr($command_line[7],index($command_line[7],":") + 2);
			my $dst_channel = substr($command_line[8],index($command_line[8],":") + 2);
			$dst_channel=substr($dst_channel,0,index($dst_channel,"-"));
			my $hold_time=0;
			my $cust_disposition=substr($command_line[25],index($command_line[25],":") + 2);
			my $hangup_cause=substr($command_line[22],index($command_line[22],":") + 2);
			my $call_status=substr($command_line[16],index($command_line[16],":") + 2);
			my $campaign_id=substr($command_line[26],index($command_line[26],":") + 2); #represents department id
			my $campaign_name=substr($command_line[27],index($command_line[27],":") + 2); #represents department name
			my $campaign_type=substr($command_line[21],index($command_line[21],":") + 2); #represents call type
			my $did_num = substr($command_line[28],index($command_line[28],":") + 2);
			$monitor_folder = substr($command_line[29],index($command_line[29],":") + 2);
			$monitor_sub_folder = substr($command_line[30],index($command_line[30],":") + 2);
			$parent_uniqueid = substr($command_line[31],index($command_line[31],":") + 2);
			my $CustUniqueId = substr($command_line[32],index($command_line[32],":") + 2);
			my $lingua = substr($command_line[33],index($command_line[33],":") + 2);
            my $callcategory = substr($command_line[34],index($command_line[34],":") + 2);
			my $peer_id = substr($command_line[35],index($command_line[35],":") + 2);
			my $userfileld = substr($command_line[19],index($command_line[19],":") + 2);
			my @urserfieldarray = split(/,/,$userfileld);
			my $dnid = (defined($urserfieldarray[0])?$urserfieldarray[0]:"");
			my $inter_call_type = (defined($urserfieldarray[1])?$urserfieldarray[1]:'0');
			$did_num = (defined($did_num)?$did_num:'0');

            my $ipbx_custphno = ($campaign_type == 0?$calling_party:$custphno);

			if(defined($monitor_folder) && ($monitor_folder !~ /^$/ && $monitor_folder !~ /^[\s]+$/) && length($monitor_folder) > 2)
			{
				if($monitor_folder !~ /^\//) {
						$monitor_folder =  "/".$monitor_folder."/";
				}
				if(!defined($monitor_sub_folder) or ($monitor_sub_folder =~ /^$/ && $monitor_sub_folder =~ /^[\s]+$/)) {
					if($monitor_folder !~ /\/$/) {
						$monitor_folder =  $monitor_folder."/";
					}
				}
			}

			if(defined($monitor_sub_folder) && ($monitor_sub_folder !~ /^$/ && $monitor_sub_folder !~ /^[\s]+$/)  && length($monitor_sub_folder) > 2)
			{
				if($monitor_sub_folder !~ /^\// && $monitor_folder !~ /\/$/) {
					$monitor_sub_folder =  "/".$monitor_sub_folder;
			     }

				$monitor_folder =  $monitor_folder.$monitor_sub_folder;
				if($monitor_folder !~ /\/$/) {
					$monitor_folder =  $monitor_folder."/";
				}	
			}


			if($dst_channel =~ /Zap/i) 
			{
				my $provider_name="";
				$dst_channel =~ s/ZAP/Zap/g;
				if($dst_channel)
				{
					if (not exists($providernameHash{$dst_channel})) {
						populateprovider($dbh);
					}
					$provider_name=$providernameHash{$dst_channel};
				}
				$channel=substr($channel,0,index($channel,"-"));

			   if(defined($provider_name) && ($provider_name !~ /^$/ && $provider_name !~ /^[\s]+$/))
				{
				   if (not exists($pricalleridHash{$provider_name})) {
					populateprovider($dbh);
				   }
				   $provider_caller_id=$pricalleridHash{$provider_name};
				}
			}
			elsif(($channel =~ /SIP/i)) {
				$channel=substr($channel,index($channel,"/")+1);
				$channel=substr($channel,0,index($channel,"-"));
				if(match_ip($channel)){
					if (not exists($sip_providernameHash{$channel}))
					{
						sip_populateprovider($dbh);
					}
					$provider_name=$sip_providernameHash{$channel};
				}
				else{
					$provider_name=$channel;
				}
				$channel = "SIP";
			}
			elsif(($channel =~ /Local/i))
			{
				$provider_name="Local";
				$channel = "Local";
			}
			else
			{
				$zap_channel=$channel;
				$channel = "SIP";
			}

			$call_status=($hangup_cause?($call_status=~"ANSWERED"?"FAILED":$call_status):$call_status);
			my $failed_reason=($hangup_cause?substr($command_line[24],index($command_line[24],":") + 2):"") ;
			$hangup_cause=($hangup_cause?substr($command_line[23],index($command_line[23],":") + 2):0);

			if($monitor_file_name !~ /^$/ && $monitor_file_name !~ /^[\s]+$/) {
				$report_query="insert into pbx_unmerged_snd_files (monitor_filename,monitor_file_path) values ('$monitor_file_name','$monitor_folder')";
				query_execute($report_query,$dbh,0,__LINE__);
				$dialer_inserted_field=0;
			}
			else{
				$dialer_inserted_field=0;
			}

			if($call_status =~ "FAILED")
			{
			  $duration=0;
			}
			$query="select now()";
			my $returnvar=query_execute($query,$dbh,1,__LINE__);
			my $cdr_time = @$returnvar[0];
            #src - peerid,dst - custphno
			$report_query="insert into cdr_$table_name (node_id,calldate,src,dst,channel,dstchannel,duration,disposition,cust_disposition,uniqueid,monitor_filename,call_type,failed_flag,failed_reason,department_id,department_name,dnid,monitor_file_path,parent_uniqueid,clid,inter_call_type,cdr_remarks,provider_caller_id,entrytime,CustUniqueId,language,callcategory) values ('$node_id',".($call_status=~"ANSWERED"?"'$link_date_time'":"'$cdr_time'").",'$peer_id','$ipbx_custphno','$channel','$dst_channel','$duration','$call_status','$cust_disposition','$session_id','$monitor_file_name','$campaign_type','$hangup_cause','$failed_reason','$campaign_id','$campaign_name','$dnid','$monitor_folder','$parent_uniqueid','$did','$inter_call_type','$did_num','$provider_caller_id',unix_timestamp('$cdr_time'),'$CustUniqueId','$lingua','$callcategory')";
			$report_id=query_execute($report_query,$dbh,3,__LINE__);

	        #Adding information to current report

			$report_query="insert into cdr_$table_name (report_id,node_id,calldate,src,dst,channel,dstchannel,duration,disposition,cust_disposition,uniqueid,monitor_filename,call_type,failed_flag,failed_reason,department_id,department_name,dnid,monitor_file_path,parent_uniqueid,clid,inter_call_type,cdr_remarks,provider_caller_id,entrytime,CustUniqueId,language,callcategory) values ('$report_id','$node_id',".($call_status=~"ANSWERED"?"'$link_date_time'":"'$cdr_time'").",'$peer_id','$ipbx_custphno','$channel','$dst_channel','$duration','$call_status','$cust_disposition','$session_id','$monitor_file_name','$campaign_type','$hangup_cause','$failed_reason','$campaign_id','$campaign_name','$dnid','$monitor_folder','$parent_uniqueid','$did','$inter_call_type','$did_num','$provider_caller_id',unix_timestamp('$cdr_time'),'$CustUniqueId','$lingua','$callcategory')";
			check_cview($report_query,$dbh,$table_name,5);
			$report_query =~ s/$table_name/current_report/i;
			query_execute($report_query,$dbh,0,__LINE__);
		}
##############CDR BLOCK END#########################################


##############SETMEFREE BLOCK START######################################
			elsif(($thread_type == 10) && ($command_line[0] =~ /Event: SetMeFree/))
			{
				my $call_duration=0;
				my $cust_free_name = '';
				my $next_call_time = 0;
				my $finwrapuptime=0;
				my $cust_category;
				my $forced=0;
				my $shortcall=0;
				my $CustUniqueId=0;
				my $remarks="";
				my $rd_flag=0;
				my $call_status="";
				my $cust_disposition="";
				my $camp_preview_flag=0;
				my $dialer_remarks="";
				my $hangup_cause="";
				my $campaigntype="";
				my $wrapup_time="";
				my $campaign_id;
				my $retvald;
				my $lead_id="";
				my $ringing_flag='0';
				my $pause_status='0';
				my $agent_session_id="";
				my $break_type="";
				my $setmefree_time;
				my $screen_rec_file_path="";
				my $screen_rec_file_name="";
				my $screen_rec_flag='0';
				my $screen_rec_start_time;
				my $screen_rec_end_time;
				my $scr_str="";
				my $customer_sentiment_name="";
				my $call_type="";
				my $csat="";
				my @outbound_feedback=();


				my $campaign_name=substr($command_line[2],index($command_line[2],":") + 2);
				my $agent_id=substr($command_line[3],index($command_line[3],"/") + 1);
				my $disconnect_time = substr($command_line[5],index($command_line[5],":") + 2);
				$session_id = substr($command_line[6],index($command_line[6],":") + 2);
				$hangup_cause = substr($command_line[7],index($command_line[7],":") + 2);
				$forced = substr($command_line[8],index($command_line[8],":") + 2);
#$shortcall = substr($command_line[9],index($command_line[9],":") + 2);

				if($campaign_name =~ /preview/)
				{
					$camp_preview_flag=1;
					$campaign_name = substr($campaign_name,8);
				}
				if (not exists $campaignNameHash{$campaign_name}) {
					populateCampaign($campaign_name,$dbh,'1');
				}
				$campaign_id = $campaignNameHash{$campaign_name};

				$query="select now()";
				my $tmp=query_execute($query,$dbh,1,__LINE__);
				$setmefree_time = @$tmp[0];


# <TVT> This query is removed
# $query="select campaign.wrapupTime from campaign,agent_live where agent_live.campaign_id=campaign.campaign_id and  agent_live.agent_id='$agent_id'";
# $retval=query_execute($query,$dbh,1,__LINE__);
# $finwrapuptime= ((defined @$retval[0])?@$retval[0]:$timestamp);

				$query="select closer_time,call_dialer_type,is_transfer,rd_flag,total_max_retries,max_retries,list_id,call_back_live,dialer_type,last_lead_id,ringing_flag,ph_type,is_paused,agent_session_id,break_type,phone_attempt_count,lead_attempt_count,per_day_mx_retry_count,call_type from agent_live where  agent_id='$agent_id' and session_id=$session_id";
				$retval=query_execute($query,$dbh,1,__LINE__);

				$disconnect_time= (((defined @$retval[0]) && @$retval[0] != 0)?@$retval[0]:$timestamp);
				$rd_flag= ((defined @$retval[3])?@$retval[3]:0);
				my $call_dialer_type= ((defined @$retval[1])?@$retval[1]:"");
				my $is_transfer= ((defined @$retval[2])?@$retval[2]:0);
				my $total_max_retries=((defined @$retval[4])?@$retval[4]:0);
				my $max_retries=((defined @$retval[5])?@$retval[5]:0);
				my $list_id=((defined @$retval[6])?@$retval[6]:0);
				my $call_back_live=((defined @$retval[7])?@$retval[7]:0);
				my $dialer_type=((defined @$retval[8])?@$retval[8]:"");
				my $phone_attempt_count=((defined @$retval[15])?@$retval[15]:"");
				my $live_lead_attempt_count=((defined @$retval[16])?@$retval[16]:"");
				my $lead_attempt_count = ($live_lead_attempt_count - 1  >= 0?$live_lead_attempt_count - 1:"");
				$ringing_flag=((defined @$retval[10])?@$retval[10]:"0");
				$lead_id=@$retval[9];
				my $ph_type= @$retval[11];
				$pause_status = @$retval[12];
				$agent_session_id = @$retval[13];
				$break_type = @$retval[14];
				$ph_type  = (defined($ph_type) && ($ph_type !~ /^$/ && $ph_type !~ /^[\s]+$/)?$ph_type:101);
				$call_type=((defined @$retval[18])?@$retval[18]:"");


				if(defined($session_id) && ($session_id !~ /^$/ && $session_id !~ /^[\s]+$/))
				{
					$query="select txt,call_status,cust_disposition,cust_name,category,next_call_time,CustUniqueId,next_action_set,agent_disconnect,screen_rec_file_path,screen_rec_file_name,screen_rec_flag,screen_rec_start_time,screen_rec_end_time,customer_sentiment_name from crm_live where agent_id='$agent_id' and session_id=$session_id";
					$retval=query_execute($query,$dbh,1,__LINE__);
					$remarks= ((defined @$retval[0])?@$retval[0]:"");
					if ($remarks !~ /^$/ && $remarks !~ /^[\s]+$/)
					{
						$remarks =~ s/\\/\\\\/g;
						$remarks =~ s/\'/\\'/g;
					}
					$cust_free_name = ((defined @$retval[3])?@$retval[3]:"");
					if ($cust_free_name !~ /^$/ && $cust_free_name !~ /^[\s]+$/)
					{
						$cust_free_name =~ s/\\/\\\\/g;
						$cust_free_name =~ s/\'/\\'/g;
					}

					$call_status= ((defined(@$retval[1]) && (@$retval[1] !~ /^$/ && @$retval[1] !~ /^[\s]+$/))?@$retval[1]:"answered");
					$cust_disposition= ((defined(@$retval[2]) && (@$retval[2] !~ /^$/ && @$retval[2] !~ /^[\s]+$/))?@$retval[2]:"None");
					$cust_category=((defined(@$retval[4]) && (@$retval[4] !~ /^$/ && @$retval[4] !~ /^[\s]+$/))?@$retval[4]:"Not Assigned");
					$next_call_time=((defined @$retval[5])?@$retval[5]:0);
					$CustUniqueId=((defined @$retval[6])?@$retval[6]:0);
					$dialer_remarks = ((defined @$retval[7])?@$retval[7]:"");
					my $agent_disconnect=((defined @$retval[8])?@$retval[8]:0);
					$screen_rec_file_path=((defined @$retval[9])?@$retval[9]:"");
					$screen_rec_file_name=((defined @$retval[10])?@$retval[10]:"");
					$screen_rec_flag=((defined @$retval[11])?@$retval[11]:0);
					$screen_rec_start_time=((defined @$retval[12])?@$retval[12]:0);
					$screen_rec_end_time=((defined @$retval[13])?@$retval[13]:0);
					$customer_sentiment_name=((defined(@$retval[14]) && (@$retval[14] !~ /^$/ && @$retval[14] !~ /^[\s]+$/))?@$retval[14]:"None");

                    if(defined($screen_rec_file_name) && ($screen_rec_file_name !~ /^$/ && $screen_rec_file_name !~ /^[\s]+$/)){
					 $scr_str=",screen_rec_file_path='$screen_rec_file_path',screen_rec_file_name='$screen_rec_file_name',screen_rec_flag='$screen_rec_flag',screen_rec_start_time='$screen_rec_start_time',screen_rec_end_time='$screen_rec_end_time'";
					}


					if (not exists $campaignWrapHash{$campaign_id}) {
						populateCampaignWrap($campaign_id,$dbh);
					}
					$finwrapuptime = $campaignWrapHash{$campaign_id};

					if (not exists $campaigntype{$campaign_id}) {
						populateCampaign($campaign_id,$dbh,'0');
					}
					$campaigntype = $campaigntype{$campaign_id};

					if($is_transfer == 0 && (($call_type == 0 && $campaigntype eq 'INBOUND') ||($call_type != 0 && $campaigntype eq 'OUTBOUND')) ) {
							if (not exists($campaignCsatHash{$campaign_id})) {
											populateCsat($dbh);
							}
							$csat=$campaignCsatHash{$campaign_id};
					}

					if(defined($csat) && ($csat !~ /^$/ && $csat !~ /^[\s]+$/)) {
							@outbound_feedback=split(/_/,$csat);
							my $start_time=$outbound_feedback[0];
							my $end_time=$outbound_feedback[1];
							my $csat_duration=$outbound_feedback[2];
							my $time_rule_flag=$outbound_feedback[3];
							my $ip=$outbound_feedback[4];
							my $type=$outbound_feedback[5];
							my $csatdisp=$outbound_feedback[6];
							if($duration >= $csat_duration && $cust_disposition ne $csatdisp){
								csat_check($dbh,$start_time,$end_time,$time_rule_flag,$campaign_id,$custphno,$ip,$type,$session_id);
							}
					}

#setting is_free to 0 as we have got a set me free. Abhi
##ADDING SESSION ID FIELD IN WHERE CONDITION. This is to avoid updating a deifferent logged in session.

                    $query="update agent_live set preview_fail=0,agent_state='FREE',closer_time='0',lead_id='0', is_free='0',holdDuration='0',holdNumTime='0',holdTimeInterval='',holdTimestamp='0000-00-00',last_activity_time='$setmefree_time',call_dialer_type='',wait_time=unix_timestamp(),is_setmefree='0',session_id='0.0000000',is_transfer='0',ringing_flag='0',phone_attempt_count='0',lead_attempt_count='0',per_day_mx_retry_count='0',CustUniqueId='',language='',callcategory='' where agent_id='$agent_id' and session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);

					my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($disconnect_time);
					my $table_YEAR=$year+1900;
					my $table_MONTH=$mon+1;
					my $report_table="$table_YEAR"."_".($table_MONTH < 10?"0"."$table_MONTH":"$table_MONTH");

					if((defined($pause_status) && $pause_status ) && $break_type ne "JoinedConference")
					{
						$query="update agent_state_analysis_$report_table set call_start_date_time='$setmefree_time' where agent_id='$agent_id' and agent_state='BREAK' and agent_session_id=$agent_session_id";
						query_execute($query,$dbh,0,__LINE__);

						check_cview($query,$dbh,$report_table,2);
#Adding information to Agent State Analysis current report
						$query =~ s/$report_table/current_report/i;
						query_execute($query,$dbh,0,__LINE__);
					}


					if((defined($hangup_cause) && $hangup_cause) || $camp_preview_flag) {
						$query="delete from callProgress where agent_id='$agent_id'";
						query_execute($query,$dbh,0,__LINE__);
					}

					my $forced_parsed= 1;
					if(defined($forced) && $forced)
					{
						if($cust_disposition eq "None")
						{
							$remarks=$remarks."F D(wrapup time exceed)";
							$dialer_remarks = ((defined $dialer_remarks) && ($dialer_remarks !~ /^$/ && $dialer_remarks !~ /^[\s]+$/)?$dialer_remarks:"Finished");
						}
					}
					if($agent_disconnect==0 && (defined($forced) && $forced) )
					{
						$next_call_time="";
						$dialer_remarks="";
						$forced_parsed= 2;
						$dialer_remarks="Finished";
					}

					if (not exists $campaigntype{$campaign_id}) {
						populateCampaign($campaign_id,$dbh,'0');
					}
					$campaigntype = $campaigntype{$campaign_id};

                    if((defined($lead_id) && ($lead_id !~ /^$/ && $lead_id !~ /^[\s]+$/)) && $lead_id > 0)
					{
						if($call_status eq "answered")
						{
							$ringing_flag='1';
						}

						if ($campaigntype ne "INBOUND" && ((defined($forced) && $forced) || $agent_disconnect==0))
						{
								$query="update dial_Lead_lookup_$campaign_id set lead_state='0' where lead_id='$lead_id'";
								query_execute($query, $dbh,0, __LINE__);

								$query="update extended_customer_$campaign_id set lead_state='0',last_call_disposition='answered',call_disposition_".($ph_type-100)."='answered',ringing_flag = '$ringing_flag' where lead_id='$lead_id'";
								query_execute($query, $dbh,0, __LINE__);

								if (($lead_attempt_count<=9) && (defined($lead_attempt_count) && ($lead_attempt_count !~ /^$/ && $lead_attempt_count !~ /^[\s]+$/))) {
									$query="update dial_state_$campaign_id set lead_state='0',disposition_$lead_attempt_count='$cust_disposition',phone_state_$lead_attempt_count='0',dial_state_$lead_attempt_count='0',next_call_time_$lead_attempt_count='$next_call_time',next_call_rule_$lead_attempt_count='$dialer_remarks',agent_id_$lead_attempt_count='$agent_id',phone_type_$lead_attempt_count='$ph_type',last_lead_status='1' where lead_id='$lead_id'";
									query_execute($query, $dbh,0, __LINE__);
								}

								$query="update dial_Lead_$campaign_id set lead_state='0'  where lead_id='$lead_id'";
								query_execute($query, $dbh,0, __LINE__);
						}
						else
						{
							$query="update extended_customer_$campaign_id set ringing_flag = if(ringing_flag < '$ringing_flag',$ringing_flag,ringing_flag) where lead_id='$lead_id'";
							query_execute($query, $dbh,0, __LINE__);

							if (($lead_attempt_count<=9) && (defined($lead_attempt_count) && ($lead_attempt_count !~ /^$/ && $lead_attempt_count !~ /^[\s]+$/))) {
								$query="update dial_state_$campaign_id set disposition_$lead_attempt_count='$cust_disposition',next_call_time_$lead_attempt_count='$next_call_time',next_call_rule_$lead_attempt_count='$dialer_remarks',agent_id_$lead_attempt_count='$agent_id',phone_type_$lead_attempt_count='$ph_type',last_lead_status='1' where lead_id='$lead_id'";
								query_execute($query, $dbh,0, __LINE__);
							}
						}
					}

					if((defined($forced) && $forced) || ((defined($finwrapuptime) && ($finwrapuptime !~ /^$/ && $finwrapuptime != /^[\s]+$/)) && $finwrapuptime != '0')) { 
						$wrapup_time = "wrapup_time=if(unix_timestamp('$setmefree_time') - unix_timestamp(call_end_date_time)<=$finwrapuptime,unix_timestamp('$setmefree_time') - unix_timestamp(call_end_date_time),$finwrapuptime)";
					}
					else {
						$wrapup_time = "wrapup_time=unix_timestamp('$setmefree_time') - unix_timestamp(call_end_date_time)";
					}

					$query="select 1 from current_report where agent_id='$agent_id' and session_id=$session_id and (transfer_status='Conference' or transfer_status='supervised_transfer') ";
					my $returnvar=query_execute($query,$dbh,1,__LINE__);

					if(defined(@$returnvar[0]))
					{
						$query="update $report_table set cust_disposition='$cust_disposition',".($hangup_cause?"call_remarks=concat(call_remarks,'$remarks'),":"call_remarks='$remarks',")."cust_category='$cust_category',setme_free_parsed='$forced_parsed',customer_sentiment_name='$customer_sentiment_name' where session_id=$session_id and agent_id ='$agent_id' and (transfer_status ='supervised_transfer' or transfer_status='Conference')";
						query_execute($query,$dbh,0,__LINE__);

						check_cview($query,$dbh,$report_table,1);
						$query =~ s/$report_table/current_report/i;
						query_execute($query,$dbh,0,__LINE__);
					}
					else
					{
					   $query="update $report_table set ". ($hangup_cause ?"":"call_status_disposition='$call_status',").($hangup_cause?"call_remarks=concat(call_remarks,'$remarks'),":"call_remarks='$remarks',")."cust_disposition='$cust_disposition',$wrapup_time,setme_free_parsed='$forced_parsed',". ($cust_free_name ?"cust_name='$cust_free_name',":"")."cust_category='$cust_category',customer_sentiment_name='$customer_sentiment_name',next_call_time='$next_call_time',".($CustUniqueId ?"CustUniqueId='$CustUniqueId',":"")."dialer_remarks='$dialer_remarks'$scr_str where session_id=$session_id and setme_free_parsed='0'  and agent_id ='$agent_id' and (isnull(transfer_status) or transfer_status='' or transfer_status = 'feedback')  and (call_status_disposition<>'supervised_transfer' or isnull(call_status_disposition))";
					   query_execute($query,$dbh,0,__LINE__);

#Adding information to current report
					  check_cview($query,$dbh,$report_table,1);
					  $query =~ s/$report_table/current_report/i;
					  query_execute($query,$dbh,0,__LINE__);
					}

##CRM_LIVE changes
					$query="update crm_live set lead_id='',txt='',call_status='',session_id='0.000000',cust_disposition='',cust_name='',category='',next_call_time='0',CustUniqueId='0',next_action_set = '',agent_disconnect='0',screen_rec_file_path='',screen_rec_file_name='',screen_rec_flag='',screen_rec_start_time='',screen_rec_end_time='',customer_sentiment_name='' where agent_id='$agent_id' and session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);

					$wrapupTime=0;
#calculate average, total wrapup time and total calls
					$wrapup_semaphore->down;
					$state_changed[$agent_id]=0;
					my @tmp_arr=();
					@tmp_arr=split(",",$agent_wrapup{$agent_id});
					$call_duration=abs ($tmp_arr[6]-$tmp_arr[8]);
					$wrapupTime=($timestamp - $disconnect_time);
					$tmp_arr[2]=$tmp_arr[2] + $wrapupTime;
					$tmp_arr[4]=$tmp_arr[4] + 1;
					$tmp_arr[1]=int($tmp_arr[2]/$tmp_arr[4]);
					if (defined $retval && $retval > 0)
					{
						$tmp_arr[5]="FREE";
					}
					if($setmefree_hit[$agent_id]==0)
					{
						$tmp_arr[6]=0;
						$tmp_arr[7]=0;
						$tmp_arr[8]=0;
					}
					if(($call_duration < $FIVE_MINUTES) && ($call_duration >= 0))
					{
						my @cda=split(",",$call_duration_array1[$agent_id]);
						if(defined $cda[0] && defined $cda[1] && defined $cda[2] && defined $cda[3])
						{
							if($cda[0]==$AVG_BLOCK)
							{
								$cda[0]=0;
								$cda[1]=0;
							}
							else
							{
								$cda[0]=$cda[0] + 1;
								$cda[1]=$cda[1] +  $wrapupTime;
							}
							$cda[2]=$cda[2] + 1;
							$cda[3]=$cda[3] +  $wrapupTime;
						}
						else
						{
							$cda[0]=1;
							$cda[1]=$wrapupTime;
							$cda[2]=1;
							$cda[3]=$wrapupTime;
						}
						$call_duration_array1[$agent_id]=join(",",@cda);
						undef(@cda);
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
					}
					elsif(($call_duration > $FIVE_MINUTES) && ($call_duration <  $TEN_MINUTES))
					{
						my @cda=split(",",$call_duration_array2[$agent_id]);
						if(defined $cda[0] && defined $cda[1] && defined $cda[2] && defined $cda[3])
						{
							if($cda[0]==$AVG_BLOCK)
							{
								$cda[0]=0;
								$cda[1]=0;
							}
							else
							{
								$cda[0]=$cda[0] + 1;
								$cda[1]=$cda[1] +  $wrapupTime;
							}
							$cda[2]=$cda[2] + 1;
							$cda[3]=$cda[3] +  $wrapupTime;
						}
						else
						{
							$cda[0]=1;
							$cda[1]=$wrapupTime;
							$cda[2]=1;
							$cda[3]=$wrapupTime;
						}
						$call_duration_array2[$agent_id]=join(",",@cda);
						undef(@cda);
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
					}
					elsif($call_duration >  $TEN_MINUTES)
					{
						my @cda=split(",",$call_duration_array3[$agent_id]);
						if(defined $cda[0] && defined $cda[1] && defined $cda[2] && defined $cda[3])
						{
							if($cda[0]==$AVG_BLOCK)
							{
								$cda[0]=0;
								$cda[1]=0;
							}
							else
							{
								$cda[0]=$cda[0] + 1;
								$cda[1]=$cda[1] +  $wrapupTime;
							}
							$cda[2]=$cda[2] + 1;
							$cda[3]=$cda[3] +  $wrapupTime;
						}
						else
						{
							$cda[0]=1;
							$cda[1]=$wrapupTime;
							$cda[2]=1;
							$cda[3]=$wrapupTime;
						}
						$call_duration_array3[$agent_id]=join(",",@cda);
						undef(@cda);
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
					}
					$wrapup_semaphore->up;
				}
			}
##############SETMEFREE BLOCK END######################################

###################ScreenRecordingStop#############################################
	 elsif(($thread_type == 7) && ($command_line[0] =~ /Event: RecordingStop/))
     {
		my $agent_id=0;
		my $campaign_id=0;
		my $rec_start_time="";
		my $rec_stop_time="";
		my $rec_flag=0;
		my $file_location="";
		my $file_name="";
		my $session_id="";
		my $system_ip="";
		my $host_name="";

		$agent_id = substr($command_line[2],index($command_line[2],":") + 2);
		$campaign_id = substr($command_line[4],index($command_line[4],":") + 2);
		$session_id = substr($command_line[3],index($command_line[3],":") + 2);
		$rec_start_time= substr($command_line[5],index($command_line[5],":") + 2);
		$rec_stop_time = substr($command_line[6],index($command_line[6],":") + 2);
		$file_location = substr($command_line[7],index($command_line[7],":") + 2);
		$file_name = substr($command_line[8],index($command_line[8],":") + 2);
		$system_ip=substr($command_line[9],index($command_line[9],":") + 2);
		$host_name=substr($command_line[10],index($command_line[10],":") + 2);
		$file_name =~ s/^\s+|\s+$//g;

		my $table_name=substr($time,0,7);
		$table_name=~s/-/_/g;
		if($scr_flag == 0)
		{
			$query="select ip from agent_live where agent_id='$agent_id'";
			$ip_address=query_execute($query,$dbh,1,__LINE__);
			if(defined(@$ip_address[0]) && @$ip_address[0]=~/$system_ip/)
			{

				$query="select 4 from current_report where session_id=$session_id ";
				$returnvar=query_execute($query,$dbh,1,__LINE__);
				if(defined(@$returnvar[0]) && (@$returnvar[0] !~ /^$/ && @$returnvar[0] !~ /^[\s]+$/))
				{
						$query="update $table_name set screen_rec_file_path='$file_location',screen_rec_file_name='$file_name',screen_rec_flag='$rec_flag',screen_rec_start_time=from_unixtime('$rec_start_time'),screen_rec_end_time=from_unixtime('$rec_stop_time') where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);

		#Adding information to current report
						check_cview($query,$dbh,$table_name,1);
						$query =~ s/$table_name/current_report/i;
						query_execute($query,$dbh,0,__LINE__);
				}
				else{

						$query="update crm_live set screen_rec_file_path='$file_location',screen_rec_file_name='$file_name',screen_rec_flag='$rec_flag',screen_rec_start_time=from_unixtime('$rec_start_time'),screen_rec_end_time=from_unixtime('$rec_stop_time'),session_id=if(session_id=0.0000000000,$session_id,session_id) where agent_id='$agent_id' ";
						query_execute($query,$dbh,0,__LINE__);
				}

			}
			else{
				$query="insert into screen_rec_backup_tbl (agent_id,system_ip,host_name,session_id,campaign_name,screen_rec_start_time, screen_rec_end_time, screen_rec_file_path, screen_rec_file_name ) values ('$agent_id','$system_ip','$host_name','$session_id','$campaign_id','$rec_start_time','$rec_stop_time','$file_location','$file_name')";
				query_execute($query,$dbh,0,__LINE__);
			}
		}
		else{
				$query="select 4 from current_report where session_id=$session_id ";
				$returnvar=query_execute($query,$dbh,1,__LINE__);
				if(defined(@$returnvar[0]) && (@$returnvar[0] !~ /^$/ && @$returnvar[0] !~ /^[\s]+$/))
				{
						$query="update $table_name set screen_rec_file_path='$file_location',screen_rec_file_name='$file_name',screen_rec_flag='$rec_flag',screen_rec_start_time=from_unixtime('$rec_start_time'),screen_rec_end_time=from_unixtime('$rec_stop_time') where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);

		#Adding information to current report
						check_cview($query,$dbh,$table_name,1);
						$query =~ s/$table_name/current_report/i;
						query_execute($query,$dbh,0,__LINE__);
				}
				else{

						$query="update crm_live set screen_rec_file_path='$file_location',screen_rec_file_name='$file_name',screen_rec_flag='$rec_flag',screen_rec_start_time=from_unixtime('$rec_start_time'),screen_rec_end_time=from_unixtime('$rec_stop_time'),session_id=if(session_id=0.0000000000,$session_id,session_id) where agent_id='$agent_id' ";
						query_execute($query,$dbh,0,__LINE__);
				}
		   }
     }
###################ScreenRecordingStopEnd###########################################

##################Screen SR_healthcheck######################################
		elsif(($thread_type == 4) && ($command_line[0] =~ /Event: SR_healthcheck/))
		{
			my $hostname="";
			my $systemip="";
			my $drive="";
			my $drive_space="";
			my $agentid="";
			my $scr_ac_name="";
			my $last_start_time="";
			my $uptime='0';
			my $scr_version="";

			$agentid=substr($command_line[5],index($command_line[5],":") + 2);
			$hostname=substr($command_line[2],index($command_line[2],":") + 2);
			$systemip=substr($command_line[3],index($command_line[3],":") + 2);
			$drive=substr($command_line[6],index($command_line[6],":") + 2);
			$drive_space=substr($command_line[7],index($command_line[7],":") + 2);
			$scr_ac_name=substr($command_line[8],index($command_line[8],":") + 2);
			$last_start_time=substr($command_line[9],index($command_line[9],":") + 2);
			$uptime=substr($command_line[10],index($command_line[10],":") + 2);
			$scr_version=substr($command_line[11],index($command_line[11],":") + 2);


			$query="select 1 from screen_rec_live  where agent_id='$agentid' and host_name='$hostname'";
			$returnvar=query_execute($query,$dbh,1,__LINE__);
			if(!defined (@$returnvar[0]))
			{
					$query="insert into screen_rec_live (host_name,system_ip,agent_id,update_time,drive,drive_space,scr_ac_name,last_start_time,uptime,scr_version) values ('$hostname','$systemip','$agentid',unix_timestamp(),'$drive','$drive_space','$scr_ac_name','$last_start_time','$uptime','$scr_version')";
					query_execute($query,$dbh,0,__LINE__);
			}
			else{
					$query="update  screen_rec_live set update_time=unix_timestamp(),drive='$drive',drive_space='$drive_space',scr_ac_name='$scr_ac_name',last_start_time='$last_start_time',uptime='$uptime',scr_version='$scr_version' where system_ip='$systemip' and host_name='$hostname'";
					query_execute($query,$dbh,0,__LINE__);
			}
		}
###################SR_healthcheck End###########################################

######################Ftpupload#################################################
			elsif(($thread_type == 7) && ($command_line[0] =~ /Event: FtpUpdateComplete/))
			{

				my $session_id="";
				$session_id = substr($command_line[3],index($command_line[3],":") + 2);
				$file_name = substr($command_line[2],index($command_line[2],":") + 2);

				my $table_name=substr($time,0,7);
				$table_name=~s/-/_/g;

				$query="update $table_name set  ftp_Complete='1' where session_id=$session_id ";
				query_execute($query,$dbh,0,__LINE__);

#Adding information to current report
				check_cview($query,$dbh,$table_name,1);
				$query =~ s/$table_name/current_report/i;
				query_execute($query,$dbh,0,__LINE__);
			}

##################ftpuploadEnd##############################################

##############AGENTCONNECT START############################################
			elsif((($thread_type == 10)) && ($command_line[0] =~ /Event: AgentConnect/))
			{
				my $preview_flag=0;
				my @dialer_variables=();
				my $phone_type="";
				my $lead_retry_count=0;
				my $phone_retry_count=0;
				my $lead_attempt_count=0;
				my $phone_attempt_count=0;
				my $per_day_mx_retry_count=0;
				my $next_call_time=0;
				my $redial_flag=0;
				my $call_back_live=0;
				my $agent_assigned=0;
				my $call_type;
				my $transfer_flag=0;
				my $screen_tranf=0;
				my $park_flag=0;
				my $dialer_type="PROGRESSIVE";
				my $list_name='';
				my $ivrs_path='';
				my $campaign_type='';
				my $did='';
				my $gmt_timestamp=get_gmt_time($timestamp) + 14400 ;
				my $exnct=$timestamp + 14400;
				my $call_back_live_re=0;
				my $returnvar ="";
				my $sth;
				my @row =();
				my $list_str="";
				my $totalMax=0;
				my $is_vdn='0';
				my $CustUniqueId;
				my $lingua="";
				my $callcategory="";
				my $campaign_customer_lookup=0;
				my $cust_remove="";
				my $skill_id=0;
				my $skill_name="";
				my $transfer_from="";
				my @trans_var=();
				my $from_tran_camp="";
				my $transfer_same_camp=0;
				my $insert_str="";
				my $insert_data_str="";
				my $update_str="";
				my @variables=();


				$campaign_name = substr($command_line[2],index($command_line[2],":") + 2);
				$session_id = substr($command_line[3],index($command_line[3],":") + 2);
				$channel = substr($command_line[6],index($command_line[6],":") + 2);
				$agent_id = substr($command_line[7],index($command_line[7],":") + 2);
				$hold_time = substr($command_line[8],index($command_line[8],":") + 2);
				$ivrs_path = substr($command_line[10],index($command_line[10],":") + 2);
				$call_type = substr($command_line[11],index($command_line[11],":") + 2);
				$custphno = substr($command_line[12],index($command_line[12],":") + 2);
				$q_enter_time = (defined($command_line[13])?substr($command_line[13],index($command_line[13],":") + 2):"");
				$q_leave_time = (defined($command_line[14])?substr($command_line[14],index($command_line[14],":") + 2):"");
				$skill_id = substr($command_line[15],index($command_line[15],":") + 2);
				$dialer_var = substr($command_line[17],index($command_line[17],":") + 2);
				$returnvar = substr($command_line[9],index($command_line[9],":") + 1);
				$did = substr($command_line[21],index($command_line[21],":") + 2);
				$CustUniqueId = substr($command_line[22],index($command_line[22],":") + 2);
				$lingua = substr($command_line[23],index($command_line[23],":") + 2);
				$callcategory = substr($command_line[24],index($command_line[24],":") + 2);
				$returnvar =~ s/^\s+//;
				$campaign_type = ($call_type==0?"INBOUND":"OUTBOUND");

                if(defined($CustUniqueId) && ($CustUniqueId !~ /^$/ && $CustUniqueId !~ /^[\s]+$/) && ($CustUniqueId != 0 && $CustUniqueId !=""))
                {
			      $insert_str=",CustUniqueId";
			      $insert_data_str=",'$CustUniqueId'";
			      $update_str=",CustUniqueId='$CustUniqueId'";
			    }

				$skill_id = ($skill_id==-1?"0":$skill_id);
#<TVT> This cannot come here.
				my $lead_id=0;
#Get Agent ID
				if($agent_id =~ /Agent\//) {
					$agent_id=substr($agent_id,index($agent_id,"/") + 1);
			        }
#Get Camapign Name
				if($campaign_name =~ /preview/) {
					$preview_flag=1;
					$campaign_name=substr($campaign_name,8);
					$dialer_type="PREVIEW"
				}
				else {
					$query="delete from queue_live where session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);
				}
#Mark the state of agent READY
				$wrapup_semaphore->down;
				my @tmp_arr=();
				@tmp_arr=split(",",$agent_wrapup{$agent_id});
				$tmp_arr[5]="INCALL";
				$tmp_arr[7]=time;               #state change time
				$tmp_arr[8]=time;               #call connect time
				$agent_wrapup{$agent_id}=join(",",@tmp_arr);
				$wrapup_semaphore->up;
				undef(@tmp_arr);

				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/)) {
					$campaign_id = $campaignNameHash{$campaign_name};
					@variables=split(/,/,$returnvar);
					$transfer_flag = (defined($variables[6])?1:0);
					$transfer_from=(defined($variables[6])?$variables[6]:"");
					if($transfer_from =~ /Park/i)
					{
						$park_flag=1;
					}
					if($transfer_flag || $channel =~ /VDN/i) {
						$custphno=(defined($variables[0])?$variables[0]:"");

						if (not exists $campaignScreenHash{$campaign_id}) {
							populateCampaign($campaign_id,$dbh,'0');
						}
						$screen_tranf = $campaignScreenHash{$campaign_id};
						if($channel =~ /VDN/i) {
							$is_vdn='1';
						}
					}
				}

				if (index($transfer_from,":") > 0) {
                     @trans_var=split(/:/,$transfer_from);
                     $from_tran_camp=$trans_var[1];
                }

                if($from_tran_camp eq $campaign_name){
                      $transfer_same_camp='1';
                }

#OUTBOUND CASE
			if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/) && (($transfer_same_camp=='1' && $transfer_flag=='1') || (!$transfer_flag && !$is_vdn && !$park_flag)  ||($transfer_flag && $screen_tranf) || ($is_vdn && $screen_tranf) ))
			{
				$returnvar=~ s/\s+//g;
				@variables=split(/,/,$returnvar);
				$custphno=$variables[0];

				$lead_id=((defined($variables[1]) && ($variables[1] !~ /^$/ && $variables[1] !~ /^[\s]+$/))?$variables[1]:0);
				$campaign_id=$variables[2];
				$list_id=((defined($variables[3]) && ($variables[3] !~ /^$/ && $variables[3] !~ /^[\s]+$/))?$variables[3]:0);
				$strict=$variables[4];
				$transfer_from=(defined($variables[6])?$variables[6]:"");
				if($channel =~ /VDN/i)
				{
					$custphno=$variables[7];
				}

				@dialer_variables=split(/,/,$dialer_var);
				$phone_type = $dialer_variables[0];
				$lead_retry_count = (defined($dialer_variables[1])?$dialer_variables[1]:"0");
				$phone_retry_count = (defined($dialer_variables[2])?$dialer_variables[2]:"0");
				$next_call_time = $dialer_variables[3];
				$next_call_time = (defined($dialer_variables[3])?$dialer_variables[3]:"");
				$redial_flag= (defined($dialer_variables[4])?$dialer_variables[4]:"");
				$call_back_live= (defined($dialer_variables[5])?$dialer_variables[5]:"");
				$agent_assigned= (defined($dialer_variables[6])?$dialer_variables[6]:"0");
				$lead_attempt_count=(defined($dialer_variables[8])?$dialer_variables[8]:"0");
				$phone_attempt_count=(defined($dialer_variables[9])?$dialer_variables[9]:"0");
				$CustUniqueId=((defined($variables[12]) && ($variables[12] !~ /^$/ && $variables[12] !~ /^[\s]+$/))?$variables[12]:"");
				$per_day_mx_retry_count=(defined($dialer_variables[19])?$dialer_variables[19]:"0");

                if(defined($CustUniqueId) && ($CustUniqueId !~ /^$/ && $CustUniqueId !~ /^[\s]+$/) && ($CustUniqueId != 0 && $CustUniqueId !=""))
                {
			      $insert_str=",CustUniqueId";
			      $insert_data_str=",'$CustUniqueId'";
			      $update_str=",CustUniqueId='$CustUniqueId'";
			    }

				if(defined($next_call_time) && ($next_call_time !~ /^$/ && $next_call_time!= /^[\s]+$/)){
					$call_back_live_re=1;
				}

				if((defined($redial_flag) && $redial_flag) || (defined($park_flag) && $park_flag)) {
					$query="delete from callProgress where agent_id='$agent_id'";
					query_execute($query,$dbh,0,__LINE__);
				}

				if(defined($lead_id) && ($lead_id !~ /^$/ && $lead_id != /^[\s]+$/))
				{

					if ((defined($dialer_var) && ($dialer_var !~ /^$/ && $dialer_var ne /^[\s] +$/)) && $transfer_from eq "")
					{

						if (not exists $campaignmax{$campaign_id}) {
							populateCampaign($campaign_id,$dbh,'1');
						}
						$totalMax = $campaignmax{$campaign_id};
						my $totalMaxlled = (((defined($totalMax) && $totalMax) && $campaign_type eq "OUTBOUND")?",total_max_retries = total_max_retries +1":",total_max_retries =0") ;
						my $Maxph = (((defined($totalMax) && $totalMax) && $campaign_type eq "OUTBOUND")?",max_retries = if(ph_type='$phone_type',max_retries +1,max_retries)":",max_retries = if(ph_type='$phone_type',0,max_retries)") ;
						my $extMaxph = (((defined($totalMax) && $totalMax) && $campaign_type eq "OUTBOUND")?",max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." +1":",max_retries_".($phone_type-100)."=0") ;


						$query="update extended_customer_$campaign_id set num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_connect_count=total_connect_count+1,total_num_times_dialed=total_num_times_dialed+1".($lead_attempt_count?"":",first_dial_time=now()").",first_success_time=if(first_success_time='0000-00-00 00:00:00' or first_success_time='',now(),first_success_time),agentid='$agent_id',next_call_time='$exnct',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),lead_state='0',last_call_disposition='answered',".($phone_type?"call_disposition_".($phone_type-100)."='answered',connect_count_".($phone_type-100)."=connect_count_".($phone_type-100)." + 1":"")." $totalMaxlled$extMaxph$update_str where lead_id='$lead_id'";
						query_execute($query,$dbh,0,__LINE__);

						if ($lead_attempt_count<=9) {
							$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',agent_id_$lead_attempt_count='$agent_id'$update_str,phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$exnct',disposition_$lead_attempt_count='answered',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_state='0',first_success_time=if(first_success_time='0' or first_success_time='',unix_timestamp(),first_success_time),lead_attempt_count=$lead_attempt_count+1,last_lead_status='1' where lead_id='$lead_id'";
							query_execute($query, $dbh,0, __LINE__);
						}


						if($campaign_type eq "OUTBOUND")
						{
							$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count=$lead_attempt_count+1,per_day_mx_retry_count=$per_day_mx_retry_count+1,lead_state='0',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count)$totalMaxlled$Maxph$update_str where lead_id='$lead_id'";
							query_execute($query,$dbh,0,__LINE__);

#---campaign---
							$query="update dial_Lead_$campaign_id set lead_attempt_count=$lead_attempt_count+1,per_day_mx_retry_count=$per_day_mx_retry_count+1,lead_state='0',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count)$totalMaxlled$Maxph$update_str where lead_id='$lead_id'";
							query_execute($query,$dbh,0,__LINE__);
						}
					}
				}

				if(!$preview_flag && defined($list_id) && ($list_id !~ /^$/ && $list_id != /^[\s]+$/)){
					$query="update listener_status set ans_avg_time=ans_avg_time + $hold_time where list_id='$list_id' and dialing_date=curdate()";
					query_execute($query,$dbh,0,__LINE__);
				}

			}       #INBOUND CASE
			else {
				my $temp="";
				my $time_zone_id="";
				my $new_customer=0;
				my $blank_num = 0;
				my $blendedlookup=0;
				if (not exists $campaignNameHash{$campaign_name}) {
					populateCampaign($campaign_name,$dbh,'1');
				}
				$campaign_id = $campaignNameHash{$campaign_name};
				$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");

				if($channel =~ /VDN/i) {
					$custphno=(defined($variables[7])?$variables[7]:"");
					$transfer_from=(defined($variables[8])?$variables[8]:"");
				}

				if (not exists $campaignblendedlookup{$campaign_id}) {
					populateCampaign($campaign_id,$dbh,'0');
				}
				$blendedlookup = $campaignblendedlookup{$campaign_id};

				if (not exists $customerlookup{$campaign_id}) {
				  populateCampaign($campaign_id,$dbh,'0');
				}
				$campaign_customer_lookup = $customerlookup{$campaign_id};

				if($custphno =~ /^$/ || $custphno =~ /^[\s]+$/) {
					$custphno=int(rand(100000));
					$custphno="1234-$custphno";
					$blank_num=1;
					$new_customer=1;
				}

					if($campaign_customer_lookup == 1)
					{
						    my $bl_list_str="";
							if(!$blank_num)  
							{
								if($blendedlookup)
								{
									$query = "select list_id from list where inbound_list_lookup='1' and campaign_id='$campaign_id'";
									$sth = $dbh->prepare($query);
									$sth->execute();
									while ( @row = $sth->fetchrow_array() ) {
											$bl_list_str=$bl_list_str.",".$row[0];
									}
									$bl_list_str =~ s/^,//g;
									$sth->finish();
									$query="select lead_id,list_id,ph_type from dial_Lead_lookup_$campaign_id where phone='$custphno' and list_id in ($bl_list_str)";
									$temp=query_execute($query,$dbh,1,__LINE__);
								}
								else
								{
									$query="select lead_id,list_id,ph_type from dial_Lead_lookup_$campaign_id where phone='$custphno' limit 1";
									$temp=query_execute($query,$dbh,1,__LINE__);
								}
								if(defined(@$temp[0]) && @$temp[0] !~ /^$/ && @$temp[0]!~ /^[\s]+$/)
								{
									$lead_id=@$temp[0];
									$list_id=@$temp[1];
									$phone_type=@$temp[2];
								}
								else {
									$new_customer=1;
									$phone_type='101';
								}
							}
							if($new_customer)
							{
									if($blendedlookup)
									{
										$query="select list_id,list_name,time_zone_id,timezone_code_id from list where campaign_id='$campaign_id' and  list_id in ($bl_list_str) limit 1";
										$temp=query_execute($query,$dbh,1,__LINE__);
										$list_id=@$temp[0];
										$list_name=@$temp[1];
										$time_zone_id=@$temp[3];
									}
									else
									{
										$query="select list_id,list_name,time_zone_id,timezone_code_id from list where campaign_id='$campaign_id' and list_name like '%inbound%'  limit 1";
										$temp=query_execute($query,$dbh,1,__LINE__);
										if(defined(@$temp[0]) && @$temp[0] !~ /^$/ && @$temp[0]!~ /^[\s]+$/)
										{  
											$list_id=@$temp[0];
											$list_name=@$temp[1];
											$time_zone_id=@$temp[3];
										}
										else{
											$query="select list_id,list_name,time_zone_id,timezone_code_id from list where campaign_id='$campaign_id' limit 1";
											$temp=query_execute($query,$dbh,1,__LINE__);
											$list_id=@$temp[0];
											$list_name=@$temp[1];
											$time_zone_id=@$temp[3];
										}
									  }

									my $custphno1;
									$custphno1=int(rand(100000));
									$custphno1="1234-$custphno1";

									$query="insert into $cust_remove (phone1,phone2,listerner_inserted_field,list_id$insert_str) values ('$custphno','$custphno1','1','$list_id'$insert_data_str)";
									$lead_id=query_execute($query,$dbh,3,__LINE__);

									$query="insert into dial_Lead_lookup_$campaign_id(lead_id,phone,list_id,time_zone_id,ph_type,dial_state,lead_state$insert_str) values ($lead_id,'$custphno','$list_id','$time_zone_id','101','0','0'$insert_data_str)";
									query_execute($query,$dbh,0,__LINE__);


									$query="insert into dial_Lead_lookup_$campaign_id(lead_id,phone,list_id,time_zone_id,ph_type,dial_state,lead_state$insert_str) values ($lead_id,'$custphno1','$list_id','$time_zone_id','102','0','0'$insert_data_str)";
									query_execute($query,$dbh,0,__LINE__);


									$query="insert into extended_customer_$campaign_id (lead_id,phone1,tz_ph_1,list_id,phone2,tz_ph_2,lead_state,total_connect_count,last_dial_time$insert_str) values ($lead_id,'$custphno','$time_zone_id','$list_id','$custphno1','$time_zone_id','0','1',now()$insert_data_str)";
									query_execute($query,$dbh,0,__LINE__);

									$query="insert into cust$campaign_id(lead_id) values ($lead_id)";
									query_execute($query,$dbh,0,__LINE__);
							}
					}
			}

			$phone_type=($phone_type?$phone_type:'101');

			if ((defined($dialer_var) && ($dialer_var !~ /^$/ && $dialer_var ne /^[\s] +$/))){
				if (not exists $campaignmax{$campaign_id}) {
					populateCampaign($campaign_id,$dbh,'1');
				}
				$totalMax = $campaignmax{$campaign_id};
			}
			my $totalMaxl_live = (((defined($totalMax) && $totalMax) && $campaign_type eq "OUTBOUND")?",total_max_retries = '$lead_retry_count'":",total_max_retries =0") ;
			my $Max_live = (((defined($totalMax) && $totalMax) && $campaign_type eq "OUTBOUND")?",max_retries='$phone_retry_count'":",max_retries =0") ;

			if(defined($park_flag) && $park_flag) {
				$transfer_flag ='2';
			}

            if($is_vdn == 1 && $preview_flag==1 && $campaign_type eq "OUTBOUND" ) {
				$custphno=(defined($variables[0])?$variables[0]:"");
				$campaign_id=(defined($variables[2])?$variables[2]:"");
				$lead_id='0';
			}

			if(defined($skill_id) && ($skill_id !~ /^$/ && $skill_id !~ /^[\s]+$/) && $skill_id > 0)
			{
				if (not exists($campaignSkillHash{$skill_id."_".$campaign_id})) {
					populateSkill($dbh);
				}
				$skill_name=$campaignSkillHash{$skill_id."_".$campaign_id};
			}
			$skill_id = ($skill_id==-1?"0":$skill_id);

			$query="update agent_live set agent_state='INCALL',session_id='$session_id',lead_id='$lead_id', is_free='1',holdDuration='0',holdNumTime='0',holdTimestamp='0000-00-00 00:00:00',last_activity_time=now(),from_campaign='$campaign_id',last_lead_id='$lead_id',last_cust_ph_no='$custphno',call_type='$call_type',ph_type='$phone_type',rd_flag='$redial_flag',call_dialer_type='$dialer_type',call_back_live='$call_back_live_re',is_transfer='$transfer_flag',is_setmefree='1',did_num='$did',wait_time=unix_timestamp() - wait_time,list_id='$list_id',lead_attempt_count=$lead_attempt_count+1,per_day_mx_retry_count=$per_day_mx_retry_count+1,phone_attempt_count='$phone_attempt_count',language='$lingua',callcategory='$callcategory',skills='$skill_name',skill_id='$skill_id',trying_flag=0,trying_cust_ph_no=0$update_str$totalMaxl_live$Max_live  where agent_id='$agent_id'";
			query_execute($query,$dbh,0,__LINE__);

			$query="replace into customer_live(cust_ph_no,agent_id,campaign_id,channel,link_time,session_id,state,ivrs_path,skills,is_vdn) values('$custphno','$agent_id','$campaign_id','$channel','$time','$session_id','MUNHOLD','$ivrs_path','$skill_id','$is_vdn')";
			query_execute($query,$dbh,0,__LINE__);

			if($lead_id && $list_id) {
				if($crm_license) {
					if($list_name=~ /^$/ || $list_name=~/^[\s]+$/) {
						$query="select list_name from list where list_id='$list_id'";
						$temp=query_execute($query,$dbh,1,__LINE__);
						$list_name=@$temp[0];
					}
				}
			}
			else {
				$list_id = 0;
				$list_name = "Manual_Dial";
			}

			$query="update crm_hangup_live set lead_id='',txt='',call_status='',category='',session_id='$session_id',cust_disposition='',next_call_time='0',CustUniqueId='0',next_action_set='',agent_disconnect='0',customer_sentiment_name='' where agent_id='$agent_id'";
			query_execute($query,$dbh,0,__LINE__);


			$channel  = ($channel =~ /ZAP/i?$channel:"SIP");
			$query="replace into call_dial_status  (agent_id,channel,link_date_time,dialer_type,status,cust_ph_no,campaign_id,lead_id,session_id,list_id,list_name,transfer_from) values ('$agent_id','$channel',now(),'$call_type','answered','$custphno','$campaign_id','$lead_id','$session_id','$list_id','$list_name','$transfer_from')";
			query_execute($query,$dbh,0,__LINE__);


			if($channel =~ /ZAP/i) {
				$channel=substr($channel,0,index($channel,"-"));

				$query="update zap_live set campaign_id='$campaign_id',skill_id='$skill_id',phone_number='$custphno',call_type='$call_type',agent_id='$agent_id',service_type='2',department_id='',peer_id='',connect_time=unix_timestamp() where zap_id='$channel'";
				query_execute($query,$dbh,0,__LINE__);
			}

			init_stateHash($session_id);
			$stateHash_semaphore->down;
			$stateHash{$session_id} = $stateHash{$session_id} | (1 << 4);
			$stateHash_semaphore->up;
		}

##############AGENTCONNECT END######################################

##############AgentComplete START######################################
			elsif((($thread_type == 10)) && ($command_line[0] =~ /Event: AgentComplete/))
			{
				my $disconnected_by = "";
				my $meetmeflag = 0;
				my $unlink_date_time = "";
				my $link_end_date_time;
				my $file_format = "";
				my $preview_flag=0;
				my $hold_timestamp=0;
				my $hold_num_time=0;
				my $cust_category = "";
				my $customer_sentiment_name="";
				my $transfer_to;
				my $provider_name="";
				my @dialer_variables=();
				my $phone_type=101;
				my $lead_retry_count=0;
				my $phone_retry_count=0;
				my $next_call_time=0;
				my $redial_flag=0;
				my $call_back_live=0;
				my $CustUniqueId="";
				my $monitor_folder="";
				my $monitor_sub_folder="";
				my $concurrent_call=0;
				my $non_desktop_ip=0;
				my $transfer_lead_id="";
				my $wait_time=0;
				my $duration=0;
				my $ringing_flag=0;
				my $remarks="";
				my $ivrsPath="";
				my $ringstart;
				my $ringend;
				my $call_back_live_re=0;
				my $ringduration=0;
				my $CallPicked;
				my $lead_attempt_count=0;
				my $per_day_mx_retry_count=0;
				my $phone_attempt_count=0;
				my $vdn_transfer="";
				my $campaigntype="";
				my $csat="";
				my $new_monitor_filename="";
				my $vdn_no=0;
				my $callerid=0;
				my $returnvar;
				my $park_start_time=0;
				my $park_end_time=0;
				my @parkval=();
				my @variables=();
				my $park_agent;
				my $park_flag=0;
				my $channel_id="";
				my $dialer_inserted_field=0;
				my $cust_reporting=0;
				my $ring_time=0;
				my $vdn_from="";
				my $lingua="";
                my $callcategory="";
				my $cust_phno="";
				my $sticky_agent_flag=0;
				my $agentringstart=0;
				my $agentcallup=0;
				my $sticky_agent_id=0;
				my $skill_wt=0;
				my $agent_ext;
				my $custr1="";
				my $custr2="";
				my $custr3="";
				my $custr4="";
				my $cust_remove = "";
				my $skill_id=0;
				my $skill_name="";
				my $channel="";
				my $dialer_var_channel="";
				my $dialer_var_channel_id="";
				my $preview_fail=0;


				$session_id = substr($command_line[3],index($command_line[3],":") + 2);
				$channel = substr($command_line[5],index($command_line[5],":") + 2);
				$agent_id=substr($command_line[6],index($command_line[6],"/") + 1);
				$duration = substr($command_line[8],index($command_line[8],":") + 2);
				$disconnected_by=substr($command_line[9],index($command_line[9],":") + 2);
				$returnvar = substr($command_line[10],index($command_line[10],":") + 2);
				$campaign_type = substr($command_line[12],index($command_line[12],":") + 2);
				$ivrsPath=substr($command_line[11],index($command_line[11],":") + 2);
				$monitor_file_name = substr($command_line[13],index($command_line[13],":") + 2);
				$q_enter_time = substr($command_line[14],index($command_line[14],":") + 2);
				$q_leave_time = substr($command_line[15],index($command_line[15],":") + 2);
				$did_num =  substr($command_line[16],index($command_line[16],":") + 2);
				$CustUniqueId = substr($command_line[17],index($command_line[17],":") + 2);
				$skill_id= substr($command_line[18],index($command_line[18],":") + 2);
				$skill_wt= substr($command_line[19],index($command_line[19],":") + 2);
				$dialer_var = substr($command_line[20],index($command_line[20],":") + 2);
				$monitor_folder = substr($command_line[22],index($command_line[22],":") + 2);
				$monitor_sub_folder = substr($command_line[23],index($command_line[23],":") + 2);
				$ringstart = substr($command_line[24],index($command_line[24],":") + 2);
				$ringend = substr($command_line[25],index($command_line[25],":") + 2);
				$CallPicked = substr($command_line[26],index($command_line[26],":") + 2);
				$agentringstart = substr($command_line[27],index($command_line[27],":") + 2);
				$agentcallup = substr($command_line[28],index($command_line[28],":") + 2);
				$lingua=substr($command_line[29],index($command_line[29],":") + 2);
				$callcategory=substr($command_line[30],index($command_line[30],":") + 2);
				$cust_phno=substr($command_line[31],index($command_line[31],":") + 2);
				$sticky_agent_id=substr($command_line[33],index($command_line[33],"/") + 1);
				$sticky_agent_id=((defined($sticky_agent_id) && ($sticky_agent_id !~ /^$/ && $sticky_agent_id !~ /^[\s]+$/))?$sticky_agent_id:"0");
								

				$skill_id = ($skill_id==-1?"0":$skill_id);
				$link_date_time = $q_leave_time;
				$unlink_date_time = $q_leave_time + $duration;
				$link_end_date_time = $unlink_date_time;
				$campaign_name = substr($command_line[2],index($command_line[2],":") + 2);
				$disconnected_by = ($disconnected_by == 1?1:2);
				$campaign_type = ($campaign_type==0?"INBOUND":"OUTBOUND");
				$call_status="answered";
				$transfer_status ="";
				$transfer_field ="";
				$transfer_from="";
				$customer_name= "";
				$zap_channel="";

				if($campaign_name =~ /preview/) {
					$preview_flag=1;
					$campaign_name = substr($campaign_name,8);
				}

				if(defined($CallPicked) && $CallPicked) {
					$ringing_flag=2;
				}
				elsif(defined($ringstart) && $CallPicked == 0 )
				{
					$ringing_flag = 1;
				}

				if($ringstart==0 || $ringend==0){
					$ringstart ="'0000-00-00 00:00:00'";
					$ringend = "'0000-00-00 00:00:00'";
				}
				else{
					if ($preview_flag==1) {					
						if ($ringstart<$link_date_time) {
						$ringstart=$link_date_time;
						}
						if ($ringstart>$link_end_date_time) {
							$ringstart=$link_date_time;
						}
						if ($ringend>$link_end_date_time) {
							$ringend=$link_end_date_time;
						}
						$ring_time=$ringend-$ringstart;
						$ringstart = "from_unixtime('$ringstart')";
						$ringend = "from_unixtime('$ringend')";
					}
				}

				if($agentringstart==0){
					$agentringstart ="'0000-00-00 00:00:00'";
					$agentcallup = "'0000-00-00 00:00:00'";
				}
				else{
					$agentringstart = "from_unixtime('$agentringstart')";
					$agentcallup = "from_unixtime('$agentcallup')";
				}

				if($preview_flag==1 && $CallPicked==0) {
					$query="delete from callProgress where agent_id='$agent_id'";
					query_execute($query,$dbh,0,__LINE__);
				}

				if(defined($monitor_folder) && ($monitor_folder !~ /^$/ && $monitor_folder !~ /^[\s]+$/) && length($monitor_folder) > 2)
				{
					if($monitor_folder !~ /^\//) {
						$monitor_folder =  "/".$monitor_folder."/";
					 }
					if(!defined($monitor_sub_folder) or ($monitor_sub_folder =~ /^$/ && $monitor_sub_folder =~ /^[\s]+$/)) {
						if($monitor_folder !~ /\/$/) {
							$monitor_folder =  $monitor_folder."/";
						}
					}
				}

				if(defined($monitor_sub_folder) && ($monitor_sub_folder !~ /^$/ && $monitor_sub_folder !~ /^[\s]+$/)  && length($monitor_sub_folder) > 2)
				{
					if($monitor_sub_folder !~ /^\// && $monitor_folder !~ /\/$/) {
						$monitor_sub_folder =  "/".$monitor_sub_folder;
				}

				$monitor_folder =  $monitor_folder.$monitor_sub_folder;
				if($monitor_folder !~ /\/$/) {
					$monitor_folder =  $monitor_folder."/";
				}
				}

				if(!$campaign_type) {
					$query="select concurrent_calls from queue_live where session_id=$session_id";
					$retval = query_execute($query, $dbh, 1, __LINE__);
					$concurrent_call = @$retval[0];
				}

				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$custphno=((!defined ($cust_phno) || ($cust_phno =~ /^$/ || $cust_phno =~ /^[\s]+$/))?$variables[0]:$cust_phno);
					$lead_id=((defined($variables[1]) && ($variables[1] !~ /^$/ && $variables[1] !~ /^[\s]+$/))?$variables[1]:"0");
					$campaign_id=$variables[2];
					$list_id=((defined($variables[3]) && ($variables[3] !~ /^$/ && $variables[3] !~ /^[\s]+$/))?$variables[3]:"0");
					$strict=((defined($variables[4]) && ($variables[4] !~ /^$/ && $variables[4] !~ /^[\s]+$/))?$variables[4]:"0");
					$dialerType=((defined($variables[5]) && ($variables[5] !~ /^$/ && $variables[5] !~ /^[\s]+$/))?$variables[5]:"PROGRESSIVE");
					$transfer_from=$variables[6];
					$vdn_no=$variables[7];
					$vdn_transfer=$variables[8];
					$vdn_from=$variables[9];
					if(!defined($transfer_from))
					{
						$transfer_from="";
					}
					elsif($transfer_from =~ /Park/){
						@parkval=split(/:/,$transfer_from);
						$park_agent = $parkval[1];
						if ($agent_id == $park_agent) {
							$park_flag=1;
						}
					}
					@dialer_variables=split(/,/,$dialer_var);
					$phone_type = ((defined($dialer_variables[0]) && ($dialer_variables[0] !~ /^$/ && $dialer_variables[0] != /^[\s]+$/))?$dialer_variables[0]:"101");
					$lead_retry_count = ((defined($dialer_variables[1]) && ($dialer_variables[1] !~ /^$/ && $dialer_variables[1] != /^[\s]+$/))?$dialer_variables[1]:"0");
					$phone_retry_count = ((defined($dialer_variables[2]) && ($dialer_variables[2] !~ /^$/ && $dialer_variables[2] != /^[\s]+$/))?$dialer_variables[2]:"0");
					$next_call_time = ((defined($dialer_variables[3]) && ($dialer_variables[3] !~ /^$/ && $dialer_variables[3] != /^[\s]+$/))?$dialer_variables[3]:"0");
					$redial_flag= ((defined($dialer_variables[4]) && ($dialer_variables[4] !~ /^$/ && $dialer_variables[4] != /^[\s]+$/))?$dialer_variables[4]:"0");
					$call_back_live= ((defined($dialer_variables[5]) && ($dialer_variables[5] !~ /^$/ && $dialer_variables[5] != /^[\s]+$/))?$dialer_variables[5]:"0");
					$lead_attempt_count=((defined($dialer_variables[8]) && ($dialer_variables[8] !~ /^$/ && $dialer_variables[8]!= /^[\s]+$/))?$dialer_variables[8]:"0");
					$phone_attempt_count=((defined($dialer_variables[9]) && ($dialer_variables[9] !~ /^$/ && $dialer_variables[9]!= /^[\s]+$/))?$dialer_variables[9]:"0");
					$dialer_var_channel = ((defined($dialer_variables[10]) && ($dialer_variables[10] !~ /^$/ && $dialer_variables[10] !~ /^[\s]+$/))?$dialer_variables[10]:"");
					$dialer_var_channel_id = ((defined($dialer_variables[11]) && ($dialer_variables[11] !~ /^$/ && $dialer_variables[11] !~ /^[\s]+$/))?$dialer_variables[11]:"");
					$callerid=(defined($dialer_variables[16])?$dialer_variables[16]:"0");
					$per_day_mx_retry_count=((defined($dialer_variables[19]) && ($dialer_variables[19] !~ /^$/ && $dialer_variables[19]!= /^[\s]+$/))?$dialer_variables[19]:"0");

					
					if(defined($next_call_time) && ($next_call_time !~ /^$/ && $next_call_time!= /^[\s]+$/)){
						$call_back_live_re=1;
					}

					if(defined($transfer_from) && ($transfer_from !~ /^$/ && $transfer_from !~ /^[\s]+$/))
					{
						$vdn_transfer = "";
						if( $transfer_from eq "MEETME") {
							$transfer_from="";
							$transfer_status ="supervised_transfer";
							$transfer_field = ",transfer_status";
							$call_status = "answered";
							$meetmeflag = 1;
						}
					}
					$list_name="Manual";
				}
				else {
					$dialerType='PROGRESSIVE';
				}
				if (not exists $agentHash{$agent_id}) {
					populateAgent($agent_id,$dbh);
				}
				$agent_name = $agentHash{$agent_id};

				if($crm_license == 0) {
					$lead_id=0;
				}

				$query="select a.agent_id,a.session_id,a.campaign_id,a.list_id,a.list_name,a.cust_ph_no,a.link_date_time,now() as link_end_date_time,unix_timestamp()-unix_timestamp(a.link_date_time) as duration,a.channel,a.monitor_file_name,b.dialer_type,a.q_enter_time,a.q_leave_time,b.holdDuration,b.holdNumTime,f.cust_disposition,f.category,f.txt,a.transfer_from,a.transfer_to,a.provider_name,f.call_status,f.CustUniqueId,f.customer_sentiment_name,a.lead_id,unix_timestamp(b.holdTimestamp),b.ip,a.monitor_file_path,b.wait_time,b.agent_ext,b.preview_fail from call_dial_status as a left join agent_live as b on (a.agent_id=b.agent_id) left join crm_hangup_live as f on (f.agent_id=a.agent_id) where a.session_id=$session_id and a.agent_id='$agent_id'";
				$retval=query_execute($query,$dbh,1,__LINE__);
				$campaign_id= @$retval[2];
				$list_id= (defined(@$retval[3])?@$retval[3]:"0");
                $list_name= (defined(@$retval[4])?@$retval[4]:"");
                $custphno=((!defined ($cust_phno) || ($cust_phno =~ /^$/ || $cust_phno =~ /^[\s]+$/))?@$retval[5]:$cust_phno);
				$hold_time= (defined(@$retval[14])?@$retval[14]:"0");
				$hold_num_time= (defined(@$retval[15])?@$retval[15]:"0");
				$cust_disposition= ((defined(@$retval[16]) && (@$retval[16] !~ /^$/ && @$retval[16] !~ /^[\s]+$/))?@$retval[16]:"None");
				$cust_category=((defined(@$retval[17]) && (@$retval[17] !~ /^$/ && @$retval[17] !~ /^[\s]+$/))?@$retval[17]:"Not Assigned");
				$remarks= (defined(@$retval[18])?@$retval[18]:"");
				$transfer_to= (defined(@$retval[20])?@$retval[20]:"");
                $customer_sentiment_name=((defined(@$retval[24]) && (@$retval[24] !~ /^$/ && @$retval[24] !~ /^[\s]+$/))?@$retval[24]:"None");
                $lead_id=@$retval[25];
				$wrapupTime=0;
				$hold_timestamp=@$retval[26];
				$non_desktop_ip=@$retval[27];
				$wait_time=(defined(@$retval[29])?@$retval[29]:"0");
				$agent_ext=(defined(@$retval[30])?@$retval[30]:"");
				if(!defined($custphno) or ($custphno =~ /^$/ && $custphno =~ /^[\s]+$/)){
					$custphno= @$retval[5];
				}

				if(!defined($CustUniqueId) or ($CustUniqueId =~ /^$/ && $CustUniqueId =~ /^[\s]+$/)){
					$CustUniqueId=(defined(@$retval[23])?@$retval[23]:"");
				}
				$preview_fail=(defined(@$retval[31])?@$retval[31]:0);
				$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");


				if($hold_timestamp) {
					$hold_num_time=$hold_num_time;
					$hold_time=$hold_time + ($timestamp - $hold_timestamp);
					
					if ($preview_flag=1 && $hold_time != 0) {
						if ($duration < $ring_time+$hold_time) {
							$hold_time = ($duration - $ring_time);
						}
						$hold_time = (($hold_time < 0)?0:$hold_time);
					}
				}

				if(!defined($transfer_status) || ($transfer_status =~ /^$/ || $transfer_status =~ /^[\s]+$/))
				{
					if(defined($transfer_to) && ($transfer_to !~ /^$/ && $transfer_to !~ /^[\s]+$/))
					{
						$transfer_status=$transfer_to;
						$call_status="transfer";
					}
				}
				if($transfer_to =~ /FeedBack/){
					$call_status="answered";
				}

				if(defined($transfer_from) && ($transfer_from !~ /^$/ && $transfer_from !~ /^[\s]+$/))
				{
					if( $transfer_from ne "MEETME") {
						$campaign_id = $campaignNameHash{$campaign_name};
					}
				}
				if((defined($vdn_transfer) && ($vdn_transfer !~ /^$/ && $vdn_transfer !~ /^[\s]+$/)) && $preview_flag )
				{
					$transfer_from="";
					$custphno=(defined(@$retval[5])?@$retval[5]:$cust_phno);
				}

				elsif(defined($vdn_transfer) && ($vdn_transfer !~ /^$/ && $vdn_transfer !~ /^[\s]+$/))
				{
					$transfer_from="$vdn_from";
					$remarks=$remarks."VDN Transfer";
					$dialerType='PROGRESSIVE';
					$custphno=(defined(@$retval[5])?@$retval[5]:$cust_phno);
				}

				
				if(!defined($remarks) || ($remarks =~ /^$/ || $remarks =~ /^[\s]+$/)) {
					$remarks="";
				}

				if (not exists $campaignNameHash{$campaign_name}) {
					populateCampaign($campaign_name,$dbh,'1');
				}
				$campaign_id = $campaignNameHash{$campaign_name};

				if($monitor_file_name =~ /^$/ || $monitor_file_name =~ /^[\s]+$/) {
					if(@$retval[10] !~ /^$/ && @$retval[10] !~ /^[\s]+$/) {
						$monitor_file_name=@$retval[10];
						$monitor_folder = @$retval[27];
					}
				}

				if($monitor_file_name !~ /^$/ && $monitor_file_name !~ /^[\s]+$/) {
					if($fileFormatHash{$campaign_id} == 1) {
						$monitor_file_name =$monitor_file_name.".mp3";
					}
					else {
						$monitor_file_name =$monitor_file_name.".wav";
					}
					$dialer_inserted_field=0;
				}
				else{
					$dialer_inserted_field=0;
				}

				if($non_desktop_ip eq '0.0.0.0')
				{
					if((defined($dialer_var) && ($dialer_var !~ /^$/ && $dialer_var !~ /^[\s]+$/)) && $lead_id > 0 && $list_id > 0)
					{
						setDisposition($dbh,$lead_id,$campaign_id,$list_id,$dialer_var,"answered",0,$custphno);
					}
				}

				if(!defined ($transfer_from) || ($transfer_from =~ /^$/ || $transfer_from =~ /^[\s]+$/)) 
				{
					if (not exists $sticky_campaignhash{$campaign_id}) {
						populateCampaign($campaign_id,$dbh,'0');
					}
					$sticky_agent_flag  = $sticky_campaignhash{$campaign_id};
				}

				if(defined($sticky_agent_flag) && $sticky_agent_flag > 0){
					$query = "select agent_id from sticky_agent where customer_number = '$custphno'";
					$retval = query_execute($query, $dbh, 1, __LINE__);
					$sticky_agent_id = @$retval[0];

					if(!defined($sticky_agent_id) || ($sticky_agent_id =~ /^$/ || $sticky_agent_id =~ /^[\s]+$/))
					{
						$query = "insert into sticky_agent (agent_id,campaign_id,campaign_name,customer_name,customer_number) values('$agent_id','$campaign_id','$campaign_name','$customer_name','$custphno')";
						query_execute($query,$dbh,0,__LINE__);
					}
					if(($sticky_agent_flag == 2) && ($sticky_agent_id != $agent_id) && (defined($sticky_agent_id) && ($sticky_agent_id !~ /^$/ && $sticky_agent_id !~ /^[\s]+$/)))
					{
						$query = "update sticky_agent set agent_id='$agent_id' where customer_number='$custphno'";
						query_execute($query,$dbh,0,__LINE__);

					}
				}

				if($lead_id)
				{
					$query="select name from $cust_remove where lead_id='$lead_id'";
					$retval=query_execute($query,$dbh,1,__LINE__);
					$customer_name=(defined(@$retval[0])?@$retval[0]:"");
					if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/))
					{
						$customer_name =~ s/\'/\\'/g;
					}

					if($campaign_type eq "OUTBOUND")
					{
						$lead_retry_count=$lead_retry_count+1;
						$phone_retry_count=$phone_retry_count+1;
					}
					$lead_attempt_count=$lead_attempt_count+1;
					$phone_attempt_count=$phone_attempt_count+1;
					$per_day_mx_retry_count=$per_day_mx_retry_count+1;
				}

				if(defined($skill_id) && ($skill_id !~ /^$/ && $skill_id !~ /^[\s]+$/) && $skill_id > 0)
				{
					if (not exists($campaignSkillHash{$skill_id."_".$campaign_id})) {
						populateSkill($dbh);
					}
					$skill_name=$campaignSkillHash{$skill_id."_".$campaign_id};
				}

				if($monitor_file_name !~ /^$/ && $monitor_file_name !~ /^[\s]+$/) {
					my $new_monitor_flag =0;
					if (not exists $new_monitor_flagHash{$campaign_id}) {
						populateCampaign($campaign_id,$dbh,'0');
					}
					$new_monitor_flag  = $new_monitor_flagHash{$campaign_id};

					if($new_monitor_flag == 1)
					{
						$new_monitor_filename = MakeNewMonitorFileName ($dbh,$lead_id,$campaign_id,$list_id,$agent_id,$session_id,$campaign_type,$dialerType,$call_status,$campaign_name,$custphno,$list_name,$CustUniqueId,$lead_attempt_count,$phone_attempt_count,$timestamp);
					}
				}

				if (not exists $cust_reporting_flagHash{$campaign_id}) {
					  populateCampaign($campaign_id,$dbh,'0');
				}
				$cust_reporting = $cust_reporting_flagHash{$campaign_id};

				if($cust_reporting == 1)
                {   
					my $cust_reporting_str="";
					$cust_reporting_str = MakecustFileName ($dbh,$lead_id,$campaign_id,$list_id,$agent_id,$session_id,$campaign_type,$dialerType,$call_status,$campaign_name,$custphno,$list_name,$CustUniqueId,$lead_attempt_count,$phone_attempt_count,$timestamp);
				    if(defined($cust_reporting_str) && ($cust_reporting_str !~ /^$/ && $cust_reporting_str !~ /^[\s]+$/)){
						my @accrf=();
						@accrf=split(/_/,$cust_reporting_str);
						$custr1 = $accrf[0];
						$custr2 = $accrf[1];
						$custr3 = $accrf[2];
						$custr4 = $accrf[3];
					}

				}

				if(defined($vdn_transfer) && ($vdn_transfer !~ /^$/ && $vdn_transfer !~ /^[\s]+$/) && $call_status ne "transfer"){
					$campaign_type='INBOUND';
					$dialerType='PROGRESSIVE';
					$custphno=$vdn_no;
				}

				if(defined($ringing_flag) && $ringing_flag) {
					$query="select miss_agent_id from missed_call_status where session_id=$session_id";
					$retval = query_execute($query, $dbh, 1, __LINE__);
					if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/)){
						my $miss_agent_id = @$retval[0];
						$remarks=$remarks."Missed Call ($miss_agent_id)";

						$query="update crm_live set txt='$remarks'  where agent_id='$agent_id' and session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);

						$query="delete from missed_call_status where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);
					}
				}

# if there is a timediff between queue enter and leave for less than eq 2 sec then set both the time same.
				$q_enter_time = (($q_leave_time-$q_enter_time <= 2)?$q_leave_time:$q_enter_time);

				if($wait_time < 0 || $wait_time > 10000) {
					$wait_time=0;
				}

				$query="select park_start_time,park_end_time from park_live where session_id=$session_id";
				$retval = query_execute($query, $dbh, 1, __LINE__);
				if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/)){
					$park_start_time=@$retval[0];
					$park_end_time=@$retval[1];
				}

				if(defined($dialer_var_channel_id) && ($dialer_var_channel_id !~ /^$/ && $dialer_var_channel_id !~ /^[\s]+$/))
				{
					$channel = $dialer_var_channel;
					$zap_channel = $dialer_var_channel_id;

					if(($channel =~ /Zap/i)) {
						$zap_channel =~ s/ZAP/Zap/g;
						if($zap_channel)
						{
							if (not exists($providernameHash{$zap_channel})) {
								populateprovider($dbh);
							}
							$provider_name=$providernameHash{$zap_channel};
						}
						$channel="ZAP";
					}
					elsif(($channel =~ /SIP/i)) {
						if($zap_channel){
							if (not exists($sip_id_providernameHash{$zap_channel}))
							{
								sip_id_populateprovider($dbh);
							}
							$provider_name=$sip_id_providernameHash{$zap_channel};
						}
						$channel = "SIP";
					}
				}
				elsif(($channel =~ /Zap/i)) {
					$zap_channel=substr($channel,0,index($channel,"-"));
					$zap_channel =~ s/ZAP/Zap/g;
					if($zap_channel)
					{
						if (not exists($providernameHash{$zap_channel})) {
							populateprovider($dbh);
						}
						$provider_name=$providernameHash{$zap_channel};
					}
					$channel="ZAP";
				}
				elsif(($channel =~ /SIP/i)) {
					$zap_channel=substr($channel,index($channel,"/")+1);
					$zap_channel=substr($zap_channel,0,index($zap_channel,"-"));
					if(match_ip($zap_channel)){
						if (not exists($sip_providernameHash{$zap_channel}))
						{
							sip_populateprovider($dbh);
						}
						$provider_name=$sip_providernameHash{$zap_channel};
					}
					else{
						$provider_name=$zap_channel;
					}
					$zap_channel=$channel;
					$channel = "SIP";
				}
				elsif(($channel =~ /Local/i))
				{
					  $zap_channel=$channel;
					  $provider_name="Local";
					  $channel = "Local";
				}
				else
				{
					$zap_channel=$channel;
					$channel = "SIP";
				}

				$report_id='';
				$report_query="insert into $table_name (node_id,lead_id,agent_id,agent_ext,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,campaign_type,campaign_channel,zap_channel,monitor_filename,new_monitor_filename,dialer_type,cust_disposition,q_enter_time,q_leave_time,hold_time,hold_num_time,call_status_disposition,cust_category,customer_sentiment_name,call_remarks,transfer_status,transfer_from,provider_name,call_charges,skills,did_num,CustUniqueId,redial_flag,callback_flag,monitor_file_path,disconnected_by,concurrent_calls,next_call_time,entrytime,ph_type,wait_time,ivrs_path,ringstart_time,ringend_time,callpicked,agent_ringstart,agent_ringend,park_start_time,park_end_time,lead_attempt_count,phone_attempt_count,lead_total_max_retry,ph_max_retry,ringing_flag,caller_id,dialer_inserted_field,language,callcategory,sticky_agent_id,skill_wt,cust_rp1,cust_rp2,cust_rp3,cust_rp4) values ('$node_id','$lead_id','$agent_id','$agent_ext','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name',from_unixtime('$link_date_time'),from_unixtime('$link_end_date_time'),'$duration','$campaign_type','$channel','$zap_channel','$monitor_file_name','$new_monitor_filename','$dialerType','$cust_disposition',from_unixtime('$q_enter_time'),from_unixtime('$q_leave_time'),'$hold_time','$hold_num_time','$call_status','$cust_category','$customer_sentiment_name','$remarks','$transfer_status','$transfer_from','$provider_name','$unit_cost','$skill_name','$did_num','$CustUniqueId','$redial_flag','$call_back_live_re','$monitor_folder','$disconnected_by','$concurrent_call','$next_call_time','$link_date_time','$phone_type','$wait_time','$ivrsPath',$ringstart,$ringend,'$CallPicked',$agentringstart,$agentcallup,'$park_start_time','$park_end_time','$lead_attempt_count','$phone_attempt_count','$lead_retry_count','$phone_retry_count','$ringing_flag','$callerid','$dialer_inserted_field','$lingua','$callcategory','$sticky_agent_id','$skill_wt','$custr1','$custr2','$custr3','$custr4')";

				$returnvar="";

#$currentReport_semaphore->down;
###---###$query="select 4 from current_report where agent_id='$agent_id' and session_id=$session_id and call_start_date_time='$link_date_time'";
				$query="select call_status_disposition from current_report where agent_id='$agent_id' and session_id=$session_id";
				$returnvar=query_execute($query,$dbh,1,__LINE__);
#if entry doesnot exist in the report table then insert it otherwise don't
				if(!defined (@$returnvar[0]))
				{
					$report_id=query_execute($report_query,$dbh,3,__LINE__);
#---Due to auto increment in report id we need to this again--
					$report_query="insert into $table_name (report_id,node_id,lead_id,agent_id,agent_ext,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,campaign_type,campaign_channel,zap_channel,monitor_filename,new_monitor_filename,dialer_type,cust_disposition,q_enter_time,q_leave_time,hold_time,hold_num_time,call_status_disposition,cust_category,customer_sentiment_name,call_remarks,transfer_status,transfer_from,provider_name,call_charges,skills,did_num,CustUniqueId,redial_flag,callback_flag,monitor_file_path,disconnected_by,concurrent_calls,next_call_time,entrytime,ph_type,wait_time,ivrs_path,ringstart_time,ringend_time,callpicked,agent_ringstart,agent_ringend,park_start_time,park_end_time,lead_attempt_count,phone_attempt_count,lead_total_max_retry,ph_max_retry,ringing_flag,caller_id,dialer_inserted_field,language,callcategory,sticky_agent_id,skill_wt,cust_rp1,cust_rp2,cust_rp3,cust_rp4) values ('$report_id','$node_id','$lead_id','$agent_id','$agent_ext','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name',from_unixtime('$link_date_time'),from_unixtime('$link_end_date_time'),'$duration','$campaign_type','$channel','$zap_channel','$monitor_file_name','$new_monitor_filename','$dialerType','$cust_disposition',from_unixtime('$q_enter_time'),from_unixtime('$q_leave_time'),'$hold_time','$hold_num_time','$call_status','$cust_category','$customer_sentiment_name','$remarks','$transfer_status','$transfer_from','$provider_name','$unit_cost','$skill_name','$did_num','$CustUniqueId','$redial_flag','$call_back_live_re','$monitor_folder','$disconnected_by','$concurrent_call','$next_call_time','$link_date_time','$phone_type','$wait_time','$ivrsPath',$ringstart,$ringend,'$CallPicked',$agentringstart,$agentcallup,'$park_start_time','$park_end_time','$lead_attempt_count','$phone_attempt_count','$lead_retry_count','$phone_retry_count','$ringing_flag','$callerid','$dialer_inserted_field','$lingua','$callcategory','$sticky_agent_id','$skill_wt','$custr1','$custr2','$custr3','$custr4')";
#Adding information to current report
					check_cview($report_query,$dbh,$table_name,1);
					$report_query =~ s/$table_name/current_report/i;
					query_execute($report_query,$dbh,0,__LINE__);
				}
				elsif(@$returnvar[0] eq "noans" && $preview_fail == '1')
				{
					$report_query ="update $table_name set lead_id='$lead_id',agent_id='$agent_id',agent_name='$agent_name',campaign_id='$campaign_id',campaign_name='$campaign_name',list_id='$list_id',list_name='$list_name',cust_ph_no='$custphno',cust_name='$customer_name',call_start_date_time=from_unixtime('$link_date_time'),call_end_date_time=from_unixtime('$link_end_date_time'),call_duration='$duration',campaign_type='$campaign_type',campaign_channel='$channel',zap_channel='$zap_channel',monitor_filename='$monitor_file_name',new_monitor_filename='$new_monitor_filename',dialer_type='$dialerType',cust_disposition='$cust_disposition',q_enter_time=from_unixtime('$q_enter_time'),q_leave_time=from_unixtime('$q_leave_time'),hold_time='$hold_time',hold_num_time='$hold_num_time',call_status_disposition='$call_status',cust_category='$cust_category',call_remarks='$remarks',transfer_status='$transfer_status',transfer_from='$transfer_from',provider_name='$provider_name',call_charges='$unit_cost',skills='$skill_name',did_num='$did_num',CustUniqueId='$CustUniqueId',redial_flag='$redial_flag',callback_flag='$call_back_live_re',monitor_file_path='$monitor_folder',disconnected_by='$disconnected_by',concurrent_calls='$concurrent_call',next_call_time='$next_call_time',entrytime='$link_date_time',ph_type='$phone_type',wait_time='$wait_time',ivrs_path='$ivrsPath',ringstart_time=$ringstart,ringend_time=$ringend,callpicked='$CallPicked',lead_attempt_count='$lead_attempt_count',phone_attempt_count='$phone_attempt_count',lead_total_max_retry='$lead_retry_count',ph_max_retry='$phone_retry_count',ringing_flag='$ringing_flag',caller_id='$callerid',dialer_inserted_field='$dialer_inserted_field',agent_ringstart=$agentringstart,agent_ringend=$agentcallup,language='$lingua',callcategory='$callcategory',sticky_agent_id='$sticky_agent_id',skill_wt='$skill_wt',agent_ext='$agent_ext',customer_sentiment_name='$customer_sentiment_name',cust_rp1='$custr1',cust_rp2='$custr2',cust_rp3='$custr3',cust_rp4='$custr4' where session_id=$session_id";
					query_execute($report_query,$dbh,0,__LINE__);

#Adding information to current report
					check_cview($report_query,$dbh,$table_name,1);
					$report_query =~ s/$table_name/current_report/i;
					query_execute($report_query,$dbh,0,__LINE__);
				}
#$currentReport_semaphore->up;

#Check Wrap Time
				if((defined($transfer_from) && ($transfer_from !~ /^$/ && $transfer_from !~ /^[\s]+$/)) && $park_flag == '0') {
					if (not exists $campaignScreenHash{$campaign_id}) {
						populateCampaign($campaign_id,$dbh,'0');
					}
					if($campaignScreenHash{$campaign_id}){
						$transfer_lead_id=",last_lead_id=0";
					}
				}

				if (not exists $campaigntype{$campaign_id}) {
					populateCampaign($campaign_id,$dbh,'0');
				}
				$campaigntype = $campaigntype{$campaign_id};

				if(!$preview_flag  && $campaign_type ne "INBOUND") {
					if(defined($wrapupTime) && ($wrapupTime < 15) && ($wrapupTime != 0))
					{
						$query="update agent_live set agent_state='READY',closer_time='$timestamp',holdDuration='0',holdNumTime='0',holdTimeInterval='',holdTimestamp='',last_activity_time=now(),call_counter=call_counter+1$transfer_lead_id,is_hold='0',call_back_live='0',is_transfer='0',wait_time=unix_timestamp(),wait_duration=wait_duration + $wait_time,ringing_flag='$ringing_flag' where agent_id='$agent_id' and agent_state='INCALL'";
						$retval = query_execute($query,$dbh,2,__LINE__);
						if (defined $retval && $retval > 0)
						{
#Mark the state of agent READY
							$wrapup_semaphore->down;
							my @tmp_arr=();
							@tmp_arr=split(",",$agent_wrapup{$agent_id});
							$tmp_arr[5]="READY";
							$tmp_arr[6]=$timestamp;         #disc time
							$tmp_arr[7]=$timestamp;         #state change time
							$agent_wrapup{$agent_id}=join(",",@tmp_arr);
							$wrapup_semaphore->up;
							undef(@tmp_arr);
						}
					}
					else
					{
						$query="update agent_live set agent_state='CLOSURE',closer_time='$timestamp',holdDuration='0',holdNumTime='0',holdTimeInterval='',holdTimestamp='',last_activity_time=now(),call_counter=call_counter+1$transfer_lead_id,is_hold='0',call_back_live='0',is_transfer='0',wait_time=unix_timestamp(),wait_duration=wait_duration + $wait_time ,ringing_flag='$ringing_flag'  where agent_id='$agent_id' and agent_state='INCALL'";
						$retval = query_execute($query,$dbh,2,__LINE__);
						if (defined $retval && $retval > 0)
						{
#Mark the state of agent CLOSURE
							$wrapup_semaphore->down;
							my @tmp_arr=();
							@tmp_arr=split(",",$agent_wrapup{$agent_id});
							$tmp_arr[5]="CLOSURE";
							$tmp_arr[6]=$timestamp;
							$tmp_arr[7]=$timestamp;
							$agent_wrapup{$agent_id}=join(",",@tmp_arr);
							$setmefree_hit[$agent_id]=0;
							$wrapup_semaphore->up;
							undef(@tmp_arr);
						}
					}
				}
				else {
					$query="update agent_live set agent_state='CLOSURE',closer_time='$timestamp',holdDuration='0',holdNumTime='0',holdTimeInterval='',holdTimestamp='',last_activity_time=now(),call_counter=call_counter+1$transfer_lead_id,is_hold='0',call_back_live='0',is_transfer='0',wait_time=unix_timestamp(),wait_duration=wait_duration + $wait_time,ringing_flag='$ringing_flag' where agent_id='$agent_id'";
					query_execute($query,$dbh,2,__LINE__);
				}
#####################POST REPORTING ACTIVITIES ON DISCONNETION OF CALL#####################
#insert an entry in unmerged_snd_files table
				if($monitor_file_name !~ /^$/ && $monitor_file_name !~ /^[\s]+$/) {
					$query="insert into unmerged_snd_files(monitor_filename,new_monitor_filename,monitor_file_path) values ('$monitor_file_name','$new_monitor_filename','$monitor_folder')";
					query_execute($query,$dbh,0,__LINE__);
				}


				if($crm_license == 0)   #if unlink is not parsed
				{
					$returnvar = "";
					$query="select lead_id from call_dial_status where session_id=$session_id";
					$returnvar = query_execute($query,$dbh,1,__LINE__);
					if(defined(@$returnvar[0]) && (@$returnvar[0] !~ /^$/ && @$returnvar[0] !~ /^[\s]+$/))
					{
						$query="delete from $cust_remove where lead_id ='@$returnvar[0]'";
						query_execute($query,$dbh,0,__LINE__);

						$query="delete from dial_Lead where lead_id ='@$returnvar[0]'";
						query_execute($query,$dbh,0,__LINE__);

						$query="delete from dial_Lead_lookup_$campaign_id where lead_id='@$returnvar[0]'";
						query_execute($query,$dbh,0,__LINE__);

						$query="delete from extended_customer_$campaign_id where lead_id='@$returnvar[0]'";
						query_execute($query,$dbh,0,__LINE__);
					}
				}

				$query="update crm_hangup_live set lead_id='',txt='',call_status='',session_id='0.0000000',cust_disposition='',next_call_time='0',CustUniqueId='0',category='',next_action_set='',customer_sentiment_name='' where agent_id='$agent_id' and session_id=$session_id";
				query_execute($query,$dbh,0,__LINE__);

				$query="delete from missed_call_status where session_id=$session_id";
				query_execute($query,$dbh,0,__LINE__);

#delete the record from call_dial_status after inserting in report table
				$query="delete from call_dial_status where agent_id='$agent_id' and session_id=$session_id";
				query_execute($query,$dbh,0,__LINE__);

				$query="delete from park_live where session_id=$session_id";
				query_execute($query, $dbh,0, __LINE__);

				if($crm_license && $lead_id) {
					$query="select 4 from sess_history where lead_id='$lead_id'";
					$returnvar=query_execute($query,$dbh,1,__LINE__);
					if(!defined (@$returnvar[0]))
					{
						$query = "insert into sess_history (lead_id,agent_id,campaign_id,session_id,link_time) values ('$lead_id','$agent_id','$campaign_id','$session_id','$link_date_time')";
						query_execute($query,$dbh,0,__LINE__);
					}
					else {
						$query = "update sess_history set session_id='$session_id',link_time='$link_date_time' where lead_id='$lead_id'";
						query_execute($query,$dbh,0,__LINE__);
					}

					$query="select 4 from recent_leads where lead_id='$lead_id'";
					$returnvar=query_execute($query,$dbh,1,__LINE__);
					if(!defined (@$returnvar[0]))
					{
						$query = "insert into recent_leads (agent_id,lead_id,session_id,link_time,cust_ph_no,name,ph_type) values ('$agent_id','$lead_id','$session_id','$time','$custphno','$customer_name','$phone_type')";
						query_execute($query,$dbh,0,__LINE__);
					}
					else {
						$query = "update recent_leads set agent_id='$agent_id',session_id='$session_id',link_time='$time',cust_ph_no='$custphno',name='$customer_name',ph_type='$phone_type' where lead_id='$lead_id'";
						query_execute($query,$dbh,0,__LINE__);
					}

				}

				if($channel =~ /ZAP/i) {
					$query="update zap_live set agent_id='',connect_time='',campaign_id='',context='' where zap_id='$zap_channel'";
					query_execute($query,$dbh,0,__LINE__);
				}

				init_stateHash($session_id);
				$stateHash_semaphore->down;
				$stateHash{$session_id} = $stateHash{$session_id} | (1 << 5);
				$stateHash_semaphore->up;
#####################POST REPORTING ENDS######################################################
			}
##############AgentComplete######################################

######################Deskless_Disposition Start###############################################
			elsif($thread_type == 11 && ($command_line[0] =~ /Event: Deskless_Disposition/))
			{
				my $session_id='';
				my $caller_id='';
				my $data;
				my $agent_id='';
				my $agent_name='';
				my $campaign_name='';
				my $ivrspath="";
				my $skill_id;
				my $chan_var="";
				my $cust_disposition="";

				$caller_id = substr($command_line[4],index($command_line[4],":")+2);
				$data = substr($command_line[6],index($command_line[6],":")+2);
				$chan_var =  substr($command_line[7],index($command_line[7],":")+2);
				$ivrspath = substr($command_line[9],index($command_line[9],":")+2);
				$skill_id = substr($command_line[10],index($command_line[10],":")+2);

				my @splited_id = split("##",$data);

				$campaign_name=$splited_id[0];
				$agent_id = $splited_id[1];
				$cust_disposition = (defined($splited_id[2])?$splited_id[2]:"None");
				$session_id=$splited_id[3];
				
				$query = "update $table_name set cust_disposition='$cust_disposition' where agent_id ='$agent_id' and campaign_name='$campaign_name' and session_id=$session_id";
				query_execute($query,$dbh,0,__LINE__);
				
				$query =~ s/$table_name/current_report/i;
				query_execute($query,$dbh,0,__LINE__);			
			}
######################Deskless_Disposition End ################################################

########################ParkedExit Start#######################################################
			elsif(($thread_type == 14) && ($command_line[0] =~ m/^Event: ParkedExit$/))
			{
				my $channel= substr($command_line[2],index($command_line[2],":") + 2);
				my $parkid= substr($command_line[3],index($command_line[3],":") + 2);
				my $campaign_name= substr($command_line[4],index($command_line[4],":") + 2);
				my $session_id = substr($command_line[5],index($command_line[5],":") + 2);
				my $returnvar=substr($command_line[7],index($command_line[7],":") + 2);
				my $park_start_time=substr($command_line[9],index($command_line[9],":") + 2);
				my $park_end_time=substr($command_line[10],index($command_line[10],":") + 2);

				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$custphno=$variables[0];
					$lead_id=$variables[1];
					$campaign_id=$variables[2];
					$list_id=$variables[3];
				}

				$query = "select dialer_type from agent_live where agent_id='$parkid'";
				my $result=query_execute($query,$dbh,1,__LINE__);
				my $in_conf_agent_dialer_type = @$result[0];
				if($in_conf_agent_dialer_type !~ /preview/i)
				{
					my $shared_key = $parkid."##".$campaign_name;
					$sendTn_semaphore->down;
					$sendTnHash{$shared_key} = "unpause1";
					$sendTn_semaphore->up;
				}

				$query="insert into park_live(park_id,campaign_name,campaign_id,session_id,channel,phone_no,lead_id,park_start_time,park_end_time) values ('$parkid','$campaign_name','$campaign_id','$session_id','$channel','$custphno','$lead_id','$park_start_time','$park_end_time')";
				query_execute($query,$dbh,0,__LINE__);

				$query="delete from call_park where session_id=$session_id";
				query_execute($query, $dbh,0, __LINE__);
			}
########################ParkedExit End###################################################

########################Parked End#######################################################
			elsif(($thread_type == 14) && ($command_line[0] =~ m/^Event: Parked$/))
			{
				my $customer_name="";
				my $lead_id=0;
				my $custphno;
				my $list_id;
				my $campaign_id;
				my $cust_remove="";
				my @variables=();
				my $channel = substr($command_line[2],index($command_line[2],":") + 2);
				my $session_id = substr($command_line[3],index($command_line[3],":") + 2);
				my $parkid=substr($command_line[4],index($command_line[4],":") + 2);
				my $campaign_name=substr($command_line[5],index($command_line[5],":") + 2);
				my $phno=substr($command_line[8],index($command_line[8],":") + 2);
				my $returnvar=substr($command_line[10],index($command_line[10],":") + 2);
				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$custphno=$variables[0];
					$lead_id=$variables[1];
					$campaign_id=$variables[2];
					$list_id=$variables[3];
				}
				$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");



				if($lead_id)
				{
					$query="select name from $cust_remove where lead_id='$lead_id' and list_id='$list_id' ";
					my $retval=query_execute($query,$dbh,1,__LINE__);
					$customer_name=(defined(@$retval[0])?@$retval[0]:"");

					if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/))
					{
						$customer_name =~ s/\'/\\'/g;
					}
				}

				if($campaign_name =~ /preview/)
				{
					$campaign_name = substr($campaign_name,8);
				}


				$query="insert into call_park(park_id,campaign_name,campaign_id,session_id,channel,phone_no,lead_id,customer_name,park_entry_time) values ('$parkid','$campaign_name','$campaign_id','$session_id','$channel','$phno','$lead_id','$customer_name',unix_timestamp())";
				query_execute($query,$dbh,0,__LINE__);
				undef(@variables);
			}
########################Parked End#######################################################

########################ParkedTimeout Start#######################################################
			elsif(($thread_type == 14) && ($command_line[0] =~ m/^Event: ParkedTimeout$/))
			{
				my $channel= substr($command_line[2],index($command_line[2],":") + 2);
				my $parkid= substr($command_line[4],index($command_line[4],":") + 2);
				my $campaign_name= substr($command_line[5],index($command_line[5],":") + 2);
				my $session_id = substr($command_line[3],index($command_line[3],":") + 2);
				my $returnvar=substr($command_line[8],index($command_line[8],":") + 2);
				my $park_start_time=substr($command_line[6],index($command_line[6],":") + 2);
				my $park_end_time=substr($command_line[7],index($command_line[7],":") + 2);

				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$custphno=$variables[0];
					$lead_id=$variables[1];
					$campaign_id=$variables[2];
					$list_id=$variables[3];
				}

				$query = "select dialer_type from agent_live where agent_id='$parkid'";
				my $result=query_execute($query,$dbh,1,__LINE__);
				my $in_conf_agent_dialer_type = @$result[0];

				if($in_conf_agent_dialer_type !~ /preview/i)
				{
					my $shared_key = $parkid."##".$campaign_name;
					$sendTn_semaphore->down;
					$sendTnHash{$shared_key} = "unpause1";
					$sendTn_semaphore->up;
				}

				$query="insert into park_live(park_id,campaign_name,campaign_id,session_id,channel,phone_no,lead_id,park_start_time,park_end_time) values ('$parkid','$campaign_name','$campaign_id','$session_id','$channel','$custphno','$lead_id','$park_start_time','$park_end_time')";
				query_execute($query,$dbh,0,__LINE__);

				$query="delete from call_park where session_id=$session_id";
				query_execute($query, $dbh,0, __LINE__);
			}
########################ParkedTimeout Ends#######################################################

########################ParkedAbandon Start#######################################################
	elsif(($thread_type == 14) && ($command_line[0] =~ m/^Event: ParkedAbandon$/ || $command_line[0] =~ m/^Event: ParkedDTMFExit$/))
	{
		my $call_type = 0;
		my $preview_call = 0;
		my $monitor_file_name ="";
		my $new_monitor_filename="";
		my $custphno="";
		my $lead_id="";
		my $list_id="";
		my $strict_flag=0;
		my $dialerType="";
		my $transfer_from="";
		my $transfer_flag=0;
		my $transfer_status = 0;
		my $provider_name="";
		my $dialer_inserted_field=0;
		my $call_status="";
		my $skill_id=0;
		my $did_num=0;
		my $CustUniqueId=0;
		my $redial_flag=0;
		my $call_back_live=0;
		my $concurrent_call=0;
		my $nc_time=0;
		my $phone_type="101";
		my $lead_retry_count = "0";
		my $phone_retry_count = "0";
		my $lead_attempt_count= "0";
		my $phone_attempt_count = "0";
		my $dialer_remarks = "";
		my $ringing_flag=0;
		my $callerid="";
		my $list_name;
		my $cust_remove="";
		my $skill_name="";
		my @variables=();

		my $returnvar = substr($command_line[8],index($command_line[8],":") + 2);
		my $agent_id = substr($command_line[4],index($command_line[4],":") + 2);
		my $session_id = substr($command_line[3],index($command_line[3],":") + 2);
		my $park_start_time = substr($command_line[6],index($command_line[6],":") + 2);
		my $park_end_time = substr($command_line[7],index($command_line[7],":") + 2);
		my $channel = substr($command_line[2],index($command_line[2],":") + 2);
		my $campaign_name = substr($command_line[5],index($command_line[5],":") + 2);
		my $link_date_time = $park_start_time;
		my $link_end_date_time = $park_end_time;
		my $duration=$park_end_time - $park_start_time;

           if($command_line[0] =~ m/^Event: ParkedAbandon$/)
		   {
				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$custphno=$variables[0];
					$lead_id=$variables[1];
					$list_id=$variables[3];
					$strict_flag=$variables[4];
					$dialerType =$variables[5];
					$transfer_from=$variables[6];
					$transfer_flag = (defined($variables[6])?1:0);
				}

				if (!defined($transfer_from))
				{
					$transfer_from="";
				}

				if(!defined ($list_id) || ($list_id =~ /^$/ || $list_id =~ /^[\s]+$/))
				{
					$list_id=0;
					$list_name="Manual Dial";
				}
				else
				{
					$query="select list_name from list where list_id='$list_id'";
					$retval = query_execute($query, $dbh, 1, __LINE__);
					$list_name = @$retval[0];
				}

				if($campaign_name =~ /preview/)
				{
					$campaign_name = substr($campaign_name,8);
					$preview_call=1;
				}

				if (not exists $campaignNameHash{$campaign_name}) {
					populateCampaign($campaign_name,$dbh,'1');
				}
				$campaign_id = $campaignNameHash{$campaign_name};
				$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");

				if($lead_id) {
					$query="select name from $cust_remove where lead_id='$lead_id'";
					$retval=query_execute($query,$dbh,1,__LINE__);
					$customer_name=(defined(@$retval[0])?@$retval[0]:"");

					if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/))
					{
						$customer_name =~ s/\'/\\'/g;
					}
				}


				if(($channel =~ /Zap/i))
				{
					$zap_channel=substr($channel,0,index($channel,"-"));
					$zap_channel =~ s/ZAP/Zap/g;
					if($zap_channel)
					{
						if (not exists($providernameHash{$zap_channel}))
						{
							populateprovider($dbh);
						}
						$provider_name=$providernameHash{$zap_channel};
					}
					$channel="ZAP";
				}

				elsif($channel =~ /SIP/i) {
					$zap_channel=substr($channel,index($channel,"/")+1);
					$zap_channel=substr($zap_channel,0,index($zap_channel,"-"));
					if(match_ip($zap_channel)){
						if (not exists($sip_providernameHash{$zap_channel}))
						{
							sip_populateprovider($dbh);
						}
						$provider_name=$sip_providernameHash{$zap_channel};
					}
					else{
						$provider_name=$zap_channel;
					}
					$zap_channel=$channel;
					$channel = "SIP";
				}
				elsif($channel =~ /Local/i)
				{
					$provider_name="Local";
					$channel = "Local";
					$zap_channel=$channel;
				}
				else
				{
					$zap_channel=$channel;
					$channel = "SIP";
				}

				$call_status="abandon";
				$dialer_inserted_field = 0;

				if(defined($skill_id) && ($skill_id !~ /^$/ && $skill_id !~ /^[\s]+$/) && $skill_id > 0)
				{
					if (not exists($campaignSkillHash{$skill_id."_".$campaign_id})) {
						populateSkill($dbh);
					}
					$skill_name=$campaignSkillHash{$skill_id."_".$campaign_id};
				}

				my $remarks="ParkAbandon";


				if(defined($agent_id) && $agent_id) {
					if (not exists $agentHash{$agent_id}) {
						populateAgent($agent_id,$dbh);
					}
					$agent_name = $agentHash{$agent_id};
				}

				$query="select agent_ext from agent_live where agent_id='$agent_id'";
				my $agentidvar=query_execute($query,$dbh,1,__LINE__);
				my $agent_ext=@$agentidvar[0];


				$report_id='';
				$report_query="insert into $table_name (node_id,lead_id,agent_id,agent_ext,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,park_start_time,park_end_time,campaign_type,campaign_channel,zap_channel,monitor_filename,new_monitor_filename,dialer_type,call_status_disposition,q_enter_time,q_leave_time,transfer_status,transfer_from,provider_name,dialer_inserted_field,skills,did_num,CustUniqueId,redial_flag,callback_flag,concurrent_calls,next_call_time,entrytime,call_remarks,ph_type,dialer_remarks,lead_attempt_count,phone_attempt_count,lead_total_max_retry,ph_max_retry,ringing_flag,caller_id) values ('$node_id','$lead_id','$agent_id','$agent_ext','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name',from_unixtime('$link_date_time'),from_unixtime('$link_end_date_time'),'$duration','$park_start_time','$park_end_time','$call_type','$channel','$zap_channel','$monitor_file_name','$new_monitor_filename','$dialerType','$call_status',from_unixtime('$park_start_time'),from_unixtime('$park_end_time'),'$transfer_status','$transfer_from','$provider_name','$dialer_inserted_field','$skill_name','$did_num','$CustUniqueId','$redial_flag','$call_back_live','$concurrent_call','$nc_time','$link_date_time','$remarks','$phone_type','$dialer_remarks','$lead_attempt_count','$phone_attempt_count','$lead_retry_count','$phone_retry_count','$ringing_flag','$callerid')";
# Current report table session id check needs lock as different packets can insert same data #
				$query="select 4 from current_report where session_id=$session_id and entrytime='$link_date_time'";
				$returnvar=query_execute($query,$dbh,1,__LINE__);

				if(!defined (@$returnvar[0]))
				{
					$report_id=query_execute($report_query,$dbh,3,__LINE__);
					$report_query="insert into $table_name (report_id,node_id,lead_id,agent_id,agent_ext,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,park_start_time,park_end_time,campaign_type,campaign_channel,zap_channel,monitor_filename,new_monitor_filename,dialer_type,call_status_disposition,q_enter_time,q_leave_time,transfer_status,transfer_from,provider_name,dialer_inserted_field,skills,did_num,CustUniqueId,redial_flag,callback_flag,concurrent_calls,next_call_time,entrytime,call_remarks,ph_type,dialer_remarks,lead_attempt_count,phone_attempt_count,lead_total_max_retry,ph_max_retry,ringing_flag,caller_id) values ('$report_id','$node_id','$lead_id','$agent_id','$agent_ext','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name',from_unixtime('$link_date_time'),from_unixtime('$link_end_date_time'),'$park_start_time','$park_end_time','$duration','$call_type','$channel','$zap_channel','$monitor_file_name','$new_monitor_filename','$dialerType','$call_status',from_unixtime('$park_start_time'),from_unixtime('$park_end_time'),'$transfer_status','$transfer_from','$provider_name','$dialer_inserted_field','$skill_name','$did_num','$CustUniqueId','$redial_flag','$call_back_live','$concurrent_call','$nc_time','$link_date_time','$remarks','$phone_type','$dialer_remarks','$lead_attempt_count','$phone_attempt_count','$lead_retry_count','$phone_retry_count','$ringing_flag','$callerid')";
#Adding information to current report
					check_cview($report_query,$dbh,$table_name,1);
					$report_query =~ s/$table_name/current_report/i;
					query_execute($report_query,$dbh,0,__LINE__);
				}
		    }

				$query="delete from call_park where session_id=$session_id";
				query_execute($query, $dbh,0, __LINE__);

				$query="delete from park_live where session_id=$session_id";
				query_execute($query, $dbh,0, __LINE__);
		}
########################ParkedAbandon End#######################################################


#################BridgeConnect START############################################################
elsif(($thread_type == 14) && ($command_line[0] =~ m/^Event: BridgeConnect$/))
 { 
			my $session_id_pre = substr($command_line[2],index($command_line[2],":") + 2);
			my $session_id_sec = substr($command_line[3],index($command_line[3],":") + 2);
			my $cust_ph_no_1 = substr($command_line[9],index($command_line[9],":") + 2);
			my $cust_ph_no_2 = substr($command_line[10],index($command_line[10],":") + 2);
			my $bridge_enter_time = substr($command_line[11],index($command_line[11],":") + 2);

			$query="insert into bridge_live(session_id,bridge_enter_time,cust_ph_no_1,cust_ph_no_2) values ('$session_id_pre','$bridge_enter_time','$cust_ph_no_1','$cust_ph_no_2')";
			query_execute($query,$dbh,0,__LINE__);

			$query="delete from park_live where session_id in ($session_id_pre,$session_id_sec)";
			query_execute($query, $dbh,0, __LINE__);

 }
#################BridgeConnect END############################################

#################BridgeComplete START############################################
elsif(($thread_type == 14) && ($command_line[0] =~ m/^Event: BridgeComplete$/))
 { 
			my $session_id_pre = substr($command_line[2],index($command_line[2],":") + 2);
			my $session_id_sec = substr($command_line[3],index($command_line[3],":") + 2);
			
			$query="delete from bridge_live where session_id=$session_id_pre";
		    query_execute($query,$dbh,0,__LINE__);

 }
#################BridgeComplete END############################################


##############UNLINK BLOCK START################################################
			elsif(($thread_type == 1) && (($command_line[0] =~ /Event: Unlink/) &&($command_line[2]!~/Local/)))
			{
				if(0) {
					my $cust_remove="";
					my @variables=();
					$session_id=substr($command_line[4],index($command_line[4],":") + 2);
					$channel = substr($command_line[2],index($command_line[2],":") + 2);
					$agent_id=substr($command_line[3],index($command_line[3],"/") + 1);
					$res = substr($agent_id,0,1);
					$hangup_cause = substr($command_line[8],index($command_line[8],":") + 2);

					$returnvar ="";
					$returnvar = substr($command_line[9],index($command_line[9],":") + 1);
					$custphno = substr($command_line[6],index($command_line[6],":") + 1);
					$custphno =~ s/^\s+//;

					$query="select now()";
					my $tmp=query_execute($query,$dbh,1,__LINE__);
					my $unlink_time = @$tmp[0];

					if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
					{
						$returnvar=~ s/\s+//g;

						@variables=split(/,/,$returnvar);
						$custphno=$variables[0];
						$lead_id=$variables[1];
						$campaign_id=$variables[2];
						$list_id=$variables[3];
						$strict=$variables[4];
					}
					else
					{
						$query="select campaign_id from agent where agent_id='$agent_id'";
						$retval = query_execute($query,$dbh,1,__LINE__);
						$campaign_id = @$retval[0];

					}
					$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");
					if ($res == 2 || $res ==3 || $res == 4)
					{
						init_stateHash($session_id);
						if($stateHash{$session_id} == 0)
						{
							joinBlock($returnvar,"answered",$time,$dbh,$session_id,$campaign_id,$custphno,$channel);
						}


#on the fly AMD is detected
						if(defined($hangup_cause) && ($hangup_cause == 126))
						{
#send agent into FREE state when AMD is detected instead of CLOSURE state
							$query="update agent_live set agent_state='FREE',lead_id='0',closer_time='',session_id='0.000000',last_activity_time=now(),is_free=0,trying_flag=0,trying_cust_ph_no=0,wait_time=unix_timestamp() where agent_id='$agent_id'";
							query_execute($query,$dbh,0,__LINE__);
							$retval="";

#update the customer table
							$query="select ansmc_disposition from campaign where campaign_id='$campaign_id'";
							$retval =query_execute($query,$dbh,1,__LINE__);

							if(defined(@$retval[0]) )
							{
								if((@$retval[0] == 143999) || (@$retval[0] == 0)) #never call again
								{
									$query="update $cust_remove set lead_state='0' , call_disposition = 'ansmc' where lead_id='$lead_id'";
									query_execute($query,$dbh,0,__LINE__);

									$query="update dial_Lead set lead_state='0' where lead_id='$lead_id'";
									query_execute($query,$dbh,0,__LINE__);

									$query="delete from dial_Lead_$campaign_id where lead_id='$lead_id'";
									query_execute($query,$dbh,0,__LINE__);

								}
								else
								{
#value from database is in minutes, hence calculate the seconds and add in current time
									@$retval[0]=(@$retval[0] * 60) + time;

									$query="update $cust_remove set next_call_time='@$retval[0]', call_disposition = 'ansmc' where lead_id='$lead_id'";
									query_execute($query,$dbh,0,__LINE__);

									$query="update dial_Lead set next_call_time='@$retval[0]' where lead_id='$lead_id'";
									query_execute($query,$dbh,0,__LINE__);

									$query="update dial_Lead_$campaign_id set next_call_time='@$retval[0]' where lead_id='$lead_id'";
									query_execute($query,$dbh,0,__LINE__);

								}
							}
						}
						else
						{
#if hangup is not parsed,otherwise hangup has already done this work
							if(($stateHash{$session_id} & 2) != 2)
							{
								if(0 && defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/))
								{
									$query="update agent_live set agent_state='FREE',lead_id='0',closer_time='0',session_id='0.000000',last_activity_time=now(),is_free=0,trying_flag=0,trying_cust_ph_no=0 where agent_id='$agent_id'";
									query_execute($query,$dbh,0,__LINE__);
								}
								else
								{
									$query="select wrapupTime from campaign where campaign_id='$campaign_id'";
									$retval=query_execute($query,$dbh,1,__LINE__);

									$wrapupTime=@$retval[0];
									if(defined($wrapupTime) && ($wrapupTime < 15) && ($wrapupTime != 0))
									{
										$query="update agent_live set agent_state='READY',closer_time='$timestamp',trying_flag=0,trying_cust_ph_no=0,last_activity_time=now() where agent_id='$agent_id' and agent_state!='FREE'";
										$retval = query_execute($query,$dbh,2,__LINE__);
										if (defined $retval && $retval > 0)
										{
#Mark the state of agent READY
											$wrapup_semaphore->down;
											my @tmp_arr=();
											@tmp_arr=split(",",$agent_wrapup{$agent_id});
											$tmp_arr[5]="READY";
											$tmp_arr[6]=$timestamp;         #disc time
											$tmp_arr[7]=$timestamp;         #state change time
											$agent_wrapup{$agent_id}=join(",",@tmp_arr);
											$wrapup_semaphore->up;
											undef(@tmp_arr);
										}
									}
									else
									{
										$query="update agent_live set agent_state='CLOSURE',closer_time='$timestamp',last_activity_time=now(),trying_flag=0,trying_cust_ph_no=0 where agent_id='$agent_id' and agent_state!='FREE'";
										$retval = query_execute($query,$dbh,2,__LINE__);
										if (defined $retval && $retval > 0)
										{

#Mark the state of agent CLOSURE
											$wrapup_semaphore->down;
											my @tmp_arr=();
											@tmp_arr=split(",",$agent_wrapup{$agent_id});
											$tmp_arr[5]="CLOSURE";
											$tmp_arr[6]=$timestamp;
											$tmp_arr[7]=$timestamp;
											$agent_wrapup{$agent_id}=join(",",@tmp_arr);
											$setmefree_hit[$agent_id]=0;
											$wrapup_semaphore->up;
											undef(@tmp_arr);
										}
									}
								}
							} #end of state hash if
						}
					}
					else
					{
#peer block recieved
						$query="update  $table_name set call_end_date_time='$unlink_time' where session_id=$session_id";
						check_cview($query,$dbh,$table_name,1);
						query_execute($query,$dbh,0,__LINE__);

					}
					$stateHash_semaphore->down;
					$stateHash{$session_id} = $stateHash{$session_id} | 4;
					$stateHash_semaphore->up;
					del_stateHash($session_id);

					init_stateHash($session_id);
					$stateHash_semaphore->down;
					$stateHash{$session_id} = $stateHash{$session_id} | (1 << 3);
					$stateHash_semaphore->up;
                    undef(@variables);
				}
			}
##############UNLINK BLOCK END##########################################


##############MEETMEJOIN BLOCK START######################################
			elsif(($thread_type == 9) && ($command_line[0] =~ /Event: MeetmeJoin/i))
			{
				my $monitor_folder="";
				my $monitor_sub_folder="";
				my $confno="";
				my $call_type;
				my $ztc_chan="";
				my $ztc_confno="";
				my $ztc_confmode="";
				my $fd_value="";
				my $is_Barge = "";
				my $is_agent = 0;
				my $confcount="";
				my $is_vdn=0;
				my $dialerType="";
				my @variables=();

				$session_id=substr($command_line[3],index($command_line[3],":") + 2);
				$channel=substr($command_line[2],index($command_line[2],":") + 2);
				$confno=substr($command_line[4],index($command_line[4],":") + 2);
				$caller_id=substr($command_line[5],index($command_line[5],":") + 2);
				$call_type = substr($command_line[6],index($command_line[6],":") + 2);
				$monitor_file_name = substr($command_line[7],index($command_line[7],":") + 2);
				$monitor_folder = substr($command_line[8],index($command_line[8],":") + 2);
				$monitor_sub_folder     = substr($command_line[9],index($command_line[9],":") + 2);
				$returnvar =substr($command_line[10],index($command_line[10],":") + 2);
				$ztc_chan = substr($command_line[12],index($command_line[12],":") + 2);
				$ztc_confno = substr($command_line[13],index($command_line[13],":") + 2);
				$ztc_confmode = substr($command_line[14],index($command_line[14],":") + 2);
				$fd_value = substr($command_line[15],index($command_line[15],":") + 2);
				$is_Barge = substr($command_line[16],index($command_line[16],":") + 2);
				$is_agent = substr($command_line[17],index($command_line[17],":") + 2);
				$confcount = substr($command_line[18],index($command_line[18],":") + 2);
				my $conf_start_time = substr($command_line[20],index($command_line[20],":") + 2);
				my $agent_live_id = $confno;
           
				if($confno =~ /\-/)
				{
					my @returnvarSess=split('\-',$confno);
					$agent_live_id=$returnvarSess[0]; 
				}

				if(defined($monitor_folder) && ($monitor_folder !~ /^$/ && $monitor_folder !~ /^[\s]+$/) && length($monitor_folder) > 2)
				{
					if($monitor_folder !~ /^\//) {
						$monitor_folder =  "/".$monitor_folder."/";
				}
				if(!defined($monitor_sub_folder) or ($monitor_sub_folder =~ /^$/ && $monitor_sub_folder =~ /^[\s]+$/)) {
					if($monitor_folder !~ /\/$/) {
						$monitor_folder =  $monitor_folder."/";
					}
				}
				}

				if(defined($monitor_sub_folder) && ($monitor_sub_folder !~ /^$/ && $monitor_sub_folder !~ /^[\s]+$/)  && length($monitor_sub_folder) > 2)
				{
					if($monitor_sub_folder !~ /^\// && $monitor_folder !~ /\/$/) {
						$monitor_sub_folder =  "/".$monitor_sub_folder;
				}
				$monitor_folder =  $monitor_folder.$monitor_sub_folder;
				if($monitor_folder !~ /\/$/) {
					$monitor_folder =  $monitor_folder."/";
				}
				}


				$returnvar=~ s/\s+//g;
				@variables=split(/,/,$returnvar);
				my $custphno=$variables[0];
				my $lead_id=(defined($variables[1])?$variables[1]:"");
				my $campaign_id=$variables[2];
				$list_id=(defined($variables[3])?$variables[3]:"");
				$strict=$variables[4];
				$dialerType=(defined($variables[5])?$variables[5]:"PREVIEW");
				$transfer_from=$variables[6];
				my $vdn_flag=$variables[7];
				if(defined($vdn_flag) && ($vdn_flag !~ /^$/ && $vdn_flag !~ /^[\s]+$/))
				{
					$is_vdn=1;
				}
				if(scalar @variables > 1)
				{
					$lead_id=$variables[1];

					$query="select campaign_id from agent where agent_id='$agent_live_id'";
					$returnvar=query_execute($query,$dbh,1,__LINE__);
					if(@$returnvar[0])
					{
						$campaign_id=@$returnvar[0];
					}
				}
				else
				{
					$lead_id=$variables[0];
				}
				if($is_Barge == 0) {
					$query="insert into meetme_user (confno,chan_name,session_id,cust_ph_no,lead_id,campaign_id,list_id,link_time,monitor_filename,callType,monitor_file_path,ztc_chan,ztc_confno,ztc_confmode,fd,conference_start_time,confcount,is_vdn,dialer_type) values('$confno','$channel','$session_id','$custphno','$lead_id','$campaign_id','$list_id',unix_timestamp(),'$monitor_file_name','$call_type','$monitor_folder','$ztc_chan','$ztc_confno','$ztc_confmode','$fd_value',from_unixtime('$conf_start_time'),'$confcount','$is_vdn','$dialerType')";
					query_execute($query,$dbh,0,__LINE__);
				}

				$query="delete from meetme_user where conf_clean_time!=0 and conf_clean_time <= unix_timestamp()";
				query_execute($query,$dbh,0,__LINE__);

				if($dialerType  =~ /PREVIEW/){
					$query="select 1 from callProgress where agent_id='$agent_live_id' and session_id=$session_id";
					$returnvar=query_execute($query,$dbh,1,__LINE__);
					if(defined(@$returnvar[0]))
					{
						$query="delete from callProgress where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);
					}
				}

				if($channel =~ /ZAP/i) {
					$channel=substr($channel,0,index($channel,"-"));
					$query="update zap_live set department_id='',peer_id='',service_type='3',connect_time=unix_timestamp() where zap_id='$channel'";
					query_execute($query,$dbh,0,__LINE__);
				}
				if($custphno==$agent_live_id){
					$query="select 1 from agent_live where agent_id='$agent_live_id' and closer_time='-999' and agent_state='CLOSURE'";
					$returnvar=query_execute($query,$dbh,1,__LINE__);
					if(defined(@$returnvar[0]))
					{
                        $query="update agent_live set agent_state='FREE',ready_time=unix_timestamp()-unix_timestamp(last_login_time),closer_time=0,wait_time=unix_timestamp() where agent_id='$agent_live_id' and closer_time='-999' and agent_state='CLOSURE'";
			            query_execute($query,$dbh,0,__LINE__);
                     }
				}
			}
##############MEETMEJOIN BLOCK END######################################

##############EVENT: ConfMute start#####################################
			elsif(($thread_type == 9) && ($command_line[0] =~ /Event: EventConfMute/i))
			{
				my $channel="";
				my $mute="";
				my $ztc_conf_no ="";

				$channel = substr($command_line[2],index($command_line[2],":") + 2);
				$ztc_conf_no=substr($command_line[3],index($command_line[3],":") + 2);
				$mute = substr($command_line[4],index($command_line[4],":") + 2);

#$channel=substr($channel,index($channel,"/")+1);
#$channel=substr($channel,0,index($channel,"-"));
				$query = "update meetme_user set ztc_confmode = '$mute' where confno = '$ztc_conf_no' and chan_name = '$channel'";
				query_execute($query,$dbh,0,__LINE__);
			}

#############Conf_Mute  BLOCK END#####################################


##############MeetmeCRMInfo BLOCK START######################################
			elsif(($thread_type == 9) && ($command_line[0] =~ /Event: MeetmeCRMInfo/i))
			{
				my $conf_leave=0;
				my $conf_table = "";
				my $category;
				$agent_id=substr($command_line[2],index($command_line[2],":") + 2);
				$session_id=substr($command_line[3],index($command_line[3],":") + 2);
                my $agent_live_id = $agent_id;
           
				if($agent_id =~ /\-/)
				{
					my @returnvarSess=split('\-',$agent_id);
					$agent_live_id=$returnvarSess[0]; 
				}

				$query="select conf_leave,report_table from meetme_user where confno='$agent_id' and session_id=$session_id";
				$retval=query_execute($query,$dbh,1,__LINE__);
				$conf_leave=@$retval[0];
				$conf_table=((defined @$retval[1])?@$retval[1]:"$table_name");
				if($conf_leave) {
#update reports
					$query="select txt,call_status,cust_disposition,category,cust_name from crm_meetme_live where agent_id='$agent_live_id' and session_id=$session_id";
					$retval=query_execute($query,$dbh,1,__LINE__);
					$remarks= ((defined @$retval[0])?@$retval[0]:"");
					if ($remarks !~ /^$/ && $remarks !~ /^[\s]+$/)
					{
						$remarks =~ s/\\/\\\\/g;
						$remarks =~ s/\'/\\'/g;
					}
					$call_status= ((defined @$retval[1])?@$retval[1]:"");
					$cust_disposition= ((defined @$retval[2])?@$retval[2]:"");
					$category= ((defined @$retval[3])?@$retval[3]:"");
					$customer_name=((defined @$retval[4])?@$retval[4]:"");

					$query="update $conf_table set cust_disposition='$cust_disposition',cust_category='$category',call_remarks=concat(call_remarks,'$remarks') where session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);

#Adding information to current report
					check_cview($query,$dbh,$conf_table,1);
					$query =~ s/$conf_table/current_report/i;
					query_execute($query,$dbh,0,__LINE__);

#clean meetme_user
					$query="delete from meetme_user where confno='$agent_id' and session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);

#clean crm_meetme_live
					$query="delete from crm_meetme_live where session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);
				}
				else {
					$query="update meetme_user set conf_crm_info='1' where confno='$agent_id' and session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);
				}

			}
###########################################################################

##############MEETMELEAVE BLOCK START######################################
			elsif(($thread_type == 9) && ($command_line[0] =~ /Event: MeetmeLeave/i))
			{
				my $crm_info=0;
				my $conf_wrapup_time=0;
				my $conf_no="";
				my $category="";
				my $monitor_file_path="";
				my $hold_time=0;
				my $confcount='';
				my $conference_start_time='';
				my $provider_name="";
				my $ConfUnique_id="";
				my $meetmeleave;
				my $campaign_name="";
				my $retval="";
				my $park_start_time=0;
				my $park_end_time=0;
				my $dialer_inserted_field=0;
				my $dialerType="";
				my $confdtmf="";
				my $remarks="";
				my $entrytime="";
				my $cust_remove="";
				my $customer_name="";

				$channel=substr($command_line[2],index($command_line[2],":") + 2);
				$agent_id=substr($command_line[3],index($command_line[3],":") + 2);
				$ConfUnique_id = substr($command_line[7],index($command_line[7],":") + 2);
				my $conf_user = substr($command_line[8],index($command_line[8],":") + 2);
				my $user_leave_time = substr($command_line[9],index($command_line[9],":") + 2);
				my $conference_end_time = substr($command_line[10],index($command_line[10],":") + 2);
				$confdtmf = substr($command_line[11],index($command_line[11],":") + 2);
				my $agent_live_id = $agent_id;
           
				if($agent_id =~ /\-/)
				{
					my @returnvarSess=split('\-',$agent_id);
					$agent_live_id=$returnvarSess[0]; 
				}


# Add reporting block
				$query="select cust_ph_no,campaign_id,lead_id,list_id,link_time, session_id,monitor_filename,callType,conf_crm_info,confno,monitor_file_path,confcount,conference_start_time,dialer_type,now() from meetme_user where confno='$agent_id' and chan_name='$channel' and conf_leave=0";
				$retval=query_execute($query,$dbh,1,__LINE__);

				$custphno=((defined @$retval[0])?@$retval[0]:"0");
				$campaign_id=((defined @$retval[1])?@$retval[1]:"0");
				$lead_id=((defined @$retval[2])?@$retval[2]:"0");
				$list_id=((defined @$retval[3])?@$retval[3]:"0");
				$link_time=((defined @$retval[4])?@$retval[4]:"0");
				$session_id=((defined @$retval[5])?@$retval[5]:"0");
				$monitor_file_name=((defined @$retval[6])?@$retval[6]:"");
				$campaign_type =((defined @$retval[7])?@$retval[7]:"0");
				$crm_info = ((defined @$retval[8])?@$retval[8]:"0");
				$conf_no=((defined @$retval[9])?@$retval[9]:"0");
				$monitor_file_path=((defined @$retval[10])?@$retval[10]:"0");
				$confcount = ((defined @$retval[11])?@$retval[11]:"0");
				$conference_start_time = ((defined @$retval[12])?@$retval[12]:"0");
				$dialerType=((defined @$retval[13])?@$retval[13]:"");
				$meetmeleave = (defined(@$retval[14])?@$retval[14]:"");

				$campaign_type = ($campaign_type=="0"?"INBOUND":"OUTBOUND");

				if($link_time =~ /^$/ || $link_time =~ /^[\s]+$/)
				{
					$link_time = $timestamp;
				}

#to enter queue timings in the reporting table
				$q_enter_time = $conference_start_time;

				if($conf_user == 0){
					$q_leave_time = "from_unixtime('$conference_end_time')";
				}
				else {
					$q_leave_time = "'$conference_start_time'";
				}

				$retval="";


				if(!defined($dialerType) || ($dialerType =~ /^$/ || $dialerType =~ /^[\s]+$/))
				{
					$query="select dialer_type from agent_live where agent_id='$agent_live_id'";
					$retval=query_execute($query,$dbh,1,__LINE__);
					$dialerType=@$retval[0];
				}

				if($monitor_file_name !~ /^$/ && $monitor_file_name !~ /^[\s]+$/) {
					if($fileFormatHash{$campaign_id} eq "1") {
						$monitor_file_name =$monitor_file_name.".mp3";
					}
					else {
						$monitor_file_name =$monitor_file_name.".wav";
					}
				    $dialer_inserted_field=0;
				}
				else{
					$dialer_inserted_field=0;
				}

				if (not exists $campaignHash{$campaign_id}) {
					populateCampaign($campaign_id,$dbh,'0');
				}
				$campaign_name = $campaignHash{$campaign_id};

				if (not exists $campaign_conf_WrapHash{$campaign_id}) {
					populateCampaignWrap($campaign_id,$dbh);
				}
				$conf_wrapup_time = $campaign_conf_WrapHash{$campaign_id};


				if($lead_id) {
					if($list_id) {
						$query="select list_name from list where list_id='$list_id'";
						$retval=query_execute($query,$dbh,1,__LINE__);
						$list_name=@$retval[0];
					}
					if (!defined($list_name) || ($list_name=~/^$/ || $list_name=~/^[\s]+$/))
					{
						$query="select list_id,list_name from list where campaign_id='$campaign_id'";
						$retval=query_execute($query,$dbh,1,__LINE__);
						$list_id=@$retval[0];
						$list_name=@$retval[1];
						if (!defined($list_name) || ($list_name=~/^$/ || $list_name=~/^[\s]+$/))
						{
							$list_name= "No_List_Manual_Call";
						}
					}
				}
				else {
					$list_name="No_List_Manual_Call";
				}

				if (not exists $agentHash{$agent_live_id}) {
				  populateAgent($agent_live_id,$dbh);
				}
				$agent_name = $agentHash{$agent_live_id};

				if(($channel =~ /Zap/i)) {
					$zap_channel=substr($channel,0,index($channel,"-"));
					$zap_channel =~ s/ZAP/Zap/g;
					if($zap_channel)
					{
						if (not exists($providernameHash{$zap_channel})) {
							populateprovider($dbh);
						}
						$provider_name=$providernameHash{$zap_channel};
					}
					$zap_type="ZAP";
				}
				elsif($channel =~ /SIP/i) {
					$zap_channel=substr($channel,index($channel,"/")+1);
					$zap_channel=substr($zap_channel,0,index($zap_channel,"-"));
					if(match_ip($zap_channel)){
						if (not exists($sip_providernameHash{$zap_channel}))
						{
							sip_populateprovider($dbh);
						}
						$provider_name=$sip_providernameHash{$zap_channel};
					}
					else{
						$provider_name=$zap_channel;
					}
					$zap_channel=$channel;
					$zap_type = "SIP";
				}
				elsif($channel =~ /Local/i)
				{
					$provider_name="Local";
					$zap_type = "Local";
					$zap_channel=$channel;
				}
				else
				{
					$zap_channel=$channel;
					$zap_type = "SIP";
					$provider_name="SIP";
				}

				$query="select txt,call_status,cust_disposition,category,cust_name from crm_meetme_live where agent_id='$agent_live_id' and session_id=$session_id";
				$retval=query_execute($query,$dbh,1,__LINE__);
				$remarks= ((defined @$retval[0])?@$retval[0]:"");
				if ($remarks !~ /^$/ && $remarks !~ /^[\s]+$/)
				{
					$remarks =~ s/\\/\\\\/g;
					$remarks =~ s/\'/\\'/g;
				}

				$call_status= ((defined @$retval[1])?@$retval[1]:"");
				$cust_disposition = (defined(@$retval[2])?@$retval[2]:"None");
				$category = (defined(@$retval[3])?@$retval[3]:"Not Assigned");
				if(defined($confdtmf) && ($confdtmf !~ /^$/ && $confdtmf !~ /^[\s]+$/))
				{
				   $remarks=$remarks."DTMF($confdtmf)";
				}
				$customer_name=((defined @$retval[4])?@$retval[4]:"");
				my $ringing_flag=1;
				$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");

				if(defined($lead_id) && ($lead_id !~ /^$/ && $lead_id !~ /^[\s]+$/) && ($lead_id != 0))
				{
					if(defined($customer_name) && ($customer_name !~ /^$/ && $customer_name !~ /^[\s]+$/)) {
						$customer_name =~ s/\'/\\'/g;
					}
					else {
						$query = "select name from $cust_remove where lead_id=$lead_id ";
						$retval=query_execute($query,$dbh,1,__LINE__);
						$customer_name =@$retval[0];
						$customer_name =~ s/\'/\\'/g;
					}
				}

				$query="select park_start_time,park_end_time from park_live where session_id=$session_id";
				$retval = query_execute($query, $dbh, 1, __LINE__);
				if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/)){
					$park_start_time=@$retval[0];
					$park_end_time=@$retval[1];
				}

				$query="select agent_ext from agent_live where agent_id='$agent_live_id'";
				my $agentidvar=query_execute($query,$dbh,1,__LINE__);
				my $agent_ext=@$agentidvar[0];

				$report_id='';
				$report_query="insert into $table_name (node_id,lead_id,agent_id,agent_ext,agent_name, campaign_id,campaign_name,campaign_type,campaign_channel,monitor_filename,call_start_date_time,call_end_date_time,zap_channel,call_duration,call_status_disposition,call_remarks,session_id,cust_ph_no,cust_name,list_id,list_name,q_enter_time,q_leave_time,hold_time,dialer_type,cust_disposition,cust_category,monitor_file_path,entrytime,ConfUnique_id,provider_name,concurrent_calls,park_start_time,park_end_time,dialer_inserted_field) values ('$node_id',".($crm_license == 0?"'0',":"'$lead_id',")."'$agent_live_id','$agent_ext','$agent_name','$campaign_id','$campaign_name', '$campaign_type','$zap_type','$monitor_file_name',from_unixtime($link_time),'$meetmeleave','$zap_channel',unix_timestamp('$meetmeleave')-$link_time,'supervised_transfer','$remarks','$session_id','$custphno','$customer_name','$list_id','$list_name','$conference_start_time',$q_leave_time,'$hold_time','$dialerType','$cust_disposition','$category','$monitor_file_path','$link_time','$ConfUnique_id','$provider_name','$confcount','$park_start_time','$park_end_time','$dialer_inserted_field')";
				$returnvar="";

#$currentReport_semaphore->down;
				$query="select 4 from current_report where agent_id='$agent_live_id' and session_id=$session_id and entrytime='$link_time'";
				$returnvar=query_execute($query,$dbh,1,__LINE__);
#if entry doesnot exist in the report table then insert it otherwise don't
				if(!defined (@$returnvar[0]))
				{
					$report_id=query_execute($report_query,$dbh,3,__LINE__);

					$report_query="insert into $table_name (report_id,node_id,lead_id,agent_id,agent_name,agent_ext,campaign_id,campaign_name,campaign_type,campaign_channel,monitor_filename,call_start_date_time,call_end_date_time,zap_channel,call_duration,call_status_disposition,call_remarks,session_id,cust_ph_no,cust_name,list_id,list_name,q_enter_time,q_leave_time,hold_time,dialer_type,cust_disposition,cust_category,monitor_file_path,entrytime,ConfUnique_id,provider_name,concurrent_calls,park_start_time,park_end_time,dialer_inserted_field) values ('$report_id','$node_id',".($crm_license == 0?"'0',":"'$lead_id',")."'$agent_live_id','$agent_name','$agent_ext','$campaign_id','$campaign_name','$campaign_type','$zap_type','$monitor_file_name',from_unixtime($link_time),'$meetmeleave','$zap_channel',unix_timestamp('$meetmeleave')-$link_time,'supervised_transfer','$remarks','$session_id','$custphno','$customer_name','$list_id','$list_name','$conference_start_time',$q_leave_time,'$hold_time','$dialerType','$cust_disposition','$category','$monitor_file_path','$link_time','$ConfUnique_id','$provider_name','$confcount','$park_start_time','$park_end_time','$dialer_inserted_field')";
#Adding information to current report
					check_cview($report_query,$dbh,$table_name,1);
					$report_query =~ s/$table_name/current_report/i;
					query_execute($report_query,$dbh,0,__LINE__);

					if(defined($confdtmf) && ($confdtmf !~ /^$/ && $confdtmf !~ /^[\s]+$/))
					{
						$query="update $table_name set call_remarks='$remarks' where session_id=$session_id and cust_ph_no!=agent_id";
						query_execute($query,$dbh,0,__LINE__);

						#Adding information to current report
						check_cview($query,$dbh,$table_name,1);
						$query =~ s/$table_name/current_report/i;
						query_execute($query,$dbh,0,__LINE__);
					}

					if(0 && $conf_user == 1)
					{
						$query = "select chan_name from meetme_user where chan_name!='$channel' and cust_ph_no = '$agent_id' and conf_leave=0";
						$retval = query_execute($query,$dbh,1,__LINE__);
						if(defined($retval) && ($retval !~ /^$/ && $retval !~ /^[\s]+$/))
						{
							my $chan_name = @$retval[0];
							my $query = "select agent_secret from agent where agent_id=$agent_live_id";
							my $agent_secret = query_execute($query,$dbh,1,__LINE__);
							if(defined($agent_secret) && ($agent_secret !~ /^$/ && $agent_secret !~ /^[\s]+$/))
							{
								my $agent_exten = @$agent_secret[0];
								$agent_exten = $agent_exten."|".$agent_live_id;
								my $priority = 1;
								$shared_key = $agent_live_id."##".$campaign_name."##".$chan_name."##".$agent_exten."##".$priority;
								$sendTn_semaphore->down;
								$sendTnHash{$shared_key} = "Redirect";
								$sendTn_semaphore->up;
							}
						}
					}
#insert an entry in unmerged_snd_files table
					if($conf_user == 0)
					{
						$query="insert into unmerged_snd_files(monitor_filename,monitor_file_path)values('$monitor_file_name','$monitor_file_path')";
						query_execute($query,$dbh,0,__LINE__);
					}
				}
# reporting block end

				if(!$crm_license || $crm_info) {
					$query="update $table_name set cust_disposition='$cust_disposition',cust_category='$category',call_remarks='$remarks' where session_id=$session_id";
					check_cview($query,$dbh,$table_name,1);
					query_execute($query,$dbh,0,__LINE__);

#Adding information to current report
					$query =~ s/$table_name/current_report/i;
					query_execute($query,$dbh,0,__LINE__);

					$query="delete from crm_meetme_live where agent_id='$agent_live_id' and session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);

					$query="delete from meetme_user  where confno='$agent_id' and chan_name='$channel' ";
					query_execute($query,$dbh,0,__LINE__);
				}
				else {
					$query="update meetme_user set conf_leave='1',conf_clean_time =".($conf_wrapup_time?"unix_timestamp() + $conf_wrapup_time":"0").",report_table='$table_name'  where confno='$agent_id' and chan_name='$channel'";
					query_execute($query,$dbh,0,__LINE__);
				}

                if($conf_wrapup_time > 0 && $conf_wrapup_time <= 2){
				  $query="delete from meetme_user where conf_clean_time!=0 and conf_leave='1'";
				  query_execute($query,$dbh,0,__LINE__);
			    }
                
				if($conf_no =~ /\-/)
				{
					my @returnvarconf_no=split('\-',$conf_no);
					$conf_no=$returnvarconf_no[0]; 
				}

				if($custphno==$conf_no) {
					$query="delete from meetme_user  where confno='$agent_id' and chan_name='$channel'";
					query_execute($query,$dbh,0,__LINE__);

					$query="delete from crm_meetme_live  where session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);
				}
			}
##############MEETMELEAVE BLOCK END######################################

##############JOIN BLOCK START##########################################
			elsif (($thread_type == 6) && ($command_line[0] =~ /Event: Join/))
			{
				my $skill_id=0;
				my $call_type;
				my $concurrent_call=0;
				my $sip_gateway_id='';
				my $campaign_id=0;
				my $ivrs_path="";
				my $vdnflag=0;
                my @dialer_variables=();
				my $dialer_var="";
				my $channel_id="";

				$channel=substr($command_line[2],index($command_line[2],":") + 2);
				$session_id=substr($command_line[3],index($command_line[3],":") + 2);
				$campaign_name=substr($command_line[6],index($command_line[6],":") + 2);

				$returnvar ="";
				$custphno = substr($command_line[4],index($command_line[4],":") + 2);
				$custphno =~ s/^\s+//;
				$transfer_from="";

				if($channel =~ /VDN/i)
				{
					$vdnflag=1;
				}

				if (($command_line[0] =~ /Event: JoinAutoIVR/) || ($command_line[0] =~ /Event: JoinSipBusy/)) {
					$returnvar = substr($command_line[7],index($command_line[7],":") + 2);
					$call_type = substr($command_line[8],index($command_line[8],":") + 2);
					$dialer_var = substr($command_line[9],index($command_line[9],":") + 2);
				}
				else {

					$returnvar = substr($command_line[9],index($command_line[9],":") + 2);
					$call_type = substr($command_line[10],index($command_line[10],":") + 2);
					if($ivr_license) {
						$ivrs_path = (defined($command_line[12])?substr($command_line[12],index($command_line[12],":") + 2):"");
					}
					$skill_id=substr($command_line[13],index($command_line[13],":") + 2);
					$skill_id = ($skill_id==-1?"0":$skill_id);
					$dialer_var = substr($command_line[16],index($command_line[16],":") + 2);
				}

				if(defined($dialer_var) && ($dialer_var !~ /^$/ && $dialer_var !~ /^[\s]+$/))
				{
					$dialer_var =~ s/\s+//g;
					@dialer_variables=split(/,/,$dialer_var);
					$channel_id= ((defined($dialer_variables[11]) && ($dialer_variables[11] !~ /^$/ && $dialer_variables[11] !~ /^[\s]+$/))?$dialer_variables[11]:"");
				}


				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$custphno=$variables[0];
					$lead_id=$variables[1];
					$campaign_id=$variables[2];
					$list_id=$variables[3];
					$strict=$variables[4];
					$transfer_from=(defined($variables[6])?$variables[6]:"");

					if($command_line[0] =~ /Event: JoinSipBusy/) {
						if(defined($channel_id) && ($channel_id !~ /^$/ && $channel_id !~ /^[\s]+$/))
				         {
                             $query="update sip set status='BUSY',session_id='$session_id',flow_state='1' where campaign_id='$campaign_id'  and status='FREE' and sip_id='$channel_id' limit 1";
							 query_execute($query,$dbh,0,__LINE__);
						 }
						 else
						 {
							$channel=substr($channel,index($channel,"/")+1);
							$channel=substr($channel,0,index($channel,"-"));
							$query="select sip_gateway.sip_gateway_id from sip_gateway,sip_channel_group where sip_gateway.sip_gateway_id=sip_channel_group.sip_gateway_id and sip_channel_group.campaign_id='$campaign_id' and (sip_gateway_name='$channel' or ipaddress='$channel')";
							my $temp_sip=query_execute($query,$dbh,1,__LINE__);
							if(defined(@$temp_sip[0])) {
								$sip_gateway_id="and sip_gateway_id='".@$temp_sip[0]."'";
							}
							$query="update sip set status='BUSY',session_id='$session_id',flow_state='1' where campaign_id='$campaign_id'  and status='FREE' $sip_gateway_id limit 1";
							query_execute($query,$dbh,0,__LINE__);
					   }
				     }
                }

				if($campaign_name !~ /preview/)
				{
					$concurrent_call = substr($command_line[8],index($command_line[8],":") + 2);
					if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/)) {
						$sh_mem_semaphore->down;
						$queueHash{$campaign_id} += 1;
						$sh_mem_semaphore->up;

						$message="";
						$message="$timestamp,";
						while(($shared_key,$value) =each(%queueHash))
						{
							$message.="$shared_key=>$value,";
						}
						$sh_mem_semaphore->down;
						shmwrite($sh_mem_id,$message,0,$size);
						$sh_mem_semaphore->up;
					}
					if($command_line[0] !~ /Event: JoinAutoIVR/ && $command_line[0] !~ /Event: JoinSipBusy/) {
						if(defined($list_id) && ($list_id !~ /^$/ && $list_id != /^[\s]+$/)) {
							$query = "update listener_status set queue = queue + 1 where list_id='$list_id' and dialing_date=curdate()";
							query_execute ($query, $dbh, 0, __LINE__);
						}

						if(!$campaign_id || (defined($transfer_from) && ($transfer_from !~ /^$/ && $transfer_from !~ /^[\s]+$/)) || $vdnflag=='1') {
							if (not exists $campaignNameHash{$campaign_name}) {
								populateCampaign($campaign_name,$dbh,'1');
							}
							$campaign_id = $campaignNameHash{$campaign_name};
						}
						if(defined($transfer_from) && ($transfer_from !~ /^$/ && $transfer_from !~ /^[\s]+$/)){
						   $call_type = ($call_type==0?"0":"2");
						}
						$query="insert into queue_live (session_id,campaign_name,campaign_id,q_enter_time,cust_ph_no,call_type,skill_id,concurrent_calls) values('$session_id','$campaign_name','$campaign_id',now(),'$custphno','$call_type','$skill_id','$concurrent_call')";
						query_execute($query, $dbh, 0, __LINE__);
					}
				}

##-----Marking campaign transfer and campaign ended in ivr reports--------------
				if($command_line[0] !~ /Event: JoinAutoIVR/ &&(defined($ivrs_path) && ($ivrs_path !~ /^$/ && $ivrs_path !~ /^[\s]+$/))) {
					$query="update ivr_call_dial_status set CampaignTransfer=ifnull(CampaignTransfer,'$campaign_name'),CampaignEnded='$campaign_name' where session_id=$session_id";
					query_execute($query,$dbh,0,__LINE__);
				}
##-----Marking channel state as handling queue call--------------
				if(($channel =~ /Zap/i)){
					$channel=substr($channel,0,index($channel,"-"));
					$query="update zap set flow_state='1' where zap_id='$channel'";
					query_execute($query,$dbh,0,__LINE__);
					if($campaign_name =~ /preview/) {
						$campaign_name =~ s/preview_//g ;
					}
					$query="update zap_live set campaign_id='$campaign_id',skill_id='$skill_id',phone_number='$custphno',call_type='$call_type',service_type='2',agent_id='',department_id='',peer_id='',connect_time='',context='$campaign_name' where zap_id='$channel'";
					query_execute($query,$dbh,0,__LINE__);
				}
				elsif (!$call_type && (!defined($returnvar) or ($returnvar =~ /^$/ or $returnvar =~ /^[\s]+$/))) {
					$query="select sip_id from sip where  session_id=$session_id";
					$retval=query_execute($query,$dbh,1,__LINE__);
					if(!defined(@$retval[0]) or (@$retval[0] =~ /^$/ && @$retval[0] =~ /^[\s]+$/)) {
						$channel=substr($channel,index($channel,"/")+1);
						$channel=substr($channel,0,index($channel,"-"));
						$query="select sip_gateway.sip_gateway_id from sip_gateway,sip_channel_group where sip_gateway.sip_gateway_id=sip_channel_group.sip_gateway_id and sip_channel_group.campaign_id='$campaign_id' and (sip_gateway_name='$channel' or ipaddress='$channel')";
						my $temp_sip=query_execute($query,$dbh,1,__LINE__);
						if(defined(@$temp_sip[0])) {
							$sip_gateway_id="and sip_gateway_id='".@$temp_sip[0]."'";
						}
						$query="update sip set status='BUSY',session_id='$session_id',flow_state='1' where campaign_id='$campaign_id'  and status='FREE' $sip_gateway_id limit 1";
						query_execute($query,$dbh,0,__LINE__);
					}
				}
				init_stateHash($session_id);
				$stateHash_semaphore->down;
				$stateHash{$session_id} = $stateHash{$session_id} | (1 << 1);
				$stateHash_semaphore->up;
				undef(@dialer_variables);
			}
##############JOIN BLOCK END##########################################

##############LEAVE BLOCK START##########################################
			elsif (($thread_type == 6) && ($command_line[0] =~ /Event: Leave/))
			{
				my $returnvar ="";
				my @variables=();
				$returnvar = substr($command_line[5],index($command_line[5],":") + 2);
				$campaign_name = substr($command_line[3],index($command_line[3],":") + 2);
				$session_id = substr($command_line[6],index($command_line[6],":") + 2);

				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;

					@variables=split(/,/,$returnvar);
					$campaign_id=$variables[2];
					if($campaign_name !~ /preview/)
					{
						if($queueHash{$campaign_id} > 0 )
						{
							$sh_mem_semaphore->down;
							$queueHash{$campaign_id} -= 1;
							$sh_mem_semaphore->up;

							$message="";
							$message="$timestamp,";
							while(($shared_key,$value) =each(%queueHash))
							{
								$message.="$shared_key=>$value,";
							}
							$sh_mem_semaphore->down;
							shmwrite($sh_mem_id,$message,0,$size);
							$sh_mem_semaphore->up;
						}
					}
				}
				$query="delete from queue_live where session_id=$session_id";
				query_execute($query, $dbh,0, __LINE__);
				undef(@variables);
			}
##############LEAVE BLOCK END##########################################

##############LINK BLOCK START##########################################
			elsif(($thread_type == 1) && (($command_line[0] =~ /Event: Link/) &&($command_line[2]!~/Local/)))
			{
				my $live_call_type = substr($command_line[10],index($command_line[10],":") + 2);
				my $department_id="";
				my $pbx_flag;
				my $ivrs_path="";
                my $agent_id="";
				if($live_call_type!=32768) {
					$channel=substr($command_line[2],index($command_line[2],":") + 2);
					$pbx_flag=substr($command_line[13],index($command_line[13],":") + 2);

                    if((defined($pbx_flag) && ($pbx_flag !~ /^$/ && $pbx_flag !~ /^[\s]+$/)) && $live_call_type==0){
                       $channel=substr($command_line[3],index($command_line[3],":") + 2);
					}
					if($channel =~ /Zap/i)
					{
						$zap_channel=substr($channel,0,index($channel,"-"));
						$zap_flag=1;
					}
					else #sip call
					{
						$zap_flag=0;
					}
					$session_id=substr($command_line[4],index($command_line[4],":") + 2);
					$monitor_file_id=substr($command_line[5],index($command_line[5],":") + 2);
					$dialer_var = substr($command_line[8],index($command_line[8],":") + 2);
					$ivrs_path = substr($command_line[9],index($command_line[9],":") + 2);
					$live_call_type = substr($command_line[10],index($command_line[10],":") + 2);
					$agent_id=substr($command_line[17],index($command_line[17],":") + 2);
					if(defined($pbx_flag) && ($pbx_flag !~ /^$/ && $pbx_flag !~ /^[\s]+$/)) {
						$monitor_file_name = substr($command_line[11],index($command_line[11],":") + 2);
						my @dialer_variables=split(/,/,$dialer_var);

						if(defined($dialer_var) && ($dialer_var !~ /^$/ && $dialer_var !~ /^[\s]+$/)) {
							$department_id = $dialer_variables[2];
						}
						if($live_call_type) {
							@dialer_variables=split(/,/,$dialer_var);
							$custphno = $dialer_variables[0];
						}
						else {
							$custphno=substr($command_line[6],index($command_line[6],":") + 2);
						}
						linkBlockPbx($agent_id,$dbh,$session_id,$monitor_file_name,$channel,$zap_flag,$custphno,substr($command_line[3],index($command_line[3],":") + 2),$zap_channel,$live_call_type,"",$ivrs_path,"",$department_id);
					}
				}
				init_stateHash($session_id);
				$stateHash_semaphore->down;
				$stateHash{$session_id} = $stateHash{$session_id} | (1 << 2);
				$stateHash_semaphore->up;

			}
##############LINK BLOCK END####################################################

##############AMD BLOCK START######################################
			elsif((($thread_type == 11)) && ($command_line[0] =~ /Event: AMD/))
			{
				$channel = substr($command_line[2],index($command_line[2],":") + 2);
				$session_id = substr ($command_line[3], index ($command_line[3], ":") + 2);
				$custphno = substr($command_line[4],index($command_line[4],":") + 1);
				$returnvar = substr($command_line[7],index($command_line[7],":") + 1);
				my $call_type = substr($command_line[8],index($command_line[8],":") + 1);
				$dialer_var = substr($command_line[9],index($command_line[9],":") + 2);
				$hangup_cause = substr($command_line[6],index($command_line[6],":") + 1);
				my $lead_retry_count = "0";
				my $phone_retry_count = "0";
				my $lead_attempt_count= "0";
				my $phone_attempt_count = "0";
				my $dialer_remarks ="";
				my @dialer_remark_array = ();
				my @variables = ();
				my $nct_time="";
				my $nc_time=0;
				my $new_monitor_flag=0;
				my $CustUniqueId="0";
				my $dialer_inserted_field=0;
				my $new_monitor_filename="";
				my $dialer_var_channel="";
				my $dialer_var_channel_id="";

				$customer_name = "";
				$dialer_var=~ s/\s+//g;
				my @dialer_variables=split(/,/,$dialer_var);
				my $phone_type = (defined($dialer_variables[0])?$dialer_variables[0]:"");
				my $redial_flag= $dialer_variables[4];
				my $call_back_live= $dialer_variables[5];

				$lead_retry_count = (defined($dialer_variables[1])?$dialer_variables[1]:"");
				$phone_retry_count = (defined($dialer_variables[2])?$dialer_variables[2]:"");
				$lead_attempt_count=(defined($dialer_variables[8])?$dialer_variables[8]:"");
				$phone_attempt_count=(defined($dialer_variables[9])?$dialer_variables[9]:"");
				my $callerid=(defined($dialer_variables[16])?$dialer_variables[16]:"0");
				$dialer_var_channel = ((defined($dialer_variables[10]) && ($dialer_variables[10] !~ /^$/ && $dialer_variables[10] !~ /^[\s]+$/))?$dialer_variables[10]:"");
                $dialer_var_channel_id = ((defined($dialer_variables[11]) && ($dialer_variables[11] !~ /^$/ && $dialer_variables[11] !~ /^[\s]+$/))?$dialer_variables[11]:"");

				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$custphno=$variables[0];
					$lead_id=$variables[1];
					$campaign_id=$variables[2];
					$list_id=$variables[3];
					$strict=$variables[4];
					$dialerType=$variables[5];
					$transfer_from=$variables[6];
					my $strict_flag =0;
					my $cust_remove="";

					my $dialer_var= substr($command_line[9],index($command_line[9],":") + 2);
					$dialer_var=~ s/\s+//g;

					$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");

					if(defined($strict) && $strict =~ /strict/)     {
						$strict_flag=1;
					}

					if($list_id > 0 && $lead_id > 0)
					{
					   $nct_time = setDisposition($dbh,$lead_id,$campaign_id,$list_id,$dialer_var,"ansmc",$strict_flag,0,$custphno);
					}

					if(defined($nct_time)){
						@dialer_remark_array=split('@@',$nct_time);

					}
					$nc_time = (defined($dialer_remark_array[0])?$dialer_remark_array[0]:"");
					$dialer_remarks = (defined($dialer_remark_array[1])?$dialer_remark_array[1]:"");

					if (not exists $campaignHash{$campaign_id}) {
						populateCampaign($campaign_id,$dbh,0);
					}
					$campaign_name = $campaignHash{$campaign_id};

					$query="select list_name,now() from list where list_id='$list_id'";
					$retval = query_execute($query, $dbh, 1, __LINE__);
					$list_name = @$retval[0];
					my $amd_time = @$retval[1];

					if($lead_id) {
						$query="select name from $cust_remove where lead_id='$lead_id'";
						$retval=query_execute($query,$dbh,1,__LINE__);
						$customer_name=@$retval[0];
						$customer_name =~ s/\'/\\'/g;
					}

					my $provider_name= '';
					my $link_end_date_time= '';
					my $hold_num_time= 0;
					my $cust_category= '';

					$agent_id= '';
					$agent_name= '';
					$link_date_time = '';
					$duration = 0;
					$zap_channel= @$retval[10];
					$monitor_file_name= '';
					$q_enter_time= '';
					$q_leave_time= '';
					$hold_time= 0;
					$cust_disposition= '';
					$remarks= "$hangup_cause";
					$transfer_from= '';

					$call_status= 'ansmc';
					$stateHash_semaphore->down;
					delete $stateHash{$session_id};
					$stateHash_semaphore->up;

					if(defined($dialer_var_channel_id) && ($dialer_var_channel_id !~ /^$/ && $dialer_var_channel_id !~ /^[\s]+$/))
					{
						$channel = $dialer_var_channel;
						$zap_channel = $dialer_var_channel_id;

						if(($channel =~ /Zap/i)) {
							$zap_channel =~ s/ZAP/Zap/g;
							if($zap_channel)
							{
								if (not exists($providernameHash{$zap_channel})) {
									populateprovider($dbh);
								}
								$provider_name=$providernameHash{$zap_channel};
							}
							$channel="ZAP";
						}
						elsif(($channel =~ /SIP/i)) {
							if($zap_channel){
								if (not exists($sip_id_providernameHash{$zap_channel}))
								{
									sip_id_populateprovider($dbh);
								}
								$provider_name=$sip_id_providernameHash{$zap_channel};
							}
							$channel = "SIP";
						}
					}
					elsif(($channel =~ /Zap/i)) {
						$zap_channel=substr($channel,0,index($channel,"-"));
						$zap_channel =~ s/ZAP/Zap/g;
						if($zap_channel)
						{
							if (not exists($providernameHash{$zap_channel})) {
								populateprovider($dbh);
							}
							$provider_name=$providernameHash{$zap_channel};
						}
						$channel="ZAP";
					}
					elsif(($channel =~ /SIP/i)) {
						$zap_channel=substr($channel,index($channel,"/")+1);
						$zap_channel=substr($zap_channel,0,index($zap_channel,"-"));
						if(match_ip($zap_channel)){
							if (not exists($sip_providernameHash{$zap_channel}))
							{
								sip_populateprovider($dbh);
							}
							$provider_name=$sip_providernameHash{$zap_channel};
						}
						else{
							$provider_name=$zap_channel;
						}
						$zap_channel=$channel;
						$channel = "SIP";
					}
					elsif(($channel =~ /Local/i))
					{
						  $zap_channel=$channel;
						  $provider_name="Local";
						  $channel = "Local";
					}
					else
					{
						$zap_channel=$channel;
						$channel = "SIP";
					}

					if($monitor_file_name !~ /^$/ && $monitor_file_name !~ /^[\s]+$/) {
                        $dialer_inserted_field=0;
						if (not exists $new_monitor_flagHash{$campaign_id}) {
							populateCampaign($campaign_id,$dbh,'0');
						}
						$new_monitor_flag  = $new_monitor_flagHash{$campaign_id};

						if($new_monitor_flag == 1)
						{
							$new_monitor_filename = MakeNewMonitorFileName ($dbh,$lead_id,$campaign_id,$list_id,$agent_id,$session_id,$campaign_type,$dialerType,$call_status,$campaign_name,$custphno,$list_name,$CustUniqueId,$lead_attempt_count,$phone_attempt_count,$timestamp);
						}
					}
					else{
					   $dialer_inserted_field=0;
					}
# if there is a timediff between queue enter and leave for less than eq 2 sec then set both the time same.
					$q_enter_time = (($q_leave_time-$q_enter_time <= 2)?$q_leave_time:$q_enter_time);

					$query="select agent_ext from agent_live where agent_id='$agent_id'";
					my $agentidvar=query_execute($query,$dbh,1,__LINE__);
					my $agent_ext=@$agentidvar[0];

					$report_id='';
					$report_query="insert into $table_name (node_id,lead_id,agent_id,agent_ext,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,campaign_type,campaign_channel,zap_channel,monitor_filename,new_monitor_filename,dialer_type,cust_disposition,q_enter_time,q_leave_time,hold_time,hold_num_time,call_status_disposition,cust_category,call_remarks,transfer_status,transfer_from,provider_name,call_charges,next_call_time,entrytime,lead_attempt_count,phone_attempt_count,dialer_remarks,lead_total_max_retry,ph_max_retry,caller_id,dialer_inserted_field) values ('$node_id','$lead_id','$agent_id','$agent_ext','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name','$amd_time','$amd_time','$duration','$campaign_type','$channel','$zap_channel','$monitor_file_name','$new_monitor_filename','$dialerType','$cust_disposition','$amd_time','$amd_time','$hold_time','$hold_num_time','$call_status','$cust_category','$remarks','$transfer_status','$transfer_from','$provider_name','$unit_cost','$nc_time',unix_timestamp('$amd_time'),'$lead_attempt_count','$phone_attempt_count','$dialer_remarks','$lead_retry_count','$phone_retry_count','$callerid','$dialer_inserted_field')";
					$report_id=query_execute($report_query,$dbh,3,__LINE__);

					$report_query="insert into $table_name (report_id,node_id,lead_id,agent_id,agent_ext,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,campaign_type,campaign_channel,zap_channel,monitor_filename,new_monitor_filename,dialer_type,cust_disposition,q_enter_time,q_leave_time,hold_time,hold_num_time,call_status_disposition,cust_category,call_remarks,transfer_status,transfer_from,provider_name,call_charges,next_call_time,entrytime,lead_attempt_count,phone_attempt_count,dialer_remarks,lead_total_max_retry,ph_max_retry,caller_id,dialer_inserted_field) values ('$report_id','$node_id','$lead_id','$agent_id','$agent_ext','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name','$amd_time','$amd_time','$duration','$campaign_type','$channel','$zap_channel','$monitor_file_name','$new_monitor_filename','$dialerType','$cust_disposition','$amd_time','$amd_time','$hold_time','$hold_num_time','$call_status','$cust_category','$remarks','$transfer_status','$transfer_from','$provider_name','$unit_cost','$nc_time',unix_timestamp('$amd_time'),'$lead_attempt_count','$phone_attempt_count','$dialer_remarks','$lead_retry_count','$phone_retry_count','$callerid','$dialer_inserted_field')";
#Adding information to current report
					check_cview($report_query,$dbh,$table_name,1);
					$report_query =~ s/$table_name/current_report/i;
					query_execute($report_query,$dbh,0,__LINE__);
				}
			}

#######AMD Info#############################################################

##############CALL ABANDON BLOCK START######################################
elsif((($thread_type == 6)) && (($command_line[0] =~ /Event: Abandon/) || ($command_line[0] =~ /Event: Dtmf_Exit_Queue/) ) )
			{
				my $ringing_flag=0;
				my $phone_type="";
				my $agent_id="";
				my $miss_agent_id="";
				my $leavecause ='';
				my $transfer_flag=0;
				my $new_monitor_flag=0;
				my $agent_name="";
				my $lead_retry_count = "0";
				my $phone_retry_count = "0";
				my $lead_attempt_count= "0";
				my $phone_attempt_count = "0";
				my $nc_time="";
				my $dialer_remarks = "";
				my $remarks = "";
				my $nct_time="";
				my $new_monitor_filename="";
				my @dialer_remark_array = ();
				my $callerid="";
				my $customer_name="";
				my $skill_id=0;
				my $skill_name="";
				my $park_duration=0;
				my $park_start_time=0;
				my $park_end_time=0;
				my $action_on_event="";
				my $channel_id="";
				my $event_values="";
				my $split_value="";
				my $event_action='';
				my $dialer_inserted_field='0';
				my $lingua;
				my $callcategory;
				my $next_call_time="";
				my $cust_remove="";
				my $dialer_var_channel_id="";
				my $dialer_var_channel="";
				my @dialer_variables=();

				$session_id = substr ($command_line[4], index ($command_line[4], ":") + 2);
				$campaign_name=substr($command_line[2],index($command_line[2],":") + 2);
				$interval=substr($command_line[5],index($command_line[5],":") + 2);
				$returnvar = substr($command_line[6],index($command_line[6],":") + 1);
				$custphno = substr($command_line[7],index($command_line[7],":") + 1);
				$channel = substr($command_line[3],index($command_line[3],":") + 2);
				my $call_type = substr($command_line[8],index($command_line[8],":") + 2);
				my $CustUniqueId = substr($command_line[9],index($command_line[9],":") + 2);
				my $sticky_agent_id=substr($command_line[10],index($command_line[10],"/") + 1);

				$custphno =~ s/^\s+//;
				$preview_call = 0;
				$hangup_cause = substr($command_line[12],index($command_line[12],":") + 2);
				$q_enter_time = substr($command_line[13],index($command_line[13],":") + 2);
				$q_leave_time = substr($command_line[14],index($command_line[14],":") + 2);
				$did_num = substr($command_line[17],index($command_line[17],":") + 2);
				$skill_id= substr($command_line[18],index($command_line[18],":") + 2);
				my $reason = substr($command_line[0],index($command_line[0],":") + 2);
				my $dialer_var= substr($command_line[16],index($command_line[16],":") + 2);
				my $ivrsPath =  substr($command_line[20],index($command_line[20],":") + 2);
				my $attempt_count =  substr($command_line[21],index($command_line[21],":") + 2);
				$leavecause = substr($command_line[22],index($command_line[22],":") + 2);
				my $ringstart = substr($command_line[23],index($command_line[23],":") + 2);
				my $ringend = substr($command_line[24],index($command_line[24],":") + 2);
				my $CallPicked = substr($command_line[25],index($command_line[25],":") + 2);
				$lingua=substr($command_line[26],index($command_line[26],":") + 2);
				$callcategory=substr($command_line[27],index($command_line[27],":") + 2);
				if(defined($skill_id) && ($skill_id !~ /^$/ && $skill_id !~ /^[\s]+$/))
				{
				   $skill_id = ($skill_id==-1?"0":$skill_id);
				}

				if(defined($CallPicked) && $CallPicked) {
					$ringing_flag=2;
				}
				elsif(defined($ringstart) && $CallPicked == 0 )
				{
					$ringing_flag = 1;
				}


# if($attempt_count!='0' && (defined($attempt_count) && ($attempt_count !~ /^$/ && $attempt_count !~ /^[\s]+$/)))
#{
#        $ringing_flag=1;

#}
				if($leavecause eq "Queue Timeout") {
					$leavecause="QT";
				}
				else {
					$leavecause="CD";
				}

				my $redial_flag=0;
				my $call_back_live=0;
				my $concurrent_call=0;
				my $provider_name="";
				my $strict_flag;
				my $lead_id="";
				my $list_id="";
				my $list_name="";
				my $zap_channel="";
				my $unit_cost = 0;
				my $from_campaign="";

				init_stateHash($session_id);

				if($campaign_name =~ /preview/)
				{
					$campaign_name = substr($campaign_name,8);
					$preview_call=1;
				}

				if(!$call_type) {
					$query="select concurrent_calls from queue_live where session_id=$session_id";
					$retval = query_execute($query, $dbh, 1, __LINE__);
					$concurrent_call = (defined(@$retval[0])?@$retval[0]:"");
				}

				if (not exists $campaignNameHash{$campaign_name}) {
					populateCampaign($campaign_name,$dbh,'1');
				}
				$campaign_id = $campaignNameHash{$campaign_name};

				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$custphno=$variables[0];
					$lead_id=$variables[1];
					$from_campaign=$variables[2];
					$list_id=$variables[3];
					$strict_flag=$variables[4];
					$dialerType =$variables[5];
					$transfer_from=$variables[6];
					$transfer_flag = (defined($variables[6])?1:0);

					$dialer_var=~ s/\s+//g;
					my @dialer_variables=split(/,/,$dialer_var);
					$phone_type = (defined($dialer_variables[0])?$dialer_variables[0]:"");
					$redial_flag= (defined($dialer_variables[4])?$dialer_variables[4]:"0");
					$call_back_live= (defined($dialer_variables[5])?$dialer_variables[5]:"0");
					$lead_retry_count = (defined($dialer_variables[1])?$dialer_variables[1]:"");
					$phone_retry_count = (defined($dialer_variables[2])?$dialer_variables[2]:"");
					$next_call_time = (defined($dialer_variables[3])?$dialer_variables[3]:"");
					$lead_attempt_count=((defined($dialer_variables[8]) && ($dialer_variables[8] !~ /^$/ && $dialer_variables[8]!= /^[\s]+$/))?$dialer_variables[8]:"0");
					$phone_attempt_count=((defined($dialer_variables[9]) && ($dialer_variables[9] !~ /^$/ && $dialer_variables[9]!= /^[\s]+$/))?$dialer_variables[9]:"0");
					$dialer_var_channel = ((defined($dialer_variables[10]) && ($dialer_variables[10] !~ /^$/ && $dialer_variables[10] !~ /^[\s]+$/))?$dialer_variables[10]:"");
					$dialer_var_channel_id = ((defined($dialer_variables[11]) && ($dialer_variables[11] !~ /^$/ && $dialer_variables[11] !~ /^[\s]+$/))?$dialer_variables[11]:"");
					$callerid=(defined($dialer_variables[16])?$dialer_variables[16]:"0");
					$lead_retry_count = $lead_retry_count + 1;
					$phone_retry_count = $phone_retry_count + 1;
					$lead_attempt_count= $lead_attempt_count + 1;
					$phone_attempt_count=$phone_attempt_count + 1;
           		          
					if(defined($next_call_time) && ($next_call_time !~ /^$/ && $next_call_time!= /^[\s]+$/)){
						$call_back_live=1;
					}

					my @params=split(/\//,$command_line[10]);
					$agent_id=$params[1];

					if(defined($agent_id) && $agent_id) {
						if (not exists $agentHash{$agent_id}) {
							populateAgent($agent_id,$dbh);
						}
						$agent_name = $agentHash{$agent_id};
					}


					if(defined($transfer_from) && ($transfer_from !~ /^$/ && $transfer_from !~ /^[\s]+$/)) {
						if (not exists $campaignNameHash{$campaign_name}) {
							populateCampaign($campaign_name,$dbh,'1');
						}
						$campaign_id = $campaignNameHash{$campaign_name};
						$redial_flag="0";
						$call_back_live="0";
					}

					if (!defined($transfer_from)){
						$transfer_from="";
					}
					if(!$lead_id) {
						$list_id=0;
						$list_name="Manual Dial";
					}
					else {
						$query="select list_name from list where list_id='$list_id'";
						$retval = query_execute($query, $dbh, 1, __LINE__);
						$list_name = @$retval[0];
					}

					if($call_type && !$preview_call && $lead_id > 0 && $list_id > 0 && !$redial_flag) {
						$nct_time = setDisposition($dbh,$lead_id,$campaign_id,$list_id,$dialer_var,"abandon",$strict_flag,$custphno);
					}
					if(defined($nct_time)){
						@dialer_remark_array=split('@@',$nct_time);

					}
					$nc_time = (defined($dialer_remark_array[0])?$dialer_remark_array[0]:"");
					$dialer_remarks = (defined($dialer_remark_array[1])?$dialer_remark_array[1]:"");


					if(($redial_flag && !$preview_call) || (defined($preview_call) && $preview_call)) {
						$query="delete from callProgress where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);
					}
				}

				if($preview_call) {
					$dialerType = "PREVIEW";
					$preview_call=0;
				}
				else {
					$query="delete from queue_live where session_id=$session_id";
					query_execute($query, $dbh,0, __LINE__);

					if($call_type) {
						if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
						{
							$query="update listener_status set queue=queue - 1,abandon = abandon + 1,aban_avg_time=(aban_avg_time + $interval)/abandon where list_id='$list_id' and dialing_date=curdate()";
							query_execute($query,$dbh,0,__LINE__);
						}
					}
					else {
						$dialerType = "PROGRESSIVE";
					}
				}

				$call_type = ($call_type=="0"?"INBOUND":"OUTBOUND");

				if($call_type eq "INBOUND")
				{
					insert_data($dbh,$campaign_id,$custphno,$did_num,$interval,$CustUniqueId,$skill_id,$cust_remove_flag);
				}
             

				if ($dialerType =~ "PREVIEW" && ((!defined($transfer_from) || ($transfer_from =~ /^$/ || $transfer_from =~ /^[\s]+$/))))
				{
						my $noans_campaign_id=((defined($from_campaign) && ($from_campaign !~ /^$/ && $from_campaign!= /^[\s]+$/))?$from_campaign:$campaign_id);
						$query="update agent_live set closer_time=unix_timestamp(),agent_state='CLOSURE',session_id='$session_id',lead_id='$lead_id',is_free=1,preview_fail=1,from_campaign='$noans_campaign_id',last_lead_id='$lead_id',last_cust_ph_no='$custphno',trying_flag=0,trying_cust_ph_no=0,call_type='1685' where agent_id='$agent_id'";
						query_execute($query,$dbh,0,__LINE__);

						$remarks = substr($command_line[12],index($command_line[12],":") + 2);
						$call_status = 'noans';
				}
				else
				{
					if($redial_flag) {
						$call_status='noans';
						$dialer_inserted_field = 1;
						$remarks="call re-dialed by $agent_id failed to connect.";
						$agent_id="";
						$agent_name="";
					}
					else {
						$call_status="abandon";
						if($reason =~ /Dtmf_Exit_Queue/i){
					           $leavecause="DTMF EXIT";
				        }

						$dialer_inserted_field = 0;
						if(defined($agent_id) && ($agent_id !~ /^$/ && $agent_id !~ /^[\s]+$/) && $agent_id) {
							$remarks=($call_back_live?"Schduled call back for agent $agent_id":"Fresh call for agent $agent_id");
						}
						$agent_id="";
					}
				}
				$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");


				if($lead_id) {
					$query="select name from $cust_remove where lead_id='$lead_id'";
					$retval=query_execute($query,$dbh,1,__LINE__);
					$customer_name=(defined(@$retval[0])?@$retval[0]:"");
					if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/)){
						$customer_name =~ s/\'/\\'/g;
					}
				}
				$query="select unix_timestamp()";
				my $tmp=query_execute($query,$dbh,1,__LINE__);
				my $link_end_date_time = @$tmp[0];

				my $hold_num_time=0;
				my $cust_category="";
				$hold_time=0;
				my $transfer_status="";
				$duration=0;
				my $link_date_time=$q_leave_time;
				if($call_status eq "noans")
				{
					$link_end_date_time=$link_date_time;
				}
				$customer_name="";
				$cust_disposition="";
				$monitor_file_name='';
				if(!defined($agent_id))
				{
					$agent_id="";
				}

				if(defined($ringing_flag) && $ringing_flag) {
					$query="select miss_agent_id from missed_call_status where session_id=$session_id";
					$retval = query_execute($query, $dbh, 1, __LINE__);
					if(defined(@$retval[0])){
						$miss_agent_id = @$retval[0];
						$remarks=$remarks."Missed Call ($miss_agent_id)";

						$query="delete from missed_call_status where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);
					}
				}

				if(defined($remarks) && $remarks =~ /Missed Call/)
				{
					$remarks=$remarks.","."$leavecause";
				}
				else
				{
					$remarks=$remarks."$leavecause";
				}
				if(!defined($miss_agent_id))
				{
					$remarks='';
					$remarks=$remarks."$leavecause";
				}

				if(defined($skill_id) && ($skill_id !~ /^$/ && $skill_id !~ /^[\s]+$/) && $skill_id > 0)
				{
					if (not exists($campaignSkillHash{$skill_id."_".$campaign_id})) {
						populateSkill($dbh);
					}
					$skill_name=$campaignSkillHash{$skill_id."_".$campaign_id};
				}

				$query="select park_start_time,park_end_time from park_live where session_id=$session_id";
				$retval = query_execute($query, $dbh, 1, __LINE__);
				if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/)){
					$park_start_time=@$retval[0];
					$park_end_time=@$retval[1];
				}

				$query="select agent_ext from agent_live where agent_id='$agent_id'";
				my $agentidvar=query_execute($query,$dbh,1,__LINE__);
				my $agent_ext=((defined(@$agentidvar[0]) && (@$agentidvar[0] !~ /^$/ && @$agentidvar[0] !~ /^[\s]+$/))?@$agentidvar[0]:"");

				if(defined($dialer_var_channel_id) && ($dialer_var_channel_id !~ /^$/ && $dialer_var_channel_id !~ /^[\s]+$/))
				{
					$channel = $dialer_var_channel;
					$zap_channel = $dialer_var_channel_id;

					if(($channel =~ /Zap/i)) {
						$zap_channel =~ s/ZAP/Zap/g;
						if($zap_channel)
						{
							if (not exists($providernameHash{$zap_channel})) {
								populateprovider($dbh);
							}
							$provider_name=$providernameHash{$zap_channel};
						}
						$channel="ZAP";
					}
					elsif(($channel =~ /SIP/i)) {
						if($zap_channel){
							if (not exists($sip_id_providernameHash{$zap_channel}))
							{
								sip_id_populateprovider($dbh);
							}
							$provider_name=$sip_id_providernameHash{$zap_channel};
						}
						$channel = "SIP";
					}
				}
				elsif(($channel =~ /Zap/i)) {
					$zap_channel=substr($channel,0,index($channel,"-"));
					$zap_channel =~ s/ZAP/Zap/g;
					if($zap_channel)
					{
						if (not exists($providernameHash{$zap_channel})) {
							populateprovider($dbh);
						}
						$provider_name=$providernameHash{$zap_channel};
					}
					$channel="ZAP";
				}
				elsif(($channel =~ /SIP/i)) {
					$zap_channel=substr($channel,index($channel,"/")+1);
					$zap_channel=substr($zap_channel,0,index($zap_channel,"-"));
					if(match_ip($zap_channel)){
						if (not exists($sip_providernameHash{$zap_channel}))
						{
							sip_populateprovider($dbh);
						}
						$provider_name=$sip_providernameHash{$zap_channel};
					}
					else{
						$provider_name=$zap_channel;
					}
					$zap_channel=$channel;
					$channel = "SIP";
				}
				elsif(($channel =~ /Local/i))
				{
					  $zap_channel=$channel;
					  $provider_name="Local";
					  $channel = "Local";
				}
				else
				{
					$zap_channel=$channel;
					$channel = "SIP";
				}


				$report_id='';
				$report_query="insert into $table_name (node_id,lead_id,agent_id,agent_ext,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,campaign_type,campaign_channel,zap_channel,monitor_filename,new_monitor_filename,dialer_type,cust_disposition,q_enter_time,q_leave_time,hold_time,hold_num_time,call_status_disposition,cust_category,call_remarks,transfer_status,transfer_from,provider_name,call_charges,dialer_inserted_field,skills,did_num,CustUniqueId,redial_flag,callback_flag,concurrent_calls,next_call_time,entrytime,ph_type,ivrs_path,park_start_time,park_end_time,dialer_remarks,lead_attempt_count,phone_attempt_count,lead_total_max_retry,ph_max_retry,ringing_flag,caller_id,language,callcategory,sticky_agent_id) values ('$node_id','$lead_id','$agent_id','$agent_ext','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name',from_unixtime('$link_date_time'),from_unixtime('$link_end_date_time'),'$duration','$call_type','$channel','$zap_channel','$monitor_file_name','$new_monitor_filename','$dialerType','$cust_disposition',from_unixtime('$q_enter_time'),from_unixtime('$q_leave_time'),'$hold_time','$hold_num_time','$call_status','$cust_category','$remarks','$transfer_status','$transfer_from','$provider_name','$unit_cost','$dialer_inserted_field','$skill_name','$did_num','$CustUniqueId','$redial_flag','$call_back_live','$concurrent_call','$nc_time','$link_end_date_time','$phone_type','$ivrsPath','$park_start_time','$park_end_time','$dialer_remarks','$lead_attempt_count','$phone_attempt_count','$lead_retry_count','$phone_retry_count','$ringing_flag','$callerid','$lingua','$callcategory','$sticky_agent_id')";
# Current report table session id check needs lock as different packets can insert same data #
				$query="select 4 from current_report where session_id=$session_id and entrytime='$link_end_date_time'";
				$returnvar=query_execute($query,$dbh,1,__LINE__);
				if(!defined (@$returnvar[0]))
				{
					$report_id=query_execute($report_query,$dbh,3,__LINE__);
					$report_query="insert into $table_name (report_id,node_id,lead_id,agent_id,agent_ext,agent_name,session_id,campaign_id,campaign_name,list_id,list_name,cust_ph_no,cust_name,call_start_date_time,call_end_date_time,call_duration,campaign_type,campaign_channel,zap_channel,monitor_filename,new_monitor_filename,dialer_type,cust_disposition,q_enter_time,q_leave_time,hold_time,hold_num_time,call_status_disposition,cust_category,call_remarks,transfer_status,transfer_from,provider_name,call_charges,dialer_inserted_field,skills,did_num,CustUniqueId,redial_flag,callback_flag,concurrent_calls,next_call_time,entrytime,ph_type,ivrs_path,park_start_time,park_end_time,dialer_remarks,lead_attempt_count,phone_attempt_count,lead_total_max_retry,ph_max_retry,ringing_flag,caller_id,language,callcategory,sticky_agent_id) values ('$report_id','$node_id','$lead_id','$agent_id','$agent_ext','$agent_name','$session_id','$campaign_id','$campaign_name','$list_id','$list_name','$custphno','$customer_name',from_unixtime('$link_date_time'),from_unixtime('$link_end_date_time'),'$duration','$call_type','$channel','$zap_channel','$monitor_file_name','$new_monitor_filename','$dialerType','$cust_disposition',from_unixtime('$q_enter_time'),from_unixtime('$q_leave_time'),'$hold_time','$hold_num_time','$call_status','$cust_category','$remarks','$transfer_status','$transfer_from','$provider_name','$unit_cost','$dialer_inserted_field','$skill_name','$did_num','$CustUniqueId','$redial_flag','$call_back_live','$concurrent_call','$nc_time','$link_end_date_time','$phone_type','$ivrsPath','$park_start_time','$park_end_time','$dialer_remarks','$lead_attempt_count','$phone_attempt_count','$lead_retry_count','$phone_retry_count','$ringing_flag','$callerid','$lingua','$callcategory','$sticky_agent_id')";
#Adding information to current report
					check_cview($report_query,$dbh,$table_name,1);
					$report_query =~ s/$table_name/current_report/i;
					query_execute($report_query,$dbh,0,__LINE__);
				}

				$query="delete from park_live where session_id=$session_id";
				query_execute($query, $dbh,0, __LINE__);

				$stateHash_semaphore->down;
				$stateHash{$session_id} = $stateHash{$session_id} | 1;
				$stateHash_semaphore->up;
				del_stateHash($session_id);
			}
##############CALL ABANDON BLOCK END######################################

############ROBO DIALER START##################################################
			elsif (($thread_type == 11) && ($command_line[0] =~ /Event: Robodial/))
			{
				my $custphno;
				my $campaign_id;
				my $robostartTime=0;
				my $lead_id=0;
				my $session_id;
				my $transfer_from;
                my $dialtype="";
				my @variables=();

				$channel=substr($command_line[2],index($command_line[2],":") + 2);
				$session_id=substr($command_line[3],index($command_line[3],":") + 2);
				$campaign_name=substr($command_line[6],index($command_line[6],":") + 2);
				$returnvar ="";
				$custphno = substr($command_line[4],index($command_line[4],":") + 1);
				$custphno =~ s/^\s+//;
				$returnvar = substr($command_line[7],index($command_line[7],":") + 1);
				$robostartTime= substr($command_line[8],index($command_line[8],":") + 1);

				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$custphno=$variables[0];
					$lead_id=$variables[1];
					$campaign_id=$variables[2];
					$list_id=$variables[3];
					$strict=$variables[4];
                    $dialtype = $variables[5];
					$transfer_from=$variables[6];
					if($dialtype =~ /AUTODIAL/) {
					   $transfer_from="ROBO";
					}
				}
 
				$query="replace into call_dial_status(cust_ph_no,campaign_id,q_enter_time,lead_id,session_id,transfer_from) values ('$custphno','$campaign_id',from_unixtime('$robostartTime'),'$lead_id','$session_id','$transfer_from')";
				query_execute($query,$dbh,0,__LINE__);

				if($channel =~ /sip/i)
				{
					$query="select 1 from sip where session_id=$session_id";
					$retval=query_execute($query,$dbh,1,__LINE__);
					if(!defined(@$retval[0]))
					{
						$query="select sip_id from sip where status='FREE' and campaign_id = '$campaign_id' limit 1";
						$retval=query_execute($query,$dbh,1,__LINE__);
						if(defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/))
						{
							$query="update sip set status='BUSY',session_id='$session_id',flow_state='1' where sip_id='@$retval[0]'";
							query_execute($query,$dbh,0,__LINE__);
						}
					}
				}
			}
############ROBO DIALER END####################################################


##############Robodisconnect BLOCK START######################################
			elsif(($thread_type == 11) && (($command_line[0] =~ /Event: Robodisconnect/) ))
			{
				if($command_line[2] =~ /sip/i || $command_line[2] =~/zap/i)
				{
					my $channel = substr($command_line[2],index($command_line[2],":") + 2);
					my $session_id = substr($command_line[3],index($command_line[3],":") + 2);
					my $returnvar = substr($command_line[6],index($command_line[6],":") + 1);
					my $campaign_type = substr($command_line[8],index($command_line[8],":") + 2);
					my $DialerVar= substr($command_line[13],index($command_line[13],":") + 2);
					my $skill_id= substr($command_line[14],index($command_line[14],":") + 2);
					my $Robodisconnect_time = substr($command_line[16],index($command_line[16],":") + 2);
					my $ivrnodeid=substr($command_line[18],index($command_line[18],":") + 2);
					my $nct_time_flag = substr($command_line[20],index($command_line[20],":") + 2);
					my $lingua = substr($command_line[21],index($command_line[21],":") + 2);
					my $callcategory = substr($command_line[22],index($command_line[22],":") + 2);

					my $dialerType = "PROGRESSIVE";
					$campaign_type = "OUTBOUND";
					my $call_status="answered";
					my $lead_retry_count = 0;
					my $phone_retry_count = 0;
					my $lead_attempt_count= 0;
					my $phone_attempt_count = 0;
					my $per_day_mx_retry_count = 0;
					my $ringing_flag = 1;
					my $gmt_timestamp=get_gmt_time($timestamp);
					my $exnct=0;
					my $phone_type=101;
					my $provider_name="";
					my $cust_ph_no="";
					my $dialer_type="";
					my $ivrs_path="";
					my $custuniqueid;
					my $robo_lead_state=0;
					my $next_call_time=0;
					my $dialer_remarks="";
					my $callerid="";
					my $cust_remove="";
					my $link_date_time=0;
					my $duration=0;
					my $skill_name="";
                    my $next_phone_dial=0;
					my $dialer_var_channel="";
					my $dialer_var_channel_id="";
					my @dialer_variables=();

					if($nct_time_flag == '1')
					{
						$exnct=$gmt_timestamp + 86400;
						$next_call_time=$exnct;
					}
					else{
						$exnct=$timestamp + 14400;
					}

					if($ivr_license) {
						$ivrs_path = substr($command_line[7],index($command_line[7],":") + 2);
					}
					
					if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
					{
						my @variables=();
						$returnvar=~ s/\s+//g;
						@variables=split(/,/,$returnvar);
						$custphno=$variables[0];
						$lead_id=$variables[1];
						$campaign_id=$variables[2];
						$list_id=$variables[3];
						$strict=$variables[4];
						$dialerType=$variables[5];
						$transfer_from=$variables[6];

						if(defined($DialerVar) && ($DialerVar !~ /^$/ && $DialerVar !~ /^[\s]+$/))
						{
							$DialerVar=~ s/\s+//g;
							@dialer_variables=split(/,/,$DialerVar);
							$phone_type=$variables[0];
							$lead_retry_count = (defined($dialer_variables[1])?$dialer_variables[1]:"0");
							$phone_retry_count = (defined($dialer_variables[2])?$dialer_variables[2]:"0");
							$lead_attempt_count=(defined($dialer_variables[8])?$dialer_variables[8]:"0");
							$phone_attempt_count=(defined($dialer_variables[9])?$dialer_variables[9]:"0");
							$dialer_var_channel = ((defined($dialer_variables[10]) && ($dialer_variables[10] !~ /^$/ && $dialer_variables[10] !~ /^[\s]+$/))?$dialer_variables[10]:"");
                            $dialer_var_channel_id = ((defined($dialer_variables[11]) && ($dialer_variables[11] !~ /^$/ && $dialer_variables[11] !~ /^[\s]+$/))?$dialer_variables[11]:"");
							$custuniqueid=(defined($dialer_variables[12])?$dialer_variables[12]:"0");
							$callerid=(defined($dialer_variables[16])?$dialer_variables[16]:"0");
							$per_day_mx_retry_count=(defined($dialer_variables[19])?$dialer_variables[19]:"0");
						}

						if(defined($skill_id) && ($skill_id !~ /^$/ && $skill_id !~ /^[\s]+$/) && $skill_id > 0)
						{
							if (not exists($campaignSkillHash{$skill_id."_".$campaign_id})) {
								populateSkill($dbh);
							}
							$skill_name=$campaignSkillHash{$skill_id."_".$campaign_id};
						}

						$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");

						if($call_status eq "answered")
						{
							$dialer_remarks = "RoboDial | Finished";
							if (not exists $campaignmax{$campaign_id}) {
								populateCampaign($campaign_id,$dbh,'1');
							}
							my $totalMax = $campaignmax{$campaign_id};

							my $totalMaxlled = (((defined($totalMax) && $totalMax) && $campaign_type eq "OUTBOUND")?",total_max_retries = total_max_retries +1":",total_max_retries =0") ;
							my $Maxph = (((defined($totalMax) && $totalMax) && $campaign_type eq "OUTBOUND")?",max_retries = if(ph_type='$phone_type',max_retries +1,max_retries)":",max_retries = if(ph_type='$phone_type',0,max_retries)") ;
							my $extMaxph = (((defined($totalMax) && $totalMax) && $campaign_type eq "OUTBOUND")?",max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." +1":",max_retries_".($phone_type-100)."=0") ;
							if($nct_time_flag=='1'){
								$dialer_remarks = "RoboDial | nct set";
								$robo_lead_state = '1';
								$exnct=$gmt_timestamp + 86400;
								$next_call_time=$exnct;
							}
							else
							{
								$exnct=$timestamp + 14400;
							}
							$query="update extended_customer_$campaign_id set num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_connect_count=total_connect_count+1,total_num_times_dialed=total_num_times_dialed+1".($lead_attempt_count?"":",first_dial_time=now()").",first_success_time=if(first_success_time='0000-00-00 00:00:00' or first_success_time='',now(),first_success_time),next_call_time='$exnct',gmt_next_call_time='$gmt_timestamp',last_call_disposition='answered',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),lead_state='$robo_lead_state',".($phone_type?"call_disposition_".($phone_type-100)."='answered',connect_count_".($phone_type-100)."=connect_count_".($phone_type-100)." + 1":"")." $totalMaxlled$extMaxph where lead_id='$lead_id'";
							query_execute($query,$dbh,0,__LINE__);

							if ($lead_attempt_count<=9) {
								$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',phone_state_$lead_attempt_count='0',dial_state_$lead_attempt_count='0',next_call_time_$lead_attempt_count='$exnct',disposition_$lead_attempt_count='answered',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_state='0',first_success_time=if(first_success_time='0' or first_success_time='',unix_timestamp(),first_success_time),lead_attempt_count=$lead_attempt_count+1,last_lead_status='1' where lead_id='$lead_id'";
								query_execute($query, $dbh,0, __LINE__);
							}


							$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count=$lead_attempt_count+1,per_day_mx_retry_count=$per_day_mx_retry_count+1,lead_state='$robo_lead_state',next_call_time='$exnct',phone_attempt_count=$phone_attempt_count+1$totalMaxlled$Maxph where lead_id='$lead_id' ".($phone_type?" and ph_type = '$phone_type'":"")."";
							query_execute($query,$dbh,0,__LINE__);

#---camapig
							$query="update dial_Lead_$campaign_id set lead_attempt_count=$lead_attempt_count+1,per_day_mx_retry_count=$per_day_mx_retry_count+1,lead_state='$robo_lead_state',next_call_time='$exnct',phone_attempt_count=$phone_attempt_count+1$totalMaxlled$Maxph where lead_id='$lead_id' ".($phone_type?" and ph_type = '$phone_type'":"")."";
							query_execute($query,$dbh,0,__LINE__);

							$lead_retry_count=$lead_retry_count+1;
							$phone_retry_count=$phone_retry_count+1;
							$lead_attempt_count=$lead_attempt_count+1;
							$phone_attempt_count=$phone_attempt_count+1;

							if($nct_time_flag > 1){
									$dialer_remarks = "RoboDial | nct set | ph2";
									$robo_lead_state = '1';
									$exnct=$gmt_timestamp - 300;
									$next_call_time=$exnct;
									$next_phone_dial=1;
									$next_phone_type="10$nct_time_flag";
							}

							if($next_phone_dial==1){

							 $query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count',phone_attempt_count=if($phone_type = $next_phone_type,phone_attempt_count + 1,0),next_call_time='$exnct',lead_state='$robo_lead_state',dial_state=if(ph_type='$next_phone_type',1,0),phone_dial_flag=if(ph_type='$next_phone_type',1,0),max_retries = if(ph_type='$next_phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count where lead_id='$lead_id'";
							 query_execute($query, $dbh,0, __LINE__);

							 $query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count',phone_attempt_count=if($phone_type = $next_phone_type,phone_attempt_count + 1,0),next_call_time='$exnct',lead_state='$robo_lead_state',dial_state=if(ph_type='$next_phone_type',1,0),phone_dial_flag=if(ph_type='$next_phone_type',1,0),max_retries = if(ph_type='$next_phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count  where lead_id='$lead_id'";
							 query_execute($query,$dbh,0,__LINE__);

							}
						}      

						$query="select unix_timestamp(q_enter_time) from call_dial_status where session_id=$session_id";
						$retval=query_execute($query,$dbh,1,__LINE__);
						$link_date_time= ((defined(@$retval[0]) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/))?@$retval[0]:$timestamp);
						$duration = $Robodisconnect_time - $link_date_time;

						$query="select list_name from list where list_id='$list_id'";
						$retval=query_execute($query,$dbh,1,__LINE__);
						$list_name=@$retval[0];

						$retval="";
						$query="select name from $cust_remove where lead_id='$lead_id'";
						$retval=query_execute($query,$dbh,1,__LINE__);
						$customer_name=@$retval[0];
						$customer_name =~ s/\'/\\'/g;

						if (not exists $campaignHash{$campaign_id}) {
							populateCampaign($campaign_id,$dbh,'0');
						}
						$campaign_name = $campaignHash{$campaign_id};

						if(defined($dialer_var_channel_id) && ($dialer_var_channel_id !~ /^$/ && $dialer_var_channel_id !~ /^[\s]+$/))
						{
							$channel = $dialer_var_channel;
							$zap_channel = $dialer_var_channel_id;

							if(($channel =~ /Zap/i)) {
								$zap_channel =~ s/ZAP/Zap/g;
								if($zap_channel)
								{
									if (not exists($providernameHash{$zap_channel})) {
										populateprovider($dbh);
									}
									$provider_name=$providernameHash{$zap_channel};
								}
								$channel="ZAP";
							}
							elsif(($channel =~ /SIP/i)) {
								if($zap_channel){
									if (not exists($sip_id_providernameHash{$zap_channel}))
									{
										sip_id_populateprovider($dbh);
									}
									$provider_name=$sip_id_providernameHash{$zap_channel};
								}
								$channel = "SIP";
							}
						}
						elsif(($channel =~ /Zap/i)) {
							$zap_channel=substr($channel,0,index($channel,"-"));
							$zap_channel =~ s/ZAP/Zap/g;
							if($zap_channel)
							{
								if (not exists($providernameHash{$zap_channel})) {
									populateprovider($dbh);
								}
								$provider_name=$providernameHash{$zap_channel};
							}
							$channel="ZAP";
						}
						elsif(($channel =~ /SIP/i)) {
							$zap_channel=substr($channel,index($channel,"/")+1);
							$zap_channel=substr($zap_channel,0,index($zap_channel,"-"));
							if(match_ip($zap_channel)){
								if (not exists($sip_providernameHash{$zap_channel}))
								{
									sip_populateprovider($dbh);
								}
								$provider_name=$sip_providernameHash{$zap_channel};
							}
							else{
								$provider_name=$zap_channel;
							}
							$zap_channel=$channel;
							$channel = "SIP";
						}
						elsif(($channel =~ /Local/i))
						{
							  $zap_channel=$channel;
							  $provider_name="Local";
							  $channel = "Local";
						}
						else
						{
							$zap_channel=$channel;
							$channel = "SIP";
						}

						$report_id='';
						$report_query = "insert into $table_name (node_id,campaign_id,campaign_name,campaign_type,q_enter_time,q_leave_time,call_start_date_time,call_end_date_time,zap_channel,call_duration,call_status_disposition,dialer_type,session_id,cust_ph_no,list_id,list_name,lead_id,entrytime,ph_type,provider_name,lead_attempt_count,phone_attempt_count,lead_total_max_retry,ph_max_retry,skills,ivrs_path,next_call_time,CustUniqueId,ringing_flag,dialer_remarks,caller_id,language,callcategory) values  ('$node_id','$campaign_id','$campaign_name','$campaign_type','$channel',from_unixtime('$link_date_time'),from_unixtime('$link_date_time'),from_unixtime('$link_date_time'),from_unixtime('$Robodisconnect_time'),'$zap_channel','$duration','$call_status','$dialerType','$session_id','$custphno','$list_id','$list_name','$lead_id','$Robodisconnect_time','$phone_type','$provider_name','$lead_attempt_count','$phone_attempt_count','$lead_retry_count','$phone_retry_count','$skill_name','$ivrs_path','$next_call_time','$custuniqueid','$ringing_flag','$dialer_remarks','$callerid','$lingua','$callcategory')";
						$report_id=query_execute($report_query,$dbh,3,__LINE__);

						$report_query = "insert into $table_name (report_id,node_id,campaign_id,campaign_name,campaign_type,campaign_channel,q_enter_time,q_leave_time,call_start_date_time,call_end_date_time,zap_channel,call_duration,call_status_disposition,dialer_type,session_id,cust_ph_no,list_id,list_name,lead_id,entrytime,ph_type,provider_name,lead_attempt_count,phone_attempt_count,lead_total_max_retry,ph_max_retry,skills,ivrs_path,next_call_time,CustUniqueId,ringing_flag,dialer_remarks,caller_id,language,callcategory) values  ('$report_id','$node_id','$campaign_id','$campaign_name','$campaign_type','$channel',from_unixtime('$link_date_time'),from_unixtime('$link_date_time'),from_unixtime('$link_date_time'),from_unixtime('$Robodisconnect_time'),'$zap_channel','$duration','$call_status','$dialerType','$session_id','$custphno','$list_id','$list_name','$lead_id','$Robodisconnect_time','$phone_type','$provider_name','$lead_attempt_count','$phone_attempt_count','$lead_retry_count','$phone_retry_count','$skill_name','$ivrs_path','$next_call_time','$custuniqueid','$ringing_flag','$dialer_remarks','$callerid','$lingua','$callcategory')";
						check_cview($report_query,$dbh,$table_name,1);
						$report_query =~ s/$table_name/current_report/i;
						query_execute($report_query,$dbh,0,__LINE__);

						$query="delete from call_dial_status where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);


						if($ivr_license) {
#IVRS PATH
							if(defined $ivrs_path && ($ivrs_path !~ /^$/ && $ivrs_path !~ /^[\s]+$/))
							{
								my $leaf_node;
								my @leafval=();
								my $cust_num;
								my $channel;
								my $campaign_name;
								my $unlink_date_time;
								@leafval = split(/->/,$ivrs_path);
								$leaf_node = pop(@leafval);
								if (!defined($unlink_date_time)) {
									$unlink_date_time= "";
								}
								if (!defined($dialerType)) {
									$dialerType= "";
								}

								$query="select '$node_id',session_id,link_date_time,if(unlink_date_time='0000-00-00 00:00:00',now(),unlink_date_time) as unlink_date_time,'$ivrs_path' as ivrs_path, cust_ph_no,'$leaf_node' as ivrs_leaf_node,CampaignTransfer,unix_timestamp(if(unlink_date_time='0000-00-00 00:00:00',now(),unlink_date_time)) - unix_timestamp(link_date_time) as duration,'$dialerType' as dialer_type,zap_channel,campaignEnded from ivr_call_dial_status where session_id=$session_id";
								$retval=query_execute($query,$dbh,1,__LINE__);
								$link_date_time=@$retval[2];
								$unlink_date_time=@$retval[3];
								$ivrs_path=@$retval[4];
								$cust_ph_no=@$retval[5];
								my $ivrs_leaf_node=@$retval[6];
								my $campaigntransfer=@$retval[7];
								$duration=@$retval[8];
								$dialer_type=@$retval[9];
								$channel=@$retval[10];
								my $campaignended=@$retval[11];
								if(($channel =~ /Zap/i)) {
									$channel=substr($channel,0,index($channel,"-"));
								}
								else {
									$channel = "SIP";
								}

                                my $node_name=""; 
								if((defined($ivrnodeid) && ($ivrnodeid !~ /^$/ && $ivrnodeid !~ /^[\s]+$/)))
								{
									if (not exists($ivrinfo{$ivrnodeid})) {
										populateivrinfo($dbh);
									}
									$node_name=$ivrinfo{$ivrnodeid};
								}

								if(!defined ($campaignended) || ($campaignended =~ /^$/ || $campaignended =~ /^[\s]+$/))
								{
									$campaignended="$campaign_name";
								}

								if(!defined ($campaigntransfer) || ($campaigntransfer =~ /^$/ || $campaigntransfer =~ /^[\s]+$/))
								{
									$campaigntransfer="$campaign_name";
								}

								$report_id='';
								$query = "insert into ivr_report_$table_name (node_id,session_id,link_date_time,unlink_date_time,ivrs_path,cust_ph_no,ivrs_leaf_node,CampaignTransfer,duration,dialer_type,zap_channel,CampaignEnded,skills,entrytime,ivr_node_name,language,callcategory)  values ('$node_id','$session_id','$link_date_time','$unlink_date_time','$ivrs_path','$cust_ph_no','$ivrs_leaf_node','$campaigntransfer','$duration','$dialer_type','$channel','$campaignended','$skill_name','$Robodisconnect_time','$node_name','$lingua','$callcategory') ";
								$report_id=query_execute($query,$dbh,3,__LINE__);

								$query = "insert into ivr_report_$table_name (report_id,node_id,session_id,link_date_time,unlink_date_time,ivrs_path,cust_ph_no,ivrs_leaf_node,CampaignTransfer,duration,dialer_type,zap_channel,CampaignEnded,skills,entrytime,ivr_node_name,language,callcategory) values ('$report_id','$node_id','$session_id','$link_date_time','$unlink_date_time','$ivrs_path','$cust_ph_no','$ivrs_leaf_node','$campaigntransfer','$duration','$dialer_type','$channel','$campaignended','$skill_name','$Robodisconnect_time','$node_name','$lingua','$callcategory')";
								check_cview($query,$dbh,$table_name,3);
								$query =~ s/$table_name/current_report/i;
								query_execute($query,$dbh,0,__LINE__);

								$query="delete from ivr_call_dial_status where session_id=$session_id";
								query_execute($query,$dbh,0,__LINE__);
								undef(@leafval);
							}
						}

						if($command_line[2] =~ /zap/i)
						{
							$query="update zap set status='FREE',session_id='0.000000',flow_state='0' where zap_id='$zap_channel'";
							query_execute($query,$dbh,0,__LINE__);
						}
						if($command_line[2] =~ /sip/i)
						{
							$query="update sip set status='FREE',session_id='0.000000',flow_state='0' where session_id=$session_id";
							query_execute($query,$dbh,0,__LINE__);
						}
					}
				}
			}
##############Robodisconnect BLOCK END#####################################

##############AGENT LOGOFF BLOCK START#####################################
			elsif(($thread_type == 2) && (($command_line[0] =~ /Event: Agentlogoff/) || ($command_line[0] =~ /Event: Agentcallbacklogoff/)))
			{
				my $tmpLogintime = '';
				my $call_state;
				my $pause_state;
				my $wrap_state=0;
				my $dialer_mode;
				my $pauseDuration;
				my $totalCalls;
				my $loginTable;
				my $agent_session_id;
				my $agent_session_id_cond;
				my $agent_in_conf='0';
				my $confDuration="";
				my $agent_confVar='0';
				my $conference_action='0';
				my $agentlogoff_time;
				my $logout_reason="";
				my $preview_pauseDuration='0';
				my $previewDuration='0';

				$agent_id=substr($command_line[2],index($command_line[2],":") + 2);
				if($command_line[0] =~ /Event: Agentcallbacklogoff/)
				{
					$agent_session_id=substr($command_line[6],index($command_line[6],":") + 2);
					$agent_in_conf = substr($command_line[7],index($command_line[7],":") + 2);
				}
				else
				{
					$agent_session_id=substr($command_line[5],index($command_line[5],":") + 2);
					$agent_in_conf = substr($command_line[6],index($command_line[6],":") + 2);
				}

				my @returnvarSess=split('\.',$agent_session_id);
				$tmpLogintime = $returnvarSess[0];

				$query="select now()";
				my $tmp=query_execute($query,$dbh,1,__LINE__);
				$agentlogoff_time = @$tmp[0];

				if(defined($agent_in_conf) && ($agent_in_conf !~ /^$/ && $agent_in_conf !~ /^[\s]+$/)  && $agent_in_conf != 0)
				{
					$query="update agent_live set agent_in_conf = '1',agent_confVar = '1' where agent_session_id = $agent_session_id and agent_id = '$agent_id'";
					query_execute($query,$dbh,0,__LINE__);
				}
				else
				{
					my $category="";
					my $cust_disp="";
					my $remarks="";
					my $nct=0;
					my $finwrapuptime=0;
					my $wrapup_time="";

					$query="select a.agent_state,a.is_paused,a.is_free,a.dialer_type, DATE_FORMAT(from_unixtime(substring_index(a.agent_session_id,'.',1)),'%Y_%m') as last_login_time,if (a.is_paused=1,a.pauseDuration + (unix_timestamp() - a.pause_time),a.pauseDuration) as pauseDuration,a.call_counter,unix_timestamp(a.last_login_time),a.campaign_id,a.agent_session_id,a.ready_time,a.last_lead_id,a.ph_type,a.wait_duration,a.session_id,a.campaign_type,a.closer_time,a.is_setmefree,a.call_type,a.agent_confVar,unix_timestamp() as currentval,a.phone_attempt_count,a.lead_attempt_count,b.logout_reason from agent_live as a,agent as b where a.agent_id='$agent_id' and a.agent_session_id = $agent_session_id and a.agent_id=b.agent_id";
					my $logval=query_execute($query,$dbh,1,__LINE__);
					if($logval) {
						$logval=query_execute($query,$dbh,1,__LINE__);
						$call_state= ((defined @$logval[0])?@$logval[0]:"");
						$pause_state= ((defined @$logval[1])?@$logval[1]:"");
						$wrap_state= ((defined @$logval[2])?@$logval[2]:"");
						$dialer_mode= ((defined @$logval[3])?@$logval[3]:'NA');
						$pauseDuration = ((defined @$logval[5])?@$logval[5]:"0");
						$totalCalls = ((defined @$logval[6])?@$logval[6]:"0");
						$agent_session_id = ((defined @$logval[9])?@$logval[9]:"");
						$campaign_id= ((defined @$logval[8])?@$logval[8]:"0");

						my $ready_time = ((defined @$logval[10])?@$logval[10]:"0");
						my $last_lead_id = ((defined @$logval[11])?@$logval[11]:"0");
						my $phone_type =  ((defined @$logval[12])?@$logval[12]:"0");
						my $wait_duration = ((defined @$logval[13])?@$logval[13]:"0");
						$loginTable= ((defined @$logval[4]) && (@$logval[4] ne '0000_00')?@$logval[4]:"$table_name");
						my $session_id=((defined @$logval[14])?@$logval[14]:"");
						my $campaign_type=((defined @$logval[15])?@$logval[15]:"");
						my $is_setmefree=((defined @$logval[17])?@$logval[17]:"");
						my $call_type=((defined @$logval[18])?@$logval[18]:"");
						$agent_confVar = ((defined @$logval[19])?@$logval[19]:"0");
						my $live_lead_attempt_count = ((defined @$logval[22])?@$logval[22]:"0");
						$logout_reason = ((defined @$logval[23])?@$logval[23]:"Normal");
						my $lead_attempt_count = ($live_lead_attempt_count - 1  >= 0?$live_lead_attempt_count - 1:"");


                        if ($agentcount{$campaign_id} > 0 ) 
						{
							 $agentcount_semaphore->down;
							 $agentcount{$campaign_id}=$agentcount{$campaign_id} - 1;
							 $agentcount_semaphore->up;

							 if ($agentcount{$campaign_id} == '0') 
							   {
								 delete $agentcount{$campaign_id};
								 if(exists($logoutagent{$campaign_id}))
								  {
									delete $logoutagent{$campaign_id};
								  }
							   }
				        }
                        
						if($call_state eq "INCALL") {
						   $totalCalls = $totalCalls + 1;
						}

						if (is_numeric($call_type) ){
							$call_type=($call_type==0?"INBOUND":"OUTBOUND");
						}

						$tmpLogintime = ((defined @$logval[7]) && @$logval[7]?@$logval[7]:$tmpLogintime);;
						if(@$logval[16] == '-999' && $call_state eq 'CLOSURE' && $wrap_state == '0') {
							$ready_time= @$logval[20] - $tmpLogintime;
							$ready_time = ($ready_time<0?'0':$ready_time);
						}

						if((defined($wrap_state) && $wrap_state) || $is_setmefree == 1) {
							$query="select category,cust_disposition,txt,next_call_time,customer_sentiment_name from crm_hangup_live where agent_id='$agent_id' and session_id=$session_id";
							$retval=query_execute($query,$dbh,1,__LINE__);
							my $category_chl=((defined @$retval[0])?@$retval[0]:"");
							my $cust_disp_chl= ((defined @$retval[1])?@$retval[1]:"");
							my $remarks_chl=((defined @$retval[2])?@$retval[2]:"");
							$nct=((defined @$retval[3])?@$retval[3]:"0");
							my $customer_sentiment_name=((defined @$retval[4])?@$retval[4]:"");


							$query="select cust_category,cust_disposition,call_remarks,customer_sentiment_name,call_end_date_time from current_report where agent_id ='$agent_id' and session_id=$session_id";
							my $result = query_execute($query,$dbh,1,__LINE__);

							$cust_disp= ((defined($cust_disp_chl) && ($cust_disp_chl !~ /^$/ && $cust_disp_chl !~ /^[\s]+$/))?$cust_disp_chl:@$result[1]);
							$category=((defined($category_chl) && ($category_chl !~ /^$/ && $category_chl !~ /^[\s]+$/))?$category_chl:@$result[0]);
							$remarks=((defined($remarks_chl) && ($remarks_chl !~ /^$/ && $remarks_chl !~ /^[\s]+$/))?$remarks_chl:@$result[2]);
							$customer_sentiment_name=((defined($customer_sentiment_name) && ($customer_sentiment_name !~ /^$/ && $customer_sentiment_name !~ /^[\s]+$/))?$customer_sentiment_name:@$result[3]);
							$call_end_date_time = ((defined(@$result[4]) && (@$result[4] !~ /^$/ && @$result[4] !~ /^[\s]+$/))?@$result[4]:$agentlogoff_time);

                            $customer_sentiment_name=((defined ($customer_sentiment_name))?$customer_sentiment_name:"");

							$remarks= "FD(logout on wrap)".$remarks;
							$category=((defined $category)?$category:"");
							$cust_disp=((defined $cust_disp)?$cust_disp:"");

							if (not exists $campaignWrapHash{$campaign_id}) {
								populateCampaignWrap($campaign_id,$dbh);
							}
							$finwrapuptime = $campaignWrapHash{$campaign_id};

							if((defined($finwrapuptime) && ($finwrapuptime !~ /^$/ && $finwrapuptime != /^[\s]+$/)) && $finwrapuptime != '0') { 
								$wrapup_time = "wrapup_time=if(unix_timestamp('$agentlogoff_time') - unix_timestamp('$call_end_date_time')<=$finwrapuptime,unix_timestamp('$agentlogoff_time') - unix_timestamp('$call_end_date_time'),$finwrapuptime)";
							}
							else {
								$wrapup_time = "wrapup_time=unix_timestamp('$agentlogoff_time') - unix_timestamp('$call_end_date_time')";
							}

							$query="update $loginTable set call_remarks ='$remarks',cust_disposition='$cust_disp',cust_category='$category',next_call_time='$nct',customer_sentiment_name='$customer_sentiment_name',$wrapup_time where agent_id ='$agent_id' and session_id=$session_id";
							query_execute($query,$dbh,0,__LINE__);

							check_cview($query,$dbh,$loginTable,2);
							$query =~ s/$loginTable/current_report/i;
							query_execute($query,$dbh,0,__LINE__);
						}

#----check for particular agent in conference room---#
## if then particular chhanel goes to hangup--#
#
						if (not exists $campaign_conference{$campaign_id}) {
							populateCampaign($campaign_id,$dbh,'0');
						}
						$conference_action  = $campaign_conference{$campaign_id};

						if($conference_action == 1)
						{
							$query="select chan_name from meetme_user where confno='$agent_id' and cust_ph_no='$agent_id'";
							my $retArray=query_execute($query,$dbh,1,__LINE__);
							if(defined(@$retArray[0]) && (@$retArray[0] !~ /^$/ && @$retArray[0] !~ /^[\s]+$/))
							{
								$sendTn_semaphore->down;
								$shared_key =  @$retArray[0];
								$sendTnHash{$shared_key} = "confRoomcheck";
								$sendTn_semaphore->up;
							}

						}

#delete the entry from agent wrapup hash when agent loggs off
						if ( @{$final_wrap_array[$agent_id][0]})
						{
							splice(@final_wrap_array,$agent_id,1);
						}

						$wrapup_semaphore->down;
						delete $agent_wrapup{$agent_id};        #delete element from hash
						delete $call_duration_array1[$agent_id];
						delete $call_duration_array2[$agent_id];
						delete $call_duration_array3[$agent_id];
						delete $update_avg_block1[$agent_id];   #delete element from UAB array
						delete $update_avg_block2[$agent_id];
						delete $update_avg_block3[$agent_id];
						delete $predict_state_after1[$agent_id];
						delete $predict_state_after2[$agent_id];
						delete $predict_state_after3[$agent_id];
						delete $state_changed[$agent_id];
						$wrapup_semaphore->up;

#to unpause the agent before logging off, asked by bhishm to send this packet
#sendTelnetCommand($agent_id,"unpause",$dbh);
						$shared_key = $agent_id;
						$sendTn_semaphore->down;
						$sendTnHash{$shared_key} = "unpause";
						$sendTn_semaphore->up;

						if(defined($agent_session_id) && ($agent_session_id !~ /^$/ && $agent_session_id !~ /^[\s]+$/)) {
							$agent_session_id_cond=" and agent_session_id=$agent_session_id";
						}

						if(defined($dialer_mode) && ($dialer_mode =~ "PREVIEW"))
						{
#to delete the entry from callProgress table whenever an agent loggs off in preview mode, requested by bhishm
							$query="delete from callProgress where agent_id='$agent_id'";
							query_execute($query,$dbh,0,__LINE__);

							$query="select dialerType from campaign as a where campaign_id='$campaign_id'";
							$returnvar=query_execute($query,$dbh,1,__LINE__);
							$dialerType = @$returnvar[0];

							if($dialerType !~ /PREVIEW/i) {
								$query="update agent_state_analysis_$loginTable set agent_state='PREVIEW_N_$dialerType',call_end_date_time='$agentlogoff_time' where agent_id='$agent_id' and agent_state='PREVIEW' ".$agent_session_id_cond;
								query_execute($query,$dbh,0,__LINE__);

#Adding information to Agent State Analysis current report
								check_cview($query,$dbh,$loginTable,2);
								$query =~ s/$loginTable/current_report/i;
								query_execute($query,$dbh,0,__LINE__);
							}
						}

						if($pause_state) {
							$query="update agent_state_analysis_$loginTable set agent_state='BREAK_N_BACK',call_end_date_time='$agentlogoff_time' where agent_id='$agent_id' and agent_state='BREAK' ".$agent_session_id_cond;
							query_execute($query,$dbh,0,__LINE__);

#Adding information to Agent State Analysis current report
							check_cview($query,$dbh,$loginTable,2);
							$query =~ s/$loginTable/current_report/i;
							query_execute($query,$dbh,0,__LINE__);
						}

						if(defined($last_lead_id) && ($wrap_state || $is_setmefree) && ($last_lead_id !~ /^$/ && $last_lead_id !~ /^[\s]+$/) && $call_type eq "OUTBOUND")
						{

							$phone_type  = (defined($phone_type) && ($phone_type !~ /^$/ && $phone_type !~ /^[\s]+$/)?$phone_type:101);

							$query="update dial_Lead_lookup_$campaign_id set lead_state='0' where lead_id='$last_lead_id'";
							query_execute($query, $dbh,0, __LINE__);

							$query="update extended_customer_$campaign_id set lead_state='0' ,last_call_disposition='answered',call_disposition_".($phone_type -100)."='answered' where lead_id='$last_lead_id'";
							query_execute($query, $dbh,0, __LINE__);

							my $call_disposition="answered";
							my $dialer_remarks= "FD | Finished";
							
							if ($lead_attempt_count <= 9) {
								$query="update dial_state_$campaign_id set lead_state='0',disposition_$lead_attempt_count='$call_disposition',phone_state_$lead_attempt_count='0',dial_state_$lead_attempt_count='0',next_call_time_$lead_attempt_count='$nct',next_call_rule_$lead_attempt_count='$dialer_remarks',agent_id_$lead_attempt_count='$agent_id',phone_type_$lead_attempt_count='$phone_type',last_lead_status='1' where lead_id='$last_lead_id'";
								query_execute($query, $dbh,0, __LINE__);
							}

							$query="update dial_Lead_$campaign_id set lead_state='0'  where lead_id='$last_lead_id'";
							query_execute($query, $dbh,0, __LINE__);

						}

						$query ="select sum(unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time)) as pauseDuration,sum(if(dailer_mode='PREVIEW',unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time),0 )) as preview_pause_duraiton from agent_state_analysis_current_report where agent_id='$agent_id' and break_type not in ('JoinedConference') and agent_state='BREAK_N_BACK'".(($agent_session_id_cond =~ /^$/ || $agent_session_id_cond =~ /^[\s]+$/)?" and entrytime between '$tmpLogintime' and unix_timestamp() ":"").$agent_session_id_cond ;
						$logval=query_execute($query,$dbh,1,__LINE__);
						$pauseDuration = ((defined @$logval[0])?@$logval[0]:"0");
						$preview_pauseDuration = ((defined @$logval[1])?@$logval[1]:"0");

						$query ="select sum(unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time)) as previewDuration from agent_state_analysis_current_report where agent_id='$agent_id'  and (agent_state='PREVIEW_N_PROGRESSIVE' or agent_state='PREVIEW_N_PREDICTIVE')".(($agent_session_id_cond =~ /^$/ || $agent_session_id_cond =~ /^[\s]+$/)?" and entrytime between '$tmpLogintime' and unix_timestamp() ":"").$agent_session_id_cond ;
						$logval=query_execute($query,$dbh,1,__LINE__);
						$previewDuration = ((defined @$logval[0])?@$logval[0]:"0");

						if(defined($agent_confVar) && ($agent_confVar !~ /^$/ && $agent_confVar !~ /^[\s]+$/)  && $agent_confVar != 0)
						{
							$query="select sum(unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time)) as conf_duration from current_report where agent_id = '$agent_id' and entrytime between '$tmpLogintime' and unix_timestamp()  and  agent_id = cust_ph_no";
							$logval=query_execute($query,$dbh,1,__LINE__);
							$confDuration = ((defined @$logval[0])?@$logval[0]:"0");
						}

						$query="update agent_state_analysis_$loginTable set agent_state='LOGIN_N_LOGOUT',call_end_date_time='$agentlogoff_time',call_state='$call_state',pause_state='$pause_state',wrap_state='$wrap_state',dailer_mode='$dialer_mode',pauseDuration='$pauseDuration',totalCall='$totalCalls',ready_time='$ready_time',wait_duration='$wait_duration',conf_duration='$confDuration',logout_reason='$logout_reason',preview_pauseDuration='$preview_pauseDuration',preview_time='$previewDuration' where agent_id='$agent_id' and agent_state='LOGIN' ".$agent_session_id_cond;
						query_execute($query,$dbh,0,__LINE__);

#Adding information to Agent State Analysis current report
						check_cview($query,$dbh,$loginTable,2);
						$query =~ s/$loginTable/current_report/i;
						query_execute($query,$dbh,0,__LINE__);

						$query="update agent set staticIP='',last_logoff_time='0',last_agent_session_id='0.000000' where agent_id='$agent_id' and last_agent_session_id=$agent_session_id";
						query_execute($query,$dbh,0,__LINE__);

						if($call_state!~ /INCALL/) {
							if(!$wrap_state && $call_state!~ /CLOSURE/) {
								$query="delete from crm_hangup_live where agent_id='$agent_id'";
								query_execute($query,$dbh,0,__LINE__);

								$query="delete from crm_live where agent_id='$agent_id'";
								query_execute($query,$dbh,0,__LINE__);
							}
						}

						$query="delete from agent_live where agent_id='$agent_id'";
						query_execute($query,$dbh,0,__LINE__);
					}
					else {
						$query ="select unix_timestamp(call_start_date_time),campaign_id from agent_state_analysis_current_report where agent_id='$agent_id' and agent_state='LOGIN' and agent_session_id=$agent_session_id";
						$logval=query_execute($query,$dbh,1,__LINE__);
						if(defined(@$logval[0]) && (@$logval[0] !~ /^$/ && @$logval[0] !~ /^[\s]+$/)) {
							logoutupdate($agent_id,@$logval[0],$agentlogoff_time,$agent_session_id,$dbh,@$logval[0]);
						}
						else {
							$query="update agent set last_logoff_time='$agentlogoff_time',last_agent_session_id='$agent_session_id' where agent_id='$agent_id'";
							query_execute($query,$dbh,0,__LINE__);
						}
					}
				}
			}
##############AGENT LOGOFF BLOCK END#########################

####################MOH BLOCK STARTS#########################
		elsif(($thread_type == 6) &&($command_line[0] =~ /Event: EventHold/) )
		{
			$channel=substr($command_line[2],index($command_line[2],":") + 2);
			$agent_id=substr($command_line[3],index($command_line[3],":") + 2);
			my $state=substr($command_line[4],index($command_line[4],":") + 2);
			
			if ($state == 1)
			{
				$query = "update agent_live set holdNumTime= holdNumTime +1,holdTimestamp=now(),last_activity_time=now(),is_hold='1' where agent_id='$agent_id' and is_hold='0'";
				query_execute($query,$dbh,0,__LINE__);

				$query="update customer_live set state='MHOLD' where agent_id='$agent_id' and state='MUNHOLD'";
				query_execute($query,$dbh,0,__LINE__);
			}
			else
			{
				$query = "update agent_live set holdDuration = holdDuration + (unix_timestamp() - unix_timestamp(holdTimestamp)),holdTimestamp='',last_activity_time=now(),is_hold='0' where agent_id='$agent_id' and unix_timestamp(holdTimestamp) > 0 and is_hold='1'";
				query_execute($query,$dbh,0,__LINE__);

				$query="update customer_live set state='MUNHOLD' where agent_id='$agent_id' and state='MHOLD'";
				query_execute($query,$dbh,0,__LINE__);
			}
			
		}
#############################################MOH BLOCK ENDS######################


##############QUEUEMEMBERPAUSED BLOCK START######################################
elsif(($thread_type == 9) &&($command_line[0] =~ /Event: QueueMemberPaused/) )
{
        my $camp_type = substr($command_line[2],index($command_line[2],":") + 2);
		$agent_id = substr($command_line[3],index($command_line[3],"/") + 1);
		my $state = substr($command_line[4],index($command_line[4],":") + 2);
		my $org_mode = substr($command_line[5],index($command_line[5],":") + 2);
		my $agent_state= substr($command_line[6],index($command_line[6],":") + 2);
		my $mode=((defined($org_mode) && ($org_mode !~ /^$/ && $org_mode ne /^[\s]+$/))?$org_mode:"BreaK");
		my $dialer_mode ="PROGRESSIVE";

		if($camp_type =~ /preview/) {
		 $dialer_mode="PREVIEW"
		}
#if agent is sent to break then only update the is_paused field to 1 don't change the agent_state field
		$agent_id =~ s/^\s+//;
		$agent_id =~ s/\s+$//;
#---------Check if agent has clicked on the ready state---------------
		if($mode =~ /CZTransfered/i)
		{
		   $query="update agent_live set is_paused='$state' where agent_id='$agent_id'";
		   query_execute($query,$dbh,0,__LINE__);
		}
		elsif(defined($agent_state) && $agent_state) {
			$query="update agent_live set agent_state='FREE',ready_time=unix_timestamp()-unix_timestamp(last_login_time),closer_time=0,wait_time=unix_timestamp() where agent_id='$agent_id' and closer_time='-999' and agent_state='CLOSURE'";
			query_execute($query,$dbh,0,__LINE__);
		}
		else
		{
			$query="select DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as last_login_time,campaign_id,agent_session_id,is_paused,closer_time,wait_time,now(),agent_state,break_type from agent_live where agent_id='$agent_id'";
			$returnvar=query_execute($query,$dbh,1,__LINE__);
			my $pauseTable = @$returnvar[0];
			$pauseTable= ((defined @$returnvar[0]) && (@$returnvar[0] ne '0000_00')?@$returnvar[0]:"$table_name");
			my $campaign_id=@$returnvar[1];
			my $agent_session_id=@$returnvar[2];
			my $pause_status=@$returnvar[3];
			my $wait_time=@$returnvar[5];
			my $pause_time=@$returnvar[6];
			my $agent_state=@$returnvar[7];
			my $alivemode=@$returnvar[8];

			#if agent is sent to break then only update the is_paused field to 1 don't change the agent_state field
			if($state==1 && !$pause_status)
			{
				if (not exists $agentHash{$agent_id}) {
					populateAgent($agent_id,$dbh);
				}
				$agent_name = $agentHash{$agent_id};

				if (not exists $campaignHash{$campaign_id}) {
					populateCampaign($campaign_id,$dbh,'0');
				}
				$campaign_name = $campaignHash{$campaign_id};
				if(defined($agent_session_id) && ($agent_session_id !~ /^$/ && $agent_session_id !~ /^[\s]+$/))
				{
					$query="update agent_live set is_paused='1',pause_time=unix_timestamp(),last_activity_time=now(),break_type='$mode' where agent_id='$agent_id'";
					query_execute($query,$dbh,0,__LINE__);

				#Adding information to Agent State Analysis current report
					$query="insert into agent_state_analysis_$pauseTable (node_id,agent_id,campaign_id,agent_state,call_start_date_time,break_type,agent_session_id,agent_name,campaign_name,dailer_mode,entrytime) values('$node_id','$agent_id','$campaign_id','BREAK','$pause_time','$mode','$agent_session_id','$agent_name','$campaign_name','$dialer_mode',unix_timestamp('$pause_time'))";
					query_execute($query,$dbh,0,__LINE__);

					check_cview($query,$dbh,$pauseTable,2);
					$query =~ s/$table_name/current_report/i;
					query_execute($query,$dbh,0,__LINE__);
				}
			}
			elsif($state==0  && $pause_status)
			{			
				my $pauseadd=($alivemode eq "JoinedConference"?"":",pauseDuration=pauseDuration + (unix_timestamp() - if(pause_time>0,pause_time,unix_timestamp(last_activity_time)))");

				$query="update agent_live set break_type=''$pauseadd,is_paused='0',pause_time='0',last_activity_time='$time'".($agent_state eq "INCALL"?"":",wait_time=unix_timestamp()")." where agent_id='$agent_id' and is_paused='1'";
				query_execute($query,$dbh,0,__LINE__);

				$query="update agent_state_analysis_$pauseTable set agent_state='BREAK_N_BACK',call_end_date_time='$pause_time',dailer_mode='$dialer_mode' where agent_id='$agent_id' and agent_state='BREAK' and agent_session_id=$agent_session_id";
				query_execute($query,$dbh,0,__LINE__);

				#Adding information to Agent State Analysis current report
				check_cview($query,$dbh,$pauseTable,2);
				$query =~ s/$pauseTable/current_report/i;
				query_execute($query,$dbh,0,__LINE__);
			}
		}
	}
##############QUEUEMEMBERPAUSED BLOCK END######################################

##############AUTO PREVIEW DIALER BLOCK START######################################
			elsif((($thread_type == 8)) && ($command_line[0] =~ /Event: AutoPreviewDialer/))
			{
				my $previewTable="";
				@params=split(/\//,substr($command_line[2],index($command_line[2],":") + 2));
				$agent_id=$params[0];
				$dialerType=$params[1];

				if($dialerType =~ /true/i)
				{
					$query="update agent_live set autoMode='1',last_activity_time=now() where agent_id='$agent_id'";
					query_execute($query,$dbh,0,__LINE__);

				}
				elsif($dialerType =~ /false/i)
				{
					$query="update agent_live set autoMode='0',last_activity_time=now() where agent_id='$agent_id'";
					query_execute($query,$dbh,0,__LINE__);
				}
			}
##############AUTO PREVIEW DIALER BLOCK END######################################
			elsif((($thread_type == 8)) && ($command_line[0] =~ /Event: SetVerifier/))
			{
				$agent_id=substr($command_line[2],index($command_line[2],":") + 2);
				$campaign_id=substr($command_line[3],index($command_line[3],":") + 2);
				$query="update agent_live set verifying_campaign='$campaign_id' where agent_id='$agent_id'";
				query_execute($query,$dbh,0,__LINE__);
			}

##############PREVIEW DIAL FAILURE BLOCK END######################################
			elsif((($thread_type == 8)) && ($command_line[0] =~ /Event: PreviewDialFailure/))
			{
				my $call_back_live_re=0;
				my $agent_id=substr($command_line[4],index($command_line[4],":") + 2);
				my $returnvar=substr($command_line[3],index($command_line[3],":") + 2);
				my $hangup_cause=substr($command_line[5],index($command_line[5],":") + 2);
				my $dialer_var=substr($command_line[6],index($command_line[6],":") + 2);
				my $cause=substr($command_line[2],index($command_line[2],":") + 2);
				my $provider_name="";
				my $preview_fail_time;
				my @dialer_variables=split(/,/,$dialer_var);
				my $phone_type = (defined($dialer_variables[0])?$dialer_variables[0]:"101");
				my $next_call_time = (defined($dialer_variables[3])?$dialer_variables[3]:"");
				my $redial_flag= (defined($dialer_variables[4])?$dialer_variables[4]:"0");
				my $call_back_live= (defined($dialer_variables[5])?$dialer_variables[5]:"0");
				my $dialer_var_channel = ((defined($dialer_variables[10]) && ($dialer_variables[10] !~ /^$/ && $dialer_variables[10] !~ /^[\s]+$/))?$dialer_variables[10]:"");
                my $dialer_var_channel_id = ((defined($dialer_variables[11]) && ($dialer_variables[11] !~ /^$/ && $dialer_variables[11] !~ /^[\s]+$/))?$dialer_variables[11]:"");
				my $callerid= (defined($dialer_variables[16])?$dialer_variables[16]:"0");
				$hangup_cause=$hangup_cause."-".$cause;
				my $report_query="";

				@variables=split(/,/,$returnvar);
				my $custphno=(defined($variables[0])?$variables[0]:"");
				my $lead_id=(defined($variables[1])?$variables[1]:"");
				my $campaign_id=(defined($variables[2])?$variables[2]:"");
				my $list_id=(defined($variables[3])?$variables[3]:"");
				my $CustUniqueId=(defined($variables[6])?$variables[6]:"");

				if(!defined($CustUniqueId) || ($CustUniqueId =~ /^$/ || $CustUniqueId =~ /^[\s]+$/)) {
					$query="select CustUniqueId from dial_Lead_lookup_$campaign_id where lead_id='$lead_id' and list_id='$list_id' and phone='$custphno'";
				    my $temp=query_execute($query,$dbh,1,__LINE__);
				    $CustUniqueId =  @$temp[0];
				}

				$query="select lastDial,session_id,channel,lead_id from callProgress where agent_id='$agent_id'";
				$returnvar=query_execute($query,$dbh,1,__LINE__);
				my $link_date_time=@$returnvar[0];
				my $session_id=@$returnvar[1];
				my $channel=@$returnvar[2];
				$lead_id = (defined(@$returnvar[3])?@$returnvar[3]:"");
				$campaign_type='OUTBOUND';

				$query="select now()";
				my $tmp=query_execute($query,$dbh,1,__LINE__);
				$preview_fail_time = @$tmp[0];

				$query="select agent_ext from agent_live where agent_id='$agent_id'";
				my $agentidvar=query_execute($query,$dbh,1,__LINE__);
				my $agent_ext=@$agentidvar[0];

				if(defined($next_call_time) && ($next_call_time !~ /^$/ && $next_call_time!= /^[\s]+$/)){
					$call_back_live_re=1;
				}

				if(defined($dialer_var_channel_id) && ($dialer_var_channel_id !~ /^$/ && $dialer_var_channel_id !~ /^[\s]+$/))
				{
					$channel = $dialer_var_channel;
					$zap_channel = $dialer_var_channel_id;

					if(($channel =~ /Zap/i)) {
						$zap_channel =~ s/ZAP/Zap/g;
						if($zap_channel)
						{
							if (not exists($providernameHash{$zap_channel})) {
								populateprovider($dbh);
							}
							$provider_name=$providernameHash{$zap_channel};
						}
						$channel="ZAP";
					}
					elsif(($channel =~ /SIP/i)) {
						if($zap_channel){
							if (not exists($sip_id_providernameHash{$zap_channel}))
							{
								sip_id_populateprovider($dbh);
							}
							$provider_name=$sip_id_providernameHash{$zap_channel};
						}
						$channel = "SIP";
					}
				}
				elsif(($channel =~ /Zap/i)) {
					$zap_channel=substr($channel,0,index($channel,"-"));
					$zap_channel =~ s/ZAP/Zap/g;
					if($zap_channel)
					{
						if (not exists($providernameHash{$zap_channel})) {
							populateprovider($dbh);
						}
						$provider_name=$providernameHash{$zap_channel};
					}
					$channel="ZAP";
				}
				elsif(($channel =~ /SIP/i)) {
					$zap_channel=substr($channel,index($channel,"/")+1);
					$zap_channel=substr($zap_channel,0,index($zap_channel,"-"));
					if(match_ip($zap_channel)){
						if (not exists($sip_providernameHash{$zap_channel}))
						{
							sip_populateprovider($dbh);
						}
						$provider_name=$sip_providernameHash{$zap_channel};
					}
					else{
						$provider_name=$zap_channel;
					}
					$zap_channel=$channel;
					$channel = "SIP";
				}
				elsif(($channel =~ /Local/i))
				{
					  $zap_channel=$channel;
					  $provider_name="Local";
					  $channel = "Local";
				}
				else
				{
					$zap_channel=$channel;
					$channel = "SIP";
				}

				if (not exists $agentHash{$agent_id}) {
					populateAgent($agent_id,$dbh);
				}
				$agent_name = $agentHash{$agent_id};

				if (not exists $campaignHash{$campaign_id}) {
					populateCampaign($campaign_id,$dbh,'0');
				}
				$campaign_name = $campaignHash{$campaign_id};

				if((!defined($session_id) || $session_id =~ /^$/ || $session_id =~ /^[\s]+$/)) {
					$session_id=2000000000 + int(rand(100000));
					$session_id = $session_id.".".int(rand(10000));
				}

				if($list_id) {
					$query="select list_name from list where list_id='$list_id'";
					$returnvar=query_execute($query,$dbh,1,__LINE__);
					$list_name=@$returnvar[0];
				}
				else {
					$list_id=0;
					$list_name="Manual Dial";
				}
				if((!defined($link_date_time) || $link_date_time =~ /^$/ || $link_date_time =~ /^[\s]+$/)) {
					$link_date_time=$time;
				}

				$phone_type=($phone_type?$phone_type:'101');

				$query="update callProgress set failureCause='$hangup_cause' where agent_id='$agent_id'";
				query_execute($query,$dbh,0,__LINE__);

				$query="update agent_live set closer_time=unix_timestamp(),agent_state='CLOSURE',session_id='$session_id',lead_id='$lead_id',is_free=1,preview_fail=1,from_campaign='$campaign_id',call_counter=call_counter+1,last_lead_id='$lead_id',last_activity_time=now(),last_cust_ph_no='$custphno',call_type='16384',ph_type='$phone_type',rd_flag='$redial_flag' where agent_id='$agent_id' and agent_state!='INCALL' ";
				query_execute($query,$dbh,0,__LINE__);


				$report_id='';
				$query="insert into $table_name(node_id,lead_id,cust_ph_no,campaign_id,campaign_name,campaign_type,campaign_channel,q_enter_time,q_leave_time,call_start_date_time,call_end_date_time,session_id,call_status_disposition,call_remarks,list_id,list_name,zap_channel,dialer_type,dialer_inserted_field,agent_ext,agent_id,agent_name,entrytime,redial_flag,callback_flag,ph_type,provider_name,causecode,caller_id,CustUniqueId)values('$node_id','$lead_id','$custphno','$campaign_id','$campaign_name','$campaign_type','$channel','$link_date_time','$link_date_time','$link_date_time','$preview_fail_time','$session_id','noans','$hangup_cause','$list_id','$list_name','$channel','PREVIEW','0','$agent_ext','$agent_id','$agent_name',unix_timestamp('$link_date_time'),'$redial_flag','$call_back_live_re','$phone_type','$provider_name','$cause','$callerid','$CustUniqueId')";
				$report_id=query_execute($query,$dbh,3,__LINE__);

				$query="select call_status_disposition from current_report where agent_id='$agent_id' and session_id=$session_id and entrytime='$link_date_time' ";
				$report_query=query_execute($query,$dbh,1,__LINE__);

                if(!defined (@$report_query[0]))
				{
					$query="insert into $table_name(report_id,node_id,lead_id,cust_ph_no,campaign_id,campaign_name,campaign_type,campaign_channel,q_enter_time,q_leave_time,call_start_date_time,call_end_date_time,session_id,call_status_disposition,call_remarks,list_id,list_name,zap_channel,dialer_type,dialer_inserted_field,agent_ext,agent_id,agent_name,entrytime,redial_flag,callback_flag,ph_type,provider_name,causecode,caller_id,CustUniqueId)values('$report_id','$node_id','$lead_id','$custphno','$campaign_id','$campaign_name','$campaign_type','$channel','$link_date_time','$link_date_time','$link_date_time','$preview_fail_time','$session_id','noans','$hangup_cause','$list_id','$list_name','$channel','PREVIEW','0','$agent_ext','$agent_id','$agent_name',unix_timestamp('$link_date_time'),'$redial_flag','$call_back_live_re','$phone_type','$provider_name','$cause','$callerid','$CustUniqueId')";
					check_cview($query,$dbh,$table_name,1);
					$query =~ s/$table_name/current_report/i;
					query_execute($query,$dbh,0,__LINE__);
				}
			}
##############PREVIEW DIAL FAILURE BLOCK END################################

##############PREVIEW DIALER BLOCK END######################################
			elsif((($thread_type == 8)) && ($command_line[0] =~ /Event: PreviewDialer/))
			{
				my $previewTable="";
				my $agent_session_id="";
				my $campaign_name="";
				my $preview_time;
				my $new_dialer_type="";
				@params=split(/\//,substr($command_line[2],index($command_line[2],":") + 2));
				$agent_id=$params[0];
				$dialerType=$params[1];

				$query="select DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as last_login_time,campaign_id,agent_session_id,now(),dialer_type from agent_live where agent_id='$agent_id'";
				$returnvar=query_execute($query,$dbh,1,__LINE__);
				$previewTable = @$returnvar[0];
				$campaign_id = @$returnvar[1];
				$agent_session_id = @$returnvar[2];
				$preview_time = @$returnvar[3];
				$new_dialer_type=@$returnvar[4];

				if($dialerType =~ /true/i && $new_dialer_type !~ m/^PREVIEW$/i)
				{
					$query="update agent_live set dialer_type='PREVIEW',last_activity_time=now(),preview_time=unix_timestamp() where agent_id='$agent_id'";
					query_execute($query,$dbh,0,__LINE__);

					if (not exists $agentHash{$agent_id}) {
						populateAgent($agent_id,$dbh);
					}
					$agent_name = $agentHash{$agent_id};

					if (not exists $campaignHash{$campaign_id}) {
						populateCampaign($campaign_id,$dbh,'0');
					}
					$campaign_name = $campaignHash{$campaign_id};

					$query="insert into agent_state_analysis_$previewTable (node_id,agent_id, campaign_id, campaign_name, agent_state, call_start_date_time,agent_name,entrytime,agent_session_id) values ('$node_id','$agent_id','$campaign_id','$campaign_name','PREVIEW','$preview_time','$agent_name',unix_timestamp('$preview_time'),'$agent_session_id')";
					query_execute($query,$dbh,0,__LINE__);

#Adding information to Agent State Analysis current report
					check_cview($query,$dbh,$previewTable,2);
					$query =~ s/$previewTable/current_report/i;
					query_execute($query,$dbh,0,__LINE__);
				}
				elsif($dialerType =~ /false/i && $new_dialer_type =~ m/^PREVIEW$/i)
				{
#the other type can be progressive or predictive
					$query="select dialerType from campaign as a where campaign_id='$campaign_id'";
					$returnvar=query_execute($query,$dbh,1,__LINE__);
					$dialerType = @$returnvar[0];

					$query="update agent_live set dialer_type='$dialerType',last_activity_time=now(),preview_Duration=preview_Duration + (unix_timestamp() - if(preview_time>0,preview_time,unix_timestamp(last_activity_time))) where agent_id='$agent_id'";
					query_execute($query,$dbh,0,__LINE__);

					$query="update agent_state_analysis_$previewTable set agent_state='PREVIEW_N_$dialerType',call_end_date_time='$preview_time' where agent_id='$agent_id' and agent_state='PREVIEW' and agent_session_id=$agent_session_id";
					query_execute($query,$dbh,0,__LINE__);

#Adding information to Agent State Analysis current report
					check_cview($query,$dbh,$previewTable,2);
					$query =~ s/$previewTable/current_report/i;
					query_execute($query,$dbh,0,__LINE__);
				}
			}
##############PREVIEW DIALER BLOCK END##################################

##############SHUTDOWN BLOCK START######################################
			elsif(($thread_type == 4) && ($command_line[0] =~ /Event: Shutdown/))
			{
				error_handler("Zentrix is down...",__LINE__,"");
				exit;
			}
##############SHUTDOWN BLOCK END######################################

##############WRAPUP BLOCK START######################################
			elsif(($thread_type == 7) && ($command_line[0] =~ /Event: Wraptime/))
			{
				$campaign_id=substr($command_line[2],index($command_line[2],":") + 2);
				my $wrapuptime=substr($command_line[3],index($command_line[3],":") + 2);
				$query="update agent_live set wrap_up_time='$wrapuptime',last_activity_time=now() where campaign_id='$campaign_id'";
				query_execute($query,$dbh,0,__LINE__);

				if (not exists $campaignWrapHash{$campaign_id}) {
					populateCampaignWrap($campaign_id,$dbh);
				} else {
					$campaignWrapHash_semaphore->down;
					$campaignWrapHash{$campaign_id}=$wrapuptime;
					$campaignWrapHash_semaphore->up;
				}
			}
##############WRAPUP BLOCK END######################################

##############Campfileformat BLOCK START############################
			elsif(($thread_type == 7) && ($command_line[0] =~ /Event: Campfileformat/))
			{
				$campaign_id=substr($command_line[2],index($command_line[2],":") + 2);
				my $file_format=substr($command_line[3],index($command_line[3],":") + 2);
				$fileFormatHash_semaphore->down;
				$fileFormatHash{$campaign_id}=$file_format;
				$fileFormatHash_semaphore->up;
			}
##############Campfileformat BLOCK END################################

##############PopulateHash START######################################
			elsif(($thread_type == 7) && ($command_line[0] =~ /Event: PopulateHash/))
			{
				my @variables="";
				my $data="";
				my $reloadtype = substr($command_line[2],index($command_line[2],":") + 2);

				if($reloadtype =~ /|/)
				{
					@variables=split(/\|/,$reloadtype);
					$reloadtype=$variables[0];
					$data=$variables[1];
				}
				if($reloadtype =~ m/^csat$/)
				{
					populateCsat($dbh);
				}
				elsif($reloadtype =~ m/^csativr$/)
				{
					populateCsativr($dbh);
				}
				elsif($reloadtype =~ m/^cview$/)
				{
					cview_flag($dbh);
				}
				elsif($reloadtype =~ m/^nwlead$/)
				{
					populateMonitorFileFormatLead($data,$dbh);
					populateCampaign($data,$dbh,'0');
				}
				elsif($reloadtype =~ m/^nwmanual$/)
				{
					populateMonitorFileFormatManual($data,$dbh);
					populateCampaign($data,$dbh,'0');
				}
				elsif($reloadtype =~ m/^crflead$/)
				{
					populateReportingFormatLead($data,$dbh);
					populateCampaign($data,$dbh,'0');
				}
				elsif($reloadtype =~ m/^crfmanual$/)
				{
					populateReportingFormatManual($data,$dbh);
					populateCampaign($data,$dbh,'0');
				}
				elsif($reloadtype =~ m/^Rule$/)
				{
					populate_disposition_hash($dbh);
				}
				elsif($reloadtype =~ m/^logs$/i)
				{
					if ($data=='0') {
						$DB_semaphore->down;
						$DB=0;
						$DB_semaphore->up;
					}elsif($data=='1') {
						$DB_semaphore->down;
						$DB=1;
						$DB_semaphore->up;
					}else{
						$DB_semaphore->down;
						$DB=0;
						$DB_semaphore->up;
					}
					
				}
				else
				{
					populatelogout($dbh,$data);
					populateAgent('',$dbh,'0');
					populateSkill($dbh);
					populateprovider($dbh);
					populateCampaign($data,$dbh,'0');
				}
				$dbh->disconnect();
				undef($dbh);
			}
##############PopulateHash END######################################

##############ReloadDialer###############################################
			elsif(($thread_type == 13) && ($command_line[0] =~ /Event: ReloadDialer/i))
			{
				my $type =  substr($command_line[2],index($command_line[2],":")+2);
				if($type eq "Rule" || $type eq "List" ){
					populate_disposition_hash($dbh);
				}
			}
##############End ReloadDialer############################################

##############NewVoiceMailRecorded START######################################
			elsif(($thread_type ==  4) && ($command_line[0] =~ /Event: NewVoiceMailRecorded/))
			{
				my @vfile;
				my @vcallerid;
				my $new_filename='';
				my $vmail_filename='';
				my $vmail_txtfile='';
				my $sess_filename='';
				my $rowaffected='0';
				my $department_name = "";
				my $peer_id = "";
				my $department_id = "";
				my $report_id="";

				$mail_box = substr($command_line[2],index($command_line[2],"=") + 1);
				$duration = substr($command_line[12],index($command_line[12],"=") + 1);
				$caller_id = substr($command_line[8],index($command_line[8],"=") + 1);
				$file_name = substr($command_line[13],index($command_line[13],"=") + 1);
				$vmail_orig_time =substr($command_line[10],index($command_line[10],"=") + 1);
				$category = substr($command_line[11],index($command_line[11],"=") + 1);
				$session_id = substr($command_line[14],index($command_line[14],"=") + 1);
				$agent_id = substr($command_line[15],index($command_line[15],"=") + 1);

				$campaign_name ="";
				my $campaign_id=$mail_box;
				
				if($caller_id =~ /</i) {
					@vcallerid = split('"', $caller_id);
					$caller_id = $vcallerid[1] ;
				}

				@vfile = split('/', $file_name);
				if(scalar @vfile) {
					$vmail_filename = $vfile[scalar @vfile -1];
					$campaign_name = $vfile[scalar @vfile -4];
					###For pbx campaign_name will be used as department_name and agent_id as peer_id
					#$agent_id = $vfile[scalar @vfile -3];
				}

				if (not exists $departmenthash{$campaign_name}) {
						  populateDepartment($campaign_name,$dbh);
					}
				$department_id = $departmenthash{$campaign_name};

				$vmail_txtfile = $file_name;
				$file_name =~ s/\.txt/\.wav/g;
				$vmail_filename=~ s/txt/wav/g;
				$sess_filename= $session_id;
				$sess_filename=~ tr/./-/;
				
				$new_filename = "$campaign_name"."-"."$sess_filename"."_"."$caller_id"."\.wav";

				if($category ne 'pbx')
				{
					$query="update call_dial_status set vmail_filename='$new_filename',vmail_orig_time= from_unixtime('$vmail_orig_time'), vmail_duration='$duration' where session_id=$session_id";
					$rowaffected=query_execute($query,$dbh,4,__LINE__);

					if(!$rowaffected)
					{
						$query="update $table_name set vmail_filename='$new_filename',vmail_orig_time= from_unixtime('$vmail_orig_time'), vmail_duration='$duration',vm_agentid='$agent_id' where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);

			            #Adding information to current report
						$query =~ s/$table_name/current_report/i;
						query_execute($query,$dbh,0,__LINE__);
					}
				}
				if(defined($category) && ($category !~ /^$/ && $category !~ /^[\s]+$/) &&  $category eq 'pbx')
				{
					$query="select 4 from voicemail_cdr where session_id='$session_id'";
					$returnvar=query_execute($query,$dbh,1,__LINE__);

					if(!defined (@$returnvar[0]))
					{
						$query="insert into voicemail_cdr (mail_box,dtetme,duration,filename,department_id,department_name,caller_id,session_id,vm_peerid) values('$mail_box','$time','$duration','$new_filename','$department_id','$campaign_name','$caller_id','$session_id','$agent_id')";
						query_execute($query,$dbh,0,__LINE__);
					}
					else
					{
						$query="update  voicemail_cdr set mail_box='$mail_box',dtetme='$time',duration='$duration',filename='$new_filename',department_id='$department_id',department_name='$campaign_name',caller_id='$caller_id',vm_peerid='$agent_id' where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);
					}
				}
				else
				{
					$query="select 4 from voicemail where session_id='$session_id'";
					$returnvar=query_execute($query,$dbh,1,__LINE__);

			#if entry doesnot exist in the report table then insert it otherwise don't
					if(!defined (@$returnvar[0]))
					{
						$query="insert into voicemail (mail_box,dtetme,duration,filename,campaign_id,campaign_name,caller_id,session_id,vm_agentid) values('$mail_box','$time','$duration','$new_filename','$campaign_id','$campaign_name','$caller_id','$session_id','$agent_id')";
						query_execute($query,$dbh,0,__LINE__);
					}
					else
					{
						$query="update  voicemail set mail_box='$mail_box',dtetme='$time',duration='$duration',filename='$new_filename',campaign_id='$campaign_id',campaign_name='$campaign_name',caller_id='$caller_id',vm_agentid='$agent_id' where session_id=$session_id";
						query_execute($query,$dbh,0,__LINE__);
					}
				}

				$query="insert into voicemail_$table_name (mail_box,datetime,duration,filename,campaign_id,campaign_name,caller_id,session_id,vm_agentid,vmail_orig_time,cust_ph_no) values('$mail_box','$time','$duration','$new_filename','$campaign_id','$campaign_name','$caller_id','$session_id','$agent_id',from_unixtime('$vmail_orig_time'),'$caller_id')";
				$report_id=query_execute($query,$dbh,3,__LINE__);

				$query="insert into voicemail_$table_name (report_id,mail_box,datetime,duration,filename,campaign_id,campaign_name,caller_id,session_id,vm_agentid,vmail_orig_time,cust_ph_no) values('$report_id','$mail_box','$time','$duration','$new_filename','$campaign_id','$campaign_name','$caller_id','$session_id','$agent_id',from_unixtime('$vmail_orig_time'),'$caller_id')";
				$query =~ s/$table_name/current_report/i;
				query_execute($query,$dbh,0,__LINE__);

				system("cp $file_name /var/spool/asterisk/voicemail/$new_filename");
				system("rm -f $file_name $vmail_txtfile");
				system("chmod 755 /var/spool/asterisk/voicemail/$new_filename");
			}
##############NewVoiceMailRecorded END########################################

##############AgentMissed Call Start###########################################
			elsif(($thread_type ==  11) && ($command_line[0] =~ /Event: AgentMissed/))
			{
				my $agent_id='';
				my $campaign_id='';
				my $campaign_name='';
				my $caller_id='';
				my $agent_name='';
				my $session_id='';
				my $listentime=time();
				my $missed_call=0;
				my $entrytime="";
				my $miss_call_start_time="";
 
				$agent_id = substr($command_line[2],index($command_line[2],":") + 2);
				$agent_id = substr($agent_id,6,index($agent_id,"/")+4);
				$caller_id = substr($command_line[4],index($command_line[4],":") + 2);
				$campaign_name = substr($command_line[6],index($command_line[6],":") + 2);
				$session_id = substr($command_line[7],index($command_line[7],":") + 2);
				$remarks = substr($command_line[8],index($command_line[8],":") + 2);
				$entrytime = substr($command_line[9],index($command_line[9],":") + 2);
				$entrytime = ((defined($entrytime))?$entrytime:$listentime);
				$miss_call_start_time = substr($command_line[10],index($command_line[10],":") + 2);
				if (not exists $campaignNameHash{$campaign_name}) {
					populateCampaign($campaign_name,$dbh,'1');
				}
				$campaign_id=$campaignNameHash{$campaign_name};

				if (not exists $agentHash{$agent_id}) {
					populateAgent($agent_id,$dbh);
				}
				$agent_name = $agentHash{$agent_id};

				$query="select missed_call from missed_call_status where session_id=$session_id";
				my $return_var = query_execute($query,$dbh,1,__LINE__);
				if(defined($return_var) && ($return_var !~ /^$/ && $return_var !~ /^[\s]+$/))
				{
					$query = "update missed_call_status set agent_id=concat(agent_id,'/$agent_id'),missed_call=missed_call+1 where session_id = $session_id";
					query_execute($query,$dbh,0,__LINE__);
				}
				else
				{
					$missed_call =1;
					$query = "insert into missed_call_status(agent_id,campaign_id,session_id,cust_ph_no,missed_call) values ('$agent_id','$campaign_id','$session_id','$caller_id','$missed_call')";
					query_execute($query,$dbh,0,__LINE__);
				}
				
				$query="select agent_session_id,agent_ext from agent_live where agent_id = '$agent_id'";
				my $result = query_execute($query,$dbh,1,__LINE__);
				if(defined($result) && ($result !~ /^$/ && $result !~ /^[\s]+$/))
				{

					my $agent_session_id =@$result[0];
					$query = "insert into misscall_$table_name (node_id,agent_id,agent_ext,agent_name,campaign_id,campaign_name,agent_state,miss_call_time,miss_call_start_time,agent_session_id,session_id,cust_ph_no,totalCall,entrytime)values('$node_id','$agent_id','@$result[1]','$agent_name','$campaign_id','$campaign_name','$remarks',from_unixtime('$entrytime'),from_unixtime('$miss_call_start_time'),'$agent_session_id','$session_id','$caller_id','$missed_call','$entrytime')";
					query_execute($query,$dbh,0,__LINE__);

					check_cview($query,$dbh,$table_name,2);
					$query =~ s/$table_name/current_report/i;
					query_execute($query,$dbh,0,__LINE__);

					$query = "update agent_live set missed_count = missed_count+1 where agent_session_id=$agent_session_id and agent_id = '$agent_id'";
					query_execute($query,$dbh,0,__LINE__);
				}
					
				$query = "update queue_live set trying_flag=0,trying_agent_id=0 where session_id=$session_id";
				query_execute($query,$dbh,0,__LINE__);

				$query = "update agent_live set trying_flag=0,trying_cust_ph_no=0 where agent_id='$agent_id'";
				query_execute($query,$dbh,0,__LINE__);
			}
##############AgentMissed Call End###########################################

##############ChangeQueue Start###########################################
			elsif(($thread_type ==  11) && ($command_line[0] =~ /Event: ChangeQueue/))
			{
				my $agent_id;
				my $primaryQ;
				my $secondaryQ;
				my $campaign_id;
				my $previous_campaign_id;
				my $new_campaign_id;
				my $query;
				my $closer_time='';
				my $is_paused='';
				my $wait_time='';
				my $dialer_mode='';
				my $call_state='';
				my $last_activity_time='';
				my $campaign_string="";
				my $changeTable;
				my $agent_session_id;
				my $changequeue;
				$primaryQ = substr($command_line[3],index($command_line[3],":") + 2);
				$agent_id = substr($command_line[2],index($command_line[2],":") + 2);
				$agent_id = substr($agent_id,6,index($agent_id,"/")+4);
				$secondaryQ = substr($command_line[4],index($command_line[4],":") + 2);

				if (not exists $campaignNameHash{$primaryQ}) {
					populateCampaign($primaryQ,$dbh,'1');
				}
				$new_campaign_id = $campaignNameHash{$primaryQ};

				if (not exists $campaignNameHash{$secondaryQ}) {
					populateCampaign($secondaryQ,$dbh,'1');
				}
				$previous_campaign_id = $campaignNameHash{$secondaryQ};

				$query = "update agent_live set campaign_id ='$new_campaign_id',last_cust_ph_no='' where agent_id = '$agent_id'";
				query_execute($query,$dbh,0,__LINE__);

				$query = "update live_agent_primary_campaign_mapping set assigned_by = '$agent_id',change_date = now(),previous_campaign_id='$previous_campaign_id',new_campaign_id='$new_campaign_id' where agent_id = '$agent_id'";
				query_execute($query,$dbh,0,__LINE__);

				$agent_name = $agentHash{$agent_id};
				$campaign_string = $secondaryQ."_TO_".$primaryQ;

				$query="select DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as last_login_time,campaign_id,agent_session_id,is_paused,closer_time,wait_time,agent_state,call_dialer_type,last_activity_time,now() from agent_live where agent_id='$agent_id'";
				$returnvar=query_execute($query,$dbh,1,__LINE__);

				$changeTable = @$returnvar[0];
				$campaign_id = @$returnvar[1];
				$agent_session_id = @$returnvar[2];
				$is_paused= @$returnvar[3];
				$closer_time = @$returnvar[4];
				$wait_time = @$returnvar[5];
				$call_state = @$returnvar[6];
				$dialer_mode = @$returnvar[7];
				$last_activity_time = @$returnvar[8];
				$changequeue = @$returnvar[9];

				$query="select 1 from agent_state_analysis_current_report where agent_state='SECONDRY_CAMPAIGN' and call_end_date_time='0000-00-00 00:00:00' and agent_session_id=$agent_session_id";
				$returnvar=query_execute($query,$dbh,1,__LINE__);
				if(defined(@$returnvar[0]))
				{
					$query = "update agent_state_analysis_$changeTable set call_end_date_time = '$changequeue' where agent_id = '$agent_id' and agent_state='SECONDRY_CAMPAIGN' and agent_session_id=$agent_session_id and call_end_date_time='0000-00-00 00:00:00'";
					query_execute($query,$dbh,0,__LINE__);

#Adding information to current report
					check_cview($query,$dbh,$changeTable,2);
					$query =~ s/$changeTable/current_report/i;
					query_execute($query,$dbh,0,__LINE__);
				}
				$query = "insert into agent_state_analysis_$changeTable (node_id,agent_id,campaign_id,agent_state,call_start_date_time,agent_session_id,agent_name,campaign_name,entrytime,call_state) values('$node_id','$agent_id','$campaign_id','SECONDRY_CAMPAIGN','$changequeue','$agent_session_id','$agent_name','$campaign_string','$timestamp','$call_state')";
				query_execute($query,$dbh,0,__LINE__);
				check_cview($query,$dbh,$changeTable,2);
				$query =~ s/$changeTable/current_report/i;
				query_execute($query,$dbh,0,__LINE__);

			}
##############ChangeQueue End##############################################

##############Context FeedBack PAcket is start#############################
	elsif($thread_type == 11 && ($command_line[0] =~ /Event: Context_FeedBack/))
	{
		my $session_id='';
		my $caller_id='';
		my $data;
		my $agent_id=0;
		my $campaign_id='';
		my $agent_name='';
		my $campaign_name='';
		my $ivrspath="";
		my $skill_id=0;
		my $skill_name="";
		my $chan_var="";
		my $cust_ph_no="";
		my $calltype=0;
		my $preview_flg=0;
		my $CustUniqueId="";
		my @returnvar=();
		my @question_array=();
		my @agent_campaign_id=();
		my @splited_id=();
		my $length=0;
		my $autodial_flag=0;
		my $campaign_type="";
		my $dialtype="PROGRESSIVE";

		$session_id = substr($command_line[3],index($command_line[3],":")+2);
		$caller_id = substr($command_line[4],index($command_line[4],":")+2);
		$data = substr($command_line[6],index($command_line[6],":")+2);
		$chan_var =  substr($command_line[7],index($command_line[7],":")+2);
		$calltype = substr($command_line[8],index($command_line[8],":")+2);
		$ivrspath = substr($command_line[9],index($command_line[9],":")+2);
		$skill_id = substr($command_line[10],index($command_line[10],":")+2);
		$campaign_type = ($calltype==0?"INBOUND":"OUTBOUND");

		$query="select now()";
		my $tmp=query_execute($query,$dbh,1,__LINE__);
		my $feedback_time = @$tmp[0];

	    if(defined($chan_var) && ($chan_var !~ /^$/ && $chan_var !~ /^[\s]+$/))
		{
		   @returnvar=split(/,/,$chan_var);
		   $cust_ph_no = $returnvar[0];
		   $dialtype = $returnvar[5];
		   if($dialtype =~ /AUTODIAL/) {
			 $autodial_flag=1;
		   }
		}
		else
		{
				   $cust_ph_no = $caller_id;
		}
		$cust_ph_no =~ s/^\s+|\s+$//g;

		if($autodial_flag == 0)
		{
				@agent_campaign_id = split("##",$data);
				@splited_id = split(/\|/,$agent_campaign_id[0]);
				$CustUniqueId=(defined($splited_id[0])?$splited_id[0]:"");
				$campaign_name = (defined($splited_id[1])?$splited_id[1]:"");
				
				if($campaign_name =~ /preview/)
				{
					$campaign_name = substr($campaign_name,8);
				}

				if (not exists $campaignNameHash{$campaign_name})
				{
						populateCampaign($campaign_name,$dbh,'1');
				}
				$campaign_id =$campaignNameHash{$campaign_name};

				if(defined($splited_id[2]) && ($splited_id[2] !~ /^$/ && $splited_id[2] !~ /^[\s]+$/)) {
					$agent_id = substr($splited_id[2],index($splited_id[2],"/")+1);
					if (not exists $agentHash{$agent_id}) {
							populateAgent($agent_id,$dbh);
					}
					$agent_name = $agentHash{$agent_id};
				}
		}
		else{
				@agent_campaign_id = split("##",$data);
				@splited_id = split(/\|/,$agent_campaign_id[0]);
                $CustUniqueId=(defined($splited_id[0])?$splited_id[0]:"");
				$campaign_id = (defined($splited_id[1])?$splited_id[1]:"");

				if (not exists $campaignHash{$campaign_id}) {
					populateCampaign($campaign_id,$dbh,'0');
				}
				$campaign_name = $campaignHash{$campaign_id};
		}

		if(defined($skill_id) && ($skill_id !~ /^$/ && $skill_id !~ /^[\s]+$/) && $skill_id > 0)
		{
			if (not exists($campaignSkillHash{$skill_id."_".$campaign_id})) {
				populateSkill($dbh);
			}
			$skill_name=$campaignSkillHash{$skill_id."_".$campaign_id};
		}

        if(defined($agent_campaign_id[1]) && ($agent_campaign_id[1] !~ /^$/ && $agent_campaign_id[1] !~ /^[\s]+$/)){
		   @question_array = split("#",$agent_campaign_id[1]);
		   $length=scalar(@question_array);
		}

		if($length==0)
		{
			my $question = "No_Question";
			my $answer = "No_Answer";
			$query = "insert into feedback_$table_name(cust_ph_no,session_id,agent_id,campaign_id,agent_name,campaign_name,call_start_date_time,question,answer,ivrs_path,skill_name,CustUniqueId,campaign_type,dialer_type,entrytime) values ('$cust_ph_no',$session_id,'$agent_id','$campaign_id','$agent_name','$campaign_name',now(),'$question','$answer','$ivrspath','$skill_name','$CustUniqueId','$campaign_type','$dialtype',unix_timestamp('$feedback_time'))";
			query_execute($query,$dbh,0,__LINE__);
			$query =~ s/$table_name/current_report/i;
			query_execute($query,$dbh,0,__LINE__);
			undef $question;
			undef $answer;
		}
		else
		{
			$i=0;
			foreach(@question_array)
			{
				my @return = split('@',$question_array[$i]);
				my $question = $return[0];
				my $answer = $return[1];
				if((!defined($question))|| $question eq "unknown")
				{
						$question = "No_Question";
				}
				if((!defined($answer))|| $answer eq "unknown")
				{
						$answer = "No_Answer";
				}
				$query = "insert into feedback_$table_name(cust_ph_no,session_id,agent_id,campaign_id,agent_name,campaign_name,call_start_date_time,question,answer,ivrs_path,skill_name,CustUniqueId,campaign_type,dialer_type,entrytime) values ('$cust_ph_no',$session_id,'$agent_id','$campaign_id','$agent_name','$campaign_name',now(),'$question','$answer','$ivrspath','$skill_name','$CustUniqueId','$campaign_type','$dialtype',unix_timestamp('$feedback_time'))";
				query_execute($query,$dbh,0,__LINE__);
				$query =~ s/$table_name/current_report/i;
				query_execute($query,$dbh,0,__LINE__);
				$i++;
				undef $question;
				undef $answer;
			}
         }		
}
##############Context FeedBack PAcket is END#############################

##############Context Context TimeRule is start#############################
			elsif($thread_type == 11 && ($command_line[0] =~ /Event: Context_TimeRule/))
			{

				my $campaignid='';
				my $rulename='';
				my $ivrs_leadf_node='Time_Rule';
				my $ivrs_path='Time_Rule';
				my $did_num='';
				my $type='';
				my $ivrs_path_new="";

				$channel = substr($command_line[2],index($command_line[2],":") + 2);
				$session_id = substr($command_line[3],index($command_line[3],":") + 2);
				my $cust_ph_no = substr($command_line[4],index($command_line[4],":") + 1);
				my $returnvar = substr($command_line[6],index($command_line[6],":") + 1);
				my $did = substr($command_line[12],index($command_line[12],":") + 1);

				$query="select now(),unix_timestamp()";
				my $tmp=query_execute($query,$dbh,1,__LINE__);
				my $timerule_time = @$tmp[0];
				my $entrytime = @$tmp[1];

				if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
				{
					$returnvar=~ s/\s+//g;
					@variables=split(/,/,$returnvar);
					$type=$variables[0];
					$campaignid=$variables[1];
					$rulename=$variables[2];
					$did_num=$variables[3];
				}

				$ivrs_path = ((defined($rulename))?$rulename:$ivrs_path);
				$ivrs_path_new = "$type"."->"."$ivrs_path";
				if (not exists $campaignHash{$campaignid}) {
					populateCampaign($campaignid,$dbh,'0');
				}
				$campaign_name = $campaignHash{$campaignid};

				if(($channel =~ /ZAP/i))
				{
					$zap_channel=substr($channel,0,index($channel,"-"));
					$channel="Zap";
				}
				else {
					$zap_channel=$channel;
					$channel = "SIP";
				}
				$report_id='';
				$query = "insert into ivr_report_$table_name (node_id,session_id,link_date_time,unlink_date_time,ivrs_path,cust_ph_no,ivrs_leaf_node,zap_channel,CampaignEnded,did_num,entrytime)  values ('$node_id','$session_id','$timerule_time','$timerule_time','$ivrs_path_new','$cust_ph_no','$ivrs_leadf_node','$channel','$campaign_name','$did','$entrytime') ";
				$report_id=query_execute($query,$dbh,3,__LINE__);

				$query = "insert into ivr_report_$table_name (report_id,node_id,session_id,link_date_time,unlink_date_time,ivrs_path,cust_ph_no,ivrs_leaf_node,zap_channel,CampaignEnded,did_num,entrytime) values ('$report_id','$node_id','$session_id','$timerule_time','$timerule_time','$ivrs_path_new','$cust_ph_no','$ivrs_leadf_node','$channel','$campaign_name','$did','$entrytime')";
				check_cview($query,$dbh,$table_name,3);
				$query =~ s/$table_name/current_report/i;
				query_execute($query,$dbh,0,__LINE__);

			}
##############Context Context TimeRule is End#############################
##############Agent Called packet start###################################
			elsif($thread_type == 11 && ($command_line[0] =~ /Event: AgentCalled/))
			{
				my $agent_id = "";
				my $caller_id = "";
				my $session_id = "";
				$agent_id=substr($command_line[2],index($command_line[2],"/") + 1);
				$caller_id = substr($command_line[4],index($command_line[4],":") + 2);
				$session_id = substr($command_line[9],index($command_line[9],":") + 2);

				$query = "update agent_live set trying_flag=1,trying_cust_ph_no='$caller_id' where agent_id='$agent_id'";
				query_execute($query,$dbh,0,__LINE__);

				$query = "update queue_live set trying_flag=1,trying_agent_id='$agent_id' where session_id=$session_id";
				query_execute($query,$dbh,0,__LINE__);

			}
##############Agent Called packet End#######################################
			$ILcount++;
		}
	};
	if ($@)
	{
		error_handler("Main Parser Crashed",__LINE__,$@);
	}
}
##################################MAIN PARSE() FUNCTION END#########################


##################FAIL SAFE START #############################################################################
# to sync the CRM (database) with Telephony (asterisk) when listener starts after a crash or manually restarted
###############################################################################################################
sub fail_safe
{
	my @command_line;
	my $agent_id;
	my $agent_count=0;
	my $agent_ext;
	my $query;
	my $session_id;
	my $retval;
	my $dialer_type;
	my $talking_channels="(";
	my $channel;
	my $dbh;
	my $cmd;
	my $tn;
	my @test=();
	my $count;
	my $res;
	my $retArray;
	my $phoneType;
	my $staticIP;
	my $time;
	my $zap_channel;
	my $zap_flag;
	my $custphno;
	my $agent_session_id;
	my $sip_talking="(";
	my $start_parsing=0;
	my $sth;
	my $fsth;
	my $message="";
	my $agentList="";
	my $last_updated_time;
	my $last_activity_time='';
	my $timestamp=time();
	my @thread_type=();
	my $i;
	my $value;
	my $shared_key;
#XXX what should be the value of limit, as discussed it is set the 8 minutes
	my $limit=480;
	my @thread_id=();
	my $campaign_name;
	my %cleanDB=();
	my $campaign_id;
	my $dialerType;
	my @arr=();

	my @n_red_channels=();
	my $red_channels;
	my @n_clear_channels=();
	my $clear_channels;
	my $currentReportTime;
	my %customer_live_session_hash;
	my $failsafe_agent_in_conf_check=0;
	my $conf_ph_no='';
	my $conf_num='';
	my @conference_data='';
	my $caller_Id='';
	my $call_Type='';
	my $monitor_file_name='';
	my $monitor_sub_folder='';
	my $monitor_file_path='';
	my $chan_var='';
	my $confunique_id='';
	my $ztc_chan='';
	my $ztc_conf_no='';
	my $ztc_conf_mode='';
	my $ztc_fd='';


#initialize the time only once and will be used in every block
	    $time=get_time_now();
#initialize the date variable
	    $dialing_date = substr(get_time_now(),0,10);

	    my $table_name=substr($time,0,7);
	    $table_name=~s/-/_/g;

	    $thread_type[0]=0;      #sendTelnetCommand
		$thread_type[1]=1;      #Link,Unlink
		$thread_type[2]=2;      #Agentlogin AgentcallbackLogin Agentlogoff AgentCallbackLogoff Hangup
		$thread_type[3]=3;      #NewExten
		$thread_type[4]=4;      #Shutdown #NewVoiceMailRecorded PeerStatus 14 15 12 #Bargestart #Bargestop Alarm
		$thread_type[5]=5;      #Hangup NewPreviewChannel
		$thread_type[6]=6;      #Join leave Abandon CDR EventHOld QueueFailed
		$thread_type[7]=7;      # Wraptime ,Monitor campfileformat Populating disposition hash ,FtpUpdateComplete
		$thread_type[8]=8;      #AutoPreviewDialer PreviewDialer PreviewDialFailure SetVerifier
		$thread_type[9]=9;      #QueueMemberPaused meetmejoin MeetMeCrmINfo meetmeleave
		$thread_type[10]=10;    #Agentconnect AgentComplete SetMeFree,Transfer
		$thread_type[11]=11;    #Robodial Robodisconnect AMD Context_TimeRule Context_FeedBack AgentCalled
		$thread_type[12]=14;    #NewState
		$thread_type[13]=12;    #ReloadDialer
		$thread_type[14]=15;    #Park,UnPark



		$dbh=DBI->connect("dbi:mysql:$db:$server",$username,$password,{mysql_auto_reconnect => 1}) or die (exit);   $tn = new Net::Telnet (Timeout => 10,Prompt  => '/%/',Host    => "localhost",Port    => "5038", Errmode=>"return");
		$tn->waitfor('/0\n$/');
		$tn->print("Action: Login\nUsername: $telnet_username\nSecret: $telnet_secret\nEvents: Off\n");
		$tn->waitfor('/Authentication accepted/');
		$tn->buffer_empty;
		$tn->max_buffer_length( 50*1024*1024 );

#----Set node id-------
	   set_node_id();

	   cview_flag($dbh);

#
#<TVT> Check if month report table and IVR table exists in database. if not then create them here
# CRITICAL as we at times loose data because of some system time but we donot have any corresponding table.
# Let's have a file where we save the show create table for reports etc
# include that file. so that if our table structure change we donot have to change the listerner code.

	
	       $query="select year(now()),month(now())";
	       $retval=query_execute($query,$dbh,1,__LINE__);
	       my $k = @$retval[0];
	       my $j = @$retval[1];
	   
		   for(my $monthCount=0;$monthCount<3;$monthCount++) {
			my $reporting_table = $k."_".($j<10?"0".$j:$j);
			checkTables($dbh,$reporting_table);
		     if($j == 12){
				$k= $k+1;
				$j=1;
			 }
			 else {
				$j=$j+1;
			 }
		    }


#store the CRM license information in a variable, if doens't exist then delete the record from customer table which was inserted from here in case of incoming call
#<TVT> Can we modify this code so that it can be done in one query. We can avoid locking
# feature table more than once.
# Not critical.
	$query="select feature_name,state from features where feature_name in ('CRM','IVR','IPBX')";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($retval = $sth->fetchrow_arrayref)
	{
		if(@$retval[0] =~ /CRM/i) {
			if(defined(@$retval[1]) && (@$retval[1] == 1))
			{
				$crm_license = 1;
			}
		}
		elsif(@$retval[0] =~ /IVR/i) {
			if(defined(@$retval[1]) && (@$retval[1] == 1))
			{
				$ivr_license = 1;
			}
		}
		elsif(@$retval[0] =~ /IPBX/i) {
			if(defined(@$retval[1]) && (@$retval[1] == 1))
			{
				$ipbx_license = 1;
			}
		}
	}
	$sth->finish;


#----Check for AGENT License---------------
	$query="select max_value from maximum where features='AGENTS'";
	$retval=query_execute($query,$dbh,1,__LINE__);
	if(defined(@$retval[0]))
	{
		$max_agents = @$retval[0];
	}

#------Initialize all the Hashes----------
#------Create Required Hashes--------------
	$query="select campaign_id,campaign_name,wrapupTime,monitor_file_type,campaign_type,screen_transfer,blended_list_lookup,abandon_action,perm_max_retries,conference_action,conf_wrapup_time,new_monitor_flag,max_agent,customer_lookup,sticky_flag,cust_reporting_flag from campaign";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

	while ($retval = $sth->fetchrow_arrayref)
	{
#<TVT> When the program is starting, we have to assume that no hash exists.
# Chaecking for not exists does not sound correct. Should remove it.
# even semaphore lock can be avoided here because the code has just started
# and no thread is in existance now other than fail_safe.
# NON-CRITICAL
		$queueHash{@$retval[0]}=0;
# Campaign id - Campaign Name Mapping
		$campaignHash{@$retval[0]}=@$retval[1];
# Campaign Name - Campaign id Mapping
		$campaignNameHash{@$retval[1]}=@$retval[0];
		$campaignScreenHash{@$retval[0]}=@$retval[5];
		$campaignblendedlookup{@$retval[0]}=@$retval[6];
		$campaignabandon_action{@$retval[0]}=@$retval[7];
		$campaigntype{@$retval[0]}=@$retval[4];
		$campaignmax{@$retval[0]}=@$retval[8];
		$campaign_conference{@$retval[0]}=@$retval[9];
		$campaign_conf_WrapHash{@$retval[0]}=@$retval[10];
		$new_monitor_flagHash{@$retval[0]}=@$retval[11];
		$camp_agentcount{@$retval[0]}=@$retval[12];
		$customerlookup{@$retval[0]}=@$retval[13];
		$sticky_campaignhash{@$retval[0]}=@$retval[14];
		$cust_reporting_flagHash{@$retval[0]}=@$retval[15];

#-----------Campaign Wrap Hash-------------
		$campaignWrapHash{@$retval[0]}=@$retval[2];
		$fileFormatHash{@$retval[0]}=@$retval[3];
	}
	$sth->finish;

#--------------Campaign Skill Hash--------------
	$query="select skill_id,skill_name,campaign_id from skills";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

	while ($retval = $sth->fetchrow_arrayref) {
		$campaignSkillHash{@$retval[0]."_".@$retval[2]}=@$retval[1];
	}
	$sth->finish;

#--------------provider name Hash----------------------
	$query="select zap_id,provider_name,Caller_id from zap";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

	while ($retval = $sth->fetchrow_arrayref) {
		@$retval[0] =~ s/ZAP/Zap/g;
		$providernameHash{@$retval[0]}=@$retval[1];
		$pricalleridHash{@$retval[1]}=@$retval[2];
	}
	$sth->finish;

#--------------SIP provider name Hash----------------------
	$query="select b.sip_gateway_name,b.ipaddress,a.sip_id from sip as a,sip_gateway as b where a.sip_gateway_name=b.sip_gateway_name;";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

	while ($retval = $sth->fetchrow_arrayref) {
		$sip_providernameHash{@$retval[1]}=@$retval[0];
		$sip_id_providernameHash{@$retval[2]}=@$retval[0];
	}
	$sth->finish;

#--------------ivrinfo name Hash----------------------
	$query="select ivr_node_id,ivr_node_name from ivr_node";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

	while ($retval = $sth->fetchrow_arrayref) {
		$ivrinfo{@$retval[0]}=@$retval[1];
	}
	$sth->finish;

#----------------------department id Hash-----------
	$query = "select department_id,department_name from department";
        $sth=$dbh->prepare($query);
        $sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
        while ($retval = $sth->fetchrow_arrayref)
        {
                $departmenthash_semaphore->down;
                $departmenthash{@$retval[1]} = @$retval[0];
                $departmenthash_semaphore->up;
        }
        $sth->finish;

#--------Campaign Csat Hash-----------

	$query="select campaign_id,start_time,end_time,call_duration,time_rule_flag,ip_address,rule_type from outbound_csat";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

	while ($retval = $sth->fetchrow_arrayref) {
		my @variables=split(/,/,@$retval[0]);
		my $j=0;
		foreach(@variables){
			$campaignCsatHash{$variables[$j]}=@$retval[1]."_".@$retval[2]."_".@$retval[3]."_".@$retval[4]."_".@$retval[5]."_".@$retval[6];
			$j++;
		}
	}
	$sth->finish;
#----------------Camapign csat end-----------
#----------------invcsat hash-------
	$query="select ivr_id,start_time,end_time,call_duration,time_rule_flag,ip_address,campaign_id from outbound_csat";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

	while ($retval = $sth->fetchrow_arrayref) {
		my @variables=split(/,/,@$retval[0]);
		my $k=0;
		foreach(@variables){
			$ivrCsatHash{$variables[$k]}=@$retval[1]."_".@$retval[2]."_".@$retval[3]."_".@$retval[4]."_".@$retval[5]."_".@$retval[6];
			$k++;
		}
	}
	$sth->finish;
#--------------ivrCsathash end--------

#--------------Agent Id to Name Hash-------------------
	$query="select agent.agent_id,agent.agent_name from agent_live,agent where agent.agent_id=agent_live.agent_id";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($retval = $sth->fetchrow_arrayref) {
		$agentHash{@$retval[0]} = @$retval[1];
	}
	$sth->finish;
#-------------------------------------------------------

#--------------MonitorFileFormat Lead Manual Hash---------------
	$query="select campaign_id,lead_voicefile_format,lead_fieldRef,manual_voicefile_format,manual_fieldRef,cust_fields,customer_fields from voicefile_template";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($retval = $sth->fetchrow_arrayref)
	{
		if(defined(@$retval[1]) && (@$retval[1] !~ /^$/ && @$retval[1] !~ /^[\s]+$/)){
			$MonitorFileFormatLead_semaphore->down;
			$MonitorFileFormatLead{@$retval[0]} = @$retval[2]."##".@$retval[1]."##".@$retval[5]."##".@$retval[6];
			$MonitorFileFormatLead_semaphore->up;
		}
		if(defined(@$retval[3]) && (@$retval[3] !~ /^$/ && @$retval[3] !~ /^[\s]+$/)){
			$MonitorFileFormatManual_semaphore->down;
			$MonitorFileFormatManual{@$retval[0]}=@$retval[4]."##".@$retval[3];
			$MonitorFileFormatManual_semaphore->up;
		}
	}
	$sth->finish;

#--------------------------------------------
#--------------Reporting Lead Hash---------------
	$query="select campaign_id,lead_reporting_format,lead_fieldRef,manual_reporting_format,manual_fieldRef,cust_fields,customer_fields from reporting_template";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($retval = $sth->fetchrow_arrayref)
	{
		if(defined(@$retval[1]) && (@$retval[1] !~ /^$/ && @$retval[1] !~ /^[\s]+$/)){
			$ReportingFormatLead_semaphore->down;
			$ReportingFormatLead{@$retval[0]} = @$retval[2]."##".@$retval[1]."##".@$retval[5]."##".@$retval[6];
			$ReportingFormatLead_semaphore->up;
		}
		if(defined(@$retval[3]) && (@$retval[3] !~ /^$/ && @$retval[3] !~ /^[\s]+$/)){
			$ReportingFormatManual_semaphore->down;
			$ReportingFormatManual{@$retval[0]}=@$retval[4]."##".@$retval[3];
			$ReportingFormatManual_semaphore->up;
		}
	}
	$sth->finish;

#------------------------------------------------------


	populate_disposition_hash($dbh);

#--------------Hashes Created--------------------------

	$message = "";
	$message="$timestamp,";
	while(($shared_key,$value) =each(%queueHash))
	{
		$message.="$shared_key=>$value,";
	}
	shmwrite($sh_mem_id,$message,0,100);


	if($DB) {
		open OUT, ">>/tmp/listener_queries.txt";
		print OUT "\n-----------IN FAIL SAFE---------------------------\n";
		print OUT "crm_lic = $crm_license ,ivr_lic = $ivr_license, shared_memory = $message";
		print OUT "\n---------------------------\n";
		close OUT;
	}


#to initialize the queue with 0 for the first time when this file executes
#<TVT> queue initiaization is not reqd here. if so then we init all of the fields. check for date time missing too.
#$query="update listener_status set queue=0";
#query_execute($query,$dbh,0,__LINE__);


#Remove two days old entry
	$query = "delete from current_report where date(call_start_date_time) < addDate(date(now()),-1)";
	query_execute($query,$dbh,0,__LINE__);

	$query = "delete from cdr_current_report where date(calldate) < addDate(date(now()),-1)";
	query_execute($query,$dbh,0,__LINE__);

	$query = "delete from agent_state_analysis_current_report where date(call_start_date_time) < addDate(date(now()),-1)";
	query_execute($query,$dbh,0,__LINE__);

	$query = "delete from ivr_report_current_report where date(link_date_time) < addDate(date(now()),-1)";
	query_execute($query,$dbh,0,__LINE__);

	$query = "delete from feedback_current_report where date(call_start_date_time) < addDate(date(now()),-1)";
	query_execute($query,$dbh,0,__LINE__);

	$query = "delete from misscall_current_report where date(miss_call_time) < addDate(date(now()),-1)";
	query_execute($query,$dbh,0,__LINE__);

	$query = "delete from escalation_current_report where date(entrytime) < addDate(date(now()),-1)";
	query_execute($query,$dbh,0,__LINE__);

	$query = "delete from voicemail_current_report where date(vmail_orig_time) < addDate(date(now()),-1)";
    query_execute($query,$dbh,0,__LINE__);

	$query = "delete from alertMsg where date(dateTime) < addDate(date(now()),-1)";
	query_execute($query,$dbh,0,__LINE__);

	$query = "delete from messaging where date(msgEntered) < addDate(date(now()),-1)";
	query_execute($query,$dbh,0,__LINE__);

#clean the queue live table when  listener restarts
	$query = "delete from queue_live";
	query_execute ($query, $dbh, 0, __LINE__);


	$query="delete from crm_meetme_live";
	query_execute($query,$dbh,0,__LINE__);

	$query="delete from park_live";
	query_execute($query,$dbh,0,__LINE__);

	$query = "optimize table zap_live";
	query_execute($query,$dbh,0,__LINE__);

	#sync the meetme_user table with sip or zap table
	#$query="delete from meetme_user where session_id not in (select session_id from sip)";
	#query_execute($query,$dbh,0,__LINE__);

	#$query="delete from meetme_user where session_id not in (select session_id from zap)";
	#query_execute($query,$dbh,0,__LINE__);

	$last_updated_time=time;
	$currentReportTime=time;
	$time=time;
	$file_global_flag=1;


##################FILE GLOBAL FLAG START ###################################
	if($file_global_flag == 1)
	{
		$time=get_time_now();
		$flags_semaphore->down;
		$file_global_flag = 0;
		$flags_semaphore->up;


#-------Conference Check Start--------------------
		$query = "delete from failsafe_conf_room";
		query_execute($query,$dbh,0,__LINE__);

		$query = "insert into failsafe_conf_room(session_id,confno,chan_name,cust_ph_no) select session_id,confno,chan_name,cust_ph_no from meetme_user";
		query_execute($query,$dbh,0,__LINE__);

		$query="update agent_live set agent_in_conf=0";
		query_execute($query,$dbh,0,__LINE__);

		my $ILcount=0;
		$tn->buffer_empty;
		$cmd = "Action: command\ncommand: show conferences2\n";
		my @input_line = $tn->cmd(String => $cmd, Prompt => '/--END COMMAND--.*/', Errmode    => Return, Timeout  => 10);
         
		my %conf_cleanDB =();
###-----------hash of session on meet_me user-----
		$query="select TRIM(TRAILING '0' FROM session_id) as session_id,chan_name,confno from meetme_user";
		$sth=$dbh->prepare($query);
		$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
		if($sth->rows)
		{
			while(my $row=$sth->fetchrow_arrayref)
			{               
				$conf_cleanDB{@$row[2]."_".@$row[1]."_".@$row[0]}=@$row[0]."####".@$row[1]."####".@$row[2];
			}
		}
		$sth->finish();

		if($input_line[2] !~ /No active conferences2./)
		{
			foreach(@input_line)
			{
				if($input_line[$ILcount] =~ /^[0-9]/) {
					my @conf_line_data = split(/\n/,$input_line[$ILcount]);
					@conference_data = split(/\|/,$conf_line_data[0]);
					$conf_num = $conference_data[0];
					$channel  = $conference_data[1];
					$session_id = $conference_data[2];
					$session_id =~ s/\.(?:|.*[^0]\K)0*\z//;
					$caller_Id =  $conference_data[3];
					$call_Type  = $conference_data[4];
					$monitor_file_name = $conference_data[5];
					$monitor_file_path =  $conference_data[6];
					$monitor_sub_folder = $conference_data[7];
					$chan_var = $conference_data[8];
					$confunique_id = $conference_data[9];
					$ztc_chan = $conference_data[10];
					$ztc_conf_no = $conference_data[11];
					$ztc_conf_mode = $conference_data[12];
					$ztc_fd = $conference_data[13];
					my $conf_ph_no = "";
					my $campaign_id =0;
					my $lead_id=0;
					my $list_id=0;
					my $dialerType="PROGRESSIVE";
					my $vdn_flag=0;
					my $is_vdn=0;
					my $conf_num_live = $conf_num;
	

				    if(defined($chan_var) && ($chan_var !~ /^$/ && $chan_var !~ /^[\s]+$/)) {
					 my @variables = split(/,/,$chan_var);
					 if($variables[0] =~ /\-/) {
						my @returnvarSessn=split('\-',$variables[0]);
						$conf_ph_no = $returnvarSessn[0]; 
					 }
					 else {
						$conf_ph_no = $variables[0];
					 }
					$campaign_id = (defined($variables[2])?$variables[2]:"0");
					$lead_id = (defined($variables[1])?$variables[1]:"0");
					$list_id = (defined($variables[3])?$variables[3]:"0");
					$dialerType=(defined($variables[5] && ($variables[5] !~ /^$/ && $variables[5] !~ /^[\s]+$/))?$variables[5]:"PROGRESSIVE");
					$vdn_flag= (defined($variables[7])?$variables[7]:""); 

					if(defined($vdn_flag) && ($vdn_flag !~ /^$/ && $vdn_flag !~ /^[\s]+$/))
					{
						$is_vdn=1;
					}
				}
				if (!defined($conf_ph_no) || ($conf_ph_no =~ /^$/ || $conf_ph_no =~ /^[\s]+$/)) {
					$conf_ph_no=((defined($caller_Id) && ($caller_Id !~ /^$/ && $caller_Id!= /^[\s]+$/))?$caller_Id:"$conf_ph_no");
				}

				if(defined($monitor_sub_folder) && ($monitor_sub_folder !~ /^$/ && $monitor_sub_folder !~ /^[\s]+$/)  && length($monitor_sub_folder) > 2)
				{
					if($monitor_sub_folder !~ /^\// && $monitor_file_path !~ /\/$/) {
						$monitor_sub_folder =  "/".$monitor_sub_folder;
				}
				$monitor_file_path =  $monitor_file_path.$monitor_sub_folder;
				if($monitor_file_path !~ /\/$/) {
					$monitor_file_path =  $monitor_file_path."/";
				}
				}

				$failsafe_agent_in_conf_check = 0;

				if($conf_num =~ /\-/)
				{
					my @returnvarSessc=split('\-',$conf_num);
					$conf_num_live=$returnvarSessc[0];
				}
				if($conf_num_live == $conf_ph_no) {
					$failsafe_agent_in_conf_check = 1;
				}

				my @returnvarSessd=split('\.',$confunique_id);
				my $link_timeConf = $returnvarSessd[0];
				#my $conf_time = "from_unixtime('$returnvarSessd[0]')";

				my @returnvarSessdSession=split('\.',$session_id);
				my $link_timeSession = $returnvarSessdSession[0];
				my $link_time=0;
				
				if ($link_timeConf>$link_timeSession) {
					$link_time=$link_timeConf;

				}else{
					$link_time=$link_timeSession;
				}
				my $conf_time = "from_unixtime('$link_time')";

#---Value in hash exists, update flag in failsafe conf table and if its an agent in conf room mark it as agent_in_cnof in live table and in fail_safe_agent_check mark it as logged in----
#---else if value doesn't exist insert new entry, if the agent is in conf mark the agent as logged in with agent_in_conf flag and don't delete it and in fail_safe_agent_check mark it as logged in-----------

#---check in hash-----------
				my $hash_key = $conf_num."_".$channel."_".$session_id;
				if(exists($conf_cleanDB{$hash_key})) {
					$query="update failsafe_conf_room set failsafe_run=1 where  session_id=$session_id && confno='$conf_num' && chan_name='$channel'";
					query_execute($query,$dbh,0,__LINE__);
				}
				else {
					if (!defined($campaign_id) || $campaign_id ==0 || ($campaign_id =~ /^$/ || $campaign_id =~ /^[\s]+$/)) {
						$query="select campaign_id from agent where agent_id='$conf_num'";
						$retval=query_execute($query,$dbh,1,__LINE__);
						$campaign_id=@$retval[0];
					}
					$query="insert into meetme_user(confno,chan_name,fd,ztc_chan,ztc_confno,ztc_confmode,flag,session_id,cust_ph_no,monitor_filename,callType,monitor_file_path,campaign_id,link_time,conference_start_time,lead_id,list_id,is_vdn,dialer_type) values ('$conf_num','$channel','$ztc_fd','$ztc_chan','$ztc_conf_no','$ztc_conf_mode','','$session_id','$conf_ph_no','$monitor_file_name','$call_Type','$monitor_file_path','$campaign_id','$link_time',$conf_time,'$lead_id','$list_id','$is_vdn','$dialerType')";
					query_execute($query,$dbh,0,__LINE__);
				}

				if($failsafe_agent_in_conf_check) {
					my $alb_table="";
					my $dst_uri="";
					my $call_back_flag=0;

                    $query="select call_back from agent where agent_id='$conf_num_live'";
					$retval=query_execute($query,$dbh,1,__LINE__);
					$call_back_flag=@$retval[0];

                    if ($call_back_flag==0) {
						$query="update agent_live set agent_in_conf=1,is_paused=1 where agent_id='$conf_num_live'";
					    query_execute($query,$dbh,0,__LINE__);
                    }
				}
			}
			$ILcount++;
		}
     }

	$query="delete from meetme_user where session_id in (select session_id from failsafe_conf_room where failsafe_run=0)";
	query_execute($query,$dbh,0,__LINE__);

#-------Conference Check End-----------------------

        $tn->buffer_empty;
    	$cmd ="Action: Command\nCommand: show agents\n";
		@command_line = $tn->cmd(String => $cmd, Prompt => '/--END COMMAND--.*/', Errmode    => Return, Timeout  => 10);
#if no agent is configured in agent.conf then delete agent from agent_live if any exist
		 if(($command_line[1] =~ /Errno: 612/) || ($command_line[2] =~ /No Agents are configured in/))
				{
					$query="select agent_id from agent_live where agent_in_conf=0";
					$sth=$dbh->prepare($query);
					$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
					if($sth->rows)
					{
						while(my $row=$sth->fetchrow_arrayref)
						{
							$cleanDB{@$row[0]}=@$row[0];
						}
					}
					$sth->finish();
					foreach $key (keys %cleanDB)
					{
						$query="select agent_state,is_paused,is_free,dialer_type,last_login_time,DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as last_login_time_table,pauseDuration,pause_time,unix_timestamp() as pause_cur_time,call_counter,last_activity_time,now(),agent_session_id,wait_duration,ready_time,agent_id,campaign_id from agent_live where agent_id='$key'";
						$retval=query_execute($query,$dbh,1,__LINE__);
						failsafeLogout ($dbh,$retval,$cleanDB{$key},$table_name,$time,'0');
						delete $cleanDB{$key};
					}

				}
		else {
			my $res=2;
#--Make cleanDB hash of agents from agent_live then sync with asterisk
			$query="select agent_id from agent_live where agent_in_conf=0";
			$sth=$dbh->prepare($query);
			$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
			if($sth->rows)
			{
				while(my $row=$sth->fetchrow_arrayref)
				{
					$cleanDB{@$row[0]}=@$row[0];
				}
			}
			$sth->finish();

			$start_parsing=0;
			foreach(@command_line)
			{
				if(($start_parsing == 1) || ($command_line[$agent_count] =~ /Response: Follows/))
				{
					$start_parsing=1;
					$agent_id=substr($command_line[$agent_count],0,index($command_line[$agent_count]," "));

					if($cleanDB{$agent_id}) {
						$query="select agent_state,is_paused,is_free,dialer_type,last_login_time,DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as last_login_time_table,pauseDuration,pause_time,unix_timestamp() as pause_cur_time,call_counter,last_activity_time,now(),agent_session_id,wait_duration,ready_time from agent_live where agent_id='$agent_id'";
						$retval=query_execute($query,$dbh,1,__LINE__);
					}

					if($command_line[$agent_count]=~/ not logged in /)
					{
						if($cleanDB{$agent_id}) {
							failsafeLogout ($dbh,$retval,$agent_id,$table_name,$time,'0');
							delete $cleanDB{$agent_id};
						}
					}

					elsif($command_line[$agent_count]=~/ idle /)
					{
						$agent_session_id=substr($command_line[$agent_count],index($command_line[$agent_count],"session")+8);
						$agent_session_id=substr($agent_session_id,0,index($agent_session_id," "));
						my $agent_login_time=substr($command_line[$agent_count],index($command_line[$agent_count],"at ")+3);
						my @agentlogin= split(/\s+/i,$agent_login_time);
						$agent_login_time = $agentlogin[0]." ".$agentlogin[1];
						my $agent_chan=substr($command_line[$agent_count],index($command_line[$agent_count],"on ")+3);
						$agent_chan=substr($agent_chan,0,index($agent_chan," "));
						if ($agent_chan =~ /Cbk_Dial/i) {
							@test=split (/@/,$agent_chan);
							$agent_ext=$test[0];
						}
						else
						{
							@test=split(/\s+SIP\/|\s+ZAP\//i,$command_line[$agent_count]);
							@test=split(/-[0-9a-zA-Z]+\s+/i,$test[1]);
							$agent_ext=$test[0];
						}
						
						my $login_chan="";
						$login_chan=substr($command_line[$agent_count],index($command_line[$agent_count],"cbkchannel")+11);
						$login_chan=substr($login_chan,0,index($login_chan," "));
						@chanarry = split (/\|/,$login_chan);
						$login_chan = (defined($chanarry[0])?$chanarry[0]:"");
						if($command_line[$agent_count] =~ /zap/i)
						{
							$zap_channel=$agent_ext;
							$talking_channels="$talking_channels'$zap_channel',";
						}

						if($cleanDB{$agent_id}) {
							if($agent_session_id != @$retval[12]) {
								failsafeLogout ($dbh,$retval,$agent_id,$table_name,$time,'0');
								AgentLoginBlock($agent_id,$agent_ext,$agent_session_id,$dbh,"fail","",$agent_login_time,$table_name,$agent_chan,"0");
							}
							else {
								AgentLoginBlock($agent_id,$agent_ext,$agent_session_id,$dbh,"fail_safe_butdonotupdatetable","","",$table_name,$agent_chan,"0");
								$query = "update agent_live set agent_state=if(closer_time='-999','CLOSURE','FREE'),is_free='0'  where agent_id='$agent_id'";
								query_execute($query,$dbh,0,__LINE__);
							}
							delete $cleanDB{$agent_id};
						}
						else {
							AgentLoginBlock($agent_id,$agent_ext,$agent_session_id,$dbh,"fail","",$agent_login_time,$table_name,$agent_chan,"0");
							if($agent_ext =~ /zap/i)
							{
								$zap_channel=substr($agent_session_id,0,index($agent_session_id,"-"));
								$talking_channels="$talking_channels'$zap_channel',";
							}
						}
					}
					elsif($command_line[$agent_count]=~/ talking /)
					{
						$agent_session_id=substr($command_line[$agent_count],index($command_line[$agent_count],"session")+8);
						$agent_session_id=substr($agent_session_id,0,index($agent_session_id," "));
						my $agent_login_time=substr($command_line[$agent_count],index($command_line[$agent_count],"at ")+3);
						my @agentlogin= split(/\s+/i,$agent_login_time);
						$agent_login_time = $agentlogin[0]." ".$agentlogin[1];
						my $call_session_id=substr($command_line[$agent_count],index($command_line[$agent_count],"call_id")+8);
						$call_session_id=substr($call_session_id,0,index($call_session_id," "));
						my $phone=substr($command_line[$agent_count],index($command_line[$agent_count],"phone_no")+9);
						$phone=substr($phone,0,index($phone," "));
						my $agent_chan=substr($command_line[$agent_count],index($command_line[$agent_count],"on ")+3);
						$agent_chan=substr($agent_chan,0,index($agent_chan," "));

						if ($agent_chan =~ /Cbk_Dial/i) {
							 @test=split (/@/,$agent_chan);
							 $agent_ext=$test[0];
						}
						else
						{
							@test=split(/\s+SIP\/|\s+ZAP\//i,$command_line[$agent_count]);
							@test=split(/-[0-9a-zA-Z]+\s+/i,$test[1]);
							$agent_ext=$test[0];
						}

						my $login_chan="";
						$login_chan=substr($command_line[$agent_count],index($command_line[$agent_count],"cbkchannel")+11);
						$login_chan=substr($login_chan,0,index($login_chan," "));
						@chanarry = split (/\|/,$login_chan);
						$login_chan = (defined($chanarry[0])?$chanarry[0]:"");

						$zap_flag=0;
						$channel=substr($command_line[$agent_count],index($command_line[$agent_count],"talking")+11);
						$channel=substr($channel,0,index($channel," "));
						if($channel =~ /zap/i)
						{
								$zap_flag=1;
								@test=split(/\s+SIP\/|\s+ZAP\//i,$channel);
								@test=split(/-[0-9a-zA-Z]+\s+/i,$test[1]);
								$zap_channel=$test[0];
								$talking_channels="$talking_channels'$zap_channel',";
						}
						else {
								$sip_talking="$sip_talking'$channel',";
						}

#agent login time to be extracted
						if($cleanDB{$agent_id}) {
							if($agent_session_id != @$retval[12]) {								
								failsafeLogout ($dbh,$retval,$agent_id,$table_name,$time,'0');
								AgentLoginBlock($agent_id,$agent_ext,$agent_session_id,$dbh,"fail","",$agent_login_time,$table_name,$agent_chan,"0");
							}
							else {
								AgentLoginBlock($agent_id,$agent_ext,$agent_session_id,$dbh,"fail_safe_butdonotupdatetable","INCALL","",$table_name,$agent_chan,"0");
							}
							$query="select 4 from agent_live where session_id=$call_session_id and agent_id='$agent_id'";
							$retArray=query_execute($query,$dbh,1,__LINE__);

#call is not present in one/any of the above tables
							if(!defined(@$retArray[0]))
							{
								linkBlock($agent_id,$dbh,$call_session_id,"",$channel,$zap_flag,$phone,$res,$zap_channel,"fail","","");
							}
							delete $cleanDB{$agent_id};
						}
						else {
							$custphno="";
							AgentLoginBlock($agent_id,$agent_ext,$agent_session_id,$dbh,"fail","",$agent_login_time,$table_name,$agent_chan,"0");
							linkBlock($agent_id,$dbh,$call_session_id,"",$channel,$zap_flag,$phone,$res,$zap_channel,"fail","","");
						}
					}
				}
				$agent_count++;
			}
		}
		$start_parsing=0;

#--Delete agents from agent_live who doesn't exist in asterisk
		while(($shared_key,$value) =each(%cleanDB))
		{
            $query="select agent_state,is_paused,is_free,dialer_type,last_login_time,DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as last_login_time_table,pauseDuration,pause_time,unix_timestamp() as pause_cur_time,call_counter,last_activity_time,now(),agent_session_id,wait_duration,ready_time from agent_live where agent_id='$shared_key'";
            $retval=query_execute($query,$dbh,1,__LINE__);

            failsafeLogout($dbh,$retval,$shared_key,$table_name,$time,'0');

			$query="delete from agent_live where agent_id='$shared_key'";
			query_execute($query,$dbh,0,__LINE__);

##-----update all the agents in agentlogoff table---------------


##CRM_LIVE CHANGES
			$query="delete from crm_live where agent_id='$shared_key'";
			query_execute($query,$dbh,0,__LINE__);

			$query="delete from crm_hangup_live where agent_id='$shared_key'";
			query_execute($query,$dbh,0,__LINE__);

			delete $cleanDB{$shared_key};
		}
################################ZAPSHOWALARMS START####################################
#--To mark zap channels healthy or unhealthy based on the packet from asterisk
        $tn->buffer_empty;
		$cmd ="Action: ZapShowAlarms\n";
		@command_line = $tn->cmd(String => $cmd, Prompt => '/--END COMMAND--.*/', Errmode    => Return, Timeout  => 10);
		foreach(@command_line)
		{
			if($_ =~ /RedAlarm/) {
				$red_channels=substr($_,index($_,":") + 2);
			}
			if($_ =~ /ClearAlarm/) {
				$clear_channels=substr($_,index($_,":") + 2);
			}
		}

		if(defined($red_channels))
		{
			@n_red_channels=split(/,/,$red_channels);
			if(scalar(@n_red_channels)) {
				foreach(@n_red_channels) {
					if((defined($_) && $_ !~ /^$/ && $_ !~ /^[\s]+$/)) {
						$zap_channel="ZAP/$_";
						$query="update zap set health='1' where zap_id='$zap_channel'";
						query_execute($query,$dbh,0,__LINE__);
					}
				}
			}
		}
		if(defined($clear_channels))
		{
			@n_clear_channels=split(/,/,$clear_channels);
			if(scalar(@n_clear_channels)) {
				foreach(@n_clear_channels) {
					if((defined($_) && $_ !~ /^$/ && $_ !~ /^[\s]+$/)) {
						$zap_channel="ZAP/$_";
						$query="update zap set health='0' where zap_id='$zap_channel'";
						query_execute($query,$dbh,0,__LINE__);
					}
				}
			}
		}
################################ZAPSHOWALARMS END####################################


################################QUEUEPAUSESTATUS START####################################
#To mark agents paused in database who are paused in asterisk
# 1 to mark campaign as preview and 2 to mark as progressive. 3 will mark pause in both preview and progressive.
		my $pause_agent_list_preview="";
		my $pause_agent_list="";
		my $lastAction;
		my $agent_report_name="";
		my $pause_time;
		my $pauseTable;
		my $break_type="";
		$tn->buffer_empty;
		$cmd ="Action: QueuePauseStatus\n";
		@command_line = $tn->cmd(String => $cmd, Prompt => '/--END COMMAND--.*/', Errmode    => Return, Timeout  => 10);
		$start_parsing=0;
		$agentList="";
		my %agentPause;
		foreach(@command_line)
		{
			if(($start_parsing == 1) || ($_ =~ /will follow/))
			{
				$start_parsing=1;
				if($_ =~ /Agent/)
				{
					@arr=split(/:|,/,$_);
					$campaign_name=$arr[1];
					$campaign_name=~s/ //g;
					$agent_id=substr($arr[2],index($arr[2],"/")+1);
					$agent_id=~s/\n//g;
					if($campaign_name =~ /preview/) {
						$pause_agent_list_preview=$pause_agent_list_preview."'$agent_id',";
					}
					else {
						$pause_agent_list=$pause_agent_list."'$agent_id',";
					}

					if(!exists($agentPause{$agent_id})) {
						$agentList = $agentList."'$agent_id',";
					}
					$agentPause{$agent_id} = {$campaign_name => 1};
				}
			}
		}


		$agentList=~s/,$//g;
		if($agentList!~/^$/ && $agentList!~/^[\s]+$/) {
			my $query1="select agent_live.agent_id,agent_live.dialer_type,DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as last_login_time,agent_live.is_paused,agent_live.last_activity_time,agent_live.agent_session_id,agent.agent_name,agent_live.campaign_id,agent_live.break_type from agent,agent_live where agent.agent_id=agent_live.agent_id and agent_live.agent_id in ($agentList) and is_paused=0 and (closer_time!='-999')";

      		$fsth=$dbh->prepare($query1);
			$fsth->execute() or error_handler($DBI::errstr,__LINE__,$query1);

			my $agent_break_flag=0;
			my $pause_state =0;
			while ($retval = $fsth->fetchrow_arrayref)
			{
				$agent_id= @$retval[0];
				$dialerType=@$retval[1];
				$pause_state=@$retval[2];
				$lastAction = ((defined @$retval[4])?@$retval[4]:"$time");
				$agent_session_id=@$retval[5];
				$agent_report_name= @$retval[6];
				$campaign_id=@$retval[7];
				$break_type=((defined(@$retval[8]) && (@$retval[8] !~ /^$/ && @$retval[8] !~ /^[\s]+$/))?@$retval[8]:"Break");
				$agent_break_flag=0;

				if (not exists $campaignHash{$campaign_id}) {
					populateCampaign($campaign_id,$dbh,'0');
				}
				$campaign_name = $campaignHash{$campaign_id};

				if($dialerType =~ "PREVIEW" ) {
					if(exists($agentPause{$agent_id}->{$campaign_name})) {
						$agent_break_flag=1;
					}
					delete $agentPause{$agent_id};
				}
				else {

					if(exists($agentPause{$agent_id}->{$campaign_name})) {
						$agent_break_flag=1;
					}
					delete $agentPause{$agent_id};
				}

				if($campaign_name =~ /preview/)
				{
				   $campaign_name = substr($campaign_name,8);
				}

				if($agent_break_flag) {
					$query="update agent_live set is_paused = 1,pause_time=unix_timestamp(),last_activity_time=now() where agent_id='$agent_id' and agent_state!='INCALL' ";
					query_execute($query,$dbh,0,__LINE__);

					$query="insert into agent_state_analysis_$table_name (node_id,agent_id,campaign_id,agent_state,call_start_date_time,agent_session_id,agent_name,campaign_name,dailer_mode,break_type,entrytime) values('$node_id','$agent_id','$campaign_id','BREAK','$lastAction','$agent_session_id','$agent_report_name','$campaign_name','$dialerType','$break_type',unix_timestamp())";
					query_execute($query,$dbh,0,__LINE__);

#Adding information to Agent State Analysis current report
					$query =~ s/$table_name/current_report/i;
					query_execute($query,$dbh,0,__LINE__);
				}

			}
			$fsth->finish;
		}


#----All the agents who are in progressive mode and are not in Break mark them free-------------
		$pause_agent_list=~s/,$//g;

		$query="select agent_id,last_activity_time,DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as pause_time,break_type from agent_live where is_paused='1' and agent_in_conf='0' and dialer_type!='PREVIEW' ".(($pause_agent_list!~/^$/ && $pause_agent_list!~/^[\s]+$/)?"and agent_id not in ($pause_agent_list)":"");
		$fsth=$dbh->prepare($query);
		$fsth->execute() or error_handler($DBI::errstr,__LINE__,$query);
		while (my $retval = $fsth->fetchrow_arrayref)
		{
			$agent_id = @$retval[0];
			$pause_time = @$retval[1];
			$pauseTable=((defined @$retval[2]) && (@$retval[2] ne '0000_00')?@$retval[2]:"$table_name");
			$break_type=((defined(@$retval[3]) && (@$retval[3] !~ /^$/ && @$retval[3] !~ /^[\s]+$/))?@$retval[3]:"Break");

			if(@$retval[0]!~/^$/ && @$retval[0]!~/^[\s]+$/) {
				$query="update agent_live set pauseDuration=pauseDuration + (unix_timestamp() - if(pause_time>0,pause_time,unix_timestamp())),is_paused='0',pause_time='0',last_activity_time=now() where agent_id='$agent_id'";
				query_execute($query,$dbh,0,__LINE__);

				$query="update agent_state_analysis_$pauseTable set agent_state='BREAK_N_BACK',call_end_date_time='$pause_time',break_type='$break_type' where agent_id='$agent_id' and agent_state='BREAK'";
				query_execute($query,$dbh,0,__LINE__);

#Adding information to Agent State Analysis current report
				$query =~ s/$pauseTable/current_report/i;
				query_execute($query,$dbh,0,__LINE__);
			}
		}
		$fsth->finish;

#----All the agents who are in preview mode and are not in Break mark them free-------------
		$pause_agent_list_preview=~s/,$//g;
		$query="select agent_id,last_activity_time,DATE_FORMAT(from_unixtime(substring_index(agent_session_id,'.',1)),'%Y_%m') as pause_time from agent_live where is_paused='1' and dialer_type='PREVIEW' ".(($pause_agent_list_preview!~/^$/ && $pause_agent_list_preview!~/^[\s]+$/)?"and agent_id not in ($pause_agent_list_preview)":"");
		$fsth=$dbh->prepare($query);
		$fsth->execute() or error_handler($DBI::errstr,__LINE__,$query);
		while (my $retval = $fsth->fetchrow_arrayref)
		{
			$agent_id = @$retval[0];
			$pause_time = @$retval[1];
			$pauseTable=((defined @$retval[2]) && (@$retval[2] ne '0000_00')?@$retval[2]:"$table_name");

			if(@$retval[0]!~/^$/ && @$retval[0]!~/^[\s]+$/) {
				$query="update agent_live set pauseDuration=pauseDuration + (unix_timestamp() - if(pause_time>0,pause_time,unix_timestamp())),is_paused='0',pause_time='0',last_activity_time=now() where agent_id='$agent_id'";
				query_execute($query,$dbh,0,__LINE__);

				$query="update agent_state_analysis_$pauseTable set agent_state='BREAK_N_BACK',call_end_date_time='$pause_time' where agent_id='$agent_id' and agent_state='BREAK'";
				query_execute($query,$dbh,0,__LINE__);

#Adding information to Agent State Analysis current report
				$query =~ s/$pauseTable/current_report/i;
				query_execute($query,$dbh,0,__LINE__);
			}
		}
		$fsth->finish;


		$start_parsing=0;
################################QUEUEPAUSESTATUS END####################################

################################QUEUESETMEFREESTATUS START####################################
#to mark agents paused in database who are not in wrapimg state in asterisk
        $tn->buffer_empty;
		$cmd ="Action: QueueSetMeFree\n";
		@command_line = $tn->cmd(String => $cmd, Prompt => '/--END COMMAND--.*/', Errmode    => Return, Timeout  => 10);
		my $setmefree;
		my %agentFree;
		my $agent_state;
		$start_parsing=0;
		$agentList="";
		foreach(@command_line)
		{
			if(($start_parsing == 1) || ($_ =~ /will follow/))
			{
				$start_parsing=1;
				if($_ =~ /Agent/)
				{
					@arr=split(/:|,/,$_);
					$campaign_name=$arr[1];
					$campaign_name=~s/ //g;
					$agent_id=substr($arr[2],index($arr[2],"/")+1);
					$agent_id=~s/\n//g;
					$setmefree=$arr[3];
					$setmefree=~s/ //g;
					$session_id=$arr[4];
					$session_id=~s/\n//g;
					$session_id=~s/ //g;

					$agentFree{$agent_id} = $session_id;
					$agentList = $agentList."'$agent_id',";

				}
			}
		}
		$agentList=~s/,$//g;

        if($agentList!~/^$/ && $agentList!~/^[\s]+$/) {
                $query="select agent_id,agent_state from agent_live where agent_id in ($agentList)";
                $fsth=$dbh->prepare($query);
                $fsth->execute() or error_handler($DBI::errstr,__LINE__,$query);
                while (my $retval = $fsth->fetchrow_arrayref)
                {
                        $agent_id=@$retval[0];
                        $agent_state=@$retval[1];

					   if ($agent_state eq "FREE")
						{
								$query="update agent_live set is_free = 1,session_id=".$agentFree{$agent_id}.",agent_state ='CLOSURE',last_activity_time=now() where agent_id='$agent_id'";
						}
						else
						{
								$query="update agent_live set is_free = 1,closer_time=if(closer_time='-999' ,'0',closer_time),session_id=".$agentFree{$agent_id}." where agent_id='$agent_id'";
						}
						query_execute($query,$dbh,0,__LINE__);
                }
                $fsth->finish();

                if(defined($agentList) && ($agentList !~ /^$/ && $agentList !~ /^[\s]+$/)) {
                        $query="update agent_live set is_free=0,agent_state='FREE' where agent_id not in ($agentList) and closer_time!='-999'";
                        query_execute($query,$dbh,0,__LINE__);
                }
                else {
                        $query="update agent_live set is_free=0,agent_state='FREE'";
                        query_execute($query,$dbh,0,__LINE__);
                }
        }
		$start_parsing=0;
################################QUEUESETMEFREESTATUS STOP####################################

#to sync the zap table with asterisk
		chop $talking_channels;
		$talking_channels="$talking_channels)";
		if($talking_channels =~ /Zap/i)
		{
			$query="update zap set status='FREE',session_id='0.000000',flow_state='0' where zap_id not in $talking_channels and status <> 'NOTINUSE'";
			query_execute($query,$dbh,0,__LINE__);
		}
		else
		{
			$query="update zap set status='FREE',session_id='0.0000000',flow_state='0' where status <> 'NOTINUSE'";
			query_execute($query,$dbh,0,__LINE__);
		}

		chop $sip_talking;
		$sip_talking="$sip_talking)";

		if(length($sip_talking)<=2) #no sip channel is talking
		{
			$query="update sip set status='FREE',session_id='0.0000000',flow_state='0'";
			query_execute($query,$dbh,0,__LINE__);
		}
		else
		{
			$query="update sip set status='FREE',session_id='0.0000000',flow_state='0' where session_id not in $sip_talking";
			query_execute($query,$dbh,0,__LINE__);
		}


		$query="delete from call_dial_status where session_id not in (select session_id from customer_live)";
		query_execute($query,$dbh,0,__LINE__);

		$query="delete from missed_call_status where session_id not in (select session_id from customer_live)";
		query_execute($query,$dbh,0,__LINE__);
	}
##################FILE GLOBAL FLAG END ###########################################################

#-----------Infinite Loop---------------
	while (1)
	{
		$current_date = substr(get_time_now(),0,10);
		if($file_global_flag == 1 || $dialing_date ne $current_date)
		{
#initialize listener status table with current date
			$query="select distinct(list_id) from listener_status where dialing_date <> curdate()";
			$fsth=$dbh->prepare($query);
			$fsth->execute() or error_handler($DBI::errstr,__LINE__,$query);

			while (my $list_id = $fsth->fetchrow_arrayref)
			{
				$retval = "";
				$query="select 1 from listener_status where list_id='@$list_id[0]' and dialing_date = curdate()";
				$retval=query_execute($query,$dbh,1,__LINE__);
				if(!@$retval[0])
				{
					$query = "insert into listener_status (list_id,dialing_date) values ('@$list_id[0]',curdate())";
					query_execute($query,$dbh,0,__LINE__);
				}
			}
			$fsth->finish();

			$query = "delete from listener_status where unix_timestamp() - unix_timestamp(dialing_date) > 172800";
			query_execute($query,$dbh,0,__LINE__);

			if(!$file_global_flag) {
				$dialing_date = $current_date;
			}
#---Check for table existence-------------
			$time = get_time_now();
			$table_name=substr($time,0,7);
			$table_name=~s/-/_/g;
			checkTables($dbh,$table_name);
			undef $table_name;
		}
		$time=time;

#to delete entries from current_report table and crrent_report agents table which are two days older
		if($time - $currentReportTime >= 172800)
		{
			$query = "delete from current_report where date(call_start_date_time) < addDate(date(now()),-1)";
			query_execute($query,$dbh,0,__LINE__);

			$query = "delete from agent_state_analysis_current_report where date(call_start_date_time) < addDate(date(now()),-1)";
			query_execute($query,$dbh,0,__LINE__);

			$query = "delete from cdr_current_report where date(calldate) < addDate(date(now()),-1)";
			query_execute($query,$dbh,0,__LINE__);

#<TVT> ivr_report_current_report missing here.
			$query = "delete from ivr_report_current_report where date(link_date_time) < addDate(date(now()),-1)";
			query_execute($query,$dbh,0,__LINE__);

			$query = "delete from feedback_current_report where date(call_start_date_time) < addDate(date(now()),-1)";
			query_execute($query,$dbh,0,__LINE__);

			$query = "delete from misscall_current_report where date(miss_call_time) < addDate(date(now()),-1)";
			query_execute($query,$dbh,0,__LINE__);

			$query = "delete from escalation_current_report where date(entrytime) < addDate(date(now()),-1)";
			query_execute($query,$dbh,0,__LINE__);

			$query = "delete from voicemail_current_report where date(vmail_orig_time) < addDate(date(now()),-1)";
            query_execute($query,$dbh,0,__LINE__);

			$currentReportTime = $time;
		}
#to delete entries from hash which are half an hour old, ie garbage calls
		if($time - $last_updated_time >= 1800)
		{
			$last_updated_time = $time;

#do not delete the session which is still live, doesn't matter whether it is half an hour old or N minutes old, if it is live then do not delete it otherwise agentui will not be able to disconnect the call.
			%customer_live_session_hash=();
			$query="select session_id from customer_live";
			$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
			while (my $customer_session_id = $sth->fetchrow_arrayref)
			{
				$customer_live_session_hash{@$customer_session_id[0]}=1;
			}
			$sth->finish();

			while(($shared_key) =each(%stateHash))
			{
				if($time - $shared_key >= 1800)
				{
#do not delete the session which is still live, doesn't matter whether it is half an hour old or N minutes old, if it is live then do not delete it otherwise agentui will not be able to disconnect the call.
					if((not exists $customer_live_session_hash{$shared_key}))
					{
						delete $stateHash{$shared_key};
					}
				}
			}
		}
		$retval="";
		if(!$dbh->ping)
		{
			$dbh=DBI->connect("dbi:mysql:$db:$server",$username,$password) or die (exit );
		}

		$time=time;

#######################START ALL THREADS FROM FAIL SAFE###########
		for($i=0; $i < scalar @thread_type; $i++)
		{
			if(!defined($threadStatusHash{$i}))
			{
				$thread_semaphore->down;
				$threadStatusHash{$i}=$time;
				$thread_semaphore->up;
				if($i == 0)
				{
					$thread_id[$i]=threads->new(\&sendTelnetCommand);
					$thread_id[$i]->detach;
				}
				else
				{
					$thread_id[$i]=threads->new(\&parser,$i,$thread_type[$i]);
					$thread_id[$i]->detach;
				}
			}
			elsif(($time - $threadStatusHash{$i}) > $limit)
			{
				error_handler("thread $time ===  $limit == ".$threadStatusHash{$i}." ===== id $i has died",__LINE__,$query);
				$thread_semaphore->down;
				$threadStatusHash{$i}=$time;
				$thread_semaphore->up;
				if($i == 0)
				{
					$thread_id[$i]=threads->new(\&sendTelnetCommand);
					$thread_id[$i]->detach;
				}
				else
				{
					$thread_id[$i]=threads->new(\&parser,$i,$thread_type[$i]);
					$thread_id[$i]->detach;
				}
				error_handler("thread id $i has started",__LINE__,$query);
			}
		}
 
         #print Dumper(\%agentcount);
		#print Dumper(\%logoutagent);
		foreach $key (keys %logoutagent) {
            if($time >= $logoutagent{$key})
			{
				if(exists($logoutagent{$key})) {
				   ontimelogout($dbh,$key);
				}
			}
		}
#---THREADS STARTED-------

		closer_check($dbh,$tn);
### sleep for 1 second(s)
		usleep(1000000);
	}
##-----------Infinite Loop End---------------

	$dbh->disconnect();
	$tn->cmd(String => "Action: Logoff\n\n", Prompt => "/.*/", Errmode => Return, Timeout =>1);
	$tn->buffer_empty;
	$tn->close;
	undef($tn);
	undef($dbh);
}
#---FAIL SAFE END--------------

###########################################################################################

sub ontimelogout
{
	my @params = @_;
	my $dbh = $params[0];
	my $campaign_id = $params[1];
	my $shared_key="";
	my $query="";
	my $osth;
    my $retval;

	$query="select agent_id from agent_live where campaign_id='$campaign_id' and agent_state!='INCALL'";
	$osth=$dbh->prepare($query);
	$osth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while (my $agent_id = $osth->fetchrow_arrayref) {
		$shared_key = @$agent_id[0];
		$sendTn_semaphore->down;
		$sendTnHash{$shared_key} = "agentlogoff";
		$sendTn_semaphore->up;

		$query="update agent set logout_reason='Campaign Time Exceed' where agent_id='@$agent_id[0]'";
        query_execute($query,$dbh,0,__LINE__);
	}
	$osth->finish();

	$query="select 1 from agent_live where campaign_id='$campaign_id' and agent_state='INCALL'";
	$retval=query_execute($query,$dbh,1,__LINE__);
	 if(!@$retval[0])
	 {
	   $logoutagent_semaphore->down;
	   delete $logoutagent{$campaign_id};
	   $logoutagent_semaphore->up;
	 }

}
############################################################################

##################SUB logoutupdate##########################################
sub logoutupdate
{
	my $retValArray;
	my $logval;
	my $loginTable="";
	my @params = @_;
	my $agent_id = $params[0];
	my $call_start_time = $params[1];
	my $logoff_time = $params[2];
	$logoff_time=(defined($logoff_time)?$logoff_time:"unix_timestamp()");
	my $agent_session_id = $params[3];
	my $dbh = $params[4];
	my $campaign_id=$params[5];
	my $previewDuration='0';
	my $preview_pauseDuration='0';
	my $pauseDuration='0';
	my $ready_time=2;
	my $query="";
	my $retval="";
	my $returnvar="";
	my $dialerType="";

	if ( @{$final_wrap_array[$agent_id][0]}) {
		splice(@final_wrap_array,$agent_id,1);
	}

	if(defined($agent_session_id) && ($agent_session_id !~ /^$/ && $agent_session_id !~ /^[\s]+$/))
	{
		$query = "select DATE_FORMAT(from_unixtime(substring_index($agent_session_id,'.',1)),'%Y_%m') as loginTable,unix_timestamp() as curr_time";
		$retval = query_execute($query,$dbh,1,__LINE__);
		if($retval) {
			$loginTable = @$retval[0];
			$logoff_time = @$retval[1];
		}
	}

	$wrapup_semaphore->down;
	delete $agent_wrapup{$agent_id};        #delete element from hash
	delete $call_duration_array1[$agent_id];
	delete $call_duration_array2[$agent_id];
	delete $call_duration_array3[$agent_id];
	delete $update_avg_block1[$agent_id];   #delete element from UAB array
	delete $update_avg_block2[$agent_id];
	delete $update_avg_block3[$agent_id];
	delete $predict_state_after1[$agent_id];
	delete $predict_state_after2[$agent_id];
	delete $predict_state_after3[$agent_id];
	delete $state_changed[$agent_id];
	$wrapup_semaphore->up;

	$query ="select count(*) from current_report where agent_id='$agent_id' and entrytime between '$call_start_time' and '$logoff_time'";
	$retValArray=query_execute($query,$dbh,1,__LINE__);
	my $totalCalls = @$retValArray[0];

	$query="select dialerType from campaign where campaign_id='$campaign_id'";
	$returnvar=query_execute($query,$dbh,1,__LINE__);
	$dialerType = @$returnvar[0];

	$query="select sum(unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time)) as conf_duration from current_report where agent_id = '$agent_id' and entrytime between '$call_start_time' and '$logoff_time'  and  agent_id = cust_ph_no";
	$logval=query_execute($query,$dbh,1,__LINE__);
	my $confDuration = ((defined @$logval[0])?@$logval[0]:"0");

	$query="update agent_state_analysis_$loginTable set agent_state='BREAK_N_BACK',call_end_date_time=from_unixtime('$logoff_time') where agent_id='$agent_id' and agent_state='BREAK' and agent_session_id=$agent_session_id";
	query_execute($query,$dbh,0,__LINE__);

	check_cview($query,$dbh,$loginTable,2);
	$query =~ s/$loginTable/current_report/i;
	query_execute($query,$dbh,0,__LINE__);

	$query="update agent_state_analysis_$loginTable set agent_state='PREVIEW_N_$dialerType',call_end_date_time=from_unixtime('$logoff_time') where agent_id='$agent_id' and agent_state='PREVIEW' and agent_session_id=$agent_session_id";
	query_execute($query,$dbh,0,__LINE__);

	check_cview($query,$dbh,$loginTable,2);
	$query =~ s/$loginTable/current_report/i;
	query_execute($query,$dbh,0,__LINE__);

	$query ="select sum(unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time)) as pauseDuration,sum(if(dailer_mode='PREVIEW',unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time),0 )) as preview_pause_duraiton from agent_state_analysis_current_report where agent_id='$agent_id' and break_type not in ('JoinedConference') and agent_state='BREAK_N_BACK'".(($agent_session_id =~ /^$/ || $agent_session_id =~ /^[\s]+$/)?" and entrytime between '$call_start_time' and '$logoff_time'":"")." and agent_session_id=$agent_session_id" ;
	$logval=query_execute($query,$dbh,1,__LINE__);
	$pauseDuration = ((defined @$logval[0])?@$logval[0]:"0");
	$preview_pauseDuration = ((defined @$logval[1])?@$logval[1]:"0");


	$query ="select sum(unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time)) as previewDuration from agent_state_analysis_current_report where agent_id='$agent_id'  and (agent_state='PREVIEW_N_PROGRESSIVE' or agent_state='PREVIEW_N_PREDICTIVE')".(($agent_session_id =~ /^$/ || $agent_session_id =~ /^[\s]+$/)?" and entrytime between '$call_start_time' and '$logoff_time'":"")." and agent_session_id=$agent_session_id" ;
	$logval=query_execute($query,$dbh,1,__LINE__);
	$previewDuration = ((defined @$logval[0])?@$logval[0]:"0");

	$query="update agent_state_analysis_$loginTable set agent_state='LOGIN_N_LOGOUT',call_end_date_time=from_unixtime('$logoff_time'),pauseDuration='$pauseDuration',totalCall='$totalCalls',conf_duration = '$confDuration',preview_pauseDuration='$preview_pauseDuration',preview_time='$previewDuration',ready_time='$ready_time' where agent_id='$agent_id' and agent_state='LOGIN' and agent_session_id=$agent_session_id";
	query_execute($query,$dbh,0,__LINE__);

	check_cview($query,$dbh,$loginTable,2);
	$query =~ s/$loginTable/current_report/i;
	query_execute($query,$dbh,0,__LINE__);
}
###########################################################################################

##################CLOSER CHECK START#######################################################
sub closer_check()
{
	my @params = @_;
	my $dbh=$params[0];
	my $tn=$params[1];
	my $query;
	my $sth;
	my $update_sth;
	my $cur_time=time;
	my $shared_key;
	my $values;
	my $agent_id;
	my $weighted_avg=0;
	my $i=0;
	my $length=0;
	my $call_duration=-999;
	my $block_avg=1;
	my $current_total_calls=0;
	my $current_total_wrapup=0;

	while(($agent_id,$values) =each(%agent_wrapup))
	{
		my @tmp_arr=();
		my $ncalls=0;
		my $total_calls=0;
		my $total_wrapup=0;
		@tmp_arr=split(",",$agent_wrapup{$agent_id});
		#print"===myissue==$agent_id====$tmp_arr[6]====\n";
#print @tmp_arr;print "--------$tmp_arr[6]----$tmp_arr[8]--===========".$agent_id;print "\n";
		$call_duration=abs ($tmp_arr[6]-$tmp_arr[8]);
#if wrap up time is infinite
		if(($tmp_arr[0] eq "PREDICTIVE"))
		{
			if(($tmp_arr[3] eq $INFINITE_WRAPUP_TIME))
			{
##################################CALL DURATION < 300 START############################
				if(($call_duration <= $FIVE_MINUTES) && ($call_duration >= 0) && ($tmp_arr[5] ne "FREE"))
				{
					$wrapup_semaphore->down;
					my @cda=split(",",$call_duration_array1[$agent_id]);
					$current_total_calls=$cda[0];
					$current_total_wrapup=$cda[1];
					$total_calls=$cda[2];
					$total_wrapup=$cda[3];
					undef(@cda);
					$wrapup_semaphore->up;
					if($current_total_calls==0){$current_total_calls=1;}
					if($current_total_wrapup==0){$current_total_wrapup=1;}
					if($total_calls==0){$total_calls=1;}
					if($total_wrapup==0){$total_wrapup=1;}
					$ncalls=$total_calls % $AVG_BLOCK;  #to make the blocks of 5 calls each
					$block_avg=int($current_total_wrapup/$current_total_calls);
					if(($ncalls==0) && ($total_calls >= $AVG_BLOCK) && ((defined($update_avg_block1[$agent_id]) && $update_avg_block1[$agent_id]!=$total_calls)))
					{
						if($total_calls<=$PREDICTION_CALLS)
						{
							unshift(@{$final_wrap_array[$agent_id][0]},$block_avg);
						}
						if($total_calls>=$PREDICTION_CALLS)
						{
#before popping the array calculate the weighted average that will be used for next four calls
#$weighted_avg=(w1*a1+w2*a2+w3*a3+w4*a4+w5*a5)/w1+w2+w3+w4+w5;
							$length=@{$final_wrap_array[$agent_id][0]};
							for($i=0;$i<$length;$i++)
							{
								$weighted_avg+=($weight_array[$i]*$final_wrap_array[$agent_id][0][$i]);
							}
							$wrapup_semaphore->down;
							$predict_state_after1[$agent_id]=$weighted_avg/$weight_sum;
							$wrapup_semaphore->up;

							pop(@{$final_wrap_array[$agent_id][0]});
							unshift(@{$final_wrap_array[$agent_id][0]},$block_avg);
						}
						$wrapup_semaphore->down;
						$update_avg_block1[$agent_id]=$total_calls;
						$wrapup_semaphore->up;
					}
#if no of calls taken is >= 25 and agent is sitting idle from more than average seconds,
#then keep agent on  READY->CLOSURE->READY after the average time until he clicks on
#disconnect button,
					if(($total_calls >= $PREDICTION_CALLS) &&
							((defined($predict_state_after1[$agent_id]) && ($predict_state_after1[$agent_id] > $WATERMARK_FOR_PREDICTION) && ($cur_time - $tmp_arr[7]) >= ($predict_state_after1[$agent_id]-$WATERMARK_FOR_PREDICTION)) &&
							 ($tmp_arr[5] eq "CLOSURE") && ($state_changed[$agent_id]!=1)))
					{
						$query="update agent_live set agent_state='READY',last_activity_time=now() where agent_id='$agent_id' and agent_state = 'CLOSURE'";
						query_execute($query,$dbh,0,__LINE__);

						$wrapup_semaphore->down;
						$state_changed[$agent_id]=1;
						$tmp_arr[5]="READY";
						$tmp_arr[7]=$cur_time;
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
						$wrapup_semaphore->up;
					}
#keep the agent on READY state for 15 seconds, then again move to CLOSURE if call not
#disconnected by Agent.
					elsif(($tmp_arr[5] eq "READY") && ($cur_time > $tmp_arr[7]) && (($cur_time - $tmp_arr[7])>=$WATERMARK_FOR_PREDICTION))
					{
						$query="update agent_live set agent_state='CLOSURE',last_activity_time=now() where agent_id='$agent_id' and agent_state='READY'";
						query_execute($query,$dbh,0,__LINE__);

						$wrapup_semaphore->down;
						$tmp_arr[5]="CLOSURE";
						$tmp_arr[7]=$cur_time;
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
						$wrapup_semaphore->up;
					}
				}
##################################CALL DURATION < 300 END############################

##################################CALL DURATION 300-600 START############################
				elsif(($call_duration > $FIVE_MINUTES) && ($call_duration <= $TEN_MINUTES) && ($tmp_arr[5] ne "FREE"))
				{
					$wrapup_semaphore->down;
					my @cda=split(",",$call_duration_array2[$agent_id]);
					$current_total_calls=$cda[0];
					$current_total_wrapup=$cda[1];
					$total_calls=$cda[2];
					$total_wrapup=$cda[3];
					undef(@cda);
					$wrapup_semaphore->up;
					if($current_total_calls==0){$current_total_calls=1;}
					if($current_total_wrapup==0){$current_total_wrapup=1;}
					if($total_calls==0){$total_calls=1;}
					if($total_wrapup==0){$total_wrapup=1;}
					$ncalls=$total_calls % $AVG_BLOCK;  #to make the blocks of 5 calls each
						$block_avg=int($current_total_wrapup/$current_total_calls);
					if(($ncalls==0) && ($total_calls >= $AVG_BLOCK) && ((defined($update_avg_block2[$agent_id]) && $update_avg_block2[$agent_id]!=$total_calls)))
					{
						if($total_calls<=$PREDICTION_CALLS)
						{
							unshift(@{$final_wrap_array[$agent_id][1]},$block_avg);
						}
						if($total_calls>=$PREDICTION_CALLS)
						{
#before popping the array calculate the weighted average that will be used for next four calls
#$weighted_avg=(w1*a1+w2*a2+w3*a3+w4*a4+w5*a5)/w1+w2+w3+w4+w5;
							$length=@{$final_wrap_array[$agent_id][1]};
							for($i=0;$i<$length;$i++)
							{
								$weighted_avg+=($weight_array[$i]*$final_wrap_array[$agent_id][1][$i]);
							}
							$wrapup_semaphore->down;
							$predict_state_after2[$agent_id]=$weighted_avg/$weight_sum;
							$wrapup_semaphore->up;

							pop(@{$final_wrap_array[$agent_id][1]});
							unshift(@{$final_wrap_array[$agent_id][1]},$block_avg);
						}
						$wrapup_semaphore->down;
						$update_avg_block2[$agent_id]=$total_calls;
						$wrapup_semaphore->up;
					}

#if no of calls taken is >= 25 and agent is sitting idle from more than average seconds,
#then keep agent on  READY->CLOSURE->READY after the average time until he clicks on
#disconnect button,
                    if(($total_calls >= $PREDICTION_CALLS) && ((defined($predict_state_after2[$agent_id]) && ($predict_state_after2[$agent_id] > $WATERMARK_FOR_PREDICTION) && ($cur_time - $tmp_arr[7]) >= ($predict_state_after2[$agent_id]-$WATERMARK_FOR_PREDICTION)) && ($tmp_arr[5] eq "CLOSURE") && ($state_changed[$agent_id]!=1)))
					{
						$query="update agent_live set agent_state='READY',last_activity_time=now() where agent_id='$agent_id' and agent_state='CLOSURE'";
						query_execute($query,$dbh,0,__LINE__);

						$wrapup_semaphore->down;
						$state_changed[$agent_id]=1;
						$tmp_arr[5]="READY";
						$tmp_arr[7]=$cur_time;
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
						$wrapup_semaphore->up;
					}
#keep the agent on READY state for 15 seconds, then again move to CLOSURE if call not
#disconnected by Agent.
					elsif(($tmp_arr[5] eq "READY") && ($cur_time > $tmp_arr[7]) && (($cur_time - $tmp_arr[7])>=$WATERMARK_FOR_PREDICTION))
					{
						$query="update agent_live set agent_state='CLOSURE',last_activity_time=now() where agent_id='$agent_id' and agent_state='READY'";
						query_execute($query,$dbh,0,__LINE__);

						$wrapup_semaphore->down;
						$tmp_arr[5]="CLOSURE";
						$tmp_arr[7]=$cur_time;
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
						$wrapup_semaphore->up;
					}
				}
##################################CALL DURATION 300-600 END############################

##################################CALL DURATION > 600 START############################
				elsif(($call_duration >  $TEN_MINUTES) && ($tmp_arr[5] ne "FREE"))
				{
					$wrapup_semaphore->down;
					my @cda=split(",",$call_duration_array3[$agent_id]);
					$current_total_calls=$cda[0];
					$current_total_wrapup=$cda[1];
					$total_calls=$cda[2];
					$total_wrapup=$cda[3];
					undef(@cda);
					$wrapup_semaphore->up;
					if($current_total_calls==0){$current_total_calls=1;}
					if($current_total_wrapup==0){$current_total_wrapup=1;}
					if($total_calls==0){$total_calls=1;}
					if($total_wrapup==0){$total_wrapup=1;}
					$ncalls=$total_calls % $AVG_BLOCK;  #to make the blocks of 5 calls each
					$block_avg=int($current_total_wrapup/$current_total_calls);
					if(($ncalls==0) && ($total_calls >= $AVG_BLOCK) && ((defined($update_avg_block3[$agent_id]) && $update_avg_block3[$agent_id]!=$total_calls)))
					{
						if($total_calls<=$PREDICTION_CALLS)
						{
							unshift(@{$final_wrap_array[$agent_id][2]},$block_avg);
						}
						if($total_calls>=$PREDICTION_CALLS)
						{
#before popping the array calculate the weighted average that will be used for next four calls
#$weighted_avg=(w1*a1+w2*a2+w3*a3+w4*a4+w5*a5)/w1+w2+w3+w4+w5;
							$length=@{$final_wrap_array[$agent_id][2]};
							for($i=0;$i<$length;$i++)
							{
								$weighted_avg+=($weight_array[$i]*$final_wrap_array[$agent_id][2][$i]);
							}
							$wrapup_semaphore->down;
							$predict_state_after2[$agent_id]=$weighted_avg/$weight_sum;
							$wrapup_semaphore->up;

							pop(@{$final_wrap_array[$agent_id][2]});
							unshift(@{$final_wrap_array[$agent_id][2]},$block_avg);
						}
						$wrapup_semaphore->down;
						$update_avg_block3[$agent_id]=$total_calls;
						$wrapup_semaphore->up;
					}
#if no of calls taken is >= 25 and agent is sitting idle from more than average seconds,
#then keep agent on  READY->CLOSURE->READY after the average time until he clicks on
#disconnect button,
					if(($total_calls >= $PREDICTION_CALLS) && ((defined($predict_state_after3[$agent_id]) && ($predict_state_after3[$agent_id] > $WATERMARK_FOR_PREDICTION) && ($cur_time - $tmp_arr[7]) >= ($predict_state_after3[$agent_id]-$WATERMARK_FOR_PREDICTION)) && ($tmp_arr[5] eq "CLOSURE") && ($state_changed[$agent_id]!=1)))
					{
						$query="update agent_live set agent_state='READY',last_activity_time=now() where agent_id='$agent_id' and agent_state='CLOSURE'";
						query_execute($query,$dbh,0,__LINE__);

						$wrapup_semaphore->down;
						$state_changed[$agent_id]=1;
						$tmp_arr[5]="READY";
						$tmp_arr[7]=$cur_time;
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
						$wrapup_semaphore->up;
					}
#keep the agent on READY state for 15 seconds, then again move to CLOSURE if call not
#disconnected by Agent.
					elsif(($tmp_arr[5] eq "READY") && ($cur_time > $tmp_arr[7]) && (($cur_time - $tmp_arr[7])>=$WATERMARK_FOR_PREDICTION))
					{
						$query="update agent_live set agent_state='CLOSURE',last_activity_time=now() where agent_id='$agent_id' and agent_state='READY'";
						query_execute($query,$dbh,0,__LINE__);

						$wrapup_semaphore->down;
						$tmp_arr[5]="CLOSURE";
						$tmp_arr[7]=$cur_time;
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
						$wrapup_semaphore->up;
					}
				}
#---CALL DURATION > 600 END-----------
			}
			else
			{
#finite wrapup case, make agent free after ready state
				if(($tmp_arr[5] eq "READY" || $tmp_arr[5] eq "CLOSURE") && ($tmp_arr[6] ne "-999"))
				{
					if(($cur_time - $tmp_arr[6]) >= $tmp_arr[3])
					{
#Let us not free an agent whose set me free is already set.
						$query="update agent_live set agent_state='FREE',closer_time=0, lead_id='0',last_activity_time=now(),is_free='0' where agent_id='$agent_id' and agent_state in ('CLOSURE','READY') and is_free='1'";
						query_execute($query,$dbh,0,__LINE__);
						$sendTn_semaphore->down;
						$sendTnHash{$agent_id} = "tellAgentStatus";
						$sendTn_semaphore->up;

						$wrapup_semaphore->down;
						$tmp_arr[5]="FREE";
						$agent_wrapup{$agent_id}=join(",",@tmp_arr);
						$wrapup_semaphore->up;
					}
				}
#finite wrapup case, make agent ready after 15 seconds of call disconnection
				if(($tmp_arr[3]>15) && (($cur_time-$tmp_arr[6])>=($tmp_arr[3]-15)) && ($tmp_arr[6] ne "-999") && ($tmp_arr[5] eq "CLOSURE")) {
#set the state to READY
					$query="update agent_live set agent_state='READY',last_activity_time=now() where agent_id='$agent_id' and agent_state ='CLOSURE'";
					query_execute($query,$dbh,0,__LINE__);
					$wrapup_semaphore->down;
					$tmp_arr[5]="READY";
					$agent_wrapup{$agent_id}=join(",",@tmp_arr);
					$wrapup_semaphore->up;
				}
			}
		}
		elsif ($tmp_arr[0] eq "PROGRESSIVE") {
#print "-A-$tmp_arr[5]-B--$tmp_arr[3]-C--$tmp_arr[6]\n";
			if($tmp_arr[5] eq "READY" || $tmp_arr[5] eq "CLOSURE") {
				if((($cur_time-$tmp_arr[6])>=($tmp_arr[3])) && ($tmp_arr[6] ne "-999") && ($tmp_arr[3] ne $INFINITE_WRAPUP_TIME)) {
#set the state to FREE
#$query="update agent_live set agent_state='FREE',last_activity_time=now() where agent_id='$agent_id' and agent_state ='CLOSURE'";
					$query="update agent_live set agent_state='FREE',closer_time=0, lead_id='0',last_activity_time=now(),is_free='0' where agent_id='$agent_id' and agent_state in ('CLOSURE') and is_free='1'";
					query_execute($query,$dbh,0,__LINE__);
					$wrapup_semaphore->down;
					$tmp_arr[5]="FREE";
					$agent_wrapup{$agent_id}=join(",",@tmp_arr);
					$wrapup_semaphore->up;
				}
			}
		}
		undef(@tmp_arr);
	}
	return 1;
}
#----CLOSER CHECK END-----------------


#---sendTelnetCommand START----------
sub sendTelnetCommand
{
	my $tnet;
	$tnet = new Net::Telnet(Timeout=>10,Prompt=>'/%/',Host=>"localhost",Port=>"5038");
	$tnet->waitfor('/0\n$/');
	$tnet->print("Action: Login\nUsername: $telnet_username\nSecret: $telnet_secret\nEvents: Off\n");
	$tnet->waitfor('/Authentication accepted/');
	$tnet->buffer_empty;

	my $agent_id;
	my $campaign_name;
	my $option;
	my $channel;
	my $agent_exten;
    my $priority;
	my $cmd="";
	my $time=0;
	my $last_updated_time=0;
	my @tmp_arr_agent=();

	while(1)
	{
		$time=time;
#to ping the telnet after 5 minutes
		if(($time - $last_updated_time) >= 300)
		{
			my @tmp;
			$last_updated_time = $time;
			@tmp = $tnet->cmd(String =>"Action: ping\n", Prompt => '/--END COMMAND--.*/', Errmode    => Return, Timeout  => 1);
			undef(@tmp);
		}
		$thread_semaphore->down;
		$threadStatusHash{0}=$time;
		$thread_semaphore->up;
		while(($agent_id,$option) =each(%sendTnHash))
		{
			@tmp_arr_agent=split("##",$agent_id);
			$agent_id = $tmp_arr_agent[0];
			$campaign_name = $tmp_arr_agent[1];
			$channel = $tmp_arr_agent[2];
			$agent_exten = $tmp_arr_agent[3];
			$priority = $tmp_arr_agent[4];
#read the hash and parse it to get the command, delete the key after execution of command
			if($option eq "agentlogoff")
			{
				$cmd = "Action: command\ncommand: agent logoff agent/$agent_id\n";
			}
			elsif($option eq "unpause")
			{
				$cmd="Action: QueuePause\nInterface: Agent/$agent_id\nPaused: 0\nDisplay: 0\n";
			}
			elsif($option eq "tellAgentStatus")
			{
				$cmd="Action: tellAgentStatus\nAgent: $agent_id\n";
			}
			elsif($option eq "confRoomcheck") {
				$cmd="Action: Hangup\nChannel: $agent_id\n";
			}
			elsif($option eq "unpause1")
			{
				$cmd="Action: QueuePause\nInterface: Agent/$agent_id\nQueue: $campaign_name\nPaused: 0\nDisplay: 1\n";
			}
			elsif($option eq "Redirect")
			{
				$cmd="Action: AgentRedirect\nChannel: $channel\ncontext: AgentLogin\nagentid: $agent_id\nexten: $agent_exten\npriority: $priority\n";
			}

			$tnet->cmd(String => $cmd, Errmode=> Return, Timeout=> 0);

			if($option eq "unpause1")
			{
				$sendTn_semaphore->down;
				delete $sendTnHash{$agent_id."##".$campaign_name};
				$sendTn_semaphore->up;
			}
			elsif($option eq "Redirect")
			{
				$sendTn_semaphore->down;
				delete $sendTnHash{$agent_id."##".$campaign_name."##".$channel."##".$agent_exten."##".$priority};
				$sendTn_semaphore->up;
			}
			else{
				$sendTn_semaphore->down;
				delete $sendTnHash{$agent_id};
				$sendTn_semaphore->up;
			}
		}
		usleep(500000);


	}
	$tnet->cmd(String => "Action: Logoff\n\n", Prompt => "/.*/", Errmode => Return, Timeout =>1);
	$tnet->close;
	undef($tnet);
}
##################sendTelnetCommand END##########################################################

##################csat block start################################################################
sub csat_check
{
	my @params = @_;
	my $tz_datetime = get_time_now();
	my $dbh = $params[0];
	my $date_time_one = $params[1];
	my $date_time_two = $params[2];
	my $time_rule_flag = $params[3];
	my $campaign_id = $params[4];
	my $phone_num = $params[5];
	my $ip = $params[6];
	my $type = $params[7];
	my $session_id = $params[8];
	my $query="";
	if(defined($time_rule_flag) && $time_rule_flag) {
		my @end_timearr = split(/:/,$date_time_two);
		my $time_duration = (($end_timearr[0] * 3600) + $end_timearr[1] * 60 + $end_timearr[2]);
		my @date_array = split(/ /,$tz_datetime);
		my $tz_time_stamp = parsedate($tz_datetime);
		my $time_stamp_one = parsedate("$date_array[0] $date_time_one");
		my $duration = strftime("%Y-%m-%d %H:%M:%S", localtime(parsedate("+$time_duration seconds",NOW => parsedate("$date_array[0] $date_time_one"))));
		my $time_stamp_two = parsedate($duration);
		if(($tz_time_stamp >= $time_stamp_one) && ($tz_time_stamp <= $time_stamp_two)) {
			$query="insert into sync_tp_agent (query,userType,method,third_party_server_ip,http_filepath,http_filename) values ('campaign_id=$campaign_id&phone=$phone_num&type=$type&session_id=$session_id','HTTP','GET','$ip','/apps/','csat_handler.php')";
			query_execute($query,$dbh,0,__LINE__);

			return;
		}
	}
	else {
		$query="insert into sync_tp_agent (query,userType,method,third_party_server_ip,http_filepath,http_filename) values ('campaign_id=$campaign_id&phone=$phone_num&type=$type&session_id=$session_id','HTTP','GET','$ip','/apps/','csat_handler.php')";
		query_execute($query,$dbh,0,__LINE__);
	}
}

#######################csat block ENd##########################################################

##################NewMonitorFileName block start###############################################
sub MakeNewMonitorFileName
{
	my @params = @_;
	my $dbh = $params[0];
	my $lead_id = $params[1];
	my $campaign_id = $params[2];
	my $list_id = $params[3]; 
	my $agent_id = $params[4];
	my $session_id = $params[5];
	my $campaign_type = $params[6];
	my $dialerType = $params[7];
	my $call_status = $params[8];
	my $campaign_name = $params[9];
	my $custphno = $params[10];
	my $list_name = $params[11];
	my $CustUniqueId = $params[12];
	my $lead_attempt_count = $params[13];
	my $phone_attempt_count = $params[14];
	my $timestamp = $params[15];
	my $voiceFileFormat="";
	my $new_monitor_filename="";
	my $nw_str="";

	if(defined($lead_id) && ($lead_id !~ /^$/ && $lead_id !~ /^[\s]+$/)  && $lead_id!=0) {
		if (defined($MonitorFileFormatLead{$campaign_id}) && ($MonitorFileFormatLead{$campaign_id} !~ /^$/ && $MonitorFileFormatLead{$campaign_id} !~ /^[\s]+$/)) {
			$voiceFileFormat  = $MonitorFileFormatLead{$campaign_id};
		}
	}
	else{
		if (defined($MonitorFileFormatManual{$campaign_id}) && ($MonitorFileFormatManual{$campaign_id} !~ /^$/ && $MonitorFileFormatManual{$campaign_id} !~ /^[\s]+$/)){
			$voiceFileFormat  = $MonitorFileFormatManual{$campaign_id};
		}
	}
	if(defined($voiceFileFormat) && ($voiceFileFormat !~ /^$/ && $voiceFileFormat !~ /^[\s]+$/)){
		$nw_str = "$campaign_name##$custphno##$list_name##$CustUniqueId##$lead_attempt_count##$phone_attempt_count##$timestamp";
		$new_monitor_filename = getNewMonitorFileName ($dbh,$campaign_id,$lead_id,$list_id,$agent_id,$session_id,$campaign_type,$dialerType,$call_status,$voiceFileFormat,$nw_str,"");
		$session_id +=0;
		$session_id =~ s/\.//g;
		if (index($new_monitor_filename, $session_id) == -1) {
			$new_monitor_filename="";
		}

		if (length($new_monitor_filename) < 10) {
			$new_monitor_filename="";
		}
	}
	return $new_monitor_filename;
}

#######################NewMonitorFileName block ENd############################################

##################NewMonitorFileName block start###############################################
sub MakecustFileName
{
	my @params = @_;
	my $dbh = $params[0];
	my $lead_id = $params[1];
	my $campaign_id = $params[2];
	my $list_id = $params[3]; 
	my $agent_id = $params[4];
	my $session_id = $params[5];
	my $campaign_type = $params[6];
	my $dialerType = $params[7];
	my $call_status = $params[8];
	my $campaign_name = $params[9];
	my $custphno = $params[10];
	my $list_name = $params[11];
	my $CustUniqueId = $params[12];
	my $lead_attempt_count = $params[13];
	my $phone_attempt_count = $params[14];
	my $timestamp = $params[15];
    my $reportingformat="";
	my $cust_reporting_str="";
	my $cnw_str="";
	if(defined($lead_id) && ($lead_id !~ /^$/ && $lead_id !~ /^[\s]+$/) && $lead_id!=0) {
	if (defined($ReportingFormatLead{$campaign_id}) && ($ReportingFormatLead{$campaign_id} !~ /^$/ && $ReportingFormatLead{$campaign_id} !~ /^[\s]+$/) ) {
			$reportingformat  = $ReportingFormatLead{$campaign_id};
		}
	}
	else{
	if (defined($ReportingFormatManual{$campaign_id}) && ($ReportingFormatManual{$campaign_id} !~ /^$/ && $ReportingFormatManual{$campaign_id} !~ /^[\s]+$/) ){
			$reportingformat = $ReportingFormatManual{$campaign_id};
		}
	}
	if(defined($reportingformat) && ($reportingformat !~ /^$/ && $reportingformat !~ /^[\s]+$/)){
		$cnw_str = "$campaign_name##$custphno##$list_name##$CustUniqueId##$lead_attempt_count##$phone_attempt_count##$timestamp";
		$cust_reporting_str = getNewMonitorFileName ($dbh,$campaign_id,$lead_id,$list_id,$agent_id,$session_id,$campaign_type,$dialerType,$call_status,$reportingformat,$cnw_str,"crf");
	}
	return $cust_reporting_str;
}
#######################NewcustFileName block ENd############################################

##################GET_TIME_NOW START###########################################################
sub get_time_now        #get the current date and time and epoch for logging call lengths and datetimes
{
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(gettimeofday());
	my $now_date;
	my $Fhour;

	$year = ($year + 1900);
	$mon++;
	if ($mon < 10) {$mon = "0$mon";}
	if ($mday < 10) {$mday = "0$mday";}
	if ($hour < 10) {$Fhour = "0$hour";}
	if ($min < 10) {$min = "0$min";}
	if ($sec < 10) {$sec = "0$sec";}

	$now_date = "$year-$mon-$mday $hour:$min:$sec";
	return $now_date;
}
##################GET_TIME_NOW  END###########################################################


###################get_gmt_time START#########################################################
sub get_gmt_time
{
	my $cur_time = shift;
	my $cur_gmt_time = gmtime($cur_time);
	return timelocal (@$cur_gmt_time);
}
#############get_gmt_time END#################################################################


##################ERROR_HANDLER START###########################################################
sub error_handler
{
	my $errorlogtime=get_time_now();
	my @params=@_;
	my $error_string=$params[0];
	my $line_no=$params[1];
	my $query=$params[2];
	my ($sec,$min,$hour,$mday,$mon,$year,$cur_wday,$yday,$isdst) = localtime(time);
	my $cur_date = sprintf("%d-%02d-%02d",$year + 1900,$mon+1,$mday);

	if($error_string =~ /is marked as crashed/)
	{
		my $crashed_table;
		my @arr;
		my $new_dbh=DBI->connect("dbi:mysql:$db:$server",$username,$password,{mysql_auto_reconnect => 1}) or die (exit );
		@arr = split(/\/|\'/,$error_string);
		$crashed_table = $arr[3];
		query_execute("repair table $crashed_table",$new_dbh,0,__LINE__);
		undef @arr;
		undef $crashed_table;
		$new_dbh->disconnect();
		undef $new_dbh;
		open OUT, ">>/var/log/czentrix/czentrix_listen_log.txt"; #open log file to write
		print OUT "$errorlogtime  $error_string at $line_no\n";
		close OUT;
	}
	elsif($error_string =~ /MySQL server has gone away/)
	{
		open OUT, ">>/var/log/czentrix/czentrix_listen_log.txt"; #open log file to write
		print OUT "$errorlogtime  $error_string at $line_no\n";
		close OUT;
		undef($errorlogtime);
		exit();
	}
	elsif($error_string eq "Unable to create shared memory")
	{
		open OUT, ">>/var/log/czentrix/czentrix_listen_log.txt"; #open log file to write
		print OUT "czentrix restarted as it was unable to create shared memory";
		close OUT;
        #unable to create the shared memory first time hence restart the service
		system('service czentrix restart');
		system('service czentrix-dialer restart');
	}
	else
	{
		open OUT, ">>/var/log/czentrix/czentrix_listen_log.txt"; #open log file to write
		print OUT "$errorlogtime  $error_string for $query at $line_no \n";
		close OUT;
		if($error_string =~ /Unknown column/)
		{
			open OUT, ">>/tmp/czentrix_listen_log_$cur_date.txt"; #open log file to write
			print OUT "$query; \n";
			close OUT;
		}
	}
	undef($errorlogtime);
	return;
}
##################ERROR_HANDLER END###########################################################


##################GETVAR START###########################################################
#Response: Success
#Variable: callerid
#Value:  11290052116,12900,1,strict
#--GET_VAR--
sub getvar
{
	my $tn = new Net::Telnet (Timeout => 20,Prompt  => '/%/',Host    => "localhost",Port    => "5038");
	$tn->waitfor('/0\n$/');
	$tn->print("Action: Login\nUsername: $telnet_username\nSecret: $telnet_secret\nEvents: Off\n");
	$tn->waitfor('/Authentication accepted/');
	$tn->buffer_empty;
	my @params = @_;
	my $var=$params[0];
	my $cmd="action: GetVar\nchannel: $var\nvariable: callerid\n";
	my @command_line = $tn->cmd(String => $cmd, Errmode => Return, Prompt => '/--GET_VAR--.*/',Timeout => 1);
	$tn->buffer_empty;
	$tn->cmd(String => "Action: Logoff\n\n", Prompt => "/.*/", Errmode => Return, Timeout =>1);
	$tn->close;
	undef($tn);
	my $total_lines=scalar(@command_line);
	return $command_line[$total_lines-1];
}
#-----GETVAR END----------------------------------


#----AGENTLOGINBLOCK START------------------------
sub AgentLoginBlock()
{
	my @params;
	my $agent_id;
	my $agent_ext;
	my $agent_session_id;
	my $channel;
	my $dbh;
	my $disconnect_time=0;
	my $agent_name='';
	my $phoneType=1;
	my $staticIP;
	my $dialerType;
	my $wrapupTime;
	my $campaign_id;
	my $campaign_name;
	my $retArray;
	my $agentdetail;
	my $type;
	my $query;
	my $time=get_time_now();
	my $zap_id;
	my $shared_key;
	my $monitoring=0;
	my $camp_monitoring=0;
	my $agent_monitoring=0;
	my $retValArray;
	my $agentlogin_time;

	my $campaign_type="";
	my $avg_wrap_time=0;
	my $total_wrap_time=0;
	my $total_calls=0;
	my $state="";

	my $connect_time=time;
	my $state_change_time=0;
	my $agent_login_time="";
	my $non_desktop_agent=0;
	my $logdinflag=0;
	my $agent_logoff_flag=0;
	my $agent_mapped_ext=0;
	my $auto_preview_dialing=0;
	my $camp_logout_flag=0;
	my $maxagentcount=0;
	my $initial_agent=0;
	my $bk_to_agent=0;

	@params=@_;
	$agent_id=$params[0];
	$agent_ext=$params[1];
	$agent_session_id=$params[2];
	$dbh=$params[3];
	$type=$params[4];
	my $fail_safe_agent_state = $params[5];
	$agent_login_time = ((defined($params[6]) && ($params[6] !~ /^$/ && $params[6] !~ /^[\s]+$/) )?"'".$params[6]."'":"");
	my $table_name =$params[7];
	$channel=$params[8];
	$bk_to_agent=$params[9];

    $query="select campaign_id from agent where agent_id='$agent_id'";
	my $campagentArray=query_execute($query,$dbh,1,__LINE__);

    if(defined($agentcount{@$campagentArray[0]}) && ($agentcount{@$campagentArray[0]} !~ /^$/ && $agentcount{@$campagentArray[0]} !~ /^[\s]+$/))
	{
              $initial_agent = $agentcount{@$campagentArray[0]};
	}

	if (not exists $camp_agentcount{@$campagentArray[0]}) {
		populateCampaign(@$campagentArray[0],$dbh,'0');
	}
	$maxagentcount = $camp_agentcount{@$campagentArray[0]};


	if ($maxagentcount > 0 && $maxagentcount <= $initial_agent) {
		$shared_key = $agent_id;
		$sendTn_semaphore->down;
		$sendTnHash{$shared_key} = "agentlogoff";
		$sendTn_semaphore->up;
       
	    $query="update agent set logout_reason='Max Connection Exceed' where agent_id='$agent_id'";
		query_execute($query,$dbh,0,__LINE__);

		return;
	}

	if((!defined($agent_login_time) || $agent_login_time =~ /^$/ || $agent_login_time =~ /^[\s]+$/)) {
		my @returnvarSess=split('\.',$agent_session_id);
		$agent_login_time = "from_unixtime('$returnvarSess[0]')";
	}

	if($type eq "main"){
		$query="select last_logoff_time,last_agent_session_id,campaign_id,staticIP,agent_name from agent where agent_id='$agent_id'";
		my $agentArray=query_execute($query,$dbh,1,__LINE__);
		if(defined(@$agentArray[0]) && (@$agentArray[0] !~ /^$/ && @$agentArray[0] !~ /^[\s]+$/) && $bk_to_agent==0)
		{
			if(@$agentArray[1] == $agent_session_id){
				if (not exists $campaignHash{@$agentArray[2]}) {
					populateCampaign(@$agentArray[2],$dbh,'0');
				}
				$campaign_name = $campaignHash{@$agentArray[2]};
				$agent_name = @$agentArray[4];

				$query="insert into agent_state_analysis_$table_name (node_id,agent_id,campaign_id,agent_state,call_start_date_time,call_end_date_time,agent_session_id,agent_name,campaign_name,ip,entrytime,agent_ext,logout_reason) values('$node_id','$agent_id','@$agentArray[2]','LOGIN_N_LOGOUT',$agent_login_time,$agent_login_time,'$agent_session_id','$agent_name','$campaign_name',inet_aton('@$agentArray[3]'),unix_timestamp(),'$agent_ext','Normal')";
				query_execute($query,$dbh,0,__LINE__);
				check_cview($query,$dbh,$table_name,2);
#Adding information to Agent State Analysis current report
				$query =~ s/$table_name/current_report/i;
				query_execute($query,$dbh,0,__LINE__);
				return;
			}
		}
	}

#first initialise the call_duration_arrays w.r.t agent_id.
#Again changed it to 0 by Manish
	my @cda;
	$cda[0]=0;
	$cda[1]=0;
	$cda[2]=0;
	$cda[3]=0;
	$wrapup_semaphore->down;
	$call_duration_array1[$agent_id]=join(",",@cda);
	$call_duration_array2[$agent_id]=join(",",@cda);
	$call_duration_array3[$agent_id]=join(",",@cda);

#initialize UAB array for a particular agent with 1
	$update_avg_block1[$agent_id]=1;
	$update_avg_block2[$agent_id]=1;
	$update_avg_block3[$agent_id]=1;

#initialize the predict state after array
	$predict_state_after1[$agent_id]=0;
	$predict_state_after2[$agent_id]=0;
	$predict_state_after3[$agent_id]=0;

	$state_changed[$agent_id]=0;
	$wrapup_semaphore->up;
	undef(@cda);

#<TVT> add non_desktop_agent params.

	if($type eq "fail_safe_butdonotupdatetable")
	{
#check for the phone type, if 0 soft else hard
		$query="select phoneType,staticIP,dialerType,wrapupTime,a.campaign_id,a.monitor_calls,b.monitoring,a.remote_agent,a.campaign_type,b.agent_ext,a.auto_preview_dialing,a.logout_flag from campaign as a,agent as b where a.campaign_id=b.campaign_id and b.agent_id='$agent_id'";
		$retArray=query_execute($query,$dbh,1,__LINE__);

		$phoneType=@$retArray[0];
		$staticIP=@$retArray[1];
		$dialerType=@$retArray[2];
		$wrapupTime=@$retArray[3];
		$campaign_id=@$retArray[4];
		$camp_monitoring=@$retArray[5];
		$agent_monitoring=@$retArray[6];
		$non_desktop_agent=@$retArray[7];
		$campaign_type=@$retArray[8];
		$agent_mapped_ext=@$retArray[9];
		$auto_preview_dialing=@$retArray[10];
		$camp_logout_flag=@$retArray[11];
		if($non_desktop_agent) {
			$staticIP = "0.0.0.0";
		}
		if (defined($agent_mapped_ext) && ($agent_mapped_ext !~ /^$/ && $agent_mapped_ext !~ /^[\s]+$/) && $agent_mapped_ext && ($agent_mapped_ext != $agent_ext)) {
			$agent_logoff_flag=1;
		}
#ip of agent will be taken from the agent table for both the soft and hard phone, no sip show peers is required now

		if(defined($staticIP) && ($staticIP !~ /^$/ && $staticIP !~ /^[\s]+$/) && $agent_logoff_flag==0 )
		{
#take the agent to closure state when s/he loggs in

            $query="select unix_timestamp(last_activity_time),agent_state from agent_live where agent_id='$agent_id'";
		    $agentdetail=query_execute($query,$dbh,1,__LINE__);

			$avg_wrap_time=0;
			$total_wrap_time=0;
			$total_calls=0;
			$disconnect_time=@$agentdetail[0];
			$state_change_time=@$agentdetail[0];

			my @tmp_arr=();
			$tmp_arr[0]=$dialerType;
			$tmp_arr[1]=$avg_wrap_time;
			$tmp_arr[2]=$total_wrap_time;
			$tmp_arr[3]=$wrapupTime;
			$tmp_arr[4]=$total_calls;
			$tmp_arr[5]=$fail_safe_agent_state;
			$tmp_arr[6]=$disconnect_time;
			$tmp_arr[7]=$state_change_time;
			$tmp_arr[8]=$connect_time;

#initiate the agent_wrapup array when an agent loggs in
			$wrapup_semaphore->down;
			$agent_wrapup{$agent_id}=join(",",@tmp_arr);
			$setmefree_hit[$agent_id]=1;
			$wrapup_semaphore->up;
			undef(@tmp_arr);
			$logdinflag = 1;
       
	        $agentcount_semaphore->down;
			$agentcount{$campaign_id}=$initial_agent + 1;
			$agentcount_semaphore->up;

			if ($camp_logout_flag==1) {
		            if (not exists $logoutagent{$campaign_id}) {
			           populatelogout($dbh,$campaign_id);
		        }
	        }

		}
		else
		{
#logoff that agent as no ip address found
#sendTelnetCommand($agent_id,"agentlogoff",$dbh);
			$shared_key = $agent_id;
			$sendTn_semaphore->down;
			$sendTnHash{$shared_key} = "agentlogoff";
			$sendTn_semaphore->up;

			$query="update agent set logout_reason='Agent id Blank' where agent_id='$agent_id'";
		    query_execute($query,$dbh,0,__LINE__);
		}
		return;
	}

	if($type eq "main")
	{
#if agent already logged in from another machine then log off that one
		$query="select agent_id from agent_live where agent_id='$agent_id'";
		$retArray=query_execute($query,$dbh,1,__LINE__);

		if(defined(@$retArray[0]) && (@$retArray[0] !~ /^$/ && @$retArray[0] !~ /^[\s]+$/))
		{
			$query="delete from agent_live where agent_id='$agent_id'";
			query_execute($query,$dbh,0,__LINE__);

##CRM_LIVE CHANGES
			$query="delete from crm_live where agent_id='$agent_id'";
			query_execute($query,$dbh,0,__LINE__);

			$query="delete from crm_hangup_live where agent_id='$agent_id'";
			query_execute($query,$dbh,0,__LINE__);

			$query="delete from lead_traverse where agent_id='$agent_id'";
			query_execute($query,$dbh,0,__LINE__);

#sendTelnetCommand(@$retArray[0],"agentlogoff",$dbh);
			$shared_key = @$retArray[0];
			$sendTn_semaphore->down;
			$sendTnHash{$shared_key} = "agentlogoff";
			$sendTn_semaphore->up;
			return;

			$query="update agent set logout_reason='Agent Already Loggin' where agent_id='$agent_id'";
		    query_execute($query,$dbh,0,__LINE__);
		}

##Clean meet me user file if user exists in conference room
		$query="select chan_name from meetme_user where confno='$agent_id' and cust_ph_no='$agent_id'";
		$retArray=query_execute($query,$dbh,1,__LINE__);
		if(defined(@$retArray[0]) && (@$retArray[0] !~ /^$/ && @$retArray[0] !~ /^[\s]+$/))
		{
			if ($channel ne @$retArray[0]) {
				$sendTn_semaphore->down;
				$sendTnHash{@$retArray[0]} = "confRoomcheck";
				$sendTn_semaphore->up;
			}
		}

#$query="delete from meetme_user where confno='$agent_id' and cust_ph_no='$agent_id'";
#query_execute($query,$dbh,0,__LINE__);
	}
	$query="delete from recent_leads where agent_id='$agent_id'";
	query_execute($query,$dbh,0,__LINE__);

	$query="delete from customer_live where agent_id='$agent_id'";
	query_execute($query,$dbh,0,__LINE__);

	$query="delete from lead_traverse where agent_id='$agent_id'";
	query_execute($query,$dbh,0,__LINE__);

#check for the phone type, if 0 soft else hard
	$query="select phoneType,staticIP,dialerType,wrapupTime,a.campaign_id,a.monitor_calls,b.monitoring,a.campaign_name,a.remote_agent,b.agent_ext,a.auto_preview_dialing,a.logout_flag,now() from campaign as a,agent as b where a.campaign_id=b.campaign_id and b.agent_id='$agent_id'";
	$retArray=query_execute($query,$dbh,1,__LINE__);

	$phoneType=@$retArray[0];
	$staticIP=@$retArray[1];
	$dialerType=@$retArray[2];
	$wrapupTime=@$retArray[3];
	$campaign_id=@$retArray[4];
	$camp_monitoring=@$retArray[5];
	$agent_monitoring=@$retArray[6];
	$campaign_name=@$retArray[7];
	$non_desktop_agent=@$retArray[8];
	$agent_mapped_ext =@$retArray[9];
	$auto_preview_dialing = @$retArray[10];
	$camp_logout_flag = @$retArray[11];
	$agentlogin_time =@$retArray[12];

	if($non_desktop_agent) {
		$staticIP="0.0.0.0";
	}


#if monitoring is disabled in campaign then insert 0 in agent_live for monitoring field
	if(defined($camp_monitoring) && ($camp_monitoring==0))
	{
		$monitoring = 0;
	}
	elsif($camp_monitoring==1)
	{
#if agent monitoring is enabled then insert 1 in agent_live else insert 0 in agent_live
		if(defined($agent_monitoring) && ($agent_monitoring==1)) {
			$monitoring = 1;
		}
		elsif($agent_monitoring==0) {
			$monitoring = 0;
		}
	}
	if (defined($agent_mapped_ext) && ($agent_mapped_ext !~ /^$/ && $agent_mapped_ext !~ /^[\s]+$/) && $agent_mapped_ext && ($agent_mapped_ext != $agent_ext)) {
		$agent_logoff_flag=1;
	}

	$query="select count(*) from agent_live";
	$retValArray=query_execute($query,$dbh,1,__LINE__);

	if ((@$retValArray[0] + 1) > $max_agents || (defined($agent_logoff_flag) && $agent_logoff_flag ))
	{
		$shared_key = $agent_id;
		$sendTn_semaphore->down;
		$sendTnHash{$shared_key} = "agentlogoff";
		$sendTn_semaphore->up;

		$query="update agent set logout_reason='Lic Exceed or ext not same' where agent_id='$agent_id'";
        query_execute($query,$dbh,0,__LINE__);
	}
	else
	{
#ip of agent will be taken from the agent table for both the soft and hard phone, no sip show peers is required now
		if(defined($staticIP) && ($staticIP !~ /^$/ && $staticIP !~ /^[\s]+$/))
		{
			my $prv_camp = 0;
			my $closer_time = -999;
			if($dialerType eq "PREVIEW")
			{
			   $closer_time=0;
			   $prv_camp=1;
			}

#take the agent to closure state when s/he loggs in
			$query="insert into agent_live (agent_id,campaign_id,agent_state,last_login_time,agent_ext,ip,dialer_type,wrap_up_time,agent_session_id,monitoring,closer_time,last_activity_time,agent_channel,wait_time,autoMode) values('$agent_id','$campaign_id','".($non_desktop_agent || $prv_camp ?'FREE':'CLOSURE')."',$agent_login_time,'$agent_ext','$staticIP','$dialerType','$wrapupTime','$agent_session_id','$monitoring','$closer_time',now(),'$channel',unix_timestamp(),'$auto_preview_dialing')";
            query_execute($query,$dbh,0,__LINE__);

			$query = "update agent set last_login_time = $agent_login_time,last_agent_session_id='$agent_session_id' where agent_id = '$agent_id'";
			query_execute($query,$dbh,0,__LINE__);

##CRM_LIVE CHANGES
			$query="delete from crm_live where agent_id='$agent_id'";
			query_execute($query,$dbh,0,__LINE__);

			$query="delete from crm_hangup_live where agent_id='$agent_id'";
			query_execute($query,$dbh,0,__LINE__);

			$query="insert into crm_live (agent_id) values('$agent_id')";
			query_execute($query,$dbh,0,__LINE__);

			$query="insert into crm_hangup_live (agent_id) values('$agent_id')";
			query_execute($query,$dbh,0,__LINE__);

#$query="delete from crm_meetme_live where agent_id = '$agent_id'";
#query_execute($query,$dbh,0,__LINE__);

			$avg_wrap_time=0;
			$total_wrap_time=0;
			$total_calls=0;
			$state="CLOSURE";
			$disconnect_time="-999";
			$state_change_time=0;

			my @tmp_arr=();
			$tmp_arr[0]=$dialerType;
			$tmp_arr[1]=$avg_wrap_time;
			$tmp_arr[2]=$total_wrap_time;
			$tmp_arr[3]=$wrapupTime;
			$tmp_arr[4]=$total_calls;
			$tmp_arr[5]=$state;
			$tmp_arr[6]=$disconnect_time;
			$tmp_arr[7]=$state_change_time;
			$tmp_arr[8]=$connect_time;

			  
			$agentcount_semaphore->down;
			$agentcount{$campaign_id}=$initial_agent + 1;
			$agentcount_semaphore->up;

#initiate the agent_wrapup array when an agent loggs in
			$wrapup_semaphore->down;
			$agent_wrapup{$agent_id}=join(",",@tmp_arr);
			$setmefree_hit[$agent_id]=1;
			$wrapup_semaphore->up;
			undef(@tmp_arr);

			$logdinflag = 1;
		}
		else
		{
#logoff that agent as no ip address found
#sendTelnetCommand($agent_id,"agentlogoff",$dbh);
			$shared_key = $agent_id;
			$sendTn_semaphore->down;
			$sendTnHash{$shared_key} = "agentlogoff";
			$sendTn_semaphore->up;

			$query="update agent set logout_reason='Agent Id Blank' where agent_id='$agent_id'";
            query_execute($query,$dbh,0,__LINE__);
		}
	 }

	 if($logdinflag)
	 {
#agent is logged in at zap channel but after fail safe zap channel is not set to busy
		if($channel =~ /zap/i) {
			$zap_id=substr($channel,0,index($channel,"-"));
			$query="update zap set status='BUSY',flow_state='1' where zap_id='$zap_id'";
			query_execute($query,$dbh,0,__LINE__);
		}

		if (not exists $agentHash{$agent_id}) {
			populateAgent($agent_id,$dbh);
		}
		$agent_name = $agentHash{$agent_id};

        $query="select 1 from agent_state_analysis_current_report  where agent_id='$agent_id' and agent_session_id=$agent_session_id";
		my $returnvar=query_execute($query,$dbh,1,__LINE__);
		  if(!defined (@$returnvar[0]))
			{
			   $query="insert into agent_state_analysis_$table_name (node_id,agent_id,campaign_id,agent_state,call_start_date_time,agent_session_id,agent_name,campaign_name,ip,entrytime,agent_ext) values('$node_id','$agent_id','$campaign_id','LOGIN',$agent_login_time,'$agent_session_id','$agent_name','$campaign_name',inet_aton('$staticIP'),unix_timestamp('$agentlogin_time'),'$agent_ext')";
			   query_execute($query,$dbh,0,__LINE__);
			   check_cview($query,$dbh,$table_name,2);
		#Adding information to Agent State Analysis current report
			   $query =~ s/$table_name/current_report/i;
			   query_execute($query,$dbh,0,__LINE__);
			}
	 }

	 if ($camp_logout_flag==1) {
		if (not exists $logoutagent{$campaign_id}) {
			populatelogout($dbh,$campaign_id);
		}
	 }
}
##################AGENTLOGINBLOCK END###########################################################


##################LINKBLOCK  PBX FUNCTION START##################################################
sub linkBlockPbx()
{
	my @params=();
	my $agent_id;
	my $extension_channel;
	my $customer_channel;
	my $zap_channel;
	my $dbh;
	my $session_id;
	my $monitor_file_name;
	my $zap_flag;
	my $custphno;
	my $custphno1;
	my $query;
	my $call_type;
	my $time=get_time_now();
	my $ivrs_path;
	my $department_id;
	@params=@_;
	$agent_id=$params[0];
	$dbh=$params[1];
	$session_id=$params[2];
	$monitor_file_name=$params[3];
	$extension_channel=$params[4];
	$customer_channel=$params[7];
	$zap_flag=$params[5];
	$custphno=$params[6];
	$zap_channel=$params[8];
	$call_type = $params[9];
	$ivrs_path =$params[11];
	$department_id =$params[13];

	init_stateHash($session_id);
	if(($stateHash{$session_id} & 2) != 2) #if hangup block is not parsed then maintain live tables
	{
		if(!defined($custphno) || $custphno =~ /^$/ || $custphno=~ /^[\s]+$/)
		{
			$custphno = $custphno1;
		}
		if($custphno == 0)
		{
			$custphno = $custphno1;
		}
		$query="replace into pbx_live(extension,caller,extension_channel,customer_channel,link_time,session_id,monitor_file_name,call_type,department_id) values('$agent_id','$custphno','$extension_channel','$customer_channel','$time','$session_id','$monitor_file_name','$call_type','$department_id')";
		query_execute($query,$dbh,0,__LINE__);
	}


	if($zap_flag==1)
	{
		$query="update zap set status='BUSY',session_id='$session_id',flow_state='1' where zap_id='$zap_channel'";
		query_execute($query,$dbh,0,__LINE__);

		$query="update zap_live set department_id='$department_id',peer_id='$agent_id',phone_number='$custphno',call_type='$call_type',service_type='1',campaign_id='',agent_id='',connect_time=unix_timestamp(),context='' where zap_id='$zap_channel'";
		query_execute($query,$dbh,0,__LINE__);
	}

	if($customer_channel =~ /ZAP/i) {
		$zap_channel=substr($customer_channel,0,index($customer_channel,"-"));
		$query="update zap set status='BUSY',session_id='$session_id',flow_state='1' where zap_id='$zap_channel'";
		query_execute($query,$dbh,0,__LINE__);

		$query="update zap_live set department_id='$department_id',peer_id='$agent_id',phone_number='$custphno',call_type='$call_type',service_type='1',campaign_id='',agent_id='',connect_time=unix_timestamp(),context='' where zap_id='$zap_channel'";
		query_execute($query,$dbh,0,__LINE__);
	}

	$stateHash_semaphore->down;
	$stateHash{$session_id} = $stateHash{$session_id} | 8;
	$stateHash_semaphore->up;
	del_stateHash($session_id);
}
##################LINKBLOCKPBX FUNCTION END##################################################


##################LINKBLOCK FUNCTION START##################################################
sub linkBlock()
{
	my @params=();
	my $agent_id;
	my $channel;
	my $zap_channel;
	my $dbh;
	my $session_id;
	my $monitor_file_name;
	my $zap_flag;
	my $custphno;
	my $custphno1;
	my $res;
	my $campaign_id;
	my $returnvar="";
	my @variables=();
	my $lead_id;
	my $list_id;
	my $list_id_temp;
	my $strict;
	my $type;
	my $query;
	my $dialedno;
	my $temp;
	my $retval;
	my $time=get_time_now();
	my $ivrs_path;
	my $complete_list_id;
	my $sth;
	my $customer_name="";
	my $count = 0;
	my $call_type='16384';
	my $blank_num="";
	my $time_zone_id;
	my $new_customer=0;
	my $agent_dialer_type="PROGRESSIVE";

	@params=@_;
	$agent_id=$params[0];
	$dbh=$params[1];
	$session_id=$params[2];
	$monitor_file_name=$params[3];
	$channel=$params[4];
	$zap_flag=$params[5];
	$custphno=$params[6];
	$res=$params[7];
	$zap_channel=$params[8];
	$type=$params[9];
	$ivrs_path =$params[11];
	if($type eq "main")
	{
		my $returnvar=$params[10];
	}
	elsif($type eq "fail")
	{
		$returnvar=getvar($channel);
		if(defined($returnvar) && ($returnvar !~ /^$/ && $returnvar !~ /^[\s]+$/))
		{
			$returnvar=substr($returnvar,index($returnvar,":") + 1);
			$returnvar =~ s/\s+//;
			if($returnvar =~ /^$/ || $returnvar =~ /^[\s]+$/) {
				$call_type="0";
			}
		}
		else {
			$call_type="16384";
		}
	}
	if ($res == 2 || $res ==3 || $res == 4)
	{
#if empty, this is an incoming call, this is an incoming join block with queue information
		if($returnvar =~ /^$/ || $returnvar =~ /^[\s]+$/)
		{
#take out the campaign id to which agent belongs
			$temp="";
			$query="select campaign_id from agent where agent_id='$agent_id'";
			$temp=query_execute($query,$dbh,1,__LINE__);
			$campaign_id=@$temp[0];

			$temp="";
			$query="select list_id from list where campaign_id='$campaign_id'";
			$sth=$dbh->prepare($query);
			$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
			
			if($sth->rows > 1)
			{
				$complete_list_id="(";
				while (my $list_id = $sth->fetchrow_arrayref)
				{
					$complete_list_id.="@$list_id[0],";
					if($count == 0) {
						$list_id_temp="@$list_id[0]";
						$count = 1;
					}
				}
				$list_id=$list_id_temp;
				chop $complete_list_id;
				$complete_list_id.=")";
			}
			else
			{
				$list_id = $sth->fetchrow_arrayref;
				$complete_list_id="(@$list_id[0])";
				$list_id = @$list_id[0];
			}
			$sth->finish();

			if(($custphno =~ /^$/ || $custphno =~ /^[\s]+$/) || $custphno =~ /[a-z]/ )   {
				$new_customer=1;
				$blank_num=1;
			}
			else
			{
				$query="select lead_id,list_id,ph_type from dial_Lead_lookup_$campaign_id where phone='$custphno' limit 1";
				$temp=query_execute($query,$dbh,1,__LINE__);
				if(defined(@$temp[0]) && @$temp[0] !~ /^$/ && @$temp[0]!~ /^[\s]+$/)
				{
					$lead_id=@$temp[0];
					$list_id=@$temp[1];
				}
				else {
					$new_customer=1;
				}
			}
			if($new_customer){
				my $cust_remove="";
				$query="select list_id,list_name,time_zone_id,timezone_code_id from list where campaign_id='$campaign_id' limit 1";
				$temp=query_execute($query,$dbh,1,__LINE__);
				$list_id=@$temp[0];
				$time_zone_id=@$temp[3];

				if($blank_num) {
					$custphno=int(rand(100000));
					$custphno="1234-$custphno";
				}

				$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");

				my $custphno1;
				$custphno1=int(rand(100000));
				$custphno1="1234-$custphno1";

				$query="insert into $cust_remove (phone1,phone2,listerner_inserted_field,list_id) values ('$custphno','$custphno1','1','$list_id')";
				$lead_id=query_execute($query,$dbh,3,__LINE__);

				$query="insert into dial_Lead_lookup_$campaign_id(lead_id,phone,list_id,time_zone_id,ph_type,dial_state) values ($lead_id,'$custphno','$list_id','$time_zone_id','101','0')";
				query_execute($query,$dbh,0,__LINE__);

				$query="insert into dial_Lead_lookup_$campaign_id(lead_id,phone,list_id,time_zone_id,ph_type,dial_state) values ($lead_id,'$custphno1','$list_id','$time_zone_id','102','0')";
				query_execute($query,$dbh,0,__LINE__);

				$query="insert into extended_customer_$campaign_id (lead_id,phone1,tz_ph_1,list_id,phone2,tz_ph_2) values ($lead_id,'$custphno','$time_zone_id','$list_id','$custphno1','$time_zone_id')";
				query_execute($query,$dbh,0,__LINE__);
			}
		}
		else
		{
			@variables=split(/,/,$returnvar);
			$custphno=$variables[0];
			$lead_id=$variables[1];
			$campaign_id=$variables[2];
			$list_id=$variables[3];
			$strict=$variables[4];

		   if(defined($variables[5]) && ($variables[5] !~ /^$/ && $variables[5] !~ /^[\s]+$/))
		   {
			 $agent_dialer_type=$variables[5];
			 $agent_dialer_type=~s/\n//g;
			 $agent_dialer_type=~s/ //g;
		   }
		}
		init_stateHash($session_id);
		if($stateHash{$session_id} == 0)
		{
			joinBlock($returnvar,"answered",$time,$dbh,$session_id,$campaign_id,$custphno,$channel);
		}

		if(($stateHash{$session_id} & 2) != 2) #if hangup block is not parsed then maintain live tables
#if((($stateHash{$session_id} & 4) != 4) && (($stateHash{$session_id} & 2) != 2)) #if neither unlink nor hangup block is parsed
		{
#in csse of INCALL we are setting the set_me_free flag. Abhi

			if(!defined($custphno) || $custphno =~ /^$/ || $custphno=~ /^[\s]+$/)
			{

				$custphno = $custphno1;
			}
			if($custphno == 0)
			{
				$custphno = $custphno1;
			}

			$query="update agent_live set agent_state='INCALL',session_id='$session_id',lead_id='$lead_id', is_free='1',holdDuration='0',holdNumTime='0',holdTimestamp='0000-00-00 00:00:00',last_activity_time=now(),from_campaign='$campaign_id',last_lead_id='$lead_id',last_cust_ph_no='$custphno',call_type='$call_type',ph_type='101',wait_time=unix_timestamp(),call_dialer_type='$agent_dialer_type',closer_time='0',trying_flag=0,trying_cust_ph_no=0 where agent_id='$agent_id'";
			query_execute($query,$dbh,0,__LINE__);

			$query="replace into customer_live(cust_ph_no,agent_id,campaign_id,channel,link_time,session_id,state,ivrs_path) values('$custphno','$agent_id','$campaign_id','$channel','$time','$session_id','MUNHOLD','$ivrs_path')";
			query_execute($query,$dbh,0,__LINE__);

#Mark the state of agent READY
			$wrapup_semaphore->down;
			my @tmp_arr=();
			@tmp_arr=split(",",$agent_wrapup{$agent_id});
			$tmp_arr[5]="INCALL";
			$tmp_arr[7]=time;               #state change time
			$tmp_arr[8]=time;               #call connect time
			$agent_wrapup{$agent_id}=join(",",@tmp_arr);
			$wrapup_semaphore->up;
			undef(@tmp_arr);
		}

		$query="select call_dialer_type from agent_live where agent_id='$agent_id'";
		$returnvar=query_execute($query,$dbh,1,__LINE__);
		$call_type=@$returnvar[0];

		if($zap_flag==1)
		{
			$query="update zap set status='BUSY',session_id='$session_id',flow_state='1' where zap_id='$zap_channel'";
			query_execute($query,$dbh,0,__LINE__);

			$query="update call_dial_status set agent_id='$agent_id',channel='$zap_channel',monitor_file_name='$monitor_file_name',link_date_time=now(),dialer_type='$call_type',status='answered',cust_ph_no='$custphno',campaign_id='$campaign_id', lead_id='$lead_id' where session_id=$session_id";
			query_execute($query,$dbh,0,__LINE__);
		}
		else
		{
			if($type eq "fail")
			{
				$query="select if(session_id='$session_id','null',sip_id) from sip limit 1";
				$retval=query_execute($query,$dbh,1,__LINE__);

				if(defined(@$retval[0]) && (@$retval[0] !~ /null/) && (@$retval[0] !~ /^$/ && @$retval[0] !~ /^[\s]+$/))
				{
					$query="update sip set status='BUSY',session_id='$session_id',flow_state='1' where sip_id='@$retval[0]'";
					query_execute($query,$dbh,0,__LINE__);
				}
				else
				{
#insert a temporary channel, i think this is not required let us insert good amount of channels at the starting
#so that this code will not be required
				}
			}
			$query="update call_dial_status set agent_id='$agent_id',channel='SIP',monitor_file_name='$monitor_file_name',link_date_time=now(),dialer_type='$call_type',status='answered',cust_ph_no='$custphno',campaign_id='$campaign_id',lead_id='$lead_id' where session_id=$session_id";
			query_execute($query,$dbh,0,__LINE__);
		}
		$stateHash_semaphore->down;
		$stateHash{$session_id} = $stateHash{$session_id} | 8;
		$stateHash_semaphore->up;
		del_stateHash($session_id);

		if(defined($lead_id) && ($lead_id !~ /^$/ && $lead_id !~ /^[\s]+$/) && ($lead_id != 0))
		{
			$returnvar="";
			my $cust_remove="";
			$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");
			$query="select name from $cust_remove where lead_id='$lead_id'";
			$returnvar=query_execute($query,$dbh,1,__LINE__);
			$customer_name=@$returnvar[0];
			if (!defined($customer_name))
			{
				$customer_name= "";
			}
			else
			{
				$customer_name =~ s/\'/\\'/g;
			}
		}
	}
}
##################LINKBLOCK FUNCTION END##########################################################


########################################joinBlock()  FUNCTION START#############################################
sub joinBlock()
{
	my @params=@_;
	my $returnvar=$params[0];
	my $status=$params[1];
	my $time=$params[2];
	my $dbh=$params[3];
	my $session_id=$params[4];
	my $campaign_id=$params[5];
	my @variables;
	my $custphno=$params[6];
	my $joinChannel=$params[7];
	my $lead_id;
	my $list_id;
	my $strict;
	my $query;
	my $message="";
	my $transfer_from="";
	my $provider_channel = "";

	if(( $joinChannel =~ /Zap/i))
	{
		$provider_channel=substr($joinChannel,0,index($joinChannel,"-"));
		$query="update zap set flow_state='1' where zap_id='$provider_channel'";
		query_execute($query,$dbh,0,__LINE__);

	}

	if($returnvar =~ /^$/ || $returnvar =~ /^[\s]+$/)
	{
		$query="replace into call_dial_status(cust_ph_no,session_id,status,q_enter_time) values ('$custphno','$session_id','$status','$time')";
		query_execute($query,$dbh,0,__LINE__);
	}
	else
	{
		$returnvar=~ s/\s+//g;

		@variables=split(/,/,$returnvar);
		$custphno=$variables[0];
		$lead_id=$variables[1];
		$campaign_id=$variables[2];
		$list_id=$variables[3];
		$strict=$variables[4];
		$transfer_from=$variables[6];
		if (!defined($transfer_from))
		{
			$transfer_from="";
		}

		$query="replace into call_dial_status(cust_ph_no,campaign_id,q_enter_time,lead_id,session_id,status,transfer_from) values ('$custphno','$campaign_id','$time','$lead_id','$session_id','$status','$transfer_from')";
		query_execute($query,$dbh,0,__LINE__);
	}
}
########################################joinBlock  END#############################################

#################################AbandonAction####################################################
#==lst===liststats===population===from=here=also====
sub insert_data
{
	my @params=@_;
	my $dbh = $params[0];
	my $org_campaign_id = $params[1];
	my $phone = $params[2];
	my $callerid = $params[3];
	my $interval = $params[4];
	my $CustUniqueId = $params[5];
	my $org_skill_id = $params[6];
	my $cust_remove_flag = $params[7];
	my $customer_name="";
	my $campaign_name;
	my $action_value1;
	my $action_value2;
	my $action;
	my $multi_dial;
	my $list_id;
	my $list_str="";
	my $blended_lookup= 0;
	my $abandon_time =0;
	my $campaign_type="";
	my $timestamp=time();
	my @row = ();
	my $cust_remove="";
	$phone = substr($phone, -10);

	if (not exists $campaignabandon_action{$org_campaign_id}) {
		populateCampaign($org_campaign_id,$dbh,'0');
	}
	$action  = $campaignabandon_action{$org_campaign_id};

	my $gmt_timestamp=get_gmt_time($timestamp);
	my $nct = 0;

	if ( $action eq "AddCampaign" )
	{
		my $query = "select campaign_type,action_value,action_value_2,abandon_time,action_value_3 from campaign where campaign_id='$org_campaign_id'";
		my $sth = $dbh->prepare($query);
		$sth->execute();

		if ( $sth->rows() ) {
			my $rs = $sth->fetchrow_hashref();
			$action_value1 = $rs->{action_value};
			$action_value2 = $rs->{action_value_2};
			$campaign_type = $rs->{campaign_type};
			$list_str=$rs->{action_value_2};
			$abandon_time=$rs->{abandon_time};
			$skill_id=$rs->{action_value_3};
		}

		if($action_value1 == $org_campaign_id){
			$skill_id=$org_skill_id;
		}

		$campaign_id = $action_value1;
		$cust_remove = (((defined($cust_remove_flag) && $cust_remove_flag) && $cust_remove_flag == 1)?"customer_$campaign_id":"customer");

		if( $interval >= $abandon_time && $action_value2 > 0)
		{

			$list_str =~ s/^,//g;
			$query = "select lead_id,phone_id,list_id from dial_Lead_lookup_$campaign_id where phone = '$phone' and list_id='$list_str' limit 1";
			$sth = $dbh->prepare($query);
			$sth->execute();

			if ($sth->rows() )
			{
				my $rs = $sth->fetchrow_hashref();
				my $lead_id = $rs->{lead_id};
				my $primary_phone_id = $rs->{phone_id};
				$list_id = $rs->{list_id};


				my $query = "select 1 from dial_Lead_lookup_$campaign_id where  lead_state = '1' and phone_state = '1' and dial_state = '1' and max_retries = '0' and total_max_retries='0' and next_call_time ='0' and phone_dial_flag='1' and lead_id = '$lead_id'";
				my $sth = $dbh->prepare($query);
				$sth->execute();

				if (!$sth->rows() )
				{
					$query = "update $cust_remove set lead_state = '1' ,call_since_last_reset = '1', last_modify_date = now() , next_call_time = '0',agentid = '0',max_retries = '0',call_disposition = NULL,agent_connect = '0' where lead_id = '$lead_id'";
					query_execute($query,$dbh,0,__LINE__);

					$query = "update extended_customer_$campaign_id set lead_state = '1',call_since_last_reset = '1', agentid = '0',preview_flag = '0',total_max_retries = '0',phone_state_1= '1',dial_state_1='1',max_retries_1='0',customer_strict='0',ringing_value='0',next_call_time='0',lead_inserted_time=now(),skill_id='$skill_id',CustUniqueId='$CustUniqueId' where lead_id = '$lead_id'";
					query_execute($query,$dbh,0,__LINE__);

					$query = "update dial_Lead_lookup_$campaign_id set lead_state = '1',phone_state = '1',dial_state = '0',max_retries = '0',total_max_retries='0',next_call_time ='0',customer_strict='0',phone_dial_flag='1',agentid='0',preview_flag='0',skill_id='$skill_id',CustUniqueId='$CustUniqueId'  where lead_id = '$lead_id'";
					query_execute($query,$dbh,0,__LINE__);
					$query = "update dial_Lead_lookup_$campaign_id set dial_state='1' where phone_id = '$primary_phone_id'";
					query_execute($query,$dbh,0,__LINE__);

					$query = "delete from dial_Lead_$campaign_id where lead_id = '$lead_id'";
					query_execute($query,$dbh,0,__LINE__);
					$query = "insert into dial_Lead_$campaign_id(phone_id,list_id,lead_id,agentid,agent_assign,lead_state,phone_state,dial_state,phone,time_zone_id,ph_type,callerid,CustUniqueId,max_retries,total_max_retries,next_call_time,customer_strict,phone_dial_flag,preview_flag,skill_id,CustUniqueId) select phone_id,list_id,lead_id,agentid,agent_assign,lead_state,phone_state,1,phone,time_zone_id,ph_type,callerid,CustUniqueId,max_retries,total_max_retries,next_call_time,customer_strict,1,preview_flag,skill_id,CustUniqueId from dial_Lead_lookup_$campaign_id where 1 and phone_id='$primary_phone_id'";
					query_execute($query,$dbh,0,__LINE__);
				}
				else{
                   $query = "update extended_customer_$campaign_id set lead_inserted_time=now() where lead_id = '$lead_id'";
				   query_execute($query,$dbh,0,__LINE__);
				}
			}
			else
			{
				$list_id = $action_value2;
				$query = "select timezone_code_id from list where list_id = '$list_id'";
				$sth = $dbh->prepare($query);
				$sth->execute();
				my $rs = $sth->fetchrow_hashref();
				my $time_zone_id = $rs->{timezone_code_id};

				$query = "insert into $cust_remove (name,phone1,list_id) values ('$customer_name','$phone','$list_id')";
				query_execute($query,$dbh,0,__LINE__);
				my $lead_id = $dbh->{q{mysql_insertid}};

				$query = "insert into extended_customer_$campaign_id (list_id,lead_id,lead_state,call_since_last_reset,phone1,tz_ph_1,phone_state_1,dial_state_1,callerid_1,next_call_time,lead_inserted_time,skill_id,CustUniqueId) values ('$list_id','$lead_id','1','1','$phone','$time_zone_id',1,1,'$callerid','$nct',now(),'$skill_id','$CustUniqueId')";
				query_execute($query,$dbh,0,__LINE__);

				$query = "insert into dial_Lead_lookup_$campaign_id (list_id,lead_id,lead_state,phone_state,dial_state,phone,time_zone_id,ph_type,callerid,max_retries,total_max_retries,next_call_time,customer_strict,phone_dial_flag,preview_flag,skill_id,CustUniqueId) values ('$list_id','$lead_id',1,1,1,'$phone','$time_zone_id',101,'$callerid',0,0,'$nct',0,1,0,'$skill_id','$CustUniqueId')";
				query_execute($query,$dbh,0,__LINE__);
				my $phone_id = $dbh->{q{mysql_insertid}};

				$query = "insert into dial_Lead_$campaign_id (phone_id,list_id,lead_id,lead_state,phone_state,dial_state,phone,time_zone_id,ph_type,callerid,max_retries,total_max_retries,next_call_time,customer_strict,phone_dial_flag,preview_flag,skill_id,CustUniqueId) values ('$phone_id','$list_id','$lead_id',1,1,1,'$phone','$time_zone_id',101,'$callerid',0,0,'$nct',0,1,0,'$skill_id','$CustUniqueId')";
				query_execute($query,$dbh,0,__LINE__);
			}
			$sth->finish;
			return 0;
		}
	}
}


#################################AbandonActon End#################################################

##########################INIT_STATUSHASH FUNCTION START##########################################
sub init_stateHash()
{
	my @params=@_;
	my $session_id=$params[0];
#initialize the hash for each session
	if (not exists $stateHash{$session_id})
	{
		$stateHash_semaphore->down;
		$stateHash{$session_id}=0;
		$stateHash_semaphore->up;
	}
}
##########################INIT_STATUSHASH FUNCTION END##########################################


##########################DEL_STATUSHASH FUNCTION START##########################################
sub del_stateHash()
{
	my @params=@_;
	my $session_id=$params[0];

	if((exists $stateHash{$session_id}) && (($stateHash{$session_id} == 30) || ($stateHash{$session_id} == 19) || ($stateHash{$session_id} == 17)))
	{
		$stateHash_semaphore->down;
		delete $stateHash{$session_id};
		$stateHash_semaphore->up;
	}
}
##########################DEL_STATUSHASH FUNCTION END##########################################

#####populateAgent() FUNCTION START#####
sub populateAgent
{
	my @params= @_;
	my $agent_id=$params[0];
	my $dbh=$params[1];
	my $temp="";
	my $query;
	my $sth;
	if(defined($agent_id))
	{
		$query="select a.agent_id,c.agent_name,b.campaign_type from agent_live as a,campaign as b,agent as c where a.campaign_id=b.campaign_id and a.agent_id=c.agent_id and a.agent_id='$agent_id'";
	}
	else{
		$query="select agent.agent_id,agent.agent_name,campaign.campaign_type from agent_live,agent,campaign where agent.agent_id=agent_live.agent_id and campaign.campaign_id=agent_live.campaign_id";
	}
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($temp = $sth->fetchrow_arrayref)
	{
		if(defined(@$temp[0])) {
			$agentHash_semaphore->down;
			$agentHash{@$temp[0]} = @$temp[1];
			$agentDialTypeHash{@$temp[0]} = @$temp[2];
			$agentHash_semaphore->up;
		}
	}
	$sth->finish;
}

#####populatecampaign() FUNCTION START#####
sub populateCampaignWrap
{
	my @params= @_;
	my $campaign_id=$params[0];
	my $dbh=$params[1];
	my $condPart= ($campaign_id?" where campaign_id='$campaign_id'":"");
	my $temp="";
	%campaignWrapHash=();
	my $query="select campaign_id,wrapupTime from campaign $condPart";
	$temp=query_execute($query,$dbh,1,__LINE__);
	if(defined(@$temp[0])) {
		$campaignWrapHash_semaphore->down;
		$campaignWrapHash{@$temp[0]}=@$temp[1];
		$campaignWrapHash_semaphore->up;
	}
}
#####populatecampaign() FUNCTION ENDS#####

#####populateIvrinfo() FUNCTION START#####
sub populateivrinfo
{
	my @params= @_;
	my $dbh=$params[0];
	my $temp="";
	%ivrinfo=();
	my $query="select ivr_node_id,ivr_node_name from ivr_node";
	$temp=query_execute($query,$dbh,1,__LINE__);
	if(defined(@$temp[0])) {
		$ivrinfo_semaphore->down;
		$ivrinfo{@$temp[0]}=@$temp[1];
		$ivrinfo_semaphore->up;
	}
}
#####populateIvrinfo() FUNCTION ENDS#####

#####populatecampaign() FUNCTION START#####
sub populateCampaign
{
	my @params= @_;
	my $campaign_id=$params[0];
	my $dbh=$params[1];
	my $campaignNameFlag=$params[2];
	my $query;
	my $sth;
	my $condPart= ($campaignNameFlag?" where campaign_name='$campaign_id'":" where campaign_id='$campaign_id'");
	my $temp="";
	if(defined($campaign_id))
	{
	 $query="select campaign_name,campaign_id,monitor_file_type,wrapupTime,screen_transfer,blended_list_lookup,abandon_action,campaign_type,perm_max_retries,conference_action,conf_wrapup_time,new_monitor_flag,max_agent,customer_lookup,sticky_flag,cust_reporting_flag from campaign $condPart";
	}
	else{
	 $query="select campaign_name,campaign_id,monitor_file_type,wrapupTime,screen_transfer,blended_list_lookup,abandon_action,campaign_type,perm_max_retries,conference_action,conf_wrapup_time,new_monitor_flag,max_agent,customer_lookup,sticky_flag,cust_reporting_flag from campaign";
	}
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($temp = $sth->fetchrow_arrayref)
	{
		if(defined(@$temp[0])) {
			if(defined($campaign_id))
			{
				if($campaignNameFlag)
				{
					$campaignNameHash_semaphore->down;
					$campaignNameHash{@$temp[0]}=@$temp[1];
					$campaignNameHash_semaphore->up;
				}
				else
				{
					$campaignHash_semaphore->down;
					$campaignHash{@$temp[1]}=@$temp[0];
					$campaignHash_semaphore->up;
				}
			}
			else
			{
				$campaignNameHash_semaphore->down;
				$campaignNameHash{@$temp[0]}=@$temp[1];
				$campaignNameHash_semaphore->up;

				$campaignHash_semaphore->down;
				$campaignHash{@$temp[1]}=@$temp[0];
				$campaignHash_semaphore->up;
			}

			$sh_mem_semaphore->down;
			$queueHash{@$temp[1]}=0;
			$sh_mem_semaphore->up;

			$fileFormatHash_semaphore->down;
			$fileFormatHash{@$temp[1]}=@$temp[2];
			$fileFormatHash_semaphore->up;

			$campaignWrapHash_semaphore->down;
			$campaignWrapHash{@$temp[1]}=@$temp[3];
			$campaignWrapHash_semaphore->up;

			$campaignScreenlHash_semaphore->down;
			$campaignScreenHash{@$temp[1]}=@$temp[4];
			$campaignScreenlHash_semaphore->up;

			$campaignblendedlookup_semaphore->down;
			$campaignblendedlookup{@$temp[1]}=@$temp[5];
			$campaignblendedlookup_semaphore->up;

			$campaignabandon_action_semaphore->down;
			$campaignabandon_action{@$temp[1]}=@$temp[6];
			$campaignabandon_action_semaphore->up;

			$campaigntype_semaphore->down;
			$campaigntype{@$temp[1]}=@$temp[7];
			$campaigntype_semaphore->up;

			$campaignmax_semaphore->down;
			$campaignmax{@$temp[1]}=@$temp[8];
			$campaignmax_semaphore->up;

			$campaign_conference_semaphore->down;
			$campaign_conference{@$temp[1]}=@$temp[9];
			$campaign_conference_semaphore->up;

			$campaign_conf_WrapHash_semaphore->down;
			$campaign_conf_WrapHash{@$temp[1]}=@$temp[10];
			$campaign_conf_WrapHash_semaphore->up;

			$new_monitor_flagHash_semaphore->down;
			$new_monitor_flagHash{@$temp[1]}=@$temp[11];
			$new_monitor_flagHash_semaphore->up;


			$camp_agentcount_semaphore->down;
			$camp_agentcount{@$temp[1]}=@$temp[12];
			$camp_agentcount_semaphore->up;

			$customerlookup_semaphore->down;
			$customerlookup{@$temp[1]}=@$temp[13];
			$customerlookup_semaphore->up;

			$sticky_campaign_semaphore->down;
			$sticky_campaignhash{@$temp[1]}=@$temp[14];
			$sticky_campaign_semaphore->up;

			$cust_reporting_flagHash_semaphore->down;
			$cust_reporting_flagHash{@$temp[1]}=@$temp[15];
			$cust_reporting_flagHash_semaphore->up;
		}
	} 
	$sth->finish;
}
#####populatecampaign() FUNCTION ENDS#####
####populateDepatment() Frunction start###
sub populateDepartment
{
	my @params= @_;
        my $department_name=$params[0];
        my $dbh=$params[1];
        my $query;
        my $sth;
		%departmenthash=();
		$query = "select department_id,department_name from department where department_name='$department_name'";
		$sth=$dbh->prepare($query);
		$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
		while ($retval = $sth->fetchrow_arrayref) 
		{
			$departmenthash_semaphore->down;
			$departmenthash{@$retval[1]} = @$retval[0];
			$departmenthash_semaphore->up;
		}
	    $sth->finish;
}
###############populateskill()FUNCTION START###
sub populateSkill
{
	my @params= @_;
	my $dbh=$params[0];
	my $query;
	my $sth;
	my $retval;
	%campaignSkillHash=();
	$query="select skill_id,skill_name,campaign_id from skills";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($retval = $sth->fetchrow_arrayref) {
		$campaignSkillHash_semaphore->down;
		$campaignSkillHash{@$retval[0]."_".@$retval[2]}=@$retval[1];
		$campaignSkillHash_semaphore->up;
	}
	$sth->finish;
}
############populateskill()FUNCTION ENDS######

############populateprovider##################
sub populateprovider
{
	my @params= @_;
	my $dbh=$params[0];
	my $query;
	my $sth;
	my $retval;
	%providernameHash=();
    %pricalleridHash=();
	$query="select zap_id,provider_name,Caller_id from zap";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($retval = $sth->fetchrow_arrayref) {

		$providernameHash_semaphore->down;
		@$retval[0] =~ s/ZAP/Zap/g;
		$providernameHash{@$retval[0]}=@$retval[1];
		$providernameHash_semaphore->up;

		$pricalleridHash_semaphore->down;
		$pricalleridHash{@$retval[1]}=@$retval[2];
		$pricalleridHash_semaphore->up;

	}
	$sth->finish;
}

############populateprovider ENDS#############

############sip populateprovider##################
sub sip_populateprovider
{
	my @params= @_;
	my $dbh=$params[0];
	my $query;
	my $sth;
	my $retval;
	%sip_providernameHash=();
	%sip_id_providernameHash=();
	$query="select b.sip_gateway_name,b.ipaddress,a.sip_id from sip as a,sip_gateway as b where a.sip_gateway_name=b.sip_gateway_name";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($retval = $sth->fetchrow_arrayref) {
		$sip_providernameHash_semaphore->down;
		$sip_providernameHash{@$retval[1]}=@$retval[0];
		$sip_providernameHash_semaphore->up;

		$sip_id_providernameHash_semaphore->down;
		$sip_id_providernameHash{@$retval[2]}=@$retval[0];
		$sip_id_providernameHash_semaphore->up;
	}
	$sth->finish;
}

############sip populateprovider ENDS#############

###############populateCsat()FUNCTION START###
sub populateCsat
{
	my @params= @_;
	my $dbh=$params[0];
	my $query;
	my $sth;
	my $retval;
	my @variables=();
	%campaignCsatHash=();
	$query="select campaign_id,start_time,end_time,call_duration,time_rule_flag,ip_address,rule_type from outbound_csat where rule_type='1'";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

	while ($retval = $sth->fetchrow_arrayref) {
		@variables=split(/,/,@$retval[0]);
		my $j=0;
		foreach(@variables){
			$campaignCsatHash_semaphore->down;
			$campaignCsatHash{$variables[$j]}=@$retval[1]."_".@$retval[2]."_".@$retval[3]."_".@$retval[4]."_".@$retval[5]."_".@$retval[6];
			$campaignCsatHash_semaphore->up;
			$j++;
		}
	}
	$sth->finish;
}
############populateCsat()FUNCTION ENDS######

################populateCsativr()FUNCTION START###

sub populateCsativr
{
	my @params= @_;
	my $dbh=$params[0];
	my $query;
	my $sth;
	my $retval;
	my @variables=();
	%ivrCsatHash=();
	$query="select ivr_id,start_time,end_time,call_duration,time_rule_flag,ip_address,out_dial_campaign,rule_type from outbound_csat where rule_type='0'";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

	while ($retval = $sth->fetchrow_arrayref) {
		@variables=split(/,/,@$retval[0]);
		my $k=0;
		foreach(@variables){
			$ivrCsatHash_semaphore->down;
			$ivrCsatHash{$variables[$k]}=@$retval[1]."_".@$retval[2]."_".@$retval[3]."_".@$retval[4]."_".@$retval[5]."_".@$retval[6]."_".@$retval[7];
			$ivrCsatHash_semaphore->up;
			$k++;
		}
	}
	$sth->finish;
}
############populateCsativr()FUNCTION ENDS######
#---POPULATE MONITOR FILE FORMAT Manual FOR CAMPAIGN-----
sub populateMonitorFileFormatManual
{
	my @params= @_;
	my $campaign_id=$params[0];
	my $dbh=$params[1];
	my $condPart= ($campaign_id?" and campaign_id='$campaign_id'":"");
	my $temp="";
	my $fileFormatFlag = 0;
	my $query;
	my $sth;
	%MonitorFileFormatManual=();

	if(defined($campaign_id)) {
		$query="select campaign_id , manual_voicefile_format ,manual_fieldRef from voicefile_template where 1 $condPart";
	}
	else {
		$query="select campaign_id , manual_voicefile_format ,manual_fieldRef from voicefile_template";
	}
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($temp = $sth->fetchrow_arrayref)
	{
		$MonitorFileFormatManual_semaphore->down;
		if(defined(@$temp[1]) && (@$temp[1] !~ /^$/ && @$temp[1] !~ /^[\s]+$/)){
			$MonitorFileFormatManual{@$temp[0]}=@$temp[2]."##".@$temp[1];
			$fileFormatFlag=1;
		}
		$MonitorFileFormatManual_semaphore->up;
	}
	if (defined($campaign_id) && $campaign_id && $fileFormatFlag==0 && exists $MonitorFileFormatManual{$campaign_id}) {
		$MonitorFileFormatManual_semaphore->down;
		$MonitorFileFormatManual{$campaign_id}="";
		$MonitorFileFormatManual_semaphore->up;
	}

	$sth->finish;
}
#---END POPULATE MONITOR FILE FORMAT FOR CAMPAIGN-----

#----POPULATE MONITOR FILE FORMAT Lead FOR CAMPAIGN--------
sub populateMonitorFileFormatLead
{
	my @params= @_;
	my $campaign_id=$params[0];
	my $dbh=$params[1];
	my $condPart= ($campaign_id?" and campaign_id='$campaign_id'":"");
	my $temp="";
	my $fileFormatFlag=0;
	my $sth;
	my $query;
	%MonitorFileFormatLead=();

	if(defined($campaign_id)) {
		$query="select campaign_id,lead_voicefile_format,lead_fieldRef,cust_fields,customer_fields from voicefile_template where 1 $condPart";
	}
	else {
		$query="select campaign_id,lead_voicefile_format,lead_fieldRef,cust_fields,customer_fields from voicefile_template";
	}
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($temp = $sth->fetchrow_arrayref)
	{
		$MonitorFileFormatLead_semaphore->down;
		if(defined(@$temp[1]) && (@$temp[1] !~ /^$/ && @$temp[1] !~ /^[\s]+$/)){
			$MonitorFileFormatLead{@$temp[0]} = @$temp[2]."##".@$temp[1]."##".@$temp[3]."##".@$temp[4];
			$fileFormatFlag=1;
		}
		$MonitorFileFormatLead_semaphore->up;
	}
	$sth->finish;

	if (defined($campaign_id) && $campaign_id && $fileFormatFlag==0 && exists $MonitorFileFormatLead{$campaign_id}) {
		$MonitorFileFormatLead_semaphore->down;
		$MonitorFileFormatLead{$campaign_id}="";
		$MonitorFileFormatLead_semaphore->up;
	}	
}

#---------END POPULATE MONITOR FILE FORMAT Lead FOR CAMPAIGN--------------------
#---POPULATE REPORTING FORMAT Manual FOR CAMPAIGN-----
sub populateReportingFormatManual
{
	my @params= @_;
	my $campaign_id=$params[0];
	my $dbh=$params[1];
	my $condPart= ($campaign_id?" and campaign_id='$campaign_id'":"");
	my $temp="";
	my $fileFormatFlag = 0;
	%ReportingFormatManual=();

	if(defined($campaign_id)) {
		$query="select campaign_id,manual_reporting_format,manual_fieldRef from voicefile_template where 1 $condPart";
	}
	else {
		$query="select campaign_id,manual_reporting_format,manual_fieldRef from voicefile_template";
	}
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($temp = $sth->fetchrow_arrayref)
	{
		$ReportingFormatManual_semaphore->down;
		if(defined(@$temp[1]) && (@$temp[1] !~ /^$/ && @$temp[1] !~ /^[\s]+$/)){
			$ReportingFormatManual{@$temp[0]}=@$temp[2]."##".@$temp[1];
			$fileFormatFlag=1;
		}
		$ReportingFormatManual_semaphore->up;
	}

	if (defined($campaign_id) && $campaign_id && $fileFormatFlag==0 && exists $ReportingFormatManual{$campaign_id}) {
		$ReportingFormatManual_semaphore->down;
		$ReportingFormatManual{$campaign_id}="";
		$ReportingFormatManual_semaphore->up;
	}

	$sth->finish;
}
#---END POPULATE REPORTING FORMAT FOR CAMPAIGN-----

#----POPULATE REPORTING FORMAT Lead FOR CAMPAIGN--------
sub populateReportingFormatLead
{
	my @params= @_;
	my $campaign_id=$params[0];
	my $dbh=$params[1];
	my $condPart= ($campaign_id?" and campaign_id='$campaign_id'":"");
	my $temp="";
	my $fileFormatFlag=0;
	%ReportingFormatLead=();

	if(defined($campaign_id)) {
		$query="select campaign_id,lead_reporting_format,lead_fieldRef,cust_fields,customer_fields from reporting_template where 1 $condPart";
	}
	else {
		$query="select campaign_id,lead_reporting_format,lead_fieldRef,cust_fields,customer_fields from reporting_template";
	}
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
	while ($temp = $sth->fetchrow_arrayref)
	{
		$ReportingFormatLead_semaphore->down;
		if(defined(@$temp[1]) && (@$temp[1] !~ /^$/ && @$temp[1] !~ /^[\s]+$/)){
			$ReportingFormatLead{@$temp[0]} = @$temp[2]."##".@$temp[1]."##".@$temp[3]."##".@$temp[4];
			$fileFormatFlag=1;
		}
		$ReportingFormatLead_semaphore->up;
	}
	$sth->finish;

	if (defined($campaign_id) && $campaign_id && $fileFormatFlag==0 && exists $ReportingFormatLead{$campaign_id}) {
		$ReportingFormatLead_semaphore->down;
		$ReportingFormatLead{$campaign_id}="";
		$ReportingFormatLead_semaphore->up;
	}	
}

#---------END POPULATE REPORTING FORMAT Lead FOR CAMPAIGN----#######
#---------Populate Logout time--------------------------------------------------
sub populatelogout
{
    my @params= @_;
	my $dbh=$params[0];
	my $campaign_id=$params[1];
	my $query;
	my $sth;
	my $retval;
	%logoutagent=();

	$query="select campaign_id,unix_timestamp((concat(curdate(),' ',local_start_time) + INTERVAL TIME_TO_SEC(local_end_time) SECOND)) as endtime from campaign where campaign_id='$campaign_id' and logout_flag='1'";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
    while ($retval = $sth->fetchrow_arrayref) {
	    $logoutagent_semaphore->down;
		$logoutagent{@$retval[0]}=@$retval[1];
		$logoutagent_semaphore->up;
	}
	$sth->finish;
}

#---------Populate Logout time End ---------------------------------------------

#---get the current date and time and epoch for logging call lengths and datetimes---
sub get_dateformat_monitorfilename
{
	my @params=@_;
	my $date_format="";
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(gettimeofday());
	my $newYear;
	$year = ($year + 1900);
	$mon++;
	if ($mon < 10) {$mon = "0$mon";}
	if ($mday < 10) {$mday = "0$mday";}
	if ($hour < 10) {$hour = "0$hour";}
	if ($min < 10) {$min = "0$min";}
	if ($sec < 10) {$sec = "0$sec";}

	if($params[0] =~ /DDMMYYYY/i) {
		$date_format =$mday.$mon.$year;
	}
	elsif($params[0] =~ /DDMMYY/i) {
		$newYear = substr($year,2);
		$date_format =$mday.$mon.$newYear;
	}
	elsif($params[0] =~ /DD_MM_YYYY_HH_MM_SS/i) {
		$date_format =$mday."_".$mon."_".$year."_".$hour."_".$min."_".$sec;
	}
	elsif($params[0] =~ /DD_MM_YYYY_HH_MM/i) {
		$date_format =$mday."_".$mon."_".$year."_".$hour."_".$min;
	}
	elsif($params[0] =~ /DD_MM_YYYY/i) {
		$date_format =$mday."_".$mon."_".$year;
	}

	return $date_format;
}
#----get_dateformat_monitorfilename-------
#----Failsafe Agent Logout-----------------
sub failsafeLogout
{
	my $dbh;
	my $agent_id;
	my $query;
	my $returnvar;
	my $retval;
	my $table_name;
	my $time;
	my $check_conference='';
	my $agent_session_id_cond='';
	my @params = @_;

	$dbh=$params[0];
	$retval=$params[1];
	$agent_id=$params[2];
	$table_name=$params[3];
	$time=$params[4];
	$check_conference = $params[5];
	my $agent_confVar=1;
	my $preview_pauseDuration='0';
	my $previewDuration='0';
	my $logval="";
	my $confDuration =0;
	my $failsafetime=get_time_now();

	my $call_state= ((defined @$retval[0])?@$retval[0]:"");
	my $pause_state= ((defined @$retval[1])?@$retval[1]:"");
	my $wrap_state= ((defined @$retval[2])?@$retval[2]:"");
	my $dialer_mode= ((defined @$retval[3])?@$retval[3]:'NA');
	my $last_login_time = ((defined @$retval[5])?@$retval[5]:"$table_name");
	my $pauseDuration = ((defined @$retval[6])?@$retval[6]:"");
	my $pauseStartTime = ((defined @$retval[7])?@$retval[7]:"0");
	my $pauseEndTime = ((defined @$retval[8])?@$retval[8]:"$pauseStartTime");
	my $totalCalls = ((defined @$retval[9])?@$retval[9]:"0");
	my $last_activity_time = ((defined @$retval[10])?@$retval[10]:"0");
	my $logout_time = ((defined @$retval[11])?@$retval[11]:"$failsafetime");
	my $agent_session_id = ((defined @$retval[12])?@$retval[12]:"0.00000");
	my $wait_duration = ((defined @$retval[13])?@$retval[13]:"0");
	my $ready_time = ((defined @$retval[14])?@$retval[14]:"0");
	my $tmpLogintime;
	if($pause_state == 1) {
		$pauseDuration = $pauseDuration + ($pauseEndTime - $pauseStartTime);
	}
	if($check_conference == 1) {
		$query="update agent set staticIP='' where agent_id='$agent_id'";
		query_execute($query,$dbh,0,__LINE__);
#delete the entry from agent wrapup hash when agent loggs off
		if ( @{$final_wrap_array[$agent_id][0]})
		{
			splice(@final_wrap_array,$agent_id,1);
		}

		$wrapup_semaphore->down;
		delete $agent_wrapup{$agent_id};        #delete element from hash
		delete $call_duration_array1[$agent_id];
		delete $call_duration_array2[$agent_id];
		delete $call_duration_array3[$agent_id];
		delete $update_avg_block1[$agent_id];   #delete element from UAB array
		delete $update_avg_block2[$agent_id];
		delete $update_avg_block3[$agent_id];
		delete $predict_state_after1[$agent_id];
		delete $predict_state_after2[$agent_id];
		delete $predict_state_after3[$agent_id];
		delete $state_changed[$agent_id];

		$wrapup_semaphore->up;
#to unpause the agent before logging off, asked by bhishm to send this packet
		my $shared_key = $agent_id;
		$sendTn_semaphore->down;
		$sendTnHash{$shared_key} = "unpause";
		$sendTn_semaphore->up;

	}
	if(defined($agent_session_id) && ($agent_session_id !~ /^$/ && $agent_session_id !~ /^[\s]+$/)) {
		$agent_session_id_cond=" and agent_session_id=$agent_session_id";
		my @returnvarSess=split('\.',$agent_session_id);
		$tmpLogintime = $returnvarSess[0];
	}

	$query="delete from agent_live where agent_id='$agent_id'";
	query_execute($query,$dbh,0,__LINE__);

	$query="delete from crm_live where agent_id='$agent_id'";
	query_execute($query,$dbh,0,__LINE__);

	$query="delete from crm_hangup_live where agent_id='$agent_id'";
	query_execute($query,$dbh,0,__LINE__);

	$query="delete from callProgress where agent_id='$agent_id'";
	query_execute($query,$dbh,0,__LINE__);

	$query="delete from customer_live where agent_id='$agent_id'";
	query_execute($query,$dbh,0,__LINE__);

	if(defined($dialer_mode) && ($dialer_mode =~ "PREVIEW"))
	{
		$query="select dialerType from campaign as a, agent as b where a.campaign_id=b.campaign_id and b.agent_id='$agent_id'";
		$returnvar=query_execute($query,$dbh,1,__LINE__);
		my $dialerType = @$returnvar[0];

		if($dialerType !~ $dialer_mode) {
			$query="update agent_state_analysis_$last_login_time set agent_state='PREVIEW_N_$dialerType',call_end_date_time='$time' where agent_id='$agent_id' and agent_state='PREVIEW'".$agent_session_id_cond;
			query_execute($query,$dbh,0,__LINE__);

			$query =~ s/$last_login_time/current_report/i;
			query_execute($query,$dbh,0,__LINE__);
		}
	}

	if($pauseDuration) {
		$query="update agent_state_analysis_$last_login_time set agent_state='BREAK_N_BACK',call_end_date_time='$time' where agent_id='$agent_id' and agent_state='BREAK'".$agent_session_id_cond;
		query_execute($query,$dbh,0,__LINE__);

		$query =~ s/$last_login_time/current_report/i;
		query_execute($query,$dbh,0,__LINE__);
	}

	$query ="select sum(unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time)) as pauseDuration,sum(if(dailer_mode='PREVIEW',unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time),0 )) as preview_pause_duraiton from agent_state_analysis_current_report where agent_id='$agent_id' and break_type not in ('JoinedConference') and agent_state='BREAK_N_BACK'".(($agent_session_id_cond =~ /^$/ || $agent_session_id_cond =~ /^[\s]+$/)?" and entrytime between '$tmpLogintime' and unix_timestamp() ":"").$agent_session_id_cond ;
	$logval=query_execute($query,$dbh,1,__LINE__);
	$pauseDuration = ((defined @$logval[0])?@$logval[0]:"0");
	$preview_pauseDuration = ((defined @$logval[1])?@$logval[1]:"0");

	$query ="select sum(unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time)) as previewDuration from agent_state_analysis_current_report where agent_id='$agent_id'  and (agent_state='PREVIEW_N_PROGRESSIVE' or agent_state='PREVIEW_N_PREDICTIVE')".(($agent_session_id =~ /^$/ || $agent_session_id =~ /^[\s]+$/)?" and entrytime between '$tmpLogintime' and unix_timestamp()":"").$agent_session_id_cond ;
	$logval=query_execute($query,$dbh,1,__LINE__);
	$previewDuration = ((defined @$logval[0])?@$logval[0]:"0");

	if(defined($agent_confVar) && ($agent_confVar !~ /^$/ && $agent_confVar !~ /^[\s]+$/)  && $agent_confVar != 0)
	{
		$query="select sum(unix_timestamp(call_end_date_time) - unix_timestamp(call_start_date_time)) as conf_duration from current_report where agent_id = '$agent_id' and entrytime between '$tmpLogintime' and unix_timestamp()  and  agent_id = cust_ph_no";
		$logval=query_execute($query,$dbh,1,__LINE__);
		$confDuration = ((defined @$logval[0])?@$logval[0]:"0");
	}

	$query="update agent_state_analysis_$table_name set agent_state='LOGIN_N_LOGOUT',call_end_date_time='$logout_time',call_state='$call_state',pause_state='$pause_state',wrap_state='$wrap_state',dailer_mode='$dialer_mode',pauseDuration='$pauseDuration',totalCall='$totalCalls',ready_time='$ready_time',wait_duration='$wait_duration',conf_duration='$confDuration',preview_pauseDuration='$preview_pauseDuration',preview_time='$previewDuration' where agent_id='$agent_id' and agent_state='LOGIN' ".$agent_session_id_cond;
	query_execute($query,$dbh,0,__LINE__);

#Adding information to Agent State Analysis current report
	check_cview($query,$dbh,$table_name,2);
	$query =~ s/$table_name/current_report/i;
	query_execute($query,$dbh,0,__LINE__);

	$query="update agent set last_logoff_time='$logout_time',last_agent_session_id='$agent_session_id' where agent_id='$agent_id'";
	query_execute($query,$dbh,0,__LINE__);
}
#----End Failsafe Agent Logout---------------


#----Disposition Based Calling Rule-------------
sub setDisposition
{
	my $sth;
	my $dbh;
	my $campaign_id=0;
	my $list_id=0;
	my $lead_id;
	my $rule_id;
	my $dialer_var;
	my $disposition="";
	my $strict_flag=0;
	my $transfer_flag=0;
	my $timestamp=time();
	my $query;
    my $custphno;

	my @params = @_;
	$dbh=$params[0];
	$lead_id=$params[1];
	$campaign_id=$params[2];
	$list_id=$params[3];
	$dialer_var=$params[4];
	$disposition=$params[5];
	$strict_flag=$params[6];
	$custphno=$params[7];

	my @dialer_variables=split(/,/,$dialer_var);
	my $phone_type = $dialer_variables[0];
	my $next_call_time = $dialer_variables[3];
	my $dialer_strict = $dialer_variables[6];
	my $lead_retry_count = (defined($dialer_variables[1])?$dialer_variables[1]:"0");
	my $phone_retry_count = (defined($dialer_variables[2])?$dialer_variables[2]:"0");
	my $agent_id = (defined($dialer_variables[7])?$dialer_variables[7]:"");
	my $lead_attempt_count=(defined($dialer_variables[8])?$dialer_variables[8]:"0");
	my $phone_attempt_count=(defined($dialer_variables[9])?$dialer_variables[9]:"0");
	my $per_day_mx_retry_count=(defined($dialer_variables[19])?$dialer_variables[19]:"0");
	my $lead_retry_count_inc = $lead_retry_count +1;
	my $lead_attempt_count_inc = $lead_attempt_count + 1;
	my $per_day_mx_retry_count_inc = $per_day_mx_retry_count + 1;
	my $next_phone_type = 0;
	my $finish_lead=0;
	my $finish_phone=0;
	my $finish_dial=0;
	my $gmt_timestamp="";
	my $local_timestamp="";
	my $dialer_remarks="";
	my $phone_dial=0;
	my $update_phone_dial=0;
	my $update_new_phone_dial=0;
	my $phone_rule_str;
	my $nct_timestamp="";
	my %phonehash=();
	my $result;
	my @phone_num_type=();
	$lead_retry_count = $lead_retry_count + 1;
	my $update_dialstateflag =($lead_attempt_count<=9?"1":"0");

	$query = "select phone,ph_type from dial_Lead_lookup_$campaign_id where lead_id = '$lead_id'";
	$sth=$dbh->prepare($query);
	$sth->execute() or error_handler($DBI::errstr,__Line__,$query);
	while($result=$sth->fetchrow_arrayref)
	{
		$phonehash{@$result[1]}=@$result[0];
	}
	$sth->finish();

	if($disposition ne "answered") {
		if($dialer_strict)
		{
			my $campDisp=$campaign_id."_".$disposition;
			my $campRetries=$campaign_id."_max_retries";
			if($strictCalling_dispositionValue{"$campRetries"} > $lead_retry_count){
				if($strictCalling_dispositionAction{"$campDisp"} eq "nct") {
					my $strict_retry_time =  $strictCalling_dispositionValue{"$campDisp"}*60 ;
					$gmt_timestamp=get_gmt_time($timestamp);
					$local_timestamp=$timestamp + $strict_retry_time;
					$gmt_timestamp=$gmt_timestamp + $strict_retry_time;
					$nct_timestamp = $local_timestamp.'@@  NCT set | Campaign Strict DispRule | '.$phone_type;
					$dialer_remarks = "NCT set | Campaign Strict DispRule | $phone_type";

					$query="update extended_customer_$campaign_id set dial_state_".($phone_type-100)."='1',max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = '$lead_retry_count_inc',num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
					query_execute($query,$dbh,0,__LINE__);

					if ($update_dialstateflag == 1) {
						$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',phone_state_$lead_attempt_count='1',dial_state_$lead_attempt_count='1',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,last_lead_status='0' where lead_id='$lead_id'";
						query_execute($query, $dbh,0, __LINE__);
					}


					$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc where lead_id='$lead_id'";
					query_execute($query,$dbh,0,__LINE__);

					$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc where lead_id='$lead_id'";
					query_execute($query,$dbh,0,__LINE__);
				}
				elsif($strictCalling_dispositionAction{"$campDisp"} eq "finish_lead") {
					$finish_lead=1;
					$local_timestamp=0;
					$nct_timestamp = $local_timestamp.'@@ Finished | Campaign Strict DispRule';
				}
				elsif($strictCalling_dispositionAction{"$campDisp"} eq "DNC") {
					$finish_lead=1;
					$local_timestamp=0;
					$nct_timestamp = $local_timestamp.'@@ Finished | Campaign Strict DispRule';
				}
			}
			else {
				my $gmt_timestamp=get_gmt_time($timestamp);
				$local_timestamp=$timestamp;
				$gmt_timestamp=$gmt_timestamp;
				$query="update extended_customer_$campaign_id set max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = total_max_retries +1,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
				query_execute($query,$dbh,0,__LINE__);

				$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc where lead_id='$lead_id'";
				query_execute($query,$dbh,0,__LINE__);

				$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc where lead_id='$lead_id'";
				query_execute($query,$dbh,0,__LINE__);

				$finish_lead=1;
				$local_timestamp=0;
				$nct_timestamp = $local_timestamp.'@@ Finished | Campaign Strict DispRule';
				$disposition = "Finished | Campaign Strict DispRule";

				if ($update_dialstateflag == 1) {
					$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',phone_state_$lead_attempt_count='0',dial_state_$lead_attempt_count='0',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_state='0',lead_attempt_count=$lead_attempt_count+1,last_lead_status='0' where lead_id='$lead_id'";
					query_execute($query, $dbh,0, __LINE__);
				}
			}
		}
		else {
#if (not exists $listRules{"$list_id"}) {
	populate_disposition_hash($dbh);
#}
	$rule_id=$listRules{"$list_id"};
	if($rule_id =~ /B/)
	{
		$rule_id =~s/_//g;
		$rule_id =~ s/[a-zA-Z]//g;
		my $switch_and_recyle_flag = $simpleRuleValue{$rule_id};
		my @switch_recyle_array = split(/##/,$switch_and_recyle_flag);
		my $switch_after_attempt_count = $switch_recyle_array[0];
		my $recycle_flag = $switch_recyle_array[1];
		my $rule_retry_count=$dispositionValue{"$rule_id"."_"."total_max_retry"};

		my $fetch_rule_string=$rule_id."_".$disposition."_".($phone_retry_count + 1);
		my $phone_retry_time=$basic_rule_disposition_time_value_hash{$fetch_rule_string} * 60;

		$gmt_timestamp=get_gmt_time($timestamp) + $phone_retry_time;
		$local_timestamp=$timestamp + $phone_retry_time;
		$nct_timestamp = $local_timestamp;

		my $basic_disposition_dialer = $basic_rule_disposition_action_hash{$fetch_rule_string};
		if($rule_retry_count > $lead_retry_count)
		{
			my $recycle_ph_type = 101;
			if($phone_retry_count + 1 >= $switch_after_attempt_count)
			{
				$query="select ph_type,max_retries,phone_state from dial_Lead_lookup_$campaign_id where lead_id ='$lead_id' and phone_state = '1' order by ph_type";
				$sth=$dbh->prepare($query);
				$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);

				my $ph_min_count = 0;
				while (my $phone_num_type = $sth->fetchrow_arrayref) {
					if ($ph_min_count == 0) {
						$recycle_ph_type = @$phone_num_type[0];
						$ph_min_count++;
					}
					if((@$phone_num_type[0]>$phone_type) && @$phone_num_type[2] ) {
						$next_phone_type = @$phone_num_type[0];
						last;
					}
				}
				$sth->finish;

				if($next_phone_type != 0){
					$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$next_phone_type',1,0) where lead_id='$lead_id'";
					query_execute($query, $dbh,0, __LINE__);

					$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$next_phone_type',1,0) where lead_id='$lead_id'";
					query_execute($query,$dbh,0,__LINE__);

					$query="update extended_customer_$campaign_id set max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = total_max_retries +1,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=$lead_retry_count_inc".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
					query_execute($query,$dbh,0,__LINE__);
					$nct_timestamp = $local_timestamp.'@@ NCT set | '.$rule_id." | ".$next_phone_type;
					$dialer_remarks="NCT set | $rule_id |$next_phone_type";
					
					if ($update_dialstateflag == 1) {
						$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,last_lead_status='0' where lead_id='$lead_id'";
						query_execute($query, $dbh,0, __LINE__);
					}
				}
				else
				{
					if($recycle_flag)
					{
						$next_phone_type = $recycle_ph_type ;
						$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$next_phone_type',1,0) where lead_id='$lead_id'";
						query_execute($query, $dbh,0, __LINE__);

						$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$next_phone_type',1,0) where lead_id='$lead_id'";
						query_execute($query,$dbh,0,__LINE__);

						$query="update extended_customer_$campaign_id set max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = total_max_retries +1,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=$lead_retry_count_inc".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
						query_execute($query,$dbh,0,__LINE__);
						$nct_timestamp = $local_timestamp.'@@ NCT set | '.$rule_id." | ".$next_phone_type;
						$dialer_remarks="NCT set | $rule_id | $next_phone_type";

						if ($update_dialstateflag == 1) {
							$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,last_lead_status='0' where lead_id='$lead_id'";
							query_execute($query, $dbh,0, __LINE__);
						}

					}
					else
					{
						$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,lead_state='0',next_call_time='$gmt_timestamp' where lead_id='$lead_id'";
						query_execute($query, $dbh,0, __LINE__);

						$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,lead_state='0',next_call_time='$gmt_timestamp' where lead_id='$lead_id'" ;
						query_execute($query, $dbh,0, __LINE__);

						$query="update extended_customer_$campaign_id set phone_state_".($phone_type-100)." ='0',dial_state_".($phone_type-100)."='0',max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = $lead_retry_count_inc,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"").",lead_state='0' where lead_id='$lead_id'";
						query_execute($query, $dbh,0, __LINE__);
						$local_timestamp = 0;
						$nct_timestamp = $local_timestamp.'@@ Finished | '.$rule_id;
						$dialer_remarks = "Finished | $rule_id";

						if ($update_dialstateflag == 1) {
							$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',phone_state_$lead_attempt_count='0',dial_state_$lead_attempt_count='0',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,lead_state='0',last_lead_status='0' where lead_id='$lead_id'";
							query_execute($query, $dbh,0, __LINE__);
						}
					}
				}
			}
			else
			{
				$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,next_call_time='$gmt_timestamp' where lead_id='$lead_id'";
				query_execute($query, $dbh,0, __LINE__);

				$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,next_call_time='$gmt_timestamp' where lead_id='$lead_id'" ;
				query_execute($query, $dbh,0, __LINE__);

				$query="update extended_customer_$campaign_id set phone_state_".($phone_type-100)." ='0',dial_state_".($phone_type-100)."='0',max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = $lead_retry_count_inc,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
				query_execute($query, $dbh,0, __LINE__);
				$nct_timestamp = $local_timestamp.'@@ NCT set  | '.$rule_id." | ".$phone_type;
				$dialer_remarks="NCT set  | $rule_id | $phone_type";

				if ($update_dialstateflag == 1) {
					$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,last_lead_status='0' where lead_id='$lead_id'";
					query_execute($query, $dbh,0, __LINE__);
				}
			}
		}
		else
		{
			$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,lead_state='0',next_call_time='$gmt_timestamp' where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

##here lead_state = 0 when lead_attemp_count is compelete##
			$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,lead_state='0',next_call_time='$gmt_timestamp' where lead_id='$lead_id'" ;
			query_execute($query, $dbh,0, __LINE__);

			$query="update extended_customer_$campaign_id set phone_state_".($phone_type-100)." ='0',dial_state_".($phone_type-100)."='0',max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = $lead_retry_count_inc,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"").",lead_state='0' where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);
			$local_timestamp = 0;
			$nct_timestamp = $local_timestamp.'@@ Finished | '.$rule_id;
			$dialer_remarks = "Finished | $rule_id";

			if ($update_dialstateflag == 1) {
				$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,phone_state_$lead_attempt_count='0',dial_state_$lead_attempt_count='0',lead_state='0',last_lead_status='0' where lead_id='$lead_id'";
				query_execute($query, $dbh,0, __LINE__);
			}
		}
		return $nct_timestamp;
	}
	else
	{
		$rule_id=$listRules{"$list_id"};
		$rule_id =~s/_//g;
		$rule_id =~ s/[a-zA-Z]//g;
		my $rule_retry_count=$dispositionValue{"$rule_id"."_"."total_max_retry"};
		$phone_rule_str =$rule_id."_".$phone_type;

		my $phone_max_retry_value =$phoneMaxValue{"$phone_rule_str"};
		my $phone_max_retry_action =$phoneMaxValue{$phone_rule_str."_max_retry_action"};

		$phone_rule_str=$phone_rule_str."_".$disposition."_".$phone_retry_count;
		my $phone_retry_time =  $phoneRetryTime{"$phone_rule_str"}*60 ;

		my $phone_retry_rule = $phoneRetryRule{"$phone_rule_str"};
		my $phone_retry_value = $phoneRetryValue{"$phone_rule_str"};
		if($rule_retry_count > $lead_retry_count){
			if($phone_max_retry_value > $phone_retry_count) {
				if($phone_retry_rule eq 'phone') {
					$phone_dial=1;
					my  $phone_number=$phonehash{$phone_retry_value};
					$next_phone_type=$phone_retry_value;
					if(!defined($phone_number)||($phone_number eq 'NULL' || $phone_number eq 'null'))
					{
						$phone_rule_str='';
						$rule_retry_count=$rule_retry_count+1;
						$phone_rule_str =$rule_id."_".$phone_retry_value;
						$phone_rule_str=$phone_rule_str."_".$disposition."_".$phone_retry_count;
						$phone_retry_value = $phoneRetryValue{"$phone_rule_str"};
						$next_phone_type=$phone_retry_value;
						$gmt_timestamp=get_gmt_time($timestamp) + $phone_retry_time;
						$local_timestamp=$timestamp + $phone_retry_time;
						$nct_timestamp = $local_timestamp;

						$query="update extended_customer_$campaign_id set max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = total_max_retries +1,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=$lead_retry_count_inc".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
						query_execute($query,$dbh,0,__LINE__);

						$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$phone_type',1,dial_state) where lead_id='$lead_id'";
						query_execute($query,$dbh,0,__LINE__);

						$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$phone_type',1,dial_state) where lead_id='$lead_id'";
						query_execute($query,$dbh,0,__LINE__);
					}
					$gmt_timestamp=get_gmt_time($timestamp) + $phone_retry_time;
					$local_timestamp=$timestamp + $phone_retry_time;
					$nct_timestamp = $local_timestamp.'@@ NCT set | '.$rule_id." | ".$phone_type;
					$dialer_remarks = "NCT set | $rule_id | $phone_type";
					
					if ($update_dialstateflag == 1) {
						$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,last_lead_status='0' where lead_id='$lead_id'";
						query_execute($query, $dbh,0, __LINE__);
					}
				}
				elsif($phone_retry_rule eq 'nct') {
					$phone_dial=0;
					$update_phone_dial=1;
					$next_phone_type=$phone_type;
					$gmt_timestamp=get_gmt_time($timestamp) + $phone_retry_time;
					$local_timestamp=$timestamp + $phone_retry_time;
					$nct_timestamp = $local_timestamp.'@@ NCT set | '.$rule_id." | ".$next_phone_type."";
					$dialer_remarks = "NCT set | $rule_id | $next_phone_type";
				}
				elsif($phone_retry_rule eq 'finish_phone_dial') {
					$phone_dial = 1;
					$finish_phone = 1;
					$next_phone_type = $phone_retry_value;
					$local_timestamp=0;
					$nct_timestamp = $local_timestamp.'@@ Finished   |' .$rule_id. " ";
					$dialer_remarks = "Finished | $rule_id"
				}
				elsif($phone_retry_rule eq 'finish_lead') {
					$finish_lead = 1;
					$local_timestamp=0;
					$nct_timestamp = $local_timestamp.'@@ Finished   |' .$rule_id. " ";
					$dialer_remarks = "Finished | $rule_id";
				}
				else{
					$finish_lead = 1;
					$local_timestamp=0;
					$nct_timestamp = $local_timestamp.'@@ Finished |' .$rule_id. "| Rule Action Not Defined" ;
					$dialer_remarks = "Rule Action Not Defined";
				}
			}
			else {
				if($phone_max_retry_action eq "finish_lead") {
					$finish_lead=1;
					$local_timestamp=0;
					$nct_timestamp = $local_timestamp.'@@ Finished   |' .$rule_id. " ";
					$dialer_remarks = "Finished | $rule_id";
				}
				else {
					$phone_dial=1;
					$next_phone_type = $phone_max_retry_action;
					$finish_phone = 1;
					$local_timestamp=0;
					$nct_timestamp = $local_timestamp.'@@ Finished   |'.$rule_id. " ";
					$dialer_remarks = "Finished | $rule_id";
				}
			}
		}
		else {
			$finish_lead=1;
			$local_timestamp=0;
			$nct_timestamp = $local_timestamp.'@@ Finished  |'.$rule_id. " ";
			$dialer_remarks = "Finished | $rule_id";
		}
	}
		}
	}
	else {
		my $gmt_timestamp=get_gmt_time($timestamp);
		my $local_timestamp=$timestamp;
		$gmt_timestamp=$gmt_timestamp;

		$query="update extended_customer_$campaign_id set max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = $lead_retry_count_inc,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
		query_execute($query,$dbh,0,__LINE__);


		$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc where lead_id='$lead_id'";
		query_execute($query,$dbh,0,__LINE__);

		$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),next_call_time='$gmt_timestamp',total_max_retries = $lead_retry_count_inc where lead_id='$lead_id'";
		query_execute($query,$dbh,0,__LINE__);

		if ($update_dialstateflag == 1) {
			$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,last_lead_status='0' where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);
		}

		$finish_lead=1;
		$gmt_timestamp=0;
		$local_timestamp=0;
		$nct_timestamp = $local_timestamp.'@@ Finished   |' .$rule_id. " ";
		$dialer_remarks = "Finished | $rule_id";

	}

#---------Run only for phone, finish_phone_dial and max_retries for phone are reached-------
	if($phone_dial) {
		my $next_phone_active=1;
		my $ct=0;
		my %temp_arr;
		my $next_phone_action="";

		$query="select ph_type,max_retries,phone_state from dial_Lead_lookup_$campaign_id where lead_id ='$lead_id'";
		$sth=$dbh->prepare($query);
		$sth->execute() or error_handler($DBI::errstr,__LINE__,$query);
		while (my $phone_num_type = $sth->fetchrow_arrayref) {
#$finish_lead=1;
			if((@$phone_num_type[0]=="$next_phone_type") && @$phone_num_type[2]) {
				$next_phone_active=1;
				$update_new_phone_dial=1;
				$finish_lead=0;
				$finish_dial=1;
				last;
			}
			if($phone_num_type[2]) {
				$temp_arr{"$phone_num_type[0]"}=1;
			}
			$ct++;
		}
		$sth->finish;
#-----------if the next_phone is not active------
#-----------check the failure action against that number-----
#-----------the action will be either finished lead or next_phone_type------
#------------if action is finish_lead finish the lead-------------
#-------------else check the the state of new phone type in active hash---------

		while(!$next_phone_active && $ct){
			if(defined($next_phone_type)) {
				$phone_rule_str = $rule_id."_".$next_phone_type."_max_retry_action";
			}
			else {
				$phone_rule_str = $rule_id."_max_retry_action";
			}
			$next_phone_action = $phoneMaxValue{$phone_rule_str};
			if($next_phone_action eq 'finish_lead'){
				$finish_lead=1;
				last;
			}
			else {
				if(exists($temp_arr{$next_phone_type}) ) {
					if($next_phone_type == $phone_type) {
						if(!$finish_phone) {
							$update_phone_dial=1;
							$phone_dial=0;
							$finish_lead=0;
							$finish_dial=0;
							last;
						}
					}
					else {
						$update_new_phone_dial=1;
						$finish_lead=0;
						$finish_dial=1;
						last;
					}
				}
			}
			$ct--;
		}
	}

	if($finish_lead) {
		$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,lead_state='0',next_call_time='$gmt_timestamp' where lead_id='$lead_id'" ;
		query_execute($query, $dbh,0, __LINE__);

		$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,lead_state='0',next_call_time='$gmt_timestamp' where lead_id='$lead_id'";
		query_execute($query, $dbh,0, __LINE__);


		$query="update extended_customer_$campaign_id set phone_state_".($phone_type-100)." ='0',dial_state_".($phone_type-100)."='0',max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = $lead_retry_count_inc,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),lead_state='0',last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
		query_execute($query, $dbh,0, __LINE__);

		$local_timestamp = 0;
		#$nct_timestamp = $local_timestamp.'@@ Finished   |' .$rule_id. " ";

		if ($update_dialstateflag == 1) {
			$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,lead_state='0',phone_state_$lead_attempt_count='0',dial_state_$lead_attempt_count='0',last_lead_status='0' where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);
		}

	}
	else {
		if($update_new_phone_dial) {
			$query="update dial_Lead_lookup_$campaign_id set dial_state=if(ph_type='$next_phone_type',1,dial_state),next_call_time='$gmt_timestamp' where lead_id='$lead_id' ";
			query_execute($query, $dbh,0, __LINE__);

			$query="update dial_Lead_$campaign_id set dial_state=if(ph_type='$next_phone_type',1,dial_state),next_call_time='$gmt_timestamp' where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			$query="update extended_customer_$campaign_id set phone_state_".($phone_type-100)." ='0',dial_state_".($phone_type-100)."='0'".($next_phone_type?",phone_state_".($next_phone_type-100)." ='1',dial_state_".($next_phone_type-100)."='1'":"").",max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = $lead_retry_count_inc,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			if ($update_dialstateflag == 1) {
				$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,phone_state_$lead_attempt_count='0',dial_state_$lead_attempt_count='0',last_lead_status='0' where lead_id='$lead_id'";
				query_execute($query, $dbh,0, __LINE__);
			}
		}

		if($update_phone_dial) {
			$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$next_phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$next_phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$next_phone_type',1,dial_state),next_call_time=if(ph_type='$next_phone_type','$gmt_timestamp',next_call_time) where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$next_phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$next_phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$next_phone_type',1,dial_state),next_call_time=if(ph_type='$next_phone_type','$gmt_timestamp',next_call_time) where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			$query="update extended_customer_$campaign_id set phone_state_".($phone_type-100)." ='1',dial_state_".($phone_type-100)."='1',max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = $lead_retry_count_inc,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			if ($update_dialstateflag == 1) {
				$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$gmt_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,last_lead_status='0' where lead_id='$lead_id'";
				query_execute($query, $dbh,0, __LINE__);
			}
		}

		if($finish_dial) {
			$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$phone_type',0,dial_state),next_call_time=if(ph_type='$phone_type','$gmt_timestamp',next_call_time) where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$phone_type',0,dial_state),next_call_time=if(ph_type='$phone_type','$gmt_timestamp',next_call_time) where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			$query="update extended_customer_$campaign_id set phone_state_".($phone_type-100)." ='1',dial_state_".($phone_type-100)."='0',max_retries_".($phone_type-100)." = max_retries_".($phone_type-100)." + 1,total_max_retries = $lead_retry_count_inc,num_times_dialed_".($phone_type-100)."=num_times_dialed_".($phone_type-100)." + 1,total_num_times_dialed=total_num_times_dialed+1".($lead_retry_count_inc?"":",first_dial_time=now()").",agentid='$agent_id',next_call_time='$local_timestamp',gmt_next_call_time='$gmt_timestamp',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time),last_call_disposition='$disposition'".($phone_type?",call_disposition_".($phone_type-100)."='$disposition'":"")." where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			if ($update_dialstateflag == 1) {
				$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$local_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,phone_state_$lead_attempt_count='0',dial_state_$lead_attempt_count='0',last_lead_status='0' where lead_id='$lead_id'";
				query_execute($query, $dbh,0, __LINE__);
			}
		}

		if($finish_phone) {
			$query="update dial_Lead_lookup_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$phone_type',0,dial_state),phone_state=if(ph_type='$phone_type',0,phone_state),next_call_time=if(ph_type='$phone_type','$gmt_timestamp',next_call_time) where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			$query="update dial_Lead_$campaign_id set lead_attempt_count='$lead_attempt_count_inc',per_day_mx_retry_count='$per_day_mx_retry_count_inc',phone_attempt_count=if(ph_type='$phone_type',$phone_attempt_count+1,phone_attempt_count),max_retries = if(ph_type='$phone_type',$phone_retry_count + 1,max_retries),total_max_retries = $lead_retry_count_inc,dial_state=if(ph_type='$phone_type',0,dial_state),phone_state=if(ph_type='$phone_type',0,phone_state),next_call_time=if(ph_type='$phone_type','$gmt_timestamp',next_call_time) where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			$query="update extended_customer_$campaign_id set dial_state_".($phone_type-100)."='0',last_dial_time=now(),first_dial_time=if(first_dial_time='0000-00-00 00:00:00' or first_dial_time='',now(),first_dial_time) where lead_id='$lead_id'";
			query_execute($query, $dbh,0, __LINE__);

			if ($update_dialstateflag == 1) {
				$query="update dial_state_$campaign_id set time_$lead_attempt_count=unix_timestamp(),phone_no_$lead_attempt_count='$custphno',phone_type_$lead_attempt_count='$phone_type',next_call_time_$lead_attempt_count='$gmt_timestamp',disposition_$lead_attempt_count='$disposition',next_call_rule_$lead_attempt_count='$dialer_remarks',dial_state_$lead_attempt_count='0',first_dial_time=if(first_dial_time='0' or first_dial_time='',unix_timestamp(),first_dial_time),last_dial_time=unix_timestamp(),lead_attempt_count=$lead_attempt_count+1,last_lead_status='0' where lead_id='$lead_id'";
				query_execute($query, $dbh,0, __LINE__);
			}
		}
	}
	return $nct_timestamp;
}
#----End Disposition Based Calling Rule----------------


#----Start Table Creation-----------------
sub checkTables
{
	my $sth;
	my $dbh;
	my $query;
	my $table_name;
	my $num_rows;
	my @params = @_;
	my $ivr_report_table;
	my $agent_report_table;
	my $cdr_table;

	$dbh=$params[0];
	$table_name=$params[1];

	#----Function to generate report table-------
	$query="SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND table_name = '$table_name'";
	$sth=$dbh->prepare($query);
	$sth->execute();
	$num_rows=$sth->rows;
	$sth->finish;
	if($num_rows != "1") {
		$query="show create table ACD_sample";
		$sth=$dbh->prepare($query);
		$sth->execute();
		my $generate_new_table = $sth->fetchrow_arrayref;
		$sth->finish;

		@$generate_new_table[1] =~ s/ACD_sample/$table_name/g;
		$sth=$dbh->prepare(@$generate_new_table[1]);
		$sth->execute();
		$sth->finish;
	}

	#----Function to generate agent state analysis table-------
	$agent_report_table='agent_state_analysis_'.$table_name;
	$query="SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND table_name = 'agent_state_analysis_".$table_name."'";
	$sth=$dbh->prepare($query);
	$sth->execute();
	$num_rows=$sth->rows;
	$sth->finish;
	if($num_rows != "1") {
		$query="show create table agent_sample";
		$sth=$dbh->prepare($query);
		$sth->execute();
		my $generate_new_table = $sth->fetchrow_arrayref;
		$sth->finish;

		@$generate_new_table[1] =~ s/agent_sample/$agent_report_table/g;
		$sth=$dbh->prepare(@$generate_new_table[1]);
		$sth->execute();
		$sth->finish;
	}

	#----Function to generate ivr report table--------
	$query="SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND table_name = 'ivr_report_".$table_name."'";
	$sth=$dbh->prepare($query);
	$sth->execute();
	$num_rows=$sth->rows;
	$sth->finish;
	$ivr_report_table='ivr_report_'.$table_name;
	if($num_rows != "1") {
		$query="show create table ivr_sample";
		$sth=$dbh->prepare($query);
		$sth->execute();
		my $generate_new_table = $sth->fetchrow_arrayref;
		$sth->finish;

		@$generate_new_table[1] =~ s/ivr_sample/$ivr_report_table/g;
		$sth=$dbh->prepare(@$generate_new_table[1]);
		$sth->execute();
		$sth->finish;
	}

	#----Function to generate cdr report table--------------
	$query="SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND table_name = 'cdr_".$table_name."'";
	$sth=$dbh->prepare($query);
	$sth->execute();
	$num_rows=$sth->rows;
	$sth->finish;
	$cdr_table= 'cdr_'.$table_name;
	if($num_rows != "1") {
		$query="show create table cdr_sample";
		$sth=$dbh->prepare($query);
		$sth->execute();
		my $generate_new_table = $sth->fetchrow_arrayref;
		$sth->finish;

		@$generate_new_table[1] =~ s/cdr_sample/$cdr_table/g;
		$sth=$dbh->prepare(@$generate_new_table[1]);
		$sth->execute();
		$sth->finish;

	}
	#----block of creation feedback_report--------------------
	$query="SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND table_name = 'feedback_".$table_name."'";

	$sth=$dbh->prepare($query);
	$sth->execute();
	$num_rows=$sth->rows;
	$sth->finish;
	my $feedback_report= 'feedback_'.$table_name;
	if($num_rows != "1") {
		$query="show create table feedback_sample";
		$sth=$dbh->prepare($query);
		$sth->execute();
		my $generate_new_table = $sth->fetchrow_arrayref;
		$sth->finish;

		@$generate_new_table[1] =~ s/feedback_sample/$feedback_report/g;
		$sth=$dbh->prepare(@$generate_new_table[1]);
		$sth->execute();
		$sth->finish;
	}

	#----block of creation misscall_report--------------------
	$query="SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND table_name = 'misscall_".$table_name."'";

	$sth=$dbh->prepare($query);
	$sth->execute();
	$num_rows=$sth->rows;
	$sth->finish;
	my $misscall_report= 'misscall_'.$table_name;
	if($num_rows != "1") {
		$query="show create table misscall_sample";
		$sth=$dbh->prepare($query);
		$sth->execute();
		my $generate_new_table = $sth->fetchrow_arrayref;
		$sth->finish;

		@$generate_new_table[1] =~ s/misscall_sample/$misscall_report/g;
		$sth=$dbh->prepare(@$generate_new_table[1]);
		$sth->execute();
		$sth->finish;
	}
#----block of creation escalation_report--------------------
	$query="SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND table_name = 'escalation_".$table_name."'";

	$sth=$dbh->prepare($query);
	$sth->execute();
	$num_rows=$sth->rows;
	$sth->finish;
	my $escalation_report= 'escalation_'.$table_name;
	if($num_rows != "1") {
		$query="show create table escalation_sample";
		$sth=$dbh->prepare($query);
		$sth->execute();
		my $generate_new_table = $sth->fetchrow_arrayref;
		$sth->finish;

		@$generate_new_table[1] =~ s/escalation_sample/$escalation_report/g;
		$sth=$dbh->prepare(@$generate_new_table[1]);
		$sth->execute();
		$sth->finish;
	}

	#----Function to generate voicemail report table--------------
	$query="SELECT table_name FROM information_schema.tables WHERE table_schema = '$db' AND table_name = 'voicemail_".$table_name."'";
	$sth=$dbh->prepare($query);
	$sth->execute();
	$num_rows=$sth->rows;
	$sth->finish;
	$voicemail_table= 'voicemail_'.$table_name;
	if($num_rows != "1") {
		$query="show create table voicemail_sample";
		$sth=$dbh->prepare($query);
		$sth->execute();
		my $generate_new_table = $sth->fetchrow_arrayref;
		$sth->finish;

		@$generate_new_table[1] =~ s/voicemail_sample/$voicemail_table/g;
		$sth=$dbh->prepare(@$generate_new_table[1]);
		$sth->execute();
		$sth->finish;

	}
}
#--- End Table Creation ------------------

sub cview_flag
{
	my @params = @_;
	my $query="";
	my $temp="";
	my $dbh= $params[0];
	$query="select cview_flag from zentrix_server_info";
	$temp=query_execute($query,$dbh,1,__LINE__);
	if(@$temp[0]=='1') {
		$cview_update_enabled = '1';
	}
}
#---Cview Lookup Flag End---------------------

#------QUERY_EXECUTE START--------------------
sub query_execute
{
	my @params=@_;
	my $query;
	my $sth;
	my $dbh;
	my $query_type; #type of query ie insert 0, delete 0, update 0, or select 1
	my $returnvar;
	my $line_no;
	my $row_id;
	my $querylogtime=get_time_now();

	$query=$params[0];
	$dbh=$params[1];
	$query_type=$params[2];
	$line_no=$params[3];
	if($DB) {
		open OUT, ">>/tmp/listener_queries.txt";
		print OUT "\n----$querylogtime-----$line_no------\n";
		print OUT $query;
		close OUT;
	}

	if(!$dbh->ping) {
		$dbh=DBI->connect("dbi:mysql:$db:$server",$username,$password) or die (exit);
	}

	if($query_type == 1) {
		$sth=$dbh->prepare($query);
		$sth->execute() or error_handler($DBI::errstr,$line_no,$query);
		$returnvar=$sth->fetchrow_arrayref;
		$sth->finish();
		return $returnvar;
	}
	elsif($query_type == 2) {
		$sth=$dbh->prepare($query);
		$sth->execute() or error_handler($DBI::errstr,$line_no,$query);
		$returnvar=$sth->rows;
		$sth->finish();
		return $returnvar;
	}
	elsif($query_type == 3) {
		$sth=$dbh->prepare($query);
		$sth->execute() or error_handler($DBI::errstr,$line_no,$query);
		$row_id = $sth->{'mysql_insertid'};
		$sth->finish();
		return $row_id;
	}
	elsif($query_type == 4) {
		$sth=$dbh->prepare($query);
		$sth->execute() or error_handler($DBI::errstr,$line_no,$query);
		$row_id = $sth->{'mysql_affectedrows'};
		$sth->finish();
		return $row_id;
	}
	else {
		$sth=$dbh->prepare($query);
		$sth->execute() or error_handler($DBI::errstr,$line_no,$query);
		$sth->finish();
	}
	return;
}
##################QUERY_EXECUTE END###########################################################

#############################################################
#end block gives you the flexibility to clean memory occupied by the variables while exiting
sub CLEANUP
{
	error_handler ("End of file doing garbage collection", __LINE__,"");
	shmctl($sh_mem_id, IPC_RMID, 0) or error_handler("Unable to clear shared memory",__LINE__,"");
	exit(1);
}


sub populate_disposition_hash
{
	my @params = @_;
	my $listSth;
	my $templistrow;
	my $dbh;

	$dbh = $params[0];
	my $tempQuery;
	my $campDisp;
	my $campRetries;
	my %tempRulecontainer;
	my $k;
	my $fetch_rule_string;
	my $rule_id;

	$tempQuery = "select a.campaign_id,a.basic_disp,a.next_call_time,a.action,a.max_retry from basic_disposition as a ,campaign as b where (b.campaign_type='OUTBOUND' or b.campaign_type='BLENDED') and (b.dialerType='PROGRESSIVE' or  b.dialerType='PREDICTIVE') and (basic_disp='abandon' or basic_disp='ansmc') and a.campaign_id=b.campaign_id";
	$listSth = $dbh->prepare($tempQuery);
	$listSth->execute() or error_handler($DBI::errstr,__LINE__);
	$disposition_semaphore->down;
	while ($templistrow = $listSth->fetchrow_hashref)
	{
		$campDisp=$templistrow->{campaign_id}."_".$templistrow->{basic_disp};
		$campRetries=$templistrow->{campaign_id}."_max_retries";

		$strictCalling_dispositionAction{"$campDisp"} = $templistrow->{action};
		$strictCalling_dispositionValue{"$campDisp"} = $templistrow->{next_call_time};
		$strictCalling_dispositionValue{"$campRetries"} = $templistrow->{max_retry};
	}
	$disposition_semaphore->up;
	$listSth->finish();

	$tempQuery="select a.rule_id,a.total_max_retry,a.rule_type,a.switch_after_attempt,a.recycle_flag,b.list_id from rule_table as a,list_rules_mapping as b where a.rule_id=b.rule_id";
	$listSth=$dbh->prepare($tempQuery);
	$listSth->execute() or error_handler($DBI::errstr,__LINE__,$tempQuery);
	$disposition_semaphore->down;

	while ($templistrow = $listSth->fetchrow_hashref)
	{
		if($templistrow->{rule_type} == '1')
		{
			$listRules{"$templistrow->{list_id}"} = "B"."_".$templistrow->{rule_id};
			$simpleRuleValue{"$templistrow->{rule_id}"}=$templistrow->{switch_after_attempt}."##".$templistrow->{recycle_flag};
		}
		else
		{
			$listRules{"$templistrow->{list_id}"} = "A"."_".$templistrow->{rule_id};
		}
		if ($templistrow->{total_max_retry} == 0 ) {
			$dispositionValue{"$templistrow->{rule_id}"."_"."total_max_retry"}=10;
		}
		else {
			$dispositionValue{"$templistrow->{rule_id}"."_"."total_max_retry"}=$templistrow->{total_max_retry};
		}
	}
	$disposition_semaphore->up;
	$listSth->finish();

	foreach $k (keys %listRules) {
		if (not exists $tempRulecontainer{$listRules{$k}}) {
			$tempRulecontainer{$listRules{$k}}=1;
			$rule_id = $listRules{$k};
			$rule_id =~s/_//g;
			$rule_id =~s/^[a-zA-Z]//g;

			if($listRules{$k} =~/B/)
			{
				$tempQuery="select rule_id,basic_disposition,retry_count,if(retry_time=0,default_time,retry_time) as retry_time,rule_action from basic_disposition_rules where rule_id = '$rule_id'";
				$listSth=$dbh->prepare($tempQuery);
				$listSth->execute() or error_handler($DBI::errstr,__LINE__,$tempQuery);
				$disposition_semaphore->down;
				while ($templistrow = $listSth->fetchrow_hashref)
				{
					$fetch_rule_string=$templistrow->{rule_id}."_".$templistrow->{basic_disposition}."_".$templistrow->{retry_count};
					$basic_rule_disposition_time_value_hash{$fetch_rule_string}=$templistrow->{retry_time};
					$basic_rule_disposition_action_hash{$fetch_rule_string}=$templistrow->{rule_action};
				}
				$disposition_semaphore->up;
				$listSth->finish();
			}
			else
			{
				$tempQuery="select rule_id,ph_type,if(max_retry=0,default_retry,max_retry) as max_retries ,max_retry_action from max_retry_phone where rule_id = '$rule_id'";
				$listSth=$dbh->prepare($tempQuery);
				$listSth->execute() or error_handler($DBI::errstr,__LINE__,$tempQuery);
				$disposition_semaphore->down;
				while ($templistrow = $listSth->fetchrow_hashref)
				{
					$fetch_rule_string=$templistrow->{rule_id}."_".$templistrow->{ph_type};
					$phoneMaxValue{$fetch_rule_string} = $templistrow->{max_retries};
					$phoneMaxValue{"$fetch_rule_string"."_"."max_retry_action"} = $templistrow->{max_retry_action};
				}
				$disposition_semaphore->up;
				$listSth->finish();

				$tempQuery="select rule_id,ph_type,basic_disposition,retry_count,if(retry_time=0,default_time,retry_time) as retry_time,rule_action,rule_value from disposition_rules where rule_id = '$rule_id'";
				$listSth=$dbh->prepare($tempQuery);
				$listSth->execute() or error_handler($DBI::errstr,__LINE__,$tempQuery);
				$disposition_semaphore->down;
				while ($templistrow = $listSth->fetchrow_hashref)
				{
					$fetch_rule_string=$templistrow->{rule_id}."_".$templistrow->{ph_type}."_".$templistrow->{basic_disposition}."_".$templistrow->{retry_count};
					$phoneRetryTime{$fetch_rule_string} = $templistrow->{retry_time};
					$phoneRetryRule{$fetch_rule_string} = $templistrow->{rule_action};
					$phoneRetryValue{$fetch_rule_string} = $templistrow->{rule_value};

				}

				$disposition_semaphore->up;
				$listSth->finish();
			}
		}
	}
}

sub check_cview
{
	my $sth;
	my @params = @_;
	my $query = $params[0];
	my $dbh= $params[1];
	my $table_name= $params[2];
	my $query_type = $params[3];
	my $value = quotemeta($query);
	if($cview_update_enabled) {
		if($query_type == 1){
			$query="insert into month_report (query,entrytime) values ('$value',unix_timestamp())";
		}
		elsif($query_type == 2){
			$query="insert into agent_report (query,entrytime) values ('$value',unix_timestamp())";
		}
		elsif($query_type == 3){
			$query="insert into ivr_report (query,entrytime) values ('$value',unix_timestamp())";
		}
		elsif($query_type == 4){
			$query="insert into feedback_report (query,entrytime) values ('$value',unix_timestamp())";
		}
		else
		{
			$query="insert into cdr_report (query,entrytime) values ('$value',unix_timestamp())";
		}
		$sth=$dbh->prepare($query);
		$sth->execute() or error_handler($DBI::errstr, __LINE__,$query);
		$sth->finish();
	}
}

sub is_numeric
{
	return $_[0] =~ /^[1-9][0-9.]*$/
}

sub match_ip()
{
  return $_[0] =~ /(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})/
}

#/* Set Node ID */
sub set_node_id
{
# this bit is to read the first word from unique_id file and set it as node_id.
# if node id is not numeric OR there is nothing to set OR the file is missing, then
# it should give an error and stop.
	my $res_fopen = open(DAT, "/etc/unique_id");
	my $errorlogtime=get_time_now();
	my $count = 1;
	if (defined $res_fopen ) {
		while( <DAT> ){
			if($count == 0){
				last;
			}
			$count --;
			my @line = split('\b', $_);
			if (is_numeric($line[0]) ){
				$node_id =$line[0];
			}
			else{
				close(DAT);
				open DAT, ">>/var/log/czentrix/czentrix_listen_log.txt";
				print DAT "$errorlogtime  Unique id is Not numeric. Kindly check /etc/unique_id \n";
				close DAT;
				exit;
			}
		}
		if ($count == 1){
			close(DAT);
			open DAT, ">>/var/log/czentrix/czentrix_listen_log.txt";
			print DAT "$errorlogtime  File Empty. Kindly check /etc/unique_id \n";
			close DAT;
			exit;
		}
	} else {
		open DAT, ">>/var/log/czentrix/czentrix_listen_log.txt";
		print DAT "$errorlogtime  File missing. Kindly check /etc/unique_id \n";
		close DAT;
		exit;
	}
	close(DAT);
}
