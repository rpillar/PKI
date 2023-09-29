# PerlKwaliteeInfo
A small app used to display info on the quality of your perl code with links to module POD / info. Built using Mojolicious and inspired in part by Dave Cross. 

The parsing of the modules to pull out inheritance / dependency data is based on work found here - http://technix.github.io/Perl-Analyzer/

# Notes

To initialize the database (sqlite) start sqlite - `sqlite3 critic.db` - and at the sqlite prompt run - `.read initial.sql`. 

The config file - `modulelib.conf` - holds the full path to libraries that are parsed during the runnning of the `perl_files.pl` script. When the app is running the possible location of the modules that are parsed for POD may be different - use `runlib.conf` to ensure that (if there are differences) these are picked up.

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
Add code to process roles - *with*
Collect and display info about a where a module is used.
Add module dependency graphs
