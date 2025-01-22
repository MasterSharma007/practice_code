<?php
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
require_once(__DIR__ . '/../env_loader.php');

// vim: set ai ts=4 sw=4 ft=php:
class Queue
{

	public function __construct()
	{
		require_once(__DIR__ . '/MySQL.class.php');

		$this->env  = $_ENV['ENV'];
		$this->crm_url = $_ENV['CRM_URL'];

		$this->db = new MySQL($_ENV['AMPDBHOST'], $_ENV['AMPDBUSER'], $_ENV['AMPDBPASS'], $_ENV['AMPDBNAME'], true);
	}

	public function add_queue($request)
	{
		$name			=	$request['name'];
		$timeout		=	(isset($request['timeout']) && !empty($request['timeout'])) ? $request['timeout'] : 7;
		$retry			=	(isset($request['retry']) && !empty($request['retry'])) ? $request['retry'] : 1;
		$wrapuptime		=	(isset($request['wrapuptime']) && !empty($request['wrapuptime'])) ? $request['wrapuptime'] : 45;
		$max_waittime	=	(isset($request['max_waittime']) && !empty($request['max_waittime'])) ? $request['max_waittime'] : 90;
		$memberdelay	=	(isset($request['memberdelay']) && !empty($request['memberdelay'])) ? $request['memberdelay'] : 1;
		$strategy		=	(isset($request['strategy']) && !empty($request['strategy'])) ? $request['strategy'] : 'leastrecent';

		$sql = "REPLACE `queues` SET name='$name', timeout='$timeout', retry='$retry', wrapuptime='$wrapuptime', servicelevel='$max_waittime', memberdelay='$memberdelay', strategy='$strategy'";

		if ($this->db->query($sql) === TRUE) {
			$ret['success'] = 1;
			$ret['msg'] = "$name queue added successfully";
		} else {
			$ret['success'] = 0;
			$ret['msg'] = 'Failed to add / update';
		}
		return $ret;
	}

	public function update_queue($request)
	{
		$name			=	$request['name'];
		$timeout		=	(isset($request['timeout']) && !empty($request['timeout'])) ? $request['timeout'] : 7;
		$retry			=	(isset($request['retry']) && !empty($request['retry'])) ? $request['retry'] : 1;
		$wrapuptime		=	(isset($request['wrapuptime']) && !empty($request['wrapuptime'])) ? $request['wrapuptime'] : 45;
		$max_waittime	=	(isset($request['max_waittime']) && !empty($request['max_waittime'])) ? $request['max_waittime'] : 90;
		$memberdelay	=	(isset($request['memberdelay']) && !empty($request['memberdelay'])) ? $request['memberdelay'] : 1;
		$strategy		=	(isset($request['strategy']) && !empty($request['strategy'])) ? $request['strategy'] : 'leastrecent';

		$sql = "REPLACE `queues` SET name='$name', timeout='$timeout', retry='$retry', wrapuptime='$wrapuptime', servicelevel='$max_waittime', memberdelay='$memberdelay', strategy='$strategy'";

		if ($this->db->query($sql) === TRUE) {
			$ret['success'] = 1;
			$ret['msg'] = "$name queue updated successfully";
		} else {
			$ret['success'] = 0;
			$ret['msg'] = 'Failed to add / update';
		}
		return $ret;
	}

	public function add_member($request)
	{

		$membername     = $request['membername'];
		$queue_name     = $request['queue_name'];
		$auto_answer    = $request['auto_answer'];

		$sql = "REPLACE `queue_member_table` SET membername='$membername', queue_name='$queue_name', interface='Local/$membername@dial-queue-member', auto_answer='$auto_answer'";

		if ($this->db->query($sql) === TRUE) {
			$ret['success'] = 1;
			$ret['msg'] = "Member/s added successfully";
		} else {
			$ret['success'] = 0;
			$ret['msg'] = 'Failed to add / update';
		}
		return $ret;
	}

	public function delete_member($request)
	{

		$membername     = $request['membername'];
		$queue_name     = $request['queue_name'];

		$sql = "DELETE from  `queue_member_table` where membername='$membername' and queue_name='$queue_name'";

		if ($this->db->query($sql) === TRUE) {
			$ret['success'] = 1;
			$ret['msg'] = "operation successfull, member $membername inactivated from $queue_name";
		} else {
			$ret['success'] = 0;
			$ret['msg'] = 'Failed to make inactive';
		}
		return $ret;
	}

	public function update_member($request)
	{

		$membername     = $request['membername'];
		$queue_name     = $request['queue_name'];
		$auto_answer    = $request['auto_answer'];

		$sql = "REPLACE `queue_member_table` SET membername='$membername', queue_name='$queue_name', interface='Local/$membername@dial-queue-member', auto_answer='$auto_answer'";

		if ($this->db->query($sql) === TRUE) {
			$ret['success'] = 1;
			$ret['msg'] = "Member/s added successfully";
		} else {
			$ret['success'] = 0;
			$ret['msg'] = 'Failed to add / update';
		}
		return $ret;
	}

	public function crm_api($url, $json_data, $timeout)
	{
		#$fp = fopen(dirname(__FILE__).'/errorlog.txt', 'w+');
		$curl = curl_init();
		curl_setopt_array($curl, array(
			CURLOPT_VERBOSE => true,
			CURLOPT_URL => $url,
			CURLOPT_RETURNTRANSFER => true,
			CURLOPT_ENCODING => '',
			CURLOPT_MAXREDIRS => 10,
			CURLOPT_CONNECTTIMEOUT => $timeout,
			CURLOPT_TIMEOUT => $timeout,
			CURLOPT_FOLLOWLOCATION => true,
			CURLOPT_HTTP_VERSION => CURL_HTTP_VERSION_1_1,
			CURLOPT_CUSTOMREQUEST => 'POST',
			CURLOPT_POSTFIELDS => $json_data,
			CURLOPT_HTTPHEADER => array(
				'Content-Type: application/json'
			),
		));

		$response = curl_exec($curl);

		curl_close($curl);
		return $response;
	}
	public function fetch_available($request)
	{
		//queue_name=${queue_name}&queue_type=ib/pd

		$campaign_name          =   $request['queue_name'];
		$queue_type             =   $request['queue_type'];

		$agents = array();
		$sql = "SELECT * FROM `queue_member_table` where `queue_name` = '$campaign_name'";
		$result = $this->db->fetchQuery($sql);
		foreach ($result as $row) {
			$agents[] = "'" . $row['membername'] . "'";
		}

		//`auto_calling` = 1 and `unmarked_lead` = 0 and `next_lead` = 0

		$agent_list = implode(',', $agents);
		$sip_status = "SELECT `name` FROM `sip_buddies` where `name` IN ($agent_list) and `unmarked_lead` = 0 and `next_lead` = 0 and `is_loggedin`=1 and length(fullcontact)>0";

		$count = 0;
		$callable = array();
		$sip_res = $this->db->fetchQuery($sip_status);
		foreach ($sip_res as $row) {
			$count = $count + 1;
			$callable[] = $row['name'];
		}
		return json_encode(array("callable" => implode(',', $callable)));
	}
}
