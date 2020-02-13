package Pki::Controller::Pki;
use Mojo::Base 'Mojolicious::Controller';

use Config::JSON;
use Data::Printer;
use JSON;
use Pod::Simple::Search;
use MetaCPAN::Pod::XHTML;

use DBI;
my $dbh = DBI->connect("dbi:SQLite:critic.db","","") or die "Could not connect";

=head2 pod

=cut

sub pod {
  my ( $self ) = @_;

  my $config = Config::JSON->new("./script/filelib.conf");

  my $module = $self->param('module');
  $self->app->log->debug('PKI - find pod for :' . $module);
  use Data::Dumper;
  $self->app->log->debug('PKI - debug : config libs - ' . Dumper($config->get('libs')));
  my $path = Pod::Simple::Search->new->inc(0)->verbose(1)->find( $module, @{ $config->get('libs') } );
  $self->app->log->debug('PKI - debug : module path - ' . $path );
  return $self->res->code(301) && $self->redirect_to("https://metacpan.org/pod/$module") unless $path && -r $path;

  my $parser = MetaCPAN::Pod::XHTML->new;
  $parser->$_('') for qw(html_header html_footer);
  $parser->anchor_items(1); # adds <a> to =items
  $parser->index(1);
  $parser->perldoc_url_prefix('/pod/');
  $parser->output_string(\my $output);
  $parser->parse_file($path);

  # add a sidenav for the links etc.
  $output =~ s/\<ul id="index"\>/\<ul id="slide-out" class="sidenav" style="transform:translateX:(-100%);padding-top:20px;"\>/;
  $output =~ s/\<li\>\<a href=\"\#NAME\"\>NAME\<\/a\>\<\/li\>/\<li\>\<a href=\"\#NAME\"\>NAME\<\/a\>\<\/li\>\<li\>\<\/li\>/;
  $output =~ s/\<li\>\<a href=\"\#SYNOPSIS\"\>SYNOPSIS\<\/a\>\<\/li\>/\<li\>\<a href=\"\#SYNOPSIS\"\>SYNOPSIS\<\/a\>\<\/li\>/;
  $output =~ s/\<li\>\<a href=\"\#DESCRIPTION\"\>DESCRIPTION\<\/a\>\<\/li\>/\<li\>\<a href=\"\#DESCRIPTION\"\>DESCRIPTION\<\/a\>\<\/li\>/;
  $output =~ s/\<li\>\<a href=\"\#USAGE\"\>USAGE\<\/a\>\<\/li\>/\<li\>\<a href=\"\#USAGE\"\>USAGE\<\/a\>\<\/li\>/;
  $output =~ s/\<li\>\<a href=\"\#METHODS\"\>METHODS\<\/a\>\<\/li\>/\<li\>\<a href=\"\#METHODS\"\>METHODS\<\/a\>\<\/li\>/;

  my ( $dependency_data, $inheritance_data ) = $self->_info( $module );
  my $critics                                = $self->_critic( $module );

  # Render template "pki/pod.html.ep" with pod output
  $self->render(
    template => 'pki/pod', 
    pod => $output, 
    dependencies => $dependency_data, 
    inheritance => $inheritance_data,
    critics => $critics
  );
}

=head2 summary

=cut 

sub summary {
  my $self = shift;

  my @modules;
  my $summary_query = "select * from summary";
  my $summary_stmt = $dbh->prepare( $summary_query );

  $summary_stmt->execute;
  while ( my $summary_data = $summary_stmt->fetchrow_hashref ) {
    push @modules, { 
      module     => $summary_data->{ module },
      compiles   => "Y",
      complexity => $summary_data->{max_complexity} ? $summary_data->{max_complexity} : 0,
      pod        => '/' . $summary_data->{ module },
      pod_score  => $summary_data->{pod},
      hierarchy  => "N",
      critic     => 'critic/' . $summary_data->{ module },
    } 
  }

  my $table_data = { data => \@modules };

  $self->render(json => $table_data);
}

=head2 welcome

=cut

sub welcome {
  my $self = shift;

  # Render template "pki/welcome.html.ep"
  $self->render(template => 'pki/welcome');
}

# utility methods

sub _critic {
  my ( $self, $module ) = @_;

  $self->app->log->debug($module);
  my ( @critics, @dependencies );

  my $critic_query = "select module, critic, line_number from critic where module = ?";
  my $critic_stmt  = $dbh->prepare( $critic_query );
  $critic_stmt->execute( $module );
  while ( my ( $module, $critic, $line_number ) = $critic_stmt->fetchrow_array ) {
    push @critics, { line_number => $line_number, critic => $critic };
  }

  return \@critics;
}

sub _info {
  my ( $self, $module ) = @_;

  # get dependency data
  my $dependency_query = "select module, dependencies from dependencies where module = ?";
  my $dependency_stmt  = $dbh->prepare( $dependency_query );
  $dependency_stmt->execute( $module );
  my ( $module_name, $dependency_jsondata ) = $dependency_stmt->fetchrow_array;
  my $dependency_data                       = decode_json( $dependency_jsondata );
  #push @dependencies, { dependency => $dependency_data };

  # get inheritance data
  my $inheritance_query = "select module, inheritance from inheritance where module = ?";
  my $inheritance_stmt  = $dbh->prepare( $inheritance_query );
  $inheritance_stmt->execute( $module );
  my ( $inheritance_module, $inheritance_jsondata ) = $inheritance_stmt->fetchrow_array;
  my $inheritance_data                              = decode_json( $inheritance_jsondata );

  return ( $dependency_data, $inheritance_data );
}

1;
