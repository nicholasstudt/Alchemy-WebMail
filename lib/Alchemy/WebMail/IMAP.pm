package Alchemy::WebMail::IMAP;

use strict;

use Encode qw(decode);
use Mail::IMAPClient;
use MIME::Entity;
use Net::SMTP;
#use POSIX qw(strftime);

use KrKit::Validate;

############################################################
# Functions                                                #
############################################################

#-------------------------------------------------
# $imap->address_list( $list )
#-------------------------------------------------
sub address_list {
	my ( $self, $list ) = @_;

	return() if ( ! is_text( $list ) );

	my @emails;
	
	$list =~ s/\r\n|\r|\n//g;

	for my $addr ( split ( /\s?,\s?|\s?;\s?/, $list ) ) { 

		# This takes care of the cases ( seperated by , or ; ):
		#  "name name" <email@mail.com>, <name@email.com>, name@email.com
		#  name name@email.com, "last, first" <name@email.com>
		$addr =~ s/^.*<//;
		$addr =~ s/>.*$//;
		$addr =~ s/^.*\s+//;

		next if ( $addr !~ /\S+@\S+/ );

		push( @emails, $addr );
	}

	return( @emails );
} # END $imap->address_list

#-------------------------------------------------
# $imap->alive()
#-------------------------------------------------
sub alive {
	my $self = shift;

	return(defined $self->{imap} ? 1 : 0);
} # END $imap->alive

#-------------------------------------------------
# $imap->close()
#-------------------------------------------------
sub close {
	my $self = shift;

	$self->{imap}->disconnect();
} # END $imap->close

#-------------------------------------------------
# $imap->decode_iso()
#-------------------------------------------------
sub decode_iso {
	my ($self, $string) = @_;

	# Decodes UTF8 stuff in a string.
	$string = decode('MIME-Header', $string);

	return($string);
} # END $imap->decode_iso

#-------------------------------------------------
# $imap->error()  
#-------------------------------------------------
sub error {
	my $self = shift;

	return((defined $self->{error}) ? $self->{error} : undef );
} # END $imap->error

#-------------------------------------------------
# $imap->folder_exists($folder)
#-------------------------------------------------
sub folder_exists {
	my ($self, $folder) = @_;

	return($self->{imap}->exists($folder));
} # END $imap->folder_exists

#-------------------------------------------------
# $imap->folder_create($folder, $can_fail)
#-------------------------------------------------
sub folder_create {
	my ($self, $folder, $cfail) = @_;

	# Allow fail of the create but not the subscibe.
	$cfail = 0 if (! is_integer($cfail));

	$self->{error} = undef;

	if ($self->{imap}->exists($folder)) {
		$self->{error} = 'Folder already exists.';
		return(0);
	}

	# Must use the host proto when addressing a mailbox.
	if ($self->{imap}->create($folder)) {
		return($self->folder_subscribe($folder)); 
	}
	else {
		if ($cfail) {
			return($self->folder_subscribe($folder)); 
		}
		else {
			$self->{error} = "Could not create folder: $folder";
			return(0);
		}
	}
} # END $imap->folder_create

#-------------------------------------------------
# $imap->folder_delete($folder)
#-------------------------------------------------
sub folder_delete {
	my ($self, $folder) = @_;

	if (! is_text($folder)) {
		$self->{error} = 'Folder does not exist';
		return(0);
	}
	
	$self->{error} = undef;
	
	if (!$self->folder_unsubscribe($folder)) {
		return(0); # Error already set.
	}
	
	if (!$self->{imap}->delete($folder)) {
		$self->{error} = "Could not delete folder: $folder";
		return(0);
	}

	return(1);
} # END $imap->folder_delete

#-------------------------------------------------
# $imap->folder_list()
#-------------------------------------------------
sub folder_list {
	my $self = shift;

	my %folders;

	for my $f ($self->{imap}->subscribed) {
		$folders{$f} = '';
	}

	return %folders
} # END $imap->folder_list()

#-------------------------------------------------
# $imap->folder_nmsgs($folder)
#-------------------------------------------------
sub folder_nmsgs {
	my ($self, $folder) = @_;

	my $count = $self->{imap}->message_count($folder);

	return((defined $count) ? $count : 0);
} # END $imap->folder_nmsgs

#-------------------------------------------------
# $imap->folder_rename($old_folder, $new_folder)
#-------------------------------------------------
sub folder_rename {
	my ($self, $old, $new) = @_;

	if (! is_text($old)) {
		$self->{error} = 'Folder does not exist.';
		return( 0 );
	}

	if (! is_text($new)) {
		$self->{error} = 'Folder does not exist.';
		return( 0 );
	}
	
	$self->{error} = undef;

	# rename
	if(!$self->{imap}->rename($old, $new)) {
		$self->{error} = 'Could not rename folder';
		return(0);
	}
	
	# subscribe (error already set)
	if(!$self->folder_subscribe($new)) {
		return(0);
	}

	# unsubscribe 
	return($self->folder_unsubscribe($old));
} # END $imap->folder_rename

#-------------------------------------------------
# $imap->folder_subscribe($folder)
#-------------------------------------------------
sub folder_subscribe {
	my ($self, $folder) = @_;

	if (! is_text($folder)) {
		$self->{error} = 'Folder is not valid.';
		return(0);
	}
	
	$self->{error} = undef;

	if(!$self->{imap}->subscribe($folder)) {
		$self->{error} = "Could not subscribe to folder: $folder";
		return(0)
	}

	return(1);
} # END $imap->folder_subscribe

#-------------------------------------------------
# $imap->folder_unsubscribe($folder)
#-------------------------------------------------
sub folder_unsubscribe {
	my ($self, $folder) = @_;
	
	if (! is_text($folder)) {
		$self->{error} = 'Folder is not valid.';
		return( 0 );
	}

	$self->{error} = undef;
	
	if(!$self->{imap}->unsubscribe($folder)) {
		$self->{error} = "Could not unsubscribe folder: $folder";
		return(0);
	}

	return(1);
} # END $imap->folder_unsubscribe

#-------------------------------------------------
# $imap->message_append( $folder, $message, $flag )
#-------------------------------------------------
sub message_append {
	my ( $self, $folder, $message, $flag ) = @_;

	# Don't do anything if we do not have a save folder.
	return( undef ) if ( ! is_text( $folder ) );

	$flag = '\Seen' if ( ! is_text( $flag ) );

	my ( %seen, $nuid );
	my $date = $self->{imap}->Rfc822_date();

	# Get the list of uid's in the folder.
	#$self->folder_open( $folder );
	my $nmsg = $self->folder_nmsgs($folder);
	
	for my $msg ( 1..$nmsg ) {
		my $uid 	= $self->{imap}->uid( $msg );
		$seen{$uid} = 1;
	}

	# Save a message to a particular folder.
	$self->{imap}->append( 	$self->{hostproto}.$folder, 
							$message->stringify, $date, $flag );

	# Get the uid's now. 
	#$self->folder_open( $folder );
	my $nnmsg = $self->folder_nmsgs($folder);

	for my $msg ( 1..$nnmsg ) {

		my $uid = $self->{imap}->uid( $msg );

		next if ( defined $seen{$uid} );

		$nuid = $uid;
	}

	return( $nuid );
} # END $imap->message_append

#-------------------------------------------------
# $imap->message_clearflag( $uid, @flags );
#-------------------------------------------------
sub message_clearflag {
	my ( $self, $uid, @flags ) = @_;

	return() if ( ! is_integer( $uid ) );
	
	for my $flag ( @flags ) {
		$self->{imap}->clearflag( $uid, $flag, 'uid' );
	}

	return();
} # END $imap->message_clearflag

#-------------------------------------------------
# $imap->message_copy($original_folder, $uid, $folder)
#-------------------------------------------------
sub message_copy {
	my ($self, $original_folder, $uid, $folder) = @_;
	
	$self->{error} = undef;

	if (! is_text($original_folder)) {
		$self->{error} = 'Folder does not exist.';
		return(0);
	}

	if (! is_integer($uid)) {
		$self->{error} = 'UID does not exist.';
		return(0);
	}

	if (! is_text($folder)) {
		$self->{error} = 'Folder does not exist.';
		return(0);
	}

	$self->{imap}->select($original_folder);

	if(!$self->{imap}->copy($folder, $uid)) {
		$self->{error} = 'Could not copy message';
		return(0);
	}

	$self->{imap}->expunge();

	return(1);
} # END $imap->message_copy

#-------------------------------------------------
# $imap->message_decode($folder, $uid)
#-------------------------------------------------
sub message_decode {
	my ($self, $folder, $uid) = @_;

	return(0) if (! is_text($folder));
	return(0) if (! is_integer($uid));

	my $body = $self->{imap}->get_bodystructure($uid);
	my $envelope = $self->{imap}->get_envelope($uid);

	my %msg;

#	my %msg = ( 'head' 	=> $entity->head,
#				'body'	=> $entity->bodyhandle	);
#
#	( $msg{type}, $msg{subtype} ) = split( '/', $msg{head}->mime_type );
#
#	my $print 	= ( $msg{type} =~ /^(text|message)$/ ) ? 1 : 0 ;
#	my $i 		= 0;
	
	for my $part ($body->parts()) {
		my $type = $body->bodytype($part);
		my $subtype = $body->bodysubtype($part);

#		# This makes nested messages go.
#		if ( $type =~ /multipart/ ) {
#			push( @parts, $parts[$i]->parts );
#			$i++;
#			next;
#		}
#
#		if ( $type =~ /^(text|message)$/ && ! $print )  {
#			# Override the core one if we should. ie it's multipart
#			$msg{body} 		= $item->bodyhandle; 
#			$msg{type} 		= $type;
#			$msg{subtype} 	= $subtype;
#			$print 			= 1;
#		}
#		else { 					# Pick up the attachment info.
#			# This line makes it skip the parts added by the e-mail
#			# clients and not real attachments, the html version of
#			# things and the like. ( Or I think it would. )
#			#next if ( ! defined $item->head->recommended_filename );
#
#			$msg{attach}{$i}{name} 	= $item->head->recommended_filename;
#			$msg{attach}{$i}{type} 	= "$type/$subtype";
#			$msg{attach}{$i}{fh} 	= $item->bodyhandle; # May not exist.
#			$msg{attach}{$i}{path} 	= $item->bodyhandle->path; 
#			$msg{attach}{$i}{size}	= 0;
#
#			if ( defined $item->bodyhandle ) { 	# may not exist
#				$msg{attach}{$i}{size} = int( -s $item->bodyhandle->path );
#			}
#
#			if ( ! defined $msg{attach}{$i}{name} ) { # may not exist
##				next if ( $subtype =~ /plain/ );
#				# drops plain text in  signed multiparts.
#
#				if ( $subtype =~ /html/ ) {
#					$msg{attach}{$i}{name} = 'View HTML Version of Message';
#				}
#				else {
#					$msg{attach}{$i}{name} = 'Unknown.'. $subtype;
#				}
#			}
#		}
#
#		$i++;
	}
	
	return(1, $envelope, $body);
} # END $imap->message_decode

#-------------------------------------------------
# $imap->message_delete( $folder, $uid ) 
#-------------------------------------------------
sub message_delete {
	my ( $self, $folder, $uid ) = @_;

	if ( ! is_text( $folder ) ) {
		$self->{error} = 'Folder does not exist.';
		return( 0 );
	}

	if ( ! is_integer( $uid ) ) {
		$self->{error} = 'UID does not exist.';
		return( 0 );
	}

	$self->{error} = undef;
	
	$self->folder_open( $folder );

	$self->{imap}->setflag( "$uid", '\Deleted', 'uid' );

	$self->{imap}->expunge();

	return( ( defined $self->{error} ) ?  0 :  1 );
} # END $imap->message_delete( $folder, $uid ) 

#-------------------------------------------------
# $imap->message_elt($uid)
#-------------------------------------------------
sub message_elt {
	my ($self, $uid) = @_;

	return(0) if (! is_integer($uid));

	my %flag_list; # Map the flags.
	for my $flag ($self->{imap}->flags($uid)) {
		$flag_list{$flag} = 1;
	}

	my $size = $self->{imap}->size($uid); # Fix the size.
	my $k = sprintf("%.1f", ($size / 1024));
	my $m = sprintf("%.1f", (($size / 1024) / 1024));

	return((($m < 1) ? (($k < 1) ? '&lt;1 KiB' : $k.' KiB') : $m.' MiB'),
			\%flag_list);
} # END $imap->message_elt

#-------------------------------------------------
# $imap->message_header($uid, @fields)
#-------------------------------------------------
sub message_header {
	my ($self, $uid, @fields) = @_;

	my $headers = $self->{imap}->parse_headers($uid, @fields);

	return( %{$headers} );
} # END $imap->message_header

#-------------------------------------------------
# $imap->message_mime( $site, $in, $attach )
#-------------------------------------------------
sub message_mime {
	my ( $self, $site, $in, $attach ) = @_;

	# Create a mime encoded version of the message which can be used to
	# either send the message or save it to a folder.

	# Maybe fix the newline problem.
	$in->{message} 	= '' 			if ( ! defined $in->{message} );
	$in->{message} 	=~ s/\r\n/\n/g;
	$in->{cc} 		= '' 			if ( ! defined $in->{cc} );
	$in->{bcc} 		= '' 			if ( ! defined $in->{bcc} );
	$in->{subject} 	= 'No Subject' 	if ( ! defined $in->{subject} );
	$in->{replyto}	= ''			if ( ! defined $in->{replyto} );
	$attach			= 1				if ( ! is_integer( $attach ) );

	if ( defined $in->{want_sig} && $in->{want_sig} ) {
		$in->{message} .= "\n--\n$in->{sig}";
	}

	my @attachments;
	#my $date 		= strftime( "%a, %d %b %Y %H:%M:%S %z", localtime( ) );
	my $date = $self->{imap}->Rfc822_date();
	my %msg 		= ( 'To' 			=> $in->{to},
						'From' 			=> $in->{from},
						'Date'			=> $date,
						'Reply-To' 		=> $in->{replyto},
						'Cc' 			=> $in->{cc},
						'Bcc' 			=> $in->{bcc},
						'Subject' 		=> $in->{subject},
						'X-Mailer' 		=> $$site{'x-mailer'},
						'X-Origin-Ip:'	=> $$site{remote_ip},
						'Type'			=> 'text/plain; format=flowed',
						'Encoding'		=> '-SUGGEST',
						'Data' 			=> [$in->{message}], );

	$msg{'In-Reply-To:'} = $in->{inreplyto} if ( defined $in->{inreplyto} );

	my $mime = MIME::Entity->build( %msg );

	if ( $attach ) {
		if ( opendir( ATTACHMENTS, $$site{file_path} ) ) {

			while ( my $file = readdir( ATTACHMENTS ) ) {
				next if ( $file !~ /^$$site{user}--/ );
			
				push( @attachments, "$$site{file_path}/$file" );
		
				my ( $type, $name ) = $file =~ /--\d+--(.*?)--(.*?)$/;
		
				$type =~ s/_/\//g;
			
				$mime->attach( 	Path 		=> "$$site{file_path}/$file",
								Type		=> $type, 
								Filename	=> $name,
								Encoding	=> '-SUGGEST' );
			}
	
			closedir( ATTACHMENTS );
		}
	}

	return( $mime, \@attachments );
} # END $imap->message_mime()

#-------------------------------------------------
# $imap->message_move($original_folder, $uid, $folder)
#-------------------------------------------------
sub message_move {
	my ($self, $original_folder, $uid, $folder) = @_;
	
	$self->{error} = undef;

	if (! is_text($original_folder)) {
		$self->{error} = 'Folder does not exist.';
		return(0);
	}

	if (! is_integer($uid)) {
		$self->{error} = 'UID does not exist.';
		return(0);
	}

	if (! is_text($folder)) {
		$self->{error} = 'Folder does not exist.';
		return(0);
	}

	$self->{imap}->select($original_folder);

	if(!$self->{imap}->move($folder, $uid)) {
		$self->{error} = 'Could not move message.';
		return(0);
	}

	$self->{imap}->expunge();

	return(1);
} # END $imap->message_move

#-------------------------------------------------
# $imap->message_msgno( $uid )
#-------------------------------------------------
sub message_msgno {
	my ( $self, $uid ) = @_;

	return( $self->{imap}->msgno( $uid ) );
} # END $imap->message_msgno

#-------------------------------------------------
# $imap->message_send($site, $message)
#-------------------------------------------------
sub message_send {
	my ( $self, $site, $message ) = @_;

	$message->head->unfold;
	
	$self->{error} = undef;

	my $count 	= 0;
	my $smtp 	= Net::SMTP->new( $$site{smtp_host} ); 

	# Actually set the error message so it can be pulled if there is a
	# problem.

	# SMTP was unable to connect case.
	if ( ! defined $smtp ) {
		$self->{error} = 'Could not connect to SMTP server.';
		return( 0 );
	}

	if ( ! $smtp->mail( "$$site{user}\@$$site{imap_domain}" ) ) {
		$self->{error} = 'Could not open SMTP connection.';
		return( 0 );
	}

	# Work out the addresses to actually use.
	my @to 	= $self->address_list( $message->head->get( 'To' ) 	|| '' );
	my @cc 	= $self->address_list( $message->head->get( 'Cc' ) 	|| '' );
	my @bcc = $self->address_list( $message->head->get( 'Bcc' ) || '' );

	if ( ! $smtp->to( @to ) ) {
		$self->{error} = 'Invalid to address.';
		return( 0 );
	}

	if ( @cc ) {
		if ( ! $smtp->cc( @cc ) ) {
			$self->{error} = 'Could not CC message.';
			return( 0 );
		}
	}

	if ( @bcc ) {
		if ( ! $smtp->bcc( @bcc ) ) {
			$self->{error} = 'Could not BCC message.';
			return( 0 );
		}
	}

	if ( ! $smtp->data() ) {
		$self->{error} = 'Could not start SMTP message.';
		return( 0 );
	}

	if ( ! $smtp->datasend( $message->stringify ) ) {
		$self->{error} = 'Could not send SMTP message.';
		return( 0 );
	}

	if ( ! $smtp->dataend() ) {
		$self->{error} = 'Could not end SMTP message send.';
		return( 0 );
	}

	if ( ! $smtp->quit ) {
		$self->{error} = 'Could not terminate SMTP connection.';
		return( 0 );
	}

	return( 1 );
} # END $imap->message_send

#-------------------------------------------------
# $imap->message_setflag( $folder, $uid, @flags )
#-------------------------------------------------
sub message_setflag {
	my ( $self, $folder, $uid, @flags ) = @_;

	return( 0 ) if ( ! is_text( $folder ) );
	return( 0 ) if ( ! is_integer( $uid ) );
	
	$self->folder_open( $folder );
	
	for my $flag ( @flags ) {
		$self->{imap}->setflag( $uid, $flag, 'uid' );
	}

	return( 1 );
} # END $imap->message_setflag

#-------------------------------------------------
# $imap->message_sort($folder, $field, $order, $type)
#-------------------------------------------------
sub message_sort {
	my ($self, $folder, $field, $order, $type) = @_;

	return(undef) if (! is_text($folder));
	return(undef) if (! is_text($field));

	$type 	= 'ALL' if (! defined $type);
	$order 	= 1 	if (! defined $order);
	$order 	= ($order) ? '' : 'REVERSE ';
	
	$self->{imap}->select($folder);

	return($self->{imap}->sort($order. uc($field), 'UTF-8', $type));
} # END $imap->message_sort

#-------------------------------------------------
# new($host, $proto, $mailbox, $user, $pass, $tmp)
#-------------------------------------------------
sub new {
	my ($proto, $host, $protocol, $mailbox, $user, $pass, $tmp) = @_;

	# FIXME: Make this understand SSL again.
	# Fix the arguement list.

	die "IMAP Hostname undefined" 	if (! is_text($host));
	die "IMAP protocol undefined" 	if (! is_text($protocol));
	die "IMAP mailbox undefined" 	if (! is_text($mailbox));
	die "IMAP username undefined" 	if (! is_text($user));
	die "IMAP password undefined" 	if (! is_text($pass));
	die "IMAP temp undefined" 		if (! is_text($tmp));

	my $class 	= ref($proto) || $proto;
	my $self 	= {};
	
	# Check for <user> in the hostname. And set it.
	$host =~ s/<user>/$user/g if ($host =~ /<user>/);

	# Save the defaults we were passed for use later.
	$self->{host} 		= $host;
	$self->{protocol} 	= $protocol;
	$self->{hostproto} 	= '{'. $host.'/'.$protocol. '}';
	$self->{mailbox} 	= $mailbox;
	$self->{user} 		= $user;
	$self->{password} 	= $pass;
	$self->{error}		= undef;
	$self->{temp}		= $tmp;

	bless($self, $class);

	$self->{imap} = Mail::IMAPClient->new(Server => $self->{host},
											User => $self->{user},
											Password => $self->{password},);

	return($self);
} # END new()

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail::IMAP - IMAP Wrapper Library.

=head1 SYNOPSIS
 
  use Alchemy::WebMail::IMAP;

  $imap = Alchemy::WebMail::IMAP->new( $host, $proto, $mbox, $user, $pass, $tmp );

=head1 DESCRIPTION

This class is a wraper for the Mail::IMAPClient module. This is wrapped to
hide the interface and allow a simplified transition to a seperate IMAP
module if the need arises.

=head1 METHODS

=over 4

=item new( $host, $proto, $mailbox, $user, $pass, $tmep_dir )

Returns a new IMAP object after creating the connection to the IMAP
server. All fields are required otherwise the function will C<die()>.

=item $imap->address_list( $list )

Returns an array of the e-mail addresses contained in the C<$list>. The
returned e-mails are simply the user@domain.com portion, the list can be
almost any possible e-mail notation.

=item $imap->alive() 

Returns true or false depending on wether or not the IMAP connection was
successful.

=item $imap->close()

Closes the IMAP connection.

=item $imap->error()

Returns either the current error from previous IMAP functions or undef
if no error has occured.

=item $imap->folder_create( $folder, $can_fail )

Returns C<1> or C<0> on success or failure of the creation of the folder.
C<$folder> is the folder to create. If C<$can_fail> is true the creation
of the folder is allowed to fail, but if the subscribe does not complete
then the function returns C<0>.

=item $imap->folder_delete( $folder )

This function deletes the given C<$folder> as well as unsubscribing from
the folder as well. C<1> is returned on success, C<0> on failure.

=item $imap->folder_list()

Returns a hash with the keys being the folders that the user is
subscribed to. 

=item $imap->folder_nmsgs()

This function checks for the count of messages in the currently open
folder. The count is returned.

=item $imap->folder_open( $folder )

Opens a given folder, no values are ever returned.

=item $imap->folder_rename( $old_folder, $new_folder )

This function renames a folder from C<$old_folder> to C<$new_folder>,
this also updates the folder subscriptions accordingly.  C<1> is
returned on success, C<0> on failure.

=item $imap->folder_subscribe( $folder )

Suscribes a user to C<$folder>. Returns C<1> on success, C<0> on
failure.

=item $imap->folder_unsubscribe( $folder )

Unsuscribes a user from C<$folder>. Returns C<1> on success, C<0> on
failure.

=item $imap->message_append( $folder, $message, $flag )

Appends a message to the C<$folder> with the C<$flag> set. C<$flag> will
default to "\Seen" if not set. The C<$message> is the messasge object
returned by the C<message_mime> method.

=item $imap->message_clearflag( $uid, @flags )

Clears the flags specified in the C<@flags> array from the C<$uid>.
Valid flags include, but are not limited to '\Seen', '\Draft',
'\Answered', or any other valid IMAP flag. 

=item $imap->message_decode( $folder, $uid )

Decodes the specified message, C<$uid>, in the given C<$folder>. This
returns ( 1, $mime_oject, $msg_object ) on success and ( 0 ) on failure.

=item $imap->message_delete( $folder, $uid )

Removes a message specified by C<$uid> from the specified C<$folder>.
Returns C<1> on success, C<0> on failure.

=item $imap->message_elt( $uid )

Returns the a pretty size string and a hash reference of with the keys
being the set flags. The message to check is specified by C<$uid>.

=item $imap->message_header( $uid, @fields )

Gathers and returns a hash of the headers specified in the C<@fields>
array. This operates on the message based on it's C<$uid>

=item $imap->message_mime( $site, $in, $attach )

This returns a C<$mime> object and an array reference of the filenames
attached. The C<$site> hash reference must contain valid keys and values
for "x-mailer", "remote_ip", "user", and "file_path". The C<$in> hash
reference must containg valid keys and values for "to", "from",
"replyto", "cc", "bcc", "subject", "inreplyto", and "message".

=item $imap->message_move( $original_folder, $uid, $folder )

Moves a message specified by C<$uid> from the C<$original_folder> to the
destination C<$folder>. Returns C<1> on success, C<0> on failure.

=item $imap->message_msgno( $uid )

Returns the message number for the currently open folder based on its
message uid.

=item $imap->message_send( $site, $message )

Send a message out. The C<$message> is the message object returned by
the C<message_mime> method. The C<$site> hash reference must include the
C<smtp_host>, C<user>, and C<imap_domain> keys and their respective
values. This function returns C<1> on success or C<0> on failure. No
error string is set in the event of failure.

=item $imap->message_setflag( $folder, $uid, @flags )

Sets the flag on a particular message based on it's C<$uid> in a given
C<$folder>, Valid flags are noted on the C<message_clearflag> method.
Returns C<1> on success, C<0> on failure.

=item $imap->message_sort( $folder, $field, $order )

Returns an array of message uids from the C<$folder> sorted by the
C<$field> in C<$order>. Order should be either 1 for ascending or 0 for
descending. Valid fields include "subject", "date", "size", "to" and
"from".

=back

=head1 SEE ALSO

Alchemy::Webmail(3), Alchemy(3), KrKit(3)

=head1 LIMITATIONS

This module suffers the limitations of Mail::IMAPClient, it's basis, as
well as all of the limitations inherant in the IMAP protocol.

=head1 AUTHOR

Nicholas Studt <nicholas@photodwarf.org>

=head1 COPYRIGHT

Copyright (c) 2003-2008 Nicholas Studt. All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=cut
