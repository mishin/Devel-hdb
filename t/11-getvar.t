use strict;
use warnings;

use lib 't';
use HdbHelper;
use WWW::Mechanize;
use JSON;

use Devel::hdb::App;  # for _encode_eval_data

use Test::More;
if ($^O =~ m/^MS/) {
    plan skip_all => 'Test hangs on Windows';
} else {
    plan tests => 85;
}

my $url = start_test_program();

my $json = JSON->new();
my $value;

my $mech = WWW::Mechanize->new();
my $resp = $mech->get($url.'continue');
ok($resp->is_success, 'continue');

$resp = $mech->post($url.'getvar', {l => 0, v => '$x'});
check_resp($resp,
        { expr => '$x', level => 0, result => 'hello' },
        'Get value of $x at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => '$y'});
check_resp($resp,
        { expr => '$y', level => 0, result => 2 },
        'Get value of $y at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => '$z'});
check_resp($resp,
        { expr => '$z', level => 0,
            result => { __reftype => 'HASH',
                        __value => { one => 1, two => 2 }
                    },
        },
        'Get value of $z at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => '$our_var'});
check_resp($resp,
        { expr => '$our_var', level => 0, result => 'ourvar' },
        'Get value of our var $our_var at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => '@bare_var'});
check_resp($resp,
        { expr => '@bare_var', level => 0,
            result => { __reftype => 'ARRAY',
                        __value => ['barevar', 'barevar']
                    },
        },
        'Get value of bare pkg var $bare_var at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => '$Other::Package::variable'});
check_resp($resp,
        { expr => '$Other::Package::variable', level => 0, result => 'pkgvar' },
        'Get value of pkg global $X at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => '@my_list'});
check_resp($resp,
        { expr => '@my_list', level => 0,
            result => { __reftype => 'ARRAY',
                        __value => [0,1,2],
                    },
        },
        'Get value of my var @my_list at level 0');


$resp = $mech->post($url.'getvar', {l => 1, v => '$x'});
check_resp($resp,
        { expr => '$x', level => 1, result => 1 },
        'Get value of $x at level 1');

$resp = $mech->post($url.'getvar', {l => 1, v => '$y'});
check_resp($resp,
        { expr => '$y', level => 1, result => 2 },
        'Get value of $y at level 1');

$resp = $mech->post($url.'getvar', {l => 1, v => '$z'});
check_resp($resp,
        { expr => '$z', level => 1, result => undef },
        'Get value of $z at level 1');

$resp = $mech->post($url.'getvar', {l => 1, v => '$our_var'});
check_resp($resp,
        { expr => '$our_var', level => 1, result => 'ourvar' },
        'Get value of our var $our_var at level 1');

$resp = $mech->post($url.'getvar', {l => 1, v => '@bare_var'});
check_resp($resp,
        { expr => '@bare_var', level => 1,
            result => { __reftype => 'ARRAY',
                        __value => ['barevar', 'barevar']
                    },
        },
        'Get value of bare package var $our_var at level 1');

$resp = $mech->post($url.'getvar', {l => 1, v => '$Other::Package::variable'});
check_resp($resp,
        { expr => '$Other::Package::variable', level => 1, result => 'pkgvar' },
        'Get value of pkg global $Other::Package::variable at level 1');

$resp = $mech->post($url.'getvar', {l => 0, v => '$my_list[1]'});
check_resp($resp,
        { expr => '$my_list[1]', level => 0, result => 1 },
        'Get value of $my_list[1] at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => '$my_list[$one]'});
check_resp($resp,
        { expr => '$my_list[$one]', level => 0, result => 1 },
        'Get value of $my_list[$one] at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => '@my_list[1, $two]'});
check_resp($resp,
        { expr => '@my_list[1, $two]', level => 0,
            result => { __reftype => 'ARRAY',
                        __value => [1,2],
                    },
        },
        'Get value of my var @my_list[1, $two] at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => '@my_list[$zero..3]'});
check_resp($resp,
        { expr => '@my_list[$zero..3]', level => 0,
            result => { __reftype => 'ARRAY',
                        __value => [0,1,2,undef],
                    },
        },
        'Get value of my var @my_list[$zero..3] at level 0');

$resp = $mech->post($url.'getvar', {l => 0, v => q($my_hash{1}) });
check_resp($resp,
        { expr => q($my_hash{1}), level => 0, result => 'one' },
        q(Get value of $my_hash{1} at level 0));

$resp = $mech->post($url.'getvar', {l => 0, v => q(@my_hash{1,2}) });
check_resp($resp,
        { expr => q(@my_hash{1,2}), level => 0,
                result => { __reftype => 'ARRAY',
                        __value => ['one','two'],
                    },
        },
        q(Get value of @my_hash{1,2} at level 0));

$resp = $mech->post($url.'getvar', {l => 0, v => q(@my_hash{$one,2}) });
check_resp($resp,
        { expr => q(@my_hash{$one,2}), level => 0,
                result => { __reftype => 'ARRAY',
                        __value => ['one','two'],
                    },
        },
        q(Get value of @my_hash{$one,2} at level 0));

$resp = $mech->post($url.'getvar', {l => 0, v => q(@my_hash{@my_list, 2}) });
check_resp($resp,
        { expr => q(@my_hash{@my_list, 2}), level => 0,
                result => { __reftype => 'ARRAY',
                        __value => [undef,'one','two','two'],
                    },
        },
        q(Get value of @my_hash{@my_list,2} at level 0));








sub check_resp {
    my $resp = shift;
    my $expected = shift;
    my $msg = shift;

    my $got = $json->decode($resp->content)->{data};

    ok($resp->is_success, $msg);
    is($got->{expr}, $expected->{expr}, 'Response expr matches');
    is($got->{level}, $expected->{level}, 'Level matches');

    if (ref $got->{result}) {
        delete ($got->{result}->{__refaddr});
    }

    is_deeply($got->{result}, $expected->{result},
        'Result is '.(defined($expected->{result}) ? '"'.$expected->{result}.'"' : 'undef'));
}

__DATA__
our $our_var = 'ourvar';
@bare_var = ('barevar', 'barevar');
$Other::Package::variable = 'pkgvar';
my $x = 1;
my $y = 2;
foo();
sub foo {
    my $x = 'hello',
    my $z = { one => 1, two => 2 };
    my $zero = 0;
    my $one = 1;
    my $two = 2;
    my @my_list = (0,1,2);
    my %my_hash = (1 => 'one', 2 => 'two', 3 => 'three');
    $DB::single=1;
    8;
}
