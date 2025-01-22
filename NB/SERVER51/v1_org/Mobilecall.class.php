<?php
// vim: set ai ts=4 sw=4 ft=php:

ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
require_once(__DIR__ . '/../env_loader.php');


class Mobilecall
{

    public function __construct()
    {
        require_once(__DIR__ . '/MySQL.class.php');

        $this->env  = $_ENV['ENV'];
        $this->crm_url = $_ENV['CRM_URL'];

        $this->db = new MySQL($_ENV['AMPDBHOST'], $_ENV['AMPDBUSER'], $_ENV['AMPDBPASS'], $_ENV['AMPDBNAME'], true);
    }

    public function dial($request)
    {
        //agentid=${AGENTID}&uid=${UID}&customer=${SFID}&uniqueid=${UNIQUEID}&epoch=${CONFNO}&rec=${BASE64_ENCODE(${CALLFILENAME})}&lead=${LEADID}&ad=${auto_dial}

        $agentid        =    $request['agentid'];
        $uid            =    $request['uid'];
        $customermobile    =    $request['customer'];
        $uniqueid        =    $request['uniqueid'];
        $epoch            =    $request['epoch'];
        $rec            =    $request['rec'];
        $lead             =    $request['lead'];
        $ad             =   $request['ad'];

        $sql = "SELECT * from agent_mobile_mapping where agent_code = '$uid' and is_active = 1 limit 1";
        $result = $this->db->fetchQuery($sql);
        $agentmobile = $result[0]['mobile_no'];
        $timestamp = @time();
        $strContext = 'multiconference';
        $strUser = "max_mbhi";
        $strSecret = "mbhi_max";
        $strChannel = '400';
        $strWaitTime = "50";
        $strPriority = "1";
        $strMaxRetry = "1";
        $port = 5038;
        $server_ip = '127.0.0.1';
        $socket = stream_socket_client("tcp://$server_ip:$port", $errno, $errstr, 30);
        $authenticationRequest = "Action: Login\r\n";
        $authenticationRequest .= "Username: $strUser\r\n";
        $authenticationRequest .= "Secret: $strSecret\r\n";
        $authenticationRequest .= "Events: off\r\n\r\n";
        $authenticate = stream_socket_sendto($socket, $authenticationRequest);
        if ($authenticate > 0) {
            usleep(20000);
            $authenticateResponse = fread($socket, 4096);
            $originateRequest = "Action: Originate\r\n";
            $originateRequest .= "Channel: LOCAL/$agentmobile@dialagent\r\n";
            $originateRequest .= "Callerid: 6998877\r\n";
            $originateRequest .= "Exten: $customermobile\r\n";
            $originateRequest .= "Context: dialcustomer\r\n";
            $originateRequest .= "Priority: 1\r\n";
            $originateRequest .= "WaitTime: 60\r\n";
            $originateRequest .= "Account: hello\r\n";
            $originateRequest .= "Variable: epoch=$epoch\r\n";
            $originateRequest .= "Variable: CALLID=$uniqueid\r\n";
            $originateRequest .= "Variable: AGENTID=$agentid\r\n";
            $originateRequest .= "Variable: UID=$uid\r\n";
            $originateRequest .= "Variable: LEADID=$lead\r\n";
            $originateRequest .= "Variable: auto_dial=$ad\r\n";
            $originateRequest .= "Variable: CALLFILENAME=$rec\r\n";
            $originateRequest .= "Variable: AGENTMOBILE=$agentmobile\r\n";
            $originateRequest .= "Variable: CUSTOMERMOBILE=$customermobile\r\n";

            $originateRequest .= "Action: Logoff\r\n\r\n";
            // Send originate request
            $originate = stream_socket_sendto($socket, $originateRequest);
            if ($originate > 0) {
                usleep(20000);
                $originateResponse = fread($socket, 4096);
                if (strpos($originateResponse, 'Success') !== false) {
                    $message = "Call initiated on";
                    $status = 200;
                } else {
                    $message = "Call is being transferred...";
                    $status = 200;
                }
            }
        }
        return json_encode(array('agentmobile' => $agentmobile, 'action' => 'success'));
    }    //dial function


    public function hangup($request)
    {
        if (!class_exists('Asterisk')) {
            require_once('Asterisk.class.php');
        }

        $agentmobile    = $request['agentmobile'];
        $action         = (isset($request['action'])) ? $request['action'] : "hangup";


        $asterisk       = new Asterisk();
        $output1        = $asterisk->run("localhost", 'core show channels concise');
        $lines2         = explode("\n", $output1);
        $response       = array();
        $key            = false;

        foreach ($lines2 as $line) {
            if (strpos($line, $agentmobile) !== false) {
                $data = explode("!", $line);
                $key = $data[12];
            }
        }

        if (empty($key)) {
            return json_encode(array("channel" => "none"));
        }

        foreach ($lines2 as $line) {
            if (strpos($line, $key) !== false) {
                $data1 = explode("!", $line);
                $channels[] = $data1[0];
            }
        }
        if ($action != "hangup") {
            return json_encode(array("channel" => $channels[0]));
        } else {
            foreach ($channels as $ch) {
                $asterisk->run("localhost", "channel request hangup " . $ch);
            }
            return json_encode(array("channel" => "none"));
        }
    }

    public function add($request)
    {
        //agent_code=P123456&mobile_no=999999999&is_active=1

        $agent_code             =   $request['agent_code'];
        $mobile_no              =   $request['mobile_no'];
        $is_active              =   (isset($request['is_active'])) ? $request['is_active'] : 1;

        $sql = "REPLACE `agent_mobile_mapping` SET agent_code='$agent_code', is_active=$is_active, mobile_no='$mobile_no'";

        if ($this->db->query($sql) === TRUE) {
            $ret['success'] = 1;
            $ret['msg'] = "Done successfully";
            $ret['data'] = array($agent_code, $mobile_no, $is_active);
        } else {
            $ret['success'] = 0;
            $ret['msg'] = 'Failed to add / update';
        }
        return json_encode($ret);
    }

    public function fetch($request)
    {
        //agent_code=P123456
        $agent_code =   $request['agent_code'];
        $sql        =   "Select * from `agent_mobile_mapping` where agent_code='$agent_code'";
        $res        =   $this->db->fetchAssocQuery($sql);
        return json_encode($res);
    }

    public function get_channel($request)
    {
        //agent_code=P123456
        $agent_code =   $request['agent_code'];
        $sql        =   "Select mobile_no from `agent_mobile_mapping` where agent_code='$agent_code' and is_active = 1";
        $res        =   $this->db->fetchAssocQuery($sql);

        if (isset($res['mobile_no'])) {
            $ar['action'] = 'get';
            $ar['agentmobile'] = $res['mobile_no'];
            $res_json = $this->hangup($ar);
            $res_json_d = json_decode($res_json);
            $channel = $res_json_d->channel;
        } else {
            $channel    =  'SIP/' . $agent_code;
        }

        return json_encode(array("channel" => $channel));
    }

    public function check_mobile_active($request)
    {
        //agent_code=P123456
        $agent_code =   $request['agent_code'];
        $sql        =   "Select mobile_no from `agent_mobile_mapping` where agent_code='$agent_code' and is_active = 1";
        $res        =   $this->db->fetchAssocQuery($sql);

        $active = (isset($res['mobile_no'])) ? 1 : 0;

        return json_encode(array("active" => $active));
    }
} // class
