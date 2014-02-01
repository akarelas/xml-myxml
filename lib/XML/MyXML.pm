package XML::MyXML;
# ABSTRACT: A simple-to-use XML module, for parsing and creating XML documents

use strict;
use warnings;
use utf8;
use Carp;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(tidy_xml object_to_xml xml_to_object simple_to_xml xml_to_simple check_xml xml_escape);
our %EXPORT_TAGS = (all => [@EXPORT_OK]);
use Encode;

warn "WARNING: Your program is using XML::MyXML, which is deprecated. Development on this module has stopped, and the module will be removed from future CPAN releases on January 1st, 2016. Please start using XML::MyXML::II as soon as possible instead, which you have installed on your system. Please also make sure you read https://metacpan.org/pod/XML::MyXML::II#DIFFERENCES-FROM-XML::MyXML to see the few differences between XML::MyXML and XML::MyXML::II";

=head1 SYNOPSIS

    use XML::MyXML qw(tidy_xml xml_to_object);
    use XML::MyXML qw(:all);

    my $xml = "<item><name>Table</name><price><usd>10.00</usd><eur>8.50</eur></price></item>";
    print tidy_xml($xml);

    my $obj = xml_to_object($xml);
    print "Price in Euros = " . $obj->path('price/eur')->value;

    $obj->simplify is hashref { item => { name => 'Table', price => { usd => '10.00', eur => '8.50' } } }
    $obj->simplify({ internal => 1 }) is hashref { name => 'Table', price => { usd => '10.00', eur => '8.50' } }

=head1 PLEASE USE XML::MyXML::II INSTEAD

B<< *** This module will not be maintained anymore *** Please use L<XML::MyXML::II> instead, which is also contained in this distribution *** >>

It's main improvements are: better unicode handling and automatic object destruction

=head1 EXPORT

tidy_xml, xml_to_object, object_to_xml, simple_to_xml, xml_to_simple, check_xml

=head1 FEATURES & LIMITATIONS

This module can parse XML comments, CDATA sections, XML entities (the standard five and numeric ones) and simple non-recursive C<< <!ENTITY> >>s

It will ignore (won't parse) C<< <!DOCTYPE...> >>, C<< <?...?> >> and other C<< <!...> >> special markup

Parsed documents must be UTF-8 encoded unless an encoding is declared in the initial XML declaration <?xml ... ?> of the document. All XML documents produced by this module will be UTF-8 encoded, as will be all strings output by its functions.

XML documents to be parsed may not contain the C<< > >> character unencoded in attribute values

=head1 OPTIONAL FUNCTION FLAGS

Some functions and methods in this module accept optional flags, listed under each function in the documentation. They are optional, default to zero unless stated otherwise, and can be used as follows: S<C<< function_name( $param1, { flag1 => 1, flag2 => 1 } ) >>>. This is what each flag does:

C<strip> : the function will strip initial and ending whitespace from all text values returned

C<file> : the function will expect the path to a file containing an XML document to parse, instead of an XML string

C<complete> : the function's XML output will include an XML declaration (C<< <?xml ... ?>  >>) in the beginning

C<soft> : the function will return undef instead of dying in case of an error during XML parsing

C<internal> : the function will only return the contents of an element in a hashref instead of the element itself (see L</SYNOPSIS> for example)

C<tidy> : the function will return tidy XML

C<indentstring> : when producing tidy XML, this denotes the string with which child elements will be indented (Default is the 'tab' character)

C<save> : the function (apart from doing what it's supposed to do) will also save its XML output in a file whose path is denoted by this flag

C<strip_ns> : strip the namespaces (characters up to and including ':') from the tags

C<xslt> : will add a <?xml-stylesheet?> link in the XML that's being output, of type 'text/xsl', pointing to the filename or URL denoted by this flag

C<arrayref> : the function will create a simple arrayref instead of a simple hashref (which will preserve order and elements with duplicate tags)

C<utf8> : the strings which will be returned will have their utf8 flag set (defaults to 0 for compatibility with software built with older versions of this module). The way this module works is that it holds everything in byte format internally (even if you provide it with a utf8 XML string), and then produces utf8 strings or simple structures if (and only if) asked for with this flag. UTF is an important issue, please read C<perldoc utf8> for more.

=head1 FUNCTIONS

=cut

sub _encode {
	my $string = shift;
	my $entities = shift || {};
	defined $string or $string = '';
	my %replace = 	(
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

Returns the same string, but with the C<< < >>, C<< > >>, C<< & >>, C<< " >> and C<< ' >> characters replaced by their XML entities (e.g. C<< &amp; >>).

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
	my %replace = reverse (
					(reverse (%$entities)),
					'<' => '&lt;',
					'>' => '&gt;',
					'&' => '&amp;',
					'\'' => '&apos;',
					'"' => '&quot;',
	);
	Encode::_utf8_on($string);
	if (utf8::valid($string)) {
		$string =~ s/\&\#x([0-9a-f]+)\;/chr(hex($1))/egi;
		$string =~ s/\&\#([0-9]+)\;/chr($1)/eg;
	}
	Encode::_utf8_off($string);
	my $keys = "(".join("|", keys %replace).")";
	$string =~ s/$keys/$replace{$1}/g;
	return $string;
}

sub _strip {
	my $string = shift;

	return defined $string ? ($string =~ /^\s*(.*?)\s*$/s)[0] : $string;
}

sub _strip_ns {
	my $string = shift;

	return defined $string ? ($string =~ /^(?:.+\:)?(.*)$/s)[0] : $string;
}

=head2 tidy_xml($raw_xml)

Returns the XML string in a tidy format (with tabs & newlines)

Optional flags: C<file>, C<complete>, C<indentstring>, C<soft>, C<save>, C<utf8>

=cut


sub tidy_xml {
	my $xml = shift;
	if ($xml eq 'XML::MyXML') { confess "Error: 'tidy_xml' is a function, not a method"; }
	my $flags = shift || {};

	my $object = xml_to_object($xml, $flags);
	defined $object or return $object;
	_tidy_object($object, undef, $flags);
	my $return = $object->to_xml({ %$flags, tidy => 0 }) . "\n";
	$object->delete();
	return $return;
}


=head2 xml_to_object($raw_xml)

Creates an 'XML::MyXML::Object' object from the raw XML provided

Optional flags: C<file>, C<soft>

=cut

sub xml_to_object {
	my $xml = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	my $soft = $flags->{'soft'}; # soft = 'don't die if can't parse, just return undef'

	if ($flags->{'file'}) {
		open my $fh, '<', $xml or do { confess "Error: The file '$xml' could not be opened for reading: $!" unless $soft; return undef; };
		$xml = join '', <$fh>;
		close $fh;
	}

	my (undef, undef, $encoding) = $xml =~ /<\?xml(\s[^>]+)?\sencoding=(['"])(.*?)\2/g;
	Encode::_utf8_on($xml);
	if (! utf8::valid($xml)) {
		if ($encoding and $encoding !~ /^utf-?8$/i) {
			Encode::_utf8_off($xml);
			$xml = decode($encoding, $xml);
			Encode::_utf8_on($xml);
		}
	}
	if (! utf8::valid($xml)) { confess "Error: Input string is invalid UTF-8" unless $soft; return undef; }
	Encode::_utf8_off($xml);

	my $entities = {};

	# Parse CDATA sections
	$xml =~ s/<\!\[CDATA\[(.*?)\]\]>/_encode($1)/egs;
	my @els = $xml =~ /(<!--.*?(?:-->|$)|<[^>]*?>|[^<>]+)/sg;
	# Remove comments, special markup and initial whitespace
	{
		my $init_ws = 1;
		foreach my $el (@els) {
			if ($el =~ /^<!--/) {
				if ($el !~ /-->$/) { confess "Error: unclosed XML comment block - '$el'" unless $soft; return undef; }
				undef $el;
			} elsif ($el =~ /^<\?/) { # like <?xml?> or <?target?>
				if ($el !~ /\?>$/) { confess "Error: Erroneous special markup - '$el'" unless $soft; return undef; }
				undef $el;
			} elsif (my ($entname, undef, $entvalue) = $el =~ /^<!ENTITY\s+(\S+)\s+(['"])(.*?)\2\s*>$/g) {
				$entities->{"&$entname;"} = _decode($entvalue);
				undef $el;
			} elsif ($el =~ /<!/) { # like <!DOCTYPE> or <!ELEMENT> or <!ATTLIST>
				undef $el;
			} elsif ($init_ws) {
				if ($el =~ /\S/) {
					$init_ws = 0;
				} else {
					undef $el;
				}
			}
		}
		@els = grep { defined $_ } @els;
		if (! @els) { confess "Error: No elements in XML document" unless $soft; return undef; }
	}
	my @stack;
	my $object = bless ({ content => [] }, 'XML::MyXML::Object');
	my $pointer = $object;
	foreach my $el (@els) {
		if ($el =~ /^<\/?>$/) {
			confess "Error: Strange element: '$el'" unless $soft; $object->delete(); return undef;
		} elsif ($el =~ /^<\/[^\s>]+>$/) {
			my ($element) = $el =~ /^<\/(\S+)>$/g;
			if (! length($element)) { confess "Error: Strange element: '$el'" unless $soft; $object->delete(); return undef; }
			if ($stack[$#stack]->{'element'} ne $element) { confess "Error: Incompatible stack element: stack='".$stack[$#stack]->{'element'}."' element='$el'" unless $soft; $object->delete(); return undef; }
			my $stackentry = pop @stack;
			if ($#{$stackentry->{'content'}} == -1) {
				delete $stackentry->{'content'};
			}
			$pointer = $stackentry->{'parent'};
		} elsif ($el =~ /^<[^>]+\/>$/) {
			my ($element) = $el =~ /^<([^\s>\/]+)/g;
			if (! length($element)) { confess "Error: Strange element: '$el'" unless $soft; $object->delete(); return undef; }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/\/>$//;
			my @attrs = $el =~ /\s+(\S+=(['"]).*?\2)/g;
			my $i = 1;
			@attrs = grep {$i++ % 2} @attrs;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, undef, $value) = $attr =~ /^(\S+?)=(['"])(.*?)\2$/g;
				if (! length($name) or ! defined($value)) { confess "Error: Strange attribute: '$attr'" unless $soft; $object->delete(); return undef; }
				$attr{$name} = _decode($value, $entities);
			}
			my $entry = { element => $element, attrs => \%attr, parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			push @{$pointer->{'content'}}, $entry;
		} elsif ($el =~ /^<[^\s>\/][^>]*>$/) {
			my ($element) = $el =~ /^<([^\s>]+)/g;
			if (! length($element)) { confess "Error: Strange element: '$el'" unless $soft; $object->delete(); return undef; }
			my $elementmeta = quotemeta($element);
			$el =~ s/^<$elementmeta//;
			$el =~ s/>$//;
			my @attrs = $el =~ /\s+(\S+=(['"]).*?\2)/g;
			my $i = 1;
			@attrs = grep {$i++ % 2} @attrs;
			my %attr;
			foreach my $attr (@attrs) {
				my ($name, undef, $value) = $attr =~ /^(\S+?)=(['"])(.*?)\2$/g;
				if (! length($name) or ! defined($value)) { confess "Error: Strange attribute: '$attr'" unless $soft; $object->delete(); return undef; }
				$attr{$name} = _decode($value, $entities);
			}
			my $entry = { element => $element, attrs => \%attr, content => [], parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			push @stack, $entry;
			push @{$pointer->{'content'}}, $entry;
			$pointer = $entry;
		} elsif ($el =~ /^[^<>]*$/) {
			my $entry = { value => _decode($el, $entities), parent => $pointer };
			bless $entry, 'XML::MyXML::Object';
			push @{$pointer->{'content'}}, $entry;
		} else {
			confess "Error: Strange element: '$el'" unless $soft; $object->delete(); return undef;
		}
	}
	if (@stack) { confess "Error: The <$stack[-1]->{'element'}> element has not been closed in XML" unless $soft; $object->delete(); return undef; }
	$object = $object->{'content'}[0];
	$object->{'parent'} = undef;
	return $object;
}

sub _objectarray_to_xml {
	my $object = shift;

	my $xml = '';
	foreach my $stuff (@$object) {
		if (! defined $stuff->{'element'} and defined $stuff->{'value'}) {
			$xml .= _encode($stuff->{'value'});
		} else {
			$xml .= "<".$stuff->{'element'};
			foreach my $attrname (keys %{$stuff->{'attrs'}}) {
				$xml .= " ".$attrname.'="'._encode($stuff->{'attrs'}{$attrname}).'"';
			}
			if (! defined $stuff->{'content'}) {
				$xml .= "/>"
			} else {
				$xml .= ">";
				$xml .= _objectarray_to_xml($stuff->{'content'});
				$xml .= "</".$stuff->{'element'}.">";
			}
		}
	}
	return $xml;
}

=head2 object_to_xml($object)

Creates an XML string from the 'XML::MyXML::Object' object provided

Optional flags: C<complete>, C<tidy>, C<indentstring>, C<save>, C<utf8>

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

	$flags->{'indentstring'} = "\t" unless exists $flags->{'indentstring'};

	if (! defined $object->{'content'} or ! @{$object->{'content'}}) { return; }
	my $hastext;
	my @children = @{$object->{'content'}};
	foreach my $i (0..$#children) {
		my $child = $children[$i];
		if (defined $child->{'value'}) {
			if ($child->{'value'} =~ /\S/) {
				$hastext = 1;
				last;
			}
		}
	}
	if ($hastext) { return; }

	@{$object->{'content'}} = grep { ! defined $_->{'value'} or $_->{'value'} !~ /^\s*$/ } @{$object->{'content'}};

	@children = @{$object->{'content'}};
	$object->{'content'} = [];
	for my $i (0..$#children) {
		push @{$object->{'content'}}, bless ({ value => "\n".($flags->{'indentstring'}x($tabs+1)), parent => $object }, 'XML::MyXML::Object');
		push @{$object->{'content'}}, $children[$i];
	}
	push @{$object->{'content'}}, bless ({ value => "\n".($flags->{'indentstring'}x($tabs)), parent => $object }, 'XML::MyXML::Object');

	for my $i (0..$#{$object->{'content'}}) {
		_tidy_object($object->{'content'}[$i], $tabs+1, $flags);
	}
}


=head2 simple_to_xml($simple_array_ref)

Produces a raw XML string from either an array reference, a hash reference or a mixed structure such as these examples:

    { thing => { name => 'John', location => { city => 'New York', country => 'U.S.A.' } } }
    [ thing => [ name => 'John', location => [ city => 'New York', country => 'U.S.A.' ] ] ]
    { thing => { name => 'John', location => [ city => 'New York', city => 'Boston', country => 'U.S.A.' ] } }

Optional flags: C<complete>, C<tidy>, C<indentstring>, C<save>, C<xslt>, C<utf8>

=cut

sub simple_to_xml {
	my $arref = shift;
	my $flags = shift || {};

	my $xml = '';
	my ($key, $value, @residue) = (ref $arref eq 'HASH') ? %$arref : @$arref;
	Encode::_utf8_off($key);
	if (@residue) { confess "Error: the provided simple ref contains more than 1 top element"; }
	my ($tag) = $key =~ /^(\S+)/g;
	confess "Error: Strange key: $key" if ! defined $tag;

	if (! ref $value) {
		Encode::_utf8_off($value);
		if (defined $value and length $value) {
			$xml .= "<$key>"._encode($value)."</$tag>";
		} else {
			$xml .= "<$key/>";
		}
	} else {
		$xml .= "<$key>"._arrayref_to_xml($value, $flags)."</$tag>";
	}
	if ($flags->{'tidy'}) { $xml = tidy_xml($xml, { $flags->{'indentstring'} ? (indentstring => $flags->{'indentstring'}) : () }); }
	my $decl = $flags->{'complete'} ? '<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>'."\n" : '';
	$decl .= "<?xml-stylesheet type=\"text/xsl\" href=\"$flags->{'xslt'}\"?>\n" if $flags->{'xslt'};
	$xml = $decl . $xml;
	if ($flags->{'utf8'}) { Encode::_utf8_on($xml); }

	if (defined $flags->{'save'}) {
		open my $fh, '>', $flags->{'save'} or confess "Error: Couldn't open file '$flags->{'save'}' for writing: $!";
		if ($flags->{'utf8'}) { binmode $fh, ':encoding(UTF-8)'; }
		print $fh $xml;
		close $fh;
	}

	return $xml;
}


sub _arrayref_to_xml {
	my $arref = shift;
	my $flags = shift || {};

	my $xml = '';

	if (ref $arref eq 'HASH') { return _hashref_to_xml($arref, $flags); }

	foreach (my $i = 0; $i <= $#$arref; ) {
	#while (@$arref) {
		my $key = $arref->[$i++];
		Encode::_utf8_off($key);
		#my $key = shift @$arref;
		my ($tag) = $key =~ /^(\S+)/g;
		confess "Error: Strange key: $key" if ! defined $tag;
		my $value = $arref->[$i++];
		#my $value = shift @$arref;

		if ($key eq '!as_is') {
			Encode::_utf8_off($value);
			$xml .= $value if check_xml($value);
		} elsif (! ref $value) {
			Encode::_utf8_off($value);
			if (defined $value and length $value) {
				$xml .= "<$key>"._encode($value)."</$tag>";
			} else {
				$xml .= "<$key/>";
			}
		} else {
			$xml .= "<$key>"._arrayref_to_xml($value, $flags)."</$tag>";
		}
	}
	return $xml;
}


sub _hashref_to_xml {
	my $hashref = shift;
	my $flags = shift || {};

	my $xml = '';

	while (my ($key, $value) = each %$hashref) {
		Encode::_utf8_off($key);
		my ($tag) = $key =~ /^(\S+)/g;
		confess "Error: Strange key: $key" if ! defined $tag;

		if ($key eq '!as_is') {
			Encode::_utf8_off($value);
			$xml .= $value if check_xml($value);
		} elsif (! ref $value) {
			Encode::_utf8_off($value);
			if (defined $value and length $value) {
				$xml .= "<$key>"._encode($value)."</$tag>";
			} else {
				$xml .= "<$key/>";
			}
		} else {
			$xml .= "<$key>"._arrayref_to_xml($value, $flags)."</$tag>";
		}
	}
	return $xml;
}

=head2 xml_to_simple($raw_xml)

Produces a very simple hash object from the raw XML string provided. An example hash object created thusly is this: S<C<< { thing => { name => 'John', location => { city => 'New York', country => 'U.S.A.' } } } >>>

Since the object created is a hashref, duplicate keys will be discarded. WARNING: This function only works on very simple XML strings, i.e. children of an element may not consist of both text and elements (child elements will be discarded in that case)

Optional flags: C<internal>, C<strip>, C<file>, C<soft>, C<strip_ns>, C<arrayref>, C<utf8>

=cut

sub xml_to_simple {
	my $xml = shift;
	my $flags = shift || {};

	my $object = xml_to_object($xml, $flags);

	my $return = defined $object ? $object->simplify($flags) : $object;

	$object->delete();

	return $return;
}

sub _objectarray_to_simple {
	my $object = shift;
	my $flags = shift || {};

	if (! defined $object) { return undef; }

	if ($flags->{'arrayref'}) {
		return _objectarray_to_simple_arrayref($object, $flags);
	} else {
		return _objectarray_to_simple_hashref($object, $flags);
	}
}

sub _objectarray_to_simple_hashref {
	my $object = shift;
	my $flags = shift || {};

	if (! defined $object) { return undef; }

	my $hashref = {};

	foreach my $stuff (@$object) {
		if (defined $stuff->{'element'}) {
			my $key = $stuff->{'element'};
			if ($flags->{'strip_ns'}) { $key = XML::MyXML::_strip_ns($key); }
			Encode::_utf8_on($key) if $flags->{'utf8'};
			$hashref->{ $key } = _objectarray_to_simple($stuff->{'content'}, $flags);
		} elsif (defined $stuff->{'value'}) {
			my $value = $stuff->{'value'};
			if ($flags->{'strip'}) { $value = XML::MyXML::_strip($value); }
			Encode::_utf8_on($value) if $flags->{'utf8'};
			return $value if $value =~ /\S/;
		}
	}

	if (keys %$hashref) {
		return $hashref;
	} else {
		return undef;
	}
}

sub _objectarray_to_simple_arrayref {
	my $object = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if (ref $flags ne 'HASH') { confess "Error: This method of setting flags is deprecated in XML::MyXML v0.083 - check module's documentation for the new way"; }

	if (! defined $object) { return undef; }

	my $arrayref = [];

	foreach my $stuff (@$object) {
		if (defined $stuff->{'element'}) {
			my $key = $stuff->{'element'};
			if ($flags->{'strip_ns'}) { $key = XML::MyXML::_strip_ns($key); }
			Encode::_utf8_on($key) if $flags->{'utf8'};
			push @$arrayref, ( $key, _objectarray_to_simple($stuff->{'content'}, $flags) );
			#$hashref->{ $key } = _objectarray_to_simple($stuff->{'content'}, $flags);
		} elsif (defined $stuff->{'value'}) {
			my $value = $stuff->{'value'};
			if ($flags->{'strip'}) { $value = XML::MyXML::_strip($value); }
			Encode::_utf8_on($value) if $flags->{'utf8'};
			return $value if $value =~ /\S/;
		}
	}

	if (@$arrayref) {
		return $arrayref;
	} else {
		return undef;
	}
}


=head2 check_xml($raw_xml)

Returns 1 if the $raw_xml string is valid XML (valid enough to be used by this module), and 0 otherwise.

Optional flags: C<file>

=cut

sub check_xml {
	my $xml = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if (ref $flags ne 'HASH') { confess "Error: This method of setting flags is deprecated in XML::MyXML v0.083 - check module's documentation for the new way"; }

	my $obj = xml_to_object($xml, { %$flags, soft => 1 });
	if ($obj) {
		$obj->delete();
		return 1;
	} else {
		return 0;
	}
}



package XML::MyXML::Object;

use Carp;

=head1 OBJECT METHODS

=cut

sub new {
	my $class = shift;
	my $xml = shift;

	my $obj = XML::MyXML::xml_to_object($xml);
	bless $obj, $class;
	return $obj;
}

sub _parse_description {
	my ($desc) = @_;

	my ($tag, $attrs_str) = $desc =~ /^([^\[]*)(.*)$/g;
	my %attrs = $attrs_str =~ /\[([^=\]]+)(?:=([^\]]*))?\]/g;

	return ($tag, \%attrs);
}

sub cmp_element {
	my ($self, $desc) = @_;

	my ($tag, $attrs) = ref $desc
			? @$desc{qw/ tag attrs /}
			: _parse_description($desc);

	! length $tag or $self->{'element'} =~ /(^|\:)\Q$tag\E$/	or return 0;
	foreach my $attr (keys %$attrs) {
		my $val = $self->attr($attr);
		defined $val											or return 0;
		! defined $attrs->{$attr} or $attrs->{$attr} eq $val	or return 0;
	}

	return 1;
}

sub children {
	my $self = shift;
	my $tag = shift;

	$tag = '' if ! defined $tag;

	my @all_children = grep { defined $_->{'element'} } @{$self->{'content'}};
	length $tag		or return @all_children;

	($tag, my $attrs) = _parse_description($tag);
	my $desc = { tag => $tag, attrs => $attrs };

	my @results;
	CHILD: foreach my $child (@all_children) {
		$child->cmp_element($desc)		or next;
		push @results, $child;
	}

	return @results;
}

sub parent {
	my $self = shift;

	return $self->{'parent'};
}

=head2 $obj->path("subtag1/subsubtag2[attr1=val1][attr2]/.../subsubsubtagX")

Returns the element specified by the path as an XML::MyXML::Object object. When there are more than one tags with the specified name in the last step of the path, it will return all of them as an array. In scalar context will only return the first one. CSS3-style attribute selectors are allowed in the path next to the tagnames, for example: C<< p[class=big] >> will only return C<< <p> >> elements that contain an attribute called "class" with a value of "big". p[class] on the other hand will return p elements having a "class" attribute, but that attribute can have any value.

=cut

sub path {
	my $self = shift;
	my $path = shift;

	my @path;
	my $orig_path = $path;
	$path = "/" . $path;
	while (length $path) {
		my $success = $path =~ s!^/((?:[^/\[]*)?(?:\[[^\]]+\])*)!!;
		my $seg = $1;
		if ($success) {
			push @path, $seg;
		} else {
			die "Invalid path: $orig_path";
		}
	}

	my $el = $self;
	for (my $i = 0; $i < $#path; $i++) {
		my $pathstep = $path[$i];
		($el) = $el->children($pathstep);
		if (! defined $el) { return; }
	}
	return wantarray ? $el->children($path[$#path]) : ($el->children($path[$#path]))[0];
}

=head2 $obj->value

When the element represented by the $obj object has only text contents, returns those contents as a string. If the $obj element has no contents, value will return an empty string.

Optional flags: C<strip>, C<utf8>

=cut

sub value {
	my $self = shift;
	my $flags = shift || {};

	if ($self->{'content'} and $self->{'content'}[0]) {
		my $value = $self->{'content'}[0]{'value'};
		if ($flags->{'strip'}) { $value = XML::MyXML::_strip($value); }
		Encode::_utf8_on($value) if $flags->{'utf8'};
		return $value;
	} else {
		return undef;
	}
}

=head2 $obj->attr('attrname' [, 'attrvalue'])

Gets/Sets the value of the 'attrname' attribute of the top element. Returns undef if attribute does not exist. If called without the 'attrname' paramter, returns a hash with all attribute => value pairs. If setting with an attrvalue of C<undef>, then removes that attribute entirely.

Optional flags: C<utf8>

=cut

sub attr {
	my $self = shift;
	my $attrname = shift;
	my ($set_to, $must_set, $flags);
	if (@_) {
		my $next = shift;
		if (! ref $next) {
			$set_to = $next;
			Encode::_utf8_off($set_to);
			$must_set = 1;
			$flags = shift;
		} else {
			$flags = $next;
		}
	}
	$flags ||= {};

	if (defined $attrname) {
		if ($must_set) {
			if (defined ($set_to)) {
				$self->{'attrs'}{$attrname} = $set_to;
				Encode::_utf8_on($set_to) if $flags->{'utf8'};
				return $set_to;
			} else {
				delete $self->{'attrs'}{$attrname};
				return;
			}
		} else {
			my $attrvalue = $self->{'attrs'}->{$attrname};
			Encode::_utf8_on($attrvalue) if $flags->{'utf8'};
			return $attrvalue;
		}
	} else {
		my %attr = %{$self->{'attrs'}};
		if ($flags->{'utf8'}) {
			foreach my $key (keys %attr) {
				Encode::_utf8_on($attr{$key});
			}
		}
		return %attr;
	}
}

=head2 $obj->tag

Returns the tag of the $obj element (after stripping it from namespaces, unless the C<strip_ns> option is passed as false). E.g. if $obj represents an <rss:item> element, C<< $obj->tag >> will just return the name 'item'.
Returns undef if $obj doesn't represent a tag.

Optional flags: C<utf8>, C<strip_ns>

=cut

sub tag {
	my $self = shift;
	my $flags = shift || {};

	my $tag = $self->{'element'};
	if (defined $tag) {
		$tag =~ s/^.*\://	unless exists $flags->{'strip_ns'} and ! $flags->{'strip_ns'};
		Encode::_utf8_on($tag) if $flags->{'utf8'};
		return $tag;
	} else {
		return undef;
	}
}

=head2 $obj->simplify

Returns a very simple hashref, like the one returned with C<&XML::MyXML::xml_to_simple>. Same restrictions and warnings apply.

Optional flags: C<internal>, C<strip>, C<strip_ns>, C<arrayref>, C<utf8>

=cut

sub simplify {
	my $self = shift;
	my $flags = (@_ and defined $_[0]) ? $_[0] : {};

	if (ref $flags ne 'HASH') { confess "Error: This method of setting flags is deprecated in XML::MyXML v0.083 - check module's documentation for the new way"; }

	my $simple = XML::MyXML::_objectarray_to_simple([$self], $flags);
	if (! $flags->{'internal'}) {
		return $simple;
	} else {
		if (ref $simple eq 'HASH') {
			return (values %$simple)[0];
		} elsif (ref $simple eq 'ARRAY') {
			return $simple->[1];
		}
	}
}

=head2 $obj->to_xml

Returns the XML string of the object, just like calling C<object_to_xml( $obj )>

Optional flags: C<complete>, C<tidy>, C<indentstring>, C<save>, C<utf8>

=cut

sub to_xml {
	my $self = shift;
	my $flags = shift || {};

	my $decl = $flags->{'complete'} ? '<?xml version="1.1" encoding="UTF-8" standalone="yes" ?>'."\n" : '';
	my $xml = XML::MyXML::_objectarray_to_xml([$self]);
	if ($flags->{'tidy'}) { $xml = XML::MyXML::tidy_xml($xml, { %$flags, complete => 0, save => undef }); }
	$xml = $decl . $xml;
	if ($flags->{'utf8'}) { Encode::_utf8_on($xml); }
	if (defined $flags->{'save'}) {
		open my $fh, '>', $flags->{'save'} or confess "Error: Couldn't open file '$flags->{'save'}' for writing: $!";
		if ($flags->{'utf8'}) { binmode $fh, ':encoding(UTF-8)'; }
		print $fh $xml;
		close $fh;
	}
	return $xml;
}

=head2 $obj->to_tidy_xml

Returns the XML string of the object in tidy form, just like calling C<tidy_xml( object_to_xml( $obj ) )>

Optional flags: C<complete>, C<indentstring>, C<save>, C<utf8>

=cut

sub to_tidy_xml {
	my $self = shift;
	my $flags = shift || {};

	$flags->{'tidy'} = 1;
	return $self->to_xml( $flags );
}




=head2 $obj->delete

Deletes the object and all its children from memory. This is the only way to remove an XML object from memory and clear the RAM, since children and parents refer to each other circularly.

The way it works is by removing references from the object's descendants to their parents.

=cut

sub delete {
	my $self = shift;

	# Remove self from parent's "content" field
	my $parent = $self->{'parent'};
	if ($parent) {
		my $content = $parent->{'content'};
		if ($content) {
			my @new = ();
			foreach my $item (@$content) {
				if ($item != $self) { push @new, $item; }
			}
			$parent->{'content'} = \@new;
		}
	}

	my $content = $self->{'content'};
	if ($content) {
		foreach my $item (@$content) {
			$item->delete();
		}
	}

	delete $self->{$_} foreach keys %$self;
}

=head1 BUGS

If you don't have a Github account to report your issues at
L<https://github.com/akarelas/xml-myxml/issues>,
then feel free to report any bugs or feature requests to
C<bug-xml-myxml at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=XML-MyXML>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=cut

1; # End of XML::MyXML

