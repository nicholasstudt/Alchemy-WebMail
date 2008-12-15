package Alchemy::WebMail::Authentication;

use strict;

use Apache2::Const -compile => qw(:common);
use Apache2::Access;
use Apache2::Connection;
use Apache2::Log;
use Apache2::RequestIO;
use Apache2::RequestRec;
use Apache2::RequestUtil;
use Apache2::ServerUtil;

use KrKit::AppBase;
use KrKit::Validate;

######################################################################
# Main Execution Begins Here                                         #
######################################################################
sub handler : method {
	my ( $self, $r ) = @_;

	return( Apache2::Const::DECLINED ) unless $r->is_initial_req;

	my $cname 		= $r->dir_config( 'WM_CookieName' )	|| 'WebMail';
	my $login_page 	= $r->dir_config( 'WM_LoginRoot' ) 	|| '/';
	my $cookies 	= appbase_cookie_retrieve( $r );
	my $uri 		= $r->uri;
	$uri 			=~ s/\//:/g;

	if ( ! is_text( $$cookies{$cname} )  ) {
		
		$r->note_basic_auth_failure; 
    	$r->log_error(  '[client ', $r->connection->remote_ip,
						'] user not found: ', $r->uri );

		$r->headers_out->set( 'Location' => "$login_page/main/$uri" );

		$r->status( Apache2::Const::REDIRECT ); 

		return( Apache2::Const::REDIRECT );
	}

	# check login would be the else case of the first if.
	if ( $$cookies{$cname} =~ /^loggedout$/ ) {
		
		$r->headers_out->set( 'Location' => "$login_page/main/$uri" );
	
		$r->status( Apache2::Const::REDIRECT ); 

		return( Apache2::Const::REDIRECT );
	}

	return( Apache2::Const::OK ); 
} # END handler 

# EOF
1;

__END__

=head1 NAME 

Alchemy::WebMail::Authentication - WebMail's Authentication handler.

=head1 SYNOPSIS

  use Alchemy::WebMail::Authentication;

=head1 DESCRIPTION

This is the Authentication for Webmail. It ensures that the user has the
cookie set by the login page but it does not check this cookie. The
cookie's password is checked on the first log in. If this cookie is
tampered with the access to the imap server will fail. On a related note
the cookie is encrypted using an encryption scheme of your choice so
tampering with the cookie in an effective way is fairly hard.

=head1 APACHE

This module is configured via PerlAccessHandler and should not be set to
a location by itself. Consult Alchemy::Webmail(3) to learn about the
configuration options.

=head1 DATABASE

This module does not contact any database in any way. 

=head1 SEE ALSO

Alchemy::WebMail(3), Alchemy(3), KrKit(3)

=head1 LIMITATIONS

This module has it's own handler, seperate from the inherited handler
used by the other modules.

=head1 AUTHOR

Nicholas Studt <nicholas@photodwarf.org>

=head1 COPYRIGHT

Copyright (c) 2003-2008 Nicholas Studt. All rights reserved.

You may distribute under the terms of either the GNU General Public
License or the Artistic License, as specified in the Perl README file.

=cut
