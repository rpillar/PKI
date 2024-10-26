# PKI
A small app used to display info on the quality of your perl code with links to module POD / info. Built using Mojolicious and inspired in part by Dave Cross. 

The parsing of the modules to pull out inheritance / dependency data is based on work found here - http://technix.github.io/Perl-Analyzer/

# Notes

To initialize the database (sqlite) start sqlite - `sqlite3 critic.db` - and at the sqlite prompt run - `.read initial.sql`. 

The config file - `./script/modulelib.conf` - holds the full path to libraries that are parsed during the runnning of the `perl_files.pl` script. When the app is running the possible location of the modules that are parsed for POD may be different - use `./script/runlib.conf` to ensure that (if there are differences) these are picked up.

As an example of this difference - for the Dancer web framework the git data would be downloaded from https://github.com/PerlDancer/Dancer.git and the source code (for POD) is downloaded from CPAN (https://metacpan.org/pod/Dancer).

### `./script/modulelib.conf`

```
{
    "libs":  [ "<full path to /lib - add as many as you want>" ],
    "git": "<full path to the 'base' of your 'local' git repo>"
}
```

### `./script/runlib.conf`

```
{
    "libs":  [ "<full path to /lib - add as many as you want>" ]
}
```

Install any requested / missing modules using `cpanm`.

# To run

To run the script to parse files / collect data :-

```
> perl ./script/perl_files.pl
```

To run the app - at the command line :-
```
> morbo -l http://localhost:3020 ./script/pki
```

# Updates
 - refactor Controller code - introduce a *Service* layer that will contain the code to *get the data* - create 
 a *thin* controller.
 - investigate whether the POD generation can be replaced with `App::sdview`
 - Add code to process roles - *with* / also *require*
 - distinguish between internal / external dependencies
 - Add module dependency graphs
 - Fix links within POD
 - Add flag so that interface / scripts *only* process source files - not GIT
 - Would it be possible - add a process that will analyse scripts for POD and allow the "user' to
 document dependencies / tables used and updated etc. 
 - Make Perl::Critic settings 'flexible' - create a 'settings' function where the 'user' could set the location of _critic_ file (env var `PERLCRITIC`) or state the _theme_ required. A settings _function_ could support user settings for other _things_.

 # Further Notes

 This code tries to provide a way of viewing information about the code base that is _pointed at_. If you would like to just see
 the complexity scores using `Perl::Metrics::Simple` then :-
 ```
 use Perl::Metrics::Simple;
 
 my $analyzer = Perl::Metrics::Simple->new;
 ```


