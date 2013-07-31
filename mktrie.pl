#!/usr/bin/perl

use strict;
use warnings;
use Data::Dumper;

my %trie;

print "building \%trie\n";
while (<>) {
  chomp;
  my $word    = lc($_);
  my $ptr     = \%trie;
  my @letters = sort(split(//, $word));
  for my $char (@letters) {
    $ptr = $ptr->{$char} ||= {};
  }
  push(@{$ptr->{'.'}}, $word);
}

print "calculating offsets\n";
calc(\%trie);

print "writing data\n";
open(my $fh, '>', 'twl06.trie');
output(\%trie);
close($fh);

sub output {
  my ($ptr) = @_;

  # write out answers if this is a stop location
  my $len = length($ptr->{'.'});
  syswrite($fh, pack('C', $len));
  syswrite($fh, $ptr->{'.'}) if $len;

  my @chars = sort grep /^[a-z]$/, keys %$ptr;

  for my $char (@chars) {
    syswrite($fh, $char);
    syswrite($fh, pack('N', $ptr->{$char}{off}));
  }
  syswrite($fh, "\x00");

  for my $char (@chars) {
    output($ptr->{$char});
  }
}

sub calc {
  my ($ptr, $off) = @_;

  $off ||= 0;

  $ptr->{'.'} = join(',', @{$ptr->{'.'} || []});
  my $len = length($ptr->{'.'});

  my @chars = sort grep /^[a-z]$/, keys %$ptr;

  # answers len + answers + chars len + stop
  $off += 1 + $len + 5 * @chars + 1;

  for my $char (@chars) {
    $ptr->{$char}{off} = $off;
    $off = calc($ptr->{$char}, $off);
  }

  return $off;
}

__END__

seat
sea
tofu
teat

{
  'a' => {
    'e' => {
      's' => {
        '.' => 1,
        't' => {
          '.' => 1
        }
      },
      't' => {
        't' => {
          '.' => 1
        }
      }
    }
  },
  'f' => {
    'o' => {
      't' => {
        'u' => {
          '.' => 1
        }
      }
    }
  }
}

