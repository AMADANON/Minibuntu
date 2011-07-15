#!/usr/bin/perl


package Package;
use Data::Dumper;

sub new {
	my ($type,$name,$package,$override)=@_;
	my $self={"name"=>$name,"package"=>$package,"override"=>$override};
	bless($self,$type);
	return $self;
}

sub get {
	my ($self,$key)=@_;
	my ($val)=$self->{"package"}->{$key};
	if ((exists $self->{"override"}) &&
	    (exists $self->{"override"}->{"Replace"}) &&
	    (exists $self->{"override"}->{"Replace"}->{$key}) &&
	    (exists $self->{"override"}->{"Replace"}->{$key}->{$val})) {
		return $self->{"override"}->{"Replace"}->{$key}->{$val};
	}
	return $val;
}

sub getbase {
	my ($self,$key)=@_;
	return $self->{"package"}->{$key};
}

sub dirty {
	my ($self,$key)=@_;
	my ($val)=$self->{"package"}->{$key};
	if ((exists $self->{"override"}) &&
	    (exists $self->{"override"}->{"Replace"}) &&
	    (exists $self->{"override"}->{"Replace"}->{$key}) &&
	    (exists $self->{"override"}->{"Replace"}->{$key}->{$val})) {
		return 1;
	}
	return;
}

sub hasoverride {
	my ($self)=@_;
	return (scalar %{$self->{"override"}})>0;
}

sub set {
	my ($self,$key,$value)=@_;
	if ($key eq "Package") {
		$self->{"override"}->{$key}=$value;
	} else {
		$self->{"override"}->{"Replace"}->{$key}->{$self->{"package"}->{$key}}=$value;
	}
}

sub allsimpledepends {
	my ($self)=@_;
	my (@deps);
	foreach (split(/\s*,\s*/,$self->get("Depends")), split(/\s*,\s*/,$self->get("Pre-Depends"))) {
		if ($_=~/^(\S+)(\s+[^\|]*|)$/) {
			push(@deps,$1);
		}
	}
	# If this is not a real package but is provided by exactly one other package, then it "depends on that package".
	# example: "abrowser-3.6" is provided by exactly only "abrowser".
	# If it's provided by more than one package, sort it out later.
	unless (($self->hasoverride) || (exists $self->{"package"}->{"Name"}) || ($#{$self->{"package"}->{"Provided-By"}}!=0)) {
		push(@deps,$self->{"package"}->{"Provided-By"}->[0]);
	}
	return @deps;
}

sub provides {
	my ($self)=@_;
	return split(/\s*,\s*/,$self->get("Provides"));
}

sub debfile {
	my ($self)=@_;
	if (exists $self->{"package"}->{"Package"}) {
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
		if (-f "$source/$debfile") {
			system("ar p $source/".$self->debfile()." data.tar.gz | tar -C $target -xzf -");
		} else {
			die "Missing file debfile $debfile\n";
		}
	}
}

package PackageDb;
use GDBM_File;
use Data::Dumper;
use Cwd;
use File::Path qw(make_path rmtree);
use File::Copy;
use GDBM_File;

$Data::Dumper::Terse=1;
$Data::Dumper::Sortkeys=1;

sub new {
	my ($type,$arch,$path)=@_;
	unless (defined $path) { $path=getcwd."/apt/";}
	unless (defined $arch) { $arch="i386";}
	my $self={path=>$path,arch=>$arch,packagedbm=>"$path/packagedb.dbm",overridedbm=>"$path/override.dbm"};
	bless($self,$type);
	return $self;
}

sub checkdbm {
	my ($self)=@_;
	return (-e $self->{"packagedbm"});
}



sub tie {
	my ($self,$path)=@_;
	if ($path eq "") { $path="."; }
	die "Could not find $self->{packagedbm}\n" unless ($self->checkdbm($path));
	$self->{"packages"}={};
	$self->{"overrides"}={};
	tie(%{$self->{"packages"}},"GDBM_File",$self->{"packagedbm"},&GDBM_WRCREAT,0640) || die "Could not open $self->{packagedbm}: $!";
	tie(%{$self->{"overrides"}},"GDBM_File",$self->{"overridedbm"},&GDBM_WRCREAT,0640) || die "Could not open $self->{overridedbm}: $!";
}

# Returns the most recent version of a package
sub mostrecent {
	my ($self,$package)=@_;
	my (@keys)=sort {system("dpkg","--compare-versions",$a,"lt",$b)==0?-1:1} keys %$package;
	return $package->{pop(@keys)};
}


sub fetch {
	my ($self,$package)=@_;
	die if ($package eq "");
	my ($db,$ov);
	if (exists $self->{"overrides"}->{$package}) { 
		$ov=eval($self->{"overrides"}->{$package});
		if (exists $ov->{"Package"}) {
			$db=$self->mostrecent(eval($self->{"packages"}->{$ov->{"Package"}}));
		}
	} elsif (exists $self->{"packages"}->{$package}) { 
		$db=$self->mostrecent(eval($self->{"packages"}->{$package}));
	} else {
		#die "Unknown package $package";
		return new Package($package);
	}
	return new Package($package,$db,$ov);
}

# to check
sub save {
	my ($self,$package)=@_;
	$self->{"overrides"}->{$package->{"name"}}=Dumper($package->{"override"});
}

sub render_simple_dependencies {
	my ($self,@packagenames)=@_;
	my (%seen,%provseen,%rdeps);
	while (my $packagename=shift(@packagenames)) {
		next if ($seen{$packagename});
		next if ($provseen{$packagename});
		my $package=$self->fetch($packagename);
		$seen{$packagename}=$package;
		foreach ($package->allsimpledepends()) {
			push(@packagenames,$_);
			$rdeps{$_}->{$packagename}=1;
		}
		
		foreach ($package->provides()) {
			$provseen{$_}=$package;
		}
	}
	foreach (keys %rdeps) {
		if (exists $seen{$_}) {
			$seen{$_}->{"rdeps"}=[keys %{$rdeps{$_}}];
		}
	}
	#TODO: Check complex $deps;
	return (values %seen);
}

sub aptget {
	my ($self,$command)=@_;
	system("apt-get -o Dir::State::status=$self->{path}/var/lib/dpkg/status -o Debug::NoLocking=true -o Dir=$self->{path} -o APT::Architecture=$self->{arch} -o Dir::Etc::Trusted=$self->{path}/etc/apt/trusted.gpg $command");
}

sub setup {
	my ($self)=@_;
	my (%seen_keys);
	die "Missing sources.list - try http://repogen.simplylinux.ch/\n"
		unless (-e "sources.list");
	&make_path("$self->{path}/etc/apt/preferences.d/");
	&make_path("$self->{path}/var/lib/apt/lists/partial");
	&make_path("$self->{path}/var/cache/apt/archives.partial");
	&make_path("$self->{path}/var/lib/dpkg");
	unless (-e "$self->{path}/var/lib/dpkg/status") {
		die "Could not touch $self->{path}/var/lib/dpkg/status: $!" unless open(F,"> $self->{path}/var/lib/dpkg/status"); 
		close(F);
	}
	unless (-e "$self->{path}/etc/apt/trusted.gpg") {
		die "Could not touch $self->{path}/etc/apt/trusted.gpg: $!" unless open(F,"> $self->{path}/etc/apt/trusted.gpg"); 
		close(F);
	}
}

sub downloadpackagelists {
	my ($self)=@_;
	&copy("sources.list","$self->{path}/etc/apt/sources.list");
	$self->aptget("update 2> $self->{path}/update.log");
	open(F,"<$self->{path}/update.log");
	while ($line=<F>) {
		if (($line=~/NO_PUBKEY ([\dA-F]{16})$/) && (!$seen{$1})) {
			$seen{$1}++;
			system("gpg --ignore-time-conflict --no-options --keyring $self->{path}/etc/apt/trusted.gpg --primary-keyring $self->{path}/etc/apt/trusted.gpg --keyserver hkp://subkeys.pgp.net --recv $1");
		}
	}
	unlink("$self->{path}/update.log");
}

sub build{
	my ($self,@packagenames)=@_;
	my @packages;
	@packages=$self->render_simple_dependencies(@packagenames);
	@pkgs=map {$_->{"package"}->{"Package"}} @packages;
	$self->aptget("install --assume-yes --download-only ".join(" ",@pkgs));
	&rmtree("target");
	mkdir("target");
	print "Installing packages\n";
	foreach my $package (@packages) {
		print $package->debfile()."\n";
		$package->install($self->{"path"}."/var/cache/apt/archives","target");
	}
}

sub rebuild {
	my ($self)=@_;
        my ($last,$line,$package,%packagedb,%already_provided);
	foreach my $packagefile (glob("$self->{path}/var/lib/apt/lists/*_Packages")) {
		open(F,"<$packagefile");
		$package={};
		while ($line=<F>) {
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
				die "Undecipherable line in $packagefile: $line";
			}
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
	untie($self->{"packagedb"});
	$self->{"packages"}={};
	unlink($self->{"packagedbm"});
        tie(%{$self->{"packages"}},"GDBM_File",$self->{"packagedbm"},&GDBM_WRCREAT,0640);
	foreach my $packagename (keys %$packagedb) {
		$self->{"packages"}->{$packagename}=Dumper($packagedb->{$packagename});
	}
	$self->{"overrides"}={};
	tie(%{$self->{"overrides"}},"GDBM_File",$self->{"overridedbm"},&GDBM_WRCREAT,0640) || die "Could not open $self->{overridedbm}: $!";
}
1;