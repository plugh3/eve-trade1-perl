#!C:\Dwimperl\perl\bin\perl.exe

use 5.010;
use strict;
use warnings;

use DBI;

sub isNum {
	my ($x) = @_;
	return ( $x =~ /^[0-9,.E]+$/ ) ? 1 : 0;
}

sub lookupItem {
	my ($dbh, $x) = @_;

	my $qry;
	if (&isNum($x)) {
		$qry = "SELECT typeID, typeName, volume FROM invtypes WHERE typeID=$x";
	} else {
		$qry = "SELECT typeID, typeName, volume FROM invtypes WHERE typeName LIKE \'\%$x\%\'";
	}

	my $sth = $dbh->prepare($qry);
	$sth->execute();
	while (my $row = $sth->fetchrow_hashref()) {
		my $id =   $row->{'typeID'};
		my $name = $row->{'typeName'};
		my $size = $row->{'volume'};

		my $id2 = sprintf("%5i", $row->{'typeID'});
		print "[$id2] $row->{'typeName'} ($row->{'volume'} m3)\n";
	}
	$sth->finish();
}


my $username = "dev";
my $password = "BNxJYjXbYXQHAvFM";
my $db_params = "DBI:mysql:database=evesdd;host=127.0.0.1;port=3306";
my $dbh = DBI->connect($db_params, $username, $password);
&lookupItem($dbh, $ARGV[0]);
$dbh->disconnect();

