#!/usr/bin/env perl

use strict;
use warnings;
use utf8;

use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More;
use Test::Deep;

use Encode;
use File::Temp qw/ tempfile /;

use XML::MyXML qw(:all);

my $xml = encode_utf8("<item><name>Τραπέζι</name><price><usd>10.00</usd><eur>8.50</eur></price></item>");
my $simple = xml_to_simple($xml);

cmp_deeply($simple, {
	item => {
		name => 'Τραπέζι',
		price => {
			usd => '10.00',
			eur => '8.50',
		},
	},
}, 'xml_to_simple ok');

my $obj = xml_to_object($xml);
is($obj->path('price/eur')->value, '8.50', 'xml_to_object & path & value ok');
is($obj->path('name')->value, 'Τραπέζι', 'value wide-characters ok');

$simple = {
	item => [
		name => 'Τραπέζι',
		price => [
			usd => '10.00',
			eur => '8.50',
		],
	],
};

my $xml2 = simple_to_xml($simple);
is($xml2, $xml, 'simple_to_xml ok');

my $tidy_xml = $obj->to_xml({ tidy => 1, indentstring => '  ' });
my $correct_tidy_xml = <<'EOB';
<item>
  <name>Τραπέζι</name>
  <price>
    <usd>10.00</usd>
    <eur>8.50</eur>
  </price>
</item>
EOB
is($tidy_xml, encode_utf8($correct_tidy_xml), 'tidy with wide-characters works well');

($obj, $xml2) = ();

is($xml, encode_utf8("<item><name>Τραπέζι</name><price><usd>10.00</usd><eur>8.50</eur></price></item>"), '$xml is unchanged');

my ($thatfh1, $filename1) = tempfile('myxml-XXXXXXXX', TMPDIR => 1, UNLINK => 1);
my ($thatfh2, $filename2) = tempfile('myxml-XXXXXXXX', TMPDIR => 1, UNLINK => 1);
close $thatfh1;
close $thatfh2;

simple_to_xml($simple, { save => $filename1 });
my $test_smp = xml_to_simple($filename1, { file => 1 });
cmp_deeply($test_smp, {
	item => {
		name => 'Τραπέζι',
		price => {
			usd => '10.00',
			eur => '8.50',
		},
	},
}, 'simple_to_xml (save) and xml_to_simple (file) ok');

# TEST NO-STRIPNS TAG
$xml = encode_utf8("<school:μαθητής>Peter</school:μαθητής>");
$obj = xml_to_object($xml);
is($obj->tag, 'school:μαθητής', 'tag not stripped_ns ok 1');
is($obj->tag({ strip_ns => 0 }), 'school:μαθητής', 'tag not stripped_ns ok 2');
is($obj->tag({ strip_ns => 1 }), 'μαθητής', 'tag stripped_ns ok');

# TEST STRIP_NS XML_TO_SIMPLE
$simple = xml_to_simple($xml, { strip_ns => 1 });
cmp_deeply($simple, {
	'μαθητής' => 'Peter',
}, 'xml_to_simple with strip_ns ok');
$simple = xml_to_simple($xml);
cmp_deeply($simple, {
	'school:μαθητής' => 'Peter',
}, 'xml_to_simple without strip_ns ok');

# TEST QUICK-CLOSE
$simple = { person => { name => undef } };
is(simple_to_xml($simple), '<person><name/></person>', 'quick close worked ok 1');
$simple = { person => { name => '' } };
is(simple_to_xml($simple), '<person><name/></person>', 'quick close worked ok 2');
$simple = { person => { name => 'Alex' } };
is(simple_to_xml($simple), '<person><name>Alex</name></person>', 'slow close worked ok');

# TEST VIEW/CHANGE ATTRS
note 'test view/change attrs';
$xml = encode_utf8('<people><person όνομα="γιώργος"><spouse>Maria</spouse></person></people>');
$obj = xml_to_object($xml);
is($obj->path('person')->attr('όνομα'), 'γιώργος', 'view ok 1');
is($obj->path('person')->attr('name2'), undef, 'view ok 2');
$obj->path('person')->attr('όνομα', 'πέτρος');
is($obj->to_xml, encode_utf8('<people><person όνομα="πέτρος"><spouse>Maria</spouse></person></people>'), 'change ok 1');
$obj->path('person')->attr('όνομα', undef);
is($obj->to_xml, '<people><person><spouse>Maria</spouse></person></people>', 'change ok 2');

# XML_ESCAPE
my $string = '<"άλ&εξ\'>';
is(xml_escape($string), '&lt;&quot;άλ&amp;εξ&apos;&gt;', 'xml string escaped okay');

# WRONG UTF-8 PRODUCES ERROR
$xml = '<person><name>Γιώργος</name></person>';
$obj = eval { xml_to_object($xml) };
ok( $@, 'error occured because of wrong UTF-8' );

# CHECK_XML
ok( check_xml('<person/>'), 'check_xml ok 1' );
ok( ! check_xml('<person>'), 'check_xml ok 2' );

# CHECK WEAKENED REFS
note 'checking weakened refs';
my ($ch1, $ch2);
{
	$xml = '<items><item>Table</item><item>Chair</item></items>';
	$obj = xml_to_object($xml);
	($ch1, $ch2) = $obj->path('item');
}
is($ch1->to_xml, '<item>Table</item>', 'item1 ok');
is($ch2->to_xml, '<item>Chair</item>', 'item2 ok');

# CHECK DOUBLE-DECODING BUG
is(XML::MyXML::_decode('&#x26;#65;'), '&#65;', 'double-decoding not occurring');

# TWO MATCHING ENTITIES
$xml = <<'EOB';
<!ENTITY copyright "Alex">
<!ENTITY author "Alex">
<person>
	<author>&author;</author>
	<copy>&copyright;</copy>
</person>
EOB
$simple = xml_to_simple($xml, {internal => 1});
cmp_deeply($simple, {
	author => 'Alex',
	copy => 'Alex',
}, 'matching entities ok');

# PATH TESTS
note 'path tests';
{
	$xml = <<'EOB';
		<people>
			<student class="B">
				<name>
					<first>Alex</first>
					<last>Karelas</last>
				</name>
			</student>
			<student class="A">
				<name>
					<first>John</first>
					<last>Doe</last>
				</name>
			</student>
			<teacher class="A">
				<name>
					<first>Mary</first>
					<last>Poppins</last>
				</name>
			</teacher>
			<teacher class="A">
				<name>
					<first>Peter</first>
					<last>Gabriel</last>
				</name>
			</teacher>
		</people>
EOB
	my $obj = xml_to_object($xml);
	my @people1 = map $_->simplify({internal => 1}), $obj->path('student');
	my @people2 = map $_->simplify({internal => 1}), $obj->path('/people/student');
	cmp_deeply(\@people1, [
		{
			name => {
				first => 'Alex',
				last => 'Karelas',
			},
		},
		{
			name => {
				first => 'John',
				last => 'Doe',
			},
		},
	], 'people1 ok');
	cmp_deeply(\@people2, \@people1, 'people2 ok');
	@people1 = map $_->simplify, $obj->path('student[class=A]');
	@people2 = map $_->simplify, $obj->path('/people/student[class=A]');
	cmp_deeply(\@people1, [
		{
			student => {
				name => {
					first => 'John',
					last => 'Doe',
				},
			},
		},
	], 'people1 ok 2');
	cmp_deeply(\@people2, \@people1, 'people2 ok 2');
	@people1 = map $_->simplify, $obj->path('/peoples/student');
	cmp_deeply(\@people1, [], 'paths first element compares ok');
}




done_testing();
