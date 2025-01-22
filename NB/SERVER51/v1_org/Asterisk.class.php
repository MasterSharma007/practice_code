<?php
// vim: set ai ts=4 sw=4 ft=php:

ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

Class Asterisk{

    public function __construct(){

	$this->env  = 'staging'; // staging / production
	$this->crm_url = ($this->env == 'staging' ? 'http://crmtest.nivabupa.com' : 'http://crm.nivabupa.com');
	
    }

    public function run($ip, $command) {
        $socket = @fsockopen($ip, "5038", $errno, $errstr, 10);
        if (!$socket) {
            throw new Exception("Error: $errstr ($errno)\n");
            return;
        }
        $wrets = '';
        fputs($socket, "Action: Login\r\n");
        fputs($socket, "UserName: max_mbhi\r\n");
        fputs($socket, "Secret: mbhi_max\r\n\r\n");
        fputs($socket, "Action: Command\r\n");
        fputs($socket, "Command:$command\r\n\r\n");
        fputs($socket, "Action: Logoff\r\n\r\n");
        $arr = array();
        while (!feof($socket)) {
            $wrets .= fread($socket, 8192);
            $arr[] = $wrets;
        }
        fclose($socket);
        return $wrets;
    }

} // class
?>
