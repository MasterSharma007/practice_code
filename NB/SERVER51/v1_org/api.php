<?php
use \Psr\Http\Message\ServerRequestInterface as Request;
use \Psr\Http\Message\ResponseInterface as Response;


require './vendor/autoload.php';
require 'Mobilecall.class.php';
require 'Asterisk.class.php';


$app = new \Slim\App;
#Route
$app->get('/', function (Request $request, Response $response){
	$res['msg']  = 'Bad Request';
	$res['code'] = '200';
        return json_encode($res);
});


$app->get('/agentmobile/dial/{data}', function (Request $request, Response $response, array $args) {
        //agentid=${AGENTID}&customer=${SFID}&uniqueid=${UNIQUEID}&epoch=${CONFNO}&rec=${BASE64_ENCODE(${CALLFILENAME})}

        $data = $args['data'];
        $url_components = parse_url($data);
        parse_str($url_components['path'], $params);
        $mobilecall = new Mobilecall();
        $ret = $mobilecall->dial($params);
        return $ret;

});

$app->get('/agentmobile/hangupchannel/{data}', function (Request $request, Response $response, array $args) {
        //agentmobile=${agentmobile}
        $data = $args['data'];
        $url_components = parse_url($data);
        parse_str($url_components['path'], $params);
        $mobilecall = new Mobilecall();
        $ret = $mobilecall->hangup($params);
        return $ret;

});

$app->get('/agentmobile/{data}', function (Request $request, Response $response, array $args) {
        //agent_code=P123456&mobile_no=999999999&is_active=1
        $data = $args['data'];
        $url_components = parse_url($data);
        parse_str($url_components['path'], $params);
        $mobilecall = new Mobilecall();
        $ret = $mobilecall->add($params);
        return $ret;

});

$app->get('/agentmobile/fetch/{data}', function (Request $request, Response $response, array $args) {
        //agent_code=P123456
        $data = $args['data'];
        $url_components = parse_url($data);
        parse_str($url_components['path'], $params);
        $mobilecall = new Mobilecall();
        $ret = $mobilecall->fetch($params);
        return $ret;

});

$app->get('/agentmobile/get_channel/{data}', function (Request $request, Response $response, array $args) {
        //agent_code=P123456
        $data = $args['data'];
        $url_components = parse_url($data);
        parse_str($url_components['path'], $params);
        $mobilecall = new Mobilecall();
        $ret = $mobilecall->get_channel($params);
        return $ret;

});

$app->get('/agentmobile/check_mobile_active/{data}', function (Request $request, Response $response, array $args) {
        //agent_code=P123456
        $data = $args['data'];
        $url_components = parse_url($data);
        parse_str($url_components['path'], $params);
        $mobilecall = new Mobilecall();
        $ret = $mobilecall->check_mobile_active($params);
        return $ret;

});


$app->get('/log_api/add/{data}', function (Request $request, Response $response, array $args) {
        $data = $args['data'];
        if(!class_exists('Logapi')){
                require_once('Logapi.class.php');
        }

        $url_components = parse_url($data);
        parse_str($url_components['path'], $params);
        $logapi = new Logapi();
        $crm_res = '';


        $base_url = "http://crm.nivabupa.com/api/v1/dialer_call/add";
        $crm_res = $logapi->add2CRM($base_url, json_encode($params), $timeout=11);	

        $crm_arr = json_decode($crm_res,true);
	#$crm_callid = $crm_arr['call_id'];
        
	$crm_callid = (json_last_error() == JSON_ERROR_NONE && isset($crm_arr['call_id']) && $crm_arr['success'] == true) ? $crm_arr['call_id'] : 'temp_'.time();

	$ret = $logapi->save2db($crm_callid, json_encode($params), $crm_res);	
        return $crm_callid;
});


$app->get('/log_api/{call_id}/{data}', function (Request $request, Response $response, array $args) {
	$call_id = $args['call_id'];
	$data = $args['data'];
        if(!class_exists('Logapi')){
                require_once('Logapi.class.php');
        }
	
	$url_components = parse_url($data);
	parse_str($url_components['path'], $params); 
	$logapi = new Logapi();
	$crm_res = '';

if(isset($params['recording_url']) &&  !empty($params['recording_url'])){
	$params['recording_url'] = base64_decode($params['recording_url']);
}

        $base_url = "http://crm.nivabupa.com/api/v1/dialer_call/update";
        $url = $base_url.'/'.$call_id;	

	$pos = strpos($call_id, 'temp_');
	if ($pos === false) {                                                           // call only if not temp
		$crm_res = $logapi->add2CRM($url, json_encode($params), $timeout=11);
	}

	$ret = $logapi->save2db($call_id, json_encode($params), $crm_res);
	return json_encode($ret);
});

$app->get('/log_api/resend_failed', function (Request $request, Response $response, array $args) {
	if(!class_exists('Logapi')){
		require_once('Logapi.class.php');
	}
        $logapi = new Logapi();
        $ret = $logapi->add_failed();
        $ret = $logapi->update_failed();
        return json_encode($ret);
});


$app->get('/queue/fetch_callable_agents/{data}', function (Request $request, Response $response, array $args) {
        //queue_name=${queue_name}&queue_type=ib/pd
        if(!class_exists('Queue')){
                require_once('Queue.class.php');
        }

        $data = $args['data'];
        $url_components = parse_url($data);
        parse_str($url_components['path'], $params);
        $queue = new Queue();
        $ret = $queue->fetch_available($params);
        return $ret;
});

$app->run();
?>
