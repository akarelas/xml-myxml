use strict;
use warnings;
use utf8;

use Test::More;

use XML::MyXML qw(:all);

my $obj = xml_to_object('<a>0</a>');
is $obj->text, '0', '0 in text';

my $foo = simple_to_xml {
    foo => {
        '!as_is' => '<g>123</g>',
    },
};
is $foo, '<foo><g>123</g></foo>', '!as_is';

done_testing;
