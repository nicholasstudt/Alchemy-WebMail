package Alchemy::WebMail::AddressBook;

use strict;

use KrKit::DB;
use KrKit::HTML qw(:all);
use KrKit::SQL;
use KrKit::Validate;

use Alchemy::WebMail;

our @ISA = ('Alchemy::WebMail');

############################################################
# Functions                                                #
############################################################

#-------------------------------------------------
# $k->_checkvals($in, $id)
#-------------------------------------------------
sub _checkvals {
	my ($k, $in, $id) = @_;

	my @err;

	if (is_text($in->{balk})) {
		push(@err, 'Please confirm address information.');
	}

	if (! is_text($in->{first})) {
		push(@err, 'Enter a first name for this entry.');
	}

	if (! is_email($in->{email})) {
		push(@err, 'Enter a valid email address.');
	}
	else {
		my $oemail;

		if (is_integer($id)) {
			my $sth = db_query($$k{dbh}, 'get name',
								'SELECT email FROM wm_abook WHERE id = ',
								sql_num($id), 'AND wm_user_id = ',
								sql_num($$k{user_id}));
	
			($oemail) = db_next($sth);
	
			db_finish( $sth );
		}

		# Make sure the name is unique to the user.
		my $ath = db_query($$k{dbh}, 'get name',
							'SELECT count(id) FROM wm_abook WHERE ',
							'wm_user_id = ', sql_num($$k{user_id}),
							' AND email = ', sql_str($in->{email}));

		my ( $count ) = db_next( $ath );

		db_finish( $ath );

		if ($count) {
			if (defined $oemail) {
				if ($oemail ne $in->{email}) {
					push(@err, 'This address is already in your address book.');
				}
			}
			else {
				push(@err, 'This address is already in your address book.');
			}
		}
	}

	if (@err) {
		return(ht_div({ 'class' => 'error' }, 
						ht_h(1, 'Errors:'),
						ht_ul(undef, map {ht_li(undef, $_)} @err)));
	} 

	return();
} # END $k->_checkvals

#-------------------------------------------------
# $k->_form($in)
#-------------------------------------------------
sub _form {
	my ( $k, $in ) = @_;

	return(ht_form_js($$k{uri}),
			ht_div({ 'class' => 'box' }),
			ht_table(),

			# First name
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'First Name'),
				ht_td(undef, ht_input('first', 'text', $in))),

			# last name
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Last Name'),
				ht_td(undef, ht_input('last', 'text', $in))),

			# email
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Email'),
				ht_td(undef, ht_input( 'email', 'text', $in))),

			ht_tr(undef,
				ht_td({ 'colspan' => '2', 'class' => 'rshd' }, 
					ht_submit('submit', 'Save'),
					ht_submit('cancel', 'Cancel'))),

			ht_utable(),
			ht_udiv(),
			ht_uform());
} # END $k->_form

#-------------------------------------------------
# $k->do_add($r, $field, $sort)
#-------------------------------------------------
sub do_add {
	my ($k, $r, $field, $sort) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title}	.= 'Add Entry';

	my $relocate = $$k{rootp};

	if ( defined $field && defined $sort ) {
		$relocate = "$$k{rootp}/list/$field/$sort";
	}
 
	return($k->_relocate($r, $relocate)) if ($in->{cancel});

	if (my @err = $k->_checkvals($in)) {
		return(($r->method eq 'POST' ? @err : ''), $k->_form($in));
	}

	db_run($$k{dbh}, 'Add a new role.', 
			sql_insert('wm_abook', 
						'wm_user_id'	=> sql_num($$k{user_id}),
						'first_name'	=> sql_str($in->{first}),
						'last_name'		=> sql_str($in->{last}),
						'email'			=> sql_str($in->{email})));

	db_commit($$k{dbh});
	
	return($k->_relocate($r, $relocate));
} # END $k->do_add

#-------------------------------------------------
# $k->do_delete($r, $id, $yes)
#-------------------------------------------------
sub do_delete {
	my ($k, $r, $id, $yes) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title} .= 'Delete Entry';

	return('Invalid id.')					if (! is_integer($id));
	return($k->_relocate($r, $$k{rootp}))	if (defined $in->{cancel});

	if ((defined $yes) && ($yes eq 'yes')) {

		db_run($$k{dbh}, 'remove the entry',
				'DELETE FROM wm_abook WHERE id = ', sql_num($id), 
				'AND wm_user_id = ', sql_num($$k{user_id}));

		db_commit($$k{dbh});

		return($k->_relocate($r, $$k{rootp}));
	}
	else {
		# Look up the entry information.
		my $sth = db_query($$k{dbh}, 'get role information',
							'SELECT first_name, last_name FROM wm_abook ',
							'WHERE id = ', sql_num($id));

		my ($fname, $lname) = db_next($sth);

		db_finish($sth);

		return( ht_form_js("$$k{uri}/yes"), 
				ht_div({ class => 'box' }),
				ht_table(),
				ht_tr(undef,
					ht_td(undef, qq!Delete the entry for "$fname $lname" ? !,
								 q!This will completely remove this entry.!)),
				ht_tr(undef,
					ht_td({ 'class' => 'rshd' }, 
						ht_submit('submit', 'Continue with Delete'),
						ht_submit('cancel', 'Cancel'))),
				ht_utable(),
				ht_udiv(),
				ht_uform());
	}
} # END $k->do_delete

#-------------------------------------------------
# $k->do_edit($r, $id)
#-------------------------------------------------
sub do_edit {
	my ($k, $r, $id) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title}	.= 'Edit Entry';
	
	return($k->_relocate($r, $$k{rootp})) if ($in->{cancel});

	if (! (my @errors = $k->_checkvals($in, $id))) {

		db_run($$k{dbh}, 'Update a role.', 
				sql_update('wm_abook', 'WHERE id = '. sql_num($id). 
								'AND wm_user_id = '. sql_num($$k{user_id}),

							'first_name'	=> sql_str($in->{first}),
							'last_name'		=> sql_str($in->{last}),
							'email'			=> sql_str($in->{email})));

		db_commit($$k{dbh});
		
		return($k->_relocate($r, $$k{rootp}));
	}
	else {
		my $sth = db_query($$k{dbh}, 'get old values',
							'SELECT first_name, last_name, email ',
							'FROM wm_abook WHERE id = ', sql_num($id), 
							'AND wm_user_id = ', sql_num($$k{user_id}));

		while (my ($first, $last, $email) = db_next($sth)) {
			$in->{first} 	= $first 	if (! defined $in->{first});
			$in->{last} 	= $last 	if (! defined $in->{last});
			$in->{email} 	= $email 	if (! defined $in->{email});
		}

		db_finish($sth);
		
		return(($r->method eq 'POST' ? @errors : ''), $k->_form($in));
	}
} # END $k->do_edit

#-------------------------------------------------
# $k->do_main($r, $sort)
#-------------------------------------------------
sub do_main {
	my ( $k, $r, $sort ) = @_;

	$$k{page_title} .= 'Address Book';

	$sort = 'last' if (! is_text($sort));

	if ($sort =~ /first/i) {
		$sort = 'first_name';
	}
	else {
		$sort = ($sort =~ /last/i) ? 'last_name' : 'email';
	}

	my @lines = ( 	ht_div({ 'class' => 'box' }),
					ht_table(),

					ht_tr(undef,
						ht_td({ 'class' => 'hdr' }, 
							ht_a("$$k{rootp}/main/first", 'First Name')),
						ht_td({ 'class' => 'hdr' }, 
							ht_a( "$$k{rootp}/main/last", 'Last Name')),
						ht_td({ 'class' => 'hdr' }, 
							ht_a( "$$k{rootp}/main/mail", 'Email')),
						ht_td({ 'class' => 'rhdr' },
							'[',
							ht_a($$k{group_root}, 'Groups'), '|',
							ht_a("$$k{rootp}/add", 'Add'), ']' )) );

	my $sth = db_query($$k{dbh}, 'list address book entries',
						'SELECT id, first_name, last_name, email',
						'FROM wm_abook WHERE wm_user_id = ',
						sql_num($$k{user_id}), 'ORDER BY ', $sort);

	while (my ($id, $first, $last, $email) = db_next($sth)) {

		my $compose = "$$k{mail_root}/compose/$$k{imap_inbox}?to=$email";

		push(@lines, ht_tr(undef,
						ht_td(undef, $first),
						ht_td(undef, $last),
						ht_td(undef, ht_a($compose, $email)),
						ht_td({ 'class' => 'rdta' },
								'[', ht_a("$$k{rootp}/edit/$id", 'Edit'), '|',
								ht_a("$$k{rootp}/delete/$id", 'Delete'), ']',
							)));
	}

	if (db_rowcount($sth) < 1) {
		push(@lines, ht_tr(undef,
						ht_td({ 'colspan' => 4, 'class' => 'cdta' }, 
								'No entries found.')));
	}

	db_finish($sth);

	return(@lines, ht_utable(), ht_udiv());
} # END $k->do_main

#-------------------------------------------------
# $k->do_list($r, $field, $sort)
#-------------------------------------------------
sub do_list {
	my ($k, $r, $field, $sort) = @_;
	
	$$k{page_title} .= 'Address Book';

	return('Invalid field') if (! is_text($field));

	$sort = 'last' if (! is_text($sort));

	if ($sort =~ /first/i) {
		$sort = 'first_name';
	}
	else {
		$sort = ($sort =~ /last/i) ? 'last_name' : 'email';
	}

	my @lines = ( 	ht_div({ 'class' => 'box' }),

					'<script type="text/javascript">',
					'<!--',
					'	function SendAddr(d) { ',
    				qq!	window.opener.SetAddr("$field",d); !,
					'	} ',
					'//--> ',
					'</script>',

					ht_table(),
					ht_tr(undef,
						ht_td({ 'class' => 'hdr' }, 'Address Book'),
						ht_td({ 'class' => 'rhdr' },
							'[', ht_a("$$k{rootp}/add/$field/$sort", 'Add'),
							']')),
					ht_tr(undef,
						ht_td({ 'class' => 'rshd', 'colspan' => '2' },
							'[',
							ht_a("$$k{rootp}/list/$field/first", 'First Name'),
							'|',
							ht_a("$$k{rootp}/list/$field/last", 'Last Name'),
							'|',
							ht_a("$$k{rootp}/list/$field/mail", 'Email'), ']',
						)));

	my %addys;
	my $sth = db_query($$k{dbh}, 'list address book entries',
						'SELECT id, first_name, last_name, email',
						'FROM wm_abook WHERE wm_user_id = ',
						sql_num($$k{user_id}), 'ORDER BY ', $sort);

	while (my ($id, $first, $last, $email) = db_next($sth)) {

		$addys{$id} = $email;

		push(@lines,	ht_tr(undef,
							ht_td({'colspan' => '2' }, 
								ht_a("javascript:SendAddr('$email')", 
										"$first $last &lt;$email&gt;"))) );
	}

	if (db_rowcount($sth) < 1) {
		push(@lines, 	ht_tr(undef,
						ht_td({ 'class' => 'cdta', 'colspan' => '2' }, 
								'No addresses found.')));
	}

	db_finish($sth);

	push(@lines,	ht_utable(), ht_udiv(),
	
					ht_div({ 'class' => 'box' }),

					'<script type="text/javascript">',
					'<!--',
					'	function SendAddr(d) { ',
    				qq!	window.opener.SetAddr("$field",d); !,
					'	} ',
					'//--> ',
					'</script>',

					ht_table(),
					ht_tr(undef, ht_td({ 'class' => 'hdr' }, 'Groups')) );
	
	my $bth = db_query($$k{dbh}, 'get groups', 
						'SELECT id, name FROM wm_mlist WHERE wm_user_id = ',
						sql_num($$k{user_id}), 'ORDER BY name');
	
	while (my ($mid, $name) = db_next($bth)) {

		my @mails;
		# Get the users.
		my $cth = db_query($$k{dbh}, 'get users',
							'SELECT wm_abook_id FROM wm_mlist_members ',
							'WHERE wm_user_id = ', sql_num($$k{user_id}),
							'AND wm_mlist_id = ', sql_num($mid) );

		while (my ($eid) = db_next($cth)) {
			push(@mails, $addys{$eid});
		}
		
		db_finish($cth);

		my $email = join(', ', @mails);

		push(@lines,	ht_tr(undef,
							ht_td(undef,
								ht_a("javascript:SendAddr('$email')", $name))));
	}

	if (db_rowcount($bth) < 1) {
		push(@lines, 	ht_tr(undef,
							ht_td({ 'class' => 'cdta' }, 'No groups found.')));
	}

	return(@lines, ht_utable(), ht_udiv());
} # END $k->do_list

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail::AddressBook - Address Book.

=head1 SYNOPSIS

  use Alchemy::WebMail::AddressBook;

=head1 DESCRIPTION

This module provides the management for the users address book, it
allows users to manage these entries. 

=head1 APACHE

This is a sample of the location required for this module to run.
Consult Alchemy::WebMail(3) to learn about the configuration options.

  <Location /webmail/mail/addressbook >
    SetHandler  perl-script

    PerlHandler Alchemy::WebMail::AddressBook
  </Location>

=head1 DATABASE

This is the core table that this module manipulates.

  create table "wm_abook" (
    id          int4 PRIMARY KEY DEFAULT NEXTVAL( 'wm_abook_seq' ),
    wm_user_id  int4,       /* user entry id ( wm_users.id ) */
    first_name  varchar,    /* first name */
    last_name   varchar,    /* last name */
    email       varchar	    /* email address */
  );

=head1 SEE ALSO

Alchemy::Webmail(3), Alchemy(3), KrKit(3)

=head1 LIMITATIONS

=head1 AUTHOR

Nicholas Studt <nicholas@photodwarf.org>

=head1 COPYRIGHT

Copyright (c) 2003-2010 Nicholas Studt. All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.


=cut
