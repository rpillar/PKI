package Pki::Controller::Pki;
use Mojo::Base 'Mojolicious::Controller';

use Config::JSON;
use Data::Printer;
use DateTime;
use JSON;
use Pod::Simple::Search;
use MetaCPAN::Pod::XHTML;

use DBI;
my $dbh = DBI->connect("dbi:SQLite:critic.db","","") or die "Could not connect";

=head2 critic

=cut

sub critic {
  my ( $self ) = @_;

  my $module = $self->param( 'module' );
  my @critics;

  my $critic_query = "select module, critic, line_number, source, explanation from critic where module = ?";
  my $critic_stmt  = $dbh->prepare( $critic_query );
  $critic_stmt->execute( $module );
  while ( my ( $module, $critic, $line_number, $source, $explanation ) = $critic_stmt->fetchrow_array ) {
    push @critics, { line_number => $line_number, critic => $critic, source => $source, explanation => $explanation };
  }

  my $critic_data = { data => \@critics };

  $self->render(json => $critic_data);
}

=head2 git_commit_stats

=cut

sub git_commit_stats {
  my $self = shift;

  my @data;
  my $gitcommits_query = "select * from gitcommits where date >= ?";
  my $gitcommits_stmt = $dbh->prepare( $gitcommits_query );

  my $date = DateTime->now();
  my $start_year = $date->year - 1;
  $gitcommits_stmt->execute( $start_year .'-01-01' );
  while ( my $gitcommits_data = $gitcommits_stmt->fetchrow_hashref ) {
    push @data, { 
      date    => $gitcommits_data->{ date },
      commits => $gitcommits_data->{ commits }
    };
  }

  my $commits_data = { data => \@data };

  $self->render(json => $commits_data);
}

=head2 pod

Retrieve POD, dependency data, inheritance data and gitlog data - render template.

=cut

sub pod {
  my ( $self ) = @_;

  my $config = Config::JSON->new("./script/runlib.conf");

  my $module    = $self->param( 'module' );
  my $pod_score = $self->param( 'pod_score' );

  if ( not $pod_score ) {
    my $summary_query = "select module, pod from summary where module = ?";
    my $summary_stmt  = $dbh->prepare( $summary_query );
    $summary_stmt->execute( $module );

    my ( $is_our_module, $my_pod_score ) = $summary_stmt->fetchrow_array;
    if ( not $is_our_module ) {
      return $self->res->code(301) && $self->redirect_to("https://metacpan.org/pod/$module");
    }
    $pod_score = $my_pod_score;
  }

  my $output;
  if ( $pod_score == 2 ) {
    my $path = Pod::Simple::Search->new->inc(0)->verbose(1)->find( $module, @{ $config->get('libs') } );
 
    my $parser = MetaCPAN::Pod::XHTML->new;
    $parser->$_('') for qw(html_header html_footer);
    $parser->anchor_items(1); # adds <a> to =items
    $parser->index(1);
    $parser->perldoc_url_prefix('/pod/');
    $parser->output_string(\$output);
    $parser->parse_file($path);

    # add a sidenav for the links etc.
    $output =~ s/\<ul id="index"\>/\<ul id="slide-out" class="sidenav" style="transform:translateX:(-100%);padding-top:20px;"\>/;
    $output =~ s/\<li\>\<a href=\"\#NAME\"\>NAME\<\/a\>\<\/li\>/\<li\>\<a href=\"\#NAME\"\>NAME\<\/a\>\<\/li\>\<li\>\<\/li\>/;
    $output =~ s/\<li\>\<a href=\"\#SYNOPSIS\"\>SYNOPSIS\<\/a\>\<\/li\>/\<li\>\<a href=\"\#SYNOPSIS\"\>SYNOPSIS\<\/a\>\<\/li\>/;
    $output =~ s/\<li\>\<a href=\"\#DESCRIPTION\"\>DESCRIPTION\<\/a\>\<\/li\>/\<li\>\<a href=\"\#DESCRIPTION\"\>DESCRIPTION\<\/a\>\<\/li\>/;
    $output =~ s/\<li\>\<a href=\"\#USAGE\"\>USAGE\<\/a\>\<\/li\>/\<li\>\<a href=\"\#USAGE\"\>USAGE\<\/a\>\<\/li\>/;
    $output =~ s/\<li\>\<a href=\"\#METHODS\"\>PROPERTIES\<\/a\>\<\/li\>/\<li\>\<a href=\"\#PROPERTIES\"\>PROPERTIES\<\/a\>\<\/li\>/;
    $output =~ s/\<li\>\<a href=\"\#METHODS\"\>METHODS\<\/a\>\<\/li\>/\<li\>\<a href=\"\#METHODS\"\>METHODS\<\/a\>\<\/li\>/;
  }

  my ( $dependency_data, $inheritance_data ) = $self->_info( $module );
  my $gitlog                                 = $self->_gitlog( $module );

  # Render template "pki/pod.html.ep" with pod output
  $self->render(
    template     => 'pki/pod', 
    pod          => $output, 
    pod_score    => $pod_score,
    dependencies => $dependency_data, 
    inheritance  => $inheritance_data,
    gitlog       => $gitlog
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
      max_complexity => $summary_data->{ max_complexity } ? $summary_data->{ max_complexity } : 0,
      avg_complexity => $summary_data->{ avg_complexity } ? $summary_data->{ avg_complexity } : 0,
      lines => $summary_data->{ lines },
      subs  => $summary_data->{ sub_count },
      pod        => '/' . $summary_data->{ module } . '/' . $summary_data->{ pod },
      hierarchy  => "N",
      critic     => 'critic/' . $summary_data->{ module },
    }; 
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

sub _gitlog {
  my ( $self, $module ) = @_;

  # get gitlog data
  my $gitlog_query = "select module, log from gitlog where module = ?";
  my $gitlog_stmt  = $dbh->prepare( $gitlog_query );
  $gitlog_stmt->execute( $module );
  my ( $module_name, $gitlog_data ) = $gitlog_stmt->fetchrow_array;
  $gitlog_data =~ s/^\s+//;
  $gitlog_data =~ s/^\t+//;

  return $gitlog_data;
}

sub _info {
  my ( $self, $module ) = @_;

  # get dependency data
  my $dependency_query = "select module, dependencies from dependencies where module = ?";
  my $dependency_stmt  = $dbh->prepare( $dependency_query );
  $dependency_stmt->execute( $module );
  my ( $module_name, $dependency_jsondata ) = $dependency_stmt->fetchrow_array;
  my $dependency_data                       = decode_json( $dependency_jsondata );

  # get inheritance data
  my $inheritance_query = "select module, inheritance from inheritance where module = ?";
  my $inheritance_stmt  = $dbh->prepare( $inheritance_query );
  $inheritance_stmt->execute( $module );
  my ( $inheritance_module, $inheritance_jsondata ) = $inheritance_stmt->fetchrow_array;
  my $inheritance_data                              = decode_json( $inheritance_jsondata );

  return ( $dependency_data, $inheritance_data );
}

1;
