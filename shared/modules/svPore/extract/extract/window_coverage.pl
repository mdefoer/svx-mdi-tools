use strict;
use warnings;

# finalize the genome fragment coverage map

# load dependencies
our $script = "window_coverage";
our $error  = "$script error";
my $perlUtilDir = "$ENV{GENOMEX_MODULES_DIR}/utilities/perl";
map { require "$perlUtilDir/$_.pl" } qw(workflow numeric);
map { require "$perlUtilDir/genome/$_.pl" } qw(chroms);
map { require "$perlUtilDir/sequence/$_.pl" } qw(general);
resetCountFile();

# constants
use constant {
    QNAME => 0,
    NODE1 => 1,
    # _QSTART => 2,    
    NODE2 => 3,
    # _QEND => 4,
    # _MAPQ => 5,
    # CIGAR => 6,
    # GAP_COMPRESSED_IDENTITY => 7,
    EDGE_TYPE => 8,
    # EVENT_SIZE => 9,
    # INSERT_SIZE => 10,
    # N_STRANDS => 11,
    #-------------
    ALIGNMENT     => "A", # the single type for a contiguous aligned segment
    TRANSLOCATION => "T", # edge/junction types (might be several per source molecule)
    INVERSION     => "V",
    DUPLICATION   => "U",
    DELETION      => "D",
    UNKNOWN       => "?",
    INSERTION     => "I"
};

# environment variables
fillEnvVar(\our $N_CPU,   'N_CPU');
fillEnvVar(\our $EXTRACT_PREFIX,   'EXTRACT_PREFIX');
fillEnvVar(\our $PIPELINE_DIR,     'PIPELINE_DIR');
fillEnvVar(\our $EXTRACT_STEP_DIR, 'EXTRACT_STEP_DIR');
fillEnvVar(\our $WINDOW_SIZE,      'WINDOW_SIZE');
fillEnvVar(\our $GENOME_FASTA,     'GENOME_FASTA');
fillEnvVar(\our $EDGES_NO_SV_FILE, 'EDGES_NO_SV_FILE');

# initialize the genome
use vars qw(%chromIndex);
setCanonicalChroms();

# load additional dependencies
map { require "$EXTRACT_STEP_DIR/$_.pl" } qw(initialize_windows);
initializeWindowCoverage();

# open output handles
open my $nosvH,  "|-", "pigz -p $N_CPU -c | slurp -s 10M -o $EDGES_NO_SV_FILE" or die "could not open: $EDGES_NO_SV_FILE\n";

# process data
my ($nReads, $nSv, $nNoSv, $prevQName, @lines) = (0, 0, 0);
while(my $line = <STDIN>){
    chomp $line;
    my @line = split("\t", $line, 11);
    if($prevQName and $prevQName ne $line[QNAME]){
        printMoleculeEdges();
        @lines = ();
    }
    push @lines, \@line;
    $prevQName = $line[QNAME];
    $line[EDGE_TYPE] eq ALIGNMENT or next;
    incrementWindowCoverage(@line[NODE1, NODE2]);
}
printMoleculeEdges();
printWindowCoverage();
close $nosvH;

# print summary information
printCount($nReads, 'nReads',   'total reads processed');
printCount($nSv,    'nSv',      'reads with at least one candidate SV');
printCount($nNoSv,  'nNoSv',    'single-alignment reads with no SV (up to 10K kept)');

# print a molecule's edges and/or qNames to the appropriate file(s)
sub printMoleculeEdges {
    $nReads++;
    if(@lines == 1){
        $nNoSv++;
        my $line = join("\t", @{$lines[0]})."\n";
        print $nosvH $line; # the record of all simple alignment edges
        $nNoSv <= 10000 or return;
        print $line; # 10K non-SV reads for training adapter models
    } else {
        $nSv++;
        print join("\n", map {join("\t", @$_)} @lines), "\n"; # all initial candidate SV reads
    }
}
