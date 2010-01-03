package Alchemy::WebMail::Folders;

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
# $k->_checkvals( $in, $edit )
#-------------------------------------------------
sub _checkvals {
	my ( $k, $in, $edit ) = @_;

	my @err;

	if ( ! is_text( $in->{folder} ) ) {
		push( @err, ht_li( {}, 'Enter folder name.' ) );
	}
	else {
		if ( $in->{folder} =~ /\// ) {
			push( @err, ht_li( {}, '"/" is not a valid character.' ) );
		}

		if ( ! $k->valid_mbox( $in->{folder} ) ) {
			push( @err,	ht_li( {}, '"*", "%", "#", and "&" are not a valid characters' ) );
		}

		if ( defined $edit && $edit ) {
			if ( $in->{folder_old} eq $in->{folder} ) {
				push( @err, ht_li( {}, 'Folder name is the same.' ) );
			}
		}

		# Make sure the folder does not already exist.
		if ($$k{imap}->folder_exists($in->{folder})) {
			push( @err, ht_li( {}, 'This folder already exists.' ) );
		}
	}

	if ( @err ) {
		return( ht_div( { 'class' => 'error' }, ht_ul( {}, @err ) ) );
	} 

	return();
} # END $k->_checkvals

#-------------------------------------------------
# $k->_form( $in, $edit )
#-------------------------------------------------
sub _form {
	my ( $k, $in, $edit ) = @_;

	my $name = ( defined $edit && $edit ) ? 'Rename' : 'Create' ;

	return( ht_form_js( $$k{uri} ),	
			ht_div( { 'class' => 'box' } ),
			ht_table( {} ),

			ht_tr(),
			ht_td( { 'class' => 'shd' }, 'Folder' ),
			ht_td( {}, ht_input( 'folder', 'text', $in ) ),
			ht_utr(),

			ht_tr(),
			ht_td( 	{ 'colspan' => '2', 'class' => 'rshd' }, 
					ht_submit( 'submit', $name. ' Folder' ),
					ht_submit( 'cancel', 'Cancel' ) ),
			ht_utr(),

			ht_utable(),

			ht_udiv(),
			ht_uform() );
} # END $k->_form

#-------------------------------------------------
# $k->do_add( $r )
#-------------------------------------------------
sub do_add {
	my ( $k, $r ) = @_;

	my $in 				= $k->param( Apache2::Request->new( $r ) );
	$$k{page_title}	.= 'Create Folder';
	
	return( $k->_relocate( $r, $$k{rootp} ) ) if ( $in->{cancel} );

	if ( my @err = $k->_checkvals( $in ) ) {
		return( ( $r->method eq 'POST' ? @err : '' ), $k->_form( $in ) );
	}

	# Create the folder.
	if ( ! $$k{imap}->folder_create( $in->{folder} ) ) {
		return( 'Error: ', $$k{imap}->error() );
	}
	
	return( $k->_relocate( $r, $$k{rootp} ) );
} # END $k->do_add

#-------------------------------------------------
# $k->do_delete( $r, $folder, $yes )
#-------------------------------------------------
sub do_delete {
	my ( $k, $r, $folder, $yes ) = @_;

	my $in 				= $k->param( Apache2::Request->new( $r ) );
	$$k{page_title} 	.= 'Delete Folder';

	return( 'No Folder.' ) 						if ( ! is_text( $folder ) );
	return( $k->_relocate( $r, $$k{rootp} ) ) 	if ( defined $in->{cancel} );

	if ( ( defined $yes ) && ( $yes eq 'yes' ) ) {

		# Remove this folder.
		if ( ! $$k{imap}->folder_delete( $folder ) ) {
			return( 'Error: ', $$k{imap}->error() );
		}

		db_run( $$k{dbh}, 'update any roles this affects',
				sql_update( 'wm_roles', 
							'WHERE wm_user_id = '. sql_num( $$k{user_id} ).
							'AND savesent = '. sql_str( $folder ),

							'savesent' => sql_str( '' ) ) );

		db_commit( $$k{dbh} );

		return( $k->_relocate( $r, $$k{rootp} ) );
	}
	else {
		# Check against master list.
		for my $fldr ( 	$$k{imap_drafts}, $$k{imap_sent}, 
						$$k{imap_trash}, $$k{imap_inbox} )
		{
			next if ( $fldr ne $folder );

			return( ht_form_js( "$$k{uri}/yes" ), 
					ht_div( { 'class' => 'box' } ),
					ht_table( {} ),
					ht_tr(),
						ht_td( {},
								qq!The '$folder' folder is required for !,
								q!normal operation and may not !,
								q!be removed.! 	),
					ht_utr(),
					ht_tr(),
						ht_td( 	{ 'class' => 'rshd' }, 
								ht_submit( 'cancel', 'Back' ) ),
					ht_utr(),
					ht_utable(),
					ht_udiv(),
					ht_uform() );
		}

		my $count = $$k{imap}->folder_nmsgs($folder);

		return( ht_form_js( "$$k{uri}/yes" ), 
				ht_div( { 'class' => 'box' } ),
				ht_table( { } ),
				ht_tr(),
					ht_td( {}, 
							qq!Delete the folder "$folder" ? This will !,
							q!completely remove this folder and all !,
							qq! '$count' message(s) it contains.! ),
				ht_utr(),
				ht_tr(),
					ht_td( { 'class' => 'rshd' }, 
							ht_submit( 'submit', 'Continue with Delete' ),
							ht_submit( 'cancel', 'Cancel' ) ),
				ht_utr(),
				ht_utable(),
				ht_udiv(),
				ht_uform() );
	}
} # END $k->do_delete

#-------------------------------------------------
# $k->do_edit( $r, $folder )
#-------------------------------------------------
sub do_edit {
	my ( $k, $r, $folder ) = @_;

	my $in 			= $k->param( Apache2::Request->new( $r ) );
	$$k{page_title}	.= 'Rename Folder';

	return( 'Unknown folder.' ) 				if ( ! is_text( $folder ) );
	return( $k->_relocate( $r, $$k{rootp} ) ) 	if ( $in->{cancel} );
		
	$in->{folder_old} = $folder;

	if ( my @err = $k->_checkvals( $in, 1 ) ) {
		$in->{folder} = $folder;

		return( ( $r->method eq 'POST' ? @err : '' ), $k->_form( $in, 1 ) );
	}

	db_run( $$k{dbh}, 'update any roles this affects',
			sql_update( 'wm_roles', 
							'WHERE wm_user_id = '. sql_num( $$k{user_id} ).
							'AND savesent = '. sql_str( $folder ),
						'savesent' => sql_str( $in->{folder} ) ) );

	# Rename the folder.
	if ( ! $$k{imap}->folder_rename( $folder, $in->{folder} ) ) {
		return( 'Error: ', $$k{imap}->error() );
	}

	db_commit( $$k{dbh} );
		
	return( $k->_relocate( $r, $$k{rootp} ) );
} # END $k->do_edit

#-------------------------------------------------
# $k->do_main( $r )
#-------------------------------------------------
sub do_main {
	my ( $k, $r ) = @_;

	$$k{page_title} .= 'Folders List';

	my %folders = $$k{imap}->folder_list();	
	my %no_edit	= ( $$k{imap_drafts}  	=> 1,
					$$k{imap_sent} 		=> 1, 
					$$k{imap_trash}  	=> 1,
					$$k{imap_inbox}		=> 1 );

	my @lines 	= (	ht_div( { 'class' => 'box' } ),
					ht_table( {} ),

					ht_tr(),
						ht_td( 	{ 'class' => 'hdr' }, 'Folder' ),
						ht_td( 	{ 'class' => 'hdr' }, 'Messages' ),
						ht_td( 	{ 'class' => 'rhdr' },
								'[',
								ht_a( "$$k{rootp}/add", 'New Folder' ), 
								']' ),
					ht_utr() );

	# Show all of the current folders. ( and their message counts )
	for my $folder ( sort 	{ ( $a eq $$k{imap_inbox} ) ? -1 : $a cmp $b }
							( keys( %folders )  ) ) {

		my $count = $$k{imap}->folder_nmsgs($folder);

		push( @lines,	ht_tr(),
						ht_td( {}, $k->inbox_mask( $folder ) ),
						ht_td( {}, $count ),
						ht_td( { 'class' => 'rdta' } ) );

		if ( ! defined $no_edit{$folder} ) {
			push( @lines, 	'[', ht_a( "$$k{rootp}/edit/$folder", 'Rename' ),
							'|', 
							ht_a( "$$k{rootp}/delete/$folder", 'Delete' ), 
							']', );
		}

		push( @lines, 	ht_utd(),
						ht_utr() );		
	}

	return( @lines, ht_utable(), ht_udiv() );
} # END $k->do_main

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail::Folders - Folder Management.

=head1 SYNOPSIS
 
  use Alchemy::WebMail::Folders;

=head1 DESCRIPTION

This module allows users to manage folders in their mailbox set. It does
prevent the user from manipulating the "core" folders, ie the inbox,
drafts, sentmail, and trash folders that are specified in the apache
configuration.

=head1 APACHE

This is a sample of the location required for this module to run.
Consult Alchemy::WebMail(3) to learn about the configuration options.

  <Location /webmail/mail/folders >
    SetHandler  perl-script

    PerlHandler Alchemy::WebMail::Folders
  </Location>

=head1 DATABASE

This module only updates the wm_roles database as folders are either
deleted or renamed.

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
