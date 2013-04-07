#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;

use File::Temp qw/ tempfile /;

use XML::MyXML qw(:all);

my $xml = "<item><name>Table</name><price><usd>10.00</usd><eur>8.50</eur></price></item>";
my $simple = xml_to_simple($xml);

cmp_deeply($simple, {
	item => {
		name => 'Table',
		price => {
			usd => '10.00',
			eur => '8.50',
		},
	},
}, 'xml_to_simple ok');

my $obj = xml_to_object($xml);
is($obj->path('price/eur')->value, '8.50', 'xml_to_object & path & value ok');

$simple = {
	item => [
		name => 'Table',
		price => [
			usd => '10.00',
			eur => '8.50',
		],
	],
};

my $xml2 = simple_to_xml($simple);
is($xml2, $xml, 'simple_to_xml ok');

$obj->delete;
($obj, $xml2) = ();

is($xml, "<item><name>Table</name><price><usd>10.00</usd><eur>8.50</eur></price></item>", '$xml is unchanged');

my ($thatfh1, $filename1) = tempfile('myxml-XXXXXXXX', TMPDIR => 1, UNLINK => 1);
my ($thatfh2, $filename2) = tempfile('myxml-XXXXXXXX', TMPDIR => 1, UNLINK => 1);
close $thatfh1;
close $thatfh2;

simple_to_xml($simple, { save => $filename1 });
my $test_smp = xml_to_simple($filename1, { file => 1 });
cmp_deeply($test_smp, {
	item => {
		name => 'Table',
		price => {
			usd => '10.00',
			eur => '8.50',
		},
	},
}, 'simple_to_xml (save) and xml_to_simple (file) ok');


done_testing();
