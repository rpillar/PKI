# PKI
A small app used to display info on the quality of your perl code with links to module POD / info. Built using Mojolicious and inspired in part by Dave Cross. 

The parsing of the modules to pull out inheritance / dependency data is based on work found here - http://technix.github.io/Perl-Analyzer/

# Notes

To initialize the database (sqlite) start sqlite - `sqlite3 critic.db` - and at the sqlite prompt run - `.read initial.sql`. 

The config file - `./script/modulelib.conf` - holds the full path to libraries that are parsed during the runnning of the `perl_files.pl` script. When the app is running the possible location of the modules that are parsed for POD may be different - use `./script/runlib.conf` to ensure that (if there are differences) these are picked up.

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
 - Add code to process roles - *with* / also *require*
 - Collect and display info about where a module is used.
 - Add module dependency graphs
 - Fix links within POD
 - Add flag so that interface / scripts *only* process source files - not GIT
