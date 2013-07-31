#!/usr/bin/perl

use strict;
use warnings;
use Getopt::Std;
use File::Basename;
use Fcntl ':seek';
use Data::Dumper;
use List::MoreUtils 'uniq';

my $prog      = basename $0;
my $word_dir  = dirname $0;
my $word_file = "$word_dir/twl06.txt";
my $trie_file = "$word_dir/twl06.trie";
my %points    = (
  a => 1, b => 3, c => 3, d => 2, e => 1, f => 4, g => 2, h => 4,  i => 1,
  j => 8, k => 5, l => 1, m => 3, n => 1, o => 1, p => 3, q => 10, r => 1,
  s => 1, t => 1, u => 1, v => 4, w => 4, x => 8, y => 4, z => 10,
);
my %freq      = (
  a => 9, b => 2, c => 2, d => 4, e => 12, f => 2, g => 3, h => 2, i => 9,
  j => 1, k => 1, l => 4, m => 2, n => 6,  o => 8, p => 2, q => 1, r => 6,
  s => 4, t => 6, u => 4, v => 2, w => 2,  x => 1, y => 2, z => 1, 
  '.' => 2,
);
my @two_letter = qw(
  aa ab ad ae ag ah ai al am an ar as at aw ax ay ba be bi bo by de do ed ef eh
  el em en er es et ex fa fe go ha he hi hm ho id if in is it jo ka ki la li lo
  ma me mi mm mo mu my na ne no nu od oe of oh oi om on op or os ow ox oy pa pe
  pi qi re sh si so ta ti to uh um un up us ut we wo xi xu ya ye yo za
);

my %opt;
getopts('hp:l:ax:sb:tcg:r:v', \%opt);
usage() if $opt{h} 
       || !($opt{p} || $opt{l} || $opt{x} || $opt{g}) 
       || (($opt{s} || $opt{b} || $opt{r}) && !$opt{l}) 
       || ($opt{b} && ($opt{s} || $opt{p})) 
       || ($opt{v} && !$opt{r})
       || @ARGV;

die "$prog: can't locate word list $word_file\n" unless -f $word_file;

# setup output
if (-t STDOUT) {
  my $pager = $ENV{PAGER} || 'less';
  open(my $less, "|$pager");
  select($less);
}

my %trie = ( off => 0 ); #global cache
open(my $trie_fh, '<', $trie_file)
  || die "$trie_file: $!: generate using $word_dir/mktrie.pl $word_file\n";

if ($opt{r}) {
  find_parallels($opt{r}, $opt{l});
}
elsif ($opt{g}) {
  $freq{$_}-- for split(//, lc($opt{g}));
  for (sort keys %freq) {
    printf("%2d %s\n", $freq{$_}, $_) if $freq{$_};
  }
  exit;
}
elsif ($opt{s}) {
  $opt{a} = 1;
}
elsif ($opt{b}) {
  $opt{p} = $opt{b};
  $opt{l} .= join('',grep(/[a-z]/, split(//, $opt{b})));
}
elsif ($opt{x}) {
  exec('fgrep', '-x', $opt{x}, $word_file);
}

# -p by itself: just punt to pcregrep
if ($opt{p} && !$opt{l}) {
  exec('pcregrep', $opt{p}, $word_file) unless -t STDOUT;
  exec('pcregrep ' . quotemeta($opt{p}) . ' ' . quotemeta($word_file) . '|' .
       ($ENV{PAGER} || 'less'));
  exit;
}

# preprocess input
my $orig_letters = lc($opt{l});
$orig_letters .= '.' if $opt{s}; # add an implicit . for -s

# find words based on this
my %out = %{find_words($orig_letters)};

# various sorting options
my @out = map { capitalize_word($_, $out{$_}) } keys %out;
if ($opt{t}) {
  @out = sort_scored(grep { !$opt{p} || /$opt{p}/oi } @out);
}
elsif ($opt{s}) {
  @out = sort { lc($a) cmp lc($b) } @out;
}
else {
  @out = map { substr($_, 2) } sort { lc($a) cmp lc($b) }
         map { sprintf('%02d%s', 99 - length($_), $_) } @out;
}

# output
my $left = $opt{a} ? -1 : 10;
for my $word (@out) {
  next if !$opt{t} && $opt{p} && $word !~ /$opt{p}/oi;
  last unless $left--; 

  print(length($word), ' ') unless $opt{s} || $opt{t};

  $word =~ s/[A-Z]/\e[1m\l$&\e[0m/g unless $opt{c};
  print "$word\n";
}

exit;

# functions
sub crawl_trie {
  my ($letters, $tiles, $ptr, $out, $depth) = @_;

  $depth ||= 0;

  # can we use the cache?
  unless (exists $ptr->{off}) {
    while ($letters) { 
      my $char = substr($letters, 0, 1, '');
      if (my $cptr = $ptr->{$char}) {
        seek($trie_fh, $cptr->{off}, SEEK_SET) if $cptr->{off};
        crawl_trie($letters, $tiles, $cptr, $out, $depth+1);
      }
    }
    return;
  }

  # add any words we've found
  read($trie_fh, my $ans_bytes, 1);
  if ($ans_bytes = unpack('C', $ans_bytes)) {
    read($trie_fh, my $answers, $ans_bytes);
    for my $word (split(/,/, $answers)) {
      last if $opt{s} && $depth != length($orig_letters);
      $out->{$word} = $tiles;
    }
  }

  # -s optimization
  return if $opt{s} && $depth >= length($orig_letters);

  # traverse the list of children
  my %matches;
  while (1) {
    # read in letter or null
    read($trie_fh, my $char, 1);
    last if $char eq "\x00"; # null: we've reached the end of this level's chars

    # read in offset corresponding w/ letter
    read($trie_fh, my $off,  4);
    $off = unpack('N', $off);

    # cache the offset
    $ptr->{$char}{off} = $off;

    # see if this letter we've collected is in our search string
    my $i = index($letters, $char);

    # if so, remember it for our visit list 
    # (but first finish this level to minimize seeks)
    $matches{$char} = $i if $i >= 0;
  }

  # visit the children
  for my $char (sort keys %matches) {
    seek($trie_fh, $ptr->{$char}{off}, SEEK_SET);
    crawl_trie(substr($letters, $matches{$char} + 1), 
      $tiles, $ptr->{$char}, $out, $depth+1);
  }

  # we've collected all of the data for this level; we don't need the offset
  delete $ptr->{off};
}

sub sort_letters {
  my ($letters) = @_;
  join('', sort(split(//, lc($letters))));
}

sub score {
  my ($word) = @_;

  my $t = 0;
  $t += ($points{$_} || 0) for grep(/[a-z]/i, split(//, $word));
  $t;
}

sub capitalize_word {
  my ($word, $tiles) = @_;

  # FIXME
  for my $sub ($tiles =~ /([A-Z])/g) {
    $word =~ s/\l$sub/$sub/;
  }
  $word;
}

sub usage {
  die <<EOF
usage: $prog [-p pattern] [-l letters [-s]] [-a] [-t]
       $prog -b pattern -l letters [-a] [-t]
       $prog -r word -l letters [-t] [-v]
       $prog -x word
       $prog -g visible-letters
       -p: perl syntax pattern to filter on
       -t: order by points (descending) instead of default word length/alpha
       -b: like -p, but specify that these are board letters, and add them
           to your -l list
       -x: exact string to filter on (-x foo == -p '^foo\$')
       -l: your letters; use . for each blank
       -s: find words that, given one additional letter, would use all letters
           (implies -a)
       -a: all words, not just top 10 longest; paged if to tty
       -c: show blanks with capital letters instead of default bold
       -g: figure out what tiles are left in the bag, given those on the board
       -r: find the maximal parallels to word using your letters
       -v: specify the word for -r is vertical (just for terminology)
    (you must specify at least one of -x, -p, or -l; otherwise just use cat(1))
EOF
}

sub find_words {
  my ($letters) = @_;

  my %out;
  my @inputs = ( $letters );

  # expand list for .s
  while (1) {
    my %new;
    for my $letts (@inputs) {
      if ($letts =~ /\./) {
        # substitute w/ capital letter to indicate a replacement
        $new{sort_letters($_)} = $_ 
          for map { my $s = $letts; $s =~ s/\./$_/; $s } 'A'..'Z';
      }
      else {
        $new{sort_letters($letts)} = $letts;
      }
    }
    my @new = values %new;
    last if @new == @inputs;
    @inputs = @new;
  }

  # look up all the words
  for my $letts (@inputs) {
    seek($trie_fh, 0, SEEK_SET);
    crawl_trie(sort_letters($letts), $letts, \%trie, \%out);
  }

  wantarray() ? keys %out : \%out;
}

sub find_parallels {
  my ($word, $letters) = @_;

  my $len     = length($word);
  my $ulchars = join('', uniq split(//, $letters));
  my @wchars  = split //, $word;
  my %terms   = (
    rb => $opt{v} ? 'right' : 'below',
    la => $opt{v} ? 'left'  : 'above',
  );

  # find all words i can make with my letters and nothing else
  my @words = find_words($letters);

  # find all two letter words using our letters and 1 from the word
  my %two;
  for my $char (@wchars) {
    $two{la}{$char} = join('',
      map { substr($_, 0, 1) } grep(/^[$ulchars]$char$/i,   @two_letter));
    $two{rb}{$char}  = join('', 
      map { substr($_, 1)    } grep(/^${char}[$ulchars]$/i, @two_letter)); 
  }

  # generate all of the possible sequences we can spell over
  my @seqs = ([0], [$len-1]);
  for my $start (0..($len-2)) {
    for my $end (($start+1)..($len-1)) {
      push(@seqs, [$start..$end]);
    }
  }

  # find matching words
  for my $which (qw(la rb)) {
    my @matches;

    for my $seq (@seqs) {
      my @pos = @$seq;

      my $re = join('', map { "[$two{$which}{$wchars[$_]}]" } @pos);
      next if $re =~ /\[\]/;  # something that doesn't match

      # anchor appropriately
      $re = "^$re" unless $pos[0]  == 0;
      $re .= '$'   unless $pos[-1] == ($len-1);

      for my $m (grep(/$re/i, @words)) {
        my $lm = length($m);
        my $start = $pos[0];   # default: the match starts at beginning of re
        if (@pos == $len) {    # the match = or exceeds word; find out where
          push(@matches, "$m [" . -length($`) . ']') while $m =~ /$re/ig;
          next;
        }
        elsif ($pos[0] == 0) { # the match starts before the word
          $start = @pos - $lm;
        }
        push(@matches, "$m [$start]");
      }
    }

    next unless @matches;

    @matches = $opt{t} 
             ? sort_scored(@matches)
             : sort sort_brackets @matches;

    print "$terms{$which}:\n";
    print "  $_\n" for @matches;
  }
}

sub sort_brackets {
  $a =~ /-?\d+/;
  my $na = $&;
  $b =~ /-?\d+/;
  my $nb = $&;
  $na <=> $nb;
}

sub sort_scored {
  map { "$_->[1] $_->[2]" } sort { lc($a->[0]) cmp lc($b->[0]) }
         map { my $s = score($_); [ sprintf('%03d%s', 999 - $s, $_), $s, $_ ] 
      } @_;
}
