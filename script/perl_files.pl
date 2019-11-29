#!/usr/bin/perl;

use strict;
use warnings;

use DDP;
use DBI;
use Path::Tiny;
use Perl::Critic;
use Perl::Metrics::Simple;
use Pod::Coverage;

my $dbh = DBI->connect("dbi:SQLite:critic.db","","") or die "Could not connect";

# initialize the environment
_initialize();

# try to import every .pm file in /lib
my $path = '/Users/richardpillar/perl/Stylus-C/Stylus/lib/';
my $dir = path($path);
my $iter = $dir->iterator({
    recurse         => 1,
    follow_symlinks => 0,
});

my $analyzer = Perl::Metrics::Simple->new;

_initialize();

while (my $path = $iter->()) {
    next if $path->is_dir || $path !~ /\.pm$/;
    my $file = $path->relative;

    my $module;
    ( $module = $file ) =~ s/(^.+\/lib\/|\.pm$)//g;
    $module =~ s/\//::/g;
    
    _collect_metrics_data( $module, $file );
    _collect_critic_data( $module, $file );
}

sub _critic {
    my $file = shift;

    my @critic_data = ();

    my $critic = Perl::Critic->new( -theme => "maintenance" ); 
    my @issues = $critic->critique($file->stringify); 
    foreach ( @issues ) { 
        push @critic_data, $_->description; 
    }
    
    return \@critic_data;
}

sub _collect_critic_data {
    my ( $module, $file ) = @_;

    my $critic_data = _critic( $file );

    my $query = "insert into critic (module, critic) values(?, ?)";
    my $stmt  = $dbh->prepare( $query );

    foreach ( @{$critic_data} ) {
        $stmt->execute( $module, $_ );
    }

    return;
}

sub _collect_metrics_data {
    my ( $module, $file ) = @_;

    my $pc = Pod::Coverage->new( package => $module );
    my $coverage = $pc->coverage;

    my @file_array = ( $file->stringify );
    my $analysis = $analyzer->analyze_files( @file_array );

    my $query = "insert into metrics (module, subname, complexity, lines) values(?, ?, ?, ?)";
    my $stmt  = $dbh->prepare( $query );

    foreach ( @{ $analysis->subs } ) {
        if ( $_->{ mccabe_complexity } > 10 ) {
            $stmt->execute( $module, $_->{ name }, $_->{ mccabe_complexity }, $_->{ lines } );
        }
    }

    my $summary = $analysis->summary_stats;
    my $lines   = $analysis->lines;
    $query = "insert into summary (module, max_complexity, lines, pod) values(?, ?, ?, ?)";
    $stmt  = $dbh->prepare( $query );
    $stmt->execute( $module, $summary->{ sub_complexity }->{ max }, $lines, $coverage ? $coverage * 10  : 0 );

    return;
}

sub _initialize {
    my $query = "delete from critic";
    my $stmt  = $dbh->prepare( $query );
    $stmt->execute();

    $query = "delete from metrics";
    $stmt  = $dbh->prepare( $query );
    $stmt->execute();

    $query = "delete from summary";
    $stmt  = $dbh->prepare( $query );
    $stmt->execute();

    return;
}

# EOF
