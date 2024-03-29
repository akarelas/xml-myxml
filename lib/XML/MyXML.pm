package XML::MyXML;

use 5.008001;
use strict;
use warnings;

use XML::MyXML::Object;
use XML::MyXML::Util 'trim', 'strip_ns';

use Encode;
use Carp;
use Scalar::Util 'weaken';

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(tidy_xml object_to_xml xml_to_object simple_to_xml xml_to_simple check_xml xml_escape);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);

our $VERSION = "1.08";

my $DEFAULT_INDENTSTRING = ' ' x 4;


=encoding utf-8

=head1 NAME

XML::MyXML - A simple-to-use XML module, for parsing and creating XML documents

=head1 SYNOPSIS

    use XML::MyXML qw(tidy_xml xml_to_object);
    use XML::MyXML qw(:all);

    my $xml = "<item><name>Table</name><price><usd>10.00</usd><eur>8.50</eur></price></item>";
    print tidy_xml($xml);

    my $obj = xml_to_object($xml);
    print "Price in Euros = " . $obj->path('price/eur')->text;

    $obj->simplify is hashref { item => { name => 'Table', price => { usd => '10.00', eur => '8.50' } } }
    $obj->simplify({ internal => 1 }) is hashref { name => 'Table', price => { usd => '10.00', eur => '8.50' } }

=head1 EXPORTABLE

xml_escape, tidy_xml, xml_to_object, object_to_xml, simple_to_xml, xml_to_simple, check_xml

=head1 FEATURES & LIMITATIONS

This module can parse XML comments, CDATA sections, XML entities (the standard five and numeric ones) and
simple non-recursive C<< <!ENTITY> >>s

It will ignore (won't parse) C<< <!DOCTYPE...> >>, C<< <?...?> >> and other C<< <!...> >> special markup

All strings (XML documents, attribute names, values, etc) produced by this module or passed as parameters
to its functions, are strings that contain characters, rather than bytes/octets. Unless you use the C<bytes>
function flag (see below), in which case the XML documents (and just the XML documents) will be byte/octet
strings.

XML documents to be parsed may not contain the C<< > >> character unencoded in attribute values

=head1 OPTIONAL FUNCTION FLAGS

Some functions and methods in this module accept optional flags, listed under each function in the
documentation. They are optional, default to zero unless stated otherwise, and can be used as follows:
S<C<< function_name( $param1, { flag1 => 1, flag2 => 1 } ) >>>. This is what each flag does:

C<strip> : the function will strip initial and ending whitespace from all text values returned

C<file> : the function will expect the path to a file containing an XML document to parse, instead of an
XML string

C<complete> : the function's XML output will include an XML declaration (C<< <?xml ... ?>  >>) in the
beginning

C<internal> : the function will only return the contents of an element in a hashref instead of the
element itself (see L</SYNOPSIS> for example)

C<tidy> : the function will return tidy XML

C<indentstring> : when producing tidy XML, this denotes the string with which child elements will be
indented (Default is a string of 4 spaces)

C<save> : the function (apart from doing what it's supposed to do) will also save its XML output in a
file whose path is denoted by this flag

C<strip_ns> : strip the namespaces (characters up to and including ':') from the tags

C<xslt> : will add a <?xml-stylesheet?> link in the XML that's being output, of type 'text/xsl',
pointing to the filename or URL denoted by this flag

C<arrayref> : the function will create a simple arrayref instead of a simple hashref (which will preserve
order and elements with duplicate tags)

C<bytes> : the XML document string which is parsed and/or produced by this function, should contain
bytes/octets rather than characters

=head1 FUNCTIONS

=cut

sub _encode {
    my $string = shift;
    defined $string or $string = '';
    my %replace =   (
                    '<' => '&lt;',
                    '>' => '&gt;',
                    '&' => '&amp;',
                    '\'' => '&apos;',
                    '"' => '&quot;',
                    );
    my $keys = "(".join("|", sort {length($b) <=> length($a)} keys %replace).")";
    $string =~ s/$keys/$replace{$1}/g;
    return $string;
}


=head2 xml_escape($string)

Returns the same string, but with the C<< < >>, C<< > >>, C<< & >>, C<< " >> and C<< ' >> characters
replaced by their XML entities (e.g. C<< &amp; >>).

=cut

sub xml_escape {
    my ($string) = @_;

    return _encode($string);
}

sub _decode {
    my $string = shift;
    my $entities = shift || {};
    my $flags = shift || {};
    defined $string or $string = '';
    my %replace = (
        %$entities,
        '&lt;'   => '<',
        '&gt;'   => '>',
        '&amp;'  => '&',
        '&apos;' => "'",
        '&quot;' => '"',
    );
    my @capture = map quotemeta, keys %replace;
    push @capture, '\&\#x([0-9A-Fa-f]+)\;', '\&\#([0-9]+)\;';
    my $capture = "(".join("|", @capture).")";
    $string =~ s|
        $capture
    |
        my $reference = $1;
        my $number = $2;
        $reference =~ /\&\#x/ ? chr(hex($number))
            : $reference =~ /\&\#/ ? chr($number)
            : $replace{$reference};
    |gex;
    return $string;
}


=head2 tidy_xml($raw_xml)

Returns the XML string in a tidy format (with tabs & newlines)

Optional flags: C<file>, C<complete>, C<indentstring>, C<save>, C<bytes>

=cut

sub tidy_xml {
    my $xml = shift;
    my $flags = shift || {};

    my $object = xml_to_object($xml, $flags);
    defined $object or return $object;
    _tidy_object($object, undef, $flags);
    my $return = $object->to_xml({ %$flags, tidy => 0 }) . "\n";
    return $return;
}


=head2 xml_to_object($raw_xml)

Creates an 'XML::MyXML::Object' object from the raw XML provided

Optional flags: C<file>, C<bytes>

=cut

sub xml_to_object {
    my $xml = shift;
    my $flags = shift || {};

    if ($flags->{file}) {
        open my $fh, '<', $xml or croak "Error: The file '$xml' could not be opened for reading: $!";
        $xml = do { local $/; <$fh> };
        close $fh;
    }

    if ($flags->{bytes} or $flags->{file}) {
        my (undef, undef, $encoding) = $xml =~ /<\?xml(\s[^>]+)?\sencoding=(['"])(.*?)\2/;
        $encoding = 'UTF-8' if ! defined $encoding or $encoding =~ /^utf\-?8\z/i;
        my $encoding_obj = find_encoding($encoding) or croak "Error: encoding '$encoding' not found";
        eval { $xml = $encoding_obj->decode($xml, Encode::FB_CROAK); 1 }
            or croak "Error: Input string is invalid $encoding";
    }

    my $entities = {};

    # Parse CDATA sections
    $xml =~ s/\<\!\[CDATA\[(.*?)\]\]\>/_encode($1)/egs;
    my @items = $xml =~ /(<!--.*?(?:-->|$)|<[^>]*?>|[^<>]+)/sg;
    # Remove comments, special markup and initial whitespace
    {
        my $init_ws = 1; # whether we are inside initial whitespace
        foreach my $item (@items) {
            if ($item =~ /\A<!--/) {
                if ($item !~ /-->\z/) { croak encode_utf8("Error: unclosed XML comment block - '$item'"); }
                undef $item;
            } elsif ($item =~ /\A<\?/) { # like <?xml?> or <?target?>
                if ($item !~ /\?>\z/) { croak encode_utf8("Error: Erroneous special markup - '$item'"); }
                undef $item;
            } elsif (my ($entname, undef, $entvalue) = $item =~ /^<!ENTITY\s+(\S+)\s+(['"])(.*?)\2\s*>\z/) {
                $entities->{"&$entname;"} = _decode($entvalue);
                undef $item;
            } elsif ($item =~ /<!/) { # like <!DOCTYPE> or <!ELEMENT> or <!ATTLIST>
                undef $item;
            } elsif ($init_ws) {
                if ($item =~ /\S/) {
                    $init_ws = 0;
                } else {
                    undef $item;
                }
            }
        }
        @items = grep defined, @items or croak "Error: No elements in the XML document";
    }
    my @stack;
    my $object = bless ({
        content      => [],
        full_ns_info => {},
        ns_data      => {},
    }, 'XML::MyXML::Object');
    my $pointer = $object;
    foreach my $item (@items) {
        if ($item =~ /^\<\/?\>\z/) {
            croak encode_utf8("Error: Strange tag: '$item'");
        } elsif ($item =~ /^\<\/([^\s>]+)\>\z/) {
            my ($el_name) = $1;
            $stack[-1]{el_name} eq $el_name
                or croak encode_utf8("Error: Incompatible stack element: stack='$stack[-1]{el_name}' item='$item'");
            my $stack_entry = pop @stack;
            delete $stack_entry->{content} if ! @{$stack_entry->{content}};
            $pointer = $stack_entry->{parent};
        } elsif ($item =~ /^\<[^>]+?(\/)?\>\z/) {
            my $is_self_closing = defined $1;
            my ($el_name) = $item =~ /^<([^\s>\/]+)/;
            defined $el_name or croak encode_utf8("Error: Strange tag: '$item'");
            $item =~ s/^\<\Q$el_name\E//;
            $item =~ s/\/>\z//;
            my @attrs = $item =~ /\s+(\S+=(['"]).*?\2)/g;
            my $i = 0;
            @attrs = grep {++$i % 2} @attrs;
            my %attr;
            foreach my $attr (@attrs) {
                my ($attr_name, undef, $attr_value) = $attr =~ /^(\S+?)=(['"])(.*?)\2\z/;
                defined $attr_name or croak encode_utf8("Error: Strange attribute: '$attr'");
                $attr{$attr_name} = _decode($attr_value, $entities);
            }
            my $entry = bless {
                el_name => $el_name,
                attrs   => \%attr,
                $is_self_closing ? () : (content => []),
                parent  => $pointer,
            }, 'XML::MyXML::Object';
            weaken $entry->{parent};
            $entry->_apply_namespace_declarations;
            push @stack, $entry unless $is_self_closing;
            push @{$pointer->{content}}, $entry;
            $pointer = $entry unless $is_self_closing;
        } elsif ($item =~ /^[^<>]*\z/) {
            my $entry = bless {
                text => _decode($item, $entities),
                parent => $pointer,
            }, 'XML::MyXML::Object';
            weaken $entry->{parent};
            push @{$pointer->{content}}, $entry;
        } else {
            croak encode_utf8("Error: Strange element: '$item'");
        }
    }
    ! @stack or croak encode_utf8("Error: The <$stack[-1]{el_name}> element has not been closed in the XML document");
    $object = $object->{content}[0];
    $object->{parent} = undef;
    return $object;
}

sub _objectarray_to_xml {
    my $object = shift;

    my $xml = '';
    foreach my $stuff (@$object) {
        if (! defined $stuff->{el_name} and defined $stuff->{text}) {
            $xml .= _encode($stuff->{text});
        } else {
            $xml .= "<".$stuff->{el_name};
            foreach my $attrname (keys %{$stuff->{attrs}}) {
                $xml .= " ".$attrname.'="'._encode($stuff->{attrs}{$attrname}).'"';
            }
            if (! defined $stuff->{content} or ! @{ $stuff->{content} }) {
                $xml .= "/>"
            } else {
                $xml .= ">";
                $xml .= _objectarray_to_xml($stuff->{content});
                $xml .= "</".$stuff->{el_name}.">";
            }
        }
    }
    return $xml;
}


=head2 object_to_xml($object)

Creates an XML string from the 'XML::MyXML::Object' object provided

Optional flags: C<complete>, C<tidy>, C<indentstring>, C<save>, C<bytes>

=cut

sub object_to_xml {
    my $object = shift;
    my $flags = shift || {};

    return $object->to_xml( $flags );
}

sub _tidy_object {
    my $object = shift;
    my $tabs = shift || 0;
    my $flags = shift || {};

    my $indentstring = exists $flags->{indentstring} ? $flags->{indentstring} : $DEFAULT_INDENTSTRING;

    return unless defined $object->{content} and @{$object->{content}};
    my $hastext;
    my @children = @{$object->{content}};
    foreach my $i (0..$#children) {
        my $child = $children[$i];
        if (defined $child->{text} and $child->{text} =~ /\S/) {
            $hastext = 1;
            last;
        }
    }
    return if $hastext;

    @{$object->{content}} = grep { ! defined $_->{text} or $_->{text} =~ /\S/ } @{$object->{content}};

    @children = @{$object->{content}};
    $object->{content} = [];
    for my $i (0..$#children) {
        my $whitespace = bless {
            text => "\n".($indentstring x ($tabs+1)),
            parent => $object,
        }, 'XML::MyXML::Object';
        weaken $whitespace->{parent};
        push @{$object->{content}}, $whitespace;
        push @{$object->{content}}, $children[$i];
    }
    my $whitespace = bless {
        text => "\n".($indentstring x $tabs),
        parent => $object,
    }, 'XML::MyXML::Object';
    weaken $whitespace->{parent};
    push @{$object->{content}}, $whitespace;

    for my $i (0..$#{$object->{content}}) {
        _tidy_object($object->{content}[$i], $tabs+1, $flags);
    }
}


=head2 simple_to_xml($simple_array_ref)

Produces a raw XML string from either an array reference, a hash reference or a mixed structure such as these examples:

    { thing => { name => 'John', location => { city => 'New York', country => 'U.S.A.' } } }
    # <thing><name>John</name><location><country>U.S.A.</country><city>New York</city></location></thing>

    [ thing => [ name => 'John', location => [ city => 'New York', country => 'U.S.A.' ] ] ]
    # <thing><name>John</name><location><country>U.S.A.</country><city>New York</city></location></thing>

    { thing => { name => 'John', location => [ city => 'New York', city => 'Boston', country => 'U.S.A.' ] } }
    # <thing><name>John</name><location><city>New York</city><city>Boston</city><country>U.S.A.</country></location></thing>

Here's a mini-tutorial on how to use this function, in which you'll also see how to set attributes.

The simplest invocations are these:

    simple_to_xml({target => undef})
    # <target/>

    simple_to_xml({target => 123})
    # <target>123</target>

Every set of sibling elements (such as the document itself, which is a single top-level element, or a pack of
5 elements all children to the same parent element) is represented in the $simple_array_ref parameter as
key-value pairs inside either a hashref or an arrayref (you can choose which).

Keys represent tags+attributes of the sibling elements, whereas values represent the contents of those elements.

Eg:

    [
        first => 'John',
        last => 'Doe,'
    ]

...and...

    {
        first => 'John',
        last => 'Doe',
    }

both translate to:

    <first>John</first><last>Doe</last>

A value can either be undef (to denote an empty element), or a string (to denote a string), or another
hashref/arrayref to denote a set of children elements, like this:

    {
        person => {
            name => {
                first => 'John',
                last => 'Doe'
            }
        }
    }

...becomes:

    <person>
        <name>
            <first>John</first>
            <last>Doe</last>
        </name>
    </person>


The only difference between using an arrayref or using a hashref, is that arrayrefs preserve the
order of the elements, and allow repetition of identical tags. So a person with many addresses, should choose to
represent its list of addresses under an arrayref, like this:

    {
        person => [
            name => {
                first => 'John',
                last => 'Doe',
            },
            address => {
                country => 'Malta',
            },
            address => {
                country => 'Indonesia',
            },
            address => {
                country => 'China',
            }
        ]
    }

...which becomes:

    <person>
        <name>
            <last>Doe</last>
            <first>John</first>
        </name>
        <address>
            <country>Malta</country>
        </address>
        <address>
            <country>Indonesia</country>
        </address>
        <address>
            <country>China</country>
        </address>
    </person>

Finally, to set attributes to your elements (eg id="12") you need to replace the key with either
a string containing attributes as well (eg: C<'address id="12"'>), or replace it with a reference, as the many
items in the examples below:

    {thing => [
        'item id="1"' => 'chair',
        [item => {id => 2}] => 'table',
        [item => [id => 3]] => 'door',
        [item => id => 4] => 'sofa',
        {item => {id => 5}} => 'bed',
        {item => [id => 6]} => 'shirt',
        [item => {id => 7, other => 8}, [more => 9, also => 10, but_not => undef]] => 'towel'
    ]}

...which becomes:

    <thing>
        <item id="1">chair</item>
        <item id="2">table</item>
        <item id="3">door</item>
        <item id="4">sofa</item>
        <item id="5">bed</item>
        <item id="6">shirt</item>
        <item id="7" other="8" more="9" also="10">towel</item>
    </thing>

As you see, attributes may be represented in a great variety of ways, so you don't need to remember
the "correct" one.

Of course if the "simple structure" is a hashref, the key cannot be a reference (because hash keys are always
strings), so if you want attributes on your elements, you either need the enclosing structure to be an
arrayref as in the example above, to allow keys to be refs which contain the attributes, or you need to
represent the key (=tag+attrs) as a string, like this (also in the previous example): C<'item id="1"'>

This concludes the mini-tutorial of the simple_to_xml function.

All the strings in C<$simple_array_ref> need to contain characters, rather than bytes/octets. The C<bytes>
optional flag only affects the produced XML string.

Optional flags: C<complete>, C<tidy>, C<indentstring>, C<save>, C<xslt>, C<bytes>

=cut

sub simple_to_xml {
    my $arref = shift;
    my $flags = shift || {};

    my $xml = '';
    my ($key, $value, @residue) = (ref $arref eq 'HASH') ? %$arref : @$arref;
    $key = _key_to_string($key);
    ! @residue or croak "Error: the provided simple ref contains more than 1 top element";
    my ($el_name) = $key =~ /^(\S+)/;
    defined $el_name or croak encode_utf8 "Error: Strange key: $key";

    if (! ref $value) {
        if ($key eq '!as_is') {
            check_xml $value or croak "invalid xml: $value";
            $xml .= $value;
        } elsif (defined $value and length $value) {
            $xml .= "<$key>"._encode($value)."</$el_name>";
        } else {
            $xml .= "<$key/>";
        }
    } else {
        $xml .= "<$key>@{[ _arrayref_to_xml($value, $flags) ]}</$el_name>";
    }
    if ($flags->{tidy}) {
        $xml = tidy_xml($xml, {
            exists $flags->{indentstring} ? (indentstring => $flags->{indentstring}) : ()
        });
    }
    my $decl = '';
    $decl .= qq'<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>\n' if $flags->{complete};
    $decl .= qq'<?xml-stylesheet type="text/xsl" href="$flags->{xslt}"?>\n' if $flags->{xslt};
    $xml = $decl . $xml;

    if (defined $flags->{save}) {
        open my $fh, '>', $flags->{save} or croak "Error: Couldn't open file '$flags->{save}' for writing: $!";
        binmode $fh, ':encoding(UTF-8)';
        print $fh $xml;
        close $fh;
    }

    $xml = encode_utf8($xml) if $flags->{bytes};
    return $xml;
}

sub _flatten {
    my ($thing) = @_;

    if (!ref $thing) { return $thing; }
    elsif (ref $thing eq 'HASH') { return map _flatten($_), %$thing; }
    elsif (ref $thing eq 'ARRAY') { return map _flatten($_), @$thing; }
    else { croak 'Error: reference of invalid type in simple_to_xml: '.(ref $thing); }
}

sub _key_to_string {
    my ($key) = @_;

    if (! ref $key) {
        return $key;
    } else {
        my ($tag, %attrs) = _flatten($key);
        return $tag . join('', map " $_=\""._encode($attrs{$_}).'"', grep {defined $attrs{$_}} keys %attrs);
    }
}

sub _arrayref_to_xml {
    my $arref = shift;
    my $flags = shift || {};

    my $xml = '';

    if (ref $arref eq 'HASH') { return _hashref_to_xml($arref, $flags); }

    foreach (my $i = 0; $i <= $#$arref; ) {
        my $key = $arref->[$i++];
        $key = _key_to_string($key);
        my ($el_name) = $key =~ /^(\S+)/;
        defined $el_name or croak encode_utf8 "Error: Strange key: $key";
        my $value = $arref->[$i++];

        if ($key eq '!as_is') {
            check_xml $value or croak "invalid xml: $value";
            $xml .= $value;
        } elsif (! ref $value) {
            if (defined $value and length $value) {
                $xml .= "<$key>@{[ _encode($value) ]}</$el_name>";
            } else {
                $xml .= "<$key/>";
            }
        } else {
            $xml .= "<$key>@{[ _arrayref_to_xml($value, $flags) ]}</$el_name>";
        }
    }
    return $xml;
}

sub _hashref_to_xml {
    my $hashref = shift;
    my $flags = shift || {};

    my $xml = '';

    while (my ($key, $value) = each %$hashref) {
        my ($el_name) = $key =~ /^(\S+)/;
        defined $el_name or croak encode_utf8 "Error: Strange key: $key";

        if ($key eq '!as_is') {
            check_xml $value or croak "invalid xml: $value";
            $xml .= $value;
        } elsif (! ref $value) {
            if (defined $value and length $value) {
                $xml .= "<$key>@{[ _encode($value) ]}</$el_name>";
            } else {
                $xml .= "<$key/>";
            }
        } else {
            $xml .= "<$key>@{[ _arrayref_to_xml($value, $flags) ]}</$el_name>";
        }
    }
    return $xml;
}


=head2 xml_to_simple($raw_xml)

Produces a very simple hash object from the raw XML string provided. An example hash object created thusly is this:
S<C<< { thing => { name => 'John', location => { city => 'New York', country => 'U.S.A.' } } } >>>

B<WARNING:> This function only works on very simple XML strings, i.e. children of an element may not consist of both
text and elements (child elements will be discarded in that case). Also attributes in tags are ignored.

Since the object created is a hashref (unless used with the C<arrayref> optional flag), duplicate keys will be
discarded.

All strings contained in the output simple structure will always contain characters rather than octets/bytes,
regardless of the C<bytes> optional flag.

Optional flags: C<internal>, C<strip>, C<file>, C<strip_ns>, C<arrayref>, C<bytes>

=cut

sub xml_to_simple {
    my $xml = shift;
    my $flags = shift || {};

    my $object = xml_to_object($xml, $flags);

    $object = $object->simplify($flags) if defined $object;

    return $object;
}

sub _objectarray_to_simple {
    my $object = shift;
    my $flags = shift || {};

    defined $object or return undef;

    return $flags->{arrayref}
        ? _objectarray_to_simple_arrayref($object, $flags)
        : _objectarray_to_simple_hashref($object, $flags);
}

sub _objectarray_to_simple_hashref {
    my $object = shift;
    my $flags = shift || {};

    defined $object or return undef;

    my $hashref = {};

    foreach my $stuff (@$object) {
        if (defined(my $key = $stuff->{el_name})) {
            $key = strip_ns $key if $flags->{strip_ns};
            $hashref->{ $key } = _objectarray_to_simple($stuff->{content}, $flags);
        }
        elsif (defined(my $value = $stuff->{text})) {
            $value = trim $value if $flags->{strip};
            return $value if $value =~ /\S/;
        }
    }

    return %$hashref ? $hashref : undef;
}

sub _objectarray_to_simple_arrayref {
    my $object = shift;
    my $flags = shift || {};

    defined $object or return undef;

    my $arrayref = [];

    foreach my $stuff (@$object) {
        if (defined(my $key = $stuff->{el_name})) {
            $key = strip_ns $key if $flags->{strip_ns};
            push @$arrayref, ( $key, _objectarray_to_simple($stuff->{content}, $flags) );
        } elsif (defined(my $value = $stuff->{text})) {
            $value = trim $value if $flags->{strip};
            return $value if $value =~ /\S/;
        }
    }

    return @$arrayref ? $arrayref : undef;
}


=head2 check_xml($raw_xml)

Returns true if the $raw_xml string is valid XML (valid enough to be used by this module), and false otherwise.

Optional flags: C<file>, C<bytes>

=cut

sub check_xml {
    my $xml = shift;
    my $flags = shift || {};

    my $ok = eval { xml_to_object($xml, $flags); 1 };
    return !!$ok;
}


1; # End of XML::MyXML

__END__


=head1 OBJECT METHODS

=head2 $obj->path("subtag1/subsubtag2[attr1=val1][attr2]/.../subsubsubtagX")

Returns the element specified by the path as an XML::MyXML::Object object. When there are more than one tags
with the specified name in the last step of the path, it will return all of them as an array. In scalar
context will only return the first one. Simple CSS3-style attribute selectors are allowed in the path next
to the tagnames, for example: C<< p[class=big] >> will only return C<< <p> >> elements that contain an
attribute called "class" with a value of "big". p[class] on the other hand will return p elements having a
"class" attribute, but that attribute can have any value. It's possible to surround attribute values with
quotes, like so: C<< input[name="foo[]"] >>

An example... To print the last names of all the students from the following XML, do:

    my $xml = <<'EOB';
    <people>
        <student>
            <name>
                <first>Alex</first>
                <last>Karelas</last>
            </name>
        </student>
        <student>
            <name>
                <first>John</first>
                <last>Doe</last>
            </name>
        </student>
        <teacher>
            <name>
                <first>Mary</first>
                <last>Poppins</last>
            </name>
        </teacher>
        <teacher>
            <name>
                <first>Peter</first>
                <last>Gabriel</last>
            </name>
        </teacher>
    </people>
    EOB
    
    my $obj = xml_to_object($xml);
    my @students = $obj->path('student');
    foreach my $student (@students) {
        print $student->path('name/last')->value, "\n";
    }

...or like this...

    my @last = $obj->path('student/name/last');
    foreach my $last (@last) {
        print $last->value, "\n";
    }

If you wish to describe the root element in the path as well, prepend it in the path with a slash like so:

    if( $student->path('/student/name/last')->value eq $student->path('name/last')->value ) {
        print "The two are identical", "\n";
    }

B<Since XML::MyXML version 1.08, the path method supports namespaces.>

You can replace the namespace prefix of an attribute or an element name in the path string with the
namespace name inside curly brackets, and place the curly-bracketed expression after the local part.

B<< I<Example #1:> >> Suppose the XML you want to go through is:

    <stream:stream xmlns:stream="http://foo/bar">
        <a>b</a>
    </stream:stream>

Then this will return the string C<"b">:

    $obj->path('/stream{http://foo/bar}/a')->value;

B<< I<Example #2:> >> Suppose the XML you want to go through is:

    <stream xmlns="http://foo/bar">
        <a>b</a>
    </stream>

Then both of these expressions will return C<"b">:

    $obj->path('/stream/a{http://foo/bar}')->value;
    $obj->path('/stream{http://foo/bar}/a{http://foo/bar}')->value;

B<Since XML::MyXML version 1.08, quotes in attribute match strings have no special meaning.>

If you want to use the "]" character in attribute values, you need to escape it with a
backslash character. As you need if you want to use the "}" character in a namespace value
in the path string.

B<< I<Example #1:> >> Suppose the XML you want to go through is:

    <stream xmlns:o="http://foo}bar">
        <a o:name="c]d">b</a>
    </stream>

Then this expression will return C<"b">:

    $obj->path('/stream/a[name{http://foo\}bar}=c\]d]')->value;

B<< I<Example #2:> >> You can match attribute values containing quote characters with just C<"> in the path string.

If the XML is:

    <stream id="&quot;1&quot;">a</stream>

...then this will return the string C<"a">:

    $obj->path('/stream[id="1"]')->value;

Optional flags: none

=head2 $obj->text([set_value]), also known as $obj->value([set_value])

If provided a set_value, will delete all contents of $obj and will place C<set_value> as its text contents.
Otherwise will return the text contents of this object, and of its descendants, in a single string.

Optional flags: C<strip>

=head2 $obj->inner_xml([xml_string])

Gets or sets the inner XML of the $obj node, depending on whether C<xml_string> is provided.

Optional flags: C<bytes>

=head2 $obj->attr('attrname' [, 'attrvalue'])

Gets/Sets the value of the 'attrname' attribute of the top element. Returns undef if attribute does not exist.
If called without the 'attrname' parameter, returns a hash with all attribute => value pairs. If setting with
an attrvalue of C<undef>, then removes that attribute entirely.

Input parameters and output are all in character strings, rather than octets/bytes.

Optional flags: none

=head2 $obj->tag

Returns the tag of the $obj element. E.g. if $obj represents an <rss:item> element, C<< $obj->tag >> will
return the string 'rss:item'. Returns undef if $obj doesn't represent a tag.

Optional flags: C<strip_ns>

=head2 $obj->name

Same as C<< $obj->tag >> (alias).

=head2 $obj->parent

Returns the XML::MyXML::Object element that is the parent of $obj in the document. Returns undef if $obj
doesn't have a parent.

Optional flags: none

=head2 $obj->simplify

Returns a very simple hashref, like the one returned with C<&XML::MyXML::xml_to_simple>. Same restrictions
and warnings apply.

Optional flags: C<internal>, C<strip>, C<strip_ns>, C<arrayref>

=head2 $obj->to_xml

Returns the XML string of the object, just like calling C<object_to_xml( $obj )>

Optional flags: C<complete>, C<tidy>, C<indentstring>, C<save>, C<bytes>

=head2 $obj->to_tidy_xml

Returns the XML string of the object in tidy form, just like calling C<tidy_xml( object_to_xml( $obj ) )>

Optional flags: C<complete>, C<indentstring>, C<save>, C<bytes>

=head1 BUGS

If you have a Github account, report your issues at
L<https://github.com/akarelas/xml-myxml/issues>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

You can get notified of new versions of this module for free, by email or RSS,
at L<https://www.perlmodules.net/viewfeed/distro/XML-MyXML>

=head1 LICENSE

Copyright (C) Alexander Karelas.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Alexander Karelas E<lt>karjala@cpan.orgE<gt>
