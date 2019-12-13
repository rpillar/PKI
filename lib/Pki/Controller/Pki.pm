package Pki::Controller::Pki;
use Mojo::Base 'Mojolicious::Controller';

use Config;
use Pod::Simple::Search;
use MetaCPAN::Pod::XHTML;

use DBI;
my $dbh = DBI->connect("dbi:SQLite:critic.db","","") or die "Could not connect";

# This action will render a template
sub welcome {
  my $self = shift;

  # Render template "pki/welcome.html.ep"
  $self->render(template => 'pki/welcome');
}

sub critic {
  my ( $self ) = @_;

  my $module = $self->param('module');
  $self->app->log->debug($module);
  my @critics;

  my $critic_query = "select module, critic, line_number from critic where module = ?";
  my $critic_stmt  = $dbh->prepare( $critic_query );
  $critic_stmt->execute( $module );
  while ( my ( $module, $critic, $line_number ) = $critic_stmt->fetchrow_array ) {
    push @critics, { line_number => $line_number, critic => $critic };
  }

  # Render template "pki/critic.html.ep"
  $self->render(template => 'pki/critic', module => $module, critics => \@critics);
}

sub dashboard {
  my $self = shift;

  # Render template "pki/dashboard.html.ep" with message
  $self->render();
}

sub pod {
  my ( $self ) = @_;

  my $module = $self->param('module');

  my $path = Pod::Simple::Search->new->inc(0)->find($module, ("/Users/richardpillar/perl/Stylus-C/Stylus/lib"));

  return $self->res->code(301) && $self->redirect_to("https://metacpan.org/pod/$module") unless $path && -r $path;

  my $parser = MetaCPAN::Pod::XHTML->new;
  $parser->$_('') for qw(html_header html_footer);
  $parser->anchor_items(1); # adds <a> to =items
  $parser->index(1);
  $parser->perldoc_url_prefix('/');
  $parser->output_string(\my $output);
  $parser->parse_file($path);

  # add a sidenav for the links etc.
  $output =~ s/\<ul id="index"\>/\<ul id="slide-out" class="sidenav sidenav-fixed" style="padding-top:20px;"\>/;
  $output =~ s/\<li\>\<a href=\"\#NAME\"\>NAME\<\/a\>\<\/li\>/\<li\>\<a href=\"\#NAME\"\>NAME\<\/a\>\<\/li\>\<div class=\"divider\"\>\<\/div\>/;
  $output =~ s/\<li\>\<a href=\"\#SYNOPSIS\"\>SYNOPSIS\<\/a\>\<\/li\>/\<li\>\<a href=\"\#SYNOPSIS\"\>SYNOPSIS\<\/a\>\<\/li\>\<div class=\"divider\"\>\<\/div\>/;
  $output =~ s/\<li\>\<a href=\"\#DESCRIPTION\"\>DESCRIPTION\<\/a\>\<\/li\>/\<li\>\<a href=\"\#DESCRIPTION\"\>DESCRIPTION\<\/a\>\<\/li\>\<div class=\"divider\"\>\<\/div\>/;
  $output =~ s/\<li\>\<a href=\"\#USAGE\"\>USAGE\<\/a\>\<\/li\>/\<li\>\<a href=\"\#USAGE\"\>USAGE\<\/a\>\<\/li\>\<div class=\"divider\"\>\<\/div\>/;
  $output =~ s/\<li\>\<a href=\"\#METHODS\"\>METHODS\<\/a\>\<\/li\>/\<li\>\<a href=\"\#METHODS\"\>METHODS\<\/a\>\<\/li\>\<div class=\"divider\"\>\<\/div\>/;

  # Render template "pki/pod.html.ep" with pod output
  $self->render(template => 'pki/pod', pod => $output );
}

sub summary {
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
      pod        => '/' . $module,
      pod_score  => $summary_data->{pod},
      hierarchy  => "N",
      critic     => 'critic/' . $module,
    } 
  }

  my $table_data = { data => \@modules };

  $self->render(json => $table_data);
}

1;
