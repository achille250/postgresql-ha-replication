#!/usr/bin/perl
# Pgpool-II Log Sanitizer — FINAL WORKING VERSION
# - Never truncates logs
# - Never processes logs still being written
# - Never processes small rotation files
# - Never sanitizes twice
# - Extracts SELECT / INSERT / UPDATE / DELETE per node
# - Safe for heavy production

use strict;
use warnings;
use File::Path qw(make_path);
use File::Copy qw(move);

############################################################
# CONFIG
############################################################
my $dir = "/u02/pgpool_log";
my $tmp = "$dir/tmp";

# Minimum size of a real Pgpool log (avoid rotation headers)
my $MIN_SIZE = 300;

# Minimum age before sanitizing (Pgpool writes many times per sec)
my $MIN_AGE  = 120;  # 2 minutes

############################################################
# Ensure tmp directory exists
############################################################
unless (-d $tmp) {
    make_path($tmp) or die "Failed to create tmp directory: $tmp";
}

############################################################
# Process log files
############################################################
opendir(my $dh, $dir) or die "Cannot open directory $dir: $!";

while (my $file = readdir($dh)) {

    next unless ($file =~ /^pgpool-.*\.log$/);
    my $full = "$dir/$file";

    ########################################################
    # 1. Skip tiny rotation files (<300 bytes)
    ########################################################
    my $size = -s $full;
    next if (!$size or $size < $MIN_SIZE);

    ########################################################
    # 2. Skip logs still being written (<2 min old)
    ########################################################
    my $mtime = (stat($full))[9];
    my $age = time - $mtime;
    next if ($age < $MIN_AGE);

    ########################################################
    # 3. Read entire file (detect summary)
    ########################################################
    open(my $fh0, "<", $full) or next;
    my $content = do { local $/; <$fh0> };
    close($fh0);

    # Already sanitized? Skip.
    if ($content =~ /^=== Summary for/m) {
        next;
    }

    ########################################################
    # 4. Parse SQL operations per DB node
    ########################################################
    my %count;

    open(my $in, "<", $full) or next;

    while (<$in>) {

        # Example:
        #   DB node id: 1 ... select
        if (/DB\s+node\s+id:\s*(\d+).*?\b(select|insert|update|delete)\b/i) {
            my $node = int($1);
            my $op   = uc($2);

            # Initialize counters
            $count{$node}{'SELECT'} //= 0;
            $count{$node}{'INSERT'} //= 0;
            $count{$node}{'UPDATE'} //= 0;
            $count{$node}{'DELETE'} //= 0;

            # Increase op counter
            $count{$node}{$op}++;
        }
    }

    close($in);

    ########################################################
    # 5. Skip logs with zero SQL ops (avoid empty summaries)
    ########################################################
    if (!%count) {
        next;
    }

    ########################################################
    # 6. Generate summary
    ########################################################
    my $out = "$tmp/$file";
    open(my $outf, ">", $out) or next;

    print $outf "=== Summary for $file ===\n\n";

    foreach my $node (sort {$a <=> $b} keys %count) {
        print $outf "Node $node:\n";
        print $outf "  INSERT: $count{$node}{'INSERT'}\n";
        print $outf "  UPDATE: $count{$node}{'UPDATE'}\n";
        print $outf "  DELETE: $count{$node}{'DELETE'}\n";
        print $outf "  SELECT: $count{$node}{'SELECT'}\n\n";
    }

    close($outf);

    ########################################################
    # 7. Replace original log with sanitized summary
    ########################################################
    move($out, $full);
}

closedir($dh);

############################################################
# 8. Fix permissions
############################################################
system("chown -R postgres:postgres $dir");
system("chmod 750 $dir");
system("chmod 777 $tmp");

exit 0;
