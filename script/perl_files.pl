#!/usr/bin/perl;

use strict;
use warnings;

use Config::JSON;
use DDP;
use DBI;
use JSON;
use Path::Tiny;
use Perl::Critic;
use Perl::Metrics::Simple;
use Pod::Simple::Search;
use Safe;

my $dbh = DBI->connect("dbi:SQLite:critic.db","","") or die "Could not connect";

# initialize the environment
_initialize();

my $analyzer = Perl::Metrics::Simple->new;
my $libs;

# try to import every .pm file in /lib
my $config = Config::JSON->new("./script/filelib.conf");

foreach ( @{ $config->get('libs') } ) {
    my $path = $_;
    my $dir = path($path);
    my $iter = $dir->iterator({
        recurse         => 1,
        follow_symlinks => 0,
    });

    while (my $path = $iter->()) {
        next if $path->is_dir || $path !~ /\.pm$/;
        my $file = $path->relative;

        my $module;
        ( $module = $file ) =~ s/(^.+\/lib\/|\.pm$)//g;
        $module =~ s/\//::/g;
    
        my $pod_score = _collect_pod_data( $module, $file );
        _collect_metrics_data( $module, $file, $pod_score );
        _collect_critic_data( $module, $file );
        _collect_use_data( $module, $file );
    }
}

=head2 _collect_critic_data

=cut

sub _collect_critic_data {
    my ( $module, $file ) = @_;

    my @critic_data = ();
    my $critic = Perl::Critic->new( -severity => 3, -theme => "maintenance" ); 
    my @issues = $critic->critique($file->stringify); 

    foreach ( @issues ) { 
        push @critic_data, [ $_->description, $_->line_number ]; 
    }

    my $query = "insert into critic (module, critic, line_number) values(?, ?, ?)";
    my $stmt  = $dbh->prepare( $query );

    foreach ( @critic_data ) {
        $stmt->execute( $module, $_->[0], $_->[1] );
    }

    return;
}

=head2 _collect_metrics_data

=cut

sub _collect_metrics_data {
    my ( $module, $file, $pod_score ) = @_;

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
    $query = "insert into summary (module, avg_complexity, max_complexity, lines, pod, sub_count) values(?, ?, ?, ?, ?, ?)";
    $stmt  = $dbh->prepare( $query );
    $stmt->execute( 
        $module, 
        $summary->{ sub_complexity }->{ mean } ? int($summary->{ sub_complexity }->{ mean } ) : 0, 
        $summary->{ sub_complexity }->{ max }, 
        $lines || 0, 
        $pod_score || 0,
        $analysis->sub_count()
    );

    return;
}

=head2 _collect_pod_data

Returns a 1 / 0 depending on whether the B<file> contains POD

=cut

sub _collect_pod_data {
    my ( $module, $file ) = @_;

    my $finder = Pod::Simple::Search->new;
    if ( $finder->contains_pod( $file ) ) {
        return 1;
    }

    return 0;
}

=head2 _collect_use_data

=cut

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

        _parse_inheritance( $file_data, $_, $fh );
    }
    close $fh;

    my $dependencies = $file_data->{data}->{$module}->{depends_on};
    my $inheritance  = $file_data->{data}->{$module}->{parent};

    my $query = "insert into dependencies (module, dependencies) values(?, ?)";
    my $stmt  = $dbh->prepare( $query );
    $stmt->execute( $module, encode_json($dependencies) );

    $query = "insert into inheritance (module, inheritance) values(?, ?)";
    $stmt  = $dbh->prepare( $query );
    $stmt->execute( $module, encode_json($inheritance) );

    return $file_data->{'data'};
}

=head2 _initialize

Reset everything before scanning the specified repos

=cut

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

    $query = "delete from inheritance";
    $stmt  = $dbh->prepare( $query );
    $stmt->execute();

    return;
}

=head2 _parse_dependencies

=cut

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

=head2 _parse_inheritance

=cut

sub _parse_inheritance {
    my ($file_data, $line, $fh) = @_;
   
    # the 'use base/parent' pragma
    if ($line =~ m/^\s*use\s+(base|parent)\s+(.*)/) {
        ( my $list = $2 ) =~ s/\s+\#.*//;
        $list =~ s/[\r\n]//;
        while ( $list !~ /;\s*$/ && ( $_ = <$fh> ) ) {
            s/\s+#.*//; # remove any comments
            s/[\r\n]//; # remove line endings
            $list .= $_;
        }
        $list =~ s/;\s*$//;
        my (@mods) = Safe->new()->reval($list);
        warn "Unable to eval $line at line $. in $file_data->{file}: $@\n" if $@;
        foreach my $mod (@mods) {
            $file_data = _util_dpush($file_data, 'parent', $mod);
        }
    }

    # there will be a way to make this better - but ....
    if ($line =~ m/^extends\s+(.*)/ ) {
        ( my $list = $1 ) =~ s/\s+\#.*//;
        $list =~ s/[\r\n]//;
        my (@mods) = Safe->new()->reval($list);
        foreach my $mod (@mods) {
            $file_data = _util_dpush($file_data, 'parent', $mod);
        }
    }

    if ($line =~ m/BEGIN\s+\{*\s*extends\s+'*([\w\:]+)'*\s*\}*/ ) {
        ( my $list = $1 ) =~ s/\s+\#.*//;
        $list =~ s/[\r\n]//;
        my (@mods) = Safe->new()->reval($list);
        foreach my $mod (@mods) {
            $file_data = _util_dpush($file_data, 'parent', $mod);
        }
    }

    return $file_data;
}

=head2 _parse_package

=cut

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

=head2 _util_dpush

=cut

sub _util_dpush {
    my ($file_data, $key, $value) = @_;

    my $curr_pkg = $file_data->{'curr_pkg'};
    push @{ $file_data->{'data'}->{$curr_pkg}->{$key} }, $value
        unless $file_data->{'seen'}->{$curr_pkg}->{$key}->{$value}++;

    return $file_data;
}

# EOF
