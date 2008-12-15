package Alchemy::WebMail;

use strict;
use Crypt::CBC;

use KrKit::AppBase;
use KrKit::DB;
use KrKit::Handler;
use KrKit::HTML qw( :common );
use KrKit::SQL;
use KrKit::Validate;

our $VERSION = '0.77';
our @ISA = ( 'KrKit::Handler' );

############################################################
# Functions                                                #
############################################################

#-------------------------------------------------
# $self->_cleanup( $r )
#-------------------------------------------------
sub _cleanup {
	my ( $site, $r ) = @_;
 	
	$site->SUPER::_cleanup( $r );

	if ( defined $$site{imap} ) {
		# Generate the folder list. ( new mail count )
		my @listing;
		my %folders 	= $$site{imap}->folder_list( $$site{mask_inbox} );	
		my $real_inbox 	= $$site{imap_inbox};

		# Try the inbox if we don't have it.
		if ( ! defined $folders{$real_inbox} ) {
			$$site{imap}->folder_subscribe( $real_inbox );
		}

		for my $fldr ( sort { ( $a eq $real_inbox ) ? -1 : $a cmp $b }
							( keys %folders ) ) {
		
			$$site{imap}->folder_open( $fldr );	
			my $mask 	= $site->inbox_mask( $fldr );

			if ( $$site{count_mail} || $fldr eq $$site{imap_inbox} ) {
				my $count 	= $$site{imap}->folder_nmsgs();
			
				push( @listing, '<li>', 
									ht_a( 	"$$site{mail_root}/main/$fldr", 
											"$mask ($count)"),
								'</li>' );
			}
			else {
				push( @listing, '<li>', 
									ht_a( 	"$$site{mail_root}/main/$fldr", 
											$mask ),
								'</li>' );
			}
		}

		$$site{'body_aux'} = ht_lines( @listing );
	
		$$site{imap}->close(); 			# close connection.
	}

	return();
} # END $self->_cleanup

#-------------------------------------------------
# $self->_init( $r )
#-------------------------------------------------
sub _init {
	my ( $site, $r ) = @_;
	
	$site->SUPER::_init( $r );

	$$site{'remote_ip'}		= $r->connection->remote_ip;
	
	$$site{'imap_domain'}	= $r->dir_config( 'WM_Domain') 	|| '';
	$$site{'imap_host'}		= $r->dir_config( 'WM_Host' )	|| 'localhost';
	$$site{'imap_proto'}	= $r->dir_config( 'WM_Proto' ) 	|| 'imap/notls';

	# Inbox must be set to "INBOX" otherwise it duplicates.
	$$site{'imap_inbox'}	= $r->dir_config( 'WM_Inbox' ) 	|| 'INBOX';
	$$site{'mask_inbox'}	= $r->dir_config( 'WM_Inbox_Mask' );
	$$site{'imap_drafts'}	= $r->dir_config( 'WM_Draft' ) 	|| 'Drafts';
	$$site{'imap_sent'}		= $r->dir_config( 'WM_Sent' ) 	|| 'Sentmail';
	$$site{'imap_trash'}	= $r->dir_config( 'WM_Trash' ) 	|| 'Trash';

	$$site{'cookie_name'}	= $r->dir_config( 'WM_CookieName') || 'WebMail';
	$$site{'cookie_path'}	= $r->dir_config( 'WM_CookiePath') || '/';
	$$site{'secretkey'}		= $r->dir_config( 'WM_SecretKey' );
	$$site{'cipher'}		= $r->dir_config( 'WM_Cipher' );
	$$site{'x-mailer'}		= $r->dir_config( 'WM_X-Mailer' ) 
								|| "WebMail $VERSION";
	
	$$site{'max_sub'} 		= $r->dir_config( 'WM_Subject_Max' ) || '0';
	$$site{'count_mail'} 	= $r->dir_config( 'WM_Count_Messages' ) || '0';

	$$site{'mail_root'}		= $r->dir_config( 'WM_MailRoot' ) 		|| '/';
	$$site{'mail_fp'}		= $r->dir_config( 'WM_MailFP' ) 		|| '/';
	$$site{'address_root'}	= $r->dir_config( 'WM_AddressRoot' ) 	|| '/';
	$$site{'group_root'}	= $r->dir_config( 'WM_AGroupRoot' ) 	|| '/';
	$$site{'folder_root'}	= $r->dir_config( 'WM_FolderRoot' ) 	|| '/';
	$$site{'pref_root'}		= $r->dir_config( 'WM_PrefRoot' ) 		|| '/';
	$$site{'login_root'}	= $r->dir_config( 'WM_LoginRoot' ) 		|| '/';
	$$site{'new_icon'}		= $r->dir_config( 'WM_NewIcon' ) 		|| 'New';
	$$site{'reply_icon'}	= $r->dir_config( 'WM_ReplyIcon' ) 		|| 'R';
	$$site{'addr_icon'}		= $r->dir_config( 'WM_ABookIcon' ) 		
								|| 'Address book';

	# This is used for the Preferences Page.
	$$site{'p_sessopt'} 	= $r->dir_config( 'WM_Pref_Session_Opt' );

	# Validate WM_Pref_Session_Opt
	if ( ! is_text( $$site{'p_sessopt'} ) ) {
		$$site{'p_sessopt'} = 'session,2:00,8:00';
	}
	else {
		for my $sopt ( split( ',', $$site{'p_sessopt'} ) ) {

			next if ( $sopt =~ /session/i );

			if ( $sopt !~ /\d+:\d+/ ) {
				die "Invalid 'WM_Pref_Session_Opt': '$sopt'";
			}

			my ( $hour, $min ) = split( ':', $sopt );

			if ( $min < 0 || $min > 59 ) {
				die "Invalid 'WM_Pref_Session_Opt' minutes: '$sopt'";
			}

			if ( $hour < 0 ) {
				die "Invalid 'WM_Pref_Session_Opt' hours: '$sopt'";
			}
		}
	}

	# Must happen at last moment before needed. ( after frame is set )
	$$site{'user'}	= '';
	$$site{'pass'}	= '';

	# Grab the cookie and figure it out.
	my $cookie = appbase_cookie_retrieve( $r );

	# Make sure we have a mostly good cookie for top of if.
	if ( ( is_text( $$cookie{ $$site{cookie_name} } ) ) && 
		 ( $$cookie{ $$site{cookie_name} } !~ /loggedout/i ) ) {

		my $cookie_text = $$cookie{ $$site{cookie_name} };

		# decrypt the cookie.
		( $$site{user}, $$site{pass} ) = $site->cookie_decrypt( $cookie_text );

		# Set the username
		$r->user( $$site{user} );

		# pull the core info from wm_users.
		my $sth = db_query( $$site{dbh}, 'get user info',
							'SELECT id, reply_include, true_delete, ',
							'session_length, fldr_showcount, fldr_sortorder,',
							'fldr_sortfield FROM wm_users WHERE username = ',
							sql_str( $$site{user} ) );

		( $$site{'user_id'}, $$site{'p_reply'}, $$site{'p_delete'}, 
		  $$site{'p_sess_s'}, $$site{'p_fcount'}, $$site{'p_sorder'}, 
		  $$site{'p_sfield'} ) = db_next( $sth );
	
		db_finish( $sth );

		# re-set the cookie.
		$$site{p_sess} 	= $site->s2hm( $$site{'p_sess_s'} );

		my $crypt 		= $site->cookie_encrypt( $$site{user}, $$site{pass} ); 
		my $expire 		= ( $$site{p_sess_s} > 0 ) ? $$site{p_sess_s} : undef ;

		appbase_cookie_set( $r, $$site{cookie_name}, $crypt, $expire, 
							$$site{cookie_path} );

		# log in to the imap server.
		$$site{imap} = Alchemy::WebMail::IMAP->new( $$site{imap_host}, 
									$$site{imap_proto}, $$site{imap_inbox},
									$$site{user}, $$site{pass},
									$$site{file_tmp} );
	}
	else {
		# These are used by the login page only.
		$$site{'p_reply'}	= $r->dir_config( 'WM_Pref_Reply' );
		if ( defined $$site{'p_reply'} ) {
			$$site{'p_reply'} = ( $$site{'p_reply'} =~ /false/i ) ? 0 : 1;
		}
		else {
			$$site{'p_reply'} = 1;
		}

		$$site{'p_delete'}	= $r->dir_config( 'WM_Pref_True_Delete' );
		if ( defined $$site{'p_delete'} ) {
			$$site{'p_delete'} = ( $$site{'p_delete'} =~ /true/i ) ? 1 : 0;
		}
		else {
			$$site{'p_delete'} = 0;
		}
		
		$$site{'p_sess'}	= $r->dir_config( 'WM_Pref_Session' );
		$$site{'p_sess'} 	= '2:00' if ( ! is_text( $$site{'p_sess'} ) );
	
		# Make sure p_sess is in p_sessopt.
		if ( $$site{'p_sessopt'} !~ /$$site{'p_sess'}/ ) {
			die "WM_Pref_Session '$$site{p_sess}' not in  WM_Pref_Session_Opt";
		}
	
		$$site{'p_sess_s'}	= $site->hm2s( $$site{p_sess} ); 
		
		$$site{'p_fcount'}	= $r->dir_config( 'WM_Pref_FCount' );
		$$site{'p_fcount'}	= 25 if ( ! is_integer( $$site{'p_fcount'} ) );
		
		# 1 DESC : 0 ASC
		$$site{'p_fsordr'}	= $r->dir_config( 'WM_Pref_FSortOrder' ) || '';
		$$site{'p_fsordr'} 	= ( $$site{'p_fsordr'} =~ /desc/i ) ? 1 : 0;
		
		$$site{'p_sfield'}	= $r->dir_config( 'WM_Pref_SortField' );
		$$site{'p_sfield'} 	= 'date' if ( ! is_text( $$site{'p_sfield'} ) );

		# Ensure valid field.
		if ( $$site{'p_sfield'} !~ /^(date|from|subject|size)$/ ) {
			$$site{'p_sfield'} = 'date';
		}
	
		$$site{'p_ssent'}	= $r->dir_config( 'WM_Pref_SaveSent' ) 	|| '';
	}

	return();
} # END $self->_init

#-------------------------------------------------
# $site->hm2s( $hours_minutes )
#-------------------------------------------------
sub hm2s ($$) {
	my ( $site, $hours_minutes ) = @_;

	return( 0 ) if ( ! is_text( $hours_minutes ) );
	return( 0 ) if ( $hours_minutes =~ /session/i );

	my $seconds = 0;

	my ( $hours, $minutes ) = split( ':', $hours_minutes );

	$seconds += ( $minutes * 60 );
	$seconds += ( $hours * 60 * 60 );

	return( $seconds );
} # END $site->hm2s

#-------------------------------------------------
# $self->inbox_mask( $folder )
#-------------------------------------------------
sub inbox_mask {
	my ( $site, $folder ) = @_;

	return( '' ) 					if ( ! defined $folder );
	return( $folder ) 				if ( ! defined $$site{mask_inbox} );
	return( $$site{mask_inbox} ) 	if ( $folder =~ /^$$site{imap_inbox}$/i );
	return( $folder );
} # END $self->inbox_mask

#-------------------------------------------------
# $site->s2hm( $seconds ))
#-------------------------------------------------
sub s2hm ($$) {
	my ( $site, $seconds ) = @_;	

	return( 'session' ) if ( ! is_integer( $seconds ) );
	return( 'session' ) if ( $seconds <= 0 );

	my ( $hours, $minutes ) = ( 0, 0 );

	$minutes 	= $seconds / 60;	
	$hours 		= $minutes / 60;
	my $min 	= $minutes % 60;

	return( sprintf( "%d:%02d" , $hours, $min ) );
} # END $site->s2hm

#-------------------------------------------------
# $site->cookie_encrypt( $user, $pass )
#-------------------------------------------------
sub cookie_encrypt {
	my ( $site, $user, $pass ) = @_;

	$user 	= '' if ( ! is_text( $user ) );
	$pass	= '' if ( ! is_text( $pass ) );

	my $c = Crypt::CBC->new( {	'key' 		=> $$site{secretkey},
								'cipher' 	=> $$site{cipher}, 		} );

	my $ciphertext = $c->encrypt_hex( "$user:;:$pass" );

	return( $ciphertext );
} # END cookie_encrypt

#-------------------------------------------------
# $site->cookie_decrypt( $encrypted_text )
#-------------------------------------------------
sub cookie_decrypt {
	my ( $site, $encrypted ) = @_;
	
	my $c = Crypt::CBC->new ( {	'key' 		=> $$site{secretkey},
								'cipher' 	=> $$site{cipher} 		} );

	my ( $user, $pass ) = split( ':;:', $c->decrypt_hex( $encrypted ) );
	
} # END $site->cookie_decrypt

#-------------------------------------------------
# $site->valid_mbox( $mbox )
#-------------------------------------------------
sub valid_mbox {
	my ( $site, $mbox ) = @_;

	return( 0 ) if ( ! is_text( $mbox ) );

	return( 0 ) if ( $mbox =~ /\*|%|#|&/ );

	return( 1 );
} # END $site->valid_mbox

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail - Web based e-mail application.

=head1 DESCRIPTION

Alchemy WebMail is a mod_perl 1.x based web e-mail client. 

=head1 MODULES

=over 4

=item Alchemy::WebMail::AddressBook

This module provides the management for the users address book, it
allows users to manage these entries. 

=item Alchemy::WebMail::AddressBook::Groups

Not yet implemented.

=item Alchemy::WebMail::Authentication

This is the Authentication for Webmail. It ensures that the user has the
cookie set by the login page but it does not check this cookie. The
cookie's password is checked on the first log in. If this cookie is
tampered with the access to the imap server will fail. On a related note
the cookie is encrypted using an encryption scheme of your choice so
tampering with the cookie in an effective way is fairly hard.

=item Alchemy::WebMail::Folders

This module allows users to manage folders in their mailbox set. It does
prevent the user from manipulating the "core" folders, ie the inbox,
drafts, sentmail, and trash folders that are specified in the apache
configuration.

=item Alchemy::WebMail::IMAP

This class is a wraper for the Mail::Cclient module. This is wrapped to
hide the interface and allow a simplified transition to a seperate IMAP
module if the need arises.

=item Alchemy::WebMail::Login

This module generates the log in and log out pages. The first cookie is
set and if it is a first time user their default preferences are set up. 

=item Alchemy::WebMail::Mail

This module is the guts of the WebMail application. It actually views
all of the folders to show a listing, allows compose / reply / forward /
drafts as well as viewing individual messages. 

=item Alchemy::WebMail::Preferences

This module allows users to manipulate their preferences for the
application, these are set to the application wide defaults on the users
first login. 

=item Alchemy::WebMail::Preferences::Roles

This module allows users to maintain roles for use with the system.
There must be at least one role, the default role, at any given time.
Users may not delete the default role, they may however pick a different
default role.

=back

=head1 SCRIPTS

=over 4

=item webmail_purgeuser.pl

This script will remove all entries for a particular user from the
database, this is a non-reversable proceedure. Multiple users may be
removed at one time.

=back

=head1 CONFIGURATION

These are the PerlSetVar's that WebMail uses. These should in most
installations be in the top level Location. The following example shows
how to set a couple of example variables. For a working example of how
to configure this application see C<WebMail.conf>.

  <Location /example>
    PerlSetVar Example_Variable    "value"
    PerlSetVar Example_Variable2   "value2"
  </Location>

=over 4

=item Frame

No default, see L<KrKit::Framing::Template> for examples.

=item SiteTitle

This is the pretty title displayed in the C<##PAGE_TITLE##> variable in
the template, there is not default.

=item File_Temp

defaults to '/tmp'

=item File_Path

defaults to '/tmp'

=item File_PostMax

Set as byptes, no default, this allows files of unlimited size to be
uploaded. It's probably a good idea to set this around 5MB (5242880).

=item SMTP_Host

This variable sets the outbond SMTP server, either the DNS name or an IP
can be used.  Since ther is no default for this variable it is best that
this is set or users will be unable to send mail.

=item WM_CookieName

This variable sets the name for the cookie that WebMail uses.  Defualts
to "WebMail".

=item WM_CookiePath

This is the path to use for cookies, this should be one directory higher
than the application. This variable defaults to "/", this keeps us to
only 1 cookie for the site.	

=item WM_Host

This is the IMAP mail server that this application will be using. This
defaults to "localhost". A host may have the string <user> included
which will replace that section of the hostname with the current users
name.

=item WM_Proto

This is the specfic IMAP protocol to use, see the documentation for your
IMAP server for options.  This defaults to "imap/notls".

=item WM_Inbox

This is the name of the Inbox for all users, this really should be set
to "INBOX", in fact, it defaults to "INBOX". 

=item WM_Draft

This variable sets the folder to be used for Drafts, appropriately it
defaults to "Drafts".

=item WM_Sent

This variable sets the folder to be used for Sent-mail. It defaults to
"Sentmail".

=item WM_Trash

This variable sets the folder to be used for Trash, defaults to "Trash".

=item WM_MailRoot

This variable sets the location for C<Alchemy::WebMail::Mail>. This
allows the application to be aware of itself.  Defaults to "/".

=item WM_MailFP

This variable sets the location for the first page to be shown after
login.  Defaults to "/".

=item WM_AddressRoot

This variable sets the location for C<Alchemy::WebMail::AddressBook>.
This allows the application to be aware of itself.  Defaults to "/".

=item WM_FolderRoot

This variable sets the location for C<Alchemy::WebMail::Folders>. This
allows the application to be aware of itself.  Defaults to "/".

=item WM_PrefRoot

This variable sets the location for C<Alchemy::WebMail::Preferences>.
This allows the application to be aware of itself.  Defaults to "/".

=item WM_LoginRoot

This variable sets the location for C<Alchemy::WebMail::Login>. This
allows the application to be aware of itself.  Defaults to "/".

=item WM_Domain

This is the default domain that users of WebMail share. It must be set
and has no default.

=item WM_SecretKey

This is the key used during the encryption process. There is no default,
if this variable is not set the application will C<die()>.

=item WM_Cipher

This variable should be set to the CBC support library that is installed
on the system, such as "Crypt::Blowfish". There is no default for this
variable.

=item WM_Subject_Max

This variable sets the maximum length in characters to allow the subject
to display on the main e-mail listing. If not set or set to '0' there is
no limit. 

=item WM_X-Mailer

This variable sets the X-Mailer header set on all out bound e-mails. The
default is "WebMail $VERSION".

=item WM_Pref_Reply

This variable sets the default value for "Reply Included", defualts to
True. The possible options are "True" or "False".

=item WM_Pref_True_Delete

This variable specifies the default delete action. "True" indicates that
the application should skip the "Trash" folder, "False" does not. The
default is "False".

=item WM_Pref_Session

This sets the default Session length for users. The default is "2:00".
This value must be contained in "WM_Pref_Session_Opt" or the application
will C<die()>.

=item WM_Pref_Session_Opt 

This sets the possible session options that a user can select from. The
numrical values should be "HH:MM". Defaults to "Session,2:00,8:00".

=item WM_Pref_FCount

This variable sets the default number of messages that are shown. The
default is 25.

=item WM_Pref_FSortOrder	 

This variable sets the default sort order for messages in a folder.
Defaults to "DESC", possible values are "DESC" or "ASC".

=item WM_Pref_SortField	

This variable sets the default sort field for messages in a folder.
Defaults to "date", the possible sort fields are "date", "from",
"subject", and "size".

=item WM_Pref_SaveSent	 

This variable sets the default Save Sentmail folder. There is no
default. This means that sent mail is not saved by default.

=item WM_NewIcon		

This variable contains the text to display in the event of a new e-mail
for use on the folder listings. Defaults to "New".

=item WM_ABookIcon

This variable contains the text to display for the address book on the
e-mail compose page.  Defaults to "Address book".

=item WM_ReplyIcon

This variable contains the text to display for e-mails that the user has
replied. Defaults to "R".
	
=back

=head1 METHODS

=over 4

=item $self->_cleanup_app( $r )

Called by the core handler to clean up after each page request.

=item $self->_init_app( $r )

Called by the core handler to initialize each page request.

=item $site->hm2s( $hours_minutes )

Converts C<$hours_minutes> to seconds.

=item $site->s2hm( $seconds )

Converts C<$seconds> to a hours and minutes duration in the from HH:MM.

=item $site->cookie_encrypt( $user, $pass )

Encrypts the C<$user> and C<$pass> and returns the encrypted text.

=item $site->cookie_decrypt( $encrypted_text )

Returns C<$user> and C<$password> decode fom the C<$encrypted_text>.

=item $site->valid_mbox( $mbox )

Returns C<1> or C<0> depending on C<$mbox> being a syntacticly valid
folder name.

=back

=head1 SEE ALSO

KrKit(3), perl(3)

=head1 LIMITATIONS

Washington University IMAP does not honor the subscribe to INBOX unless
there exists e-mail in the INBOX at the time of subscription. Cyrus IMAP
server does not have this limitation.

In the event of a user using POP3 and IMAP at the same time there is the
possibility that the mail spool may be corrupted. This is not a problem
that WebMail is able to address, beyond noting the possibility.

=head1 AUTHOR

Nicholas Studt <nstudt@photodwarf.org>

=head1 COPYRIGHT

Copyright (c) 2003-2008 Nicholas Studt. All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=cut
