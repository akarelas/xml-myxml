#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use Test::Deep;

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

done_testing();
