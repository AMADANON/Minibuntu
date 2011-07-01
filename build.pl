#!/usr/bin/perl


package Package;

sub new {
	my ($type,$name,$package,$override,$packagedb)=@_;
	my $self={"type"=>$type,"name"=>$name,"package"=>$package,"override"=>$override,"packagedb"=>$packagedb};
	bless($self,$type);
	return $self;
}

sub get {
	my ($self,$key)=@_;
	my ($val)=$self->{"package"}->{$key};
	if (exists $self->{"override"}->{"Replace"}->{$key}->{$val}) {
		$val=$self->{"override"}->{"Replace"}->{$key}->{$val};
	}
	return $val;
}

sub dirty {
	my ($self,$key)=@_;
	return (exists $self->{"override"}->{"Replace"}->{$key}->{$self->{"package"}->{$key}});
}

sub set {
	my ($self,$key,$value)=@_;
	if ($key eq "Parent") {
		$self->{"override"}->{$key}=$value;
	} else {
		$self->{"override"}->{"Replace"}->{$key}->{$self->{"package"}->{$key}}=$value;
	}
	$self->{"packagedb"}->save($self->{"name"},$self->{"override"});
}

sub alldeps {
	my ($self)=@_;
	my (@deps);
	foreach (split(/\s*,\s*/,$self->get("Depends")), split(/\s*,\s*/,$self->get("Pre-Depends"))) {
		if ($_=~/^(\S+)(\s+[^\|]*|)$/) {
			push(@deps,$1);
		}
	}
	return @deps;
}

sub debfile {
	my ($self)=@_;
	if ($self->{"package"}->{"Package"}) {
		my $deb;
		$deb=join("_",$self->{"package"}->{"Package"},$self->{"package"}->{"Version"},$self->{"package"}->{"Architecture"});
		$deb=~s/:/\%3a/g;
		return "$deb.deb";
	} else {
		return;
	}
}

sub install {
	my ($self,$source,$target)=@_;
	my ($debfile)=$self->debfile();
	if ($debfile) {
		if (-f $debfile) {
			system("ar p $source/".$self->debfile()." data.tar.gz | tar -C $target -xzf -");
		} else {
			die "Missing file debfile $debfile\n";
		}
	}
}

package PackageDb;
use GDBM_File;
use Data::Dumper;
$Data::Dumper::Terse=1;
$Data::Dumper::Sortkeys=1;

sub new {
	my ($type,$name)=@_;
	my $self={type=>$type};
	bless($self,$type);
	return $self;
}

sub checkdbm {
	my ($self,$path)=@_;
	if ($path eq "") { $path="."; }
	return (-e "$path/packagedb.dbm");
}

sub tie {
	my ($self,$path)=@_;
	if ($path eq "") { $path="."; }
	die "Could not find $path/packagedb.dbm\n" unless ($self->checkdbms($path));
	$self->{"packagedb"}={};
	$self->{"overrides"}={};
	tie(%{$self->{"packagedb"}},"GDBM_File","$path/packagedb.dbm",&GDBM_WRCREAT,0640) || die "Could not open $path/packagedb.dbm: $!";
	tie(%{$self->{"overrides"}},"GDBM_File","$path/overrides.dbm",&GDBM_WRCREAT,0640) || die "Could not open $path/overrides.dbm: $!";
}

# Returns the most recent version of a package
sub mostrecent {
	my ($package)=@_;
	my (@keys)=sort {system("dpkg","--compare-versions",$a,"lt",$b)==0?-1:1} keys %$package;
	return $package->{pop(@keys)};
}


sub fetch {
	my ($self,$package)=@_;
	my ($db,$ov);
	if (exists $self->{"overrides"}->{$package}) { 
		$ov=eval($self->{"overrides"}->{$package});
		if ($ov->{"Parent"}) {
			$db=&mostrecent(eval($self->{"packagedb"}->{$ov->{"Parent"}}));
		}
	} elsif (exists $self->{"packagedb"}->{$package}) { 
		$db=&mostrecent(eval($self->{"packagedb"}->{$package}));
	}
	$self->{"seen"}->{$package}=new Package($db,$ov,$self);
}

sub save {
	my ($self,$key,$value)=@_;
	$self->{"overrides"}->{$key}=Dumper($value);
}

package main;
$|=1;
use Cwd;
use File::Path qw(make_path rmtree);
use File::Copy;
use Data::Dumper;
use GDBM_File;
$Data::Dumper::Terse=1;
$Data::Dumper::Sortkeys=1;


my $arch="i386";
my $path=getcwd."/apt/".$platform;

sub aptget {
	my ($arch,$path,$command)=@_;
	system("apt-get -o Dir::State::status=$path/var/lib/dpkg/status -o Debug::NoLocking=true -o Dir=$path -o APT::Architecture=$arch -o Dir::Etc::Trusted=$path/etc/apt/trusted.gpg $command");
}

sub setup {
	my ($arch,$path)=@_;
	my (%seen_keys);
	die "Missing sources.list - try http://repogen.simplylinux.ch/\n"
		unless (-e "sources.list");
	&make_path("$path/etc/apt/preferences.d/");
	&make_path("$path/var/lib/apt/lists/partial");
	&make_path("$path/var/cache/apt/archives.partial");
	&make_path("$path/var/lib/dpkg");
	unless (-e "$path/var/lib/dpkg/status") {
		die "Could not touch status" unless open(F,">$path/var/lib/dpkg/status"); 
		close(F);
	}
	&copy("sources.list","$path/etc/apt/sources.list");
	&aptget($arch,$path,"update 2> update.log");
	open(F,"<update.log");
	while ($line=<F>) {
		if (($line=~/NO_PUBKEY ([\dA-F]{16})$/) && (!$seen{$1})) {
			$seen{$1}++;
			system("gpg --ignore-time-conflict --no-options --keyring $path/etc/apt/trusted.gpg --primary-keyring $path/etc/apt/trusted.gpg --keyserver hkp://subkeys.pgp.net --recv $1");
		}
	}
	unlink("update.log");
}

sub install_package {
	my ($path,$package)=@_;
	$path.="/var/cache/apt/archives/$package->{DebFile}.deb";
	die "missing deb: $path" unless (-f $path);
	my $contents=`ar t $path`;
	if ($contents=~/data\.tar\.gz/) {
		system("ar p $path data.tar.gz | tar -C target/ -xzf -");
	} elsif ($contents=~/data\.tar\.bz2/) {
		system("ar p $path data.tar.bz2 | tar -C target/ -xjf -");
	} else {
		die $contents;
	}
}

sub alldeps {
	my ($package)=@_;
	my (@deps);
	foreach (split(/\s*,\s*/,$package->{"Depends"}), split(/\s*,\s*/,$package->{"Pre-Depends"})) {
		if ($_=~/^(\S+)(\s+[^\|]*|)$/) {
			push(@deps,$1);
		}
	}
	return @deps;
}

sub load_packageslist {
	my ($path)=@_;
	my ($last,$line,$package,%packagedb,%alread_provided);
	if (-e "packagedb.dbm") {
		tie(%packagedb,"GDBM_File","packagedb.dbm",&GDBM_WRCREAT,0640);
		return \%packagedb;
	}
	tie(%packagedb,"GDBM_File","packagedb.dbm",&GDBM_WRCREAT,0640);
	my $counter;
	print "Building package list\n";
	foreach my $packagefile (glob("$path/var/lib/apt/lists/*_Packages")) {
		my $filetime=[stat $packagefile]->[9];
		open(F,"<$packagefile");
		$package={};
		while ($line=<F>) {
			print "." if ($counter++%20000==0);
			if ($line=~/^$/) {
				$package={};
			} elsif ($line=~/^(\S*):\s*(.*)$/i) {
				$package->{$1}=$2;
				$last=$1;
			} elsif ($line=~/^\s\.$/) {
				$package->{$last}.="\n";
			} elsif ($line=~/^\s(.*)$/) {
				$package->{$last}.="\n$1";
			} else {
				die "Undecipherable line: $line";
			}
			$package->{"FromFile"}=$packagefile;
			if (($package->{"Package"} ne "") && ($package->{"Version"} ne "")) {
				$packagedb->{$package->{"Package"}}->{$package->{"Version"}}=$package;
				if ($package->{"Provides"} ne "") {
					foreach (split(/\s+/,$package->{"Provides"})) {
						next if ($already_provided{"$_ $package->{Package}"});
						$already_provided{"$_ $package->{Package}"}++;
						push(@{$packagedb->{$_}->{""}->{"Provided-By"}},$package->{"Package"});
					}
				}
			}
		}
		close(F);
	}
	print " saving ";
	foreach my $packagename (keys %$packagedb) {
		my $details=$packagedb->{$packagename};
		foreach $package (values %$details) {
			if (exists $package->{"Package"}) {
				$package->{"DebFile"}=$package->{"Package"}."_".$package->{"Version"}."_".$package->{"Architecture"};
				$package->{"DebFile"}=~s/:/\%3a/g;
			}
		}
		$packagedb{$packagename}=Dumper($details);
	}
	print "\n";
	return \%packagedb;
}

# Returns the most recent version of a package
sub mostrecent {
	my ($package)=@_;
	my (@keys)=sort {system("dpkg","--compare-versions",$a,"lt",$b)==0?-1:1} keys %$package;
	return $package->{pop(@keys)};
}

sub load_overrides {
	my %overrides;
	tie(%overrides,"GDBM_File","overrides.dbm",&GDBM_WRCREAT,0640);
	return \%overrides;
}

sub render_dependencies {
	my ($packages,$packagedb,$overrides,$edit)=@_;
	my (@deps,%seen,%provseen);
	my @queue=(@$packages);
	while (my $package=shift(@queue)) {
		next if ($seen{$package});
		next if ($provseen{$package});
		my $packageinfo;
		if ($overrides->{$package}) {
			my $override=eval($overrides->{$package});
			if ($override->{"Parent"}) {
				if ($packagedb->{$override->{"Parent"}}) {
					$packageinfo=&mostrecent(eval($packagedb->{$override->{"Parent"}}));
				} else {
					die "Package not found: $override->{Parent} used by override $package";
				}
			}
			while (my ($key,$vals)=each %{$override->{"Replace"}}) {
				unless (exists $vals->{$packageinfo->{$key}}) {
					die "Override for $package says replace $key, but has no replacement for '$packageinfo->{$key}'\n";
				}
				$packageinfo->{$key}=$vals->{$packageinfo->{$key}};
			}
		} elsif ($packagedb->{$package}) {
			$packageinfo=&mostrecent(eval($packagedb->{$package}));
		} else {
			die "Package not found: $package" unless $edit;
		}
		# There is a correct test for this, but I can't think of it, so band-aid.
		if (($packageinfo->{"Version"} eq "") && ($packageinfo->{"Depends"} eq "")) {
			my %uniq=map {$_, 1} @{$packageinfo->{"Provided-By"}};
			if ((scalar (keys %uniq))==1) {
				push(@queue,keys %uniq);
				next;
			} else {
				my $found=0;
				foreach my $option (keys %uniq) {
					$found=1 if ($seen{$option});
					$found=1 if ($provseen{$option});
				}
				next if ($found);
				if (scalar %uniq) {
					die "No package found for $package - please specify which one you want: ".join(", ",keys %uniq)."\n";
				}
				print Dumper($packageinfo);
				die "No package found for $package\n" unless ($edit);
			}
		}
		$seen{$package}=$packageinfo;

		# Get the right package
		foreach my $prov (split(/\s*,\s*/,$seen{$package}->{"Provides"})) {
			$provseen{$prov}={};
		}
		push(@queue,&alldeps($seen{$package}));
	}
#	print Dumper(\%seen);
#	exit;
	#TODO: Check $deps;
	#print Dumper($deps);
	#print Dumper(\%provseen);
	return \%seen;
}

sub build{
	my ($arch,$path,$packages)=@_;
	$packages=&render_dependencies($packages,&load_packageslist($path),&load_overrides());
	@pkgs=grep {exists $packages->{$_}->{"DebFile"}} keys %$packages;
	&aptget($arch,$path,"install --assume-yes --download-only ".join(" ",@pkgs));
	&rmtree("target");
	mkdir("target");
	print "Installing packages\n";
	foreach my $package (keys %$packages) {
		next unless (exists $packages->{$package}->{"DebFile"});
		print "\t$package\n";
		&install_package($path,$packages->{$package});
	}
}

# Given a title, and a list of options, shows (somehow) the list, allows the user to select one,
# and returns the number of the item selected.
sub menu {
	my ($title,$options,$suffix,$specified_packages)=@_;
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
	my ($path,$specified_packages)=@_;
	my ($packages,$packagenumber,@packages,$packagedb,$overrides,@editfields);
	$overrides=&load_overrides();
	$packagedb=&load_packageslist($path);
	$packages=&render_dependencies($specified_packages,$packagedb,$overrides,1);
	@packages=sort keys %$packages;
	@editfields=qw/FilePackage ReverseDeps Depends Pre-Depends Provides/;
	while (1) {
		$packagenumber=&menu("Packages",[@packages,"","Quit"],"",$specified_packages);
		last if ($packagenumber>$#packages);
		while (1) {
			my ($override,$package,$combined,$dirty);
			if ($overrides->{$packages[$packagenumber]}) {
				$override=eval($overrides->{$packages[$packagenumber]});
				if ($override->{"Parent"}) {
					$package=&mostrecent(eval($packagedb->{$override->{"Parent"}}));
					$combined=&mostrecent(eval($packagedb->{$override->{"Parent"}})); ## A seperate copy!
				} else {
					$combined={};
				}
				while (my ($key,$replace)=each(%{$override->{"Replace"}})) {
					if (exists $replace->{$combined->{$key}}) {
						$combined->{$key}=$replace->{$combined->{$key}};
						$dirty->{$key}=1;
					} else {
						$dirty->{$key}=2;
					}
				}
			} else {
				$combined=$package=&mostrecent(eval($packagedb->{$packages[$packagenumber]}));
			}
			my (@editmenu,$title,@rdeps);
			$title="Fields for package $packages[$packagenumber]";
			foreach my $editfield (@editfields) {
				my $text=$editfield.(" " x (15-length($editfield)));
				if ($editfield eq "ReverseDeps") {
					$text.="\t(calc)";
					while (my ($subpkgname,$subpkg)=each %$packages) {
						foreach my $dep (&alldeps($subpkg)) {
							foreach my $alias ($packages[$packagenumber],$combined->{"Provides"}) {
								if ($dep eq $alias) {
									push(@rdeps,$subpkgname);
								}
							}
						}
					}
					$text.="\t\t".join(",",@rdeps);
				} elsif ($editfield eq "FilePackage") {
					if ($override->{"Parent"} ne "") {
						$text.="\t(modified)\t$override->{Parent}";
					} elsif (exists $override->{"Parent"}) {
						$text.="\t(modified)\t(none)";
					} else {
						$text.="\t(stock)\t\t$packages[$packagenumber]";
					}
				} else {
					if ($dirty->{$editfield}==1) {
						$text.="\t(modified)";
					} elsif ($dirty->{$editfield}==2) {
						# Stale means it was changed, but there's no replacement for the value we have
						$text.="\t(stale)\t";
					} else {
						$text.="\t(stock)\t";
					}
					$text.="\t".$combined->{$editfield};
				}
				push(@editmenu,$text);
			}
			my $editchoice=&menu($title,[@editmenu,"","Main Menu"]);
			last if ($editchoice>$#editfields);
			if ($editfields[$editchoice] eq "ReverseDeps") {
				my $rdepchoice;
				if ($#rdeps==0) {
					$redpchoice=0;
				} else {
					$rdepchoice=&menu("Things that depend on $packages[$packagenumber]",[@rdeps,"","Back to $packages[$packagenumber]","Main menu"]);
					last if ($rdepchoice==$#rdeps+2); # main menu
				}
				if ($rdepchoice<=$#rdeps) {
					for ($packagenumber=0; ($packagenumber<=$#packages) && ($packages[$packagenumber] ne $rdeps[$rdepchoice]); $packagenumber++) {
};
					if ($packagenumber>$#packages) {
						die "Could not find package?!?!";
					}
				}
				
			} else { # Any other editable field
				print "Original value:\t$package->{$editfields[$editchoice]}\n";
				print "Current value:\t$combined->{$editfields[$editchoice]}\n";
				print "New value:\t";
				my $newval=<STDIN>;
				chomp($newval);
				if ($editfields[$editchoice] eq "FilePackage") {
					print "Yes\n";
					$override->{"Parent"}=$newval;
				} elsif (ref($override->{"Replace"}) eq "") {
					$override->{"Parent"}=$package->{"Package"};
					$override->{"Replace"}->{$editfields[$editchoice]}->{$package->{$editfields[$editchoice]}}=$newval;
				} else {
					$override->{"Replace"}->{$editfields[$editchoice]}->{$package->{$editfields[$editchoice]}}=$newval;
				}
				$newval=$packages[$packagenumber];
				$overrides->{$newval}=Dumper($override);

				$packages=&render_dependencies($specified_packages,$packagedb,$overrides,1);
				@packages=sort keys %$packages;
				for ($packagenumber=0; ($packagenumber<=$#packages) && ($packages[$packagenumber] ne $newval); $packagenumber++) {}
			}
		}
	}
}

my $commands={
	"help"=>sub {
		print "$0 builddb		Reloads all the packages, builds database\n";
		print "$0 edit <package>	Edits the package overrides\n";
		print "$0 build <packages>	Builds the machine specified\n";
	},
	"builddb"=>sub {
		&setup($arch,$path); 
		unlink("packagedb.dbm"); 
		&load_packageslist($path); 
	},
	"edit"=>sub {
		unless (-e "packagedb.dbm") {
			die "Before editing packages, you must rebuild the db:\n\t$0 builddb\n";
		}
		shift(@ARGV);
		&edit($path,\@ARGV);
	},
	"build"=>sub {
		unless (-e "packagedb.dbm") {
			die "Before building, you must rebuild the db:\n\t$0 builddb\n";
		}
		shift(@ARGV);
		&build($arch,$path,\@ARGV);
	},
};
unless (exists $commands->{$ARGV[0]}) {
	$ARGV[0]="help";
}
&{$commands->{$ARGV[0]}}();
