
<?php
// vim: set ai ts=4 sw=4 ft=php:

ini_set('display_errors', 0);
ini_set('display_startup_errors', 0);
//error_reporting(E_ALL);
date_default_timezone_set('Asia/Kolkata');
require_once(__DIR__ . '/../env_loader.php');


class Checkrec
{

    public function __construct()
    {
        require_once(__DIR__ . '/MySQL.class.php');

        $this->env  = $_ENV['ENV'];
        $this->crm_url = $_ENV['CRM_URL'];

        $this->db = new MySQL($_ENV['AMPDBHOST'], $_ENV['AMPDBUSER'], $_ENV['AMPDBPASS'], $_ENV['AMPDBNAME'], true);

        $this->recording_path  = '/Asterikrecording/Recordings';
        $this->server_id       = 1;
    }


    public function select()
    {
        $handle = fopen("../export10_.csv", "a");

        $sql = "select crm_callid,data,created_date from api_log where id > '4013901' and date(created_date) = '2021-07-09'  and data like '{\"recording_url%'";
        $result = $this->db->fetchQuery($sql);
        // print_r($result);						
        foreach ($result as $row) {
            $data = $row['data'];
            $d = json_decode($data, true);

            if (file_exists($d['recording_url'] . '.wav')) {
                echo '*';
                continue;
            } else {

                echo $d['recording_url'] . '.wav';

                $tmp = preg_split('/\//m', $d['recording_url']);
                $filename = end($tmp);          //filename
                $file_items = explode('-', $filename);
                $lead = $file_items[3];
                $mno = $file_items[4];

                //get talktime
                $call_data = $this->get_call_data($row['crm_callid']);

                //create log row
                $items = array(
                    $row['crm_callid'],
                    $lead,
                    $mno,
                    $call_data['call_hangup_time'],
                    $call_data['disposition'],
                    $call_data['disconnected_by'],
                    $call_data['duration'],
                    $call_data['talktime']
                );
                echo '.';
                fputcsv($handle, $items);
            }
        }
        fclose($handle);
    }

    public function get_call_data($callid)
    {
        $sql = "select data from api_log where crm_callid = $callid and data like '{\"duration%'";
        $result = $this->db->fetchQuery($sql);
        return json_decode($result[0]['data'], true);
    }
} // class

$chk = new Checkrec();
$chk->select();

?>

