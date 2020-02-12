package Pki;
use Mojo::Base 'Mojolicious';

use Pki::Model;

# This method will run once at server start
sub startup {
  my $self = shift;

  # Load configuration from hash returned by config file
  my $config = $self->plugin('Config');

  # Configure the application
  $self->secrets($config->{secrets});

  # Router
  my $r = $self->routes;

  # routes
  $r->get('/')->to(controller => 'pki', action => 'welcome');
  $r->get('/summary')->to(controller => 'pki', action => 'summary');
  $r->get('/pod/:module')->to(controller => 'pki', action => 'pod');
}

1;
