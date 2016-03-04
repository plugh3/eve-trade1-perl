#!C:\Dwimperl\perl\bin\perl.exe

use 5.010;
use strict;
use warnings;

use DBI;

sub isNum {
	my ($x) = @_;
	return ( $x =~ /^[0-9,.E]+$/ ) ? 1 : 0;
}

sub lookupLoc {
	my ($dbh, $x) = @_;
	&lookupStation($dbh, $x);
	&lookupSystem($dbh, $x);
	&lookupRegion($dbh, $x);
}

sub lookupStation {
	my ($dbh, $x) = @_;
	my $results = 0;
	my $qry = (&isNum($x)) 
		? "SELECT stationID, solarSystemID, regionID, stationName FROM stastations WHERE stationID=$x" 
		: "SELECT stationID, solarSystemID, regionID, stationName FROM stastations WHERE stationName LIKE \'\%$x\%\'";
	my $qh = $dbh->prepare($qry);
	$qh->execute();
	while (my $row = $qh->fetchrow_hashref()) {
		$results++;
		print "[$row->{'regionID'}.$row->{'solarSystemID'}.$row->{'stationID'}] $row->{'stationName'}\n";
	}
	$qh->finish();
	return $results;
}
sub lookupSystem {
	my ($dbh, $x) = @_;
	my $results = 0;
	my $qry = (&isNum($x)) 
		? "SELECT solarSystemID, regionID, solarSystemName FROM mapsolarsystems WHERE solarSystemID=$x" 
		: "SELECT solarSystemID, regionID, solarSystemName FROM mapsolarsystems WHERE solarSystemName LIKE \'\%$x\%\'";
	my $qh = $dbh->prepare($qry);
	$qh->execute();
	while (my $row = $qh->fetchrow_hashref()) {
		$results++;
		print "[$row->{'regionID'}.$row->{'solarSystemID'}] $row->{'solarSystemName'}\n";
	}
	$qh->finish();
	return $results;
}
sub lookupRegion {
	my ($dbh, $x) = @_;
	my $results = 0;
	my $qry = (&isNum($x)) 
		? "SELECT regionID, regionName FROM mapregions WHERE regionID=$x" 
		: "SELECT regionID, regionName FROM mapregions WHERE regionName LIKE \'\%$x\%\'";
	my $qh = $dbh->prepare($qry);
	$qh->execute();
	while (my $row = $qh->fetchrow_hashref()) {
		$results++;
		print "[$row->{'regionID'}] $row->{'regionName'}\n";
	}
	$qh->finish();
	return $results;
}

my $username = "dev";
my $password = "BNxJYjXbYXQHAvFM";
my $db_params = "DBI:mysql:database=evesdd;host=127.0.0.1;port=3306";
my $dbh = DBI->connect($db_params, $username, $password);
&lookupLoc($dbh, $ARGV[0]);
$dbh->disconnect();

