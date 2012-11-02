package ui;

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

return 1;
