use strict;
use warnings;
use ExtUtils::MakeMaker 6.64;	# 6.64 for TEST_REQUIRES

WriteMakefile(
	NAME			=> 'Log::Dispatch::Email::VWFMail',
	AUTHOR			=> q{Nigel Horne <njh@bandsman.co.uk>},
	VERSION_FROM	=> 'lib/Log/Dispatch/Email/VWFMail.pm',
	ABSTRACT_FROM	=> 'lib/Log/Dispatch/Email/VWFMail.pm',
	LICENSE			=> 'gpl_2',	# the bundled LICENSE is GPL version 2
	PREREQ_PM => {
		'Carp' => 0,
		'Email::Address::XS' => 0,
		'File::Basename' => 0,
		'File::HomeDir' => 0,
		'File::Spec' => 0,
		'Log::Dispatch' => 0,
		'Params::Get' => 0,
		'Params::Validate::Strict' => 0,
		'Readonly' => 0,
		'Sub::Private' => '0.09',	# 0.09 for the enforce mode
		'Sub::Protected' => 0,
		# Web::VWF only recommends Mail::DKIM, because a site with no key must
		# still send its contact form, but this appender exists to sign: without
		# it every message goes out unsigned
		'Mail::DKIM' => 0,
		'Web::VWF' => '0.003',
	},
	TEST_REQUIRES => {
		'Test::More' => 0,
		'File::Temp' => 0,
	},
	clean => { FILES => 'Log-Dispatch-Email-VWFMail-*' },
	META_MERGE => {	# https://perldoc.perl.org/CPAN::Meta::Spec
		'meta-spec' => { version => 2 },
		resources => {
			repository => {
				type => 'git',
				url => 'https://github.com/nigelhorne/Log-Dispatch-Email-VWFMail.git',
				web => 'https://github.com/nigelhorne/Log-Dispatch-Email-VWFMail',
			}, bugtracker => {
				web => 'https://github.com/nigelhorne/Log-Dispatch-Email-VWFMail/issues',
				url => 'https://github.com/nigelhorne/Log-Dispatch-Email-VWFMail/issues',
				mailto => 'bug-Log-Dispatch-Email-VWFMail@rt.cpan.org'
			}
		},
	},
	MIN_PERL_VERSION	=> '5.10.1'	# CI covers 5.36 and later; the attributes and // used here need 5.10
);
