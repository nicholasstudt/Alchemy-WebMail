package Alchemy::WebMail::Login;

use strict;

use KrKit::AppBase;
use KrKit::DB;
use KrKit::HTML qw(:all);
use KrKit::SQL;
use KrKit::Validate;

use Alchemy::WebMail;
use Alchemy::WebMail::IMAP;

our @ISA = ('Alchemy::WebMail');

############################################################
# Functions                                                #
############################################################

#-------------------------------------------------
# $k->_checkvals($in)
#-------------------------------------------------
sub _checkvals {
	my ($k, $in) = @_;

	my @errors;

	if (! is_text($in->{username})) {
		push(@errors, 'Please enter your user name.');
	}

	if (! is_text($in->{password})) {
		push(@errors, 'Please enter your password.');
	}

	if (! @errors) {
		# Check the username and password ? against server.
		my $imap = Alchemy::WebMail::IMAP->new( $$k{imap_host}, 
							$$k{imap_proto}, $$k{imap_inbox},
							lc($in->{username}), $in->{password},
							$$k{file_tmp});

		if (! $imap->alive()) {
			push(@errors, 'Invalid username or password.');
		}
		else {
			$imap->close();
		}
	}

	if (@errors) {
		return(ht_div({ 'class' => 'error' }, 
						ht_h(1, 'Errors:'), 
						ht_ul(undef, map {ht_li(undef, $_)} @errors)));
	}

	return();
} # END $k->_checkvals

#-------------------------------------------------
# $k->_form($in )
#-------------------------------------------------
sub _form {
	my ($k, $in) = @_;

	return( ht_form_js( $$k{uri} ),	
			ht_div( { 'class' => 'box' } ),

			ht_table( {} ),
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Username'),
				ht_td(undef, ht_input('username', 'text', $in))),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Password'),
				ht_td(undef, ht_input('password', 'password', $in))),

			ht_tr(undef,
				ht_td({ 'colspan' => '2', 'class' => 'rshd' }, 
					ht_submit('submit', 'Log in'))),

			ht_utable(),
			ht_udiv(),
			ht_uform());
} # END $k->_form

#-------------------------------------------------
# $k->do_logout($r)
#-------------------------------------------------
sub do_logout {
	my ($k, $r) = @_;

	$$k{page_title} .= 'Log out';

	# This is not really usefull...
	my $expire 	= ($$k{p_sess_s} > 0) ? $$k{p_sess_s} : undef;

	# Set a bum cookie and tell the user they have been logged out.
	appbase_cookie_set($r, $$k{cookie_name}, 'loggedout', $expire,
						$$k{cookie_path});

	return('You have been logged out.', ht_br(), 
			ht_a($$k{login_root}, 'Log in'));

} # END $k->do_logout

#-------------------------------------------------
# $k->do_main($r, $location)
#-------------------------------------------------
sub do_main {
	my ($k, $r, $location) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title}	.= 'Log in';

	# Show the form or errors as needed.
	if (my @errors = $k->_checkvals($in)) {
		return(($r->method eq 'POST' ? @errors : ''), $k->_form($in));
	}

	# Make it happy for any case.
	$in->{username} = lc($in->{username}); 
	
	# look up user in the database.
	my $sth = db_query($$k{dbh}, 'get user id',
						'SELECT id FROM wm_users WHERE username = ',
							sql_str($in->{username}));

	my ($id) = db_next($sth);

	db_finish($sth);

	if ( ! is_number( $id ) ) {
		# if they don't exist.
		my $imap = Alchemy::WebMail::IMAP->new($$k{imap_host}, 
								$$k{imap_proto}, $$k{imap_inbox},
								$in->{username}, $in->{password}, 
								$$k{file_tmp});

		my %existing = $imap->folder_list();

		# Create and Subscribe to the default folders.
		for my $folder ($$k{imap_drafts}, $$k{imap_sent}, $$k{imap_trash}) {
			next if (defined $existing{$folder});

			if (! $imap->folder_create($folder, 1)) {
				return('Error: ', $imap->error());
			}
		}
	
		# This needs to fail cleanly.
		if (! defined $existing{$$k{imap_inbox}}) { 
			$imap->folder_subscribe( $$k{imap_inbox} );
		}

		$imap->close();

		# Insert defaults into wm_users
		db_run($$k{dbh}, 'insert user', 
				sql_insert('wm_users', 
							'reply_include' => sql_bool($$k{p_reply}),
							'true_delete' 	=> sql_bool($$k{p_delete}),
							'session_length'=> sql_num($$k{p_sess_s}),
							'fldr_showcount'=> sql_num($$k{p_fcount}),
							'fldr_sortorder'=> sql_num($$k{p_fsordr}),
							'fldr_sortfield'=> sql_str($$k{p_sfield}),
							'username'		=> sql_str($in->{username})));
	
		# insert default role into wm_roles
		my $wm_user_id 	= db_lastseq($$k{dbh}, 'wm_users_seq');
		my $email 		= "$in->{username}\@$$k{imap_domain}";

		db_run($$k{dbh}, 'insert default role',
				sql_insert('wm_roles',	
							'wm_user_id'=> sql_num($wm_user_id),
							'main_role'	=> sql_bool('t'),
							'role_name'	=> sql_str('Default'),
							'name'		=> sql_str(''),
							'reply_to'	=> sql_str($email),
							'savesent'	=> sql_str($$k{p_ssent})));
						
		db_commit($$k{dbh});
	} 
	
	# Send the login cookie.
	my $crypt = $k->cookie_encrypt($in->{username}, $in->{password}); 
	my $expire 	= ($$k{p_sess_s} > 0) ? $$k{p_sess_s} : undef ; 
	
	appbase_cookie_set($r, $$k{cookie_name}, $crypt, $expire, $$k{cookie_path});

	# redirect to the main page of the application. ( WM_MailFP )
	if (is_text($location)) {
		$location =~ s/:/\//g;
		return($k->_relocate($r, $location));
	}

	return($k->_relocate($r, $$k{mail_fp}));
} # END $k->do_main

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

Nicholas Studt <nicholas@nicholasstudt.com>

=head1 COPYRIGHT

Copyright (c) 2003-2010 Nicholas Studt. All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=cut
