#!/usr/bin/perl -w

use strict;

use Getopt::Long; 

use KrKit::DB;
use KrKit::SQL;
use KrKit::Validate;

############################################################
# Functions                                                #
############################################################

#------------------------------------------------
# help()
#------------------------------------------------
sub help () {
	
	print 	"USAGE: webmail_purgeuser.pl [options] <username to purge>\n\n",
			"    --help                Display this usage\n", 
			"    --dbtype <type>       Database type\n",
			"    --dbsrv <server>      Database server\n",
			"    --dbname <name>       Database name\n", 
			"    --dbuser <user>       Database username\n", 
			"    --dbpass <password>   Database password\n",
			"    --verbose             Be verbose\n";
	
	exit;
} # END help

#------------------------------------------------
# purge_user($opt, $username)
#------------------------------------------------
sub purge_user {
	my ($opt, $username) = @_;

	# Look up the username and get the id.
	my $sth = db_query($$opt{dbh}, 'Get the users id',
						'SELECT id FROM wm_users WHERE username = ', 
						sql_str($username));

	my ($uid) = db_next($sth);

	db_finish($sth);

	if (! is_integer($uid)) {
		print "User '$username' not found, not removed.\n";
		return();
	}
	
	print "Remove user '$username' $uid.\n" if ($$opt{verbose});

	# Remove from wm_roles
	db_run($$opt{dbh}, 'Remove from wm_roles',
			'DELETE FROM wm_roles WHERE wm_user_id = ', sql_num($uid));
	
	print "Removed user's roles.\n" if ($$opt{verbose});

	# Remove from wm_mlist_members
	db_run($$opt{dbh}, 'Remove from wm_mlist_members',
			'DELETE FROM wm_mlist_members WHERE wm_user_id = ', sql_num($uid));
	
	print "Removed user's list members.\n" if ($$opt{verbose});

	# Remove from wm_mlist
	db_run($$opt{dbh}, 'Remove from wm_mlist',
			'DELETE FROM wm_mlist WHERE wm_user_id = ', sql_num($uid));
	
	print "Removed user's list.\n" if ($$opt{verbose});

	# Remove from wm_abook
	db_run($$opt{dbh}, 'Remove from wm_abook',
			'DELETE FROM wm_abook WHERE wm_user_id = ', sql_num($uid));
	
	print "Removed user's address book.\n" if ($$opt{verbose});

	# Remove from wm_users
	db_run($$opt{dbh}, 'Remove from wm_users',
			'DELETE FROM wm_users WHERE id = ', sql_num($uid));
	
	db_commit( $$opt{dbh} );

	print "User '$username' removed.\n" if ($$opt{verbose});

	return();
} # END purge_user

######################################################################
# Main Execution Begins Here                                         #
######################################################################
eval {
	my %opt = ( 'dbtype'	=> 'Pg',
				'dbsrv'		=> '',
				'dbname'	=> 'webmail',
				'dbuser'	=> 'apache',
				'dbpass'	=> '',
				'verbose'	=> 0, ); 
	
	GetOptions('help'			=> sub { help() },
				'dbtype=s'		=> \$opt{dbtype},
				'dbsrv=s'		=> \$opt{dbsrv},
				'dbname=s'		=> \$opt{dbname},
				'dbuser=s'		=> \$opt{dbuser},
				'dbpass=s'		=> \$opt{dbpass}, 
				'verbose+'		=> \$opt{verbose});

	# Catch the no user time.
	help() if (! @ARGV);

	# Connect to the db.
	$opt{dbh} = db_connect($opt{dbtype}, $opt{dbuser}, $opt{dbpass}, 
						 	$opt{dbsrv}, $opt{dbname}, 'off');

	for my $user (@ARGV) {
		purge_user(\%opt, lc($user));
	}

	db_disconnect($opt{dbh});
};

print "Error: $@\n\n" if ($@);

# EOF 
1;

__END__

=head1 NAME 

webmail_purgeuser.pl - Remove a WebMail user.

=head1 SYNOPSIS

  USAGE: webmail_purgeuser.pl [options] <username to purge>

      --help                Display this usage
      --dbtype <type>       Database type
      --dbsrv <server>      Database server
      --dbname <name>       Database name
      --dbuser <user>       Database username
      --dbpass <password>   Database password
      --verbose             Be verbose

=head1 DESCRIPTION

This script will remove all entries for a particular user from the
database, this is a non-reversable proceedure. Multiple users may be
removed at one time.

=head1 DATABASE

This script will remove a user's data from wm_users, wm_roles, wm_abook,
wm_list, and wm_mlist_members. Once removed this data is not
retrievable, use with care.

=head1 SEE ALSO

Alchemy::WebMail(3)

=head1 LIMITATIONS 

The removal of a user is no-reversable, unless you happen to have made a
backup of the database. 

=head1 AUTHOR

Nicholas Studt <nicholas@photodwarf.org>

=head1 COPYRIGHT

Copyright (c) 2003-2010 Nicholas Studt. All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=cut
