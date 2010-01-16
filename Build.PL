use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'Alchemy::WebMail',
    license             => 'perl',
    dist_author         => 'Nicholas Studt <nicholas@photodwarf.org>',
    dist_version_from   => 'lib/Alchemy/WebMail.pm',
    requires			=> {
							'KrKit' 			=> '>= 0.22',
							'Apache2::Request'	=> 0,
							'Date::Manip'		=> 0,
							'Crypt::CBC' 		=> 0,
							'Mail::IMAPClient'	=> '>= 3.21',
							'MIME::Entity'		=> 0,
							'MIME::Parser'		=> 0,
							'Net::SMTP'			=> 0,
						},
	recommends			=> {
							'Crypt::Blowfish'	=> 0,
						},
    add_to_cleanup      => [ 'Alchemy-WebMail', '_build', 'Build' ],
);

$builder->create_build_script();

