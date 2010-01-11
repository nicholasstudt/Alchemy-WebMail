package Alchemy::WebMail::Preferences::Roles;

use strict;

use KrKit::DB;
use KrKit::HTML qw( :all );
use KrKit::SQL;
use KrKit::Validate;

use Alchemy::WebMail;

our @ISA = ( 'Alchemy::WebMail' );

############################################################
# Functions                                                #
############################################################

#-------------------------------------------------
# $k->_checkvals( $in )
#-------------------------------------------------
sub _checkvals {
	my ( $k, $in ) = @_;
 
	my @errors;

	if (! is_number($in->{main_role})) {
		push(@errors, 'Select if this should be the default role.');
	}

	if (! is_text($in->{role_name})) {
		push(@errors, 'Enter a name for this role.');
	}

	if (! is_email($in->{reply_to})) {
		push(@errors, 'A role must have a reply to address.');
	}

	if (@errors) {
		return(ht_div({ 'class' => 'error' }, 
						ht_h(1, 'Errors:'),
						ht_ul(undef, map {ht_li(undef, $_)} @errors)));
	}

	return();
} # END $k->_checkvals

#-------------------------------------------------
# $k->_form($in)
#-------------------------------------------------
sub _form {
	my ($k, $in) = @_;

	my @folders = ('', 'Do Not Save');
	my %fldrs 	= $$k{imap}->folder_list();

	for my $f (sort {($a eq $$k{imap_inbox}) ? -1 : $a cmp $b} keys(%fldrs)) {
		push(@folders, $f, $k->inbox_mask($f));
	}

	return(ht_form_js( $$k{uri} ),	
			ht_div({ 'class' => 'box' }),
			ht_table(),

			# main role
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Default Role'),
				ht_td({ 'class' => 'dta' },
					ht_select('main_role', 1, $in, '', '', 
								'0', 'No', '1', 'Yes'))),

			# role name
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Role Name'),
				ht_td({ 'class' => 'dta' }, 
					ht_input('role_name', 'text', $in))),

			# name
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Name'),
				ht_td({ 'class' => 'dta' }, ht_input('name', 'text', $in))),

			# reply to 
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Reply To'),
				ht_td({ 'class' => 'dta' }, ht_input('reply_to', 'text', $in))),

			# save sent 
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Save Sentmail'),
				ht_td({ 'class' => 'dta' }, 
					ht_select('savesent', 1, $in, '', '', @folders))),

			# signature
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Signature'),
				ht_td({ 'class' => 'dta' }, 
					ht_input('signature', 'textarea', $in,
								'cols="50" rows="4"'))),

			ht_tr(undef,
				ht_td({ 'colspan' => '2', 'class' => 'rshd' }, 
					ht_submit('submit', 'Save'),
					ht_submit('cancel', 'Cancel'))),

			ht_utable(),

			ht_udiv(),
			ht_uform());
} # END $k->_form

#-------------------------------------------------
# $self->do_add($r)
#-------------------------------------------------
sub do_add {
	my ($k, $r) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title}	.= 'Add Role';
	
	return($k->_relocate($r, $$k{rootp})) if ($in->{cancel});
	
	if (my @err = $k->_checkvals($in)) {
		return(( $r->method eq 'POST' ? @err : ''), $k->_form($in));
	}

	# Clean up the signature.
	$in->{signature} = '' if (! defined $in->{signature});
	$in->{signature} =~ s/\r\n/\n/g;
	$in->{signature} =~ s/\r/\n/g;
  	$in->{signature} = ht_qt($in->{signature});

   	# IF main_role is true, update everyone else to false.
   	if ($in->{main_role}) {
		db_run($$k{dbh}, 'update other default',
				sql_update('wm_roles', 
							'WHERE wm_user_id ='. sql_num($$k{user_id}),
							'main_role'	=> sql_bool('f')));
   	}

	db_run($$k{dbh}, 'Add a new role.', 
			sql_insert('wm_roles', 
						'wm_user_id'	=> sql_num($$k{user_id}),
						'main_role'		=> sql_bool($in->{main_role}),
						'role_name'		=> sql_str($in->{role_name}),
						'name'			=> sql_str($in->{name}),
						'reply_to'		=> sql_str($in->{reply_to}),
						'savesent'		=> sql_str($in->{savesent}),
						'signature'		=> sql_str($in->{signature})));

	db_commit($$k{dbh});
	
	return($k->_relocate($r, $$k{rootp}));
} # END $self->do_add

#-------------------------------------------------
# $self->do_delete($r, $id, $yes)
#-------------------------------------------------
sub do_delete {
	my ($k, $r, $id, $yes) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title} .= 'Delete Role';

	return('Invalid id.') if (! is_integer($id));
	return($k->_relocate($r, $$k{rootp})) if (defined $in->{cancel});

	if ((defined $yes) && ($yes eq 'yes')) {

		db_run($$k{dbh}, 'remove the role',
				'DELETE FROM wm_roles WHERE id = ', sql_num($id), 
				'AND wm_user_id = ', sql_num($$k{user_id}));

		db_commit($$k{dbh});

		return($k->_relocate($r, $$k{rootp}));
	}
	else {
		# Look up the role information.
		my $sth = db_query($$k{dbh}, 'get role information',
							'SELECT main_role, role_name FROM wm_roles ',
							'WHERE id = ', sql_num($id));

		my ($main, $name) = db_next($sth);

		db_finish($sth);

		if ($main) {
			return(ht_div({ 'class' => 'box' },
							'Unable to remove the default role.',
							ht_a($$k{rootp}, 'Back')));
		}

		return(ht_form_js("$$k{uri}/yes"), 
				ht_div({ 'class' => 'box' },
					ht_table(),
					ht_tr(undef,
						ht_td({ 'class' => 'dta' }, 
								qq!Delete the role "$name" ? This will !,
								q!completely remove this role.! )),
					ht_tr(undef,
						ht_td({ 'class' => 'rshd' }, 
							ht_submit('submit', 'Continue with Delete'),
							ht_submit('cancel', 'Cancel'))),
					ht_utable()),
				ht_uform());
	}
} # END $self->do_delete

#-------------------------------------------------
# $self->do_edit($r, $id)
#-------------------------------------------------
sub do_edit {
	my ($k, $r, $id) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title}	.= 'Edit Role';
	
	return($k->_relocate($r, $$k{rootp})) if ($in->{cancel});
	return('Invalid id.') if (! is_integer($id));

	if (! (my @errors = $k->_checkvals($in))) {

		# Clean up the signature.
		$in->{signature} =~ s/\r\n/\n/g;
		$in->{signature} =~ s/\r/\n/g;
		$in->{signature} = ht_qt($in->{signature});
		
	   	# IF main_role is true, update everyone else to false.
	   	if ($in->{main_role}) {
			db_run($$k{dbh}, 'update other default',
					sql_update('wm_roles', 
								' WHERE wm_user_id ='.sql_num($$k{user_id}),
								'main_role'	=> sql_bool('f')));
	   	}

		db_run($$k{dbh}, 'Add a new role.', 
				sql_update('wm_roles',  
								'WHERE id ='. sql_num($id). 
								'AND wm_user_id = '. sql_num($$k{user_id}),
							'main_role'	=> sql_bool($in->{main_role}),
							'role_name'	=> sql_str($in->{role_name}),
							'name'		=> sql_str($in->{name}),
							'reply_to'	=> sql_str($in->{reply_to}),
							'savesent'	=> sql_str($in->{savesent}),
							'signature'	=> sql_str($in->{signature})));

		db_commit($$k{dbh});
		
		return($k->_relocate($r, $$k{rootp}));
	}
	else {
		# Get the old role values.
		my $sth = db_query($$k{dbh}, 'get old values',
							'SELECT main_role, role_name, name, reply_to, ',
							'savesent, signature FROM wm_roles WHERE id = ',
							sql_num($id), 'AND wm_user_id = ',
							sql_num($$k{user_id}));

		while (my($main, $rname, $name, $reply, $save, $sig) = db_next($sth)) {
			$in->{main_role} 	= $main 	if (! defined $in->{main_role});
			$in->{role_name} 	= $rname 	if (! defined $in->{role_name});
			$in->{name} 		= $name 	if (! defined $in->{name});
			$in->{reply_to} 	= $reply 	if (! defined $in->{reply_to});
			$in->{savesent} 	= $save 	if (! defined $in->{savesent});
			$in->{signature} 	= $sig 		if (! defined $in->{signature});
		}

		db_finish($sth);
		
		return(($r->method eq 'POST' ? @errors : ''), $k->_form($in));
	}
} # END $self->do_edit

#-------------------------------------------------
# $self->do_main($r)
#-------------------------------------------------
sub do_main {
	my ( $k, $r ) = @_;

	$$k{page_title} .= 'Roles';

	my @lines = (	ht_div({ 'class' => 'box' }),
					ht_table(),

					ht_tr(undef,
						ht_td({ colspan => 5, 'class' => 'hdr' }, 
								"Roles for $$k{user}")),

					ht_tr(undef,
						ht_td({ 'class' => 'shd' }, ''),
						ht_td({ 'class' => 'shd' }, 'Role'),
						ht_td({ 'class' => 'shd' }, 'Name'),
						ht_td({ 'class' => 'shd' }, 'Address'),
						ht_td({ 'class' => 'rshd' },
								'[',ht_a( "$$k{rootp}/add", 'Add' ), ']')),);

	# Get a list of all of the roles, show the default first.
	my $sth = db_query($$k{dbh}, 'get roles list',
						'SELECT id, main_role, role_name, name, reply_to ',
						' FROM wm_roles WHERE wm_user_id = ', 
						sql_num($$k{user_id}), 
						'ORDER BY main_role DESC, role_name' );

	while ( my($id, $main, $rname, $name, $reply) = db_next($sth) ) {

		push(@lines,	ht_tr(undef,
							ht_td({ 'class' => 'dta' }, ($main ? '*' : '')),
							ht_td({ 'class' => 'dta' }, $rname),
							ht_td({ 'class' => 'dta' }, $name),
							ht_td({ 'class' => 'dta' }, $reply),
							ht_td({ 'class' => 'rdta' },
								'[',
								ht_a("$$k{rootp}/edit/$id", 'Edit'), '|',
								ht_a("$$k{rootp}/delete/$id", 'Delete'), ']',
							)),);		
	}

	db_finish( $sth );

	return(@lines, ht_utable(), ht_udiv());
} # END $self->do_main

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail::Preferences::Roles - Roles Management.

=head1 SYNOPSIS

  use Alchemy::WebMail::Preferences::Roles;

=head1 DESCRIPTION

This module allows users to maintain roles for use with the system.
There must be at least one role, the default role, at any given time.
Users may not delete the default role, they may however pick a different
default role.

=head1 APACHE

This is a sample of the location required for this module to run.
Consult Alchemy::WebMail(3) to learn about the configuration options.

  <Location /webmail/mail/prefs/roles >
    SetHandler  perl-script

    PerlHandler Alchemy::WebMail::Preferences::Roles
  </Location>

=head1 DATABASE

This is the core table that this module manipulates.

  create table "wm_roles" (
    id          int4 PRIMARY KEY DEFAULT NEXTVAL( 'wm_roles_seq' ),
    wm_user_id  int4,       /* user entry id ( wm_users.id ) */
    main_role   bool,       /* only one default allowed per user */
    role_name   varchar,    /* name of the role */
    name        varchar,    /* name to display in email */
    reply_to    varchar,    /* reply to email address */
    savesent    varchar,    /* folder to save sent into */
    signature   text        /* Role signature */
  );

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
