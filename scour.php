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
$fname_data  = 		'data-scour.txt';


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



// bool isValidItem(int item_id)
// checks item ID for deprecated/invalid/etc
//$invalidGroups = array(0-11, 13-14, 16-17, 19, 23, 29, 32, 92, 104);
// "SKIN" groups: 528, 1311, 1319, 351064, 350858, 351844, 368726
//
// "SKIN" groups
// 1311 - yes
// 368726 - test items only?
//
// "SKIN" groupID query => SELECT DISTINCT groupID FROM `invtypes` WHERE typeName LIKE '% SKIN%'
function isValidItem($x) {
	global $handler;
	$marketHrefs = $handler->getMarketTypeHrefs();
	if (!isset($marketHrefs[$x])) return false;

	$invalidItems = array(49, 50, 51, 52, 53, 270, 670, 681, 682);
	if (in_array($x, $invalidItems)) return false;

	$deprecatedItems = array(784, 935, 943, 947);
	if (in_array($x, $deprecatedItems)) return false;

	if ($x >=   0 && $x <=  17) return false;
	if ($x >=  24 && $x <=  33) return false; // groups 13, 14, 16, 17, [not 18], 19
	if ($x >=  49 && $x <=  59) return false; // group 24
	if ($x >= 164 && $x <= 166) return false; // group 23
	
	return true;
}


$ItemNames = array(); // populated from mysql
function fmtItem($itemID)
{
	global $ItemNames;
	return $ItemNames[$itemID];
}


// array allItemsWhere($whereClause) - get item list from mysql
// retval - array of item IDs
// side effect - populates 
function allItemsWhere($whereClause) {
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

		// add item to ItemNames[]
		$itemName = mysql_result($result, $i, 'typeName');
		global $ItemNames;
		if (!isset($ItemNames[$itemID])) { $ItemNames[$itemID] = $itemName;}
		
		// skip if deprecated item
		if (!isValidItem($itemID)) continue;

		// add item to retval
		$ret[] = $itemID;
	}
	echo "mysql pass 2 (deprecated): ".number_format(count($ret))."\n";

	mysql_free_result($result);
	mysql_close($db_server);
	
	sort($ret, SORT_NUMERIC);
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
function fmtReg($regionID, $leftJustify = true)
{
	global $reg_id_jita, $reg_id_amarr, $reg_id_dodixie, $reg_id_rens;
	$names = array(
		$reg_id_jita	=>	"Jita", 	// 4
		$reg_id_amarr	=>	"Amarr",	// 5
		$reg_id_dodixie	=>	"Dodixie",	// 7
		$reg_id_rens	=>	"Rens",		// 4
	);

	// autojustify field width
	$maxLen = 0;
	foreach ($names as $key => $val) {
		$maxLen = max($maxLen, strlen($val));
	}
	$fmt = "%".(($leftJustify) ? "-" : "").$maxLen."s";

	return sprintf($fmt, $names[$regionID]);
}


// main()


// $AllItems[] - all purchaseable items items in game (volume < 8967m3) (=22876)
$AllItems = allItemsWhere("WHERE `volume` < 8967");

// $Orders[itemID][regionID] - datastore for Crest responses
$Orders = array();
$nsorts = 0;
function sort_orders_asc($a, $b) { global $nsorts; $nsorts++; return (($a->price - $b->price) < 0) ? -1 : 1; }
function sort_orders_dsc($a, $b) { global $nsorts; $nsorts++; return (($b->price - $a->price) < 0) ? -1 : 1; }
function add_crest_response($itemID, $regionID, $bid_type, $response)
{
	global $Orders;
	if (! isset($Orders[$itemID][$regionID])) {
		$Orders[$itemID][$regionID] = new \stdClass();
	}
	
	// crest returns orders as main body of http response
	$orders = $response->content->items;
	if ($bid_type) {
		// buy orders, sort descending
		$Orders[$itemID][$regionID]->bids = $orders;
		usort($Orders[$itemID][$regionID]->bids, "sort_orders_dsc");
	} else {
		// sell orders, sort ascending
		$Orders[$itemID][$regionID]->asks = $orders;
		usort($Orders[$itemID][$regionID]->asks, "sort_orders_asc");
	}
}
function countOrders()
{
	global $Orders;
	$nOrders = 0;
	foreach ($Orders as $itemID => $orders_by_item) {
		foreach ($orders_by_item as $regionID => $market) {
			$mkt = $Orders[$itemID][$regionID];
			$nOrders += count($mkt->bids) + count($mkt->asks);
		}
	}
	return $nOrders;
}
function freeOrders()
{
	global $Orders, $AllItems;
	foreach ($AllItems as $itemID) {
		$Orders[$itemID] = array();
	}
	$Orders = array();
}




//
// batching -- batch out crest requests, by item
// need this to stay under the memory cap
// free up data structures between batches
// all orders for item X have to be in the same batch
//
function initBatch($numItems, $reqsPerItem)
{
	global $batch_size;
	global $maxCrestReqs;
	$batch_size = intval($maxCrestReqs / $reqsPerItem); // items per batch
	global $n_items;
	$n_items = $numItems;
	global $n_batches;
	$n_batches = intval($n_items / $batch_size) + 1;
}
// nextBatch() - queue next batch of crest requests, return item list
// queue = array of (item x region x bidType) 
// retval = list of items queued
function nextBatch(&$q, $rollover)
{
	// calculate batch
	global $AllItems, $n_batch, $batch_size;
	$batch_start_i = $n_batch * $batch_size;
	if ($batch_start_i >= count($AllItems)) { return array(); }
	$newItems = array_slice($AllItems, $batch_start_i, $batch_size);

	// add items
	queueItemsAllHubs($q, $newItems); // new items for current batch
	array_tack($q, $rollover); // carryover from previous batch

	// next batch
	$n_batch++;
	return $newItems;
}
// queueItemsAllHubs() - add to master list of crest requests 
// each item x each region x (buy + sell) orders
// (12k items => 95k requests)
function queueItemsAllHubs(&$q, $items) {
	foreach ($items as $itemID) {
		// add requests for all hub stations
		global $Hubs;
		foreach ($Hubs as $regionID) {
			queueRequest($q, $itemID, $regionID, true); 	// buy order
			queueRequest($q, $itemID, $regionID, false);	// sell order
		}
	}
}

// primitive methods for queue
function queueRequest(&$q, $itemID, $regionID, $bidType) {
	$q[] = q_join_row($itemID, $regionID, $bidType);
}
function q_join_row($reg, $item, $is_bid)
{
	$sep = "~";
	$ary = array($reg +0, $item +0, $is_bid +0);
	return join($sep, $ary);
}
function q_split_row($row)
{
	$sep = "~";
	list ($reg, $item, $is_bid) = split($sep, $row);
	$ary = array($reg +0, $item +0, $is_bid +0);
	return $ary;
}





//
// main loop
//	

$maxCrestReqs = 1000;
initBatch(count($AllItems), 8);


$q = array();
$rollover = array();
$items = array();
function initLoop(&$q) {
	// 1. delete previous data file
	global $fname_data;
	if (file_exists($fname_data)) {
		unlink($fname_data);
	}
	
	// 2. prime first batch of requests
	global $items;
	$items = nextBatch($q, array());
	global $n_batch;
	$n_batch = 0;
}

// analytics
$n_orig = count($AllItems) * 8;
$t_scour = microtime(true);
$all_profitables = 0;
$all_orders = 0;
$all_calcs = 0;
for (initLoop($q); count($q) > 0; $items = nextBatch($q, $rollover)) {

	// loop until GET queue is empty
	$my_batch_size = count($q); // initial size of queue
	$pass = 0;
	// analytics
	$n503s = 0;
	$t_start = microtime(true);
	while (! empty($q)) {
		// debug
		$pass++; if ($pass > 1) { beep(); }
		$suffix = ($pass == 1) ? ("") : (", Pass #$pass");
		echo ">>> batch $n_batch of $n_batches   (".(($n_batch-1)*$batch_size*8)." - ".((($n_batch-1)*$batch_size*8) + count($q) - 1).")$suffix\n";

		// setup args for getMultiMarketOrders()
		$typeIDs 	= array();
		$regionIDs 	= array();
		$bidTypes 	= array();
		foreach ($q as $key => $queueItem) {
			list($itemID, $regionID, $bidType) = q_split_row($queueItem);
			$typeIDs[] 		= $itemID +0;
			$regionIDs[] 	= $regionID +0;
			$bidTypes[] 	= $bidType &&true;
		}
		
		// process crest responses populate Orders[reg][item][] from crest responses
		$suffix = ($pass == 1) ? ("") : (", Pass #$pass");
		echo time2s()."php.getMulti(".count($typeIDs).")$suffix\n";
		$handler->getMultiMarketOrders2(
			$typeIDs, 
			$regionIDs, 
			$bidTypes,
			function(\iveeCrest\Response $response) use (&$q, &$Orders) {

				// parse parameters from URL
				$url = $response->getInfo()['url'];
				list($itemID, $regionID, $bid_type) = decode_url($url);
				$queueItem = q_join_row($itemID, $regionID, $bid_type);
				
				// remove from queue
				array_remove($q, $queueItem); 
				
				// process Crest response
				add_crest_response($itemID, $regionID, $bid_type, $response);
			},
			function (\iveeCrest\Response $r) use (&$n503s) {
				$code = $r->getInfo()['http_code'];
				if ($code == "503") { $n503s++; }
				//echo " HTTP $code\n";
				//echo time2s()."php.getMultiMarketOrders() error, http code $code\n";
				//if ($code == 0) { var_dump($r); }
			},
			false // false = caching disabled to reduce memory
		); // end getMultiMarketOrders() call

		
		// peak rate sample 
		$out = sprintf("%7.1f", $client->cw->max_rate)." GET/s";
		echo($client->cw->backspace(strlen($out)));
		echo $out." peak";
		echo " (".fmtPct2($n503s, $my_batch_size)." errors)";
		echo "\n";
		$client->cw->max_rate = 0.0;
			
		// push leftovers to next batch (unless this is last batch)
		if (count($q)) { echo time2s().count($q)." leftovers\n"; }
		if ($n_batch < $n_batches - 1) {
			$rollover = $q;
			$q = array(); // free memory (!)
		}
		
	}
	
	// timer
	$t_batch = microtime(true) - $t_start;
	echo time2s()."=> ".fmtFlt($t_batch)."s\n";
	
	
/*
	// find profitable trades by chewing crest responses
	$profitableItems = array();
	// in: $Orders[]
	// out: $profitableItems[]
	$profitableItems = array();
	eachItemAllRoutes(
		$items, 
		function($itemID, $from, $to) use (&$profitableItems) {
			if (isProfitable($itemID, $from, $to)) { $profitableItems[] = array($itemID, $from, $to); }
		}
	);
*/
	$profitables = calcProfitables($items);
	exportProfitables($profitables);

	logLoop(); // do before freeing $profitables

	// free memory
	freeOrders(); // CRITICAL
	$profitables = array();
}
logEnd();


function logLoop() 
{
	global $profitableItems;
	global $ncalcs;
	global $nsorts;

	echo time2s().fmtInt(count($profitableItems))." profitable trades\n";
	echo time2s().fmtInt($ncalcs)." trades tested\n"; $ncalcs = 0;
	echo time2s().fmtInt($nsorts)." sort comparisons\n"; $nsorts = 0;
	echo time2s().fmtInt(countOrders())." orders received\n";

	global $all_profitables;
	global $all_orders;
	global $all_calcs;
	$all_profitables += count($profitableItems);
	$all_orders += countOrders();
	$all_calcs += $ncalcs;	
}
function logEnd() 
{
	global $profitableItems;
	global $all_profitables;
	global $all_orders;
	global $all_calcs;
	global $t_scour;

	echo "---------\n";
	echo time2s().">>> full scour ".fmtSec(microtime(true) - $t_scour)."\n";
	echo time2s().fmtInt($all_profitables, 9)." profitable trades\n";
	echo time2s().fmtInt($all_calcs, 9)." trades tested\n";
	echo time2s().fmtInt($all_orders, 9)." orders received\n";
}




// calcProfitables(): check $items list for profitable trades in $Orders[]
// scan crest responses for profitable trades
function calcProfitables($items) 
{
	$profitables = array();
	eachItemAllRoutes(
		$items, 
		function($itemID, $from, $to) use (&$profitables) {
			if (isProfitable($itemID, $from, $to)) { $profitables[] = array($itemID, $from, $to); }
		}
	);
	return $profitables;
}
// exportProfitables() - export profitable trades to file
function exportProfitables($trades)
{
	$text = "";
	$sep = '~';
	foreach ($trades as $x) {
		list($itemID, $from, $to) = $x;
		$text .= $itemID.$sep.$from.$sep.$to."\r\n";
	}
	global $fname_data;
	appendFile($fname_data, $text);
}




$dir_export = __DIR__;
function appendFile($fname, $text)
{
	echo time2s()."appendFile() \"$fname\"\n";
	
    global $dir_export;
    $fname_short = substr($fname, strpos($fname, $dir_export) + strlen($dir_export));
    //$n = preg_match("/^(.*)-[0-9]{4}.[0-9]{2}.[0-9]{2} [0-9]{6}.txt$/", $fname_short, $match);
    //$fname_short2 = $match[1];
    //echo time2s()."crest-php.export() \"$fname_short\"\n";

    $fh = fopen($fname, 'a') or die("Failed to open $fname");
    flock($fh, LOCK_EX);
    fwrite($fh, $text);
    flock($fh, LOCK_UN);
    fclose($fh);
}



// TODO: class CrestReq
// (regionID x itemID x bidType)
$ncalcs = 0;
// isProfitable() - checks if Orders[] has profitable trade for this (item x from x to)
// even if only $0.01 profit after tax
function isProfitable($itemID, $from, $to)
{
	global $Orders, $ncalcs;
	$ncalcs++;
	
	if (! isset($Orders[$itemID][$from])) { return false; }
	if (! isset($Orders[$itemID][$to])) { return false; }
	if (! isset($Orders[$itemID][$from]->asks)) { return false; }
	if (! isset($Orders[$itemID][$to]->bids)) { return false; }
	if (count($Orders[$itemID][$from]->asks) == 0) { return false; }
	if (count($Orders[$itemID][$to]->bids) == 0) { return false; }
	
	$asks = $Orders[$itemID][$from]->asks;
	$bids = $Orders[$itemID][$to]->bids;

	$bestAskPrice = $asks[0]->price;
	$bestBidPrice = $bids[0]->price;

	$netTax = 0.9925;
	$bestProfit = (($bestBidPrice * $netTax) - $bestAskPrice);

	// debug
	/*
	if ($bestProfit < 0.0) { 
		echo "[$itemID] ".fmtItem($itemID)."\n";
		foreach ($asks as $ask) {
			$price = $ask->price;
			echo "   ".fmtReg($from)." sell ".fmtMoney($price, 16)."\n";
		}
		echo "                              ---\n";
		foreach ($bids as $bid) {
			$price = $bid->price;
			echo "   ".fmtReg($to)  ." buy  ".fmtMoney($price, 16)."\n";
		}
		echo "   "."profit =      ".sprintf("%16s", fmtFlt($bestProfit, 2))."\n";
	}
	*/
	
	return ($bestProfit > 0.0);
}


// takes fn(from, to)
function forAllRoutes(callable $block) {
	global $Hubs;
	foreach ($Hubs as $from) {
		foreach ($Hubs as $to) {
			if ($from === $to) { continue; }
			$block($from, $to);
		}
	}
}
// takes fn(item, from, to)
function eachItemAllRoutes($items, callable $block) {
	foreach ($items as $itemID) {
		forAllRoutes(function($from, $to) use ($block, $itemID) {
			$block($itemID, $from, $to);
		});
	}
}



echo time2s()."done\n";


// crest response format
/*
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

		// Marketlogs format
        $line = "$price,$volRemaining,$typeID,$range,$orderID,$volEntered,$minVolume,$bid,$issueDate,$duration,$stationID,$regionID,$solarSystemID,$jumps,\r\n";
*/









// Timer Class
//
// --class methods--
//tStart("label")
//tEnd("label") => returns elapsed
//tGet("label") => returns elapsed
//tReset("label")
//fmtSec
//fmtUsec
//
// --instance methods--
// t->start()
// t->end() => returns elapsed
// t->get() => returns elapsed
// t->reset()


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
function array_tack(&$big, $small) {
	foreach ($small as $x) {
		$big[] = $x;
	}
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
    return date("h:i:sa ", $time - 7*60*60);
}




// SampleRate class
// calculates rate of events over fixed period
class SampleRate {
	

	protected $samplePeriod = 1.0;  ## sample period (sec) used to calculate instantaneous rate
	public $currRate = 0.0;
	public $maxRate = 0.0;

	protected $countsByTime = array();
	protected $n_gets = 0;
	public function recordEvent(callable $recordedRate)
	{

		### event counter + current time
		$now = microtime(true);
		$this->n_gets++;

		### add to history
		array_unshift($this->countsByTime, array($this->n_gets, $now));

		### find far side of sample window
		$n_sample = 0;
		$t_sample = $now;
		for ($i_sample = 0; $i_sample < count($this->countsByTime); $i_sample++) {
			list ($n_sample, $t_sample) = $this->countsByTime[$i_sample];
			if ($now - $t_sample >= $samplePeriod) { break; }
		}

		### calculate rate (n/usec)
		$rate = ($now != $t_sample) 
			? (($this->n_gets - $n_sample) / ($now - $t_sample))
			: (0.0);
		$this->currRate = $rate;
		if ($rate > $this->max_rate) { $this->max_rate = $rate; }

		$recordedRate($rate);
	}

	// I/O
	protected $outputFormat = "%7.1f %s";
	protected $outputUnits	= "GET/s"; 		// set in constructor
	public function outputRate($x)
	{
		### output current rate
		$out = sprintf($outputFormat, $x, $outputUnits);
		echo($this->backspace(strlen($out)));
		echo $out;
	}
	public function clearOutput() 
	{
		$out = sprintf($outputFormat, 1.0, $outputUnits);
		echo($this->backspace(strlen($out)));	
	}
	protected function backspace($x = 1)
	{
		$ret = "";
		for ($i = 0; $i < $x; $i++) { $ret .= "\x8"; }
		return $ret;
	}
}

function fmtFlt($x, $digits=1) {
	$fmt = "%0.".$digits."f";
	return sprintf($fmt, $x);
}
function fmtInt($x, $fieldLen=0) {
	$commafied = number_format($x);

	// count commas added
	$raw = sprintf("%d", $x);
	$nCommas = strlen($commafied) - strlen($raw);

	if ($fieldLen) { 
		$fmt = "%" . $fieldLen . "s";
		return sprintf($fmt, $commafied);
	}
	return $commafied;
}
function fmtPct($x, $digits=1) {
	$allDigits = 4 + $digits;
	$fmt = '%'.$allDigits.'.'.$digits."f%%";
	return sprintf($fmt, 100.0 * $x);
}
function fmtPct2($numer, $denom, $digits=1) {
	return fmtPct(($numer + 0.0)/$denom, $digits);
}
function fmtMoney($x, $fieldLen="") {
	$commafied = number_format($x, 2);
	$fmt = "$%".$fieldLen."s";
	return sprintf($fmt, $commafied);
}
function fmtSec ($nsec) 
{
	if ($nsec > 99) {
		$nmin = $nsec / 60.0;
		return fmtFlt($nmin, 1)."m";
	} else {
		return $nsec."s";
	}
}
