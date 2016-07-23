use strict;
use warnings;
use utf8;

use Test::More;

use Encode;
use File::Temp qw/ tempfile /;

use XML::MyXML qw(:all);

my $xml = "<(ng-something)><eur>10</eur><usd>8</usd></(ng-something)>";
my $simple = xml_to_simple($xml);

is_deeply($simple, {
	'(ng-something)' => {
		eur => 10,
		usd => 8,
	}
}, 'xml_to_simple, tagname with symbols');

$xml = "<item><name>Τραπέζι</name><price><usd>10.00</usd><eur>8.50</eur></price></item>";
$simple = xml_to_simple($xml);

is_deeply($simple, {
	item => {
		name => 'Τραπέζι',
		price => {
			usd => '10.00',
			eur => '8.50',
		},
	},
}, 'xml_to_simple');

my $obj = xml_to_object($xml);
is($obj->path('price/eur')->value, '8.50', 'xml_to_object & path & value');
is($obj->path('name')->value, 'Τραπέζι', 'value wide-characters');

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
is($xml2, $xml, 'simple_to_xml');

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
is($tidy_xml, $correct_tidy_xml, 'tidy with wide-characters works well');

($obj, $xml2) = ();

is($xml, "<item><name>Τραπέζι</name><price><usd>10.00</usd><eur>8.50</eur></price></item>", '$xml is unchanged');

my ($thatfh1, $filename1) = tempfile('myxml-XXXXXXXX', TMPDIR => 1, UNLINK => 1);
close $thatfh1;

simple_to_xml($simple, { save => $filename1 });
my $test_smp = xml_to_simple($filename1, { file => 1 });
is_deeply($test_smp, {
	item => {
		name => 'Τραπέζι',
		price => {
			usd => '10.00',
			eur => '8.50',
		},
	},
}, 'simple_to_xml (save) and xml_to_simple (file)');

# TEST NO-STRIPNS TAG
$xml = "<school:μαθητής>Peter</school:μαθητής>";
$obj = xml_to_object($xml);
is($obj->tag, 'school:μαθητής', 'tag not stripped_ns 1');
is($obj->tag({ strip_ns => 0 }), 'school:μαθητής', 'tag not stripped_ns 2');
is($obj->tag({ strip_ns => 1 }), 'μαθητής', 'tag stripped_ns');

# TEST STRIP_NS XML_TO_SIMPLE
$simple = xml_to_simple($xml, { strip_ns => 1 });
is_deeply($simple, {
	'μαθητής' => 'Peter',
}, 'xml_to_simple with strip_ns');
$simple = xml_to_simple($xml);
is_deeply($simple, {
	'school:μαθητής' => 'Peter',
}, 'xml_to_simple without strip_ns');

# TEST QUICK-CLOSE
$simple = { person => { name => undef } };
is(simple_to_xml($simple), '<person><name/></person>', 'quick close worked 1');
$simple = { person => { name => '' } };
is(simple_to_xml($simple), '<person><name/></person>', 'quick close worked 2');
$simple = { person => { name => 'Alex' } };
is(simple_to_xml($simple), '<person><name>Alex</name></person>', 'slow close worked');

# TEST VIEW/CHANGE ATTRS
note 'test view/change attrs';
$xml = '<people><person όνομα="γιώργος"><spouse>Maria</spouse></person></people>';
$obj = xml_to_object($xml);
is($obj->path('person')->attr('όνομα'), 'γιώργος', 'view 1');
is($obj->path('person')->attr('name2'), undef, 'view 2');
$obj->path('person')->attr('όνομα', 'πέτρος');
is($obj->to_xml, '<people><person όνομα="πέτρος"><spouse>Maria</spouse></person></people>', 'change 1');
$obj->path('person')->attr('όνομα', undef);
is($obj->to_xml, '<people><person><spouse>Maria</spouse></person></people>', 'change 2');

# XML_ESCAPE
my $string = '<"άλ&εξ\'>';
is(xml_escape($string), '&lt;&quot;άλ&amp;εξ&apos;&gt;', 'xml string escaped');

# WRONG UTF-8 PRODUCES ERROR
$xml = '<person><name>Γιώργος</name></person>';
$obj = eval { xml_to_object($xml, { bytes => 1 }) };
ok( $@, 'error occured because of wrong UTF-8' );

# CHECK_XML
ok( check_xml('<person/>'), 'check_xml 1' );
ok( ! check_xml('<person>'), 'check_xml 2' );

# CHECK WEAKENED REFS
note 'checking weakened refs';
my ($ch1, $ch2);
{
	$xml = '<items><item>Table</item><item>Chair</item></items>';
	$obj = xml_to_object($xml);
	($ch1, $ch2) = $obj->path('item');
}
is($ch1->to_xml, '<item>Table</item>', 'item1');
is($ch2->to_xml, '<item>Chair</item>', 'item2');

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
is_deeply($simple, {
	author => 'Alex',
	copy => 'Alex',
}, 'matching entities');

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
			<teacher class="High ] C">
				<name>
					<first>Barbara</first>
					<last>Mullins</last>
				</name>
			</teacher>
		</people>
EOB
	my $obj = xml_to_object($xml);
	my @people1 = map $_->simplify({internal => 1}), $obj->path('student');
	my @people2 = map $_->simplify({internal => 1}), $obj->path('/people/student');
	is_deeply(\@people1, [
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
	], 'people1');
	is_deeply(\@people2, \@people1, 'people2');
	@people1 = map $_->simplify, $obj->path('student[class=A]');
	@people2 = map $_->simplify, $obj->path('/people/student[class=A]');
	my @people3 = map $_->simplify, $obj->path('student[class="A"]');
	is_deeply(\@people1, [
		{
			student => {
				name => {
					first => 'John',
					last => 'Doe',
				},
			},
		},
	], 'people1 2');
	is_deeply(\@people2, \@people1, 'people2 2');
	is_deeply(\@people3, \@people1, 'quotes in attr values');
	@people1 = map $_->simplify, $obj->path('/peoples/student');
	is_deeply(\@people1, [], 'paths first element compares ok');
	is($obj->path('/people')->tag, 'people', 'identity path');
	is($obj->path('/')->tag, 'people', 'identity path 2');
	my @names_a = map $_->value, $obj->path('/people/[class=A]/name/first');
	is_deeply(\@names_a, ['John', 'Mary', 'Peter'], 'multiple deep paths');
	my $special = $obj->path('teacher[class="High ] C"]/name/first')->value;
	is($special, 'Barbara', 'closing square bracket in attr value');
}

# BYTES FLAG
note 'bytes flag';
$xml = <<EOB;
<ατομο><ονομα>Γιώργος</ονομα></ατομο>
EOB
$obj = xml_to_object(encode_utf8($xml), { bytes => 1 });
is($obj->path('/ατομο/ονομα')->value, 'Γιώργος', 'xml_to_object & path & value from UTF-8 doc');
is($obj->to_xml, '<ατομο><ονομα>Γιώργος</ονομα></ατομο>', 'to_xml without bytes flag');
is($obj->to_xml({bytes => 1}), encode_utf8('<ατομο><ονομα>Γιώργος</ονομα></ατομο>'), 'to_xml with bytes flag');
$tidy_xml = <<EOB;
<ατομο>
	<ονομα>Γιώργος</ονομα>
</ατομο>
EOB
is($obj->to_xml({bytes => 1, tidy => 1}), encode_utf8($tidy_xml), 'to_xml with bytes and tidy flags');
is($obj->to_tidy_xml({bytes => 1}), encode_utf8($tidy_xml), 'to_tidy_xml with bytes flag');

# PARENT
note 'parent';
is($obj->path('ονομα')->parent, $obj, 'childs parent == identity');
is($obj->parent, undef, 'top parent == undef');


done_testing();
