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
$handler->getMarketTypeHrefs(); echo "\n";
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
    // wait for request file update
    $fnameReqsShort = $fname_crest_reqs;
    $fnameReqs = __DIR__ . DIRECTORY_SEPARATOR . $fnameReqsShort;
	while (!file_exists($fnameReqs)) { sleep(1); }
    clearstatcache();
	$mtime = filemtime($fnameReqs);
    while ($mtime <= $last) { 
		sleep(1); 
		clearstatcache();
		$mtime = filemtime($fnameReqs);
	} 
    
    // import request file => crestReqs[]
    $allCrestReqs = array();
	$regionNames = array();
	$itemNames = array();
    $fh = fopen($fnameReqs, 'r') or die("Failed to open $fname");
    flock($fh, LOCK_EX);
    while (($file_row = fgets($fh)) !== false)
    {
        $file_row = rtrim($file_row);
        list($reg_id, $reg_name, $item_id, $item_name, $is_bid) = split($sep, $file_row);

		$row_mod = join_row($reg_id, $item_id, $is_bid);
        $allCrestReqs[] = $row_mod;
		$regionNames[$reg_id] = $reg_name;
		$itemNames[$item_id] = $item_name;
    }
    flock($fh, LOCK_UN);
    fclose($fh);

	// empty request file?
    if (count($allCrestReqs) == 0) { 
		if (!$last_empty) { echo time2s()."php (empty request list)\n"; $last_empty = 1;} 
    } else { 
		$last_empty = 0; 
    }

	// crest GET cooldown (45s)
    $time = time();
    foreach ($allCrestReqs as $row) {
        $cooldown_crest = 45;
        if (array_key_exists($row, $last2) && $time - $last2[$row] <= $cooldown_crest) { 
            //echo time2s()."defer ".($last2[$row] + 5*60 - $time)."s $reg_name-$item_name\n";
			array_remove($allCrestReqs, $row);
            continue; 
        }
        $last2[$row] = $time;
    }
	
	if (count($allCrestReqs) == 0) { sleep(1); continue; }
    $last = $mtime;


	//
	// fetch from Crest
	// loop until GET queue is empty (some fail b/c rate limits or ???)
	//
	
	// break into batches of 1000
	$batch_size = 1000;
	for ($b = 0; $b * $batch_size < count($allCrestReqs); $b++) {
		echo time2s()." Batch #$b (".($b*$batch_size)."-".(($b+1)*$batch_size-1)." of ".count($allCrestReqs).")\n";
		
		$crestReqs = array_slice($allCrestReqs, $b * $batch_size, $batch_size);
		$Orders	= array();
		$pass = 0;
		while (! empty($crestReqs)) {
			$pass++; 
			#if ($pass > 1) {echo "\x07";}

			// setup params for getMultiMarketOrders2()
			$typeIDs 	= array();
			$regionIDs 	= array();
			$bidTypes 	= array();
			foreach ($crestReqs as $row) {
				list($reg_id, $item_id, $is_bid) = split_row($row);
				// input
				$typeIDs[] 		= $item_id +0;
				$regionIDs[] 	= $reg_id +0;
				$bidTypes[] 	= $is_bid &&true;
				// output
				if (!array_key_exists($reg_id, $Orders)) { $Orders[$reg_id] = array(); } // init Orders[r][]
			}

			
			// populate Orders[reg][item][]
			$suffix = ($pass == 1) ? ("") : (", Pass #$pass");
			echo time2s()."php.getMulti(".count($typeIDs).")$suffix\n";
			$handler->getMultiMarketOrders2(
				$typeIDs, 
				$regionIDs, 
				$bidTypes, 
				function(\iveeCrest\Response $response) use (&$crestReqs, &$Orders) {

					// parse URL
					$url = $response->getInfo()['url'];
					list($reg_id, $item_id, $bid_type) = decode_url($url);
					$row = join_row($reg_id, $item_id, $bid_type);

					// remove from queue
					array_remove($crestReqs, $row); 

					// orders: main body of http response
					// getMulti() generates 2 GETs for each region.item (buyOrders + sellOrders)
					// but Marketlog files contain buy + sell orders, so we merge responses
					//var_dump($response->content->items); exit;
					if (!isset($response->content->items)) { return; }
					$orders = convertOrders($response->content->items);
					$response = null;
					
					if (isset($Orders[$reg_id][$item_id])) {
						$Orders[$reg_id][$item_id]->orders = array_merge($Orders[$reg_id][$item_id]->orders, $orders);
					} else {
						$Orders[$reg_id][$item_id] = new \stdClass();
						$Orders[$reg_id][$item_id]->row = $row;
						$Orders[$reg_id][$item_id]->orders = $orders;
					}
				},
				function (\iveeCrest\Response $r) {
				  //echo " HTTP ".$r->getInfo()['http_code']."\n";
				  //echo time2s()."php.getMultiMarketOrders() error, http code ".$r->getInfo()['http_code']."\n";
				  //echo "\x07"; # beep
				  //if ($r->getInfo()['http_code'] == 0) { var_dump($r); }
				},
				false // disable caching for getMultiMarketOrders() call (reduce memory)
			); // end getMultiMarketOrders() call
			
			$typeIDs = null;
			$regionIDs = null;
			$bidTypes = null;
			
			// peak rate
			$out = sprintf("%7.1f", $client->cw->max_rate)." GET/s";
			echo($client->cw->backspace(strlen($out)));
			echo $out." peak\n";
			$client->cw->max_rate = 0.0;
			
		} // loop until batch queue is empty

    // export batch to Marketlogs
	exportMarketlogs($Orders, $regionNames, $itemNames);

	
	
	} // loop over all batches
	

    #echo time2s()."sleep 1 sec\n";
    sleep(1);
}


//
// utility fns
//

function join_row($reg, $item, $is_bid)
{
	global $sep;
	return join($sep, array($reg +0, $item +0, $is_bid +0));
}
function split_row($row)
{
	global $sep;
	list ($reg, $item, $is_bid) = split($sep, $row);
	return array($reg +0, $item +0, $is_bid +0);
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
	
	$regionID = $match[1];
	$itemID = $match[3];
	$bidType = ($match[2] == "buy");
    return array($regionID, $itemID, $bidType);
}
function array_remove(array &$ary, $val) {
    for($i = 0; $i < count($ary); $i++) {
        if ($ary[$i] == $val) { array_splice($ary, $i, 1); return; }
    }
	echo "array_remove() failed >$val<\n";
}
function time2s($time = '')
{
    if ($time == '') { $time = time(); }
    return date("h:i:sa ", $time - 8*60*60);
}


//
// Marketlogs export
//

function exportMarketlogs($Orders, $regionNames, $itemNames)
{
	// queue files for export
    $exportQueue = array();
    $nexports = 0;
    foreach ($Orders as $reg_id => $regionOrders) {
        foreach ($regionOrders as $item_id => $mkt) {
			// TODO: check if more recent Marketlog file already exists

			list($reg_id2, $item_id2, $is_bid) = split_row($mkt->row);
			if ($reg_id != $reg_id2) die("inconsistent regions $reg_id $reg_id2");
			if ($item_id != $item_id2) die("inconsistent regions $reg_id $reg_id2");
			
			// file name
            $regionName = $regionNames[$reg_id];
			$itemName = $itemNames[$item_id];
            $fname2 = getExportFilename($mkt->row, $regionName, $itemName);

			// file contents
            $orders = $mkt->orders;
            $text = formatHeader().formatOrders($orders, $reg_id);
			
            //$n = count(explode("\n", $text))-1;
            //$fname_short = substr($fname2, strpos($fname2, $dir_export) + strlen($dir_export));
            //echo time2s()."export (x$n) $fname_short\n";

            $exportQueue[$fname2] = $text;
            $nexports++;
        }
    }
	
	// bulk export
    if ($nexports > 0) { echo time2s()."php.export($nexports)\n"; }
    foreach ($exportQueue as $fname2 => $text) {
      exportFile($fname2, $text);
    }	
}
function getExportFilename($row, $fname_region, $fname_item)
{
    global $sep;
    global $dir_export;

   // region
    list($reg_id, $item_id, $is_bid) = split_row($row);
    // item
    if (!$fname_item) { print ">>> malformed fname region=$fname_region, item=\"$fname_item\" [$item_id]\n\$row=>$row<\n"; exit;}
	$fname_item = item_name2fname($fname_item);
    // time
    $fname_time = date("Y.m.d His", time() - 300); ### crest data is 5 mins delayed, so backdate timestamp
    return $dir_export.$fname_region.'-'.$fname_item.'-'.$fname_time.'.txt';        
}
function exportFile($fname, $text)
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
function convertOrders($orders)
{
	$rets = array();
	foreach ($orders as $x) {
		$y = new \stdClass();
		$y->price = $x->price;
		$y->volume = $x->volume;
        $y->type = new \stdClass();
		$y->type->id = $x->type->id;
        $y->range = $x->range;
        $y->id = $x->id;
        $y->volumeEntered = $x->volumeEntered;
		$y->minVolume = $x->minVolume;
        $y->buy = $x->buy;
        $y->issued = $x->issued;
        $y->duration = $x->duration;
		$y->location = new \stdClass(); 
		$y->location->id = $x->location->id;
		$rets[] = $y;
	}
	return $rets;
}
function formatOrders($orders, $reg_id)
{
    $ret = '';
    foreach ($orders as $x)
    {
		//var_dump($x);
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
