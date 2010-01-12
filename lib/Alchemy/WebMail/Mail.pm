package Alchemy::WebMail::Mail;

use strict;

use Apache2::Request qw(); # Enables file upload.
use Apache2::Upload;
use Date::Manip qw(UnixDate);

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
# $k->attachments_checkvals($in, $apr)
#-------------------------------------------------
sub attachments_checkvals {
	my ($k, $in, $apr) = @_;

	my @errors;

	if ($in->{attach}) {
		if (! is_text($in->{newfile})) {
			push(@errors, 'Select a file to upload.');
		}
		else { # Check the file size.
			my $upload 	= $apr->upload('newfile');
			my $size 	= $upload->size;

			if (! defined $size || $size < 1) {
				push(@errors, 'Select a file to upload.');
			}
		}
	}

	if ($in->{remove}) {
		if (! is_text($in->{attached})) {
			push(@errors, 'Select a file to remove.');
		}
	}

	if (! $in->{attach} && ! $in->{remove} && ! $in->{submit}) {
		push(@errors, 'Unseen error.');
	}

	if (@errors) {
		return(ht_div({ 'class' => 'error' }, 
						ht_h(1, 'Errors:'),
						ht_ul(undef, map {ht_li(undef, $_)} @errors)));
	}

	return();
} # END $k->attachments_checkvals

#-------------------------------------------------
# $k->attachments_form($in)
#-------------------------------------------------
sub attachments_form {
	my ($k, $in) = @_;

	# Get the list of all current attachments.
	my @files = ('', '-- Current Attachments --');

	if (opendir(ATTACHMENTS, $$k{file_path})) {

		while (my $file = readdir(ATTACHMENTS)) {
			next if ($file !~ /^$$k{user}--/);

			(my $name = $file) =~ s/^.*--//;
			
			push(@files, $file, $name);
		}

		closedir(ATTACHMENTS);
	}

	my $size = (int(scalar(@files) / 2)) + 1;

	return(ht_form_js($$k{uri}, 'enctype="multipart/form-data"'),	
			ht_div({ 'class' => 'box' }),
			ht_table(undef),

			ht_tr(undef,
				ht_td(undef, 
					ht_input('newfile', 'file', $in),
					ht_submit('attach', 'Attach'))),

			# Select
			ht_tr(undef,
				ht_td(undef,
					ht_select('attached', $size, $in, '', '', @files),
					ht_submit('remove', 'Remove'))),

			ht_tr(undef,
				ht_td({ 'colspan' => '2', 'class' => 'rshd' }, 
					ht_submit('submit', 'Back to e-mail'))),

			ht_utable(),
			ht_udiv(),
			ht_uform() );
} # END $k->attachments_form

#-------------------------------------------------
# $k->compose_checkvals($in)
#-------------------------------------------------
sub compose_checkvals {
	my ($k, $in) = @_;

	my @errors;

	if (! is_integer($in->{role})) {
		push(@errors, 'Select a role to use.');
	}

	if (! is_email($in->{to})) {
		push(@errors, 'Enter a valid "To" e-mail address.');
	}

	if (! is_text($in->{message})) {
		push(@errors, 'Enter a message for this e-mail.');
	}

	if (@errors) {
		return(ht_div({ 'class' => 'error' }, 
						ht_h(1, 'Errors:'),
						ht_ul(undef, map {ht_li(undef, $_)} @errors)));
	}

	return();
} # END compose_checkvals

#-------------------------------------------------
# $k->compose_form($in)
#-------------------------------------------------
sub compose_form {
	my ($k, $in) = @_;

	my (@roles, @files, @sigs);

	my $sth = db_query($$k{dbh}, 'get roles list',
						'SELECT id, main_role, role_name, reply_to, ',
						' signature FROM wm_roles WHERE wm_user_id = ', 
						sql_num($$k{user_id}), 'ORDER BY role_name');

	while (my ($id, $def, $name, $email, $sig) = db_next($sth)) {
		push(@roles, $id, "$name &lt;$email&gt;");

		$in->{role} = $id if ($def && (! defined $in->{role}));

		$sig = ht_uqt((defined $sig) ? $sig : '');
		$sig =~ s/"/\\"/g;
		$sig =~ s/(\r\n|\r|\n)/\\n/g;

		push(@sigs, '"'. $sig. '"');
	}

	db_finish($sth);

	if (opendir(ATTACHMENTS, $$k{file_path})) {

		while (my $file = readdir(ATTACHMENTS)) {
			next if ( $file !~ /^$$k{user}--/ );

			(my $name = $file) =~ s/^.*--//; # Get out the filename
			
			push(@files, $name, ht_br());
		}

		closedir(ATTACHMENTS);
	}

	my $sigcode = '	sigs = new Array( '. join(', ', @sigs).')';

	return(ht_form_js($$k{uri}, 'name="compose"'),	

			q!<script type="text/javascript">!,

			$sigcode,

			q! function SetAddr(Fe, Email) { !,
			q!  var Form = document.compose.elements[Fe]; !,

    		q!	if( Form.value.length == 0 || !,
        	q!		Form.value.indexOf(Email) == -1 ) { !,
        	q!		if( Form.value.length \!= 0 && !,
            q!			Form.value.charAt( Form.value.length -1 ) \!= ',') { !,
            q!			Form.value += ','; !,
        	q!		} !,
        	q!		Form.value += Email; !,
    		q!	} !,
			q! } !,

			q! 	function addrpop(n) { !,
			qq! 	window.open('$$k{address_root}/list/'+n, 'short',!,
			q! 					'height=550,width=350,scrollbars,resizable');!,
			q! 	} !,

			q!  function addsig() { !,
			q!	myField = document.compose.message; !,
			q!	myValue = "\n\n-- \n" +  !,
			q!  	sigs[document.compose.role.selectedIndex] + "\n"; !,
			q!	//IE support !,
			q!	if (document.selection) { !,
			q!		myField.focus(); !,
			q!		sel = document.selection.createRange(); !,
			q!		sel.text = myValue; !,
			q!	} !,
			q!	//MOZILLA/NETSCAPE support !,
			q!	else if (myField.selectionStart || !,
			q!				myField.selectionStart == '0') { !,
			q!		var startPos = myField.selectionStart; !,
			q!		var endPos = myField.selectionEnd; !,
			q!		myField.value = myField.value.substring(0, startPos) !,
			q!		+ myValue !,
			q!		+ myField.value.substring(endPos, myField.value.length); !,
			q!	} else { !,
			q!		myField.value += myValue; !,
			q!	} !,
			q!} !,

			q!</script>!,

			ht_div({ 'class' => 'box' }),
			ht_table(undef),

			# From ( role )
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'From'),
				ht_td(undef,
					ht_select('role', 1, $in, '', '', @roles),
					'[', ht_a('javascript:addsig()', 'Add Signature'), ']')),

			# To
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'To'),
				ht_td(undef,
					ht_input('to', 'text', $in, 'size="45"'), 
					ht_a('javascript:addrpop(\'to\')', $$k{addr_icon}))),

			# CC
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Cc'),
				ht_td(undef,
					ht_input('cc', 'text', $in, 'size="45"'),
					ht_a('javascript:addrpop(\'cc\')', $$k{addr_icon}))),

			# BCC
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Bcc'),
				ht_td(undef,
					ht_input('bcc', 'text', $in, 'size="45"'),
					ht_a('javascript:addrpop(\'bcc\')', $$k{addr_icon}))),

			# Subject
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Subject'),
				ht_td(undef,
					ht_input('subject', 'text', $in, 'size="50"'))),

			# Attachments
			ht_tr(undef,
				ht_td({ 'class' => 'shd' }, 'Attachments'),
				ht_td(undef,
					(@files) ? @files : 'No attachments',
					ht_submit('attach', 'Attachments'))),

			# Text
			ht_tr(undef,
				ht_td({ colspan => 2 }, 
					'Message', ht_br(),
					ht_input('message', 'textarea', $in, 
								'cols="75" rows="20"'))),

			ht_tr(undef,
				ht_td({ 'colspan' => '2', 'class' => 'rshd' }, 
					ht_submit( 'submit', 'Send' ),
					ht_submit( 'draft', 'Save Draft' ),
					ht_submit( 'cancel', 'Cancel' ) )),

			ht_utable(),
			ht_udiv(),
			ht_uform() );
} # END $k->compose_form

#-------------------------------------------------
# $k->do_attached( $r, $folder, $uid, $part )
#-------------------------------------------------
sub do_attached {
	my ($k, $r, $folder, $uid, $part) = @_;

	return('Invalid folder.') 		if (! is_text($folder));
	return('Invalid message.') 		if (! is_integer($uid));
	return('Inavlie message part.') if (! is_integer($part));
	
	my ($chk, $mime, $msg) = $$k{imap}->message_decode($folder, $uid);

	return('Could not decode message') if ( ! $chk );
	
	$$k{frame} = 'none'; # So we don't frame output.

	$$k{contenttype} = $$msg{attach}{$part}{type};
	$$k{body_file} = $$msg{attach}{$part}{path};
	
	# Can not purge here. Becaues then the attachment will not be
	# available for display.
	#$mime->filer->purge; 

	return('Get Attachment.');
} # END $k->do_attached

#-------------------------------------------------
# $k->do_attachments($r, $dfolder, $folder, $uid)
#-------------------------------------------------
sub do_attachments {
	my ($k, $r, $dfolder, $folder, $uid) = @_;

	return('Invalid draft folder.') if (! is_text($dfolder));
	return('Invalid folder.') 		if (! is_text($folder));
	return('Invalid msg_id.') 		if (! is_integer($uid));

	my $apr = Apache2::Request->new($r, TEMP_DIR => $$k{file_tmp});
#                                       POST_MAX => $$k{file_max});
#    my $status  = $apr->parse;
#    return( 'Error: Upload File too large.' ) if ( $status );
                                                                                
	my $in = $k->param($apr); # The in hash ;)
	$$k{page_title}	.= 'Manage attachments';

	# Show the form or errors as needed.
	if (my @err = $k->attachments_checkvals($in, $apr)) {
		return(($r->method eq 'POST' ? @err : ''), $k->attachments_form($in));
	}

	if ($in->{attach}) {	# Actually Save the file to disk.
		my $now 			= time;
		my $upload 			= $apr->upload('newfile');
		my $type 			= $upload->type();
		$type 				=~ s/\//_/g;
		my ( $t, $fname )   = $upload->filename =~ /^(.*\\|.*\/)?(.*?)?$/;
		$fname 				=~ s/--/-/g; # Make it marker safe.

		# Attach_path/$now-$uname-$type-$fname
		my $file = "$$k{file_path}/$$k{user}--$now--$type--$fname";
		
		if ( open( ATTACH, ">$file" ) ) {
			my $fh = $upload->fh;

			while ( my $part = <$fh> ) {
				print ATTACH $part;
			}

			close( ATTACH );
		}
		else {
			die "Could not open $file: $!";
		}

		$in->{newfile} = '';
		
		return($k->attachments_form($in));
	}

	if ($in->{remove}) { # Actually remove a file.
		if (! unlink("$$k{file_path}/$in->{attached}")) {
			die "Can not remove $in->{attached}: $!";
		}
		return($k->attachments_form($in));
	}

	# Send them to the compose draft page to pick up on the old message.
	return($k->_relocate($r,
				"$$k{rootp}/response/draft/$folder/$uid/$$k{imap_drafts}"));
} # END $k->do_attachments

#-------------------------------------------------
# $k->do_compose($r, $folder, $uid)
#-------------------------------------------------
sub do_compose {
	my ($k, $r, $folder, $uid) = @_;

	my $in = $k->param( Apache2::Request->new($r) );

	$$k{page_title}	.= 'Compose message';
	$folder = $$k{imap_inbox} if (! defined $folder);
 
 	if ($in->{cancel}) {
		return($k->_relocate($r, "$$k{rootp}/main/$folder"));
	}

	if ($in->{draft}) {
		$in->{want_sig} = 0; # Kill the sig on a draft.

		# Set the from address correctly.
		my ($name, $from, $sentmail, $sig) = $k->role_info($in->{role});	
		$in->{from}	= (is_text($name)) ? "\"$name\" <$from>" : $from;

		# Save to the drafts folder.
		my ($message, $attach) = $$k{imap}->message_mime($k, $in);
	
		# What about the From address ?
		$$k{imap}->message_append($$k{imap_drafts}, $message, '\Seen');

		# Unlink the files since they have been put in the draft.
		unlink(@{$attach});

		return($k->_relocate($r, "$$k{rootp}/main/$folder"));
	}

	if ($in->{attach}) {
		$in->{want_sig} = 0; # Kill the sig on a draft.
		
		# Set the from address correctly.
		my ($name, $from, $sentmail, $sig) = $k->role_info($in->{role});	
		$in->{from}	= (is_text($name)) ? "\"$name\" <$from>" : $from;

		my ($message, $attach) = $$k{imap}->message_mime($k, $in, 0);
	
		my $uid = $$k{imap}->message_append($$k{imap_drafts}, 
												$message, '\Draft');

		return($k->_relocate($r, 
			"$$k{rootp}/attachments/$$k{imap_drafts}/$folder/$uid"));
	}

	if (my @errors = $k->compose_checkvals($in)) {
		return(($r->method eq 'POST' ? @errors : ''), $k->compose_form($in));
	} 
	
	# Look up the role information.
	my ($name, $from, $sentmail, $sig) = $k->role_info($in->{role});	
	
	$in->{from}	= is_text($name) ? "\"$name\" <$from>" : $from;
	$in->{sig} 	= $sig; 
	
	# Generate the email content
	my ($message, $attach) = $$k{imap}->message_mime($k, $in); 
	
	# Send the email.
	if (! $$k{imap}->message_send($k, $message)) {
		return('Unable to send message: '. $$k{imap}->error());
	} 
	
	# Figure out if I need to save the sentmail.
	$$k{imap}->message_append($sentmail, $message, '\Seen'); 
	
	if (is_number($uid)) {
		$$k{imap}->message_setflag($folder, $uid, '\Answered');
	} 
	
	unlink(@{$attach}); 
	
	return($k->_relocate($r, "$$k{rootp}/main/$folder"));
} # END $k->do_compose

#-------------------------------------------------
# $k->do_delete($r, $folder $yes)
#-------------------------------------------------
sub do_delete {
	my ($k, $r, $folder, $yes) = @_;

	# confirm then delete all messages in the trash.
	my $in 				= $k->param(Apache2::Request->new($r));
	$folder 			= $$k{imap_trash} if (! is_text($folder));
	$$k{page_title} 	.= "Empty $folder";

	return($k->_relocate($r, $$k{rootp})) if (defined $in->{cancel});

	if ((defined $yes) && ($yes eq 'yes')) {

		# Empty the folder
		my @sorted 	= $$k{imap}->message_sort($folder, $$k{p_sfield}, 
													$$k{p_sorder});

		for my $uid (@sorted) {
			next if (! defined $uid);
			$$k{imap}->message_delete($folder, $uid);
		}

		return($k->_relocate($r, $$k{rootp}));
	}

	return( ht_form_js("$$k{rootp}/delete/$folder/yes"), 
			ht_div({ 'class' => 'box' }),
			ht_table(undef),
			ht_tr(undef,
				ht_td(undef,
					qq!Delete all messages from the "$folder" folder?!)),
			ht_tr(undef,
				ht_td({ 'class' => 'rshd' }, 
					ht_submit('submit', 'Continue with Delete'),
					ht_submit('cancel', 'Cancel'))),
			ht_utable(),
			ht_udiv(),
			ht_uform() );
} # END $k->do_empty_trash

#-------------------------------------------------
# $k->do_main($r, $folder, $field, $order)
#-------------------------------------------------
sub do_main {
	my ($k, $r, $folder, $field, $order, $offset) = @_;

	my @lines;
	my %ln; # Links for the headers.
	my $in 				= $k->param( Apache2::Request->new($r) );
	$folder 			= $$k{imap_inbox} 	if (! is_text($folder));
	$field 				= $$k{p_sfield} 	if (! is_text($field));
	$order 				= $$k{p_sorder} 	if (! is_integer($order));
	$offset 			= 0 				if (! is_integer($offset));
	$$k{page_title} 	.= $k->inbox_mask($folder). ' view';
	my $draft 			= ($folder eq $$k{imap_drafts}) ? 1 : 0;
	my $sentmail		= ($folder eq $$k{imap_sent}) ? 1 : 0;

	# Really, don't try to read the Javascript, it's better that way ;)
	my $clkjs = 	q!onClick="var e, i=0, o=document.fldr; while (e=o[i++]) !.
					q!if (e.type == 'checkbox') e.checked=o.mstr.checked;"!;

	my @folders = ('', 'Move to folder...');
	my %fldrs 	= $$k{imap}->folder_list();

	for my $f (sort	{ ($a eq $$k{imap_inbox}) ? -1 : $a cmp $b } 
						(keys(%fldrs))) {
		
		next if ($f eq $folder);

		push(@folders, $f, $k->inbox_mask($f));
	}
		
	# Do the move
	if ($$in{move} && is_text($$in{folder}) && defined $fldrs{$$in{folder}}) {
		my $count = 0; 
		
		for my $msg (keys(%$in)) {
			next if ($msg !~ /^msg_/);
			(my $muid = $msg) =~ s/^msg_//;
			$count += $$k{imap}->message_move($folder, $muid, $$in{folder});
		}
	
		push(@lines, "$count message(s) moved to $in->{folder}.");
	}

	if ($$in{copy} && is_text($$in{folder}) && defined $fldrs{$$in{folder}}) {
		my $count = 0; 
		
		for my $msg (keys(%$in)) {
			next if ($msg !~ /^msg_/);
			(my $muid = $msg) =~ s/^msg_//;
			$count += $$k{imap}->message_copy($folder, $muid, $$in{folder});
		}
		push(@lines, "$count message(s) copied to $in->{folder}.");
	}

	if ($$in{delete}) { 		# Do the delete.
		my $count = 0;

		# Force delete in the trash bin.
		$$k{p_delete} = 1 if ($folder eq $$k{imap_trash});

		for my $msg (keys(%$in)) {
			next if ($msg !~ /^msg_/);
			(my $muid = $msg) =~ s/^msg_//;
		
			if ($$k{p_delete}) {
				$count += $$k{imap}->message_delete($folder, $muid);
			}
			else {
				$count += $$k{imap}->message_move($folder, $muid, 
														$$k{imap_trash});
			}
		}

		push(@lines, 
			"$count message(s) ". 
			($$k{p_delete} ? 'deleted.' : "moved to $$k{imap_trash}."));
	}

	# Work out the header links.
	for my $fld ('to', 'from', 'subject', 'date', 'size') {
		my $root = "$$k{rootp}/main/$folder";

		if ($field =~ /$fld/i) {
			$ln{$fld} = ($order) ? "$root/$fld/0" : "$root/$fld/1";
		}
		else {
			$ln{$fld} = "$root/$fld/1";
		}
	}

	# Get the message order, and count stuff.
	my $count 	= 0;
	my @sorted 	= $$k{imap}->message_sort($folder, $field, $order);
	my $total 	= scalar(@sorted);
	my $ptotal 	= $$k{p_fcount} + $offset;
	my $mtotal 	= ($ptotal > $total) ? $total: $ptotal;

	push(@lines,  	ht_form_js($$k{uri}, 'name="fldr"'),	
					ht_div({ 'class' => 'box' }),
					ht_table(undef),

					ht_tr(),
						ht_td({	colspan => 3, 'class' => 'hdr' }), 
							($total ? ($offset + 1). " - $mtotal of " : ''),
							"$total messages",
						ht_utd(),
						ht_td({ colspan => 3, 'class' => 'rhdr' }), 
							ht_select('folder', 1, $in, '', '', @folders),
							ht_submit('move', 'Move'),
							ht_submit('copy', 'Copy'),
							ht_submit('delete', 'Delete'),
						ht_utd(),
					ht_utr(),

					ht_tr(),
						ht_td({ 'class' => 'shd' }, 
								ht_checkbox('mstr', 1, 0, $clkjs)),
						ht_td({ 'class' => 'shd' }, ''),  # new 
						ht_td({ 'class' => 'shd' }));

	if ($draft || $sentmail) {
		push(@lines, ht_a($ln{to}, 'To')); 
	}
	else {
		push(@lines, ht_a($ln{from}, 'From')); 
	}

	push(@lines, 	ht_utd(),
					ht_td({ 'class' => 'shd' }, ht_a($ln{subject}, 'Subject')),
					ht_td({ 'class' => 'shd' }, ht_a($ln{date}, 'Date')),
					ht_td({ 'class' => 'shd' }, ht_a($ln{size}, 'Size')),
					ht_utr() );

	for my $uid (@sorted) {
		next if (! defined $uid);

		$count++;

		next if ($count <= $offset);
		last if ($count > ($$k{p_fcount} + $offset));
	
		my ($size, $flags) = $$k{imap}->message_elt($uid);

		# \Answered means it has been replied to.
		my $flag = (defined $$flags{'\Seen'}) ? '' : $$k{new_icon};
		$flag 	.= (defined $$flags{'\Answered'}) ? $$k{reply_icon} : '';

		my %header = $$k{imap}->message_header($uid, 'To', 'From', 
													'Subject', 'Date');

		# FIXME: Maybe everything should understand the new header hash...
		$header{To} = $header{To}[0];
		$header{From} = $header{From}[0];
		$header{Subject} = $header{Subject}[0];
		$header{Date} = $header{Date}[0];

		$header{To} 	= 'Unknown Recipient' 	if ( $header{To} =~ /^\s+$/ );
		$header{To}		= ht_qt($header{To});
		my $temail 		= $header{To};
		$temail 		=~ s/^.*\s<?(\S+@\S*?)>?\s?$/$1/;
		$header{From} 	= 'Unknown Sender' 		if ( $header{From} =~ /^\s+$/ );
		$header{From} 	=~ s/From:.*$//s 		if ( $header{From} =~ /From/ );
		$header{From}	=~ s/\n|\r//g;

		my $email 		= $k->{imap}->decode_iso( $header{From} );
		my $name 		= $email;
		$email 			=~ s/^.*\s<?(\S+@\S*?)>?\s?$/$1/;
		$name 			=~ s/^"?(.*?)"?\s?<?\S+@\S+/$1/;
		$header{From} 	= ( length( $name ) > 1 ) ? $name : $email;
		$header{From}	= ht_qt( $header{From} );
	
		# Clean up the date field.
		$header{Date} 		=~ s/^...\,//; # Strip off the day
		$header{Date}		= UnixDate($header{Date}, $$k{fmt_dt}) || '';
		$header{Subject} 	= 'No Subject' 	if ( ! defined $header{Subject} );
		$header{Subject} 	= 'No Subject' 	if ( $header{Subject} =~ /^\s+$/ );
		$header{Subject} 	= $k->{imap}->decode_iso( $header{Subject} );


		# Subject Too long.
		if ($$k{max_sub} && length($header{Subject}) > $$k{max_sub}) {
			$header{Subject} = substr($header{Subject}, 0, $$k{max_sub});
			$header{Subject} .= '...';
		}

		my $label	= ($sentmail) ? $header{To} : $header{From};
		my $reply	= ($sentmail) ? $temail : $email;
		my $sublink = "$$k{rootp}/view/$folder/$uid/$field/$order/$folder";
 
 		if ($draft) {
			$label 		= $header{To};
			$sublink 	= "$$k{rootp}/response/draft/$folder/$uid";
		}

		push(@lines, ht_tr(undef,
						ht_td({ 'class' => 'shd' },
								ht_checkbox("msg_$uid", 1, $in)),
						ht_td(undef, $flag),
						ht_td(undef,
							ht_a("$$k{rootp}/compose/$folder?to=$reply", 
									$label)),
						ht_td(undef, ht_a($sublink, ht_qt($header{Subject}))),
						ht_td(undef, $header{Date}),
						ht_td(undef, $size)));
	}

	if (! @sorted) {
		push(@lines, ht_tr(undef,
						ht_td({ 'colspan' => 6, 'class' => 'cdta' }, 
								'No messages in this folder')));
	}
	elsif (scalar(@sorted) > $$k{p_fcount}) {

		push(@lines, 	ht_tr(),
						ht_td({ colspan => 6, 'class' => 'rshd' }), '[');

		if ($offset > 0) { # need previous.
			push(@lines, ht_a("$$k{rootp}/main/$folder/$field/$order/". 
								($offset - $$k{p_fcount}), 'Previous'));
		}

		if (($offset > 0) && (($offset + $$k{p_fcount}) < $count)) {
			push(@lines, '|');
		}

		if (($offset + $$k{p_fcount}) < $count) { # need next
			push(@lines, ht_a("$$k{rootp}/main/$folder/$field/$order/".
								($offset + $$k{p_fcount}), 'Next'));
		}

		push(@lines, ']', ht_utd(), ht_utr()); 
	}

	return(@lines, ht_utable(), ht_udiv(), ht_uform());
} # END $k->do_main

#-------------------------------------------------
# $k->do_response( $r, $type, $folder, $uid, $dfolder )
#-------------------------------------------------
sub do_response {
	my ( $k, $r, $type, $folder, $uid ) = @_;

	my $in 				= $k->param( Apache2::Request->new( $r ) );
	$$k{page_title} .= 'Compose message';
	
	return( 'Invalid type.' ) 		if ( ! is_text( $type ) );
	return( 'Invalid folder.' )		if ( ! is_text( $folder ) );
	return( 'Invalid message.' ) 	if ( ! is_integer( $uid ) );

	# $dfolder is the folder to decode the message from.
	my $dfolder = ( $type =~ /^draft$/ ) ? $$k{imap_drafts} : $folder;

	my ( $chk, $mime, $msg ) = $$k{imap}->message_decode( $dfolder, $uid );
	
	return( 'Could not decode message' ) if ( ! $chk );

	my $txt = 'No message text.';

	if ( $$msg{type} =~ /^(text|message)$/ ) {
 		$txt = $$msg{body}->as_string || 'No message text.';
	}

	my $reply_to	= $$msg{head}->get( 'Reply-To' )|| ''; 
	my $to 			= $$msg{head}->get( 'To' ) 		|| 'Unknown Recpient'; 
	my $from 		= $$msg{head}->get( 'From' ) 	|| 'Unknown Sender';
	my $subject		= $$msg{head}->get( 'Subject' ) || 'No Subject';

	if ( $type =~ /reply/i || $type =~ /group/i ) { 	# Reply to single.
		$in->{subject} 	= 'Re: '. $subject;
		$in->{to} 		= ( is_email( $reply_to ) ) ? $reply_to : $from;
		$txt 			=~ s/^/> /mg;
		$in->{to} 		=~ s/\s+$//;
		$in->{message}	= '';
		$in->{message} 	= "> $in->{to} wrote: \n>\n".$txt if ( $$k{p_reply} );

		if ( $type =~ /group/ ) { 						# reply all

			my %cc;

			for my $addr ( 	split( ',',  $$msg{head}->get( 'Cc' ) || '' ),
							split( ',',  $$msg{head}->get( 'To' ) || '' ) ) {
				$addr =~ s/^\s+//;
				$addr =~ s/\s+$//;
				$cc{$addr} = 1;	
			}

			$in->{cc} = join( ', ', keys( %cc ) );
		}
	}
	elsif ( $type =~ /^new$/i ) { 						# New email
		if ( $dfolder =~ /^$$k{imap_drafts}$/ ) {
			$in->{to} = $to;
		}
		else {
			$in->{to} = ( is_email( $reply_to ) ) ? $reply_to : $from;
		}
	}
	elsif ( $type =~ /^draft$/i ) {						# Recover draft

		$in->{role} 	= $k->get_role_id( $$msg{head}->get( 'From' ) );
		$in->{to}		= $$msg{head}->get( 'To' ) || ''; 
		$in->{cc} 		= $$msg{head}->get( 'Cc' ) || ''; 
		$in->{bcc} 		= $$msg{head}->get( 'Bcc' ) || ''; 
		$in->{subject}	= $subject;
		$in->{message}	= $txt;

		my $now = time;

		for my $fkey ( keys %{$$msg{attach}} ) {
	
			my $fname 	= $$msg{attach}{$fkey}{name};
			$fname 		=~ s/--/-/g; # Make it marker safe.
	
			my $ftype 	= $$msg{attach}{$fkey}{type};
			$ftype 		=~ s/\//_/g;
	
			my $file = "$$k{file_path}/$$k{user}--$now--$ftype--$fname";
	
			if ( open( ATTACH, ">$file" ) ) {
					
				my $handle = $$msg{attach}{$fkey}{fh}->open('r');
	
				while ( my $part = $handle->getline ) {
					print ATTACH $part;
				}
	
				$handle->close();
	
				close( ATTACH );
			}
			else {
				die "Could not open $file: $!";
			}
		}
	
		$$k{imap}->message_delete( $dfolder, $uid );
	}
	else { 												# forward
		my $now = time;
		my $show 		= ( is_email( $reply_to ) ) ? $reply_to : $from;
		$in->{subject} 	= 'Fwd: '. $subject;
		$in->{message} 	= 	"--- Forwarded message from $show ---\n\n". 
							$txt. "\n".
							'--- End forwarded message ---';

		for my $fkey ( keys %{$$msg{attach}} ) {

			my $fname 	= $$msg{attach}{$fkey}{name};
			$fname 		=~ s/--/-/g; # Make it marker safe.

			my $ttype 	= $$msg{attach}{$fkey}{type};
			$ttype 		=~ s/\//_/g;

			my $file = "$$k{file_path}/$$k{user}--$now--$ttype--$fname";

			if ( open( ATTACH, ">$file" ) ) {
				next if ( ! defined $$msg{attach}{$fkey}{fh} );
				
				my $handle = $$msg{attach}{$fkey}{fh}->open('r');

				while ( my $part = $handle->getline ) {
					print ATTACH $part;
				}

				$handle->close();

				close( ATTACH );
			}
			else {
				die "Could not open $file: $!";
			}
		}
	}

	$mime->filer->purge; # Removes the files used by the MIME tool.

	# Cheat the compose form to post to the correct place.
	$$k{uri} = "$$k{rootp}/compose/$folder/$uid";

	return($k->compose_form($in));
} # END $k->do_response

#-------------------------------------------------
# $k->do_view($r, $folder, $uid, $field, $order, $header)
#-------------------------------------------------
sub do_view {
	my ($k, $r, $folder, $uid, $field, $order, $header) = @_;

	my $in = $k->param(Apache2::Request->new($r));
	$$k{page_title} .= 'View Message';	

	return('Invalid message.') if (! is_text($folder));
	return('Invalid message.') if (! is_integer($uid));
	return('Invalid message.') if (! is_text($field));
	return('Invalid message.') if (! is_integer($order));

	$header 	= 0 if (! is_integer($header));
	my %fldrs 	= $$k{imap}->folder_list();
	my @sorted 	= $$k{imap}->message_sort($folder, $field, $order);

	my ( $nu, $pu, $tu );

	return('Invalid message.') if (! @sorted);

	while (my $cuid = shift(@sorted)) {
		if ($cuid == $uid)  {
			($pu, $nu) = ($tu, shift(@sorted));
			last;
		}
		$tu = $cuid;
	}

	my ($next, $prev);

	if (! defined $pu) {
		$prev = "$$k{rootp}/main/$folder/$field/$order";
	}
	else {
		$prev = "$$k{rootp}/view/$folder/$pu/$field/$order";
	}

	if (! defined $nu) {
		$next = "$$k{rootp}/main/$folder/$field/$order";
	}
	else {
		$next = "$$k{rootp}/view/$folder/$nu/$field/$order";
	}

	if ($in->{move}) { 			# Do the move
		if (is_text($in->{folder}) && defined $fldrs{$in->{folder}}) {
			$$k{imap}->message_move($folder, $uid, $in->{folder});

			return($k->_relocate($r, $next)); # redirect to the next message.
		}
	}

	if ($in->{copy}) {
		if (is_text($in->{folder}) && defined $fldrs{$in->{folder}}) {
			$$k{imap}->message_copy($folder, $uid, $in->{folder});

			return($k->_relocate($r, $next)); # redirect to the next message.
		}
	}

	if ($in->{delete}) { 		# Do the delete.
		$$k{p_delete} = 1 if ($folder eq $$k{imap_trash});

		if ($$k{p_delete}) {
			$$k{imap}->message_delete($folder, $uid);
		}
		else {
			$$k{imap}->message_move($folder, $uid, $$k{imap_trash});
		}

		return($k->_relocate($r, $next));
	}

	# Will need to work out the next and previous messages.
	# As well as which way we are currently sorted to know.
	my ($chk, $mime, $msg) = $$k{imap}->message_decode($folder, $uid);
	
	return('Could not decode message') if (! $chk);

	# Headers to use.
	my @files;

	my $subject = $k->{imap}->decode_iso($$msg{head}->get( 'Subject' ) || '');
	my $from = $k->{imap}->decode_iso($$msg{head}->get('From') || '');
	my $to = $k->{imap}->decode_iso($$msg{head}->get( 'To' ) || '');
	my $cc = $k->{imap}->decode_iso($$msg{head}->get( 'Cc' ) || '');
	my $date = $$msg{head}->get('Date')	|| '';

	# Figure out the attachment names to list.
	for my $fkey ( sort { $a <=> $b }  keys %{$$msg{attach}} ) {
		my $name = $$msg{attach}{$fkey}{name};

		next if (! defined $name); # Fix this, we are skipping attachments.

		push(@files, ht_a("$$k{rootp}/attached/$folder/$uid/$fkey/$name",
							$name, 'target="_new"'));
	}

	my @folders = ('', 'Move to folder...');
	for my $foldr (sort { ($a eq $$k{imap_inbox}) ? -1 : $a cmp $b } 
					(keys(%fldrs))) {
		next if ($foldr eq $folder);

		push(@folders, $foldr, $k->inbox_mask($foldr));
	}

	my @lines = ( ht_div({ 'class' => 'maction_box' }),
					ht_form($$k{uri}),
					ht_ul(undef,
						ht_li(undef, ht_a( $prev, 'Prev' )),
						ht_li(undef, ht_a( $next, 'Next' )),

						ht_li(undef,
							ht_a("$$k{rootp}/main/$folder/$field/$order", 
								'Folder')),

						ht_li(undef,
							ht_a("$$k{rootp}/response/reply/$folder/$uid",
								'Reply')),

						ht_li(undef,
							ht_a("$$k{rootp}/response/group/$folder/$uid",
								'Reply All')),

						ht_li(undef,
							ht_a("$$k{rootp}/response/fwd/$folder/$uid",
								'Forward')),

						ht_li(undef,
								ht_select('folder', 1, '', '', '', @folders),
								ht_submit('move', 'Move'),
								ht_submit('copy', 'Copy'),
								ht_submit('delete', 'Delete'))),
					ht_uform(),
					ht_udiv(),

					ht_div({ 'class' => 'mhdr_box' }),	
					ht_table(undef), 
				
					ht_tr(undef,
						ht_td({ 'class' => 'shd' }, 'From:'),
						ht_td(undef, $k->address_links($from) )),

					ht_tr(undef,
						ht_td({ 'class' => 'shd' }, 'To:'),
						ht_td(undef, ht_qt($to))) );

	if (is_text($cc)) {
		push(@lines, ht_tr(undef,
							ht_td({ 'class' => 'shd' }, 'Cc:'),
							ht_td(undef,, ht_qt($cc))) );
	}

	push(@lines, 	ht_tr(undef,
						ht_td({ 'class' => 'shd' }, 'Subject:'),
						ht_td(undef, ht_qt($subject))),

					ht_tr(undef,
						ht_td({ 'class' => 'shd' }, 'Date:'),
						ht_td(undef, $date)) );

	if (@files) {
		push( @lines, 	ht_tr(undef,
						ht_td({ 'class' => 'shd' }, 'Attachments:'),
						ht_td(undef, join(ht_br(), @files))) );
	}

	push(@lines, ht_utable(),
					ht_p(),
						( ($header) ?
						ht_a(
						"$$k{rootp}/view/$folder/$uid/$field/$order/0", 
						'View Standard Headers' ) :
						ht_a( "$$k{rootp}/view/$folder/$uid/$field/$order/1",
								'View Full Headers' ) ), 
					ht_up(), 
					ht_udiv() );

	if ($header) { # View full headers.
		my %hdrs = $k->{imap}->message_header($uid, 'ALL');
		my @l;

		for my $h (sort(keys(%hdrs))) {
			push(@l, $h.':', ht_qt(join('', @{$hdrs{$h}})), ht_br());
		}

		push(@lines, ht_div({ 'class' => 'mhall_box' }, @l));
	}

	push(@lines, ht_div({ 'class' => 'mbody_box' }));

	# Get the body of the message presentable.
	if ($$msg{type} =~ /^(text|message)$/) {
 		my $txt = $$msg{body}->as_string || '';

		# Deal with html
		if ($$msg{subtype} !~ /html/) {
			$txt = ht_qt($txt);

			# Clean up the some characters so they appear corretly.
			my $br 	= ht_br();
	  		$txt 	=~ s|\n|$br\n|g;	

			# Do some link magic.
	  		$txt =~ s|(https?://[\[\]:a-z\-0-9/~._,\#=;?&%+]+[a-z\-0-9/_~+])
					 |<a href="$1">$1</a>|gimx;

	  		$txt =~ s|([^/>])(www\.[\[\]:a-z\-0-9/~._,\#=;?&]+\.[a-z\-0-9/_~]+)
					 |$1<a href="http://$2">$2</a>|gimx;

	  		$txt =~ s|<a href="(.+?)&gt">(.+?)&gt</a>;
					 |<a href="$1">$2</a>&gt;|gimx;

	  		$txt =~ s|(ftp://[a-z\-0-9/~._,]+[a-z\-0-9/_~])
					 |<a href="$1">$1</a>|gimx;
		}

		push(@lines, $txt);
	}
	else { # just a binary attachement.
		push(@lines, ht_b('No message text.'));
	}
	
	$mime->filer->purge; # Removes the files used by the MIME tool.
	
	return(@lines, ht_udiv());
} # END $k->do_view

#-------------------------------------------------
# $k->address_links( $from )
#-------------------------------------------------
sub address_links {
	my ( $k, $from ) = @_;

	return( 'Unknown Sender' ) if ( ! is_text( $from ) );

	my @emails;

	$from =~ s/\r\n|\r|\n//g;

	for my $addr ( split ( /\s?,\s?|\s?;\s?/, $from ) ) { 

		my $orig = $addr;
		my $name = $addr;
		# This takes care of the cases ( seperated by , or ; ):
		#  "name name" <email@mail.com>, <name@email.com>, name@email.com
		#  name name@email.com, "last, first" <name@email.com>
		$addr =~ s/>.*$//;
		$addr =~ s/^.*<//;
		$addr =~ s/^.*\s+//;

		next if ( $addr !~ /\S+@\S+/ );

		$name =~ s/$addr//g;
		$name =~ s/(<|>|")//g;

		push( @emails, ht_a( 	"$$k{address_root}/add?first=$name".
								"&amp;email=$addr&amp;balk=yes",
								ht_qt( $orig ) ) );
	}

	return( join( ', ', @emails ) );
} # END $k->address_links

#-------------------------------------------------
# $k->role_info( $role_id )
#-------------------------------------------------
sub role_info {
	my ( $k, $role ) = @_;

	my $sth = db_query( $$k{dbh}, 'get role info',
						'SELECT name, reply_to, savesent, signature ',
						'FROM wm_roles WHERE id = ', sql_num( $role ), 
						'AND wm_user_id = ', sql_num( $$k{user_id} ) );

	my ( $name, $from, $sent, $sig ) = db_next( $sth );

	db_finish( $sth );

	return( $name, $from, $sent, $sig );
} # END $k->role_info

#-------------------------------------------------
# $k->get_role_id( $from )
#-------------------------------------------------
sub get_role_id {
	my ( $k, $from ) = @_;

	$from =~ s/^.*<//s;
	$from =~ s/>.*$//s;

	my $sth = db_query( $$k{dbh}, 'get role info',
						'SELECT id FROM wm_roles WHERE reply_to = ', 
						sql_str( $from ), 'AND wm_user_id = ', 
						sql_num( $$k{user_id} ) );

	my ( $id ) = db_next( $sth );

	db_finish( $sth );

	return( is_number( $id ) ? $id : '' );
} # END $k->get_role_id

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail::Mail - Mail Manipulation.

=head1 SYNOPSIS

  use Alchemy::WebMail::Mail;

=head1 DESCRIPTION

This module is the guts of the WebMail application. It actually views
all of the folders to show a listing, allows compose / reply / forward /
drafts as well as viewing individual messages. 

=head1 APACHE

This is a sample of the location required for this module to run.
Consult Alchemy::WebMail(3) to learn about the configuration options.

  <Location /webmail/mail >
    SetHandler perl-script

    PerlHandler         Alchemy::WebMail::Mail
    PerlAuthenHandler   Alchemy::WebMail::Authentication	

    require valid-user
  </Location>

=head1 DATABASE

This module does not directly manipulate any of the database tables, it
does however draw from some of the database tables.

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
