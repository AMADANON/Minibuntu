#!/usr/bin/perl
use GDBM_File;
use Data::Dumper;
$Data::Dumper::Terse=1;
$Data::Dumper::Sortkeys=1;

die "$0 <database> [<package> [<version>] ]\n" unless ($ARGV[0]);

if ($ARGV[0] eq "-edit") {
	$edit=1;
	shift(@ARGV);
}

tie(%packagedb,"GDBM_File",$ARGV[0],&GDBM_WRCREAT,0640);

if (($edit) && ($ARGV[1] eq "")) {
	die "Edit requires a key!\n";
} elsif ($edit) {
	open(F,">key.txt");
	print F $packagedb{$ARGV[1]};
	close(F);
	system("vi key.txt");
	open(F,"<key.txt");
	$tmp=eval(join("",<F>));
	if (defined $tmp) {
		$packagedb{$ARGV[1]}=Dumper($tmp);
	}
	unlink("key.txt");
} elsif ($ARGV[1] eq "") {
	print Dumper(\%packagedb);
} elsif ($ARGV[2] eq "") {
	print $packagedb{$ARGV[1]};
} elsif ($ARGV[2] eq "+") {
	$tmp=eval($packagedb{$ARGV[1]});
	@keys=sort keys %$tmp;
	print Dumper($tmp->{pop(@keys)});
} else {
	$tmp=eval($packagedb{$ARGV[1]});
	print Dumper($tmp->{$ARGV[2]});
}

