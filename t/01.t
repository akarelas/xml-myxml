#!/usr/bin/env perl

use strict;
use warnings;

use FindBin qw($Bin);
use lib "$Bin/../lib";

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

# TEST NO-STRIPNS TAG
$xml = "<school:student>Peter</school:student>";
$obj = xml_to_object($xml);
is($obj->tag, 'student', 'tag stripped_ns ok');
is($obj->tag({ strip_ns => 0 }), 'school:student', 'tag not stripped_ns ok');

# TEST QUICK-CLOSE
$simple = { person => { name => undef } };
is(simple_to_xml($simple), '<person><name/></person>', 'quick close worked ok 1');
$simple = { person => { name => '' } };
is(simple_to_xml($simple), '<person><name/></person>', 'quick close worked ok 2');
$simple = { person => { name => 'Alex' } };
is(simple_to_xml($simple), '<person><name>Alex</name></person>', 'slow close worked ok');

# TEST VIEW/CHANGE ATTRS
note 'test view/change attrs';
$xml = '<people><person name="george"><spouse>Maria</spouse></person></people>';
$obj = xml_to_object($xml);
is($obj->path('person')->attr('name'), 'george', 'view ok 1');
is($obj->path('person')->attr('name2'), undef, 'view ok 2');
$obj->path('person')->attr('name', 'peter');
is($obj->to_xml, '<people><person name="peter"><spouse>Maria</spouse></person></people>', 'change ok 1');
$obj->path('person')->attr('name', undef);
is($obj->to_xml, '<people><person><spouse>Maria</spouse></person></people>', 'change ok 2');

# XML_ESCAPE
my $string = '<"al&ex\'>';
is(xml_escape($string), '&lt;&quot;al&amp;ex&apos;&gt;', 'xml string escaped okay');


done_testing();
