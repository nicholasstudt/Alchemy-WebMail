package Alchemy::WebMail::Login;

use strict;

use KrKit::AppBase;
use KrKit::DB;
use KrKit::HTML qw( :all );
use KrKit::SQL;
use KrKit::Validate;

use Alchemy::WebMail;
use Alchemy::WebMail::IMAP;

our @ISA = ( 'Alchemy::WebMail' );

############################################################
# Functions                                                #
############################################################

#-------------------------------------------------
# $site->do_logout( $r )
#-------------------------------------------------
sub do_logout {
	my ( $site, $r ) = @_;

	$$site{page_title} .= 'Log out';

	# This is not really usefull...
	my $expire 	= ( $$site{p_sess_s} > 0 ) ? $$site{p_sess_s} : undef ;

	# Set a bum cookie and tell the user they have been logged out.
	appbase_cookie_set( $r, $$site{cookie_name}, 'loggedout', $expire,
						$$site{cookie_path} );

	return( 'You have been logged out.', 
			ht_br(),
			ht_a( $$site{login_root}, 'Log in' ) );

} # END $site->do_logout

#-------------------------------------------------
# $site->do_main( $r, $location )
#-------------------------------------------------
sub do_main {
	my ( $site, $r, $location ) = @_;

	my $in 				= $site->param( Apache2::Request->new( $r ) );
	$$site{page_title}	.= 'Log in';

	if ( ! ( my @errors = login_checkvals( $site, $in ) ) ) {

		# Make it happy for any case.
		$in->{username} = lc( $in->{username} );
	
		# look up user in the database.
		my $sth = db_query( $$site{dbh}, 'get user id',
							'SELECT id FROM wm_users WHERE username = ',
							sql_str( $in->{username} ) );

		my ( $id ) = db_next( $sth );

		db_finish( $sth );

		if ( ! is_number( $id ) ) {
			# if they don't exist.
			my $imap = Alchemy::WebMail::IMAP->new( $$site{imap_host}, 
									$$site{imap_proto}, $$site{imap_inbox},
									$in->{username}, $in->{password}, 
									$$site{file_tmp} );

			my %existing = $imap->folder_list();

			# Create and Subscribe to the default folders.
			for my $folder ( 	$$site{imap_drafts}, $$site{imap_sent},
								$$site{imap_trash} )
			{
				next if ( defined $existing{$folder} );

				if ( ! $imap->folder_create( $folder, 1 ) ) {
					return( 'Error: ', $imap->error() );
				}
			}
		
			if ( ! defined $existing{$$site{imap_inbox}} ) {
				# This needs to fail cleanly.
				$imap->folder_subscribe( $$site{imap_inbox} );
			}

			$imap->close();

			# Insert defaults into wm_users
			db_run( $$site{dbh}, 'insert user', 
					sql_insert( 'wm_users', 
								'reply_include' => sql_bool( $$site{p_reply} ),
								'true_delete' 	=> sql_bool( $$site{p_delete} ),
								'session_length'=> sql_num( $$site{p_sess_s} ),
								'fldr_showcount'=> sql_num( $$site{p_fcount} ),
								'fldr_sortorder'=> sql_num( $$site{p_fsordr} ),
								'fldr_sortfield'=> sql_str( $$site{p_sfield} ),
								'username'		=> sql_str( $in->{username} ) ) );
		
			# insert default role into wm_roles
			my $wm_user_id 	= db_lastseq( $$site{dbh}, 'wm_users_seq' );
			my $email 		= "$in->{username}\@$$site{imap_domain}";

			db_run( $$site{dbh}, 'insert default role',
					sql_insert( 'wm_roles',	
								'wm_user_id'=> sql_num( $wm_user_id ),
								'main_role'	=> sql_bool( 't' ),
								'role_name'	=> sql_str( 'Default' ),
								'name'		=> sql_str( '' ),
								'reply_to'	=> sql_str( $email ),
								'savesent'	=> sql_str( $$site{p_ssent} ) ) );
							
			db_commit( $$site{dbh} );
		}
		
		# Send the login cookie.
		my $crypt = $site->cookie_encrypt( $in->{username}, $in->{password} ); 
		my $expire 	= ( $$site{p_sess_s} > 0 ) ? $$site{p_sess_s} : undef ;

		appbase_cookie_set( $r, $$site{cookie_name}, $crypt, $expire,
							$$site{cookie_path} );


		# redirect to the main page of the application. ( WM_MailFP )
		if ( is_text( $location ) ) {
			$location =~ s/:/\//g;
			return( $site->_relocate( $r, $location ) );
		}
		else {
			return( $site->_relocate( $r, $$site{mail_fp} ) );
		}
	}
	else {
		if ( $r->method eq 'POST' ) {
			return( @errors, login_form( $site, $in ) );
		}
		else {
			return( login_form( $site, $in ) );
		}
	}
} # END $site->do_main

#-------------------------------------------------
# login_checkvals( $site, $in )
#-------------------------------------------------
sub login_checkvals {
	my ( $site, $in ) = @_;

	my @errors;

	if ( ! is_text( $in->{username} ) ) {
		push( @errors, 'Please enter your user name.'. ht_br() );
	}

	if ( ! is_text( $in->{password} ) ) {
		push( @errors, 'Please enter your password.'. ht_br() );
	}

	if ( ! @errors ) {
		# Check the username and password ? against server.
		my $imap = Alchemy::WebMail::IMAP->new( $$site{imap_host}, 
							$$site{imap_proto}, $$site{imap_inbox},
							lc( $in->{username} ), $in->{password},
							$$site{file_tmp} );

		if ( ! $imap->alive() ) {
			push( @errors, 'Invalid username or password.'. ht_br() );
		}
		else {
			$imap->close();
		}
	}

	return( @errors );
} # END login_checkvals

#-------------------------------------------------
# login_form( $site, $in )
#-------------------------------------------------
sub login_form {
	my ( $site, $in ) = @_;

	return( ht_form_js( $$site{uri} ),	
			ht_div( { 'class' => 'box' } ),

			ht_table( {} ),
			ht_tr(),
			ht_td( 	{ 'class' => 'shd' }, 'Username', ),
			ht_td( 	{ 'class' => 'dta' },
					ht_input( 'username', 'text', $in ) ),
			ht_utr(),

			ht_tr(),
			ht_td( 	{ 'class' => 'shd' }, 'Password' ),
			ht_td( 	{ 'class' => 'dta' }, 
					ht_input( 'password', 'password', $in ) ),
			ht_utr(),

			ht_tr(),
			ht_td( 	{ 'colspan' => '2', 'class' => 'rshd' }, 
					ht_submit( 'submit', 'Log in'  ) ),
			ht_utr(),

			ht_utable(),

			ht_udiv(),
			ht_uform() );
} # END login_form

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail::Login - Login and Logout handler.

=head1 SYNOPSIS

  use Alchemy::WebMail::Login;

=head1 DESCRIPTION

This module generates the log in and log out pages. The first cookie is
set and if it is a first time user their default preferences are set up. 

=head1 APACHE

This is a sample of the location required for this module to run.
Consult Alchemy::Webmail(3) to learn about the configuration options.

  <Location /webmail/login >
    SetHandler  perl-script

    PerlHandler Alchemy::WebMail::Login
  </Location>

=head1 DATABASE

This module adds to the wm_users and wm_roles tables. It does not access
any of the other tables.

=head1 SEE ALSO

Alchemy::Webmail(3), Alchemy(3), KrKit(3)

=head1 LIMITATIONS

=head1 AUTHOR

Nicholas Studt <nicholas@photodwarf.org>

=head1 COPYRIGHT

Copyright (c) 2003-2008 Nicholas Studt. All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=cut
