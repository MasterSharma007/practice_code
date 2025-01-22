<?php
// vim: set ai ts=4 sw=4 ft=php:
require_once(__DIR__ . '/../env_loader.php');

class Logapi
{

	public function __construct()
	{

		require_once(__DIR__ . '/MySQL.class.php');

		$this->env  = $_ENV['ENV'];
		$this->crm_url = $_ENV['CRM_URL'];

		$this->db = new MySQL($_ENV['AMPDBHOST'], $_ENV['AMPDBUSER'], $_ENV['AMPDBPASS'], $_ENV['AMPDBNAME'], true);
	}


	public function save2db($call_id, $json_data, $crm_res)
	{

		$is_success = 0;
		$res_ar = json_decode($crm_res, true);
		if (json_last_error() == JSON_ERROR_NONE) {
			$is_success = (isset($res_ar['success']) && $res_ar['success'] == true) ? 1 : 0;
		}

		$sql = "REPLACE `api_log` SET crm_callid='$call_id', data='$json_data', response='$crm_res', is_success='$is_success'";

		if ($this->db->query($sql) === TRUE) {
			return json_encode(array('200', $crm_res));
		} else {
			return json_encode('500', 'error');
		}
	}

	public function add_failed()
	{
		$sql = "SELECT * from `api_log` where  crm_callid LIKE '%temp_%' and is_success = '0' and response NOT LIKE '%Call ID not valid%' and date(created_date) = CURRENT_DATE() ORDER BY id DESC LIMIT 100";
		$result = $this->db->fetchQuery($sql);
		print_r($result);						//PRINTING RESULT
		foreach ($result as $row) {
			$base_url = $this->crm_url . "/api/v1/dialer_call/add";
			$crm_res = $this->add2CRM($base_url, $row['data'], $timeout = 6);
			$is_success = 0;
			$res_ar = json_decode($crm_res, true);
			if (json_last_error() == JSON_ERROR_NONE) {
				$is_success = (isset($res_ar['success']) && $res_ar['success'] == true) ? 1 : 0;
			}

			if ($is_success) {
				$update_callid_other_rows = "UPDATE `api_log` SET crm_callid='" . $res_ar['call_id'] . "' WHERE crm_callid = '" . $row['crm_callid'] . "'";
				$this->db->query($update_callid_other_rows);

				$update_res = "UPDATE `api_log` SET crm_callid='" . $res_ar['call_id'] . "', response='$crm_res', is_success='$is_success', succeeded_by='1', `attempt`=attempt + 1 WHERE id = '" . $row['id'] . "'";
				if ($this->db->query($update_res) === TRUE) {
					echo json_encode(array($row['id'], $crm_res));
				} else {
					echo json_encode($row['id'], $crm_res, 'error');
				}
			}
			sleep(0.25);
		}
		return 'done';
	}



	public function update_failed()
	{
		$sql = "SELECT * from `api_log` where crm_callid NOT LIKE '%temp_%' and is_success = '0' and response NOT LIKE '%Call ID not valid%' and date(created_date) = CURRENT_DATE() ORDER BY id DESC LIMIT 150";
		$result = $this->db->fetchQuery($sql);
		print_r($result);
		foreach ($result as $row) {

			$base_url = $this->crm_url . "/api/v1/dialer_call/update";
			$url = $base_url . '/' . $row['crm_callid'];
			$crm_res = $this->add2CRM($url, $row['data'], $timeout = 6);
			$is_success = 0;
			$res_ar = json_decode($crm_res, true);
			if (json_last_error() == JSON_ERROR_NONE) {
				$is_success = (isset($res_ar['success']) && $res_ar['success'] == true) ? 1 : 0;
			}

			if ($is_success) {

				$update_sql = "UPDATE `api_log` SET response='$crm_res', is_success='$is_success', succeeded_by='1', `attempt`=attempt + 1  WHERE id = '" . $row['id'] . "'";

				if ($this->db->query($update_sql) === TRUE) {
					echo json_encode(array($row['id'], $crm_res));
				} else {
					echo json_encode($row['id'], $crm_res, 'error');
				}
			}
			sleep(0.25);
		}
		return 'done';
	}

	public function add2CRM($url, $json_data, $timeout)
	{
		$fp = fopen(dirname(__FILE__) . '/errorlog.txt', 'w+');
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
			CURLOPT_STDERR => $fp,
			CURLOPT_HTTPHEADER => array(
				'Content-Type: application/json'
			),
		));

		$response = curl_exec($curl);

		curl_close($curl);
		return $response;
	}
}
