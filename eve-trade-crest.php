<?php


// primer
//echo time2s()."defer ".($last2[$row] + 5*60 - $time)."s $reg_name-$item_name\n"; // print
//$_item_fname2name = array('k1' => 'v1', 'k2' => 'v2'); // hash
//iterator
//concat

$debugStr = "Gist X-Type Large Shield Booster";

// OS-specific stuff
switch (strtolower(php_uname("s"))) {
    case "darwin":
		$dir_sep = "/";
        $dir_home = getenv("HOME");
        $dir_export = $dir_home.'/Library/Application Support/EVE Online/p_drive/User/My Documents/EVE/logs/Marketlogs/';
        break;
    case "windows nt":
		$dir_sep = "\\";
        $dir_home = getenv("HOMEDRIVE").getenv("HOMEPATH");
        $dir_export = $dir_home.'\\Documents\\EVE\\logs\\Marketlogs\\';
        break;
    default:
        echo ">>> unknown OS type ".php_uname("s")."\n";
        exit;
}        
$fname_crest_reqs = 'data-dash2crest.txt';
$fname_cache = 		'cache-ivee.txt';


//initialize iveeCrest. Adapt path as required.
require_once(__DIR__.$dir_sep.'iveeCrestInit.php');
//instantiate the CREST client, passing the configured options
$client = new iveeCrest\Client(
    iveeCrest\Config::getCrestBaseUrl(),
    iveeCrest\Config::getClientId(),
    iveeCrest\Config::getClientSecret(),
    iveeCrest\Config::getUserAgent(),
    iveeCrest\Config::getClientRefreshToken()
);
//instantiate an endpoint handler
$handler = new iveeCrest\EndpointHandler($client);

// prime cache
$fnameCache = __DIR__.$dir_sep.$fname_cache;
$client->importCache($fnameCache);
//$client->getEndpoint();
$handler->getRegions();
$handler->getMarketTypeHrefs();
$client->exportCache($fnameCache);
// good to go


// item_name2fname(): convert itemname to filename
// items are sometimes spelled differently in Marketlog filenames
// this backwards approach makes for easier cut-and-paste with Perl version of same
// map: file name => item name
$_item_fname2name = array(
	'GDN-9 Nightstalker Combat Goggles' 		=> 'GDN-9 "Nightstalker" Combat Goggles',
	'SPZ-3 Torch Laser Sight Combat Ocular Enhancer (right_black)' => 'SPZ-3 "Torch" Laser Sight Combat Ocular Enhancer (right/black)',
);
// map: item name => file name
$_item_name2fname = array();
foreach ($_item_fname2name as $fname => $iname) {
  $_item_name2fname[$iname] = $fname;
}
function item_name2fname($name) {
	// brute force
	global $_item_name2fname;
	if (array_key_exists($name, $_item_name2fname)) { return $_item_name2fname[$name]; }
	// algorithmic
	$name = str_replace("/", "_", $name); 
    $name = str_replace(":", "_", $name); 
	return $name;
}


$sep = '~';


function set_remove(array &$set, $id) {
    for($i = 0; $i < count($set); $i++) {
        if ($set[$i] == $id) { array_splice($set, $i, 1); return; }
    }
}




// main()

$last = 0;          // time of last import (of crest request file)
$last2 = array();   // time of last export, by filename
$last_empty = 0;
while (1)
{
    $fnameReqsShort = $fname_crest_reqs;
    $fnameReqs = __DIR__ . DIRECTORY_SEPARATOR . $fnameReqsShort;
	while (!file_exists($fnameReqs)) { sleep(1); }

    // wait for request file update
    clearstatcache();
	$mtime = filemtime($fnameReqs);
    while ($mtime <= $last) { 
		sleep(1); 
		clearstatcache();
		$mtime = filemtime($fnameReqs);
	} 

    
    // import request file => rowsRaw[]
    $fh = fopen($fnameReqs, 'r') or die("Failed to open $fname");
    flock($fh, LOCK_EX);
    $rowsRaw = array();
    while (($row = fgets($fh)) !== false)
    {
        $row = rtrim($row);
        $rowsRaw[] = $row;
    }
    flock($fh, LOCK_UN);
    fclose($fh);

    if (count($rowsRaw) == 0) { 
      if (!$last_empty) { echo time2s()."php (empty request list)\n"; $last_empty = 1;} 
    } else { 
      $last_empty = 0; 
    }

    // aggregate rows by region => rowsByRegion[][]
    $rowsByRegion = array();
    $time = time();
    foreach ($rowsRaw as $row)
    {
        list($reg_id, $reg_name, $item_id, $item_name, $is_bid) = explode($sep, $row);
        
        // crest get cooldown (15s)
        $cooldown_crest = 30;
        if (array_key_exists($row, $last2) && $time - $last2[$row] <= $cooldown_crest) { 
            //echo time2s()."defer ".($last2[$row] + 5*60 - $time)."s $reg_name-$item_name\n";
            continue; 
        }
        $last2[$row] = $time;

        if (!isset($rowsByRegion[$reg_id])) { $rowsByRegion[$reg_id] = array(); } // necessary?
        $rowsByRegion[$reg_id][] = $row;
    }
    if (count($rowsByRegion) > 0) { $last = $mtime; }
    if (count($rowsByRegion) > 0) { echo time2s()."php.requested(".count($rowsRaw).")\n";}
    
    // get crest data => Orders[r][i][]
    // via aysnc multiget for each region
    $Orders = array();
    // loop: region
    foreach ($rowsByRegion as $reg_id => $rows) {
      if (!array_key_exists($reg_id, $Orders)) { $Orders[$reg_id] = array(); }

      // setup args for multiGet()
      $typeIds = array(); // multiget arg AND while loop condition
      $rowByItem = array();
      // loop: item
      foreach ($rows as $row) 
      {
          list($reg_id2, $reg_name, $item_id, $item_name, $is_bid) = explode($sep, $row);
          // TODO: check reg_ids match
          $typeIds[] = $item_id;
          $rowByItem[$item_id] = $row;          
      }

      // loop until GET queue is empty (some fail b/c rate limits or ???)
      $pass = 0;
      while (! empty($typeIds)) {
        $pass++; if ($pass > 1) {echo "\x07";}
        
        // populate Orders[reg][item][]
        $suffix = ($pass == 1) ? ("") : (", Pass #$pass");
        echo time2s()."php.getMulti(".count($typeIds).") region=$reg_id$suffix\n";
        $handler->getMultiMarketOrders(
            $typeIds, 
            $reg_id2, 
            #function(\iveeCrest\Response $response) use ($rowByItem, &$Orders, $reg_id, &$typeIds) {
            function(\iveeCrest\Response $response) use ($rowByItem, &$Orders, &$typeIds) {

                // item ID: parse from URL
                $url = $response->getInfo()['url'];
				list($item_id, $reg_id, $bid_type) = decode_url($url);
                #$item_id = url2item($url);
                array_remove($typeIds, $item_id); // remove item_id from GET queue

                // region ID: lookup in dictionary of file rows (eve-trade-crest-reqs.txt)
                $row = $rowByItem[$item_id +0];
                #$sep = '~'; // TODO: use global instead
                #list($reg_id, $reg_name, $item_id2, $item_name, $is_bid) = explode($sep, $row);

                // orders: main body of http response
                // getMulti() generates 2 GETs for each region.item (buyOrders + sellOrders)
                // so we need to merge responses into 1 array
                $orders = $response->content->items;                
                
                if (isset($Orders[$reg_id][$item_id])) {
                    $Orders[$reg_id][$item_id]->orders = array_merge($Orders[$reg_id][$item_id]->orders, $orders);
                } else {
                    $Orders[$reg_id][$item_id] = new \stdClass();
                    $Orders[$reg_id][$item_id]->row = $row;
                    $Orders[$reg_id][$item_id]->orders = $orders;
                }
            },
            function (\iveeCrest\Response $r) use ($rowByItem) {
              echo " HTTP ".$r->getInfo()['http_code']."\n";
              //echo time2s()."php.getMultiMarketOrders() error, http code ".$r->getInfo()['http_code']."\n";
              //echo "\x07"; # beep
              //if ($r->getInfo()['http_code'] == 0) { var_dump($r); }
            },
			false // disable caching for getMultiMarketOrders() call (reduce memory)
        ); // end getMultiMarketOrders() call
        echo " [peak ".sprintf("%.1f", $client->cw->max_rate)."]";
		echo "\n";
		$client->cw->max_rate = 0.0;
      }
    }
    
    // export to Marketlogs files
    $nexports = 0;
    // TODO: check if more recent Marketlog file already exists
    $exportQueue = array();
    foreach ($Orders as $reg_id => $OrdersByItem) {
        foreach ($OrdersByItem as $i => $mkt) {
            $row = $mkt->row;
            $orders = $mkt->orders;
            $text = formatHeader().formatOrders($orders, $reg_id);
            $fname2 = getExportFilename($row);

            $n = count(explode("\n", $text))-1;
            $fname_short = substr($fname2, strpos($fname2, $dir_export) + strlen($dir_export));
            //echo time2s()."export (x$n) $fname_short\n";

            $exportQueue[$fname2] = $text;
            //export($fname2, $text);
            $nexports++;
        }
    }
    if ($nexports > 0) { echo time2s()."php.export($nexports)\n"; }
    foreach ($exportQueue as $fname2 => $text) {
      export($fname2, $text);
    }
    
    #echo time2s()."sleep 1 sec\n";
    sleep(1);
}
function regexp_esc($x)
{
	return preg_quote($x, '/');
}
function decode_url($url)
{
    $base_esc = regexp_esc(iveeCrest\Config::getCrestBaseUrl());
	$re =  $base_esc.'market\/([0-9]{8})\/orders\/(buy|sell)\/\?type\='.$base_esc.'types\/([0-9]{1,6})\/';
	preg_match("/$re/", $url, $match);
	
	$itemID = $match[3];
	$regionID = $match[1];
	$bidType = ($match[2] == "buy");
    return array($itemID, $regionID, $bidType);
}
function array_remove(array &$ary, $val) {
    for($i = 0; $i < count($ary); $i++) {
        if ($ary[$i] == $val) { array_splice($ary, $i, 1); return; }
    }
}
function url2item($url)
{
    $base = iveeCrest\Config::getCrestBaseUrl();
    $match = '?type='.$base.'types/'; 
    if (strpos($url, $match) === false) return 0;
    $item_id = substr($url, strpos($url, $match) + strlen($match));
    $item_id = substr($item_id, 0, strlen($item_id) - 1); ## chomp trailing '/'
    return $item_id;
}
function url2buy($url)
{
    return (strpos($url, 'orders/sell') === false);
}
function getExportFilename($row)
{
	### inputs: need region_name and item_name from $row
    global $sep;
    global $dir_export;

    // region
    list($reg_id, $fname_region, $item_id, $fname_item, $is_bid) = explode($sep, $row);

    // item
    if (!$fname_item) { print ">>> malformed fname region=$fname_region, item=\"$fname_item\" [$item_id]\n\$row=>$row<\n"; exit;}
	$fname_item = item_name2fname($fname_item);

    // time
    $fname_time = date("Y.m.d His", time() - 300); ### crest data is 5 mins delayed, so backdate timestamp

    return $dir_export.$fname_region.'-'.$fname_item.'-'.$fname_time.'.txt';        
}
function export($fname, $text)
{
    global $dir_export;

    $fname_short = substr($fname, strpos($fname, $dir_export) + strlen($dir_export));
    $n = preg_match("/^(.*)-[0-9]{4}.[0-9]{2}.[0-9]{2} [0-9]{6}.txt$/", $fname_short, $match);
    $fname_short2 = $match[1];
	//global $debugStr;
    //if ( strpos($fname_short, $debugStr) !== FALSE) { echo time2s()."crest-php.export() \"$fname_short\"\n"; }

    $fh = fopen($fname, 'w') or die("Failed to open $fname");
    flock($fh, LOCK_EX);
    fwrite($fh, $text);
    flock($fh, LOCK_UN);
    fclose($fh);
}
function formatHeader()
{
    $hdr = "price,volRemaining,typeID,range,orderID,volEntered,minVolume,bid,issueDate,duration,stationID,regionID,solarSystemID,jumps,\r\n";
    $ret = $hdr;
    return $ret;
}
function formatOrders($orders, $reg_id)
{
    $ret = '';
    foreach ($orders as $x)
    {
        $price = sprintf("%.2f", $x->price); // NEED
        $volRemaining = $x->volume;          // NEED
        $typeID = $x->type->id;
        $range = $x->range;
        if ($range == 'region')  { $range = 32767; }
        if ($range == 'station') { $range = -1; }
        $orderID = $x->id;
        $volEntered = $x->volumeEntered;
        $minVolume = $x->minVolume;          // NEED
        $bid = ($x->buy) ? 'True' : 'False';
        $issueDate = str_replace('T', ' ', $x->issued).".000";
        $duration = $x->duration;
        $stationID = $x->location->id;
        $regionID = $reg_id;
        $solarSystemID = 30000000; //$x->location->name; // convert station to solar system
        $jumps = 32768; // = Region-wide + 1 // TODO: calculate how many jumps away from hub

        $line = "$price,$volRemaining,$typeID,$range,$orderID,$volEntered,$minVolume,$bid,$issueDate,$duration,$stationID,$regionID,$solarSystemID,$jumps,\r\n";
        //echo $line;
        $ret .= $line;
    }
    return $ret;
}
function time2s($time = '')
{
    if ($time == '') { $time = time(); }
    return date("h:i:sa ", $time - 8*60*60);
}
