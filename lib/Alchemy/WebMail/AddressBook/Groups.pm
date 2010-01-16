package Alchemy::WebMail::AddressBook::Groups;

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

	if (! is_text($in->{name})) {
		push(@err, 'Enter a name for this group.');
	}
	else {
		my $oname;

		if (is_integer($id)) {
			my $sth = db_query($$k{dbh}, 'get name',
								'SELECT name FROM wm_mlist WHERE id = ',
								sql_num($id), 'AND wm_user_id = ',
								sql_num($$k{user_id}));
	
			($oname) = db_next($sth);
	
			db_finish($sth);
		}

		# Make sure the name is unique to the user.
		my $ath = db_query($$k{dbh}, 'get name',
							'SELECT count(id) FROM wm_mlist WHERE ',
							'wm_user_id = ', sql_num($$k{user_id}),
							' AND name = ', sql_str($in->{name}));

		my ($count) = db_next($ath);

		db_finish($ath);

		if ($count) {
			if (defined $oname) {
				if ($oname ne $in->{name}) {
					push(@err, 'This group name is already in use.');
				}
			}
			else {
				push(@err, 'This group name is already in use.');
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
	my ($k, $in) = @_;

	return(ht_form_js($$k{uri}),
			ht_div({ class => 'box' }),
			ht_table(),

			ht_tr(undef,
				ht_td({ class => 'shd' }, 'Group Name'),
				ht_td(undef, ht_input('name', 'text', $in))),
			
			ht_tr(undef,
				ht_td({ 'colspan' => '2', 'class' => 'rshd'}, 
					ht_submit('submit', 'Next'),
					ht_submit('cancel', 'Cancel'))),

			ht_utable(),
			ht_udiv(),
			ht_uform());
} # END $k->_form

#-------------------------------------------------
# $k->do_add($r)
#-------------------------------------------------
sub do_add {
	my ($k, $r) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title}	.= 'Add Group';
	
	return($k->_relocate($r, $$k{rootp})) if ($in->{cancel});

	if (my @err = $k->_checkvals($in)) {
		return(($r->method eq 'POST' ? @err : ''), $k->_form($in));
	}

	db_run($$k{dbh}, 'Add a new role.', 
			sql_insert('wm_mlist', 
						'wm_user_id'	=> sql_num($$k{user_id}),
						'name'			=> sql_str($in->{name})));

	my $mlist = db_lastseq($$k{dbh}, 'wm_mlist_seq');

	db_commit($$k{dbh});
		
	return($k->_relocate($r, "$$k{rootp}/members/$mlist"));
} # END $k->do_add

#-------------------------------------------------
# $k->do_delete($r, $id, $yes)
#-------------------------------------------------
sub do_delete {
	my ($k, $r, $id, $yes) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title} .= 'Delete Group';

	return('Invalid id.') 					if (! is_integer($id));
	return($k->_relocate($r, $$k{rootp})) 	if (defined $in->{cancel});

	if ((defined $yes) && ($yes eq 'yes')) {

		db_run($$k{dbh}, 'remove the people',
				'DELETE FROM wm_mlist_members WHERE wm_mlist_id = ', 
				sql_num($id), 'AND wm_user_id = ', sql_num($$k{user_id}));

		db_run($$k{dbh}, 'remove the group',
				'DELETE FROM wm_mlist WHERE id = ', sql_num($id), 
				'AND wm_user_id = ', sql_num($$k{user_id}));

		db_commit($$k{dbh});

		return($k->_relocate($r, $$k{rootp}));
	}
	else {
		# Look up the entry information.
		my $sth = db_query($$k{dbh}, 'get role information',
							'SELECT name FROM wm_mlist WHERE id = ', 
							sql_num($id));

		my ($name) = db_next($sth);

		db_finish($sth);

		return(ht_form_js("$$k{uri}/yes"), 
				ht_div({ class => 'box' }),
				ht_table(),
				ht_tr(undef,
					ht_td(undef,
							qq!Delete the group "$name"? !,
							q!This will completely remove this group.!)),

				ht_tr(undef,
					ht_td({ 'class' => 'rshd' }, 
							ht_submit('submit', 'Continue with Delete'),
							ht_submit('cancel', 'Cancel'))),
				ht_utable(),
				ht_udiv(),
				ht_uform() );
	}
} # END $k->do_delete

#-------------------------------------------------
# $k->do_edit($r, $id )
#-------------------------------------------------
sub do_edit {
	my ($k, $r, $id) = @_;

	# Change the name.
	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title}	.= 'Rename Group';
	
	return($k->_relocate($r, $$k{rootp})) if ($in->{cancel});

	if (my @err = $k->_checkvals($in, $id)) {

		my $sth = db_query($$k{dbh}, 'get name',
							'SELECT name FROM wm_mlist WHERE id = ',
							sql_num($id), 'AND wm_user_id = ',
							sql_num($$k{user_id}));

		my ($name) = db_next($sth);

		$in->{name}	= $name if (! defined $in->{name});

		db_finish($sth);

		return(($r->method eq 'POST' ? @err : ''), $k->_form($in));
	}

	db_run($$k{dbh}, 'Add a new role.', 
			sql_update('wm_mlist', 
							'WHERE id = '. sql_num($id). 
							' AND wm_user_id = '. sql_num($$k{user_id}),
						'name' => sql_str($in->{name})));
	
	db_commit($$k{dbh});
	
	return($k->_relocate($r, "$$k{rootp}/members/$id"));
} # END $k->do_edit

#-------------------------------------------------
# $k->do_main($r)
#-------------------------------------------------
sub do_main {
	my ($k, $r) = @_;

	$$k{page_title} .= 'Group Book';

	my @lines = ( 	ht_div({ 'class' => 'box' }),
					ht_table(),

					ht_tr(undef,
						ht_td({ 'class' => 'hdr' }, 'Name'),
						ht_td({ 'class' => 'rhdr' }, '[',
							ht_a($$k{address_root}, 'Address Book'), '|',
							ht_a("$$k{rootp}/add", 'Add'), ']' )));

	my $sth = db_query($$k{dbh}, 'get list', 
						'SELECT id, name FROM wm_mlist WHERE wm_user_id = ', 
						sql_num($$k{user_id}), 'ORDER BY name');

	while (my ($id, $name) = db_next($sth)) {
		push(@lines, 	ht_tr(undef,
						ht_td(undef, ht_a("$$k{rootp}/members/$id", $name)),
						ht_td({ 'class' => 'rdta' },
							'[', ht_a("$$k{rootp}/edit/$id", 'Rename'), '|',
							ht_a("$$k{rootp}/delete/$id", 'Delete'), ']')) );
	}

	if (db_rowcount($sth) < 1) {
		push(@lines, 	ht_tr(undef,
							ht_td({ 'colspan' => 2, 'class' => 'cdta' }, 
									'No entries found.')));
	}

	db_finish($sth);

	return(@lines, ht_utable(), ht_udiv());
} # END $k->do_main

#-------------------------------------------------
# $k->do_members($r, $id, $add_remove, $aid)
#-------------------------------------------------
sub do_members {
	my ($k, $r, $id, $add_remove, $aid) = @_;

	$$k{page_title} .= 'Group Members';
	$add_remove = 'neither' if (! is_text($add_remove));

	return('Invalid id.') if (! is_integer($id));

	# Get the group name.
	my $sth = db_query($$k{dbh}, 'get group name', 
						'SELECT name FROM wm_mlist WHERE id = ', sql_num($id),
						'AND wm_user_id = ', sql_num($$k{user_id}));
	
	my ($name) = db_next($sth);

	db_finish($sth);

	return('Invalid group.') if (! is_text($name));

	my @lines;

	# Remove if remove
	if ($add_remove =~ /^add$/ && is_number($aid)) {
		db_run($$k{dbh}, 'add member', 
				sql_insert('wm_mlist_members', 
							'wm_user_id' 	=> sql_num($$k{user_id}),
							'wm_mlist_id' 	=> sql_num($id),
							'wm_abook_id' 	=> sql_num($aid)));

		db_commit($$k{dbh});

		push(@lines, 'User added to group.');
	}

	# Add if Add
	if ($add_remove =~ /^remove$/ && is_number($aid)) {
		db_run($$k{dbh}, 'remove member',
				'DELETE FROM wm_mlist_members WHERE wm_user_id = ',
				sql_num($$k{user_id}), 'AND wm_mlist_id = ',
				sql_num($id), 'AND wm_abook_id = ', sql_num($aid));
		
		db_commit($$k{dbh});

		push(@lines, 'User removed from group.');
	}

	my %userlist;
	my $i = 0;

	# Get all addresses
	my $ath = db_query($$k{dbh}, 'get all',
						'SELECT id, first_name, last_name, email ',
						'FROM wm_abook WHERE wm_user_id = ', 
						sql_num($$k{user_id}), 
						'ORDER BY last_name, first_name');
	
	while (my ($oid, $fname, $lname, $email) = db_next($ath)) {
		$userlist{$oid}{lname} = $lname;
		$userlist{$oid}{fname} = $fname;
		$userlist{$oid}{email} = $email;
		$userlist{$oid}{stat} = 0;
		$userlist{$oid}{order} = $i;
		$i++;
	}

	db_finish($ath);

	# Addresses in the list.
	my $bth = db_query($$k{dbh}, 'get in list',
						'SELECT wm_abook_id FROM wm_mlist_members ',
						'WHERE wm_user_id = ', sql_num($$k{user_id}),
						'AND wm_mlist_id = ', sql_num($id));

	while (my ($inid) = db_next($bth)) {
		$userlist{$inid}{stat} = 1;
	}

	db_finish($bth);

	my (@in, @out);
	# Display the current listings.

	for my $oid (sort { $userlist{$a}{order} <=> $userlist{$b}{order} } 
						(keys(%userlist))) {

		my $fname = $userlist{$oid}{fname};
		my $lname = $userlist{$oid}{lname};
		my $email = $userlist{$oid}{email};
	
		if ($userlist{$oid}{stat}) {
			push(@in, 	ht_li(undef,
							ht_a("$$k{rootp}/members/$id/remove/$oid", 
									"$fname $lname &lt;$email&gt;")));
		}
		else {
			push(@out, ht_li(undef,
							ht_a("$$k{rootp}/members/$id/add/$oid",
									"$fname $lname &lt;$email&gt;")));
		}
	}

	return(@lines,
			ht_div({ 'class' => 'box' }),
			ht_table(), 

			ht_tr(undef,
				ht_td({ 'class' => 'hdr' }, $name ),
				ht_td({ 'class' => 'rhdr' }, 
					'[', ht_a($$k{rootp}, 'Groups List'), '|',
					ht_a("$$k{rootp}/edit/$id", 'Rename'), '|',
					ht_a("$$k{rootp}/delete/$id", 'Delete'), ']')), 
			
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Members'),
				ht_td(undef,
					(@in) ?	( '<p>Click on the address to remove it from the list</p>',
							'<ul>', @in, '</ul>') : 
							'This group has no members' )),
					
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Non-members'),
				ht_td(undef,
					( @out) ? ( '<p>Click on the address to add it
										to the list</p>',
										'<ul>', @out, '</ul>') : 
										'Everyone is a member.')), 
			ht_utable(),
			ht_udiv());
} # END $k->do_members

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail::AddressBook::Groups - Address Book Groups

=head1 SYNOPSIS

  use Alchemy::WebMail::AddressBook::Groups;

=head1 DESCRIPTION

This module manages groups for a user. Groups are built from people that
are currently in their address book.

=head1 APACHE

This is a sample of the location required for this module to run.
Consult Alchemy::WebMail(3) to learn about the configuration options.

  <Location /mail/addressbook/groups >
    SetHandler  perl-script

    PerlHandler Alchemy::WebMail::AddressBook::Groups
  </Location>

=head1 DATABASE

This module manipulates the wm_mlist and wm_mlist_members tables. 

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
