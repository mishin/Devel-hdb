package Devel::hdb::App::Breakpoint;

use strict;
use warnings;

use base 'Devel::hdb::App::Base';

use Plack::Request;
use Devel::hdb::Response;
use Digest::MD5 qw();
use Time::HiRes qw();

sub response_url_base() { '/breakpoints' };

__PACKAGE__->add_route('post', response_url_base(), 'set');
__PACKAGE__->add_route('get', qr{(/breakpoints/\w+)$}, 'get');
__PACKAGE__->add_route('delete', qr{(/breakpoints/\w+)$}, 'delete');
__PACKAGE__->add_route('get', '/breakpoints', 'get_all');

sub delete_response_type { 'delete-breakpoint' }
sub actionable_getter() { 'get_breaks' }
sub actionable_adder() { 'add_break' }
sub actionable_remover() { 'remove_break' }

{
    my(%my_breakpoints);
    sub storage { \%my_breakpoints; }
}

sub is_file_or_line_invalid {
    my($class, $app, $filename, $line) = @_;

    if (! $app->is_loaded($filename)) {
        return [ 404, ['Content-Type' => 'text/html'], ["$filename is not loaded"]];
    } elsif (! $app->is_breakable($filename, $line)) {
        return [ 403, ['Content-Type' => 'text/html'], ["line $line of $filename is not breakable"]];
    }
    return;
}

sub _read_request_body {
    my($class, $env) = @_;

    my $buff = '';
    my $fh = $env->{'psgi.input'};
    while ($fh->read($buff, 4096, length($buff))) {
        1;
    }

    return $buff;
}

sub set {
    my($class, $app, $env) = @_;

    my $body = $class->_read_request_body($env);
    my $params = $app->decode_json( $body );

    if (my $error = $class->is_file_or_line_invalid($app, @$params{'filename','line'})) {
        return $error;
    }

    my $resp_data = $class->set_and_respond($app, $params);

    return [ 200,
            [ 'Content-Type' => 'application/json' ],
            [ $app->encode_json($resp_data) ],
          ];
}

sub delete {
    my($class, $app, $env, $id) = @_;

    my $bp = $class->get_stored($id);
    unless ($bp) {
        return [ 404,
                    ['Content-Type' => 'text/html'],
                    ["No breakpoint $id"] ];
    }
    my $remover = $class->actionable_remover;
    $app->$remover($bp);
    $class->delete_stored($id);

    return [ 204,
            [ ],
            [ ],
          ];
}

sub set_and_respond {
    my($class, $app, $params) = @_;

    my($file, $line, $code, $inactive) = @$params{'filename','line','code','inactive'};
    my $href = join('/',
                $class->response_url_base,
                Digest::MD5::md5_hex($file, $line, Time::HiRes::time)
            );

    my $set_inactive = exists($params->{inactive})
                        ? sub { shift->inactive($inactive) }
                        : sub {};

    my $changer;
    my $adder = $class->actionable_adder;
    if (exists $params->{code}) {
        # setting a breakpoint
        $changer = sub {
                $params->{file} = delete $params->{filename};
                my $bp = $app->$adder(%$params);
                $set_inactive->($bp);
                $class->set_stored($href, $bp);
            };
    } else {
        # changing a breakpoint
        my $bp = $class->get_stored($file, $line);
        $bp ||= $app->$adder(file => $file, line => $line, code => '0');
        $changer = sub { $set_inactive->($bp); $bp };
    }

    unless ($app->is_loaded($file)) {
        $app->postpone(
                $file,
                $changer
        );
        return;
    }

    my $bp = $changer->();
    my $resp_data = {   filename => $file,
                        line => $line,
                        code => $bp->code,
                        inactive => $bp->inactive,
                        href => $href,
                    };
    return $resp_data;
}


sub get {
    my($class, $app, $env, $id) = @_;

    my $bp = $class->get_stored($id);
    my %bp_data;
    @bp_data{'href','filename','line','code','inactive'}
        = ( $id,
            map { $bp->$_ } qw(file line code inactive) );

    return [ 200,
            ['Content-Type' => 'application/json'],
            [ $app->encode_json(\%bp_data) ],
          ];
}

sub get_all {
    my($class, $app, $env) = @_;
    my $req = Plack::Request->new($env);

    my %filters;
    foreach my $filter ( qw( line code inactive ) ) {
        $filters{$filter} = $req->param($filter) if defined $req->param($filter);
    }

    my @bp_list =
            map { my %bp_data;
                    @bp_data{'filename','line','code','inactive'}
                        = @$_{'file','line','code','inactive'};
                    \%bp_data;
                }
            map { Devel::Chitin::Breakpoint->get(file => $_, %filters) }
            defined($req->param('filename'))
                ? ($req->param('filename'))
                : $app->loaded_files;

    return [ 200, ['Content-Type' => 'application/json'],
            [ JSON::encode_json( \@bp_list ) ]
        ];
}

sub delete_stored {
    my($class, $id) = @_;
    my $s = $class->storage;
    delete $s->{$id};
}

sub get_stored {
    my($class, $id) = @_;
    my $s = $class->storage;
    return $s->{$id};
}

sub set_stored {
    my($class, $id, $item) = @_;
    my $s = $class->storage;
    $s->{$id} = $item;
}


1;

=pod

=head1 NAME

Devel::hdb::App::Breakpoint - Get and set breakpoints

=head1 DESCRIPTION

Breakpoints are perl code snippets run just before executable statements in
the debugged program.  If the code returns a true value, then the debugger
will stop before that program statement is executed.

These code snippets are run in the context of the debugged program and have
access to any of its variables, lexical included.

Unconditional breakpoints are usually stored as "1".  

=head2 Routes

=over 4

=item GET /breakpoint

Get breakpoint information about a particular file and line number.  Accepts
these parameters:
  f     File name
  l     Line number

Returns a JSON-encoded hash with these keys:
  filename  => File name
  lineno    => Line number
  code      => Breakpoint condition, or 1 for an unconditional break
  inactive  => 1 (yes) or undef (no), whether this breakpoint
                        is disabled/inactive

=item POST /breakpoint

Set a breakpoint.  Accepts these parameters:
  f     File name
  l     Line number
  c     Breakpoint condition code.  This can be a bit of Perl code to
        represent a conditional breakpoint, or "1" for an unconditional
        breakpoint.
  ci    Set to true to make the breakpoint condition inactive, false to
        clear the setting.

It responds with the same JSON-encoded hash as GET /breakpoint.  If the
condition is empty/false (to clear the breakpoint) the response will only
include the keys 'filename' and 'lineno'.

=item GET /delete-breakpoint

Delete a breakpoint on a particular file ane line number.  Requires these
parameters:
  f     File name
  l     Line number

=item GET /breakpoints

Request data about all breakpoints.  Return a JSON-encoded array.  Each
item in the array is a hash with the same information returned by GET
/breakpoint.

=back


=head1 SEE ALSO

Devel::hdb

=head1 AUTHOR

Anthony Brummett <brummett@cpan.org>

=head1 COPYRIGHT

Copyright 2014, Anthony Brummett.  This module is free software. It may
be used, redistributed and/or modified under the same terms as Perl itself.
