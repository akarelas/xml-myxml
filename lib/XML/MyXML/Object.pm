package XML::MyXML::Object;

use strict;
use warnings;

use XML::MyXML::Util 'trim';

use Encode;
use Carp;
use Scalar::Util 'weaken';

our $VERSION = "1.07";

sub new {
    my $class = shift;
    my $xml = shift;

    return bless XML::MyXML::xml_to_object($xml), $class;
}

sub _parse_description {
    my ($desc) = @_;

    my ($el_name, $attrs_str) = $desc =~ /^([^\[]*)(.*)\z/;
    my %attrs = $attrs_str =~ /\[([^\]=]+)(?:=(\"[^"]*\"|[^"\]]*))?\]/g;
    foreach my $attr_value (values %attrs) {
        defined $attr_value or next;
        $attr_value =~ s/^\"//;
        $attr_value =~ s/\"\z//;
    }

    return ($el_name, \%attrs);
}

sub cmp_element {
    my ($self, $desc) = @_;

    my ($el_name, $attrs) = ref $desc
        ? @$desc{qw/ tag attrs /}
        : _parse_description($desc);

    ! length $el_name or $self->{el_name} =~ /(^|\:)\Q$el_name\E\z/ or return 0;
    foreach my $attr (keys %$attrs) {
        my $attr_value = $self->attr($attr);
        defined $attr_value                                            or return 0;
        ! defined $attrs->{$attr} or $attrs->{$attr} eq $attr_value    or return 0;
    }

    return 1;
}

sub children {
    my $self = shift;
    my $el_name = shift;

    $el_name = '' if ! defined $el_name;

    my @all_children = grep { defined $_->{el_name} } @{$self->{content}};
    length $el_name or return @all_children;

    ($el_name, my $attrs) = _parse_description($el_name);
    my $desc = { tag => $el_name, attrs => $attrs };

    return grep $_->cmp_element($desc), @all_children;
}

sub path {
    my $self = shift;
    my $path = shift;

    my @path;
    my $original_path = $path;
    my $path_starts_with_root = $path =~ m|^/|;
    $path = "/$path" unless $path_starts_with_root;
    while (length $path) {
        my $success = $path =~ s!\A/((?:[^/\[]*)?(?:\[[^\]=]+(?:=(?:\"[^"]*\"|[^"\]]*))?\])*)!!;
        my $seg = $1;
        $success or croak "Invalid XML path: $original_path";
        push @path, $seg;
    }

    my @result = ($self);
    $self->cmp_element(shift @path) or return if $path_starts_with_root;
    for (my $i = 0; $i < @path; $i++) {
        @result = map $_->children( $path[$i] ), @result;
        @result     or return;
    }
    return wantarray ? @result : $result[0];
}

sub text {
    my $self = shift;
    my $flags = (@_ and ref $_[-1]) ? pop : {};
    my $set_value = @_ ? (defined $_[0] ? shift : '') : undef;

    if (! defined $set_value) {
        my $value = '';
        if ($self->{content}) {
            $value .= $_->text($flags) foreach @{ $self->{content} };
        }
        if ($self->{text}) {
            my $temp_value = $self->{text};
            $temp_value = trim $temp_value if $flags->{strip};
            $value .= $temp_value;
        }
        return $value;
    } else {
        if (length $set_value) {
            my $entry = bless {
                text => $set_value,
                parent => $self
            }, 'XML::MyXML::Object';
            weaken $entry->{parent};
            $self->{content} = [ $entry ];
        } else {
            $self->{content} = [];
        }
    }
}

*value = \&text;

sub inner_xml {
    my $self = shift;
    my $flags = (@_ and ref $_[-1]) ? pop : {};
    my $set_xml = @_ ? defined $_[0] ? shift : '' : undef;

    if (! defined $set_xml) {
        # TODO: there is a bug here: if $xml is just a self-closing tag, this will not work
        my $xml = $self->to_xml($flags);
        $xml =~ s/^\<.*?\>//s;
        $xml =~ s/\<\/[^\>]*\>\z//s;
        return $xml;
    } else {
        my $xml = "<div>$set_xml</div>";
        my $obj = XML::MyXML::xml_to_object($xml, $flags);
        $self->{content} = [];
        foreach my $child (@{ $obj->{content} || [] }) {
            $child->{parent} = $self;
            weaken $child->{parent};
            push @{ $self->{content} }, $child;
        }
    }
}

sub attr {
    my $self = shift;
    my $attr_name = shift;
    my $flags = ref $_[-1] ? pop : {};
    my ($set_to, $must_set);
    if (@_) {
        $set_to = shift;
        $must_set = 1;
    }

    if (defined $attr_name) {
        if ($must_set) {
            if (defined ($set_to)) {
                $self->{attrs}{$attr_name} = $set_to;
                return $set_to;
            } else {
                delete $self->{attrs}{$attr_name};
                return;
            }
        } else {
            return $self->{attrs}->{$attr_name};
        }
    } else {
        return %{$self->{attrs}};
    }
}

sub tag {
    my $self = shift;
    my $flags = shift || {};

    my $el_name = $self->{el_name};
    if (defined $el_name) {
        $el_name =~ s/^.*\:// if $flags->{strip_ns};
        return $el_name;
    } else {
        return undef;
    }
}

*name = \&tag;

sub parent {
    my $self = shift;

    return $self->{parent};
}

sub simplify {
    my $self = shift;
    my $flags = shift || {};

    my $simple = XML::MyXML::_objectarray_to_simple([$self], $flags);
    if (! $flags->{internal}) {
        return $simple;
    } else {
        if (ref $simple eq 'HASH') {
            return (values %$simple)[0];
        } elsif (ref $simple eq 'ARRAY') {
            return $simple->[1];
        }
    }
}

sub to_xml {
    my $self = shift;
    my $flags = shift || {};

    my $decl = '';
    $decl .= qq'<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>\n' if $flags->{complete};
    my $xml = XML::MyXML::_objectarray_to_xml([$self]);
    $xml = XML::MyXML::tidy_xml($xml, {
        %$flags,
        bytes => 0,
        complete => 0,
        save => undef
    }) if $flags->{tidy};
    $xml = $decl . $xml;
    if (defined $flags->{save}) {
        open my $fh, '>', $flags->{save} or croak "Error: Couldn't open file '$flags->{save}' for writing: $!";
        binmode $fh, ':encoding(UTF-8)';
        print $fh $xml;
        close $fh;
    }
    $xml = encode_utf8 $xml if $flags->{bytes};
    return $xml;
}

sub to_tidy_xml {
    my $self = shift;
    my $flags = shift || {};

    return $self->to_xml({ %$flags, tidy => 1 });
}

1;