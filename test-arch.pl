use Config;

print ">>> osname   >".$Config{osname}."<\n";
print ">>> archname >".$Config{archname}."<\n";

while (($k, $v) = each %Config) {
	print ">>>    Config{\"$k\"} $v\n";
}
while (($k, $v) = each %ENV) {
	print ">>>    ENV{\"$k\"} $v\n";
}

=begin
	my $fname = '/Users/cserra/Library/Application Support/EVE Online/p_drive/User/My Documents/EVE/logs/Marketlogs/Domain-Medium Pulse Laser Specialization-2016.02.10 194937.txt';
	my $marketlogs_dir = '/Users/cserra/Library/Application Support/EVE Online/p_drive/User/My Documents/EVE/logs/Marketlogs';
	$fname =~ /^$marketlogs_dir\/(?<region>[^-]+?)-(?<item>.*)-(?<yr>[0-9]{4})\.(?<mo>[0-9][0-9])\.(?<dy>[0-9][0-9]) (?<hh>[0-9][0-9])(?<mm>[0-9][0-9])(?<ss>[0-9][0-9])\.txt$/;

	my $region = $+{region};
	my $item = $+{item};

	print ">>> fname >".$fname."<\n";
	print ">>> region >".$region."<\n";
	print ">>> item >".$item."<\n";
=cut

	my $dirname = 'C:\Users\csserra\Documents\EVE\logs\Marketlogs';
	my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,$atime,$modtime,$ctime,$blksize,$blocks) = stat($dirname);
	print ">>> directory last modified $modtime >$dirname<\n";
	my $DIR;
	opendir($DIR, $dirname) or die "directory.open failed: >$dirname<";

	### TODO: not working on win32 !!!
	my $fname = 'C:\Users\csserra\Documents\EVE\logs\Marketlogs\Domain-150mm Light \'Scout\' Autocannon I-2016.03.01 222448.txt';
	print ">>> fname >$fname<\n";
	print ">>> dirname >$dirname<\n";
	my $dir_sep = "\\";
	my $path_esc = $dirname.$dir_sep;
	$path_esc =~ s/\\/\\\\/g;
	print ">>> esc >$dir_marketlogs_esc<\n";
	$fname =~ /^$path_esc(?<region>[^-]+?)-(?<item>.*)-(?<yr>[0-9]{4})\.(?<mo>[0-9][0-9])\.(?<dy>[0-9][0-9]) (?<hh>[0-9][0-9])(?<mm>[0-9][0-9])(?<ss>[0-9][0-9])\.txt$/;
	my $fileRegName = $+{region};
	print ">>> fileRegName >$fileRegName<\n";

my $dir_sep = "\\";
sub strip_dir {
	my ($x) = @_;
	my @tokens = split(quotemeta($dir_sep), $x);
	return $tokens[@tokens-1];
}
print ">>> unstripped ".$fname."\n";
print ">>> stripped ".&strip_dir($fname)."\n";

