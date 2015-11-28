#!C:\Dwimperl\perl\bin\perl.exe

use 5.010;
use strict;
use warnings;
use LWP::Simple;
use List::Util qw (shuffle);
use Time::HiRes qw (gettimeofday);
use Fcntl qw(:DEFAULT :flock);
use HTML::FormatText;
use HTML::Parse;
use DBI;


### GET query parameters
my $maxRecords = 99999;
my $minProfit = 1000;
my $minTotalProfit = 2*1000*1000;
my $minProfitPerSize = 1000;
my $maxGets = 100;
my $maxDelay = 1;
my $maxSpace = 8967;
my $maxSpace_html = $maxSpace;
### GET rate throttling
my $getDelay = 0; 
my $loop_min = 60;
my $loop_rdm = 0;
#my $getDelay = 5; ### min 5 sec between GETs

my $nGets = 0;
my $n_dup_checks = 0;
my $n_market_exports = 0;
my $time_dup = 0;
my $time_sort = 0;
my $time_get = 0;

my $age_expire = 3*24*60*60; ### 72 hours

# to/from systems
my %is_region = ();
my $sys_amarr = 30002187;
my $sys_jita = 30000142;
my $sys_dodixie = 30002659;
my $reg_providence = 10000047; $is_region{$reg_providence} = 1;
my $reg_lonetrek = 10000016; $is_region{$reg_lonetrek} = 1;
my $reg_pureblind = 10000023; $is_region{$reg_pureblind} = 1;
my $reg_thespire = 10000018; $is_region{$reg_thespire} = 1;
my %sys_names = (
	$sys_amarr => "Amarr",
	$sys_jita => "Jita",
	$sys_dodixie => "Dodixie",
	$reg_providence => "Providence",	
	$reg_lonetrek => "Lonetrek",
	$reg_pureblind => "Pure Blind",
	$reg_thespire => "The Spire",
);
my %primary_stations = (
	"Jita" => "Jita IV - Moon 4 - Caldari Navy Assembly Plant",
	"Amarr" => "Amarr VIII (Oris) - Emperor Family Academy",
	"Dodixie" => "Dodixie IX - Moon 20 - Federation Navy Assembly Plant",
);


my $item_db_overwrite = 1;  
my $shopping_fname_prefix = "eve-shopping-";
my $debug_filename = "eve-shopping-debug.txt";
my $itemDBfilename = "eve-trade-itemdb.txt";
my $market_db_filename = "eve-trade-marketdb.txt";
my $market_db_filename2 = "eve-trade-marketdb2.txt";
my $get_log_fname = "eve-trade-log-gets.txt";
my $cargo_filename = "eve-trade-cargo.txt";


my %items_ignore = (
	"Cormack's Modified Armor Thermal Hardener" => 1,
	"Draclira's Modified EM Plating" => 1,
	"Gotan's Modified EM Plating" => 1,
	"Tobias' Modified EM Ward Amplifier" => 1,
	"Ahremen's Modified Explosive Plating" => 1,
	"Setele's Modified Explosive Plating" => 1,
	"Raysere's Modified Mega Beam Laser" => 1,
);
my %is_mineral = (
	'Isogen' => 1,
	'Megacyte' => 1,
	'Mexallon' => 1,
	'Morphite' => 1,
	'Nocxium' => 1,
	'Pyerite' => 1,
	'Tritanium' => 1,
	'Zydrine' => 1,
);


### globals
my %Bids = ();
my %Asks = ();
my %Bids2 = ();  
my %Asks2 = ();
my %Bids_old = ();
my %Asks_old = ();

my %itemDB = ();
my %items_name = ();
my %items_size = ();
my %items_old = ();


### stations: id <=> long name <=> short name
### id: for HMTL query
### long name: for array indexes
### short name: for display
sub loc_i2n {
	my ($sysid) = @_;
	return $primary_stations{$sys_names{$sysid}};
}
my %sys_name2id = ();
foreach my $sid (keys %sys_names) {
	if ($is_region{$sid}) { next; }
	my $short = $sys_names{$sid};
	my $long = $primary_stations{$short};
	$sys_name2id{$short} = $sid;
	$sys_name2id{$long} = $sid;
}
sub loc_n2i {
	my ($sysname) = @_;
	return $sys_name2id{$sysname};
}
sub primary {
	my ($station) = @_;
	foreach my $system (keys %primary_stations) {
		if ( index($station, $system) != -1 && 
		     $station ne $primary_stations{$system}) 
		{
			#print ">>> non-primary station $station\n";
			return 0;
		}
	}
	return 1;
}






### FUNCTIONS ###


my $n_orders_old = 0; # marketDB imports
sub import_market_db {
	my $FH;
	if (! open($FH, '<:crlf', $market_db_filename)) {
		 print ">>> Open.read of \"$market_db_filename\" failed!\n";
		 return 0;
	}
	
	flock($FH, LOCK_SH);
	while (<$FH>) {
		### FORMAT for market_db
		my ($where, $id, $bidask, $price, $vol, $rem, $when) = split(':'); chomp $when;
		$n_orders_old++;

		### retire old entries (skip)
		my $now = time;
		if ($now - $when > $age_expire) { next; }

		### initialize hashes
		if (! $Bids_old{$where})      { $Bids_old{$where} = (); }
		if (! $Bids_old{$where}{$id}) { $Bids_old{$where}{$id} = (); }
		if (! $Asks_old{$where})      { $Asks_old{$where} = (); }
		if (! $Asks_old{$where}{$id}) { $Asks_old{$where}{$id} = (); }

		### sanity checks
		if ($rem > $vol) { warn ">>> remainder error!".join(':', $where, $id, $bidask, $price, $vol, $rem, $when); }
		
		### TODO: age out old entries
		
		my $tuple = join(':', ($price, $vol, $rem, $when));
		if ($bidask eq 'ask') {
			push(@{$Asks_old{$where}{$id}}, $tuple);
		} else {
			push(@{$Bids_old{$where}{$id}}, $tuple);
		}
	}

	close $FH;
	print "Imported market DB ($n_orders_old orders).\n";
}
sub export_market_db {
	my $FH;
	open($FH, '>:crlf', $market_db_filename) or die "Open.write of \"$market_db_filename\" failed!";
	flock($FH, LOCK_EX);

	foreach my $where (keys %Asks) {			# for each station...
		foreach my $id (keys %{$Asks{$where}}) {	# for each item...
			foreach my $x (@{$Asks{$where}{$id}}) {	# for each ask order
				#print("         ", $x, "\n");
				my ($price, $vol, $rem, $when) = split(':', $x);
				my $bidask = 'ask';
				my $line = join(':', $where, $id, $bidask, $price, $vol, $rem, $when);
				print $FH $line."\n";
				#print $line."\n";
				$n_market_exports++;
			}
		}
	}
	foreach my $where (keys %Bids) {			# for each station...
		foreach my $id (keys %{$Bids{$where}}) {	# for each item...
			foreach my $x (@{$Bids{$where}{$id}}) {	# for each bid order
				my ($price, $vol, $rem, $when) = split(':', $x);
				my $bidask = 'bid';
				my $line = join(':', $where, $id, $bidask, $price, $vol, $rem, $when);
				print $FH $line."\n";
				#print $line."\n";
				$n_market_exports++;
			}
		}
	}

	### Asks_old[] (de-dup)
	foreach my $where (keys %Asks_old) {				# for each station...
		foreach my $id (keys %{$Asks_old{$where}}) {		# for each item...
			foreach my $x (@{$Asks_old{$where}{$id}}) {	# for each ask order
				#print("         ", $x, "\n");
				my ($price, $vol, $rem, $when) = split(':', $x);
				if (! &dup_order(\@{$Asks{$where}{$id}}, $price, $vol)) {
					my $bidask = 'ask';
					my $line = join(':', $where, $id, $bidask, $price, $vol, $rem, $when);
					print $FH $line."\n";
					$n_market_exports++;
				}
			}
		}
	}
	### Bids_old[] (de-dup)
	foreach my $where (keys %Bids_old) {				# for each station...
		foreach my $id (keys %{$Bids_old{$where}}) {		# for each item...
			foreach my $x (@{$Bids_old{$where}{$id}}) {	# for each ask order
				#print("         ", $x, "\n");
				my ($price, $vol, $rem, $when) = split(':', $x);
				if (! &dup_order(\@{$Bids{$where}{$id}}, $price, $vol)) {
					my $bidask = 'bid';
					my $line = join(':', $where, $id, $bidask, $price, $vol, $rem, $when);
					print $FH $line."\n";
					$n_market_exports++;
				}
			}
		}
	}


	close $FH;
	print "Exported market DB.\n";
}


my $n_imports = 0; # itemDB imports
my %baddata_size = (
	"Daredevil" => "2500.0",
	"Datacore - Amarrian Starship Engineering" => "0.1",
	"Datacore - Caldari Starship Engineering" => "0.1",
	"Datacore - Defensive Subsystems Engineering" => "0.1",
	"Datacore - Electromagnetic Physics" => "0.1",
	"Datacore - Electronic Engineering" => "0.1",
	"Datacore - Electronic Subsystems Engineering" => "0.1",
	"Datacore - Engineering Subsystems Engineering" => "0.1",
	"Datacore - Gallentean Starship Engineering" => "0.1",
	"Datacore - Graviton Physics" => "0.1",
	"Datacore - High Energy Physics" => "0.1",
	"Datacore - Hydromagnetic Physics" => "0.1",
	"Datacore - Laser Physics" => "0.1",
	"Datacore - Mechanical Engineering" => "0.1",
	"Datacore - Minmatar Starship Engineering" => "0.1",
	"Datacore - Molecular Engineering" => "0.1",
	"Datacore - Nanite Engineering" => "0.1",
	"Datacore - Nuclear Physics" => "0.1",
	"Datacore - Offensive Subsystems Engineering" => "0.1",
	"Datacore - Plasma Physics" => "0.1",
	"Datacore - Propulsion Subsystems Engineering" => "0.1",
	"Datacore - Quantum Physics" => "0.1",
	"Datacore - Rocket Science" => "0.1",
	"Drone Link Augmentor II" => "25.0",
	"F-90 Positional Sensor Subroutines" => "5.0",
	"Gecko" => "50.0",
	"Large Capacitor Control Circuit I" => "20.0",
	"Legion Defensive - Adaptive Augmenter" => "40.0",
	"Legion Defensive - Augmented Plating" => "40.0",
	"Legion Defensive - Nanobot Injecter" => "40.0",
	"Legion Defensive - Warfare Processor" => "40.0",
	"Legion Electronics - Energy Parasitic Complex" => "40.0",
	"Legion Electronics - Dissolution Sequencer" => "40.0",
	"Legion Electronics - Emergent Locus Analyzer" => "40.0",
	"Legion Electronics - Tactical Targeting Network" => "40.0",
	"Legion Engineering - Power Core Multiplier" => "40.0",
	"Legion Engineering - Augmented Capacitor Reservoir" => "40.0",
	"Legion Engineering - Capacitor Regeneration Matrix" => "40.0",
	"Legion Engineering - Supplemental Coolant Injector" => "40.0",
	"Legion Offensive - Drone Synthesis Projector" => "40.0",
	"Legion Offensive - Assault Optimization" => "40.0",
	"Legion Offensive - Covert Reconfiguration" => "40.0",
	"Legion Offensive - Liquid Crystal Magnifiers" => "40.0",
	"Legion Propulsion - Chassis Optimization" => "40.0",
	"Legion Propulsion - Fuel Catalyst" => "40.0",
	"Legion Propulsion - Interdiction Nullifier" => "40.0",
	"Legion Propulsion - Wake Limiter" => "40.0",
	"Loki Defensive - Adaptive Augmenter" => "40.0",
	"Loki Defensive - Adaptive Shielding" => "40.0",
	"Loki Defensive - Amplification Node" => "40.0",
	"Loki Defensive - Warfare Processor" => "40.0",
	"Loki Electronics - Dissolution Sequencer" => "40.0",
	"Loki Electronics - Emergent Locus Analyzer" => "40.0",
	"Loki Electronics - Immobility Drivers" => "40.0",
	"Loki Electronics - Tactical Targeting Network" => "40.0",
	"Loki Engineering - Augmented Capacitor Reservoir" => "40.0",
	"Loki Engineering - Capacitor Regeneration Matrix" => "40.0",
	"Loki Engineering - Power Core Multiplier" => "40.0",
	"Loki Engineering - Supplemental Coolant Injector" => "40.0",
	"Loki Offensive - Covert Reconfiguration" => "40.0",
	"Loki Offensive - Hardpoint Efficiency Configuration" => "40.0",
	"Loki Offensive - Projectile Scoping Array" => "40.0",
	"Loki Offensive - Turret Concurrence Registry" => "40.0",
	"Loki Propulsion - Chassis Optimization" => "40.0",
	"Loki Propulsion - Fuel Catalyst" => "40.0",
	"Loki Propulsion - Intercalated Nanofibers" => "40.0",
	"Loki Propulsion - Interdiction Nullifier" => "40.0",
	"Medium Ancillary Current Router I" => "10.0",
	"Medium Ancillary Current Router II" => "10.0",
	"Medium Anti-EM Screen Reinforcer I"  => "10.0",
	"Medium Anti-EM Screen Reinforcer II" => "10.0",
	"Medium Anti-Explosive Screen Reinforcer I" => "10.0",
	"Medium Anti-Explosive Screen Reinforcer II" => "10.0",
	"Medium Anti-Kinetic Screen Reinforcer I" => "10.0",
	"Medium Anti-Kinetic Screen Reinforcer II" => "10.0",
	"Medium Anti-Thermal Screen Reinforcer I" => "10.0",
	"Medium Anti-Thermal Screen Reinforcer II" => "10.0",
	"Medium Anti-EM Pump I" => "10.0",
	"Medium Anti-EM Pump II" => "10.0",
	"Medium Anti-Explosive Pump I" => "10.0",
	"Medium Anti-Explosive Pump II" => "10.0",
	"Medium Anti-Kinetic Pump I" => "10.0",
	"Medium Anti-Kinetic Pump II" => "10.0",
	"Medium Anti-Thermal Pump I" => "10.0",
	"Medium Anti-Thermal Pump II" => "10.0",
	"Medium Capacitor Control Circuit I" => "10.0",
	"Medium Core Defense Field Extender I" => "10.0",
	"Small Anti-EM Screen Reinforcer I" => "5.0",
	"Small Anti-EM Screen Reinforcer II" => "5.0",
	"Small Anti-Explosive Screen Reinforcer I" => "5.0",
	"Small Anti-Explosive Screen Reinforcer II" => "5.0",
	"Small Anti-Kinetic Screen Reinforcer I" => "5.0",
	"Small Anti-Kinetic Screen Reinforcer II" => "5.0",
	"Small Anti-Thermic Screen Reinforcer I" => "5.0",
	"Small Anti-Thermic Screen Reinforcer II" => "5.0",
	"Small Anti-EM Pump I" => "5.0",
	"Small Anti-EM Pump II" => "5.0",
	"Small Anti-Explosive Pump I" => "5.0",
	"Small Anti-Explosive Pump II" => "5.0",
	"Small Anti-Kinetic Pump I" => "5.0",
	"Small Anti-Kinetic Pump II" => "5.0",
	"Small Anti-Thermic Pump I" => "5.0",
	"Small Anti-Thermic Pump II" => "5.0",
	"Proteus Defensive - Adaptive Augmenter" => "40.0",
	"Proteus Defensive - Augmented Plating" => "40.0",
	"Proteus Defensive - Nanobot Injector" => "40.0",
	"Proteus Defensive - Warfare Processor" => "40.0",
	"Proteus Electronics - CPU Efficiency Gate" => "40.0",
	"Proteus Electronics - Dissolution Sequencer" => "40.0",
	"Proteus Electronics - Emergent Locus Analyzer" => "40.0",
	"Proteus Electronics - Friction Extension Processor" => "40.0",
	"Proteus Engineering - Augmented Capacitor Reservoir" => "40.0",
	"Proteus Engineering - Capacitor Regeneration Matrix" => "40.0",
	"Proteus Engineering - Power Core Multiplier" => "40.0",
	"Proteus Engineering - Supplemental Coolant Injector" => "40.0",
	"Proteus Offensive - Covert Reconfiguration" => "40.0",
	"Proteus Offensive - Dissonic Encoding Platform" => "40.0",
	"Proteus Offensive - Drone Synthesis Projector" => "40.0",
	"Proteus Offensive - Hybrid Propulsion Armature" => "40.0",
	"Proteus Propulsion - Gravitational Capacitor" => "40.0",
	"Proteus Propulsion - Interdiction Nullifier" => "40.0",
	"Proteus Propulsion - Localized Injectors" => "40.0",
	"Proteus Propulsion - Wake Limiter" => "40.0",
	"Tengu Defensive - Adaptive Shielding" => "40.0",
	"Tengu Defensive - Amplification Node" => "40.0",
	"Tengu Defensive - Supplemental Screening" => "40.0",
	"Tengu Defensive - Warfare Processor" => "40.0",
	"Tengu Electronics - CPU Efficiency Gate" => "40.0",
	"Tengu Electronics - Dissolution Sequencer" => "40.0",
	"Tengu Electronics - Emergent Locus Analyzer" => "40.0",
	"Tengu Electronics - Obfuscation Manifold" => "40.0",
	"Tengu Engineering - Augmented Capacitor Reservoir" => "40.0",
	"Tengu Engineering - Capacitor Regeneration Matrix" => "40.0",
	"Tengu Engineering - Power Core Multiplier" => "40.0",
	"Tengu Engineering - Supplemental Coolant Injector" => "40.0",
	"Tengu Offensive - Accelerated Ejection Bay" => "40.0",
	"Tengu Offensive - Covert Reconfiguration" => "40.0",
	"Tengu Offensive - Magnetic Infusion Basin" => "40.0",
	"Tengu Offensive - Rifling Launcher Pattern" => "40.0",
	"Tengu Propulsion - Fuel Catalyst" => "40.0",
	"Tengu Propulsion - Gravitational Capacitor" => "40.0",
	"Tengu Propulsion - Intercalated Nanofibers" => "40.0",
	"Tengu Propulsion - Interdiction Nullifier" => "40.0",
	"Worm" => "2500.0",
);
sub import_item_db {
	my $username = "dev";
	my $password = "BNxJYjXbYXQHAvFM";
	my $db_params = "DBI:mysql:database=evesdd;host=127.0.0.1;port=3306";
	my $dbh = DBI->connect($db_params, $username, $password);
	my $sth = $dbh->prepare("SELECT typeID, typeName, volume FROM invtypes");
	$sth->execute();	while (my $ref = $sth->fetchrow_hashref()) {
		#print "Found a row: id=$ref->{'typeID'}, name=$ref->{'typeName'}, size=$ref->{'volume'}\n";

		my $id =   $ref->{'typeID'};
		my $name = $ref->{'typeName'};
		my $size = $ref->{'volume'};
		$itemDB{$id} = join('~',$name,$id,$size);
		$items_name{$id} = $name;
		$items_size{$id} = $size;
		$items_old{$id} = 1;	}
	$sth->finish();
	$dbh->disconnect();

}

my $n_exports = 0; # itemDB exports
sub export_item_db {
	my $FH;
	my $mode = ($item_db_overwrite ? '>:crlf' : '>>:crlf');
	open($FH, $mode, $itemDBfilename) or die "Open.write of \"$itemDBfilename\" failed!";
	flock($FH, LOCK_EX);

	if ($item_db_overwrite) { print "Re-sorting item DB.\n";}

	foreach my $key (sort sort_id_by_name (keys %itemDB)) {
		if ($item_db_overwrite) {
			### overwrite all records
			print $FH "$itemDB{$key}\n"; ### same formats for itemDB[] and DB file
			$n_exports++;
		} else {
			### add new records only
			if (! $items_old{$key}) {
				print $FH "$itemDB{$key}\n"; ### same formats for itemDB[] and DB file
				$n_exports++;
			}
		}
	}

	close $FH;
	print "Exported item DB.\n";
}

my %get_errors = ();
my $get_item_buf = "";
sub get_item_info {
	my ($url, $id, $name) = @_;
	
	### GET quota
	if ($nGets >= $maxGets || $get_errors{$name}) { return undef; }

	
	#print "GET item $name..."; flush STDOUT; $now = time;
	&timer_start("get");
	my $itemPage = get $url; $nGets++;
	$time_get += &timer_stop("get");
	#print "done (" . (time - $now) . "s)\n";
	$get_item_buf .= "- GET item $name\n";

	if ($itemPage =~ /Item.*\Q$name\E.*size: (?<itemSize>[0-9]+\.?[0-9]*) m\<sup\>3\<\/sup\>/) {
	#if ($itemPage =~ /(Item.*)size: (?<itemSize>[0-9]+\.?[0-9]*) m\<sup\>3\<\/sup\>/) {
		my $size = $+{itemSize};
		
		### known data errors
		if ($baddata_size{$id}) { $size = $baddata_size{$id}; };

		### add new item record
		$itemDB{$id} = join('~',$name,$id,$size);
		$items_name{$id} = $name;
		$items_size{$id} = $size;
		$items_old{$id} = 0;
		
		if ($size == 0) { print ">>> Zero size for $id >$name<!!!\n"; } ### error state
		#print "Size of $id >$name< is $size m^3\n";
		#print "$url\n";
		return $size;		
	} else {

		my $FH;
		open($FH, '>>', 'errorlog.txt');
		flock($FH, LOCK_EX);
		print $FH "get_item_info() parse error for ID $id NAME >$name< URL >$url<\n";
		close $FH;

		print ">>> Parse error! Item property page for ID $id NAME >$name< URL >$url<\n";
		$get_errors{$name} = 1;
		return undef;
	}
}


### create URL for "from X to Y" orders page
sub url_orders {
	my ($from_sys_id, $to_sys_id) = @_;
	my $url = "https://eve-central.com/home/tradefind_display.html?set=1". 
	"&fromt=$from_sys_id".
	"&to=$to_sys_id".
	"&qtype=".($is_region{$to_sys_id} ? "SystemToRegion" : "Systems").
	"&age=$maxDelay". 
	"&minprofit=$minProfit".
	"&size=$maxSpace_html".
	"&limit=$maxRecords".
	"&sort=sprofit".
	"&prefer_sec=0";
	#print ">>> URL $url\n";
	return $url;
}
my $last_get = 0;
sub get_html_orders {
	my ($from, $to) = @_;

	### debug output
	my $prefix = &time2m()." ".sprintf("%-7s", $sys_names{$from})." - ".sprintf("%-7s", $sys_names{$to});
	print "$prefix "; flush STDOUT;

	### min time between GETs
	my $now = time;
	if ($now - $last_get < $getDelay) { 
		print "sleeping..."; flush STDOUT; 
		sleep($getDelay); 
		print "\b\b\b\b\b\b\b\b\b\b\b"; flush STDOUT; 
	}
	$last_get = $now;

	### log GET
	my $log = "";
	my $FH;
	open($FH, '>>:crlf', $get_log_fname) or warn "fopen.append of \"$get_log_fname\" failed";
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$log .= sprintf("%02i", $mon+1).'/'.sprintf("%02i", $mday+1).'/'.sprintf("%4i", $year+1900);
	$log .= ' ';
	$log .= sprintf("%02i", $hour).':'.sprintf("%02i", $min).':'.sprintf("%02i", $sec);
	$log .= '  ';
	$log .= '192.168.0.1';
	$log .= '  ';
	$log .= "GET from=".sprintf("%-7s", $sys_names{$from})." to=".sprintf("%-7s", $sys_names{$to});
	$log .= ' ';
	$log .= "profit=".sprintf("%6i", $minProfit);
	$log .= ' ';
	$log .= "age=$maxDelay";
	$log .= ' ';
	$log .= "size=".sprintf("%5i", $maxSpace_html);
	$log .= ' ';
	$log .= "results=".sprintf("%6i", $maxRecords);
	$log .= "\n";
	print $FH $log;
	close $FH;

	### debug	
	print "GET()..."; flush STDOUT; # timed fetch
	#print "GET profit=$minProfit age=$maxDelay size=$maxSpace_html results=$maxRecords..."; flush STDOUT; # timed fetch
	&timer_start("get");

	### GET() order page from web
	my $url_orders = &url_orders($from, $to);
	my $orders_html= get $url_orders; $nGets++;

	### debug	
	my $elapsed = &timer_stop("get"); 
	$time_get += $elapsed;
	print "\b\b\b\b\b (".&timer2s($elapsed).")..."; flush STDOUT;
	#print "done (" . sprintf("%4.1f", ($elapsed / 1000000.0)) . "s)\n"; # timed fetch

	return $orders_html;
}



### sample data from deals page
#
#<tr>
#  <td><b>From:</b> Amarr VIII (Oris) - Emperor Family Academy</td>    ## leading space only
#  <td><b>To:</b> Jita IV - Moon 4 - Caldari Navy Assembly Plant </td> ## leading + trailing space
#  <td><b>Jumps:</b> 9</td>
#</tr>
#<tr>
#  <td><b>Type:</b> <a href="quicklook.html?typeid=17648">Antimatter Charge XL</a></td>
#  <td><b>Selling:</b> 2,299.97 ISK</td>
#  <td><b>Buying:</b> 2,450.00 ISK</td>
#</tr>
#
#<tr>
#  <td><b>Per-unit profit:</b> 150.03 ISK</td>
#  <td><b>Units tradeable:</b> 38,213 (38,213 -&gt; 100,000)</td>
#  <td>&nbsp;</td>
#</tr>
#<tr>
#  <td><b><i>Potential profit</i></b>: 5,733,096.39 ISK </td>
#  <td><b><i>Profit per trip:</i></b>: 5,381,276.04 ISK</td>
#  <td><b><i>Profit per jump</i></b>: 538,127.60</td>
#</tr>
#<tr><td>&nbsp;</td></tr>
#
#   <=== start of next block
#<tr>

### HTML format for orders page (single quotes = no interpolation)
my $regexp_html_orders = 
'
\<tr\>
  \<td\>\<b\>From:\<\/b\> (?<askLocation>[^<]+?)\<\/td\>
  \<td\>\<b\>To:\<\/b\> (?<bidLocation>[^<]+?) \<\/td\>
  \<td\>\<b\>Jumps:\<\/b\> [0-9]+?\<\/td\>
\<\/tr\>
\<tr\>
  \<td\>\<b\>Type:\<\/b\> \<a href=\"(?<itemURLsuffix>quicklook.html\?typeid=(?<itemID>[0-9]+?))\"\>(?<itemName>[^<]+?)\<\/a\>\<\/td\>
  \<td\>\<b\>Selling:\<\/b\> (?<askPrice>[,.0-9]+?) ISK\<\/td\>
  \<td\>\<b\>Buying:\<\/b\> (?<bidPrice>[,.0-9]+?) ISK\<\/td\>
\<\/tr\>

\<tr\>
  \<td\>\<b\>Per-unit profit:\<\/b\> [,.0-9]+? ISK\<\/td\>
  \<td\>\<b\>Units tradeable:\<\/b\> [,0-9]+? \((?<askVolume>[,0-9]+?) -\&gt; (?<bidVolume>[,0-9]+?)\)\<\/td\>
  \<td\>\&nbsp;\<\/td\>
\<\/tr\>
\<tr\>
  \<td\>\<b\>\<i\>Potential profit\<\/i\>\<\/b\>: [,.0-9]+? ISK \<\/td\>
  \<td\>\<b\>\<i\>Profit per trip:\<\/i\>\<\/b\>: [,.0-9]+? ISK\<\/td\>
  \<td\>\<b\>\<i\>Profit per jump\<\/i\>\<\/b\>: [,.0-9]+?\<\/td\>
\<\/tr\>
\<tr\>\<td\>\&nbsp;\<\/td\>\<\/tr\>

';
### tried replacing ".*" with "[^<]+?" since these wildcards are always followed by "<"
### tried removing unnecessary ".*" with exact or type-specific matches (eg "[,.0-9]+")
### tried changing all greedy modifiers to non-greedy
### did not reduce parse time at all
### I give up

my $regexp_html_init = 
'\<p\>Found \<i\>([0-9]+)\<\/i\> possible routes
.\<\/p\>
\<p\>Page [0-9]+\.
(\<a href=\".*\"\>Next page\<\/a\>
)?
\<hr \/\>
\<table border=0 width=90\%\>\n';


### NOTE: contrary to popular belief, regexp is much faster than html parsing
### sample of html vs. regexp parse times 
### html 19, re 9
### html 8.4, re 1.3
### html 5.6, re 0.4
### html 6.6, re 0.7

=SLOW
### proper HTML parsing
use HTML::TreeBuilder;
sub parse_orders2 {
	&timer_start("parse2");

	my ($html_text) = @_;
	print "\nhtml ".sprintf("%.1f", (length($html_text)/1000000.0))." MB\n";

	my $parser = HTML::TreeBuilder->new();
	$parser->parse($html_text);
	my $formatter = HTML::FormatText->new(leftmargin => 0, rightmargin => 50);
	my $ascii = $formatter->format($parser);
	print "ascii ".sprintf("%.1f", (length($ascii)/1000000.0))." MB\n";

	print "parse2(): ".&timer2s(&timer_stop("parse2"))."\n";
}
=cut


### parse_orders(): parse input, add each order to Asks[]/Bids[]
### ARGS: html_orders x fetch_time 
### globals for parse_orders()
my $nDeals = 0;
my $n_records = 0;
my $n_dups = 0;
my $n_offers_new = 0;
my $time_main = 0;
my $time_parse = 0;
my $time_parse_all = 0;
sub parse_orders {
	my ($html_raw, $fetch_time) = @_;
	my ($from, $to);
	my $html_size = length($html_raw);


	### parse to order start
	$html_raw =~ /$regexp_html_init/;
	my $html_rest = $'; ### remainder variable
	my $n_deals = $1;
	$nDeals += $n_deals;
	#print $1 . " records.\n";
	if ($2) { print ">>> $1 records, multiple pages.\n"; }


	### erratic error
	if (! $n_deals || ! $html_rest) {
		my $FH;
		open($FH, '>>', 'errorlog.txt');
		flock($FH, LOCK_EX);

		print $FH &time2m()." prematch >$`<\n";
		print $FH &time2m()." match >$&<\n";

		if (! $` || ! $&) { print $FH &time2m()." bad html >$html_raw<\n"; }

		close $FH;
		exit;
	}

	$time_parse = 0;
	&timer_start("main");
	&timer_start("parse");
	print "parsing ".sprintf("%.1f", ($html_size/1000000.0))."MB..."; flush STDOUT;
	#print "parsing ".sprintf("%i", $html_size)."B..."; flush STDOUT;

	### parse in chunks (24 lines each)
	my $MEM;
	open ($MEM, '<', \$html_rest);
	my $html_chunk = '';
	for (1..24) { $html_chunk .= <$MEM>; }
	while ($html_chunk =~ /$regexp_html_orders/) {	
		$n_records++;
		$time_parse += &timer_stop("parse");
		#print "."; flush STDOUT;
		my $url_itemsuffix = $+{itemURLsuffix};
		my $id = $+{itemID};
		my $name = $+{itemName};
		my $ask_price = $+{askPrice};
		my $ask_vol = $+{askVolume};
		my $ask_loc = $+{askLocation};
		my $ask_time = $fetch_time;
		my $bid_price = $+{bidPrice};
		my $bid_vol = $+{bidVolume};
		my $bid_loc = $+{bidLocation};
		my $bid_time = $fetch_time;

		my $url_prefix = "https://eve-central.com/home/";
		my $url_item = $url_prefix . $url_itemsuffix;

		if (!$from) { ($from, $to) = ($ask_loc, $bid_loc); } ### for debug statements

		### strip commas from numeric values
		$ask_price =~ tr/,//d;
		$bid_price =~ tr/,//d;
		$ask_vol =~ tr/,//d;
		$bid_vol =~ tr/,//d;
		### sanity check for commas in numeric fields
		if (index($ask_price,',') != -1 || index($bid_price,',') != -1 || index($ask_vol,',') != -1 || index($bid_vol,',') != -1) {
			die ">>> comma askp >$ask_price< bidp >$bid_price< askv >$ask_vol< bidv >$bid_vol<\n";
		}

		### debug: all fields parsed correctly?
		#print "---\n";
		#print ">>> $id $name ask $ask_price x $ask_vol at ".&where2s($ask_loc)." ".&ago($ask_time)."\n";
		#print ">>> $id $name bid $bid_price x $bid_vol at ".&where2s($bid_loc)." ".&ago($bid_time)."\n";
		
		### fetch item data if not buffered
		
		if (exists $itemDB{$id} || &get_item_info($url_item, $id, $name)) {
			if ($name ne $items_name{$id}) {
				#print ">>> converting item name \"$items_name{$id}\" from \"$name\"\n";
				$name = $items_name{$id};					}
			### initialize hashes (confirmed necessary)
			
			### NOTE: Perl references are weird.
			### Passing "\@{$Bids{$id}}" to fn always works.
			### Passing "$Bids{$id}" works sometimes, but not if $Bids{$id} was just set to empty "()".
			### And for some reason screwing around with $Bids{$id} before calling the function fixes the problem.
			### I.e., printing out its contents (empty), size (0), and number of last index (-1).
			### EXAMPLES: array references + index operator
			#print "array n=".$#{$Bids{$id}}." >@{$Bids{$id}}< ".(0+@{$Bids{$id}})."\n";
			#my $t1 = \@{$Bids{$id}};
			#print "t1    n=".(0 + $#{$t1})." >@{$t1}< ".(0 + @{$t1})."\n";
			#my $t2 = $Bids{$id};
			#print "t2    n=".(0 + $#{$t2})." >@{$t2}< ".(0 + @{$t2})."\n";

			### add bid
			if (&primary($bid_loc)) { ### skip orders from non-primary stations
				if (! $Bids{$bid_loc})      { $Bids{$bid_loc} = ();      $Bids2{$bid_loc} = (); }
				if (! $Bids{$bid_loc}{$id}) { $Bids{$bid_loc}{$id} = (); $Bids2{$bid_loc}{$id} = (); }
				if (&dup_order(\@{$Bids{$bid_loc}{$id}}, $bid_price, $bid_vol)) {
					### saw in this fetch (dup)
					$n_dups++;
					#print ">>> dup bid $id >$name< \$".&comma($bid_price)." x $bid_vol\n";
				} else {
					my $price = $bid_price;
					my $vol = $bid_vol;
					my $rem = $bid_vol;
					my $where = $bid_loc;
					my $when = $bid_time;

					### saw in previous fetch?
					my $old = &dup_order(\@{$Bids_old{$where}{$id}}, $price, $vol);
					### inherit timestamp + remainder
					if ($old) { (undef, undef, $rem, $when) = split(':', $old);}

					### new bid
					my $tuple = join(':', ($price, $vol, $rem, $when)); ### TODO
					push(@{$Bids{$where}{$id}}, $tuple);
					push(@{$Bids2{$where}{$id}}, $tuple);
					#print "NEW bid $name \$$price x $vol at ".&where2s($where)." ".&ago($when)."\n";
					$n_offers_new++;
				}
			}
						
			### add ask
			if (&primary($ask_loc)) { ### skip orders from non-primary stations
				if (! $Asks{$ask_loc})      { $Asks{$ask_loc} = ();      $Asks2{$ask_loc} = (); }
				if (! $Asks{$ask_loc}{$id}) { $Asks{$ask_loc}{$id} = (); $Asks2{$ask_loc}{$id} = (); }
				if (&dup_order(\@{$Asks{$ask_loc}{$id}}, $ask_price, $ask_vol)) {
					$n_dups++;
				} else {
					my $price = $ask_price;
					my $vol = $ask_vol;
					my $rem = $ask_vol;
					my $where = $ask_loc;
					my $when = $ask_time;

					### TODO: check if (this.vol == old.rem)
					my $old = &dup_order(\@{$Asks_old{$where}{$id}}, $price, $vol);
					### inherit timestamp + remainder
					if ($old) { (undef, undef, $rem, $when) = split(':', $old);}

					### new ask
					my $tuple = join(':', ($price, $vol, $rem, $when));
					push(@{$Asks{$where}{$id}}, $tuple);
					push(@{$Asks2{$where}{$id}}, $tuple);
					#print "NEW ask $name \$$price x $vol at ".&where2s($where)." ".&ago($when)."\n";
					$n_offers_new++;
				}
			}
		} else {
			### get_item() failed
			### this could be because we exceeded the GET quota, or failed to parse the item page
			### result is we just move on to the next record
		}

		&timer_start("parse");
		
		### bite off next chunk
		$html_chunk = ''; for (1..24) { $html_chunk .= <$MEM>; }
	}
	$time_parse += &timer_stop("parse");
	#print "\b\b\b (".&timer2s($time_parse).")..."; flush STDOUT;
	print "parse1(".&timer2ms($time_parse).")..."; flush STDOUT;
	
	$time_main += &timer_stop("main");
	$time_parse_all += $time_parse;
	#my $prefix = sprintf("%-7s", &where2s($from))."-".sprintf("%-7s", &where2s($to));
	#print "$prefix Parsed ".sprintf("%5i", $n_deals)." orders (".&timer2s($time_parse).")\n";
	#print "done (" . (time - $now) . "s)\n";
	print "done\n";
	print $get_item_buf; $get_item_buf = "";
}


### compare tuple against array of tuples
sub dup_order {
	&timer_start("dup");
	my ($orders_ref, $price1, $vol1) = @_;
	my @orders = @{$orders_ref};
	#if ($#orders == -1) { print ">>> empty array\n"; } ### if this shows up we're in good shape
	foreach my $x (@orders) {
		$n_dup_checks++;
		my ($price2, $vol2, $when2) = split(':', $x);
		### same bid/ask?
		if ($price1 == $price2 && $vol1 == $vol2) {
			$time_dup += &timer_stop("dup");
			return $x; ### return earlier order
		}
	}
	$time_dup += &timer_stop("dup");
	return 0;
}


my $n_sort_by_price = 0;
sub sort_bids_by_price { ### inputs are tuples
	&timer_start("sort");
	$n_sort_by_price++;
	my ($price_a, $vol_a, $rem_a, $when_a) = split(':', $a);
	my ($price_b, $vol_b, $rem_b, $when_b) = split(':', $b);
	my $ret = $price_b <=> $price_a; ### descending
	$time_sort += &timer_stop("sort");
	return $ret;
}
sub sort_asks_by_price { ### inputs are tuples
	&timer_start("sort");
	$n_sort_by_price++;
	my ($price_a, $vol_a, $rem_a, $when_a) = split(':', $a);
	my ($price_b, $vol_b, $rem_b, $when_b) = split(':', $b);
	my $ret = $price_a <=> $price_b; ### ascending
	$time_sort += &timer_stop("sort");
	return $ret;
}
sub sort_id_by_name {
	$items_name{$a} cmp $items_name{$b};
}


### match_orders(): match bids/asks by max profit
### ARGS: (from x to) (NOTE full station name, not system)
### OUTPUT: Deals[]
my $i_deals = 0;
my $n_unprofitables = 0;
my $debug_append = 0;
sub match_orders {
	### input
	my ($s_from, $s_to) = @_;
	my $ask_loc = $s_from;
	my $bid_loc = $s_to;
	### output
	my @Deals = (); ### $profit_per, $id, $bid_price, $bid_loc, $ask_price, $ask_loc, $qty, $total_size, $when

	#print "Matching bid and ask orders..."; flush STDOUT; $now = time;
	&timer_start("match");
	my $mode = ($debug_append++) ? '>>:crlf' : '>:crlf' ;
	my $FH3; open($FH3, $mode, $debug_filename) or die "Open.write of \"$debug_filename\" failed!";
	foreach my $id (keys %{$Bids{$bid_loc}}) {
		### empty order sets are possible
		if (! $Asks{$ask_loc}{$id}) { next;}
		if (! $Bids{$bid_loc}{$id}) { next;}
		if (@{$Bids{$bid_loc}{$id}} + 0 == 0) { next; }
		if (@{$Asks{$ask_loc}{$id}} + 0 == 0) { next; }

		my $name = $items_name{$id};
		my $size = $items_size{$id};
		print $FH3 "$name (".sprintf("%.1f", $size)." m^3) id $id from ".&where2s($ask_loc)." to ".&where2s($bid_loc)."\n";
		#print      "$name (".sprintf("%.1f", $size)." m^3) id $id from ".&where2s($ask_loc)." to ".&where2s($bid_loc)."\n";

		### sort asks ascending
		foreach my $x (sort sort_asks_by_price @{$Asks{$ask_loc}{$id}}) {
			my ($price, $vol, $rem, $when) = split(':', $x);
			print $FH3 "   ask ".&comma($price)." x $vol\n";
			#print      "   ask ".&comma($price)." x $vol\n";
		}
		print $FH3 "   ---\n";
		#print      "   ---\n";
		
		### sort bids descending
		foreach my $x (sort sort_bids_by_price @{$Bids{$bid_loc}{$id}}) {
			my ($price, $vol, $rem, $when) = split(':', $x);
			print $FH3 "   bid ".&comma($price)." x $vol\n";
			#print      "   bid ".&comma($price)." x $vol\n";
		}
		print $FH3 "   ---\n";
		#print      "   ---\n";


		### sort bids and asks, match until empty
		my @ask_indexes = sort { ### sort asks descending
			my ($a2) = split(':', $Asks{$ask_loc}{$id}[$a]); 
			my ($b2) = split(':', $Asks{$ask_loc}{$id}[$b]);
			$a2 <=> $b2; 
		} keys @{$Asks{$ask_loc}{$id}}; 
		my @bid_indexes = sort { ### sort bids ascending
			my ($a2) = split(':', $Bids{$bid_loc}{$id}[$a]); 
			my ($b2) = split(':', $Bids{$bid_loc}{$id}[$b]);
			$b2 <=> $a2; 
		} keys @{$Bids{$bid_loc}{$id}}; 
		my $n_bid_indexes = scalar(@bid_indexes);
		my $n_ask_indexes = scalar(@ask_indexes);
		my $i_bid = 0;
		my $i_ask = 0;

		#print $FH3 "   ask indexes >".join(',', @ask_indexes)."<\n";
		#print $FH3 "   bid indexes >".join(',', @bid_indexes)."<\n";
		#print $FH3 "---\n";

		### sanity check
		### not sure how this possible
		if ($n_bid_indexes == 0) { 
			warn ">>> empty Bids[".&where2s($bid_loc)."][$items_name{$id}]"; 
			print "Bids[] = >@{$Bids{$bid_loc}{$id}}<\n";
			if ($Bids{$bid_loc}{$id}) { print "passed boolean test\n"; }
			if (!(0 + @{$Bids{$bid_loc}{$id}})) { print "failed scalar test\n"; }
			next;
		}
		if ($n_ask_indexes == 0) { 
			warn ">>> empty Asks[".&where2s($ask_loc)."][$items_name{$id}]"; 
			print "Asks[] = >@{$Asks{$ask_loc}{$id}}<\n";
			next;
		}
		
		### check for unprofitables
		my ($bid_price0) = split(':', $Bids{$bid_loc}{$id}[$bid_indexes[0]]);
		my ($ask_price0) = split(':', $Asks{$ask_loc}{$id}[$ask_indexes[0]]);
		if (($bid_price0 * 0.9925) < $ask_price0) { $n_unprofitables++; } 
		### check for scams
		### Scam 1: profit > $1B
		if ((($bid_price0-$ask_price0) > 1000000000) && $items_ignore{$items_name{$id}}) {
			print ">>> SKIP $items_name{$id}\n";
			#next;
		}
		### Scam 2: profit > $29M, cost > $200M
		if (($bid_price0-$ask_price0) > 29*1000000 && $ask_price0 > 200*1000000) {
			### DEPRECATED: these are being filtered in dashboard app now
			#print ">>> potential scam".
			#	" $items_name{$id}".
			#	"\n".
			#	"  profit ".sprintf("%.1f", ($bid_price0-$ask_price0)/1000000.0)."M".
			#	"\n".
			#	"  ask ".sprintf("%i", ($ask_price0/1000000.0))."M ".&where2s($ask_loc).
			#	"\n".
			#	"  bid ".sprintf("%i", ($bid_price0/1000000.0))."M ".&where2s($bid_loc).
			#	"\n";
			#next;
		}
		
		while (($i_bid < $n_bid_indexes) && ($i_ask < $n_ask_indexes)) {
			#print "."; flush STDOUT;
			my $bid_i2 = $bid_indexes[$i_bid];
			my $ask_i2 = $ask_indexes[$i_ask];
			my $bid = $Bids{$bid_loc}{$id}[$bid_i2];
			my $ask = $Asks{$ask_loc}{$id}[$ask_i2];
			my ($bid_price, $bid_vol, $bid_rem, $bid_when) = split(':', $bid);
			my ($ask_price, $ask_vol, $ask_rem, $ask_when) = split(':', $ask);
			
			my $this_vol = &min($bid_vol, $ask_vol);
			my $this_when = &max($bid_when, $ask_when); ### timestamp = most recent underlying order
			
			my $profit_per_unit = ($bid_price * 0.9925) - $ask_price;
			if ($profit_per_unit < 0.0) { last; }
			my $profit_per_size = $profit_per_unit / $size;
			my $total_profit = $profit_per_unit * $this_vol;
			my $total_size = $this_vol * $size;
			my $roi = $profit_per_unit / $ask_price;
			
			#print "      match \$" . &comma($profit_per_size) . "\/m3 x ".&comma($total_size)." m3 = \$".&comma($profit_per_unit * $this_vol)."\n";
			#print "         $this_vol x (".&comma($bid_price)." - ".&comma($ask_price).")\n";
			print $FH3 "   match $this_vol x (".&comma($bid_price)." - ".&comma($ask_price).") => \$".&comma($profit_per_unit * $this_vol).
				" (".sprintf("%.1f", $total_size)." at \$".&comma($profit_per_size)."\/m3)\n";
			#print      "   match $this_vol x (".&comma($bid_price)." - ".&comma($ask_price).") => \$".&comma($profit_per_unit * $this_vol).
			#	" (".sprintf("%.1f", $total_size)." at \$".&comma($profit_per_size)."\/m3)\n";
			### TODO: add to deal list
			### Deals[] format: $profit_per, $id, $bid_price, $bid_loc, $ask_price, $ask_loc, $qty, $total_size, $when
			my $deal = join(':', $profit_per_size, $id, $bid_price, $bid_loc, $bid_i2, $ask_price, $ask_loc, $ask_i2, $this_vol, $total_size, $this_when);
			push @Deals, $deal;
			#$Deals[$i_deals++] = $deal;


			### subtract qty consumed in Asks/Bids[]
			$bid_vol -= $this_vol;
			$ask_vol -= $this_vol;
			my $bid_new = join(':', $bid_price, $bid_vol, $bid_rem, $bid_when);
			my $ask_new = join(':', $ask_price, $ask_vol, $ask_rem, $ask_when);
			$Bids{$bid_loc}{$id}[$bid_indexes[$i_bid]] = $bid_new;
			$Asks{$ask_loc}{$id}[$ask_indexes[$i_ask]] = $ask_new;
			if ($bid_vol == 0) { $i_bid++;}
			if ($ask_vol == 0) { $i_ask++;}
		}	
		print $FH3 "\n";
	}
	close $FH3;
	#print "match_orders() done (".&timer2ms(&timer_stop("match")).")\n";

	return \@Deals;
}

### TODO: change to Deals[from][to][], args are fromxto
### pick_cargo(): select subset of orders to take, based on profitability and cargo size
### ARGS: Deals[] array of available bid/ask orders
### OUTPUT: Take2[] picked orders, aggregated by item
sub pick_cargo {
	### input
	my ($deals_ref) = @_;
	my @Deals = @$deals_ref;
	### output
	my %Take2 = (); # output

	### Take[]: order Deals[] by profit-per-m3, take until ship is full 
	#print "Sorting matches by profit"; flush STDOUT; 
	my @Take = (); ### orders to take
	my $ship_space = $maxSpace;
	foreach my $i (sort 	{
					my ($profit_a) = split(':', $Deals[$a]);
					my ($profit_b) = split(':', $Deals[$b]);
					$profit_b <=> $profit_a; ### sort descending
				} keys @Deals) {

		### extract fields from Deals[]
		my ($profit_per_size, $id, $bid_price, $bid_loc, $bid_i, $ask_price, $ask_loc, $ask_i, $order_vol, $order_size, $when) = split(':',$Deals[$i]);	
		if ($profit_per_size < $minProfitPerSize) { last; }

		### calculate fit
		my $this_size = $items_size{$id};
		my $this_space = ($order_size > $ship_space) ? ((int($ship_space / $this_size))*$this_size) : $order_size;
		my $this_qty = int($this_space / $this_size); if ($this_qty == 0) { next; }	
		my $this_profit = $this_qty * $profit_per_size * $this_size;
		my $take = join(':', $profit_per_size, $id, $bid_price, $bid_loc, $bid_i, $ask_price, $ask_loc, $ask_i, $this_qty, $this_profit, $this_space, $when);

		### add to cargo Take[]
		push @Take, $take;

		#print "   \$".sprintf("%13.2f", $profit_per_size)."\/m3 ".sprintf("%5i", $this_qty)." x $items_name{$id}\n";
		#print sprintf("%12.2f", $profit_per_size)."\/m3 ".sprintf("%5i", $this_qty)." x $items_name{$id} ".
		#	"(".sprintf("%0.2f", $this_space)." m3), ".sprintf("%0.2f", $ship_space - $this_space)." left\n";
		#print "take >".$Take[$i_take-1]."<, ".sprintf("%0.2f", $ship_space-$this_space)." m3 left\n";

		$ship_space -= $this_space; if ($ship_space == 0) { last; }
	}
	#print "pick_cargo() sorted matches by profit.\n";


	### Take2[]: aggregate Take[] entries by item 
	#print "Consolidating orders..."; flush STDOUT; $now = time;
	for my $i (0 .. $#Take) {
		#print "."; flush STDOUT;
		my ($profit_per, $id, $bid, $bid_loc, $bid_i, $ask, $ask_loc, $ask_i, $qty, $profit, $space, $when) = split(':', $Take[$i]);
	#	print sprintf("%12.2f", $profit_per)."\/m3 ".sprintf("%5i", $qty)." x $items_name{$id} ".
	#		"(".sprintf("%0.2f", $space)." m3)\n";
		if (!$Take2{$id}) { 
			$Take2{$id}{qty} = 0; 
			$Take2{$id}{profit} = 0.0; 
			$Take2{$id}{cost} = 0.0;
			$Take2{$id}{when} = 0;
			$Take2{$id}{from} = $ask_loc;
			$Take2{$id}{to} = $bid_loc;
			$Take2{$id}{orders} = ();
		}
		$Take2{$id}{qty} += $qty;
		$Take2{$id}{profit} += $profit;
		$Take2{$id}{cost} += $ask * $qty;
		$Take2{$id}{when} = &max($when, $Take2{$id}{when}); ### most recent underlying order
		push(@{$Take2{$id}{orders}}, join(':', $bid_i, $ask_i, $qty));
	}
	#print "done (" . (time - $now) . "s)\n";
	#print "pick_cargo() consolidated orders.\n";

	### TODO: if (when == now) and (item profit > $25M) send notification
	### SMS email to 8586922163@txt.att.net
	
	return \%Take2;
}


sub export_to_dashboard {
	my ($FH, $from, $to, $take2_ref) = @_;
	my %Take2 = %$take2_ref;

	my @keys = keys %Take2;
	if (0+@keys == 0) { print "shopping_list() empty $from -> $to\n"; return; }

	foreach my $id (sort {$Take2{$b}{profit} <=> $Take2{$a}{profit}} keys %Take2) {
		my $qty = $Take2{$id}{qty};
		my $profit = $Take2{$id}{profit};
		my $cost = $Take2{$id}{cost};
		my $size = $items_size{$id};
		my $when = $Take2{$id}{when};
		my $ask_loc = $Take2{$id}{from};
		my $bid_loc = $Take2{$id}{to};
		
		### "ignore" scenarios
		if ($profit < $minTotalProfit) { next; }  			### profit cutoff
		if ($profit > 1000000000 && $items_ignore{$id}) { next; } 	### margin scams
		if ($is_mineral{$items_name{$id}}) { next; }					### minerals
		if ($ask_loc ne $from) { warn "export_shopping_list() ask location mismatch $ask_loc, $from"; }
		if ($bid_loc ne $to) { warn "export_shopping_list() bid location mismatch $bid_loc, $to"; }

		my @matches = @{$Take2{$id}{orders}};
		my $last;
		### underlying ask orders
		$last = -1;
		foreach my $m (0..$#matches) {
			my ($i_bid, $i_ask, $match_qty) = split(':', $matches[$m]);
			if ($i_ask == $last ) { next; } $last = $i_ask;
			my $where = $ask_loc;
			my $bidask = 'ask';
			my $other_loc = $bid_loc;
			my $x = $Asks2{$ask_loc}{$id}[$i_ask];
			my ($price, $vol, $rem, $when) = split(':', $x);
			my $line = join(':', $where, $id, $bidask, $price, $vol, $rem, $when, $other_loc);
			print $FH $line."\n";
		}
		### underlying bid orders
		$last = -1;
		foreach my $m (0..$#matches) {
			my ($i_bid, $i_ask, $match_qty) = split(':', $matches[$m]);
			if ($i_bid == $last ) { next; } $last = $i_bid;
			my $where = $bid_loc;
			my $bidask = 'bid';
			my $other_loc = $ask_loc;
			my $x = $Bids2{$bid_loc}{$id}[$i_bid];
			my ($price, $vol, $rem, $when) = split(':', $x);
			my $line = join(':', $where, $id, $bidask, $price, $vol, $rem, $when, $other_loc);
			print $FH $line."\n";
		}
	}
}

### export_shopping_list(): print item x qty selected
### format 1: item names only (for Copy to Clipboard)
### format 2: items + profit + underlying bid/ask orders (for verification)
sub export_shopping_list {
	my ($take2_ref) = @_;
	my %Take2 = %$take2_ref;
	
	### export to file

	### TODO: assumes Take2 only contains 1 from/to pair
	my @keys = keys %Take2;
	if (0+@keys == 0) { print "shopping_list() empty\n\n"; return; }
	my $i1 = $keys[0];
	my $q_from = &loc_n2i($Take2{$i1}{from});
	my $q_to = &loc_n2i($Take2{$i1}{to});

	#my $fh2;
	#my $f_suffix = (lc $sys_names{$q_from})."2".(lc $sys_names{$q_to});
	#$f_suffix =~ tr/ //d;
	#my $shopping_filename = $shopping_fname_prefix.$f_suffix.".txt";
	#open($fh2, '>:crlf', $shopping_filename) or die "Open.write of \"$shopping_filename\" failed!";

	### preamble = "FROM => TO hh:dd"
	my $preamble = (uc $sys_names{$q_from})." => ".(uc $sys_names{$q_to});
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$preamble = $preamble." ".sprintf("%02i:%02i", ($hour+7)%24, $min);
	#print $fh2 "$preamble\n\n";
	print "\n$preamble\n\n";

	### print item names only (for Copy to Clipboard)
	#print $fh2 "$preamble\n\n";
	foreach my $id (sort {$Take2{$b}{profit} <=> $Take2{$a}{profit}} keys %Take2) {
		my $profit = $Take2{$id}{profit};
		if ($profit < $minTotalProfit) { next; }  ### ignore entries below the profit cutoff
		#print $fh2 "$items_name{$id}\n";
	}
	#print $fh2 "\n$preamble\n\n";

	### print underlying bid/ask offers
	my $profit_all = 0;
	my $size_all = 0;
	my $cost_all = 0;
	my $when_all = 0;
	my $n_order = 1;
	my $now = time;
	foreach my $id (sort {$Take2{$b}{profit} <=> $Take2{$a}{profit}} keys %Take2) {
		my $qty = $Take2{$id}{qty};
		my $profit = $Take2{$id}{profit};
		my $cost = $Take2{$id}{cost};
		my $size = $items_size{$id};
		my $when = $Take2{$id}{when};
		my $ask_loc = $Take2{$id}{from};
		my $bid_loc = $Take2{$id}{to};
		
		if ($profit < $minTotalProfit) { next; }  ### ignore entries below the profit cutoff
		if ($profit < 1000000000) { ### show margin scams but don't count in totals
			$profit_all += $profit;
			$size_all += $qty * $size;
			$cost_all += $cost;
			$when_all = &max($when_all, $when);
		}
		
		### print item's aggregate profit + aggregate vol
		my $text = "";
		### optional warnings for high cost or high size
		$text .= "\$".&comma($profit, 16)."  ".&ago($when, $now)."".sprintf("%8i", $qty)."x $items_name{$id}";
		#print " ".sprintf("%4.1f", (100*$profit/$cost))."%"; 	### ROI
		#print " (".sprintf("%0.1f", $qty*$size)." m3)"; 	### m3
		if ($cost > 500000000) { $text .= " (\$".sprintf("%0.3f", $cost/1000000000.0)."B cost)"; }
		print $text."\n";
		
		#print $fh2 "$preamble\n\n";
		#print $fh2 "$items_name{$id}\n";
		#print $fh2 $n_order++."\. +\$".&comma($profit)."   [x $qty]";
		### show warning if size above 750m3
		#if ($qty * $size > 750) { print $fh2 " (".sprintf("%0.2f", $qty*$size)." m3)";}
		### show warning if cost above $500M
		#if ($cost > 500000000) { print $fh2 "  \$".sprintf("%0.2f", $cost/1000000000.0)."B cost!"; }
		#print $fh2 "\n";

		my $w_prefix = "  ";

		my @matches = @{$Take2{$id}{orders}};
		my $last;
		### show underlying ask orders
		$last = -1;
		foreach my $m (0..$#matches) {
			my ($i_bid, $i_ask, $match_qty) = split(':', $matches[$m]);
			if ($i_ask == $last ) { next; } ### order could be split across multiple matches
			$last = $i_ask;
			my $x = $Asks2{$ask_loc}{$id}[$i_ask];
			my ($price, $order_qty, $rem, $when) = split(':', $x);
			#my $ago = sprintf("%3i", ($now - $when) / 60.0)."m ago";
			#print $w_prefix."ask ".&comma($price)." x $order_qty  \t$ago\n";
			#print $fh2 $w_prefix."ask ".&comma($price)." x $order_qty\n";
		}
		#print $w_prefix."---\n";
		#print $fh2 $w_prefix."---\n";
		### show underlying bid orders
		$last = -1;
		foreach my $m (0..$#matches) {
			my ($i_bid, $i_ask, $match_qty) = split(':', $matches[$m]);
			if ($i_bid == $last ) { next; } ### order could be split across multiple matches
			$last = $i_bid;
			my $x = $Bids2{$bid_loc}{$id}[$i_bid];
			my ($price, $order_qty, $rem, $when) = split(':', $x);
			#my $ago = sprintf("%3i", ($now - $when) / 60.0)."m ago";
			#print $w_prefix."bid ".&comma($price)." x $order_qty  \t$ago\n";
			#print $fh2 $w_prefix."bid ".&comma($price)." x $order_qty\n";
		}
		#print $fh2 "\n";
	}
	#close $fh2;
	
	### print summary to terminal
	print "-----------------\n";
	#print"\$".&comma($profit_all, 16)."            Total profit ($size_all m3 used, ".($maxSpace-$size_all)." m3 free)\n";
	print"\$".&comma($profit_all, 16)."  ".&ago($when_all, $now)."          Total profit";
	if ($cost_all > 4000000000) { 
		print " (\$".sprintf("%.3f", $cost_all/1000000000.0)."B cost!)"
	}
	print "\n"; 
}



### UTILITY FNS ###

### timers return time elapsed in usecs
my %Timers;
sub timer_start {
	my ($label) = @_;
	if (! $label) { $label = "default";}
	($Timers{$label}{sec}, $Timers{$label}{usec}) = gettimeofday;
}
sub timer_stop {
	my ($label) = @_;
	if (! $label) { $label = "default";}
	my ($now_sec, $now_usec) = gettimeofday;
	my $ret = (1000000 * ($now_sec - $Timers{$label}{sec})) + ($now_usec - $Timers{$label}{usec});
	$ret; ### (usec)
}
sub timer2s {
	my ($usec) = @_;
	sprintf("%4.1f", $usec/1000000.0)."s";
}
sub timer2ms {
	my ($usec) = @_;
	sprintf("%6.1f", $usec/1000.0)."ms";
}
sub max {
	my ($a, $b) = @_;
	($a > $b) ? $a : $b;
}
sub min {
	my ($a, $b) = @_;
	($a < $b) ? $a : $b;
}
sub time2m {
	my ($t) = @_;
	if (! $t) { $t = time; }
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
	sprintf("%i:%02i", ($hour > 12)?($hour-12):$hour, $min).(($hour>11)?"pm":"am");
}
sub ago {
	my ($when, $now) = @_;
	if (!$now) { $now= time; }
	my $ago = $now - $when;
	if ($when == 0) { return "never"; }
	if ($ago > 3600) { return sprintf("%4.1f", ($now - $when) / 3600.0)."h ago"; }
	return sprintf("%4i", ($now - $when) / 60.0)."m ago";
}
sub comma {
	my ($x, $y) = @_;
	#print "\ncomma  ($x)\n";

	my $a = sprintf("%.2f", $x);
	$a =~ /^(.*)\.([0-9][0-9])$/;
	my $r = $1;
	my $decimal = $2;
	#print "integer $r decimal $decimal\n";

	my $n = length $r;
	for my $i (1..(($n-1)/3)) {
		#print "before  $r\n";
		my $n2 = $n-(3*$i); ### first char after new comma
		my $t1 = substr($r, 0, $n2);
		my $t2 = substr($r, $n2, (length $r)-$n2);
		#print "   r>$r< t1>$t1< t2>$t2< n2>$n2<\n";
		$r = substr($r, 0, $n2) . "," . substr($r, $n2, (length $r)-$n2);
		#print "after   $r\n";
	}
	$r = $r . "." . $decimal;
	
	### add whitespace to desired field length
	$n = length $r;
	if ($y && ($y > $n)) { 
		#print "comma() add ".($y-$n)." spaces\n";
		for my $i (1..($y-$n)) { $r=' '.$r;} 
	}
	$r;
}
sub where2s {
	my ($station_fullname) = @_;
	if (! $station_fullname) { warn "where2s()"; }
	my $where = substr($station_fullname, 0, index($station_fullname, " "));
}	







my @routes = (
	[$sys_jita, $sys_amarr],
	[$sys_amarr, $sys_jita],
	[$sys_jita, $sys_dodixie],
	[$sys_dodixie, $sys_jita],
	[$sys_amarr, $sys_dodixie],
	[$sys_dodixie, $sys_amarr],
);
my %Cargos = ();


sub random2 {
	my ($min, $max, $inc) = @_;
	my $range = int(($max - $min) / $inc) + 1;
	my $n = int(rand() * $range);
	return $min + ($n * $inc);
}
sub randomize_html_args {
	$maxRecords = &random2(10000, 12000, 50);
	$minProfit = &random2(5000, 10000, 10000);
	$maxDelay = &random2(1, 2, 1);
	$maxSpace_html = &random2(7000, 9999, 1);
}

sub error {
	my ($t) = @_;
	my $FH;
	open($FH, '>>', 'errorlog.txt');
	flock($FH, LOCK_EX);
	print $FH &time2m." ".$t."\n";
	close $FH;
}


### main()
&import_item_db;

my $last_loop = time;
while (1) {
	### reset market datastore
	%Bids = ();
	%Asks = ();
	%Bids2 = ();
	%Asks2 = ();
	%Bids_old = ();
	%Asks_old = ();
	$debug_append = 0;

	&import_market_db;

	my @cycle = shuffle(@routes);
	&timer_start("fetchall");
	my $time_fn_get_html = 0;
	my $time_fn_parse_orders = 0;
	foreach my $r (@cycle) {
		my ($from_id, $to_id) = @$r;
		#print ">>> fetching orders ".&where2s(&loc_i2n($from_id))." => ".&where2s(&loc_i2n($to_id)).":\n";
		my $fetch_time = time;
		&randomize_html_args;
		&timer_start("fn_get_html");
		my $html_orders = &get_html_orders($from_id, $to_id);
		$time_fn_get_html += &timer_stop("fn_get_html");
		&timer_start("fn_parse_orders");
		if (!$html_orders) { 
			&error("\$html_orders empty, from=$sys_names{$from_id}, to=$sys_names{$to_id}"); 
			warn ">>> parse error";
			next; 
		}
		&parse_orders($html_orders, $fetch_time); # populate Bids/Asks[]
			$time_fn_parse_orders += &timer_stop("fn_parse_orders");
	}
	my $time_fetchall = &timer_stop("fetchall");

	&export_market_db;

	### export "eve-shopping-amarr2dodixie.txt" files
	foreach my $r (@routes) {
		my ($from_id, $to_id) = @$r;
		my $loc_from = &loc_i2n($from_id);
		my $loc_to = &loc_i2n($to_id);
		#print "\n-- ".&where2s($loc_from)."-".&where2s($loc_to)." --\n";
		#print ">>> analyzing ".$loc_from." => ".$loc_to."\n";

		#print ">>> match_orders() ".&where2s($loc_from)."-".&where2s($loc_to)."\n";
		my $deals_ref = &match_orders($loc_from, $loc_to);
		if (! $deals_ref) { next; }

		#print ">>> pick_cargo() ".&where2s($loc_from)."-".&where2s($loc_to)."\n";
		my $take2_ref = &pick_cargo($deals_ref);
		$Cargos{$loc_from}{$loc_to} = $take2_ref;

		#print ">>> export_shopping() ".&where2s($loc_from)."-".&where2s($loc_to)."\n";
		&export_shopping_list($take2_ref);
	}

	### data for dashboard
	my $FH;
	open($FH,'>:crlf', $cargo_filename); ### TODO: lock file 
	flock($FH, LOCK_EX);
	foreach my $r (@routes) {
		my ($from_id, $to_id) = @$r;
		my $loc_from = &loc_i2n($from_id);
		my $loc_to = &loc_i2n($to_id);

		&export_to_dashboard($FH, $loc_from, $loc_to, $Cargos{$loc_from}{$loc_to});
	}
	close($FH);

	### debug output
	print "\n\n";
	print sprintf("%7i", $n_imports).	" items read\n"; 	$n_imports = 0;
	print sprintf("%7i", $n_exports).	" items written\n"; 	$n_exports = 0;
	print sprintf("%7i", $n_orders_old).	" orders imported\n";	$n_orders_old = 0;
	print sprintf("%7i", $n_offers_new).	" current orders\n";	$n_offers_new = 0;
	print sprintf("%7i", $n_market_exports)." orders exported\n";	$n_market_exports = 0;
	print "---\n";
	print sprintf("%7i", $nDeals).		" records reported\n";	
	if ($nDeals) {print sprintf("%7i", $n_records).	" records processed (".sprintf("%.1f", ($n_records / $nDeals) * 100.0)."%)\n"; $n_records = 0; $nDeals = 0;}
	print sprintf("%7i", $n_dups).		" duplicate bids/asks\n";$n_dups = 0;
	print sprintf("%7i", $n_unprofitables).	" false positives\n";	$n_unprofitables = 0;
	#print sprintf("%7i", $i_deals)." orders matched\n";
	print sprintf("%7i", $nGets).		" GETs performed\n";	$nGets = 0;
	print sprintf("%7i", $n_dup_checks).	" duplicate checks\n";	$n_dup_checks = 0;
	print sprintf("%7i", $n_sort_by_price).	" sorts by price\n";	$n_sort_by_price = 0;
	print "---\n";
	print "  ".&timer2s($time_fetchall)." fetch + parse\n";		$time_fetchall = 0;
	print "  ".&timer2s($time_fn_get_html)." get_html_orders()\n";	$time_fn_get_html = 0;
	print "  ".&timer2s($time_fn_parse_orders)." parse_orders()\n";	$time_fn_parse_orders= 0;
	print "  ".&timer2s($time_main)." main parse loop\n";		$time_main = 0;
	print "  ".&timer2s($time_parse_all)." parsing\n";		$time_parse_all = 0;
	print sprintf("%6.1f", $time_dup/1000000.0). "s dup checking\n";$time_dup = 0;
	print sprintf("%6.1f", $time_sort/1000000.0)."s sorting\n";	$time_sort = 0;
	print sprintf("%6.1f", $time_get/1000000.0). "s GET()\n";	$time_get = 0;

	#my $time_fn_get_html = 0;
	#my $time_fn_parse_orders = 0;


	### 2.0-2.5 min between loops ($refresh_min + rand(30))
	my $now = time;
	my $nap = 0;
	if ($now - $last_loop < $loop_min) { $nap = ($now - $last_loop) + int(rand($loop_rdm)); }
	$last_loop = $now;
	print "\nSleeping for ".sprintf("%3i", $nap)." sec"; flush STDOUT;
	for my $n (1..$nap) {
		sleep(1);
		print "\b\b\b\b\b\b\b".sprintf("%3i", $nap-$n)." sec"; flush STDOUT;
		#print "."; flush STDOUT;
	}
	print "...awake\n\n";
}









		 