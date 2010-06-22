package Alchemy::WebMail::Preferences;

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
# $k->_checkvals($in)
#-------------------------------------------------
sub _checkvals {
	my ($k, $in) = @_;

	my @errors;

	if (! is_number($in->{reply})) {
		push(@errors, 'Select reply inclusion.');
	}

	if (! is_number($in->{delete})) {
		push(@errors, 'Select delete action.');
	}

	if (! is_text($in->{length})) {
		push(@errors, 'Select session length.');
	}

	if (! is_number($in->{count})) {
		push(@errors, 'Select folder message count.');
	}

	if (! is_text($in->{field})) {
		push(@errors, 'Select sort field.');
	}

	if (! is_number($in->{order})) {
		push(@errors, 'Select sort order.');
	}

	if (@errors) {
		return(ht_div({ 'class' => 'error' },
					ht_h(1, 'Errors:'),
					ht_ul(undef, map {ht_li(undef, $_)} @errors )));
	}

	return();
} # END $k->_checkvals

#-------------------------------------------------
# $k->_form($in)
#-------------------------------------------------
sub _form {
	my ($k, $in) = @_;

	my @opts;

	for my $sopt (split(',', $$k{'p_sessopt'})) {
		push(@opts, $sopt, ucfirst($sopt));
	}

	return(ht_form_js($$k{uri}),	
			ht_div({ 'class' => 'box' }),
			ht_table(),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Reply Included'),
				ht_td(undef,
					ht_select('reply', 1, $in, '', '', '1', 'Yes', '0', 'No'))),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Delete Action'),
				ht_td(undef, ht_select('delete', 1, $in, '', '', 
										'1', 'Delete', '0', 'Move to Trash'))),
			
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Session Length'),
				ht_td(undef, ht_select('length', 1, $in, '', '', @opts))),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Folder Message Count'),
				ht_td(undef, ht_select('count', '1', $in, '', '',
										'10', '10', '25', '25', '50', '50',
										'1000', 'All'))),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Folder Sort Field'),
				ht_td(undef, ht_select('field', '1', $in, '', '', 
										'date', 'Date', 'from', 'From',
										'subject', 'Subject', 'size', 'Size'))),
			
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Folder Sort Order'),
				ht_td(undef, ht_select('order', '1', $in, '', '', 
										'0', 'Ascending', '1', 'Descending'))),

			ht_tr(undef,
				ht_td({ 'colspan' => '2', 'class' => 'rshd' }, 
					ht_submit('submit', 'Save'),
					ht_submit('cancel', 'Cancel'))),

			ht_utable(),
			ht_udiv(),
			ht_uform());
} # END $k->_form

#-------------------------------------------------
# $k->do_edit($r)
#-------------------------------------------------
sub do_edit {
	my ($k, $r) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title}	.= 'Update Preferences';
	
	return($k->_relocate($r, $$k{rootp})) if ($in->{cancel});

	if (my @err = $k->_checkvals($in)) {

		# Look up the users id and the old values. 
		my $sth = db_query($$k{dbh}, 'get prefs', 
							'SELECT reply_include, true_delete, ',
							'session_length, fldr_showcount, fldr_sortorder,',
							'fldr_sortfield FROM wm_users WHERE id = ', 
							sql_num($$k{user_id}));
	
		my ($reply, $delete, $length, $count, $order, $field) = db_next($sth);

		db_finish($sth);

		# Set the old values if they are not already defined. 
		# Setting here rather than above lets users blank entries.
		$in->{reply} 	= $reply 	if (! defined $in->{reply});
		$in->{delete} 	= $delete 	if (! defined $in->{delete});
		$in->{count} 	= $count 	if (! defined $in->{count});
		$in->{order} 	= $order 	if (! defined $in->{order});
		$in->{field} 	= $field 	if (! defined $in->{field});
		
		$in->{length} = $k->s2hm($length) if (! defined $in->{length});

		return(($r->method eq 'POST' ? @err : ''), $k->_form($in));
	}

	my $session = $k->hm2s($in->{length});

	db_run($$k{dbh}, 'Update user prefrences', 
			sql_update('wm_users', 'WHERE id ='. sql_num($$k{user_id}),
						'reply_include' 	=> sql_bool($in->{reply}),
						'true_delete' 		=> sql_bool($in->{delete}),
						'session_length'	=> sql_num($session),
						'fldr_showcount'	=> sql_num($in->{count}),
						'fldr_sortorder'	=> sql_num($in->{order}),
						'fldr_sortfield'	=> sql_str($in->{field})));

	db_commit($$k{dbh});
		
	return($k->_relocate($r, $$k{rootp}));
} # END $k->do_edit

#-------------------------------------------------
# $k->do_main($r)
#-------------------------------------------------
sub do_main {
	my ($k, $r) = @_;

	$$k{page_title} .= 'Preferences';

	return(ht_div({ 'class' => 'box' }),

			ht_table(),
			ht_tr(undef,
				ht_td({ 'class' => 'hdr' }, "Preferences for $$k{user}"),
				ht_td({ 'class' => 'rhdr' },
					'[', ht_a("$$k{rootp}/edit", 'Update'), ']')),
		
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Reply Included'),
				ht_td(undef, ($$k{p_reply} ? 'Yes' : 'No'))),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Delete Action'),
				ht_td(undef, ($$k{p_delete} ? 'Delete' : 'Move to trash'))),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Session Length'),
				ht_td(undef, $k->s2hm($$k{p_sess_s}))),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Folder Message Count'),
				ht_td(undef, $$k{p_fcount})),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Folder Sort Field'),
				ht_td(undef, ucfirst($$k{p_sfield}))),

			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Folder Sort Order'),
				ht_td(undef, ($$k{p_sorder} ? 'Descending' : 'Ascending'))),

			ht_utable(),
			ht_udiv());
} # END $k->do_main

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail::Preferences - Preferences

=head1 SYNOPSIS

  use Alchemy::WebMail::Preferences;

=head1 DESCRIPTION

This module allows users to manipulate their preferences for the
application, these are set to the application wide defaults on the users
first login. 

=head1 APACHE

This is a sample of the location required for this module to run.
Consult Alchemy::WebMail(3) to learn about the configuration options.

  <Location /webmail/mail/prefs >
    SetHandler  perl-script

    PerlHandler Alchemy::WebMail::Preferences
  </Location>

=head1 DATABASE

This is the core table that this module manipulates.

  create table "wm_users" (
    id                  int4 PRIMARY KEY DEFAULT NEXTVAL( 'wm_users_seq' ),
    reply_include       bool,       /* include original in reply */
    session_length      int2,       /* length of users session */
    fldr_showcount      int2,       /* number of emails in folder to show */
    fldr_sortorder      int2,       /* folder sort order */
    fldr_sortfield      varchar,    /* folder sort field */
    username            varchar     /* imap user name */
  );

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
