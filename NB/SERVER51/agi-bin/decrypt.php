#!/usr/bin/php -q
<?php

# create file handles if needed
if (!defined('STDIN')) {
    define('STDIN', fopen('php://stdin', 'r'));
}
if (!defined('STDOUT')) {
    define('STDOUT', fopen('php://stdout', 'w'));
}
if (!defined('STDERR')) {
    define('STDERR', fopen('php://stderr', 'w'));
}

while (!feof(STDIN)) {
    $temp = trim(fgets(STDIN, 4096));
    if (($temp == "") || ($temp == "\n")) {
        break;
    }
    $s = explode(":", $temp);
    $name = str_replace("agi_", "", $s[0]);
    $agi[$name] = trim($s[1]);
}
foreach ($agi as $key => $value) {
    fwrite(STDERR, "-- $key = $value\n");
    fflush(STDERR);
}
$decrypted = ($agi['extension'] ^ 890982345677654) - 98761234567890;
#$decrypted = $agi['extension']
fwrite(STDOUT, "SET VARIABLE SFID $decrypted");
fflush(STDOUT);
?>

