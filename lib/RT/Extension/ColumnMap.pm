use 5.008003;
use strict;
use warnings;

package RT::Extension::ColumnMap;

=head1 NAME

RT::Extension::ColumnMap - bring ColumnMap to libraries

=head1 DESCRIPTION


=cut

our %MAP;

$MAP{'RT::Record'} = {
    id => sub { return $_[0]->id },

    ( map { my $m = $_ .'Obj'; $_ => sub { return $_[0]->$m() } }
    qw(Created LastUpdated CreatedBy LastUpdatedBy) ),
};

$MAP{'RT::Ticket'} = {
    ( map { my $m = $_ .'Obj'; $_ => sub { return $_[0]->$m() } }
    qw(Queue Owner Starts Started Told Due Resolved) ),

    ( map { my $m = $_; $_ => sub { return $_[0]->$m() } }
    qw(
        Status Subject
        Priority InitialPriority FinalPriority
        EffectiveId Type
        TimeWorked
    ) ),
};
foreach my $type (qw(Requestor Cc AdminCc)) {
    my $method = $type eq 'Requestor'? $type.'s': $type;
    my $map = {
        Trailing => sub { return $_[0]->$method()->UserMembersObj },
        Default => sub { return $_[0]->$method() },
    };
    $MAP{$type} = $MAP{$type .'s'} = $map;
}


$MAP{'RT::User'} = {
    ( map { my $m = $_; $_ => sub { return $_[0]->$m() } }
    qw(Name Comments Signature EmailAddress FreeformContactInfo
    Organization RealName NickName Lang EmailEncoding WebEncoding
    ExternalContactInfoId ContactInfoSystem ExternalAuthId
    AuthSystem Gecos HomePhone WorkPhone MobilePhone PagerPhone
    Address1 Address2 City State Zip Country Timezone PGPKey) ),
};


use Regexp::Common qw(delimited);
my $dequoter = $RE{delimited}{-delim=>q{'"}}{-esc=>'\\'}->action('dequote');

my $re_quoted = qr/$RE{delimited}{-delim=>q{'"}}{-esc=>'\\'}/;
my $re_not_quoted = qr/[^{}'"\\]+/;

my $re_arg_value = qr/ $re_quoted | $re_not_quoted /x;
my $re_arg = qr/\.?{$re_arg_value}/x;

my $re_field_name = qr/\w+/;
my $re_field = qr/$re_field_name $re_arg*/x;

my $re_column = qr/$re_field(?:\.$re_field)*/;

sub Get {
    my $self = shift;
    my %args = (String => undef, Objects => undef, @_);

    my $struct = $self->Parse( $args{'String'} );

    my @objects;
    while ( my ($k, $v) = each %{ $args{'Objects'} } ) {
        my %tmp = (
            object => $v,
            struct => $self->Parse( $k )
        );
        push @objects, \%tmp;
    }
    @objects = sort { @{$b->{struct}} <=> @{$b->{struct}} } @objects;

    my $prefix;
    foreach $prefix ( @objects ) {
        last if $self->IsPrefix( $prefix->{'struct'} => $struct );
    }
    return undef unless $prefix;

    splice @$struct, 0, scalar @{$prefix->{'struct'}};

    return $self->_Get( $struct, $prefix->{'object'} );
}

sub _Get {
    my $self = shift;
    my $struct = shift;
    my $object = shift;

    my ($entry, $callback) = $self->GetEntry( $struct, $object );
    die "boo" unless $entry;

    my %args = ( Arguments => [] );
    foreach ( @{$struct}[0 .. @$entry-1] ) {
        push @{ $args{'Arguments'} }, $_->{'arguments'};
    }
    if ( @$struct == @$entry ) {
        $args{'Trailing'} = 1;
    }

    my $value = $callback->( $object, %args );
    if ( $args{'Trailing'} ) {
        return $value;
    } elsif ( blessed $value ) {
        splice @$struct, 0, @$entry-1;
        return $self->Get( $struct, $object );
    } else {
        die "not trailing and not blessed";
    }
}

sub GetEntry {
    my $self = shift;
    my $struct = shift;
    my $object = shift;

    my $type = ref $object;
    my $map = $MAP{$type} or die "No map for $type";

    foreach my $e ( sort {length $b <=> length $a } keys %$map ) {
        my $parse = $self->Parse($e);
        next unless $self->IsPrefix(
            $parse => $struct,
            SkipArguments => 1
        );
        return ($parse, $map->{$e});
    }
    return ();
}

sub Parse {
    my $self = shift;
    my $string = shift;
    return $string if ref $string;
    return [] unless defined $string && length $string;

    my @fields = split /\.(?=$re_field)/o, $string;
    foreach my $field ( @fields ) {
        my ($name, $args_string) = ($field =~ /^($re_field_name)(.*)/);
        next unless length $args_string;

        my @args;
        push @args, $1 while $args_string =~ s/^\.?{($re_arg_value)}//;
        $dequoter->($_) foreach @args;
        $field = { name => $name, arguments => \@args };
    }
    return \@fields;
}

sub IsPrefix {
    my $self = shift;
    my $what = shift;
    my $in = shift;
    my %args = @_;

    return 1 unless @$what;
    return 0 if @$what > @$in;
    foreach ( my $i = 0; $i < @$what; $i++ ) {
        my ($l, $r) = map ref $_? $_->{name} : $_, $what->[$i], $in->[$i];
        return 0 unless $l eq $r;
        next if $args{'SkipArguments'};

        ($l, $r) = map ref $_? $_->{arguments} : [], $what->[$i], $in->[$i];
        return 0 unless @$l == @$r;
        return 0 if grep $l->[$_] ne $r->[$_], 0 .. (@$l-1);
    }
    return 1;
}


=head1 LICENSE

Under the same terms as perl itself.

=head1 AUTHOR

Ruslan Zakirov E<lt>Ruslan.Zakirov@gmail.comE<gt>

=cut

1;
