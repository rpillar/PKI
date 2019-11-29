package PKI::Controller::Pki;
use Mojo::Base 'Mojolicious::Controller';

use Config;
use Pod::Simple::Search;
use MetaCPAN::Pod::XHTML;

use DBI;
my $dbh = DBI->connect("dbi:SQLite:critic.db","","") or die "Could not connect";

# This action will render a template
sub welcome {
  my $self = shift;

  # Render template "pki/welcome.html.ep" with message
  my $modules = $self->_modules();
  $self->render(modules => $modules);
}

sub dashboard {
  my $self = shift;

  # Render template "pki/dashboard.html.ep" with message
  $self->render();
}

sub info {
  my ( $self ) = @_;

  my $module = $self->param('module');

  # Render template "pki/info.html.ep"
  $self->render(template => 'test/info' );
}

sub pod {
  my ( $self ) = @_;

  my $module = $self->param('module');

  my $path = Pod::Simple::Search->new->inc(0)->find($module, ("/Users/richardpillar/perl/Stylus-C/Stylus/lib"));

  my $parser = MetaCPAN::Pod::XHTML->new;
  $parser->$_('') for qw(html_header html_footer);
  $parser->anchor_items(1); # adds <a> to =items
  $parser->index(1);
  $parser->perldoc_url_prefix('/');
  $parser->output_string(\my $output);
  $parser->parse_file($path);

  # Render template "test/pod.html.ep" with pod output
  $self->render(template => 'test/pod', pod => $output );
}

sub _modules {
  my $self = shift;

  my @modules;

  my $critic_query = "select distinct(module) from critic";
  my $critic_stmt  = $dbh->prepare( $critic_query );
  my $summary_query = "select * from summary where module = ?";
  my $summary_stmt = $dbh->prepare( $summary_query );

  $critic_stmt->execute;
  while ( my $module = $critic_stmt->fetchrow_array ) {
    $summary_stmt->execute( $module );
    my $summary_data = $summary_stmt->fetchrow_hashref;
    push @modules, { 
      module     => $module,
      compiles   => "Y",
      complexity => $summary_data->{max_complexity} ? $summary_data->{max_complexity} : 0,
      pod        => '/pod/' . $module,
      pod_score  => $summary_data->{pod},
      hierarchy  => "N"
    } 
  }

  return \@modules;
}

1;
