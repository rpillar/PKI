# PerlKwaliteeInfo
A small app used to display info on the quality of your perl code with links to module POD / info. Built using Mojolicious and inspired in part by Dave Cross. 

The parsing of the modules to pull out inheritance / dependency data is based on work found here - http://technix.github.io/Perl-Analyzer/

# Notes

The config file - `filelib.conf` - holds the full path to libraries that are parsed during the runnning of the `perl_files.pl` script **or** when the app is running the possible location of the modules that are parsed for POD. These locations may differ and whilst I could have two config files I leave it up to the user to amend the file as necessary.

# To run

To run the script to parse files / collect data :-

```
> perl ./script/perl_files.pl
```

To run the app - at the command line :-
```
> morbo -l http://localhost:3020 ./script/pki
```
