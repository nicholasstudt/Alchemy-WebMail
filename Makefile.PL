use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'			=> 'Alchemy::WebMail',
    'VERSION_FROM'	=> 'lib/Alchemy/WebMail.pm', # finds $VERSION
	'INSTALLSCRIPT'	=> '/usr/local/bin',
    'PREREQ_PM'		=> 	{
							'KrKit' 			=> 0.14,
							'Apache2::Request'	=> 0,
							'Date::Manip'		=> 0,
							'Crypt::CBC' 		=> 0,
							'Mail::Cclient'		=> 1.8,
							'MIME::Entity'		=> 0,
							'MIME::Parser'		=> 0,
						},
	'EXE_FILES'		=> 	[
							'bin/webmail_purgeuser.pl',
						],
);
