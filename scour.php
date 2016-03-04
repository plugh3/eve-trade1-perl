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
        $dir_home = getenv("HOME");
        $dir_export = $dir_home.'/Library/Application Support/EVE Online/p_drive/User/My Documents/EVE/logs/Marketlogs/';
        break;
    case "windows nt":
        $dir_home = getenv("HOMEDRIVE").getenv("HOMEPATH");
        $dir_export = $dir_home.'\\Documents\\EVE\\logs\\Marketlogs\\';
        break;
    default:
        echo ">>> unknown OS type ".php_uname("s")."\n";
        exit;
}        
$fname_cache = 		'cache-ivee2.txt';


//
//initialize iveeCrest
//
require_once(__DIR__ . DIRECTORY_SEPARATOR . 'iveeCrestInit.php');
//instantiate the CREST client, passing the configured options
$client = new iveeCrest\Client(
    iveeCrest\Config::getCrestBaseUrl(),
    iveeCrest\Config::getClientId(),
    iveeCrest\Config::getClientSecret(),
    iveeCrest\Config::getUserAgent(),
    iveeCrest\Config::getClientRefreshToken()
);
$cw = $client->cw;
//instantiate an endpoint handler
$handler = new iveeCrest\EndpointHandler($client);
// prime cache
$fnameCache = __DIR__ . DIRECTORY_SEPARATOR . $fname_cache;
$client->importCache($fnameCache);
$handler->getRegions();
$handler->getMarketTypeHrefs();
$client->exportCache($fnameCache);
// good to go



function fmtDigits($x, $digits=1) {
	$fmt = "%0.".$digits."f";
	return sprintf($fmt, $x);
}
function fmtPct($x, $digits=1) {
	$allDigits = 4 + $digits;
	$fmt = '%'.allDigits.'.'.$digits."f%%";
	return sprintf($fmt, 100.0 * $x);
}

//$invalidGroups = array(0-11, 13-14, 16-17, 19, 23, 29, 32, 92, 104);
function isValidItem($x) {
	global $handler;
	$marketHrefs = $handler->getMarketTypeHrefs();
	if (!isset($marketHrefs[$x])) return false;

	$invalidItems = array(49, 50, 51, 52, 53, 270, 670, 681, 682);
	$deprecatedItems = array(784, 935, 943, 947);
	if (in_array($x, $invalidItems)) return false;
	if (in_array($x, $deprecatedItems)) return false;

	if ($x >=   0 && $x <=  17) return false;
	if ($x >=  24 && $x <=  33) return false; // groups 13, 14, 16, 17, [not 18], 19
	if ($x >=  49 && $x <=  59) return false; // group 24
	if ($x >= 164 && $x <= 166) return false; // group 23
	
	return true;
}


// mysql
function selectItems($whereClause) {
	require_once('mysql_login.php');
	$db_server = mysql_connect($db_hostname, $db_username, $db_password);
	if (!$db_server) die("unable to connect to mysql: ".mysql_error());

	$db_database = 'evesdd';
	$db_table = '`invtypes`';
	mysql_select_db($db_database);
	$query = "SELECT * FROM ".$db_table." ".$whereClause;
	$result = mysql_query($query);
	if (!$result) die("query failed: ".mysql_error());

	$nItems = mysql_num_rows($result);
	echo "mysql pass 1 (volume): ".number_format($nItems)."\n";
	for ($i = 0; $i < $nItems; $i++) {
		$itemID = mysql_result($result, $i, 'typeId');
		$itemName = mysql_result($result, $i, 'typeName');
		if (!isValidItem($itemID)) continue;
		$ret[] = $itemID;
		#if ($i % 500 == 0) echo(sprintf("%6d %s\n", $itemID, $itemName));
	}

	mysql_free_result($result);
	mysql_close($db_server);
	
	sort($ret);
	return $ret;
}








$reg_id_jita = 		10000002;
$reg_id_amarr = 	10000043;
$reg_id_dodixie = 	10000032;
$reg_id_rens = 		10000030;
$Hubs = array( 
	$reg_id_jita,
	$reg_id_amarr,
	$reg_id_dodixie,
	$reg_id_rens,
);



// main()


// 1. get list of items WHERE volume < 8967m3 (22876)
$itemList = selectItems("WHERE `volume` < 8967");
echo "mysql pass 2 (group):  ".number_format(count($itemList))."\n";

// 2. issue Crest requests for each (hub x item x orderType)

// 3. check if profitable

// 4. output list of profitables (from x to x item)
    


// fill queue
foreach ($itemList as $itemID) {
	foreach ($Hubs as $regionID) {
		### item x region x "buy"
		$superqueue[] = join_row($itemID, $regionID, true); 
		### item x region x "sell"
		$superqueue[] = join_row($itemID, $regionID, false);
	}
}
echo "fill queue x".count($superqueue)."\n";

function array_tack(&$big, $small) {
	foreach ($small as $x) {
		$big[] = $x;
	}
}

// divide queue[] into batches
$batch_size = 1000;
$n_orig = count($superqueue);
$n_batches = intval($n_orig, $batch_size);
$rollover = array();
for ($b = 0; $b < $n_batches; $b++) {
	$batch_start = $b * $batch_size;
	$queue = array_slice($superqueue, $batch_start, $batch_size);
	array_tack($queue, $rollover);

	// loop until GET queue is empty
	$pass = 0;
	while (! empty($queue)) {
		$pass++; if ($pass > 1) { echo "\x07"; }
		$suffix = ($pass == 1) ? ("") : (", Pass #$pass");
		echo ">>> batch #$b (".count($queue).")$suffix\n";

		// setup args for getMultiMarketOrders()
		$typeIDs 	= array();
		$regionIDs 	= array();
		$bidTypes 	= array();
		foreach ($queue as $key => $queueItem) {
			list($itemID, $regionID, $bidType) = split_row($queueItem);
			$typeIDs[] 		= $itemID +0;
			$regionIDs[] 	= $regionID +0;
			$bidTypes[] 	= $bidType &&true;
		}
		
		// populate Orders[reg][item][]
		$suffix = ($pass == 1) ? ("") : (", Pass #$pass");
		echo time2s()."php.getMulti(".count($typeIDs).")$suffix\n";
		try {
			$handler->getMultiMarketOrders2(
				$typeIDs, 
				$regionIDs, 
				$bidTypes,
				function(\iveeCrest\Response $response) use (&$queue) {

					// parse parameters from URL
					$url = $response->getInfo()['url'];
					list($item_id, $reg_id, $bid_type) = decode_url($url);
					$queueItem = join_row($item_id, $reg_id, $bid_type);
					#echo "got >$queueItem<\n";
					
					// remove from queue
					array_remove($queue, $queueItem); 
					#echo ".";
					
				
					
					// reporting
					/*
					$n_rem = count($queue);
					$n_done = $n_orig - $n_rem;
					$status = sprintf("%s complete", fmtPct($n_done / $n_orig));
					for ($x = 0; $x < strlen($status); $x++) { echo "\b"; }
					echo $status;
					flush();
					*/
									
					// orders: main body of http response
					//$orders = $response->content->items;                

		/*                
					if (isset($Orders[$reg_id][$item_id])) {
						$Orders[$reg_id][$item_id]->orders = array_merge($Orders[$reg_id][$item_id]->orders, $orders);
					} else {
						$Orders[$reg_id][$item_id] = new \stdClass();
						$Orders[$reg_id][$item_id]->row = $row;
						$Orders[$reg_id][$item_id]->orders = $orders;
					}
		*/
				},
				function (\iveeCrest\Response $r) {
					//echo " HTTP ".$r->getInfo()['http_code']."\n";
					#echo time2s()."php.getMultiMarketOrders() error, http code ".$r->getInfo()['http_code']."\n";
					//echo "\x07"; # beep
					//if ($r->getInfo()['http_code'] == 0) { var_dump($r); }
				},
				false // disable caching for getMultiMarketOrders() call (reduce memory)
			); // end getMultiMarketOrders() call
			$out = sprintf("%7.1f", $client->cw->max_rate)." GET/s";
			echo($client->cw->backspace(strlen($out)));
			echo $out." peak\n";
			$client->cw->max_rate = 0.0;
		} catch (\iveeCrest\Exceptions\InvalidArgumentException $e){
			if (preg_match('/TypeID=[0-9]+ not found in market types/', $e->getMessage())) {
				echo "matched\n";
			// do nothing
			} else {
				echo "not matched; msg = >".$e->getMessage()."<\n";
				//throw($e);
			}
		}

		// push leftovers to next batch (unless this is last batch)
		if (count($queue)) { echo time2s().count($queue)." leftovers\n"; }
		if ($b < $n_batches - 1) {
			$rollover = $queue;
			$queue = array();
		}
	}
}
echo "done\n";

function join_row($reg, $item, $is_bid)
{
	$sep = "~";
	$ary = array($reg +0, $item +0, $is_bid +0);
	return join($sep, $ary);
}
function split_row($row)
{
	$sep = "~";
	list ($reg, $item, $is_bid) = split($sep, $row);
	$ary = array($reg +0, $item +0, $is_bid +0);
	return $ary;
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
	echo "array_remove() failed >$val<\n";
}
function beep() {
	echo "\x07";
}
function time2s($time = '')
{
    if ($time == '') { $time = time(); }
    return date("h:i:sa ", $time - 8*60*60);
}
