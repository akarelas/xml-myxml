#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use Encode;
use FindBin qw($Bin);
use lib "$Bin/../lib";

use Test::More tests => 50;
use Test::Deep;

use XML::MyXML qw(:all);

sub parse_binary
{
	my ($str) = @_;
	my $xml = "<item><a><b>$str</b></a></item>";
	my $obj = xml_to_object($xml);
	$obj->path('a/b')->value;
}

# should work for Latin1, plain ASCII-7bit strings and Wide strings
for ("\xB5", "\xDF", "test\xB5", "plain ascii", "тест") {
	my $s = encode("UTF-8", $_);

	my $su = $s; # s, upgraded
	utf8::upgrade($su);

	my $sd = $s; # s, downgraded
	utf8::downgrade($sd);

	is $su, $s;
	is $sd, $s;
	is $su, $sd, "assume \$su and \$sd are equal binary strings";

	my ($su_bit, $su_orig) = (utf8::is_utf8($su), $su);
	my $xu = parse_binary($su);
	is utf8::is_utf8($su), $su_bit, "should not modify arguments in any way";
	is $su, $su_orig, "should not modify arguments in any way";

	my ($sd_bit, $sd_orig) = (utf8::is_utf8($sd), $sd);
	my $xd = parse_binary($sd);
	is utf8::is_utf8($sd), $sd_bit, "should not modify arguments in any way";
	is $sd, $sd_orig, "should not modify arguments in any way";

	is $xu, $su;
	is $xd, $sd;
	is $xu, $xd, "so xml output for both \$su and \$sd should be equal too";
}
