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
	@editfields=qw/Package DebFiles NewFiles ReverseDeps Depends Pre-Depends Provides/;
	while (1) {
		#$package=$packages[&menu("Packages",[(map {$_->{"name"}} @packages),"","Quit"])];
		$package=&menu("Packages",[(map {$_->{"name"}} @packages),"","Quit"]);
		$package=$packages[$package];
		last unless (defined $package);
		while (1) {
			my (@menu)=map {sprintf("%-13s %s",$_,$package->get($_));} @editfields;
			$menu[0]=sprintf("%-13s %s",$editfields[0],$package->{"name"});
			$menu[3]=sprintf("%-13s %s",$editfields[3],join(", ",@{$package->{"rdeps"}}));
			$edit=&menu("Fields for package $package->{name}",[@menu,"","Back"]);
			if ($edit>$#menu) {
				last;
			} elsif ($editfields[$edit] eq "Package") {
				#TODO
			} elsif ($editfields[$edit] eq "DebFiles") {
				while (1) {
					$files=$package->getfilesstate();
					$pdb->save($package);
					my $last="";
					my (@menu,@filenames)=();
					foreach (sort keys(%$files)) {
						if (($last ne "") && (substr($_,0,length($last)) eq $last)) {
						} elsif ($files->{$_}->{"include"} eq "none") {
							push(@menu,"N $_");
							push(@filenames,$_);
							if (substr($files->{$_}->{"perms"},0,1) eq "d") {
								$last=$_;
							}
						} elsif ($files->{$_}->{"include"} eq "documentation") {
							push(@menu,"D $_");
							push(@filenames,$_);
							if (substr($files->{$_}->{"perms"},0,1) eq "d") {
								$last=$_;
							}
						} else {
							push(@menu,"F $_");
							push(@filenames,$_);
							$last="";
						}
					}
					$file=&menu("Files for $package->{name}",[@menu,"","Back"],"Where to install? F=filesystem, D=documentation, N=None");
					last if ($file>$#menu);
					while (1) {
						$option=&menu("Package $package->{name} File $filenames[$file]",["Install these files on the filesystem","Install these files as documentation","Don't install these files anywhere","","Back"]);
						last if ($option==3);
						$files->{$filenames[$file]}->{"include"}=["filesystem","documentation","none"]->[$option];
						$pdb->save($package);
						last;
					}
				}
			} elsif ($editfields[$edit] eq "NewFiles") {
				while (1) {
					$files=$package->getfiles();
					@menu=(sort keys %$files);
					$filechoice=&menu("Additional files for ".$package->{"name"},[@menu,"New File","","Back to ".$package->{"name"}]);
					last if ($filechoice==$#menu+2);
					if ($filechoice==$#menu+1) {
						print "New file name: ";
						$filename=<STDIN>;
						chomp($filename);
						$filecontents="";
					} else {
						$filename=$menu[$filechoice];
						$filecontents=$files->{$filename};
					}
					system("rm -rf install_$$; mkdir install_$$");
					open(F,">install_$$/$filename");
					print F $filecontents;
					close(F);
					system("cd install_$$; vi $filename");
					open(F,"<install_$$/$filename");
					$filecontents=join("",<F>);
					close(F);
					system("rm -rf install_$$");
					$package->updatefile($filename,$filecontents,0755);
					$pdb->save($package);
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
			print Dumper($output);
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
