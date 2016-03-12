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




//$invalidGroups = array(0-11, 13-14, 16-17, 19, 23, 29, 32, 92, 104);
// "SKIN" groups: 528, 1311, 1319, 351064, 350858, 351844, 368726
// "SKIN" groupID query => SELECT DISTINCT groupID FROM `invtypes` WHERE typeName LIKE '%SKIN%'
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


$ItemNames = array();
function fmtItem($itemID)
{
	global $ItemNames;
	return $ItemNames[$itemID];
}

// get item list from mysql
function fetch_items_from_mysql($whereClause) {
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
		if (!isValidItem($itemID)) continue;

		global $ItemNames;
		$itemName = mysql_result($result, $i, 'typeName');
		$ItemNames[$itemID] = $itemName;

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


// 1. get list of items WHERE volume < 8967m3 (22876)
$itemList = fetch_items_from_mysql("WHERE `volume` < 8967");
sort($itemList, SORT_NUMERIC);
echo "mysql pass 2 (group):  ".number_format(count($itemList))."\n";

// 2. issue Crest requests for each (hub x item x orderType)

// 3. check if profitable

// 4. output list of profitables (from x to x item)
    



//
// $Orders[itemID][regionID] - datastore for Crest responses
//
$Orders;
reset_orders();

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
function count_orders()
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
function reset_orders()
{
	global $Orders, $itemList;
	$Orders = array();
	foreach ($itemList as $itemID) {
		$Orders[$itemID] = array();
	}
}


// master list of crest requests ($12k items => 95k requests)
function queueAddItems(&$q, $items) {
	foreach ($items as $itemID) {
		// add requests for all hub stations
		global $Hubs;
		foreach ($Hubs as $regionID) {
			$q[] = join_row($itemID, $regionID, true); 	// buy orders
			$q[] = join_row($itemID, $regionID, false);	// sell orders
		}
	}
	echo time2s()."queueAdd(".count($q).")\n";
}



$batch_size = 125;
$n_items = count($itemList);
$n_batches = intval($n_items / $batch_size) + 1;
$n_batch = 0;
function next_batch_items(&$q)
{
	global $itemList, $n_batch, $batch_size;
	$batch_start_i = $n_batch * $batch_size;
	if ($batch_start_i >= count($itemList)) { return array(); }

	$items = array_slice($itemList, $batch_start_i, $batch_size);
	queueAddItems($q, $items);

	$n_batch++;
	return $items;
}



// divide queue[] into batches of size N
//$batch_size = 1000;
//$n_batches = intval($n_orig / $batch_size);

$rollover = array();
$n_orig = count($itemList) * 8;
//for ($b = 0; $b < $n_batches; $b++) {
	// $queue = next batch
	//$batch_start_i = $b * $batch_size;
	//$queue = array_slice($superqueue, $batch_start_i, $batch_size);

$queue = array();
while (1) {
	$items = next_batch_items($queue);

	// add previous rollovers
	array_tack($queue, $rollover);

	$my_batch_size = count($queue);
	if ($my_batch_size == 0) { break; }

	
	// loop until GET queue is empty
	$pass = 0;
	$n503s = 0;
	$t_start = microtime(true);
	while (! empty($queue)) {
		// debug
		$pass++; if ($pass > 1) { beep(); }
		$suffix = ($pass == 1) ? ("") : (", Pass #$pass");
		echo ">>> batch #$n_batch (".(($n_batch-1)*$batch_size*8)." - ".((($n_batch-1)*$batch_size*8) + count($queue) - 1).")$suffix\n";

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
				function(\iveeCrest\Response $response) use (&$queue, &$Orders) {

					// parse parameters from URL
					$url = $response->getInfo()['url'];
					list($itemID, $regionID, $bid_type) = decode_url($url);
					$queueItem = join_row($itemID, $regionID, $bid_type);
					//echo "got >$queueItem<\n";
					
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

					// process Crest response
					add_crest_response($itemID, $regionID, $bid_type, $response);
				},
				function (\iveeCrest\Response $r) use (&$n503s) {
					//echo " HTTP ".$r->getInfo()['http_code']."\n";
					if ($r->getInfo()['http_code'] == "503") { $n503s++; }
					#echo time2s()."php.getMultiMarketOrders() error, http code ".$r->getInfo()['http_code']."\n";
					//if ($r->getInfo()['http_code'] == 0) { var_dump($r); }
				},
				false // false = caching disabled for getMultiMarketOrders() call (reduces memory)
			); // end getMultiMarketOrders() call
			
			// final sampling output (peak rate)
			$out = sprintf("%7.1f", $client->cw->max_rate)." GET/s";
			echo($client->cw->backspace(strlen($out)));
			echo $out." peak";
			echo " (".fmtPct2($n503s, $my_batch_size)." errors)";
			echo "\n";
			// reset sampling -- sample_reset()
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
		if ($n_batch < $n_batches - 1) {
			$rollover = $queue;
			$queue = array();
		}
		
	}
	
	// timer
	$t_batch = microtime(true) - $t_start;
	echo time2s()."=> ".fmtFlt($t_batch)."s\n";
	
	// find profitables
	$ProfitableItems = array();
	// TODO: check only sublist of $Items
	eachItemAllRoutes(
		$items, 
		function($itemID, $from, $to) use (&$ProfitableItems) {
			if (isProfitable($itemID, $from, $to)) { $ProfitableItems[] = array($itemID, $from, $to); }
		}
	);

	// export profitables
	$text = "";
	$sep = '~';
	foreach ($ProfitableItems as $x) {
		list($itemID, $from, $to) = $x;
		$text .= $itemID.$sep.$from.$sep.$to."\r\n";
	}
	appendFile($fname_data, $text);
	
	
	echo time2s().fmtInt(count($ProfitableItems))." profitable trades\n";
	echo time2s().fmtInt($ncalcs)." trades tested\n"; $ncalcs = 0;
	echo time2s().fmtInt($nsorts)." sort comparisons\n"; $nsorts = 0;
	echo time2s().fmtInt(count_orders())." orders received\n";
	
	reset_orders();

	
	//break; // DEBUG: break after first batch
}


$dir_export = __DIR__;
function appendFile($fname, $text)
{
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
// TODO: filter for profitables
// TODO: output profitable trades
$ncalcs = 0;
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
function eachRoute(callable $block) {
	global $Hubs;
	foreach ($Hubs as $from) {
		foreach ($Hubs as $to) {
			if ($from === $to) { continue; }
			$block($from, $to);
		}
	}
}
// takes fn(item, from, to)
function allItemsAllRoutes(callable $block) {
	global $itemList;
	foreach ($itemList as $itemID) {
		eachRoute(function($from, $to) use ($block, $itemID) {
			$block($itemID, $from, $to);
		});
	}
}
function eachItemAllRoutes($items, callable $block) {
	foreach ($items as $itemID) {
		eachRoute(function($from, $to) use ($block, $itemID) {
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
function fmtFlt($x, $digits=1) {
	$fmt = "%0.".$digits."f";
	return sprintf($fmt, $x);
}
function fmtInt($x, $fieldLen=0) {
	$commafied = number_format($x);

	// count commas added
	//$raw = sprintf("%d", $x);
	//$nCommas = strlen($commafied) - strlen($raw);

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
function beep() {
	echo "\x07";
}
function time2s($time = '')
{
    if ($time == '') { $time = time(); }
    return date("h:i:sa ", $time - 8*60*60);
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
