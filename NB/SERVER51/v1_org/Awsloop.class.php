<?php
// vim: set ai ts=4 sw=4 ft=php:

ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);
date_default_timezone_set('Asia/Kolkata');
require_once(__DIR__ . '/../env_loader.php');


class Aws
{

    public function __construct()
    {
        require_once(__DIR__ . '/MySQL.class.php');

        $this->env  = $_ENV['ENV'];
        $this->crm_url = $_ENV['CRM_URL'];

        $this->db = new MySQL($_ENV['AMPDBHOST'], $_ENV['AMPDBUSER'], $_ENV['AMPDBPASS'], $_ENV['AMPDBNAME'], true);

        $this->recording_path  = '/var/lib/asterisk/static-http/config/Recordings';
        $this->server_id       = 1;
    }

    public function list_folder($date)
    {
        //$date = '31-12-2020';
        $path = $this->recording_path . '/' . $date;
        echo $path;
        if (file_exists($path))
            $dir = scandir($path, 0);
        else
            return false;
        unset($dir[0]);
        unset($dir[1]);
        foreach ($dir as $key => $hour) {
            $files = scandir($path . '/' . $hour, 0);
            unset($files[0]);
            unset($files[1]);
            foreach ($files as $key => $filename) {
                $sub_path = $date . '/' . $hour . '/' . $filename;             // to store in db date/hour/file
                $file_location = $this->recording_path . '/' . $sub_path; // full file location
                $rec_file_items = explode('-', $filename);
                $unique_id = $rec_file_items[0];
                if (count($rec_file_items) > 7) {
                    $one = '/[0-9]*\.[0-9]*-[0-9]*-/';
                    $two = '/-[0-9]*-[0-9]{10}/';
                    $k = preg_split($one, $filename);
                    $m = preg_split($two, $k[1]);
                    $call_id = $m[0];
                } else {
                    $call_id = $rec_file_items[2];
                }
                $create_row = array(
                    'unique_id' => $unique_id,
                    'call_id'   => $call_id,
                    'server_id' => $this->server_id,
                    'current_place' => 1,
                    'local_file' => $sub_path,
                    'local_file_time' => date("Y-m-d H:i:s", filemtime($file_location))
                );

                $this->create($create_row);
                $awsres = $this->upload2aws(
                    array(
                        'file_location' => $file_location,
                        'upload_to_path' => $sub_path
                    )
                );
                $update_row = array(
                    'unique_id' => $unique_id,
                    'current_place' => 2,
                    's3' => 's3://max-callrecords/recordings/' . $sub_path,
                    's3_time' => date('Y-m-d H:i:s')
                );
                $this->update($update_row);

                echo $filename . "\r\n";
            }
        }
        //return json_encode($dir);
    }

    public function create($create_row)
    {

        foreach ($create_row as $k => $v) {
            $data[] = "`" . $k . "`='$v'";
        }
        $query_string = implode(', ', $data);
        $sql = "REPLACE `recording_storage` SET $query_string";

        if ($this->db->query($sql) === TRUE) {
            return true;
        } else {
            $this->log('insertfailed,' . $sql);
            exit;
        }
    }

    public function update($update_row)
    {
        $unique_id = $update_row['unique_id'];
        unset($update_row['unique_id']);

        foreach ($update_row as $k => $v) {
            $data[] = "`" . $k . "`='$v'";
        }
        $query_string = implode(', ', $data);
        $sql = "Update `recording_storage` SET $query_string where unique_id = '$unique_id'";

        if ($this->db->query($sql) === TRUE) {
            return true;
        } else {
            $this->log('updatefailed,' . $sql);
            exit;
        }
    }
    public function upload2aws($fd)
    {

        $file_location = $fd['file_location'];
        $this->s3upload_to_path = $fd['upload_to_path'];
        $filename = $fd['upload_to_path'];

        $cmd = "aws s3 --region ap-south-1 --endpoint-url https://bucket.vpce-01e414640e8a4ff76-rp1v14wv.s3.ap-south-1.vpce.amazonaws.com/ mv " . $file_location . " s3://max-callrecords/recordings/" . $this->s3upload_to_path;
        $output = shell_exec($cmd);

        if (preg_match('/upload:/', $output) || preg_match('/move:/', $output)) {
	    $cmd1 = "rm -rf $file_location/$filename";
            $output = shell_exec($cmd1);
            return true;
        } else {
            $this->log('s3uploadfailed,' . $output);
            exit;
        }
    }

    public function log($data)
    {
        $log  = date("F j, Y, g:i a") . ", " . $data . PHP_EOL;
        file_put_contents('/var/log/httpd/log_.txt', $log, FILE_APPEND);
    }
} // class

$aws = new Aws();
$currentYear = date('Y');
$month = 12;
while ($month >= 1) {
    $monthString = $month < 10 ? "0$month" : $month;
    $i = 1;
    $totalDays = cal_days_in_month(CAL_GREGORIAN, $month, $currentYear);
    if ($monthString == date('m')) {
        $totalDays = date('d') - 3;
    }
    while ($i <= $totalDays) {
        $date = ($i < 10) ? "0$i-$monthString-$currentYear" : "$i-$monthString-$currentYear";
        $aws->list_folder($date);
        $i++;
    }
    $month--;
}
