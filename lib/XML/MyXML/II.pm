package XML::MyXML::II;

use strict;
use warnings;

use XML::MyXML qw();

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = @XML::MyXML::EXPORT_OK;
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

foreach my $func (@EXPORT_OK) {
	no strict "refs";

	*$func = sub {
		my @args = @_;
		&{ "XML::MyXML::$func" }( @args );
	};
}


1;
