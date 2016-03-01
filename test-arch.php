<?php

//echo time2s()."defer ".($last2[$row] + 5*60 - $time)."s $reg_name-$item_name\n"; // print
//$item_fname2iname = array('k1' => 'v1', 'k2' => 'v2'); // hash

echo ">>> php_uname() ".php_uname("s")."\n";

switch (strtolower(php_uname("s"))) {
    case "darwin":
        $dir_home = getenv("HOME");
        $dir_export = $dir_home.'/Library/Application Support/EVE Online/p_drive/User/My Documents/EVE/logs/Marketlogs';
        break;
    case "windows nt":
        $dir_home = getenv("HOMEDRIVE").getenv("HOMEPATH");
        $dir_export = $dir_home.'\\Documents\\EVE\\logs\\Marketlogs';
        break;
    default:
        echo ">>> unknown OS type ".php_uname("s")."\n";
        exit;
}        
echo ">>> home ".$dir_home."\n";
echo ">>> logs ".$dir_export."\n";
if (file_exists($dir_export)) { echo "Success!\n"; } else { echo "Failure\n"; }
