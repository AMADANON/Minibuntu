#!/usr/bin/perl
$|=1;
use pkglib;
use Data::Dumper;
$Data::Dumper::Terse=1;
$Data::Dumper::Sortkeys=1;


my $arch="i386";



# Given a title, and a list of options, shows (somehow) the list, allows the user to select one,
# and returns the number of the item selected.
sub menu {
	my ($title,$options,$suffix)=@_;
	my ($line,$offset);
	do {
		$count=0;
		print "\e[2J\e[H"; # Clear screen, move to (1,1).
		print "$title:\n";
		foreach my $index (0..$#{$options}) {
			if ($options->[$index] eq "") {
				print "\n";
			} else {
				$count++;
				print "\t".($count)."\t$options->[$index]\n";
			}
		}
		print "$suffix\n";
		print "Option: ";
		$choice=<STDIN>;
		chomp($choice);
		$choice--; # Because we want 0 based. If it's a non-number, it becomes -1.
	} while (($choice<0) || ($choice>$count));
	return $choice;
}

sub edit {
	my ($pdb,@specified_packages)=@_;
	my ($package,$edit);
	my @packages=$pdb->render_simple_dependencies(@specified_packages);

	@packages=sort {$a->{"name"} cmp $b->{"name"}} @packages;

	#my ($packages,$packagenumber,@editfields);
	@editfields=qw/Package ReverseDeps Depends Pre-Depends Provides/;
	while (1) {
		#$package=$packages[&menu("Packages",[(map {$_->{"name"}} @packages),"","Quit"])];
		$package=&menu("Packages",[(map {$_->{"name"}} @packages),"","Quit"]);
		$package=$packages[$package];
		last unless (defined $package);
		while (1) {
			my (@menu)=map {sprintf("%-13s %s",$_,$package->get($_));} @editfields;
			$menu[0]=sprintf("%-13s %s",$editfields[0],$package->{"name"});
			$menu[1]=sprintf("%-13s %s",$editfields[1],join(", ",@{$package->{"rdeps"}}));
			$edit=&menu("Fields for package $package->{name}",[@menu,"","Back"]);
			if ($edit>$#menu) {
				last;
			} elsif ($editfields[$edit] eq "Package") {
				#TODO
			} elsif (($editfields[$edit] eq "ReverseDeps") && ($#{$package->{"rdeps"}}==-1)) {
				print "This package has no reverse dependencies\nPress enter to continue\n";
				$edit=<>;
			} elsif ($editfields[$edit] eq "ReverseDeps") {
				my ($rdepchoice,@rdeps);
				@rdeps=sort(@{$package->{"rdeps"}});
				if ($#rdeps==0) {
					$redpchoice=0;
				} else {
					$rdepchoice=&menu("Things that depend on ".$package->{"name"},[@rdeps,"","Back to ".$package->{"name"},"Main menu"]);
				}
				last if ($rdepchoice==$#rdeps+2); # "Main menu"
				if ($rdepchoice<=$#rdeps) {
					for ($packagenumber=0; ($packagenumber<=$#packages) && ($packages[$packagenumber]->{"name"} ne $rdeps[$rdepchoice]); $packagenumber++) { };
					if ($packagenumber>$#packages) {
						die "Could not find package?!?!";
					}
					$package=$packages[$packagenumber];
				}
			} else {
				$edit=$editfields[$edit];
				print sprintf("%-13s %s\n","Field",$edit);
				print sprintf("%-13s %s\n","Stock",$package->getbase($edit));
				print sprintf("%-13s %s\n","Current",$package->get($edit));
				print sprintf("%-13s","New",$package->get($edit));
				my $newdata;
				$newdata=<STDIN>;
				chomp($newdata);
				$package->set($edit,$newdata);
				$pdb->save($package);
			}
		}
	}
}

$pdb=new PackageDb($arch);
my $commands={
	"help"=>sub {
		print "$0 builddb		Reloads all the packages, builds database\n";
		print "$0 edit <package>	Edits the package overrides\n";
		print "$0 build <packages>	Builds the machine specified\n";
	},
	"builddb"=>sub {
		$pdb->setup();
		$pdb->downloadpackagelists();
		$pdb->rebuild();
	},
	"edit"=>sub {
		die "Before editing packages, you must rebuild the db:\n\t$0 builddb\n" unless ($pdb->checkdbm());
		shift(@ARGV);
		$pdb->tie();
		&edit($pdb,@ARGV);
	},
	"build"=>sub {
		die "Before editing packages, you must rebuild the db:\n\t$0 builddb\n" unless ($pdb->checkdbm());
		shift(@ARGV);
		$pdb->tie();
		$pdb->build(@ARGV);
	},
};
unless (exists $commands->{$ARGV[0]}) {
	$ARGV[0]="help";
}
&{$commands->{$ARGV[0]}}();
