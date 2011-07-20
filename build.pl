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
	@editfields=qw/Package Files ReverseDeps Depends Pre-Depends Provides/;
	while (1) {
		#$package=$packages[&menu("Packages",[(map {$_->{"name"}} @packages),"","Quit"])];
		$package=&menu("Packages",[(map {$_->{"name"}} @packages),"","Quit"]);
		$package=$packages[$package];
		last unless (defined $package);
		while (1) {
			my (@menu);
			foreach (@editfields) {
				if ($_ eq "Package") {
					push(@menu,sprintf("%-13s %s",$_,$package->{"Package"}));
				} elsif ($_ eq "Files") {
					push(@menu,"Files");
				} elsif ($_ eq "ReverseDeps") {
					push(@menu,sprintf("%-13s %s",$editfields[3],join(", ",@{$package->{"rdeps"}})));
				} else {
					push(@menu,sprintf("%-13s %s",$_,$package->get($_)));
				}
			}
			$edit=&menu("Fields for package $package->{name}",[@menu,"","Back"]);
			if ($edit>$#menu) {
				last;
			} elsif ($editfields[$edit] eq "Package") {
				#TODO
			} elsif ($editfields[$edit] eq "Files") {
				while (1) {
					$files=$package->getfilesstate();
					$pdb->save($package);
					my $last="";
					my (@menu,@filenames)=();
					foreach (sort keys(%$files)) {
						if (($last ne "") && (substr($_,0,length($last)) eq $last)) {
						} elsif ((!exists $files->{$_}->{"Filesystem"}) || ($files->{$_}->{"Filesystem"}=~/root/)) {
							push(@menu,"F $_");
							push(@filenames,$_);
							$last="";
						} elsif ($files->{$_}->{"Filesystem"} eq "none") {
							push(@menu,"N $_");
							push(@filenames,$_);
							if ($files->{$_}->{"Type"} eq "d") {
								$last=$_;
							}
						} elsif ($files->{$_}->{"Filesystem"} eq "documentation") {
							push(@menu,"D $_");
							push(@filenames,$_);
							if ($files->{$_}->{"Type"} eq "d") {
								$last=$_;
							}
						} else {
							die "Unknown target";
						}
					}
					$file=&menu("Files for $package->{name}",[@menu,"New File","","Back"],"Where to install? F=filesystem, D=documentation, N=None");
					if ($file==$#menu+2) {
						last;
					} elsif ($file==$#menu+1) {
						print "New file name: ";
						$filename=<STDIN>;
						chomp($filename);
						$filecontents="";
						system("rm -rf install_$$; mkdir install_$$");
						system("cd install_$$; touch $filename; vi $filename");
						open(F,"<install_$$/$filename");
						$filecontents=join("",<F>);
						close(F);
						system("rm -rf install_$$");
						$package->setfileattribute($filename,"Perms",0755);
						$package->setfileattribute($filename,"Timestamp",time);
						$package->setfileattribute($filename,"Contents",$filecontents);
						$pdb->save($package);
					} else {
						while (1) {
							$option=&menu("Package $package->{name} File $filenames[$file]",["Install these files on the filesystem","Install these files as documentation","Don't install these files anywhere","","Back"]);
							last if ($option==3);
							$package->setfileattribute($filenames[$file],"Filesystem",["root","documentation","none"]->[$option]);
							$pdb->save($package);
							last; # Because there is only one thing to set about a file at the moment, and we've just set it.
						}
					}
				}
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
				@packages=$pdb->render_simple_dependencies(@specified_packages);
				@packages=sort {$a->{"name"} cmp $b->{"name"}} @packages;
				for ($packagenumber=0; ($packagenumber<=$#packages) && ($packages[$packagenumber]->{"name"} ne $package->{"name"}); $packagenumber++) { };
				if ($packagenumber>$#packages) {
					die "Could not find package?!?!";
				}
				$package=$packages[$packagenumber];
			}
		}
	}
}

$pdb=new PackageDb($arch);
my $output={
	"-cpio.gz"=>sub {system("cd target && find . | cpio -H newc -o | gzip > ../root.cpio.gz"); return "root.cpio.gz";},
	"-iso"	=>sub {system("genisoimage -o root.iso target/"); return "root.iso";},
	"-ext2" =>sub {system("genext2fs -d target -b 10000 root.ext2"); return "root.ext2"; },
	"-tar.gz"=>sub {system("tar -C target -cvzf root.tar.gz ."); return "root.tar.gz"; },
};
my $commands={
	"help"=>sub {
		print "$0 builddb			Reloads all the packages, builds database\n";
		print "$0 edit <package>		Edits the package overrides\n";
		print "$0 build [-format] <packages>	Builds the machine specified\n";
		print "					-format may be one of: ".join(", ",keys %$output)."\n";
		print "$0 get-kernel <kernelversion> 	Downloads the specified kernel (e.g. generic, server, virtual)\n";
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
		if (exists $output->{$ARGV[0]}) {
			$output=$output->{shift(@ARGV)};
		} else {
			$output=undef;
		}
		$pdb->tie();
		$pdb->build(@ARGV);
		if ($output) {
			system("ls -lah ".&$output());
		}
	},
	"get-kernel"=>sub {
		die "Before fetching the kernel, you must rebuild the db:\n\t$0 builddb\n" unless ($pdb->checkdbm());
		unless ($ARGV[1]) {
			print "$0 get-kernel <kernelversion> 	Downloads the specified kernel (e.g. generic, server, virtual)\n";
			exit(1);
		}
		$pdb->tie();
		foreach ($pdb->fetch("linux-image-$ARGV[1]")->allsimpledepends()) {
			if ($_=~/^linux-image-/) {
				$pkg=$pdb->fetch($_);
				$pdb->aptget("install --assume-yes --download-only ".join(" ",$pkg->{"name"}));
				system($pkg->datatarcmd()."-xv --transform 's/.*\\///' --show-transformed-names --wildcards './boot/vmlinuz-*'");
			}
		}
	},
};
unless (exists $commands->{$ARGV[0]}) {
	$ARGV[0]="help";
}
&{$commands->{$ARGV[0]}}();
