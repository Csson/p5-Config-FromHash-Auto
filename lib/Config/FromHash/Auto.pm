use strict;
use warnings;

package Config::FromHash::Auto;

# VERSION
# ABSTRACT: Auto config from share dir

use Moo::Role;
use Config::FromHash;
use Dir::Self;
use File::HomeDir();
use File::ShareDir::Tarball 'dist_file';
use Path::Tiny;
use List::Util();

has auto => (
    is => 'rw',
    default => sub {
        shift->autoconfigure;
    },
);
has mode => (
    is => 'ro',
    lazy => 1,
    default => sub {
        shift->auto->{'mode'};
    }
);
has dist => (
    is => 'ro',
    lazy => 1,
    default => sub {
        shift->auto->{'autoconf'}->get('dist_name')
    },
);


has config => (
    is => 'ro',
    lazy => 1,
    default => sub {
        my $self = shift;

        my $autoconf = $self->auto->{'autoconf'};
        my $config_key = $autoconf->get('config_key') || die "'config_key' not set in conf.autoconf";
        my $mode_settings = $autoconf->get('modes/'.$self->auto->{'mode'});

        my $config_file = $self->parse_path(delete $mode_settings->{'config_file'});

        my $config = Config::FromHash->new(filename => $config_file->realpath);

        $config->data->{ $config_key }{'mode'} = $self->mode;
        for my $setting (keys %$mode_settings) {
            $config->data->{ $config_key }{ $setting } = $self->parse_path($mode_settings->{ $setting })->realpath;
        }
        return $config;
    },
);

requires qw/package dir/;

sub get {
    my $self = shift;
    my $path = shift;
    return $self->config->get($path);
}

sub parse_path {
    my $self = shift;
    my $pathref = shift;

    my @parts = ();
    for my $part (@$pathref) {
        if($part =~ m{^:(?<clean>.*)}) {
            if($+{'clean'} eq 'dist_dir') {
                push @parts => $self->auto->{'dist_dir'}->parent;
            }
            else {
                my $method = $+{'clean'};
                my $homedir_location = File::HomeDir->$method($self->dist);

                if(!defined $homedir_location) {
                    die sprintf "%s('%s') returns undef, needs to be created", $method, $self->dist;
                }
                push @parts => $homedir_location;
            }
        }
        else {
            push @parts => $part;
        }
    }
    return path(@parts);
}

# This tries to find the configuration for Config::FromHash::Auto
sub autoconfigure {
    my $self = shift;

    my @dist_dir_parts = $self->get_dist_dir_parts;

    my($autoconf, $mode_file);

    # If we are in a lib directory, we assume that the autoconfiguration is in ../share
    #   most likely since we are using Config::FromHash::Auto from a not installed module.
    # If we are *not* in a lib directory, we assume that the autoconfiguration is in
    #   the distribution's sharedir.
    my $dist_dir = path('/',@dist_dir_parts);
    if($dist_dir_parts[-1] eq 'lib') {
        # Here we are in lib, expecting a ../share directory

        my $autoconf_file = path($dist_dir->parent, qw<share conf.autoconf>);
        $mode_file = path($dist_dir->parent, qw<share mode.autoconf>);

        if($autoconf_file->is_file) {
            $autoconf = Config::FromHash->new(filename => $autoconf_file->realpath);
        }
        else {
            die "Can't find conf.autoconf in " . $autoconf_file;
        }
    }
    else {
        # The using module is installed, check in its installed ShareDir for conf.autoconf
        my $autoconf_file = path(dist_file($self->dist, 'conf.autoconf'));

        if($autoconf_file->is_file) {
            $autoconf = Config::FromHash->new(filename => $autoconf_file->realpath);
        }
        else {
            die "Can't find conf.autoconf in the distribution's sharedir";
        }
    }

    my $mode = defined $mode_file && $mode_file->is_file                                       ? $mode_file->slurp
             : defined $autoconf->get('mode_env') && exists $ENV{ $autoconf->get('mode_env') } ? $ENV{ $autoconf->get('mode_env') }
             :                                                                                   undef
             ;
    if(!defined $mode) {
        die qq{Config::FromHash::Auto can't set the mode. Possible reasons: 1. There is no [$mode_file] 2. 'mode_env' in autoconf.conf is set to [@{[ $autoconf->get('mode_env') ]}], but it is not set.};
    }

    if(List::Util::none { $mode eq $_ } keys %{ $autoconf->data->{'modes'} }) {
        die sprintf qq{Config::FromHash::Auto can't set the mode. Attempt to set the mode to '%s', but allowed values in conf.autoconf are: (%s)}, $mode, join ', ' => sort keys %{ $autoconf->data->{'modes'} };
    }

    return {
        mode => $mode,
        autoconf => $autoconf,
        dist_dir => $dist_dir,
    };
}

sub get_dist_dir_parts {
    my $self = shift;

    # Where do we start our search?
    my $path = path($self->dir)->realpath;
    my @package_parts = split /::/ => $self->package;
    pop @package_parts; # pops the filename, only looking for directories

    my @dir_parts = split m{/} => $path->stringify;
    shift @dir_parts; # don't want leading /
    my $failed = 0;

    # We traverse the directory structure and package parts
    while(my $part = pop @package_parts) {
        my $dir_part = pop @dir_parts;

        if($dir_part ne $part) {
            $failed = 1;
        }
    }

    # If the directories don't match the package we get confused.
    if($failed) {
        die "Could not traverse [@{[ $self->package ]}] in [$path]";
    }

    return @dir_parts;
}


1;
