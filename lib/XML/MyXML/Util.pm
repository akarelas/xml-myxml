package XML::MyXML::Util;

use strict;
use warnings;

require Exporter;
our @ISA = ('Exporter');
our @EXPORT_OK = qw/ trim /;

sub trim {
    my $string = shift;

    if (defined $string) {
        $string =~ s/^\s+//;
        $string =~ s/\s+$//;
    }

    return $string;
}

1;
