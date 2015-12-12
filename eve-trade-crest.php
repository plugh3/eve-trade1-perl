<?php


//initialize iveeCrest. Adapt path as required.
require_once(__DIR__.'/iveeCrestInit.php');

//instantiate the CREST client, passing the configured options
$client = new iveeCrest\Client(
    iveeCrest\Config::getCrestBaseUrl(),
    iveeCrest\Config::getClientId(),
    iveeCrest\Config::getClientSecret(),
    iveeCrest\Config::getUserAgent(),
    iveeCrest\Config::getClientRefreshToken()
);
$export_prefix = 'C:\\Users\\csserra\\Documents\\EVE\\logs\\Marketlogs\\';


//instantiate an endpoint handler
$handler = new iveeCrest\EndpointHandler($client);

// prime cache
$fnameCache = __DIR__.'/cache-ivee.txt';
$client->importCache($fnameCache);
//$client->getEndpoint();
$handler->getRegions();
$handler->getMarketTypeHrefs();
$client->exportCache($fnameCache);

// ready to go

/*
// iveeeCrest sample code
//gather all item groups (multipage response is gathered automatically)
$handler->getItemGroups();
//get regions endpoint
$handler->getRegions();
*/

// maps file name => item name
$item_fname2iname = array(
	'GDN-9 Nightstalker Combat Goggles' 		=> 'GDN-9 "Nightstalker" Combat Goggles',
	'Odin Synthetic Eye (left_gray)' 		=> 'Odin Synthetic Eye (left/gray)',
	'Men\'s \'Hephaestus\' Shoes (white_red)' 		=> 'Men\'s \'Hephaestus\' Shoes (white/red)',
	'SPZ-3 Torch Laser Sight Combat Ocular Enhancer (right_black)' => 'SPZ-3 "Torch" Laser Sight Combat Ocular Enhancer (right/black)',
	'Public Portrait_ How To' 			=> 'Public Portrait: How To',
	'Men\'s \'Ascend\' Boots (brown_gold)' 		=> 'Men\'s \'Ascend\' Boots (brown/gold)',
	'Beta Reactor Control_ Shield Power Relay I' 	=> 'Beta Reactor Control: Shield Power Relay I',
	'Alliance Tournament I_ Band of Brothers' 	=> 'Alliance Tournament I: Band of Brothers',
	'Alliance Tournament I_ KAOS Empire' 		=> 'Alliance Tournament I: KAOS Empire',
	'Alliance Tournament II_ Band of Brothers' 	=> 'Alliance Tournament II: Band of Brothers',
	'Alliance Tournament III_ Band of Brothers' 	=> 'Alliance Tournament III: Band of Brothers',
	'Alliance Tournament III_ Cult of War' 		=> 'Alliance Tournament III: Cult of War',
	'Alliance Tournament III_ Interstellar Alcohol Conglomerate' => 'Alliance Tournament III: Interstellar Alcohol Conglomerate',
	'Alliance Tournament IV_ HUN Reloaded' 		=> 'Alliance Tournament IV: HUN Reloaded',
	'Alliance Tournament IV_ Pandemic Legion' 	=> 'Alliance Tournament IV: Pandemic Legion',
	'Alliance Tournament IV_ Star Fraction' 	=> 'Alliance Tournament IV: Star Fraction',
	'Alliance Tournament IX_ Darkside.' 		=> 'Alliance Tournament IX: Darkside.',
	'Alliance Tournament IX_ HYDRA RELOADED and 0utbreak' => 'Alliance Tournament IX: HYDRA RELOADED and 0utbreak',
	'Alliance Tournament X_ HUN Reloaded' 		=> 'Alliance Tournament X: HUN Reloaded',
	'Alliance Tournament V_ Ev0ke' 			=> 'Alliance Tournament V: Ev0ke',
	'Alliance Tournament V_ Triumvirate' 		=> 'Alliance Tournament V: Triumvirate',
	'Alliance Tournament VI_ Pandemic Legion' 	=> 'Alliance Tournament VI: Pandemic Legion',
	'Alliance Tournament VI_ R.U.R.' 		=> 'Alliance Tournament VI: R.U.R.',
	'Alliance Tournament VII_ Pandemic Legion' 	=> 'Alliance Tournament VII: Pandemic Legion',
	'Alliance Tournament VIII_ Pandemic Legion' 	=> 'Alliance Tournament VIII: Pandemic Legion',
	'Alliance Tournament VIII_ HYDRA RELOADED' 	=> 'Alliance Tournament VIII: HYDRA RELOADED',
	'Alliance Tournament X_ HUN Reloaded' 		=> 'Alliance Tournament X: HUN Reloaded',
	'Alliance Tournament X_ Verge of Collapse' 	=> 'Alliance Tournament X: Verge of Collapse',
);
$item_iname2fname = array();
foreach ($item_fname2iname as $fname => $iname) {
  $item_iname2fname[$iname] = $fname;
}
// maps item name => file name
/*
$item_iname2fname = array(
	'GDN-9 "Nightstalker" Combat Goggles' => 'GDN-9 Nightstalker Combat Goggles',
	'Odin Synthetic Eye (left/gray)' => 'Odin Synthetic Eye (left_gray)',
	'SPZ-3 "Torch" Laser Sight Combat Ocular Enhancer (right/black)' => 'SPZ-3 Torch Laser Sight Combat Ocular Enhancer (right_black)',
	'Public Portrait: How To' => 'Public Portrait_ How To',
  'Men\'s \'Ascend\' Boots (brown/gold)' => 'Men\'s \'Ascend\' Boots (brown_gold)',
 	'Beta Reactor Control: Shield Power Relay I' => 'Beta Reactor Control_ Shield Power Relay I',
);
*/
$old_access_token = '9uOF0I5F0CjDeRyu97bvOCj9PNFdkTDfhiV-LSiiu1ZTQClrtMF2hmyXn9V9WDWGBAPKKgI4_D4sgzCAJxnplA2'; // 5/1 2:58pm

$sep = '~';


function set_remove(array &$set, $id) {
    for($i = 0; $i < count($set); $i++) {
        if ($set[$i] == $id) { array_splice($set, $i); return; }
    }
}

$last = 0;          // time of last import (of crest requests)
$last2 = array();   // time of last export, by filename
$last_empty = 0;
while (1)
{
    $fnameReqs = __DIR__.'/'.'eve-trade-crest-reqs.txt';
    // check if request file updated
    clearstatcache();
    $mtime = filemtime($fnameReqs);
    if (!$mtime or $mtime <= $last) { sleep(1); continue; } 
    
    
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

    if (count($rowsRaw) == 0) { if (!$last_empty) { echo time2s()."php (empty request list)\n"; $last_empty = 1;} } 
    else { $last_empty = 0; }

    // aggregate rows by region => rowsByRegion[][]
    $rowsByRegion = array();
    $time = time();
    foreach ($rowsRaw as $row)
    {
        list($reg_id, $reg_name, $item_id, $item_name, $is_bid) = explode($sep, $row);
        
        // crest get cooldown (15s)
        if (array_key_exists($row, $last2) && $time - $last2[$row] <= 15) { 
            //echo time2s()."defer ".($last2[$row] + 5*60 - $time)."s $reg_name-$item_name\n";
            continue; 
        }
        $last2[$row] = $time;

        if (!isset($rowsByRegion[$reg_id])) { $rowsByRegion[$reg_id] = array(); } // necessary?
        $rowsByRegion[$reg_id][] = $row;
    }
    if (count($rowsByRegion) > 0) { $last = $mtime; }

    
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
        $pass++;
        if ($pass > 1) {echo "\x07";}
        
        // populate Orders[reg][item][]
        $suffix = ($pass == 1) ? ("") : (", Pass #$pass");
        echo time2s()."php.getMulti(".count($typeIds).") region=$reg_id$suffix\n";
        $handler->getMultiMarketOrders(
            $typeIds, 
            $reg_id2, 
            function(\iveeCrest\Response $response) use ($rowByItem, &$Orders, $reg_id, &$typeIds) {

                // item ID: parse from URL
                $url = $response->getInfo()['url'];
                $item_id = url2item($url);
                set_remove($typeIds, $item_id); // remove item_id from GET queue

                // region ID: lookup in dictionary of file rows (eve-trade-crest-reqs.txt)
                $row = $rowByItem[$item_id];
                $sep = '~'; // TODO: use global instead
                list($reg_id, $reg_name, $item_id2, $item_name, $is_bid) = explode($sep, $row);

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
              echo time2s()."php.getMultiMarketOrders() error, http code ".$r->getInfo()['http_code']."\n";
              //echo "\x07"; # beep
              //if ($r->getInfo()['http_code'] == 0) { var_dump($r); }
            }
        ); // end getMultiMarketOrders() call
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
            $fname_short = substr($fname2, strpos($fname2, $export_prefix) + strlen($export_prefix));
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
    
    //echo time2s()."sleeping 60 secs...\n";
    sleep(1);
}
function url2item($url)
{
    $base = iveeCrest\Config::getCrestBaseUrl();
    $match = '?type='.$base.'types/'; 
    if (strpos($url, $match) === false) return 0;
    $item_id = substr($url, strpos($url, $match) + strlen($match));
    $item_id = substr($item_id, 0, strlen($item_id) - 1);
    return $item_id;
}
function url2buy($url)
{
    return (strpos($url, 'orders/sell') === false);
}
function getExportFilename($row)
{
    global $sep;
    global $item_iname2fname;
    global $export_prefix;

    list($reg_id, $fname_region, $item_id, $fname_item, $is_bid) = explode($sep, $row);

    // construct export filename
    //$fname_region2 = $handler->getRegion($reg_id)->name;
    $fname_time = date("Y.m.d His", time() - 300); ### crest data is 5 mins delayed, so backdate timestamp
    if (!$fname_item) { print ">>> malformed fname region=$fname_region, item=\"$fname_item\" [$item_id]\n\$row=>$row<\n"; exit;}
    if (array_key_exists($fname_item, $item_iname2fname)) { $fname_item = $item_iname2fname[$fname_item]; }

    $fname2 = $export_prefix.$fname_region.'-'.$fname_item.'-'.$fname_time.'.txt';
    $fname2 = str_replace("/", "_", $fname2); // hacky
    return $fname2;        
}
function export($fname, $text)
{
    global $export_prefix;

    $fname_short = substr($fname, strpos($fname, $export_prefix) + strlen($export_prefix));
    $n = preg_match("/^(.*)-[0-9]{4}.[0-9]{2}.[0-9]{2} [0-9]{6}.txt$/", $fname_short, $match);
    $fname_short2 = $match[1];
    //echo time2s()."crest-php.export() \"$fname_short2\"\n";
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
        $jumps = 0;

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
