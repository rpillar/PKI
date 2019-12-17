#!/usr/bin/perl;

use strict;
use warnings;

use DDP;
use DBI;
use JSON;
use Path::Tiny;
use Perl::Critic;
use Perl::Metrics::Simple;

my $dbh = DBI->connect("dbi:SQLite:critic.db","","") or die "Could not connect";

# initialize the environment
_initialize();

# try to import every .pm file in /lib
my $path = '/Users/richardpillar/perl/Stylus-C/Stylus/lib';
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
    _collect_use_data( $module, $file );

}

sub _critic {
    my $file = shift;

    my @critic_data = ();

    my $critic = Perl::Critic->new( -theme => "maintenance" ); 
    my @issues = $critic->critique($file->stringify); 

    foreach ( @issues ) { 
        push @critic_data, [ $_->description, $_->line_number ]; 
    }
    
    return \@critic_data;
}

sub _collect_critic_data {
    my ( $module, $file ) = @_;

    my $critic_data = _critic( $file );

    my $query = "insert into critic (module, critic, line_number) values(?, ?, ?)";
    my $stmt  = $dbh->prepare( $query );

    foreach ( @{$critic_data} ) {
        $stmt->execute( $module, $_->[0], $_->[1] );
    }

    return;
}

sub _collect_metrics_data {
    my ( $module, $file ) = @_;

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
    $stmt->execute( $module, $summary->{ sub_complexity }->{ max }, $lines, 0 );

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

    $query = "delete from dependencies";
    $stmt  = $dbh->prepare( $query );
    $stmt->execute();

    return;
}

sub _collect_use_data {
    my ( $module, $file ) = @_;
    
    # go through the file and try to find out some things
    open my $fh, '<', $file or do { warn("Can't open file $file for read: $!"); return undef; };

    (my $filename = $file) =~ s/^\.//;

    my $file_data = {
        'file'          => $file,
        'filename'      => $filename,
        'data'          => {},
        'seen'          => {},
        'source'        => {},
        'in_pod'        => undef,
        'curr_pkg'      => undef,
        'curr_method'   => undef,
    };

    while (<$fh>) {
        s/\r?\n$//;
        $file_data->{'in_pod'} = 1 if m/^=\w+/ && !m/^=cut/;
        if ($file_data->{'in_pod'}) {
            $file_data->{'in_pod'} = 0 if /^=cut/;
            next;
        }
        last if m/^\s*__(END|DATA)__/;

        _parse_package( $file_data, $_ );
        
        # skip lines which are not belong to package namespace
        next if !$file_data->{'curr_pkg'};
        
        # append current line to package source
        $file_data->{'source'}->{$file_data->{'curr_pkg'}} .= $_ . "\n";

        # count non-empty lines
        #$self->count_package_lines($_);
        
        #$self->parse_sub($_);
        #$self->parse_super($_);
        #$self->parse_method_call($_);

        _parse_dependencies( $file_data, $_ );

        #$self->parse_inheritance($_, $fh);
    }
    close $fh;

    my $dependencies = $file_data->{data}->{$module}->{depends_on};
    p $dependencies;

    p $file_data->{data};
    my $query = "insert into dependencies (module, dependencies) values(?, ?)";
    my $stmt  = $dbh->prepare( $query );
    $stmt->execute( $module, encode_json($dependencies) );

    return $file_data->{'data'};
}

sub _parse_package {
    my ($file_data, $line) = @_;

    # get the package name
    if ($line =~ m/^\s*package\s+([\w\:]+)\s*;/) {
        my $curr_pkg = $1;
        $file_data->{'curr_pkg'} = $curr_pkg;
        $file_data->{'data'}->{$curr_pkg} = {
            'filename'         => $file_data->{'filename'},
            'filerootdir'      => $file_data->{'rootdir'},
            'package'          => $curr_pkg,
            'line_count'       => 0,
            'depends_on'       => [],
            'parent'           => [],
            'methods'          => [],
            'methods_super'    => [],
            'methods_used'     => {},
            'constants'        => {},
            'fields'           => [],
        };
    }

    return $file_data;
}

sub _parse_dependencies {
    my ($file_data, $line) = @_;
    
    # need to process 'use parent *****' in DBIX resultset classes.
    if ( $line =~ m/^\s*use\s+([\w\:]+)/ ) {
        if ( $1 ne "strict" and $1 ne "warnings" and $1 ne "parent" and $1 ne 'base' and $1 ne 'namespace::autoclean') {
            $file_data = _util_dpush($file_data, 'depends_on', $1);
        }
    }
    if ( $line =~ m/^\s*use\s+([\w\:]+)\s(\S+)/ ) {
        if ( $1 eq 'parent' or $1 eq 'base' ) {
            my $file = $2;
            $file =~ s/\'|\;//g;
            $file_data = _util_dpush($file_data, 'depends_on', $file);
        }
    }

    if ($line =~ m/^\s*require\s+([^\s;]+)/) { # "require Bar;" or "require 'Foo/Bar.pm' if $wibble;'
        my $required = $1;
        if ($required =~ m/^([\w\:]+)$/) {
            $file_data = _util_dpush($file_data, 'depends_on', $required);
        }
        elsif ($required =~ m/^["'](.*?\.pm)["']$/) { # simple Foo/Bar.pm case
            ($required = $1) =~ s/\.pm$//;
            $required =~ s!/!::!g;
            $file_data = _util_dpush($file_data, 'depends_on', $required);
        }
        else {
            warn "Can't interpret $line at line $. in $file_data->{file}\n"
                unless m!sys/syscall.ph!
                    or m!dumpvar.pl!
                    or $required =~ /^\$/   # dynamic 'require'
                    or $required =~ /^5\./;
        }
    }

    return $file_data;
}

sub _util_dpush {
    my ($file_data, $key, $value) = @_;
    my $curr_pkg = $file_data->{'curr_pkg'};
    push @{ $file_data->{'data'}->{$curr_pkg}->{$key} }, $value
        unless $file_data->{'seen'}->{$curr_pkg}->{$key}->{$value}++;

    return $file_data;
}

# EOF
