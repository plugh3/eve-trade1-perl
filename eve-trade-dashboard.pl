#!C:\Dwimperl\perl\bin\perl.exe

use 5.010;
use strict;
use warnings;

### remote dependencies
use Tk; ## cpan
### remote dependencies - skynet
#use HTML::FormatText;
#use HTTP::Async;
### other
use Config;
use DBI; ## cpan
use Fcntl qw(:DEFAULT :flock);
#use constant LOCK_SH => 1;
#use constant LOCK_EX => 2;
#use constant LOCK_UN => 8;
use List::Util qw (shuffle);
use LWP::Simple;
use Time::HiRes qw (gettimeofday);
use Time::Local;
use Tk::HList;
use Tk::Tree;
use Tk::ItemStyle;
use Tk::Pretty;
use Tk::Adjuster;
use Tk::Font;
use Tk::ProgressBar;



### TODO: spawn processes on OSX

my $cargo_filename = 		"data-sky2dash.txt";
my $my_data_filename = 		"data-dash-all.txt";
my $fname_crest_reqs = 		"data-dash2crest.txt";

### OS-specific stuff
my $dir_sep;
my $dir_home;
my $dir_marketlogs;
if      ($Config{osname} eq "darwin") {
	$dir_sep = '/';
	$dir_home = $ENV{'HOME'};
	$dir_marketlogs = $dir_home.'/Library/Application Support/EVE Online/p_drive/User/My Documents/EVE/logs/Marketlogs';
} elsif ($Config{osname} eq "MSWin32") {
	$dir_sep = "\\";
	$dir_home = $ENV{'HOMEDRIVE'}.$ENV{'HOMEPATH'};
	$dir_marketlogs = $dir_home.'\Documents\EVE\logs\Marketlogs';
} else {	
	die ">>> unknown OS type \"$Config{osname}\"";
} 





### INIT + SPAWN ###

### wipe data files
unlink $cargo_filename if (-e $cargo_filename);
unlink $my_data_filename if (-e $my_data_filename);
unlink $fname_crest_reqs if (-e $fname_crest_reqs);

### start local mysqld
if (not (`tasklist` =~ m/mysqld/)) {
	print &time2s()." starting mysql...";
	system("start C:\\xampp\\xampp-control.exe"); ## new window

	### wait for mysqld to wake up
	my $db_name = "evesdd";
	my $db_host = "127.0.0.1";
	my $db_port = "3306";	
	my $db_info = "DBI:mysql:database=$db_name;host=$db_host;port=$db_port";
	my $db_user = "dev";
	my $db_pass = "BNxJYjXbYXQHAvFM";
	my $dbh;
	eval {$dbh = DBI->connect($db_info, $db_user, $db_pass, {'RaiseError' => 1})};
	while ($@) {
		print ".";
		sleep 1;
		eval {$dbh = DBI->connect($db_info, $db_user, $db_pass, {'RaiseError' => 1})};
	}
	$dbh->disconnect();

	print "done.\n";
}

### spawn crest daemon
my $pid_crest = fork;
if (!$pid_crest) {
	### CREST gets
	#system("run-crest.bat"); ## same window
	#system("start C:\\xampp\\php\\php.exe -f eve-trade-crest.php > out-crest.txt 2>&1"); ## new window + log
	system("start run-crest.bat"); ## new window, persist after die (DEBUG)
	#system("start C:\\xampp\\php\\php.exe -f eve-trade-crest.php"); ## new window
	exit;
}
$pid_crest = substr($pid_crest, 1);
#print "pid_crest  $pid_crest\n";

### spawn skynet daemon
my $pid_skynet = fork;
 if (!$pid_skynet) {
	### skynet (evecentral + marketlogs gets)
	system("start run-skynet.bat"); ## new window, persist after die (DEBUG)
	#system("start perl eve-trade-j2a-v5-skynet.pl"); ## new window
	exit;
}
$pid_skynet = substr($pid_skynet, 1);
#print "pid_skynet $pid_skynet\n";




### main window
my $mw = MainWindow->new(-title => 'Tree');
$mw->geometry("850x650");


my $textbox = $mw->Text(); # never packed
sub copy2clipboard {
	my ($x) = @_;
	# do stuff

	### Plan B
	$textbox->clipboardClear;
	$textbox->clipboardAppend($x);


	### Plan A
	#$textbox->clipboardClear;
    #$textbox->delete('1.0', 'end');
    #$textbox->insert('end', $x);
    #$textbox->selectAll;
    #this next line must come after the selectAll      
    #$textbox->delete('end - 1 chars', 'end');
    #$textbox->clipboardColumnCopy;      
}

sub my_beep {
	### beep
	print "\07";
	#$mw->bell; # beep
}



### GLOBAL VARIABLES ###

### persistent across recalc()
my %State_mode = ();
my @State_selection = ();
my %Ignore = ();
### reset on each recalc()
my %Data = (); ### totals by route/item + underlying bids/asks
my %Totals = (); ### totals by route only
my %items_name;
my %items_size;
my %items_id;
my %Bids;
my %Asks;
my %Notify = ();
my $N_items;
my $N_orders;


### GLOBAL CONSTANTS ###

#my $Net_tax = 0.9910; 	### Accounting 4
my $Net_tax = 0.9925; 	### Accounting 5
my $game_data_expire = 0*60;			### game export data trumps "newer" eve-market.com data for 20 mins
my $age_expire_export = 1*24*3600;		### game export data purged after 1 day
my $age_expire_web = 3*24*3600;			### web data purged after 3 days
my $notify_threshold_price_super = 50*1000000;	### $50M
my $notify_threshold_price = 25*1000000;	### $30M
my $notify_threshold_age = 60*60;		### 20 min
my $minProfitPerSize = 2000;			### $/m3
my $minProfit = 3*1000000;			### $2.0M/item
my $total_cost_threshold = 4*1000000000;

### UI config
my $Pre = ' ';
my $Post = ' ';
my $Sep = '~'; ### separator used for pathnames (route/item/bid)
my $RouteSep = " -> ";
my $font = 		'evesans 10';
my $font_bold =		'evesans 10 bold';
my $font_big =		'evesans 12';
my $font_menu = 	'evesans 8';
my $colwidth_item = 	40;
my $color_fg =		'#dddddd';
my $color_top = 	$color_fg;
my $color_ig =		'#777777';
my $color_hdr =		'#181818';
#my $color_bgselect = 	'#4a6e65';
my $color_bg =  	'#242424';
my $color_bgselect = 	'#283e50';
#my $color_bgalt =	'#252a3f'; # color_bg..x......color_bgselect
my $color_bgalt =	'#3f2a3f'; # color_bg..x......color_bgselect
my $color_fgselect =	$color_fg;
my $color_menubg =	'#121212';
my $color_menuselect =	'#121224';
my $color_menufg = 	$color_fg;
my $color_urgent_red = 	'#ff8888';
#my $color_urgent_orange='#ffcc88';
my $color_urgent_orange='#dfac48';
my $color_urgent_yellow='#dfdf88';
my $color_hover =	'#5555ff';
my $color_red = 	'#ff8888';
my $color_brightred = 	'#ff3333';
my $color_green = 	'#88ff88';
my $color_yellow=	'#dfdf88';
my $color_purple = 	'#c600ff';
my $color_orange=       '#ff8000';




my $f_top = $mw->Frame()->pack(-side => 'top', -fill => 'x');
my $w_adj = $mw->Adjuster(-widget => $f_top, -side => 'top')
->pack(-side => 'top', -fill => 'x');
my $f_bot = $mw->Frame->pack(-side => 'bottom', -fill => 'x', -expand => 1);


my $nCols = 8;
my $col_route =  0;
my $col_item = 	 0;
my $col_profit = 1;
my $col_qty =    2;
my $col_cost =   3;
my $col_roi =    4;
my $col_size =   5;
my $col_age =    6;
my $col_pps =	 7;




### Tree widget: route cargo lists
my $w1 = $f_top->Scrolled('Tree', -scrollbars => 'e',
	-columns => $nCols,
	-header => 1,
	-selectmode => 'extended',
	-font => $font,
	-foreground => $color_fg,
	-background => $color_bg,
	-browsecmd => \&highlight_return_route_cmd,
#	-selectforeground => $color_fgselect,
	-selectbackground => $color_bgselect,
	-separator => $Sep,
	-height => 35,
)->pack(-fill => 'both', -expand => 1);


my $p_lastAltHighlight = 0;
my @styles_lastAlt = ();
sub highlight_return_route_clear {
	### restore previous row
	if ($p_lastAltHighlight) {
		for (my $col = 0; $col < $nCols; $col++) {
			my $style_orig = $styles_lastAlt[$col];
			if (! $style_orig) { next; } 
			$w1->itemConfigure($p_lastAltHighlight, $col, '-style', $style_orig);
		}
	}
	$p_lastAltHighlight = 0;
	@styles_lastAlt = ();
}
sub highlight_return_route_cmd {
	my ($p_selected) = @_;
	
	if (! &is_route($p_selected)) { return; }
	my ($from, $to) = split($RouteSep, $p_selected);
	if (! $to) { print ">>> highlight_return_route() error: route = >$p_selected<\n"; return; }
	
	### construct string for return route
	my $p_return = join($RouteSep, $to, $from);
	#print &time2s()." highlight_return_route($p_return)\n";

	if ($p_return eq $p_lastAltHighlight) { return; }
	
	### restore previous row
	&highlight_return_route_clear();

	### save old style + set new style 
	$p_lastAltHighlight = $p_return;
	@styles_lastAlt = ();
	for (my $col = 0; $col < $nCols; $col++) {
		### skip incompatible cell types
		if (not $w1->itemExists($p_return, $col)) { next; }
		my $itemtype = $w1->itemCget($p_return, $col, '-itemtype');
		if ($itemtype eq 'window' or $itemtype eq 'image') { next; }

		### save old style
		my $style_orig = $w1->itemCget($p_return, $col, '-style');
		$styles_lastAlt[$col] = $style_orig;

		### create new style
		my $style_mod  = &mod_style($style_orig, $itemtype, '-background', $color_bgalt);

		### publish new style
		$w1->itemConfigure($p_return, $col, '-style', $style_mod);
	}

}


### Text widget: notifications
my $w_notify = $f_bot->Scrolled('Text', -scrollbars => 'e', 
	-font => $font,
	-foreground => $color_fg,
	-background => $color_bg, 
	-height => 30,
)->pack(-fill => 'both', -expand => 1);



my @common = (-background => $color_bg, -activebackground => $color_bg, -selectforeground => $color_fgselect, -selectbackground => $color_bgselect);
my $style_l = 		$w1->ItemStyle('text', -foreground => $color_fg,  -activeforeground => $color_fg,  @common, -font => $font);
my $style_r = 		$w1->ItemStyle('text', -foreground => $color_fg,  -activeforeground => $color_fg,  @common, -font => $font, -justify => 'right', );
my $style_ignore_l = 	$w1->ItemStyle('text', -foreground => $color_ig,  -activeforeground => $color_ig,  @common, -font => $font);
my $style_ignore_r = 	$w1->ItemStyle('text', -foreground => $color_ig,  -activeforeground => $color_ig,  @common, -font => $font, -justify => 'right', );
my $style_top_l = 	$w1->ItemStyle('text', -foreground => $color_top, -activeforeground => $color_top, @common, -font => $font_big);
my $style_top_r = 	$w1->ItemStyle('text', -foreground => $color_top, -activeforeground => $color_top, @common, -font => $font_big, -justify => 'right', );
my $style_top_r2 = 	$w1->ItemStyle('imagetext', -anchor => 'e', -foreground => $color_top, -activeforeground => $color_top, @common, -font => $font_big, -justify => 'right', );
my $style_top_l2 = 	$w1->ItemStyle('imagetext', -anchor => 'w', -foreground => $color_top, -activeforeground => $color_top, @common, -font => $font_big, -justify => 'left', );

my @opts_l = (-itemtype, 'text', -style, $style_l);
my @opts_r = (-itemtype, 'text', -style, $style_r);
my @opts_ignore_l = (-itemtype, 'text', -style, $style_ignore_l);
my @opts_ignore_r = (-itemtype, 'text', -style, $style_ignore_r);
my @opts_top_l = (-itemtype, 'text', -style, $style_top_l);
my @opts_top_r = (-itemtype, 'text', -style, $style_top_r);
my @opts_hdr = (-headerbackground, $color_hdr);
my @opts_hdr_r = (@opts_hdr, -style, $style_top_r2);
my @opts_hdr_l = (@opts_hdr, -style, $style_top_l2);


### TODO: need initial set / clear at end
my $p_cycle = '';
my $p_cycle_first;
sub copy2clip_iterate {
	print &time2s()." copy2clip_iterate()\n";
	if (! $p_cycle) {
		### TODO
		#my $r = 'Jita -> Amarr';
		#my @p_items = $w1->infoChildren($r);
		#my $i0 = &next_item(\@p_items, -1);
		#$p_cycle = $p_items[$i0];
	}

	my $r = &get_route($p_cycle);
	my @p_items = $w1->infoChildren($r);
	my $n = 0+@p_items;
	foreach my $i (0..$n-1) {
		my $p = $p_items[$i];
		my ($r, $id) = split($Sep, $p);
		if ($id eq 'TOTAL') { last; }
		if ($Data{$r}{$id}{Ignore}) { next; }
		if ($p eq $p_cycle) { 
			### advance iterator
			my $i2 = &next_item(\@p_items, $i);
			$p_cycle = $p_items[$i2];
			my ($r2, $id2) = split($Sep, $p_cycle);
			### copy to clipboard
			copy2clipboard($items_name{$id2});
			### beep
			&my_beep();

			redraw();
			last;
		}
	}
	

}
sub next_item {
	my ($aref, $i1) = @_;
	my @p_items = @{$aref};
	my $n = 0+@p_items;
	my $i2 = $i1;

	while (1) {
		$i2 = ($i2 + 1) % $n;
		my $p = $p_items[$i2];
		my ($r, $id) = split($Sep, $p);
		if ($i2 == $i1) { return $i2;}  ### avoids infinite loop, but could return original $i1
		if ($id eq 'TOTAL') { next; }
		if ($Data{$r}{$id}{Ignore}) { next; }
		print "next_item($i1) => \#$i2 $items_name{$id}\n";
		return $i2;
	}
}
sub get_route {
	my ($p) = @_;
	while ($p && ! &is_route($p)) {
		$p = $w1->infoParent($p);
	}
	return $p;
}


### button: iterate copy-to-clipboard
my $button = $w1->Button(
	-text => 'Age', 
	-command => \&copy2clip_iterate, 
	-padx => 0, -pady => 0, 
	-borderwidth => 0, 
	-highlightthickness => 0, 
	-foreground => $color_top, 
	-activeforeground => $color_top, 
	-background => $color_hdr, 
	-activebackground => $color_hdr, 
	-font => $font_big,
);



### columns
$w1->headerCreate($col_route, -text => 'Route ', @opts_hdr_l);
$w1->columnWidth($col_item, -char => $colwidth_item);
$w1->headerCreate($col_profit, -text => 'Profit ', @opts_hdr_r);
$w1->headerCreate($col_qty, -text => 'Qty ', @opts_hdr_r);
$w1->headerCreate($col_cost, -text => 'Cost ', @opts_hdr_r);
$w1->headerCreate($col_roi, -text => 'ROI ', @opts_hdr_r);
$w1->headerCreate($col_size, -text => 'Volume ', @opts_hdr_r);
$w1->headerCreate($col_age, -text => 'Age ', @opts_hdr_r);
#$w1->headerCreate($col_age, -itemtype => 'window', -widget => $button);
$w1->headerCreate($col_pps, -text => '$/m3 ', @opts_hdr_r);
### these options do not work for header
### -command
### -browsecmd
### -tag
### TODO: sort by selected column
### bind Button-1
### image text (up-/down-arrow)
sub test3 {
	print ">>> test3\n";
}
### NOTE: you cannot bind Tree header cells directly
$mw->bind('<Button-1>', 
	sub { 
		### cursor
		my ($x, $y) = ($mw->pointerx, $mw->pointery);

		### skip if click was outside header row
		if (! &is_hdr($y)) { return; }

		my $c = &which_col($x);
		my $ret = &rotate_sort($c);
		if ($ret) { &redraw(); }

=debug widget/cursor coords
		### implicit padding
		### -borderwidth (Tree.cget())
		### -borderwidth (headerCget())
		### -borderwidth

		my ($w_hdr0, $h_hdr0) = $w1->headerSize(0);
		my ($x_l0_ul, $y_l0_ul, $x_l0_br, $y_l0_br) = $w1->infoBbox('Jita -> Amarr');


		print "\n";
		print "\n>>> X coords\n";
		print "x: ".sprintf("%3i", 0)."-".sprintf("%3i", $w_hdr0-1)." header0\n";


		my $base = $w1->cget('-borderwidth') + $w1->cget('-padx'); 
		my $n = $w1->cget('-columns');
		for (my $i = 0; $i < $n; $i++) {
			my $w = $w1->columnWidth($i);
			### NOTE: columnWidth() of last column does not take expanded window size into account
			### NOTE: infoBbox() does
			#my $w = $w1->columnWidth($i) + (1*$w1->headerCget($i, '-borderwidth'));

			my $x0 = $base;
			my $x1 = $x0 + $w - 1;
			print "x: ".sprintf("%3i", $x0)."-".sprintf("%3i", $x1)." col $i\n";
			$base = $x1 + 1;
		}
		print "x: ".($x_l0_ul)." - ".($x_l0_br)." line0\n";
		print "x: ".sprintf("%7i", $x_rel)." cursor.x\n";


		print "\n>>> Y coords\n";
		print "hlt.w=".$w1->cget('-highlightthickness')."\n";
		#print "hlt.h=".$w1->headerCget(0, '-highlightthickness')."\n";
		#print "hlt.i=".$w1->itemCget('Jita -> Amarr', 0, '-highlightthickness')."\n";
		my $pad_w = $w1->cget('-borderwidth') + $w1->cget('-pady');
		my $s0 = $w1->headerCget(0, '-style');
		my $pad_h = $w1->headerCget(0, '-borderwidth') + $s0->cget('-pady');
		my $y0 = 0;
		my $hdr_h = $pad_w + (2*$pad_h) + $h_hdr0;

		$base = $y1+1-4; 
		print "y: ".sprintf("%3i", $y0)."-".sprintf("%3i", $hdr_h)." header0\n";
		foreach my $p ($w1->infoChildren()) {
			my ($x_ul, $y_ul, $x_br, $y_br) = $w1->infoBbox($p);
			print "y: ".sprintf("%3i", $base+$y_ul)."-".sprintf("%3i", $base+$y_br)." line $p\n";
		}
		print "y: ".sprintf("%7i", $y_rel)." cursor.y\n";
=cut
	} 
);

sub which_col {
	### cursor
	### TODO: traverse all parents, and offset x_w for each
	my ($x_ptr) = @_;
	my $x_abs = $x_ptr;
	my $x = $x_abs - $w1->rootx - $w1->x; 

	my $base = $w1->cget('-borderwidth') + $w1->cget('-padx'); 
	my $n = $w1->cget('-columns');
	for (my $i = 0; $i < $n; $i++) {
		my $w = $w1->columnWidth($i);
		my $x0 = $base;
		my $x1 = $x0 + $w - 1;
		$base = $x1 + 1;
		if ($x <= $x1) { return $i; }
	}
	return $n-1;
}

sub is_hdr {
	### cursor
	### TODO: traverse all parents, and offset for each
	my ($y_ptr) = @_;
	my $y_abs = $y_ptr;
	my $y_rel = $y_abs - $w1->rooty - $w1->y; 

	### header height
	my $pad_w = $w1->cget('-borderwidth') + $w1->cget('-pady');
	my $s0 = $w1->headerCget(0, '-style');
	my $pad_h = $w1->headerCget(0, '-borderwidth') + $s0->cget('-pady');
	my ($w_hdr0, $h_hdr0) = $w1->headerSize(0);
	my $hdr_h = $pad_w + (2*$pad_h) + $h_hdr0;

	($y_rel < $hdr_h);
}


my $bits1 = pack("b8" x 5,
	"........",
	"...11...",
	"..1111..",
	".111111.",
	"........");
$mw->DefineBitmap('uparrow', 8, 5, $bits1);
my $bits2 = pack("b8" x 5,
	"........",
	".111111.",
	"..1111..",
	"...11...",
	"........");
$mw->DefineBitmap('downarrow', 8, 5, $bits2);

$w1->headerConfigure($col_profit, -bitmap => 'downarrow');
my $sort_col = $col_profit;
my $sort_dec = 1;

#&rotate_sort($col_profit);

### legal sort columns:
### -col_profit
### -col_item
### -col_roi
### -col_pps 
sub rotate_sort {
	my ($col_new) = @_;

	print &time2s()." rotate_sort(): sort by ".$w1->headerCget($col_new, -text)."\n";
	### only legal for certain columns
	if ($col_new != $col_item &&
	    $col_new != $col_profit &&
	    $col_new != $col_roi    &&
	    $col_new != $col_pps) { return 0; }

	my $col_old = $sort_col;
	if ($col_new == $sort_col) {
		if ($sort_col == $col_item) { return 0; }
		$sort_dec = ! $sort_dec;
	} else {
		$sort_col = $col_new;
		$sort_dec = 1;
	}

	### turn old arrow off
	$w1->headerConfigure($col_old, -bitmap => '');
		
	### turn new arrow on
	$w1->headerConfigure($sort_col, -bitmap => ($sort_dec ? 'downarrow' : 'uparrow'));
	
	return 1;
}
sub repop_sort {
	my ($r) = @_;
	my @keys_sorted = ();
	if      ($sort_col == $col_profit && $sort_dec == 1) {
		@keys_sorted = (sort {$Data{$r}{$b}{Profit} <=> $Data{$r}{$a}{Profit}} (keys %{$Data{$r}}));
	} elsif ($sort_col == $col_profit && $sort_dec == 0) {
		@keys_sorted = (sort {$Data{$r}{$a}{Profit} <=> $Data{$r}{$b}{Profit}} (keys %{$Data{$r}}));
	} elsif ($sort_col == $col_item) {
		@keys_sorted = (sort {
			my $a2 = $items_name{$Data{$r}{$a}{Item}};
			my $b2 = $items_name{$Data{$r}{$b}{Item}};
			$a2 =~ tr/'//d;
			$b2 =~ tr/'//d;
			$a2 cmp $b2;
		} (keys %{$Data{$r}}));
	} elsif ($sort_col == $col_roi && $sort_dec == 1) {
		@keys_sorted = (sort {$Data{$r}{$b}{ROI} <=> $Data{$r}{$a}{ROI}} (keys %{$Data{$r}}));
	} elsif ($sort_col == $col_roi && $sort_dec == 0) {
		@keys_sorted = (sort {$Data{$r}{$a}{ROI} <=> $Data{$r}{$b}{ROI}} (keys %{$Data{$r}}));
	} elsif ($sort_col == $col_pps && $sort_dec == 1) {
		@keys_sorted = (sort {$Data{$r}{$b}{ProfitPerSize} <=> $Data{$r}{$a}{ProfitPerSize}} (keys %{$Data{$r}}));
	} elsif ($sort_col == $col_pps && $sort_dec == 0) {
		@keys_sorted = (sort {$Data{$r}{$a}{ProfitPerSize} <=> $Data{$r}{$b}{ProfitPerSize}} (keys %{$Data{$r}}));
	}
	return @keys_sorted;
}


my @fields_style = (
	'-foreground',
	'-background',
	'-activeforeground',
	'-activebackground',
	'-font',
	'-justify',
	'-anchor',
	'-padx',
	'-padx',
);

my $style_indic2 = $w1->ItemStyle('image', 
#	-foreground => $color_fg, 		# fail
#	-activeforeground => $color_fg,		# fail
	-background => $color_fg,  		# Y
	-activebackground => $color_fg,  	# Y
);


### Styles{} cache
### key = joined list of style fields
### val = style ref
my %Styles = (); 
sub get_style {
	my (%style_as_hsh, $itemtype) = @_;
	
	### styleID = serialized style field values
	my @style_as_ary = ();
	foreach my $key (@fields_style) {
		my $val = $style_as_hsh{$key};
		push(@style_as_ary, ($key, $val));
	}
	my $style_as_id = join(':', @style_as_ary);

	my $style2 = $Styles{$style_as_id};
	if (! $style2) {
		$style2 = $mw->ItemStyle($itemtype, (@style_as_ary));
		$Styles{$style_as_id} = $style2;
		#print ">>> mod_style() new >[$itemtype]$style_as_id<\n";
		#print "    -itemtype => $itemtype\n";
		foreach my $key (@fields_style) { print "    $key => $style_as_hsh{$key}\n"; }
	} else {
		#print ">>> mod_style() dup\n";
	}

	return $style2;
}
sub mod_style {
	my ($style1, $itemtype, $opt1, $val1, $opt2, $val2) = @_;

	### convert existing style to hash
	my %style_as_hsh = ();
	foreach my $field (@fields_style) {
		$style_as_hsh{$field} = $style1->cget($field);
	}
	
	### overwrite new value(s)
	$style_as_hsh{$opt1} = $val1;
	if ($opt2) { $style_as_hsh{$opt2} = $val2; }

	### styleID = serialized style field values
	my @style_as_ary = ();
	foreach my $key (@fields_style) {
		my $val = $style_as_hsh{$key};
		push(@style_as_ary, ($key, $val));
	}
	my $style_as_id = join(':', @style_as_ary);

	### get modified style (cached)
	my $style2 = $Styles{$style_as_id};
	if (! $style2) {
		$style2 = $mw->ItemStyle($itemtype, (@style_as_ary));
		$Styles{$style_as_id} = $style2;
		#print ">>> mod_style() new\n[$itemtype]$style_as_id<\n";
		#print "    -itemtype => $itemtype\n";
		#foreach my $key (@fields_style) { print "    $key => $style_as_hsh{$key}\n"; }
	} else {
		#print ">>> mod_style() dup\n";
	}

	return $style2;


	#return &get_style(\%style_as_hsh, $itemtype);
}

sub change_color_cell {
	my ($p, $x, $color) = @_;
	if (! $w1->itemExists($p, $x)) { return; }
	
	### get current style ref
	my $styleref1 = $w1->itemCget($p, ($x ? $x : 0), '-style');
	my $itemtype = $w1->itemCget($p, ($x ? $x : 0), '-itemtype');

	### create modified style
	my $styleref2 = &mod_style($styleref1, $itemtype, "-foreground", $color, "-activeforeground", $color);

	### apply modified style
	$w1->itemConfigure($p, $x, '-style', $styleref2);
}

sub change_color_cell2 {
	my ($p, $x, $color) = @_;
	#if (! &is_item($p)) { return; }
	if (! $w1->itemExists($p, $x)) { return; }
	
	### get current style ref
	my $styleref1 = $w1->itemCget($p, ($x ? $x : 0), '-style');
	my $itemtype = $w1->itemCget($p, ($x ? $x : 0), '-itemtype');

	my %vals_h = ();
	foreach my $field (@fields_style) {
		$vals_h{$field} = $styleref1->cget($field);
		#print ">>> $field => $vals_h{$field}\n";
	}
	
	### change color fields
	$vals_h{'-foreground'} = $color;
	$vals_h{'-activeforeground'} = $color;

	### serialize
	my @vals_a = ();
	foreach my $key (@fields_style) {
		my $val = $vals_h{$key};
		push(@vals_a, ($key, $val));
	}
	my $styleid = join(':', @vals_a);
	
	### get modified style ref
	my $styleref2 = $Styles{$styleid};
	if (! $styleref2) {
		$styleref2 = $mw->ItemStyle('text', (@vals_a));
		$Styles{$styleid} = $styleref2;
	}

	#my $styleref2 = &mod_style($styleref1, $itemtype, -foreground => $color, -activeforeground => $color);

	### apply modified style
	#print ">>> change_color() $p, col $x, color $color\n";
	$w1->itemConfigure($p, $x, '-style', $styleref2);
}

sub change_color {
	my ($p, $color, $x) = @_;
	
	if ($x) { ### change one cell only
		change_color_cell($p, $x, $color);
	} else { ### change whole row
		foreach my $x (0..$nCols-1) {
			#if ($x == $col_size) { next; }
			change_color_cell($p, $x, $color);
		}
	}	
}
sub underline_cell {
	my ($p, $x) = @_;
	#print "underline_cell() $p.$x\n";
	if (! $w1->itemExists($p, $x)) { return; }
	
	### get current style ref
	my $styleref1 = $w1->itemCget($p, ($x ? $x : 0), '-style');
	my %vals_h = ();
	foreach my $field (@fields_style) {
		$vals_h{$field} = $styleref1->cget($field);
		#print ">>> $field => $vals_h{$field}\n";
	}
	
	### change fields
	my $font = $vals_h{'-font'};
	$vals_h{'-font'} = $font." underline";

	### serialize
	my @vals_a = ();
	foreach my $key (@fields_style) {
		my $val = $vals_h{$key};
		push(@vals_a, ($key, $val));
	}
	my $styleid = join(':', @vals_a);
	
	### get modified style ref
	my $styleref2 = $Styles{$styleid};
	if (! $styleref2) {
		$styleref2 = $mw->ItemStyle('text', (@vals_a));
		$Styles{$styleid} = $styleref2;
	}

	### apply modified style
	#print ">>> change_color() $p, col $x, color $color\n";
	$w1->itemConfigure($p, $x, '-style', $styleref2);
}

sub notify_check {
	my ($r, $id) = @_;
	
	if (  $Data{$r}{$id}{Profit} > $notify_threshold_price && 
	      ( (time - $Data{$r}{$id}{Asks_Age} < $notify_threshold_age) || 
	        (time - $Data{$r}{$id}{Bids_Age} < $notify_threshold_age) 
	      )
	   ) 
	{ 
		&notify_add($r, $id);
	}


}
sub notify_add {
	my ($r, $id) = @_;
	#print &time2s()." notify_add() $r $id\n";
	my $key = $r.$Sep.$id;
	if ($Notify{$key}) { return; }
	if ($Data{$r}{$id}{Ignore}) { return; }
	
	$Notify{$key} = $Data{$r}{$id}{Profit};
	if ($Data{$r}{$id}{Profit} > $notify_threshold_price_super) { &my_beep(); }
}

my @test_colors = ();
my ($r1, $g1, $b1) = (0xff, 0xa5, 0x00);
my ($r2, $g2, $b2) = (0xff, 0xff, 0x46);
my $steps = 8;
my $glow_ms = 100;

for my $i (0..$steps) {
	my $r3 = $r1;
	my $g3 = $g1;
	my $b3 = $b1;
	my $color = '#'.sprintf("%02x",$r3).sprintf("%02x",$g3).sprintf("%02x",$b3);
	push(@test_colors, $color);
}
for my $i (0..$steps) {
	my $r3 = $r1 + int(($r2-$r1)*$i/$steps);
	my $g3 = $g1 + int(($g2-$g1)*$i/$steps);
	my $b3 = $b1 + int(($b2-$b1)*$i/$steps);
	my $color = '#'.sprintf("%02x",$r3).sprintf("%02x",$g3).sprintf("%02x",$b3);
	push(@test_colors, $color);
}
for (my $i=$steps-1; $i > 0; $i--) {
	my $r3 = $r1 + int(($r2-$r1)*$i/$steps);
	my $g3 = $g1 + int(($g2-$g1)*$i/$steps);
	my $b3 = $b1 + int(($b2-$b1)*$i/$steps);
	my $color = '#'.sprintf("%02x",$r3).sprintf("%02x",$g3).sprintf("%02x",$b3);
	push(@test_colors, $color);
}

#my @test_colors = (
#	'#000000',
#	'#202020',
#	'#404040',
#	'#606060',
#	'#808080',
#	'#a0a0a0',
#	'#c0c0c0',
#	'#e0e0e0',
#	'#e0e0e0',
#	'#ffffff',
#);
my $test_n = 0;
my $test_curr_color = 0;
sub test_refresh {
	$test_n++;
	my $n = (0+@test_colors);
	my $x = $test_n % $n;
	my $color = $test_colors[$x];
	if ($color ne $test_curr_color) { $w_notify->tagConfigure("glow", -foreground => $color); }
	$test_curr_color = $x;
}

### Notify[]: key is route-item pathname, value is item profit 
sub notify_refresh {
	#print &time2s()." notify_refresh()\n";
	$w_notify->delete("1.0", 'end');
	
	my $tag3 = "glow";
	my $status = &time2s()." -- ";
	$status .= ($Net_tax == 0.9925) ? "Accounting V, " : "Accounting IV, ";
	$status .= "$N_items items, $N_orders bids/asks";
	$status .= "\n";
	$w_notify->insert('1.0', $status);
	$w_notify->insert('2.0', "this is a test of glowing\n", [$tag3]);

	
	foreach my $key (sort {$Notify{$a} <=> $Notify{$b};} keys %Notify) {
		my ($r, $id) = split($Sep, $key);
		if (! $Data{$r}{$id}) { next; } ### item may have dropped out

		my ($from, $to) = split(' -> ', $r);
		my $profit = $Data{$r}{$id}{Profit};
		my $when = &max($Data{$r}{$id}{Asks_Age}, $Data{$r}{$id}{Bids_Age});
		my $age = time - $when;

		### age out after 1 hour
		if ($age > 60*60) { delete $Notify{$key}; next; }
		
		### text
		my $t = "";
		#$t.= &time2m($when);
		#$t.= " ";
		$t.= sprintf("%4s", &age2s($when))." ago";
		$t.= " ";
		$t.= sprintf("%5s", &iski2s($Data{$r}{$id}{Profit}));
		$t.= " - ";
		$t.= "[".$from." to ".$to."]";
		$t.= "\t";
		$t.= $items_name{$id};
		$t.= " ";
		$t.= "(\$".sprintf("%i", (int(($Data{$r}{$id}{Profit}/$Data{$r}{$id}{Size})/100.0))*100 )."/m3)";
		$t.= "\n";

		### tags
		my $w2 = $w_notify;
		### tag 1: link to item
		my $p = $r.$Sep.$id;
		my $tag1 = "$r$id"; $tag1 =~ tr/ //d; ### strip spaces
		$w2->tagBind($tag1, "<Button-1>", sub {
			### collapse all
			my @p_routes = $w1->infoChildren();
			foreach my $pr (@p_routes) {
				my @p_items = $w1->infoChildren($pr);
				foreach my $pi (@p_items) {
					$w1->close($pi);	
				}
				$w1->close($pr);	
			}
			### open + select
			$w1->open($r);
			$w1->open($p);
			$w1->selectionClear();
			$w1->selectionSet($p);
		
		});
		#$w2->tagBind($tag1, "<Any-Enter>", sub {shift->tagConfigure($tag1, -underline => 1);});
		#$w2->tagBind($tag1, "<Any-Leave>", sub {shift->tagConfigure($tag1, -underline => 0);});
		$w2->tagBind($tag1, "<Any-Enter>", sub {shift->tagConfigure($tag1, -underline => 1);});
		$w2->tagBind($tag1, "<Any-Leave>", sub {shift->tagConfigure($tag1, -underline => 0);});
		### tag 2: color by age
		my $tag2 = &notify_color($when);

		$w2->insert('1.0', $t, [$tag1, $tag2]);

	}
	
	#$w_notify->insert('end', "pid_crest \t$pid_crest\n");
}
foreach ($color_urgent_red, $color_urgent_orange, $color_urgent_yellow, $color_fg) {
	$w_notify->tagConfigure($_, -foreground => $_);
}
sub notify_color {
	my ($timestamp) = @_;
	my $age = time - $timestamp;
	if ($age < 5*60) {
		return $color_urgent_red; 
	} elsif ($age < 15*60) { 
		return $color_urgent_orange; 
	} elsif ($age < 30*60) {
		return $color_urgent_yellow; 
	} else {
		return $color_fg; 
	}
}	




my $p_cycle = '';
my $p_cycle_first;

sub pick_color {
	my ($p_item, $x) = @_;
	if (&is_item($p_item) && ! $x) { 
		my ($r, $i) = split($Sep, $p_item);
		if ($Data{$r}{$i}{Ignore}) { 
			change_color($p_item, $color_ig);
		} elsif ($p_item eq $p_cycle) {
			change_color($p_item, $color_brightred);
		} else {
			change_color($p_item, $color_green);
		}
	} elsif (&is_item($p_item) && $x) {
		### p[x] => set [x] to match [0]
		if (! $w1->itemExists($p_item, $x)) { return; }
		my $styleref1 = $w1->itemCget($p_item, 0, '-style');
		my $color = $styleref1->cget('-foreground');
		&change_color_cell($p_item, $x, $color);
	}	
}


### popup menu
my $This; ### global path reference passed by <Button-3> invocation
my $menucmd_copy_route = ['command', 'Copy route', -command => sub {
	### ARG: $This
	my $route = &is_route($This);
	if (! $route) { return 0; }
	&route2clipboard($route);
}];
my $menucmd_copy_item = ['command', 'Copy item', -command => sub {
	### ARG: $This
	my $i = &is_item($This);
	if (! $i) { return 0; }
	copy2clipboard($items_name{$i});
}];


sub copy2clip_iterate {
	print &time2s()." copy2clip_iterate()\n";

	my $r = &get_route($p_cycle);
	my @p_items = $w1->infoChildren($r);
	my $n = 0+@p_items;
	foreach my $i (0..$n-1) {
		my $p = $p_items[$i];
		my ($r, $id) = split($Sep, $p);
		if ($id eq 'TOTAL') { last; }
		if ($Data{$r}{$id}{Ignore}) { next; }
		if ($p eq $p_cycle) { 
			### advance iterator
			my $i2 = &next_item(\@p_items, $i);
			$p_cycle = $p_items[$i2];
			my ($r2, $id2) = split($Sep, $p_cycle);
			### copy to clipboard
			Clipboard->copy($items_name{$id2});
			### beep
			&my_beep();

			redraw();
			last;
		}
	}
	

}
sub next_item {
	my ($aref, $i1) = @_;
	my @p_items = @{$aref};
	my $n = 0+@p_items;
	my $i2 = $i1;

	while (1) {
		$i2 = ($i2 + 1) % $n;
		my $p = $p_items[$i2];
		my ($r, $id) = split($Sep, $p);
		if ($i2 == $i1) { return $i2;}  ### avoids infinite loop, but could return original $i1
		if ($id eq 'TOTAL') { next; }
		if ($Data{$r}{$id}{Ignore}) { next; }
		print "next_item($i1) => \#$i2 $items_name{$id}\n";
		return $i2;
	}
}
sub get_route {
	my ($p) = @_;
	while ($p && ! &is_route($p)) {
		$p = $w1->infoParent($p);
	}
	return $p;
}



sub fn_iterative_copy {
	my ($p) = @_;
	if (! $p) { $p = $This; }
	
	if (&is_route($p)) {
		my $r = $p;
		my @p_items = $w1->infoChildren($r);
		my $i0 = &next_item(\@p_items, -1);
		$p_cycle = $p_items[$i0];
	} elsif (&is_item($p)) {
		$p_cycle = $p;
	}

	my ($r2, $id2) = split($Sep, $p_cycle);
	copy2clipboard($items_name{$id2});
	&my_beep();
	&redraw();
}
my $menucmd_iterative_copy = ['command', 'Iterative copy', -command => \&fn_iterative_copy];

my $h_cycle;
sub fn_iterate_start {
	&fn_iterative_copy();
	$p_cycle_first = $p_cycle;
	$h_cycle = $w1->repeat(5500, \&fn_iterate);
}
sub fn_iterate_start_fast {
	&fn_iterative_copy();
	$p_cycle_first = $p_cycle;
	sleep 1;
	$h_cycle = $w1->repeat(3500, \&fn_iterate);
}
sub fn_iterate {
	&copy2clip_iterate();
	if ($p_cycle eq $p_cycle_first) {
		$h_cycle->cancel();
		print &time2s()." iterate() cycle ended\n";
		$p_cycle = '';
		&my_beep();
		&redraw();
	}
}
sub fn_iterate_stop {
	$h_cycle->cancel();
}
my $menucmd_iterate_start = ['command', 'Iterate', -command => \&fn_iterate_start];
my $menucmd_iterate_start2 = ['command', 'Fast Iterate', -command => \&fn_iterate_start_fast];
my $menucmd_iterate_stop = ['command', 'Stop iterate', -command => \&fn_iterate_stop];

sub toggle_item {
	my ($p) = @_;
	#print "toggle_item() $p\n";
	if (! &is_item($p)) { return 0;}
	my ($r, $i) = split($Sep, $p);
	$Data{$r}{$i}{Ignore} = !($Data{$r}{$i}{Ignore});
	$Ignore{$r.$Sep.$i} = $Data{$r}{$i}{Ignore};
}
sub ignore_item {
	my ($p) = @_;
	#print "ignore_item() $p\n";
	if (! &is_item($p)) { return 0;}
	my ($r, $i) = split($Sep, $p);
	$Data{$r}{$i}{Ignore} = 1;
	$Ignore{$r.$Sep.$i} = 1;
}
my $menucmd_ignore = ['command', 'Toggle ignore', -command => sub { 
	### ARG: $This
	### disregards ignore() at route- or order-level
	my @selected = $w1->infoSelection();
	#print "ignore(): selection of ".(@selected+0)."\n";
	if (@selected <= 1) {
		### case: active item (no selection)
		if (&is_order($This)) { 
			### TODO: order-level ignore
			### disregard
		} elsif (&is_item($This)) { 
			&toggle_item($This);
			&redraw();
		} else { 
			### ignore() invoked at route-level 
			### disregard
		}
	} else {
		### case: multiple items selected
		foreach my $p (@selected) {
			### TODO: order-level ignore
			if (&is_item($p)) {
				&toggle_item($p);
			}
		}
		$w1->selectionClear();
		&redraw();	
	}
}];
my $doubleclickcmd = [ 
	sub {
		my ($w, $p) = @_;
		#print "doubleclickcmd() window=$w, path=$p\n";

		if (&is_item($p)) {
			&toggle_item($p);
			$w->selectionClear();
			&redraw();
		} elsif (&is_route($p)) {
			my $mode = $w->getmode($p);
			if ($mode eq 'open') {
				$w->open($p);
			} else {
				$w->close($p);
				#&opencmd_fn($w, $p);
			}
		}
	},
	$w1, ### Tree widget
];
$w1->configure(-command => $doubleclickcmd);

my $menucmd_ignore_below = ['command', 'Ignore all below', -command => sub { 
	if (&is_item($This)) { 
		print "   $This\n";

		my ($r1, $i1) = split($Sep, $This);
		if (! $Data{$r1}{$i1}{Ignore}) {
			$Data{$r1}{$i1}{Ignore} = 1;
			$Ignore{$r1.$Sep.$i1} = 1;
		}
		my $p2 = $This;
		while ($p2 = $w1->infoNext($p2)) {
			if (!&is_item($p2)) { next; }
			my ($r2, $i2) = split($Sep, $p2);
			if ($i2 eq "TOTAL") { last; }
			if ($r2 ne $r1) { warn "unreachable"; last; }
			if (! $Data{$r2}{$i2}{Ignore}) {
				$Data{$r2}{$i2}{Ignore} = 1;
				$Ignore{$r2.$Sep.$i2} = 1;
			}
		}
		&redraw();
	}	
}];
my $menucmd_ignore_reset = ['command', 'Reset all ignores', -command => sub { 
	foreach my $ig (keys %Ignore) {
		my ($r, $i) = split($Sep, $ig);
		$Data{$r}{$i}{Ignore} = 0;
	}
	%Ignore = ();
	&redraw();
}];
my $menucmd_update = ['command', '(force sync)', -command => sub {
	### update from file
	&refresh_server_data();
}];
sub fn_collapse_all {
	my @p_routes = $w1->infoChildren();
	foreach my $pr (@p_routes) {
		my @p_items = $w1->infoChildren($pr);
		foreach my $pi (@p_items) {
			$w1->close($pi);	
		}
		$w1->close($pr);	
	}
}
my $menucmd_collapse_all = ['command', 'Collapse all', -command => \&fn_collapse_all];

my $m1 = $mw->Menu(
	-popover => 'cursor', 
	-popanchor => 'nw', 
	-overanchor => 'se',

	-borderwidth => 0,
#	-relief => 'flat',
	-activeborderwidth => 0,

	-activebackground => $color_bgselect,
	-background => $color_menubg,
	-foreground => $color_menufg,
	-font => $font_menu,
	-tearoff => 0,
	-postcommand => \&menu_popup_postcmd,
);

my $menucmd_geometry = ['command', '(my geometry)', -command => sub {
	my $x = $w1->width;
	my $y = $w1->height;
	print "$x x $y\n";

	my $screen = $w1->screen;
	print ">>> screen $screen ".$w1->screenwidth." x ".$w1->screenheight."\n";

	my $y_cur = $w1->pointery;
	my $y_win = $w1->y;
	my $y_root = $w1->rooty;
	my $y2 = $y_cur - ($y_root + $y_win);
	#print ">>> Y-coords rel_y=$y2, root=$y_root, win=$y_win, cur=$y_cur\n";
	my $x_cur = $w1->pointerx;
	my $x_win = $w1->x;
	my $x_root = $w1->rootx;
	my $x2 = $x_cur - ($x_root + $x_win);
	#print ">>> X-coords rel_x=$x2, root=$x_root, win=$x_win, cur=$x_cur\n";

	print ">>> w1    ($x_root, $y_root)\n";
	my $geo = $m1->geometry;
	$geo =~ /([0-9]+)x([0-9]+)([\+-]+[0-9]+)([\+-]+[0-9]+)/;
	my ($pw, $ph, $px, $py) = ($1, $2, $3, $4);
	print ">>> popup abs (".($w1->pointerx).", ".($w1->pointery).")\n";
	print ">>> popup rel (".($w1->pointerx - $w1->rootx).", ".($w1->pointery - $w1->rooty).")\n";
}];

sub fn_debug_item {
	my $p = $This;
	my ($r, $i) = split($Sep, $p);

	my $FH;
	open($FH, '>>', 'errorlog.txt');
	flock($FH, LOCK_EX);

	print $FH "item ID $i NAME >$items_name{$i}< ROUTE >$r<\n";

	close $FH;

}
my $menucmd_debug_item = ['command', '(debug item)', -command => \&fn_debug_item];


my $menuitems_item = [
	$menucmd_copy_route,
	$menucmd_copy_item,
	$menucmd_iterate_start,
	$menucmd_iterate_start2,
	'',
	$menucmd_ignore,
	$menucmd_ignore_below,
	'',
	$menucmd_collapse_all,		
	'',
	$menucmd_ignore_reset,
	$menucmd_geometry,
	$menucmd_debug_item,		
	$menucmd_iterate_stop,
];
my $menuitems_route = [
	$menucmd_copy_route,
	$menucmd_iterate_start,
	$menucmd_iterate_start2,
	'',
	$menucmd_collapse_all,		
	'',
	$menucmd_geometry,		
	$menucmd_iterate_stop,
];


### context-sensitive popup
sub menu_popup_postcmd {
	#my ($arg1, $arg2) = @_;
	#print "postcommand() \$This = \"$This\", arg1=$arg1, arg2=$arg2\n";
	#print "postcommand() \$This = \"$This\"\n";
	my $menu = $m1;
	
	### delete all
	$menu->delete(0, 'last');
	
	### repopulate based on path type
	my $menuitems_ref;
	if (&is_route($This)) {
		$menuitems_ref = $menuitems_route;
	} elsif (&is_item($This)) {
		$menuitems_ref = $menuitems_item;
	} elsif (&is_order($This)) {
	}

	foreach my $mcmd (@$menuitems_ref) {
		if ($mcmd eq '') {
			$menu->separator();
		} else {
			$menu->command(-label => $$mcmd[1], $$mcmd[2] => $$mcmd[3]);
		}
	}

	### print all widget options
	#use Tk::Pretty;
	#my @config = $m1->configure;
	#print Pretty @config;
}

### bind popup menu to right-click
### '<Button-3>' = mouse-right-click 
$w1->bind('<Button-3>', 
	sub { 
		#my ($class_this) = @_; 
		### set global for callback
		$This = get_my_path($w1);
		### need to use post() bc Popup() gets confused by multiple monitors
		$m1->post($m1->pointerx, $m1->pointery);  
	} 
);

sub get_my_path {
	my ($w1) = @_;
	my $cur = $w1->pointery;
	my $win = $w1->y;
	my $root = $w1->rooty;
	#print "Y-coords root=$root win=$win cur=$cur\n";
	my $y = $cur - ($root + $win);
	return $w1->nearest($y);
}






### UTILITY FNS ###

### default display order
my @Routes = (
	"Jita -> Amarr",
	"Jita -> Dodixie",
	"Jita -> Rens",
	"Amarr -> Jita",
	"Amarr -> Dodixie",
	"Amarr -> Rens",
	"Dodixie -> Jita",
	"Dodixie -> Amarr",
	"Dodixie -> Rens",
	"Rens -> Jita",
	"Rens -> Amarr",
	"Rens -> Dodixie",
);
my %is_region = ();
my $reg_providence = 10000047; $is_region{$reg_providence} = 1;
my $reg_lonetrek =   10000016; $is_region{$reg_lonetrek} = 1;
my $reg_pureblind =  10000023; $is_region{$reg_pureblind} = 1;
my $reg_thespire =   10000018; $is_region{$reg_thespire} = 1;





my $reg_domain     = 10000043;
my $reg_theforge   = 10000002;
my $reg_sinqlaison = 10000032;
my $reg_heimatar =   10000030;

my $sys_amarr =   30002187;
my $sys_jita =    30000142;
my $sys_dodixie = 30002659;
my $sys_rens =    30002510;
my $stn_amarr =   60008494;
my $stn_jita = 	  60003760;
my $stn_dodixie = 60011866;
my $stn_rens =    60004588;
my %Hubs = (
	$stn_jita => "Jita IV - Moon 4 - Caldari Navy Assembly Plant",
	$stn_amarr => "Amarr VIII (Oris) - Emperor Family Academy",
	$stn_dodixie => "Dodixie IX - Moon 20 - Federation Navy Assembly Plant",
	$stn_rens => "Rens VI - Moon 8 - Brutor Tribe Treasury",
);

my %stn2sys = (
	$stn_amarr => $sys_amarr,
	$stn_jita => $sys_jita,
	$stn_dodixie => $sys_dodixie,
);

### in: station ID
### based on @Hubs_stnid list
my %is_hub = ();
sub stn_is_hub {
	my ($stn_id) = @_;

	### init lookup table
	if (! %is_hub) {
		foreach my $_id (keys %Hubs) {
			$is_hub{$_id} = 1;
		}
	}
	
	return $is_hub{$stn_id};
}

my %sys_names = (
	$sys_amarr => "Amarr",
	$sys_jita => "Jita",
	$sys_dodixie => "Dodixie",
	$sys_rens => "Rens",
	$reg_providence => "Providence",	
	$reg_lonetrek => "Lonetrek",
	$reg_pureblind => "Pure Blind",
	$reg_thespire => "The Spire",
);
my %sys2reg = (
	'Amarr' => 'Domain',
	'Jita' => 'The Forge',
	'Dodixie' => 'Sinq Laison',
	'Rens' => 'Heimatar',
);
my %primary_stations = (
	"Jita" => "Jita IV - Moon 4 - Caldari Navy Assembly Plant",
	"Amarr" => "Amarr VIII (Oris) - Emperor Family Academy",
	"Dodixie" => "Dodixie IX - Moon 20 - Federation Navy Assembly Plant",
	"Rens" => "Rens VI - Moon 8 - Brutor Tribe Treasury",

);
my %stn2reg = (
	"Jita IV - Moon 4 - Caldari Navy Assembly Plant" => 'The Forge',
	"Amarr VIII (Oris) - Emperor Family Academy" => 'Domain',
	"Dodixie IX - Moon 20 - Federation Navy Assembly Plant" => 'Sinq Laison',
	"Rens VI - Moon 8 - Brutor Tribe Treasury" => 'Heimatar',

);
my %_hub2sys = (
	"Jita IV - Moon 4 - Caldari Navy Assembly Plant" => $sys_jita,
	"Amarr VIII (Oris) - Emperor Family Academy" => $sys_amarr,
	"Dodixie IX - Moon 20 - Federation Navy Assembly Plant" => $sys_dodixie,
	"Rens VI - Moon 8 - Brutor Tribe Treasury" => $sys_rens,
);
my %reg_n2i = (
	'Domain'      	=> $reg_domain,
	'The Forge'   	=> $reg_theforge,
	'Sinq Laison' 	=> $reg_sinqlaison,
	'Heimatar' 	=> $reg_heimatar,
);
my %reg_i2n = (
	$reg_domain 	=> 'Domain',
	$reg_theforge	=> 'The Forge',
	$reg_sinqlaison => 'Sinq Laison',
	$reg_heimatar 	=> 'Heimatar',
);

sub hub2sys {
	my ($hubStnFullName) = @_;
	my $hubSysID = $_hub2sys{$hubStnFullName};
	return $hubSysID;
}
my %_reg2hub = ();
sub reg2hub {
	my ($reg) = @_;
	### init lookup table
	if (! %_reg2hub) {
		foreach my $stnName (keys %stn2reg) {
			$_reg2hub{$stn2reg{$stnName}} = $stnName;
		}
	}
	return $_reg2hub{$reg};
}
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
sub where2s {
	my ($station_fullname) = @_;
	my $where = substr($station_fullname, 0, index($station_fullname, " "));
}	
### END: copied from skynet
sub is_order {
	my ($path) = @_;
	if ($path =~ /(.*)$Sep(.*)$Sep(.*)/) { 	### bid/ask order
		return $3;
	} elsif ($path =~ /(.*)\~(.*)/) {  	### item
		return 0;
	} else {  				### route
		return 0;
	}
}
sub is_item {
	my ($path) = @_;
	if ($path =~ /(.*)$Sep(.*)$Sep(.*)/) { 	### bid/ask order
		return 0;
	} elsif ($path =~ /(.*)$Sep(.*)/) {  	### item
		return $2;
	} else {  				### route
		return 0;
	}
}
sub is_route {
	my ($path) = @_;
	if ($path =~ /(.*)$Sep(.*)$Sep(.*)/) { 	### bid/ask order
		return 0;
	} elsif ($path =~ /(.*)$Sep(.*)/) {  	### item
		return 0;
	} else {  				### route
		return $path;
	}
}
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
sub isk2s {
	my ($n) = @_;
	if (! defined $n) { die "empty isk"; }
	$n =~ tr/,//d;  # strip ,
	$n =~ tr/\$//d; # strip $
	if ($n >= 1000000000) { return '$'.sprintf("%2.1f", $n/1000000000.0)."B"; }
	return '$'.sprintf("%2.1f", $n/1000000.0)."M";
}
sub iski2s {
	my ($n) = @_;
	if (! defined $n) { die "empty isk"; }
	$n =~ tr/,//d;  # strip ,
	$n =~ tr/\$//d; # strip $
	if ($n >= 1000000000) { return '$'.sprintf("%2.1f", $n/1000000000.0)."B"; }
	return '$'.sprintf("%i", $n/1000000.0)."M";
}
sub age2s {
	my ($t, $now) = @_;
	if (! $now) { $now = time; }
	my $x = $now - $t;
	if ($x > 3600) { return sprintf("%.1f", $x/3600)."h"; }
	else { return sprintf("%i", $x/60)."m"; }
}
sub time2s {
	my ($t) = @_;
	if (! $t) { $t = time; }
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
	sprintf("%i:%02i:%02i", ($hour > 12)?($hour-12):$hour, $min, $sec).(($hour>11)?"pm":"am");
}
sub time2m {
	my ($t) = @_;
	if (! $t) { $t = time; }
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
	sprintf("%i:%02i", ($hour > 12)?($hour-12):$hour, $min).(($hour>11)?"pm":"am");
}
sub locs2r {
	my ($from, $to) = @_;
	return &where2s($from).' -> '.&where2s($to);
}
sub route2stns {
	my ($route) = @_;
	$route =~ m/(.*) -\> (.*)/;
	my ($from_s, $to_s) = ($1, $2);
	return ($primary_stations{$from_s}, $primary_stations{$to_s});
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
sub commai {
	my ($x, $y) = @_;
	#print "\ncomma  ($x)\n";

	my $r = sprintf("%i", $x);

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
	
	### add whitespace to desired field length
	$n = length $r;
	if ($y && ($y > $n)) { 
		#print "comma() add ".($y-$n)." spaces\n";
		for my $i (1..($y-$n)) { $r=' '.$r;} 
	}

	$r;
}
sub print_all_config {
	my ($w) = @_;
	my @config = $w->configure;
	print Pretty @config;
	print "\n";
}



sub size2expanders {
	my ($size) = @_;
	if ($size > 7012) {
		return 3;
	} elsif ($size > 5478) {
		return 2;
	} elsif ($size > 4275) {
		return 1;
	} else {
		return 0;
	}
}

### REAL FNS ###

### copy manifest to clipboard
sub route2clipboard {
	my ($r) = @_;
	$r =~ m/(.*) -\> (.*)/;
	my ($from_s, $to_s) = ($1, $2);
		
	my $text = '';
	my $eol = "\r\n";
	
	### force recalc(), which filters out unprofitable bid/ask orders
	&redraw();
	
	### OUTPUT: list of item names, alphabetized (for copy/paste)
	my @list = ();
	foreach my $i (sort {$Data{$r}{$b}{Profit} <=> $Data{$r}{$a}{Profit}} (keys %{$Data{$r}})) {
		if ($Data{$r}{$i}{Ignore}) { next; }
		#$text.= $items_name{$i}.$eol;
		push(@list, $items_name{$i});
	}	
	### alphabetize
	foreach (sort {
			my $a2 = $a;
			my $b2 = $b;
			$a2 =~ tr/'//d;
			$b2 =~ tr/'//d;
			$a2 cmp $b2;
		} @list) {
		$text.= $_.$eol;
	}


	### OUTPUT (header)
	$text.= $eol.$eol;
	### OUTPUT: route name (ex "JITA => AMARR")
	$text.= (uc $from_s)." => ".(uc $to_s);
	### OUTPUT: total profit (ex: "+$101,648,363.99")
	$text.= "  +\$".&comma($Totals{$r}{Profit});
	#$text.= " (".sprintf("%.1f", $Totals{$r}{Profit}*100.0/$Totals{$r}{Cost})."% ROI)";
	### OUTPUT: size (ex: "(5,063 m3 x2**)")
	my $size = $Totals{$r}{Size};
	my $text_mods = "";
	my $nmods = &size2expanders($size);
	if ($nmods) {
		$text_mods = "  [ *";
		for (my $i=2; $i<=$nmods; $i++) {
			$text_mods .= " *";
		}
		$text_mods .= " ]";
	}
	$text.= "  (".&commai($Totals{$r}{Size})." m3)".$text_mods;
	$text.= $eol;
	### OUTPUT: timestamp (ex "19:10")
	my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime(time);
	$text.= sprintf("%02i:%02i", ($hour+8)%24, $min);
	$text.= "  ".&checksum_out($Totals{$r}{Checksum}, 3);
	$text.= $eol;


	### bid/ask lists
	my $n_items = 1;
	foreach my $i (sort {$Data{$r}{$b}{Profit} <=> $Data{$r}{$a}{Profit}} (keys %{$Data{$r}})) {
		if ($Data{$r}{$i}{Ignore}) { next; }

		### separator every N items
		my $break = 3;
		if ((($n_items-1) % $break) == 0 and not $n_items==1) {
			$text.= $eol;
			$text.= "-----";
			$text.= " ";
			$text.= (uc $from_s)." => ".(uc $to_s);
			$text.= " ";
			$text.= "-----";
		}

		$text.= $eol.$eol;

		### Item
		my $profit = $Data{$r}{$i}{Profit};
		my $qty = $Data{$r}{$i}{Qty}; 
		$text.= $items_name{$i}.$eol;
		$text.= $n_items++."\. +\$".&comma($profit)."   [x $qty]$eol";

		### Asks
		my $ask_hi;
		my $ask_qty = 0;
		foreach my $ask (@{$Data{$r}{$i}{Asks}}) {
			my ($price, $vol, $ignore, $when) = split(':', $ask);
			if (! $ask_hi) { $ask_hi = $price; }
			if ($ignore) { last; } ### keep going until hit first ignored order
			$ask_hi = &max($ask_hi, $price);
			$ask_qty += $vol;
			#$text .= "  ask ".&comma($price)." x $vol$eol";
		}
		$text.= "  ask ".&comma($ask_hi)." x $ask_qty$eol"; ### highest profitable ask price

		#$text.= "  ---$eol";

		### Bids
		my $bid_lo;
		my $bid_qty = 0;
		foreach my $bid (@{$Data{$r}{$i}{Bids}}) {
			my ($price, $vol, $ignore, $when) = split(':', $bid);
			if (! $bid_lo) { $bid_lo = $price; }
			if ($ignore) { last; } ### keep going until hit first ignored order
			$bid_lo = &min($bid_lo, $price);
			$bid_qty += $vol;
			#$text .= "  bid ".&comma($price)." x $vol$eol";
		}
		$text.= "  bid ".&comma($bid_lo)." x $bid_qty$eol"; ### lowest profitable bid price
	}
	
	copy2clipboard($text);
}

sub items_size {
	my ($id) = @_;
	if (not exists $items_size{$id}) {
		print &time2s." >>> undefined item ID $id\n";
		exit;
	}
	return $items_size{$id};
}

sub import_item_db {
	print &time2s()." import_item_db()\n";
	my $username = "dev";
	my $password = "BNxJYjXbYXQHAvFM";
	my $db_params = "DBI:mysql:database=evesdd;host=127.0.0.1;port=3306";
	my $dbh = DBI->connect($db_params, $username, $password);

	my $sth = $dbh->prepare("SELECT typeID, typeName, volume FROM invtypes");
	$sth->execute();
	while (my $ref = $sth->fetchrow_hashref()) {
		#print "mysql import ITEMS: id=$ref->{'typeID'}, name=$ref->{'typeName'}, size=$ref->{'volume'}\n";

		my $id =   $ref->{'typeID'};
		my $name = $ref->{'typeName'};
		my $size = $ref->{'volume'};
		$items_name{$id} = $name;
		$items_size{$id} = $size;
		$items_id{$name} = $id;
	}
	$sth->finish();
	$dbh->disconnect();
}

### import evecentral data from skynet file to Data[] (via Bids/Asks + kludge)
sub import_from_server {
	print &time2s()." import_from_server()\n";

	### reset
	%Bids = ();
	%Asks = ();
	my %kludge = ();

	my $FH;
	if(not open($FH, '<:crlf', $cargo_filename)) {
		print &time2s()." import_from_server(): no cargo file \"$cargo_filename\"\n";
		return;
	}

	### workaround: wait until cargo file is ready
	while (not open($FH, '<:crlf', $cargo_filename)) {
		print &time2s()."fopen() \"$cargo_filename\" failed\n";
		sleep 1;
	}
	flock($FH, LOCK_SH);
	my $latest = 0;
	
	### populate Bids/Asks[] from cargo_filename
	while (<$FH>) {
		### FORMAT for market_db
		my ($where, $id, $bidask, $price, $vol, $rem, $when, $other_loc) = split(':'); chomp $other_loc;
		my ($from, $to) = ($bidask eq 'ask') ? ($where, $other_loc) : ($other_loc, $where);
		my $r = &locs2r($from, $to);
		$latest = &max($latest, $when);

		### if item_id is not in DB, this isn't going to work (skip)
		if (! $items_name{$id}) { next; }

		### initialize hashes
		if (! $Bids{$where})    {$Bids{$where}   = ();}
		if (! $Asks{$where})    {$Asks{$where}   = ();}
		if (! $kludge{$where})  {$kludge{$where} = ();}

		my $t = "";
		$t .= $items_name{$id}." ";
		$t .= $bidask." ";
		$t .= "\$".&comma($price)." ";
		$t .= "x $vol ";
		$t .= &ago($when)." ";
		$t .= &where2s($where);
		#print $t."\n";

		my $flag_ignore = 0;
		### construct order
		my $tuple = join(':', ($price, $vol, $flag_ignore, $when, 'evecentral'));
		if ($bidask eq 'ask') {
			push(@{$Asks{$where}{$id}}, $tuple);
		} else {
			push(@{$Bids{$where}{$id}}, $tuple);
			$kludge{$where}{$id} = $other_loc;
		}
	}
	close $FH;

	### populate Data[] from Bids/Asks
	### sort bids/asks by route + item
	my $when = $latest;
	foreach my $bid_loc (keys %kludge) {
		
		foreach my $id (keys %{$kludge{$bid_loc}}) {
			my $ask_loc = $kludge{$bid_loc}{$id};
			### bid_loc, ask_loc : station longname
			
		
			### check alternate sources
			foreach my $from_stn (values %Hubs) {
				if ($from_stn eq $bid_loc) { next; }
				my $r = &locs2r($from_stn, $bid_loc);

				### import route parameters from evecentral
				if (! $Data{$r}{$id} ) {
					$Data{$r}{$id}{From} = $ask_loc;
					$Data{$r}{$id}{To} = $bid_loc;
					$Data{$r}{$id}{Route} = $r;
					$Data{$r}{$id}{Item} = $id;
					$Data{$r}{$id}{Ignore} = $Ignore{$r.$Sep.$id};
					$Data{$r}{$id}{Bids} = ();
					$Data{$r}{$id}{Bids_Reliable} = 0;
					$Data{$r}{$id}{Bids_Age} = 0;
					$Data{$r}{$id}{Asks} = ();
					$Data{$r}{$id}{Asks_Reliable} = 0;
					$Data{$r}{$id}{Asks_Age} = 0;
				}
			}

			### check alternate destinations
			foreach my $to_stn (values %Hubs) {
				if ($to_stn eq $ask_loc) { next; }
				my $r = &locs2r($ask_loc, $to_stn);

				### add $Data[] placeholders for each route (this triggers evecentral queries)
				if (! $Data{$r}{$id} ) {
					$Data{$r}{$id}{From} = $ask_loc;
					$Data{$r}{$id}{To} = $bid_loc;
					$Data{$r}{$id}{Route} = $r;
					$Data{$r}{$id}{Item} = $id;
					$Data{$r}{$id}{Ignore} = $Ignore{$r.$Sep.$id};
					$Data{$r}{$id}{Bids} = ();
					$Data{$r}{$id}{Bids_Reliable} = 0;
					$Data{$r}{$id}{Bids_Age} = 0;
					$Data{$r}{$id}{Asks} = ();
					$Data{$r}{$id}{Asks_Reliable} = 0;
					$Data{$r}{$id}{Asks_Age} = 0;
				}
			}
		

			### do NOT import detailed order data from evecentral
			#if (! $Data{$r}{$id}{Bids}) {
			#	#print ">>> adding server bids ($Data{$r}{$id}{Route} :: ".$items_name{$Data{$r}{$id}{Item}}.")\n";
			#	$Data{$r}{$id}{Bids} = ();
			#	$Data{$r}{$id}{Bids_Reliable} = 0;
			#	foreach my $bid (@{$Bids{$bid_loc}{$id}}) {
			#		if (&dup_order(\@{$Data{$r}{$id}{Bids}}, $bid)) { next; }
			#		push (@{$Data{$r}{$id}{Bids}}, $bid);
			#	}
			#} else { 
			#	#print ">>> ignoring server bids for $items_name{$id} \[$r\]\n"; 
			#}
			### import orders from evecentral, unless we already have order data 
			#if (! $Data{$r}{$id}{Asks}) {
			#	#print ">>> adding server bids ($Data{$r}{$id}{Route} :: ".$items_name{$Data{$r}{$id}{Item}}.")\n";
			#	$Data{$r}{$id}{Asks} = ();
			#	$Data{$r}{$id}{Asks_Reliable} = 0;
			#	foreach my $ask (@{$Asks{$ask_loc}{$id}}) {
			#		if (&dup_order(\@{$Data{$r}{$id}{Asks}}, $ask)) { next; }
			#		push (@{$Data{$r}{$id}{Asks}}, $ask);
			#	}
			#} else { 
			#	#print ">>> ignoring server asks for $items_name{$id} \[$r\]\n"; 
			#}
		}
	}
	#print &time2s()." import_cargo_lists()\n";
}

sub dup_order {
	my ($array_ref, $order) = @_;
	my @orders = @{$array_ref};
	foreach my $x (@orders) {
		if ($x eq $order) { return 1;}
	}
	return 0;
}

my $Redraw = 0;
my %empty_game_files = ();

### maps file name => item name
### file transform rules
###   '"' => ''
###   '/' => '_'
###   ':' => '_'
my %item_fname2iname = (
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
### time format for Marketlog filename: "Region-Item-2015.12.06 033516"
sub fname2time {
	my ($fname) = @_;
	### NOTE: $+{region} may or may not include directory path (bc we don't know if full filename was provided)
	$fname =~ /(?<region>[^-]+?)-(?<item>.*)-(?<yr>[0-9]{4})\.(?<mo>[0-9][0-9])\.(?<dy>[0-9][0-9]) (?<hh>[0-9][0-9])(?<mm>[0-9][0-9])(?<ss>[0-9][0-9])\.txt$/;
	my ($yr, $mo, $dy, $hh, $mm, $ss) = ($+{yr}, $+{mo}, $+{dy}, $+{hh}, $+{mm}, $+{ss}); 
	my $fnameTime = timegm($ss, $mm, $hh, $dy, $mo-1, $yr-1900, 0);
	return $fnameTime;
}
### time format for Marketlog row: "2015-12-03 20:44:26.000"
sub issuedate2time {
	my ($issueDate) = @_;
	my ($yr,$mo,$dy,$hh,$mm,$ss,$ms) = split(/[\s.:-]+/, $issueDate);
	my $issueTime = timegm($ss, $mm, $hh, $dy, $mo-1, $yr-1900, 0);
	return $issueTime;
}
sub line2time {
	my ($row) = @_;
	my ($price2, $volRemaining, $typeID, $range, $orderID, $volEntered, $minVolume, $isBid, $issueDate, $duration, $stationID, $regionID, $systemID, $jumps, undef) = split(',', $row);
	return issuedate2time($issueDate);
}

sub export_my_data {
	#print &time2s()." export_my_data()\n";
	my $FH;
	open($FH, '>:crlf', $my_data_filename);
	flock($FH, LOCK_EX);
	
	foreach my $r (keys %Data) {
		foreach my $i (keys %{$Data{$r}}) {
			foreach my $x (@{$Data{$r}{$i}{Asks}}) {
				my $bidask = 'ask';
				my ($price, $vol, $flag_ignore, $modtime, $orderID) = split(':', $x);
				my $flag_reliable = $Data{$r}{$i}{Asks_Reliable};

				my $line = join(':', $r, $i, $bidask, $price, $vol, $flag_ignore, $modtime, $flag_reliable, $orderID);
				print $FH $line."\n";
			}
			foreach my $x (@{$Data{$r}{$i}{Bids}}) {
				my $bidask = 'bid';
				my ($price, $vol, $flag_ignore, $modtime, $orderID) = split(':', $x);
				my $flag_reliable = $Data{$r}{$i}{Bids_Reliable};

				my $line = join(':', $r, $i, $bidask, $price, $vol, $flag_ignore, $modtime, $flag_reliable, $orderID);
				print $FH $line."\n";
			}
		}
	}
	close $FH;
}


### import_my_data()
### stomps Data[]
sub import_my_data {
	my $FH;
	if (open($FH, '<:crlf', $my_data_filename)) {
		flock($FH, LOCK_SH);

		%Data = ();

		while (<$FH>) {
			chomp;
			my ($r, $i, $bidask, $price, $vol, $flag_ignore, $modtime, $flag_reliable, $orderID) = split(':');

			if (time - $modtime > $age_expire_web) { next; }

			### init
			if (! $Data{$r}) { $Data{$r} = (); }
			if (! $Data{$r}{$i}) { 
				$Data{$r}{$i}{Route} = $r;
				$Data{$r}{$i}{Item} = $i;
				my ($ask_loc, $bid_loc) = &route2stns ($r);
				$Data{$r}{$i}{From} = $ask_loc;
				$Data{$r}{$i}{To} = $bid_loc;
				$Data{$r}{$i}{Ignore} = 0;
				$Data{$r}{$i}{Asks} = ();
				$Data{$r}{$i}{Asks_Age} = 0;
				$Data{$r}{$i}{Asks_Reliable} = 0;
				$Data{$r}{$i}{Bids} = ();
				$Data{$r}{$i}{Bids_Age} = 0;
				$Data{$r}{$i}{Bids_Reliable} = 0;
			}

			### populate bid/ask order
			### construct order
			my $x = join(':', $price, $vol, $flag_ignore, $modtime, $orderID);
			if ($bidask eq 'ask') {
				push (@{$Data{$r}{$i}{Asks}}, $x);
				$Data{$r}{$i}{Asks_Age} = &max($Data{$r}{$i}{Asks_Age}, $modtime);
				$Data{$r}{$i}{Asks_Reliable} = $flag_reliable;	
			} else {
				push (@{$Data{$r}{$i}{Bids}}, $x);
				$Data{$r}{$i}{Bids_Age} = &max($Data{$r}{$i}{Bids_Age}, $modtime);
				$Data{$r}{$i}{Bids_Reliable} = $flag_reliable;
			}
		}
		close $FH;
	}
}

use Digest::MD5 qw(md5_hex);
sub checksum_new {
	return Digest::MD5->new;
}
sub checksum_add {
	my ($hh, $str) = @_;
	$hh->add($str);
}
sub checksum_out {
	my ($hh, $digitsHex) = @_;
	$digitsHex = 4 if not defined $digitsHex;
	my $hexMod = 0x10 ** $digitsHex;

	my $hh2 = $hh->clone;			### clone handle
	my $hexStr = $hh2->hexdigest;		### 128 bit hex string (destroys handle)
	my $hexStrShort = substr($hexStr, -8); 	### truncate to 32 bit hex string
	my $hexNum = hex($hexStrShort); 	### convert to numeric
	my $hexTiny = $hexNum % $hexMod;	### truncate to X hex digits
	my $fmt = "0x%0".$digitsHex."x";
	my $out = sprintf($fmt, $hexTiny);  	### convert to string
	return $out;
}


sub match_until_size {
	my ($r, $id, $max) = @_;
	
	### reset subtotals
	$Data{$r}{$id}{Profit} = 0;
	$Data{$r}{$id}{Cost} = 0;
	$Data{$r}{$id}{Qty} = 0;			
	$Data{$r}{$id}{Size} = 0;
	$Data{$r}{$id}{ROI} = 0; 
	$Data{$r}{$id}{ProfitPerSize} = 0;
	$Data{$r}{$id}{Age} = 0;
	$Data{$r}{$id}{Checksum} = &checksum_new; 

	if (!$Data{$r}{$id}{Asks_Reliable}) { $Data{$r}{$id}{Asks_Age} = 0; }
	if (!$Data{$r}{$id}{Bids_Reliable}) { $Data{$r}{$id}{Bids_Age} = 0; }

	### match bids/asks
	my $ask_loc = $Data{$r}{$id}{From};
	my $bid_loc = $Data{$r}{$id}{To};
	my $n_bids = scalar(@{$Data{$r}{$id}{Bids}});
	my $n_asks = scalar(@{$Data{$r}{$id}{Asks}});
	my $i_bid = 0;
	my $i_ask = 0;
	my $last_i_bid = -1;
	my $last_i_ask = -1;
	my $last_bid_rem = 0;
	my $last_ask_rem = 0;
	my $Eject = 0;
	
	### TODO: sort Bids + Asks
	 
	### find profitable order matches
	while (($i_bid < $n_bids) && ($i_ask < $n_asks)) {
		my $bid = $Data{$r}{$id}{Bids}[$i_bid];
		my $ask = $Data{$r}{$id}{Asks}[$i_ask];
		my ($bid_price, $bid_vol, $bid_flag, $bid_when) = split(':', $bid);
		my ($ask_price, $ask_vol, $ask_flag, $ask_when) = split(':', $ask);

		### "age" = time of most profitable order (i==0)
		if ($i_ask == 0) { $Data{$r}{$id}{Asks_Age} = $ask_when; }
		if ($i_bid == 0) { $Data{$r}{$id}{Bids_Age} = $bid_when; }

		### order-level: check profit per size
		### this also flags unprofitables
		my $profit = (($Net_tax * $bid_price) - $ask_price);
		my $profit_per_vol = $profit / &items_size($id);
		if ($profit_per_vol < $minProfitPerSize) {
			last; ### skip
		}

		### carryover remainder qty
		if ($i_bid == $last_i_bid) { $bid_vol = $last_bid_rem; }
		if ($i_ask == $last_i_ask) { $ask_vol = $last_ask_rem; }
		$last_i_bid = $i_bid;
		$last_i_ask = $i_ask;
		my $qty = &min($bid_vol, $ask_vol);
		$last_bid_rem = $bid_vol - $qty;
		$last_ask_rem = $ask_vol - $qty;
		### ptr increment
		if ($last_bid_rem == 0) { $i_bid++; }
		if ($last_ask_rem == 0) { $i_ask++; }
		$N_orders++;

		### aggregate item data
		$Data{$r}{$id}{Profit} += $qty * (($Net_tax * $bid_price) - $ask_price);
		$Data{$r}{$id}{Cost} += $qty * $ask_price;
		$Data{$r}{$id}{Qty} += $qty;
		$Data{$r}{$id}{Size} += $qty * &items_size($id);
		$Data{$r}{$id}{ROI} = $Data{$r}{$id}{Profit}/$Data{$r}{$id}{Cost};
		#$Data{$r}{$id}{Asks_Age} = &max($Data{$r}{$id}{Asks_Age}, $ask_when);
		#$Data{$r}{$id}{Bids_Age} = &max($Data{$r}{$id}{Bids_Age}, $bid_when);
		
		### hash string format
		my $tradeStr = "$r, $id, $qty, $ask_price, $bid_price";
		&checksum_add($Data{$r}{$id}{Checksum}, $tradeStr);
		&checksum_add($Totals{$r}{Checksum}, $tradeStr);
	}
	### loop exits on (a) first unprofitable match or (b) ran out of bids or asks
	### if last order was partially consumed, skip to next
	if ($last_bid_rem != 0) { $i_bid++; }
	if ($last_ask_rem != 0) { $i_ask++; }
	### last profitable match is Bid[$i_bid-1], Ask[$i_ask-1]


	### Filter: below profitability threshold, delete item
	### item-level: check total profit
	### this should catch the scenario of zero matches
	if ($Data{$r}{$id}{Profit} < $minProfit) {
		#print &time2s." >>> skipping $r :: ".$items_name{$id}." (profit=".$Data{$r}{$id}{Profit}.")\n";
		delete $Data{$r}{$id};
		next;
	}


	### filter unmatched asks for unprofitables
	### Asks[] is sorted by decreasing profitability
	if ($i_ask < $n_asks) {
		my $i_bid_last = $i_bid - 1;
		my $bid = $Data{$r}{$id}{Bids}[$i_bid_last]; ### last profitable bid
		my ($bid_price, $bid_vol, $bid_flag, $bid_when) = split(':', $bid);
		foreach my $i ($i_ask..$n_asks-1) { 
			my $ask = $Data{$r}{$id}{Asks}[$i];
			my ($ask_price, $ask_vol, $ask_flag, $ask_when) = split(':', $ask);
			my $profit_per_vol = (($Net_tax * $bid_price) - $ask_price) / &items_size($id);
			### find first unprofitable order, then ignore all
			if ($profit_per_vol < $minProfitPerSize) {
				#print "ignoring ".($n_asks-$i)." asks $items_name{$id} [$r]\n";
				### ignore all remaining orders
				for my $i2 ($i..$n_asks-1) {
					### set ignore flag
					my $ask3 = $Data{$r}{$id}{Asks}[$i2];
					my ($ask3_price, $ask3_vol, $ask3_flag, $ask3_when, $orderID) = split(':', $ask3);
					$ask3_flag = 1; ### set to ignore
					$ask3 = join(':', $ask3_price, $ask3_vol, $ask3_flag, $ask3_when, $orderID);
					$Data{$r}{$id}{Asks}[$i2] = $ask3;
				}
				last;
			}
		}
	}
	### filter unmatched bids for unprofitables
	### Bids[] is sorted by decreasing profitability
	if ($i_bid < $n_bids) {
		my $i_ask_last = $i_ask - 1;
		my $ask = $Data{$r}{$id}{Asks}[$i_ask_last]; ### last profitable ask
		my ($ask_price, $ask_vol, $ask_flag, $ask_when) = split(':', $ask);
		foreach my $i ($i_bid..$n_bids-1) { 
			my $bid = $Data{$r}{$id}{Bids}[$i];
			my ($bid_price, $bid_vol, $bid_flag, $bid_when) = split(':', $bid);
			my $profit_per_vol = (($Net_tax * $bid_price) - $ask_price) / &items_size($id);
			### find first unprofitable order, then ignore all
			if ($profit_per_vol < $minProfitPerSize) {
				#print "ignoring ".($n_bids-$i)." bids $items_name{$id} [$r]\n";
				for my $i2 ($i..$n_bids-1) {
					my $bid3 = $Data{$r}{$id}{Bids}[$i2];
					my ($bid3_price, $bid3_vol, $bid3_flag, $bid3_when, $orderID) = split(':', $bid3);
					$bid3_flag = 1; ### set to ignore
					$bid3 = join(':', $bid3_price, $bid3_vol, $bid3_flag, $bid3_when, $orderID);
					$Data{$r}{$id}{Bids}[$i2] = $bid3;
				}
				last;
			}
		}
	}
}

### recalc(): calculate subtotals by item + route
### IN: Data[]
### OUT: Data[] + Totals[]
my %Tags = ();
my $GrandTotal = 0;
sub recalc {
	print &time2s()." recalc()\n";
	
	foreach my $r (@Routes) {
		### reset subtotals
		$Totals{$r}{Profit} = 0;
		$Totals{$r}{Cost} = 0;
		$Totals{$r}{Size} = 0;
		$Totals{$r}{Age} = 0;
		$Totals{$r}{Checksum} = &checksum_new;
	}

	$GrandTotal = 0;
	$N_items = 0;
	$N_orders = 0;
	### each route (pair: from -> to)
	foreach my $r (keys %Data) {
		### each item
		foreach my $id (keys %{$Data{$r}}) {
			$N_items++;
			if (! $Data{$r}{$id}{Bids} || ! $Data{$r}{$id}{Asks} ) {
				delete $Data{$r}{$id};
				next;
			}

			### reset subtotals
			$Data{$r}{$id}{Profit} = 0;
			$Data{$r}{$id}{Cost} = 0;
			$Data{$r}{$id}{Qty} = 0;			
			$Data{$r}{$id}{Size} = 0;
			$Data{$r}{$id}{ROI} = 0; 
			$Data{$r}{$id}{ProfitPerSize} = 0;
			$Data{$r}{$id}{Age} = 0;
			$Data{$r}{$id}{Checksum} = &checksum_new; 

			if (!$Data{$r}{$id}{Asks_Reliable}) { $Data{$r}{$id}{Asks_Age} = 0; }
			if (!$Data{$r}{$id}{Bids_Reliable}) { $Data{$r}{$id}{Bids_Age} = 0; }

			### match bids/asks
			my $ask_loc = $Data{$r}{$id}{From};
			my $bid_loc = $Data{$r}{$id}{To};
			my $n_bids = scalar(@{$Data{$r}{$id}{Bids}});
			my $n_asks = scalar(@{$Data{$r}{$id}{Asks}});
			my $i_bid = 0;
			my $i_ask = 0;
			my $last_i_bid = -1;
			my $last_i_ask = -1;
			my $last_bid_rem = 0;
			my $last_ask_rem = 0;
			my $Eject = 0;
			
			### TODO: sort Bids + Asks
			 
			### find profitable order matches
			while (($i_bid < $n_bids) && ($i_ask < $n_asks)) {
				my $bid = $Data{$r}{$id}{Bids}[$i_bid];
				my $ask = $Data{$r}{$id}{Asks}[$i_ask];
				my ($bid_price, $bid_vol, $bid_flag, $bid_when) = split(':', $bid);
				my ($ask_price, $ask_vol, $ask_flag, $ask_when) = split(':', $ask);

				### "age" = time of most profitable order (i==0)
				if ($i_ask == 0) { $Data{$r}{$id}{Asks_Age} = $ask_when; }
				if ($i_bid == 0) { $Data{$r}{$id}{Bids_Age} = $bid_when; }
		
				### order-level: check profit per size
				### this also flags unprofitables
				my $profit = (($Net_tax * $bid_price) - $ask_price);
				my $profit_per_vol = $profit / &items_size($id);
				if ($profit_per_vol < $minProfitPerSize) {
					last; ### skip
				}

				### carryover remainder qty
				if ($i_bid == $last_i_bid) { $bid_vol = $last_bid_rem; }
				if ($i_ask == $last_i_ask) { $ask_vol = $last_ask_rem; }
				$last_i_bid = $i_bid;
				$last_i_ask = $i_ask;
				my $qty = &min($bid_vol, $ask_vol);
				$last_bid_rem = $bid_vol - $qty;
				$last_ask_rem = $ask_vol - $qty;
				### ptr increment
				if ($last_bid_rem == 0) { $i_bid++; }
				if ($last_ask_rem == 0) { $i_ask++; }
				$N_orders++;
		
				### aggregate item data
				$Data{$r}{$id}{Profit} += $qty * (($Net_tax * $bid_price) - $ask_price);
				$Data{$r}{$id}{Cost} += $qty * $ask_price;
				$Data{$r}{$id}{Qty} += $qty;
				$Data{$r}{$id}{Size} += $qty * &items_size($id);
				$Data{$r}{$id}{ROI} = $Data{$r}{$id}{Profit}/$Data{$r}{$id}{Cost};
				#$Data{$r}{$id}{Asks_Age} = &max($Data{$r}{$id}{Asks_Age}, $ask_when);
				#$Data{$r}{$id}{Bids_Age} = &max($Data{$r}{$id}{Bids_Age}, $bid_when);
				
				### hash string format
				my $tradeStr = "$r, $id, $qty, $ask_price, $bid_price";
				&checksum_add($Data{$r}{$id}{Checksum}, $tradeStr);
				&checksum_add($Totals{$r}{Checksum}, $tradeStr);
			}
			### loop exits on (a) first unprofitable match or (b) ran out of bids or asks
			### if last order was partially consumed, skip to next
			if ($last_bid_rem != 0) { $i_bid++; }
			if ($last_ask_rem != 0) { $i_ask++; }
			### last profitable match is Bid[$i_bid-1], Ask[$i_ask-1]


			### Filter: below profitability threshold, delete item
			### item-level: check total profit
			### this should catch the scenario of zero matches
			if ($Data{$r}{$id}{Profit} < $minProfit) {
				#print &time2s." >>> skipping $r :: ".$items_name{$id}." (profit=".$Data{$r}{$id}{Profit}.")\n";
				delete $Data{$r}{$id};
				next;
			}


			### filter unmatched asks for unprofitables
			### Asks[] is sorted by decreasing profitability
			if ($i_ask < $n_asks) {
				my $i_bid_last = $i_bid - 1;
				my $bid = $Data{$r}{$id}{Bids}[$i_bid_last]; ### last profitable bid
				my ($bid_price, $bid_vol, $bid_flag, $bid_when) = split(':', $bid);
				foreach my $i ($i_ask..$n_asks-1) { 
					my $ask = $Data{$r}{$id}{Asks}[$i];
					my ($ask_price, $ask_vol, $ask_flag, $ask_when) = split(':', $ask);
					my $profit_per_vol = (($Net_tax * $bid_price) - $ask_price) / &items_size($id);
					### find first unprofitable order, then ignore all
					if ($profit_per_vol < $minProfitPerSize) {
						#print "ignoring ".($n_asks-$i)." asks $items_name{$id} [$r]\n";
						### ignore all remaining orders
						for my $i2 ($i..$n_asks-1) {
							### set ignore flag
							my $ask3 = $Data{$r}{$id}{Asks}[$i2];
							my ($ask3_price, $ask3_vol, $ask3_flag, $ask3_when, $orderID) = split(':', $ask3);
							$ask3_flag = 1; ### set to ignore
							$ask3 = join(':', $ask3_price, $ask3_vol, $ask3_flag, $ask3_when, $orderID);
							$Data{$r}{$id}{Asks}[$i2] = $ask3;
						}
						last;
					}
				}
			}
			### filter unmatched bids for unprofitables
			### Bids[] is sorted by decreasing profitability
			if ($i_bid < $n_bids) {
				my $i_ask_last = $i_ask - 1;
				my $ask = $Data{$r}{$id}{Asks}[$i_ask_last]; ### last profitable ask
				my ($ask_price, $ask_vol, $ask_flag, $ask_when) = split(':', $ask);
				foreach my $i ($i_bid..$n_bids-1) { 
					my $bid = $Data{$r}{$id}{Bids}[$i];
					my ($bid_price, $bid_vol, $bid_flag, $bid_when) = split(':', $bid);
					my $profit_per_vol = (($Net_tax * $bid_price) - $ask_price) / &items_size($id);
					### find first unprofitable order, then ignore all
					if ($profit_per_vol < $minProfitPerSize) {
						#print "ignoring ".($n_bids-$i)." bids $items_name{$id} [$r]\n";
						for my $i2 ($i..$n_bids-1) {
							my $bid3 = $Data{$r}{$id}{Bids}[$i2];
							my ($bid3_price, $bid3_vol, $bid3_flag, $bid3_when, $orderID) = split(':', $bid3);
							$bid3_flag = 1; ### set to ignore
							$bid3 = join(':', $bid3_price, $bid3_vol, $bid3_flag, $bid3_when, $orderID);
							$Data{$r}{$id}{Bids}[$i2] = $bid3;
						}
						last;
					}
				}
			}


			### ignore certain items (scams, illegal, etc.)
			&filter_ignore($r, $id);


			### aggregate data 
			$Data{$r}{$id}{ProfitPerSize} = $Data{$r}{$id}{Profit} / $Data{$r}{$id}{Size};
			$Data{$r}{$id}{Age} = &max($Data{$r}{$id}{Asks_Age}, $Data{$r}{$id}{Bids_Age});
			if (! $Data{$r}{$id}{Ignore}) {
				$Totals{$r}{Profit} += $Data{$r}{$id}{Profit};
				$Totals{$r}{Cost} += $Data{$r}{$id}{Cost};
				$Totals{$r}{Size} += $Data{$r}{$id}{Size};
				$Totals{$r}{Age} = &max($Totals{$r}{Age}, $Data{$r}{$id}{Age});
			}

			### check for for high-value opportunities
			&notify_check($r, $id);
		
		} # end item loop

		### adjust if over volume
		if ($Totals{$r}{Size} > 8967.0) {
			
		}

		$GrandTotal += $Totals{$r}{Profit};
	} # end route loop

	&notify_refresh();
}

sub color_item {
	my ($r, $i) = @_;
	my $p_item = $r.$Sep.$i;
	
	### ignore -> grey
	### confirmed -> green
	### 1/2 confirmed -> yellow
	### unconfirmed -> red
	if ($Data{$r}{$i}{Ignore}) { 
		change_color($p_item, $color_ig);
	} elsif ($p_item eq $p_cycle) {
		change_color($p_item, $color_brightred);
	} else {
		change_color($p_item, $color_green);
	}
}

my %items_scam = (
	"Cormack's Modified Armor Thermic Hardener" => 1,
	"Draclira's Modified EM Plating" => 1,
	"Gotan's Modified EM Plating" => 1,
	"Tobias' Modified EM Ward Amplifier" => 1,
	"Ahremen's Modified Explosive Plating" => 1,
	"Setele's Modified Explosive Plating" => 1,
	"Raysere's Modified Mega Beam Laser" => 1,
);
sub filter_ignore {
	my ($r, $id) = @_;
	my $p = $r.$Sep.$id;

	my $bid0 = $Data{$r}{$id}{Bids}[0];
	my ($bid_price0, $bid_vol0, $bid_rem0, $bid_when0) = split(':', $bid0);
	my $ask0 = $Data{$r}{$id}{Asks}[0];
	my ($ask_price0, $ask_vol0, $ask_rem0, $ask_when0) = split(':', $ask0);
	my ($ask_loc, $bid_loc) = &route2stns($r);
	
	
	### Scenario 4: illegal
	if ($items_name{$id} =~ /^(Improved|Standard|Strong) .* Booster$/) { 
		&ignore_item($p); 
		return;
	}
			
	### Scam 1: profit > $1B
	if ((($bid_price0-$ask_price0) > 1000000000) && $items_scam{$items_name{$id}}) {
=debug
		print ">>> potential scam".
			" $items_name{$id}".
			"\n".
			"  profit ".sprintf("%.1f", ($bid_price0-$ask_price0)/1000000.0)."M".
			"\n".
			"  ask ".sprintf("%i", ($ask_price0/1000000.0))."M ".&where2s($ask_loc).
			"\n".
			"  bid ".sprintf("%i", ($bid_price0/1000000.0))."M ".&where2s($bid_loc).
			"\n";
=cut
		&ignore_item($p);
		return;
	}

	### Scam 2: profit > $29M, cost > $190M
	if (($bid_price0-$ask_price0) > 29*1000000 && $ask_price0 > 190*1000000) {
=debug
		print ">>> potential scam".
			" $items_name{$id}".
			"\n".
			"  profit ".sprintf("%.1f", ($bid_price0-$ask_price0)/1000000.0)."M".
			"\n".
			"  ask ".sprintf("%i", ($ask_price0/1000000.0))."M ".&where2s($ask_loc).
			"\n".
			"  bid ".sprintf("%i", ($bid_price0/1000000.0))."M ".&where2s($bid_loc).
			"\n";
=cut
		&ignore_item($p);
		return;
	}
}

### redraw(): reset + populate main widget
### IN: Data[], Totals[]
### OUT: $w1
sub repop {
	print &time2s()." repop()\n";

	### reset tree
	$w1->delete('all');
	
	### each Route
	foreach my $r (@Routes) {

		### UI line: Route
		my $p_route = $r;	
		#print "add route $p_route\n";
		$w1->add($p_route, -text => $Pre.$r.$Post, @opts_top_l);
		#$w1->itemCreate($p_route, $col_profit, -text => $Pre.'+'.&iski2s($Totals{$r}{Profit}).$Post, @opts_top_r); 
		$w1->itemCreate($p_route, $col_profit, -text => $Pre.&iski2s($Totals{$r}{Profit}).$Post, @opts_top_r); 
		$w1->itemCreate($p_route, $col_cost, -text => $Pre.'-'.&iski2s($Totals{$r}{Cost}).$Post, @opts_top_r); 
		$w1->itemCreate($p_route, $col_size, -text => $Pre.&commai(int($Totals{$r}{Size}))." m3".$Post, @opts_top_r); 
		$w1->itemCreate($p_route, $col_age, -text => $Pre.($Totals{$r}{Age} ? &age2s($Totals{$r}{Age}) : "---").$Post, @opts_top_r); 

		$w1->itemCreate($p_route, $col_qty, -text => " ", @opts_top_r); 
		$w1->itemCreate($p_route, $col_roi, -text => " ", @opts_top_r); 
		$w1->itemCreate($p_route, $col_pps, -text => " ", @opts_top_r); 

		### Filter 1: grey out zero profit
		if ($Totals{$r}{Profit} == 0) {
			&change_color($p_route, $color_ig);
		}

=begin
		### Filter 2: show route Volume (m3) as progress bar
		my $size_pct = ($Totals{$r}{Size} / 8967.0) * 100.0;
		my $wpb1 = $w1->ProgressBar(
			-anchor => 'w',
			-troughcolor => '#191919',
			-from => 0, 
			-to => 100, 
			-gap => 0,
			-colors => [0, 'green', 48, 'yellow', 61, 'orange', 78, 'red'],
			-value => $size_pct,
		);
		$w1->itemCreate($p_route, $col_size, -itemtype => 'window', -widget => $wpb1); 
		my $pbstyle = $w1->ItemStyle('window', -anchor => 'n', '-padx' => 2, '-pady' => 3);
		$w1->itemConfigure($p_route, $col_size, '-style' => $pbstyle);
		$w1->columnWidth($col_size, -char => 10); ### this works
=cut

		### Filter 3: change Cost to red if over threshold
		if ($Totals{$r}{Cost} > 7_000_000_000) { 
			&change_color_cell($p_route, $col_cost, $color_red); 
		}

		### Filter 4: change Profit color if over threshold
		if ($Totals{$r}{Profit} > 100_000_000) { 
			&change_color_cell($p_route, $col_profit, $color_orange); 
		} elsif ($Totals{$r}{Profit} > 50_000_000) { 
			&change_color_cell($p_route, $col_profit, $color_purple); 
		}

		### Filter 5: change Volume color if over threshold
		if ($Totals{$r}{Size} > 8967) { 
			&change_color_cell($p_route, $col_size, $color_red); 
		}


		### each Item
		my @items_sorted = &repop_sort($r);
		my $n_items = (0+@items_sorted);
		foreach my $i (@items_sorted) {

			### Scenario 3: if bids/asks is empty or zero profit, skip item
			if ( (0+@{$Data{$r}{$i}{Bids}}) == 0 || 
			     (0+@{$Data{$r}{$i}{Asks}}) == 0 ||
			     $Data{$r}{$i}{Profit} == 0
			   ) 
			{ $n_items--; next; }

			### UI line: Item
			my $p_item = $r.$Sep.$i;
			my $iname = $items_name{$i};
			if ($p_item eq $p_cycle) { $iname = ">>> ".$iname; }
			#print "add item $r.$items_name{$i}\n";
			my @o_l = @opts_l; # NOTE: color_item() will override color (item)
			my @o_r = @opts_r; # NOTE: color_item() will override color (item)
			$w1->add($p_item, -text => $iname, @o_l);
			$w1->itemCreate($p_item, $col_profit, -text => '+'.&isk2s($Data{$r}{$i}{Profit}).$Post, @o_r); 
			$w1->itemCreate($p_item, $col_cost, -text => '-'.&iski2s($Data{$r}{$i}{Cost}).$Post, @o_r); 
			$w1->itemCreate($p_item, $col_qty, -text => &commai($Data{$r}{$i}{Qty})." x".$Post, @o_r); 
			$w1->itemCreate($p_item, $col_size, -text => &commai(int($Data{$r}{$i}{Size}))." m3".$Post, @o_r); 
			$w1->itemCreate($p_item, $col_age, -text => &age2s($Data{$r}{$i}{Age}).$Post, @o_r); 
			$w1->itemCreate($p_item, $col_roi, -text => sprintf("%.1f", $Data{$r}{$i}{ROI}*100.0)."\%".$Post, @o_r); 
			$w1->itemCreate($p_item, $col_pps, -text => sprintf("%.1f", $Data{$r}{$i}{ProfitPerSize}/1000.0)."K".$Post, @o_r); 
			$w1->hide('entry', $p_item);

			### set line color based on ignore/confirmed status (red/yellow/green/grey)
			&color_item($r, $i);
			
			### Color [ROI < 0.5%] red
			if ($Data{$r}{$i}{ROI} < 0.005) { 
				&change_color_cell($p_item, $col_roi, $color_red); 
			}
			### Color [ROI > 20%] purple
			if ($Data{$r}{$i}{ROI} > 0.20) { 
				&change_color_cell($p_item, $col_roi, $color_purple); 
			}
			### Color [Age > 1hr] yellow
			if (time - $Data{$r}{$i}{Age} > 3600) { 
				&change_color_cell($p_item, $col_age, $color_yellow); 
			}

			
			if (scalar(@{$Data{$r}{$i}{Bids}}) == 0) { warn ">>> empty Bids[] $r $i $items_name{$i}"; } ### sanity check
			if (scalar(@{$Data{$r}{$i}{Asks}}) == 0) { warn ">>> empty Asks[] $r $i $items_name{$i}"; } ### sanity check

			### UI line: Asks 
			my $n_ignores = 0;
			my $kIgnoresHideAfter = 3;
			foreach my $ask (@{$Data{$r}{$i}{Asks}}) {
				my ($price, $vol, $flag_ignore, $when, $orderID) = split(':', $ask);
				my $where = $Data{$r}{$i}{From};
				my $n = join(':', 'ask', $price, $vol, $when, $orderID);
				my $p = $r.$Sep.$i.$Sep.$n;
				#print "add ask $r.$items_name{$i}.$n  $price x $vol\n";

				### set line color
				my @o_l = @opts_l;
				my @o_r = @opts_r;
				if ($Data{$r}{$i}{Ignore} || $flag_ignore) {
					$n_ignores++;
					@o_l = @opts_ignore_l;
					@o_r = @opts_ignore_r;
				}
				### check for duplicate order
				if ($w1->infoExists($p)) {
					print(&time2s.">>> duplicate order: $p at ".&time2s($when)."\n");
					next;
				}
				
				if ($n_ignores == 0 or $n_ignores < $kIgnoresHideAfter+1) {
					$w1->add($p, -text => '');
					$w1->itemCreate($p, $col_route, -text => &where2s($where).$Post, @o_r); 
					$w1->itemCreate($p, $col_profit, -text => 'ask  '.$Post, @o_r); 
					$w1->itemCreate($p, $col_qty, -text => &commai($vol)." x".$Post, @o_r); 
					$w1->itemCreate($p, $col_cost, -text => &comma($price).$Post, @o_r); 
					$w1->itemCreate($p, $col_age, -text => &age2s($when).$Post, @o_r); 
					$w1->hide('entry', $p);
				} elsif ($n_ignores == $kIgnoresHideAfter+1) {
					$w1->add($p, -text => '');
					$w1->itemCreate($p, $col_route,  -text => '---'.$Post, @o_r); 
					$w1->itemCreate($p, $col_profit, -text => '---  '.$Post, @o_r); 
					$w1->itemCreate($p, $col_qty,    -text => '----'.$Post, @o_r); 
					$w1->itemCreate($p, $col_cost,   -text => '---'.$Post, @o_r); 
					$w1->itemCreate($p, $col_age,    -text => '---'.$Post, @o_r); 
					$w1->hide('entry', $p);
				} elsif ($n_ignores > $kIgnoresHideAfter+1) {
					### skip
				}					

			}

			### UI line: Bids
			$n_ignores = 0;
			foreach my $bid (@{$Data{$r}{$i}{Bids}}) {
				my ($price, $vol, $flag_ignore, $when, $orderID) = split(':', $bid);
				my $where = $Data{$r}{$i}{To};
				my $n = join(':', 'bid', $price, $vol, $when, $orderID);
				my $p = $r.$Sep.$i.$Sep.$n;
				#print "add bid $r.$items_name{$i}.$n  $price x $vol\n";

				### set line color
				my @o_l = @opts_l;
				my @o_r = @opts_r;
				if ($Data{$r}{$i}{Ignore} || $flag_ignore) {
					$n_ignores++;
					@o_l = @opts_ignore_l;
					@o_r = @opts_ignore_r;
				}
				### check for duplicate order
				if ($w1->infoExists($p)) {
					print(&time2s.">>> duplicate order: $p at ".&time2s($when)."\n");
					next;
				}

				if ($n_ignores == 0 or $n_ignores < $kIgnoresHideAfter+1) {
					$w1->add($p, -text => '');
					$w1->itemCreate($p, $col_route, -text => &where2s($where), @o_r); 
					$w1->itemCreate($p, $col_profit, -text => 'bid  '.$Post, @o_r); 
					$w1->itemCreate($p, $col_qty, -text => &commai($vol)." x".$Post, @o_r); 
					$w1->itemCreate($p, $col_cost, -text => &comma($price).$Post, @o_r); 
					$w1->itemCreate($p, $col_age, -text => &age2s($when).$Post, @o_r); 
					$w1->hide('entry', $p);
				} elsif ($n_ignores == $kIgnoresHideAfter+1) {
					$w1->add($p, -text => '');
					$w1->itemCreate($p, $col_route,  -text => '---'.$Post, @o_r); 
					$w1->itemCreate($p, $col_profit, -text => '---  '.$Post, @o_r); 
					$w1->itemCreate($p, $col_qty,    -text => '----'.$Post, @o_r); 
					$w1->itemCreate($p, $col_cost,   -text => '---'.$Post, @o_r); 
					$w1->itemCreate($p, $col_age,    -text => '---'.$Post, @o_r); 
					$w1->hide('entry', $p);
				} elsif ($n_ignores > $kIgnoresHideAfter+1) {
					### skip
				}
			}
		} ### end item
		
		### route row label (actual)
		### "Jitas -> Amarr   (4)  0xcdef"		
		my $id = &checksum_out($Totals{$r}{Checksum}, 3);
		$w1->itemConfigure($r, $col_route, -text => $Pre.$r."\t($n_items)   $id".$Post);
		
		### total line
		my $p = $r.$Sep."TOTAL";
		$w1->add($p, -text => 'TOTAL', @opts_top_r);
		$w1->itemCreate($p, $col_profit, -text => &iski2s($Totals{$r}{Profit}).$Post, @opts_top_r); 
		$w1->itemCreate($p, $col_cost,   -text => '-'.&iski2s($Totals{$r}{Cost}).$Post, @opts_top_r); 
		$w1->itemCreate($p, $col_size,   -text => &commai(int($Totals{$r}{Size}))."".$Post, @opts_top_r); 
		$w1->itemCreate($p, $col_age,    -text => ($Totals{$r}{Age} ? &age2s($Totals{$r}{Age}) : "---").$Post, @opts_top_r); 
		$w1->hide('entry', $p);			
	} ### end route

	$w1->add('TOTAL', -text => 'ALL ROUTES', @opts_top_r);
	$w1->itemCreate('TOTAL', $col_profit, -text => $Pre.'+'.&isk2s($GrandTotal).$Post, @opts_top_r); 
	
	### underline last route for grand total
	my $r_last = $Routes[-1];
	&underline_cell($r_last, $col_profit);

	#print "repop() exit\n";
}

sub repop_indicators {
	foreach my $r (@Routes) {
		foreach my $i (keys %{$Data{$r}}) {
			### hlist indicator
			my $p_item = $r.$Sep.$i;
			if ($w1->indicatorExists($p_item)) { $w1->indicatorConfigure($p_item, -style => $style_indic2); }
		}

		### hlist indicator
		my $p_route = $r;
		if ($w1->indicatorExists($p_route)) { $w1->indicatorConfigure($p_route, -style => $style_indic2); }
	}
}
### open/close triggers
my $opencmd_orig = $w1->cget('-opencmd');
sub opencmd_fn {
	#print "opencmd() args=@_\n";
	my $w = shift;

	### system opencmd()
	$w->$opencmd_orig(@_);

	### insert new stuff here
	my ($p) = @_;
	if (&is_route($p)) {
		### Scenario 1: when route-line opened, move data to total-line (bottom)
		my $p_route = $p;
		$w->itemDelete($p_route, $col_profit);
		$w->itemDelete($p_route, $col_cost);
		$w->itemDelete($p_route, $col_size);
		$w->itemDelete($p_route, $col_age);
		$w->itemDelete($p_route, $col_qty);
		$w->itemDelete($p_route, $col_roi);
		$w->itemDelete($p_route, $col_pps);
		$w->selectionClear();
		$w->selectionSet($p_route.$Sep."TOTAL");
		&highlight_return_route_clear();
	} elsif (&is_item($p)) {
		### Scenario 2: only show item quantity when bid/ask orders are visible
		my $p_item = $p;
		my ($r, $i) = split($Sep, $p);
		my @o_r = ($Data{$r}{$i}{Ignore}) ? @opts_ignore_r : @opts_r;
		$w1->itemCreate($p_item, $col_qty, -text => &commai($Data{$r}{$i}{Qty})." x".$Post, @o_r); 
		&pick_color($p_item, $col_qty);
	}
}
my $opencmd = [\&opencmd_fn, $w1];
my $closecmd_orig = $w1->cget('-closecmd');
sub closecmd_fn {
	#print "closecmd() args=@_\n";
	my $w = shift;

	### call system closecmd()
	$w->$closecmd_orig(@_);

	### insert new stuff here
	my ($p) = @_;
	### when route closed, restore route-line data (total-line now hidden)
	if (&is_route($p)) {
		### Scenario 1: when route-line opened, move data to total-line (bottom)
		my $p_route = $p;
		my $r = $p_route;
		$w->itemCreate($p_route, $col_profit, -text => $Pre.&iski2s($Totals{$r}{Profit}).$Post, @opts_top_r); 
		$w->itemCreate($p_route, $col_cost, -text => $Pre.'-'.&iski2s($Totals{$r}{Cost}).$Post, @opts_top_r); 
		$w->itemCreate($p_route, $col_size, -text => $Pre.&commai(int($Totals{$r}{Size}))." m3".$Post, @opts_top_r); 
		$w->itemCreate($p_route, $col_age, -text => $Pre.($Totals{$r}{Age} ? &age2s($Totals{$r}{Age}) : "---").$Post, @opts_top_r); 
		$w->itemCreate($p_route, $col_qty, -text => " ", @opts_top_r); 
		$w->itemCreate($p_route, $col_roi, -text => " ", @opts_top_r); 
		$w->itemCreate($p_route, $col_pps, -text => " ", @opts_top_r); 
		if ($p eq $Routes[-1]) { &underline_cell($p, $col_profit); }
	} elsif (&is_item($p)) {
		### Scenario 2: only show item quantity when bid/ask orders are visible
		my $p_item = $p;
		#$w1->itemDelete($p_item, $col_qty); 
	}
}
my $closecmd = [\&closecmd_fn, $w1];
$w1->configure(-opencmd => $opencmd);
$w1->configure(-closecmd => $closecmd);

sub save_state {
	### save open/close modes
	my @p_routes = $w1->infoChildren();
	foreach my $pr (@p_routes) {
		$State_mode{$pr} = $w1->getmode($pr); ### open/close modes (route)
		my @p_items = $w1->infoChildren($pr);
		foreach my $pi (@p_items) {
			### open/close modes (item + order)
			$State_mode{$pi} = $w1->getmode($pi);
			my @p_orders = $w1->infoChildren($pi);
			foreach my $po (@p_orders) {
				$State_mode{$po} = $w1->getmode($po);
			}1
		}
	}

	### save selection
	@State_selection = $w1->selectionGet();
	$p_lastAltHighlight = 0;
}
sub restore_state {
	### open/close modes
	foreach my $p (keys %State_mode) {
		if (! $w1->infoExists($p)) { next; }
		#print "restoring $p $State{$p}\n";
		my $mode = $State_mode{$p};
		if ($mode eq 'open') { $w1->close($p); }
		if ($mode eq 'close') { $w1->open($p); }
	}
	%State_mode = ();

	### selection
	if (@State_selection > 0) {$w1->selectionClear();} ### clear auto-select of "Total" line
	foreach my $p (@State_selection) {
		if ($w1->infoExists($p)) {
			$w1->selectionSet($p);
			&highlight_return_route_cmd($p);
			print ">>> selection set \"$p\"\n";
		}
	}
	@State_selection = ();
}



### redraw(): recalc + redraw based on Data.Asks[] and Data.Bids[]
sub redraw {
	&save_state();
	&recalc();
	&repop();
	$w1->autosetmode();
	&repop_indicators();
	&restore_state();
}



my $last_req = '';
sub export_crest_reqs {
	my $fname = $fname_crest_reqs; 
	my $age_old = 20 + 300; ### crest files are backdated by 5 mins
	
	### TODO: separate data by source
	### 1. game export (trumps for 5m)
	### 2. CREST (refresh every 1m)
	### 3. eve-central.com (baseline)
	
	### collect data
	my %reqs;
	foreach my $r (@Routes) {
		my ($from_sys, $to_sys) = split(' -> ', $r);
		my $from_rid = $reg_n2i{$sys2reg{$from_sys}};
		my $to_rid = $reg_n2i{$sys2reg{$to_sys}};
		foreach my $i (keys %{$Data{$r}}) {
			### if data is (age_old) secs old, then request crest data
			if (time - $Data{$r}{$i}{Asks_Age} >= $age_old || !$Data{$r}{$i}{Asks_Reliable}) { 
				my $is_bid = 0;
				$reqs{$from_rid}{$i}{$is_bid} = 1;
			}
			if (time - $Data{$r}{$i}{Bids_Age} >= $age_old || !$Data{$r}{$i}{Bids_Reliable}) { 
				my $is_bid = 1;
				$reqs{$to_rid}{$i}{$is_bid} = 1;
			}
		}
	}

	### collect output
	my $text = '';
	my $nreqs = 0;
	if (%reqs) {
		foreach my $reg (sort keys %reqs) {
			foreach my $item (sort { ($a+0) <=> ($b+0) } keys %{$reqs{$reg}}) {
				foreach my $is_bid (keys %{$reqs{$reg}{$item}}) {
					if (not $items_name{$item}) { print ">>> missing item name $item\n"; } # CSS
					$text .= join('~', $reg, $reg_i2n{$reg}, $item, $items_name{$item}, $is_bid)."\n";
					$nreqs++;
				}
			}
		}
	}

	### export (only if new)
	#if ($text ne $last_req) {
	if (1) {
		if ($nreqs > 0) { print &time2s()." export_crest_reqs($nreqs)\n"; }
		my $FH;
		open ($FH, '>', $fname);
		flock ($FH, LOCK_EX);
		print $FH $text;
		close($FH); 
		$last_req = $text;
	} 
	#else { print &time2s()." export_crest_reqs(): dup\n"; }
}

### ignores any orders at non-hub stations
sub import_game_file {
	my ($fname, $fileTime) = @_;
	#print "import_game_file() $fname\n";

	my $ex_fname = '/Users/cserra/Library/Application Support/EVE Online/p_drive/User/My Documents/EVE/logs/Marketlogs/Domain-Medium Pulse Laser Specialization-2016.02.10 194937.txt';
	#my $dir_marketlogs = '/Users/cserra/Library/Application Support/EVE Online/p_drive/User/My Documents/EVE/logs/Marketlogs';
	$fname =~ /^$dir_marketlogs\/(?<region>[^-]+?)-(?<item>.*)-(?<yr>[0-9]{4})\.(?<mo>[0-9][0-9])\.(?<dy>[0-9][0-9]) (?<hh>[0-9][0-9])(?<mm>[0-9][0-9])(?<ss>[0-9][0-9])\.txt$/;

	my $fileRegName = $+{region};
	my $fileHubStnFullname = &reg2hub($fileRegName);
	my $fileItem = &item_fname2iname( $+{item} );
	my $id = $items_id{$fileItem};
	#$fileTime = &fname2time($fname); ### override system modtime with evetime
	#print &time2s()." import() ".sprintf("%-13s", "[".$fileRegName."]")." $fileItem\n";

	### Pass 1: parse marketlog file into bids[] and asks[]
	my @bids = ();
	my @asks = ();
	my $order_loc = 0;
	my $n_orders = 0;
	my $FH;
	open($FH, '<:crlf', $fname);
	<$FH>; ### header line
	while (<$FH>) {
		my ($orderPrice, $volRemaining, $typeID, $range, $orderID, $volEntered, $minVolume, $isBid, $issueDate, $duration, $orderStationID, $orderRegionID, $orderSystemID, $jumps, undef) = split(',');
		my $bidask = ($isBid eq 'True') ? 'bid' : 'ask';
		my $price = $orderPrice;
		my $vol = $volRemaining;
		my $when = &issuedate2time($issueDate);
		my $ignore = 0;

		### skip if minimum volume (scam)
		if ($minVolume > 1) { next; }

		### keep all hub station orders + regional buy orders
		my $hubSys = &hub2sys($fileHubStnFullname);
		if ($range eq "solarsystem") { $range = 0; }
		if ( &stn_is_hub($orderStationID) or 					### hub order
		    ($isBid eq 'True' and $range == 32767) or 				### regional buy order
		    ($isBid eq 'True' and $range > -1 and $orderSystemID == $hubSys) or	### same-system buy order
		    ($isBid eq 'True' and $jumps <= $range)				### in-range buy order (if jumps known)
		   ) { 
		   	### construct order
			my $tuple = join(':', ($price, $vol, $ignore, $when, $orderID));
			if ($bidask eq 'bid') {
				push(@bids, $tuple); $n_orders++;
			} else {
				push(@asks, $tuple); $n_orders++;
			}
		}
	}
	if ($n_orders == 0) { 
		### this is not a fail state
		### the fact that there are zero bids/asks is valid data
		print &time2s()." import_game_file(): empty marketlog file ".sprintf("%12s", "[".$fileRegName."]")." $fileItem\n";
	}

	### Pass 2: sort into bidsSorted[] and askSorted[]
	my @asksSorted = sort {
		my ($price_a) = split(':', $a);
		my ($price_b) = split(':', $b);
		$price_a <=> $price_b; ### lowest first (ascending)
	} @asks;
	my @bidsSorted = sort {
		my ($price_a) = split(':', $a);
		my ($price_b) = split(':', $b);
		$price_b <=> $price_a; ### highest first (descending)
	} @bids;

	### Pass 3: import new data to all relevant Routes
	### wipe old data first
	my $n_asks = 0;
	my $n_bids = 0;
	foreach my $r (@Routes) {
		my ($startStn, $endStn) = &route2stns($r); ### station fullname

		### check if this file is relevant to this Route
		if ($fileRegName ne $stn2reg{$startStn} and $fileRegName ne $stn2reg{$endStn}) { next; } 
		if (not exists $Data{$r}{$id}) { next; } ### item not relevant to this Route
			

		#print ">>> locs:\n  $startStn  X\n  $endStn  X\n  $order_loc\n";

		### check if asks are relevant to this Route
		if ($fileHubStnFullname eq $startStn) {
			$Data{$r}{$id}{Asks} = (); ### wipe current list of asks
			$Data{$r}{$id}{Asks_Reliable} = 1;
			$Data{$r}{$id}{Asks_Age} = 0;			
			foreach my $ask (@asksSorted) { 
				push(@{$Data{$r}{$id}{Asks}}, $ask); 
				$n_asks++; 
				my ($price, $vol, $ignore, $when) = split(':', $ask);
				$Data{$r}{$id}{Asks_Age} = max($Data{$r}{$id}{Asks_Age}, $when); ### most recent order
			}
			$Redraw = 1;
			
		### check if bids are relevant to this Route
		} elsif ($fileHubStnFullname eq $endStn) {
			$Data{$r}{$id}{Bids} = (); ### wipe current list of asks
			$Data{$r}{$id}{Bids_Reliable} = 1;
			$Data{$r}{$id}{Bids_Age} = 0;
			foreach my $bid (@bidsSorted) { 
				push(@{$Data{$r}{$id}{Bids}}, $bid); 
				$n_bids++;
				my ($price, $vol, $ignore, $when) = split(':', $bid);
				$Data{$r}{$id}{Bids_Age} = max($Data{$r}{$id}{Bids_Age}, $when); ### most recent order
			}
			$Redraw = 1;
		} else { 
			next; 
		}
	}

	close $FH;
	#print "game data: $items_name{$id} ".sprintf("%11s", "\[$fileReg\]")." - $n_asks asks, $n_bids bids\n";
}

sub item_fname2iname {
	my ($item) = @_;
	if (! $items_id{$item} ) {
		if ( $item_fname2iname{$item} ) { 
			$item = $item_fname2iname{$item};
		} elsif ( $items_id{ $item =~ s/_/:/r } ) {
			$item =~ s/_/:/;
			#print &time2s()." import_from_game(): colon substitution, item=$item\n";
		} elsif ( $items_id{ $item =~ s/_/\//r } ) {
			$item =~ s/_/\//;
			#print &time2s()." import_from_game(): slash substitution, item=$item\n";
		} else {
			print &time2s()." import_from_game(): unknown item, item=$item\n";
			next;
		}
	}	
	return $item;
}

my %lastImports = ();
sub import_from_game {
	#print "refresh_game_data()\n";

	my $dirname = $dir_marketlogs;
	#my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$modtime,$ctime,$blksize,$blocks) = stat($dirname);
	#print ">>> directory last modified ".&time2s($modtime)." >$dirname<\n";
	my $DIR;
	opendir($DIR, $dirname) or die "directory.open failed: >$dirname<";

	my %Exports = ();
	#my @files = grep { ($_ ne '.') and ($_ ne '..') } readdir($DIR);
	my @files = readdir($DIR);
	closedir($DIR);

	### read marketlog dir into Exports[]
	### purge older files
	foreach my $fname (@files) {
		if ($fname =~ /^(?<region>[^-]+?)-(?<item>.*)-(?<yr>[0-9]{4})\.(?<mo>[0-9][0-9])\.(?<dy>[0-9][0-9]) (?<hh>[0-9][0-9])(?<mm>[0-9][0-9])(?<ss>[0-9][0-9])\.txt$/) {
			my $fname_full = $dirname.$dir_sep.$fname;
			#if ( $empty_game_files{$fname2} ) { next; }
			my $reg = $+{region};
			my $item = &item_fname2iname( $+{item} );
			my $id = $items_id{$item};
			my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$modtime,$ctime,$blksize,$blocks) = stat($fname_full);
			
			### purge game export files > 72 hours old
			if (time - $modtime > $age_expire_export) {
				unlink $fname_full;
				next;
			}

			### dictionary key = <region> + <item>
			### dictionary value = <fname> + <ftime>
			my $key = "$reg.$id";
			my $ftime = &fname2time($fname); ### evetime of file export
			my $f1 = join($Sep, $fname_full, $ftime);
			
			### if dup delete older
			if (! $Exports{$key}) {
				$Exports{$key} = $f1;
			} else {
				### 2 files for same region-item pair => most recent wins
				my $f2 = $Exports{$key};
				my ($fname2_full, $ftime2) = split($Sep, $f2);
				if ($ftime2 >= $ftime) {
					unlink $fname_full;
				} else {
					unlink $fname2_full;
					$Exports{$key} = $f1;
				}
			}
		} else {
			### this captures "." and ".."
			#print ">>> filename $fname did not parse\n";
		}
	}

	### compare game files to live data
	### for each route, for each item, if there is a file for that item at From or To, import it 
	$Redraw = 0;
	my $nimports = 0;
	foreach my $r (keys %Data) {
		my ($from_s, $to_s) = split(' -> ', $r);
		my $from_r = $sys2reg{$from_s};
		my $to_r = $sys2reg{$to_s};
		foreach my $id (keys %{$Data{$r}}) {

			### check From region
			my $key = "$from_r.$id";
			if ($Exports{$key}) {
				my ($fname, $ftime) = split($Sep, $Exports{$key}); ### evetime of marketlog export
				if ( !$lastImports{$key} || $lastImports{$key} < $ftime) {
					&import_game_file($fname, $ftime);
					$lastImports{$key} = $ftime;
					$nimports++;
					$Redraw = 1;
				} else {
					#print "old file $fname ".&time2s($ftime)." vs ".($Data{$r}{$id}{Asks_Reliable} ? 'game' : 'html')." data (asks) \n";
				}
			}

			### check To region
			my $key2 = "$to_r.$id";
			if ($Exports{$key2}) {
				my ($fname, $ftime) = split($Sep, $Exports{$key2});
				my $age2 = $Data{$r}{$id}{Bids_Age};
				#if ( $modtime > $age2 )
				if ( !$lastImports{$key} || $lastImports{$key} < $ftime) {
					&import_game_file($fname, $ftime);
					$lastImports{$key} = $ftime;
					$nimports++;
					$Redraw = 1;
				} else {
					#print "old file $fname ".&time2s($ftime)." vs ".($Data{$r}{$id}{Bids_Reliable} ? 'game' : 'html')." data (bids)\n";
				}
			}
		}
	}
	
	if ($nimports > 0) { print &time2s()." import_marketlogs($nimports)\n"; }
	return $Redraw;
}

### refresh(): update loop, called every N sec
my $last_update_server = 0;
sub server_data_init {
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($cargo_filename);
	if (not $mtime) { 
		print "\n".&time2s()." waiting for cargo file..."; 
		while (not $mtime) {
			($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($cargo_filename);
			print ".";
			sleep 1;
		}
		print "done\n";
	}
}
sub refresh_server_data {
	#print &time2s()." refresh_server_data()...";

	my $Redraw = 0;

	### check if evecentral data has changed (cargo file)
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$mtime,$ctime,$blksize,$blocks) = stat($cargo_filename);
	if (not $mtime) { print "\n".&time2s()." no cargo file\n"; }
	if ($mtime and ($mtime > $last_update_server)) {
		#$Redraw ||= &import_from_server();
		&import_from_server();
		&export_crest_reqs(); ### request crest data for new items

		my $update_ago = ($last_update_server != 0) ? (sprintf("%3i", (time - $last_update_server))."s ago") : ("never");
		my $mod_ago = (defined $mtime) ? ((time - $mtime)."s ago") : ("never");
		print &time2s()." refresh_server_data(): last $update_ago, file mod $mod_ago\n";
		$last_update_server = time;
	}

	### check if marketlogs files have changed
	$Redraw ||= &import_from_game();

	if ($Redraw) { 
		&export_my_data();
		&redraw(); 
	}
}





### main()
&import_item_db;
&import_my_data();
&server_data_init(); 

my $repeat1 = $w1->repeat( 3000, \&refresh_server_data);
#my $repeat2 = $w1->repeat(20000, \&notify_refresh);
#my $repeat4 = $w1->repeat( 15000, \&export_crest_reqs); ### refresh crest data for all items every N sec
#$repeat2->cancel(); # HOWTO: cancel a repeating process






my @fields_indicator = (
	-itemtype,
	-image,
	-style,
);

my $style_indic = $w1->ItemStyle('image', 
#	-foreground => $color_fg, 		# fail
#	-activeforeground => $color_fg,		# fail
	-background => $color_fg,  		# Y
	-activebackground => $color_fg,  	# Y
);
#$w1->indicatorConfigure('Amarr -> Jita', -style => $style_indic); ### works (for backgrounds)
#$w1->indicatorConfigure('Jita -> Amarr', -background => $color_fg); ### fail

my @fields_style2 = (
	'-foreground',
	'-background',
	'-activeforeground',
	'-activebackground',
	'-anchor',
	'-padx',
	'-padx',
);

my $imgopen = $mw->Getimage('minusarm');
my $imgclose = $mw->Getimage('plus');
#$imgopen->configure(-style => $style_indic); # fail
#my $os = $imgclose->cget(-style);		# fail
#my $os = $imgclose->cget(-foreground);		# fail
#my $os = $imgclose->cget(-color);		# fail

#print "minusarm options: ".($opts)."\n";

#my $path = 'Jita -> Amarr';
#unshift(@{$w1->{Images}},[$path,$imgopen,$imgclose]);
#my $img = $w->_indicator_image( $ent );




MainLoop;
print "MainLoop() exit\n";


#system("taskkill /PID $pid_skynet");  # fail
system("taskkill /F /T /IM php.exe");  # pwn
system("taskkill /F /T /IM perl.exe");
