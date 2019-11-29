use Mojo::Base -strict;

use PKI::More;
use PKI::Mojo;

my $t = PKI::Mojo->new('PKI');
$t->get_ok('/')->status_is(200)->content_like(qr/Mojolicious/i);

done_testing();
