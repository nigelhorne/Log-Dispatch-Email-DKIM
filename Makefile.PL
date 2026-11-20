use strict;
use warnings;
use ExtUtils::MakeMaker 6.64;	# 6.64 for TEST_REQUIRES

WriteMakefile(
	NAME				=> 'Log::Dispatch::Email::VWFMail',
	AUTHOR				=> q{Nigel Horne <njh@bandsman.co.uk>},
	VERSION_FROM		=> 'lib/Log/Dispatch/Email/VWFMail.pm',
	ABSTRACT_FROM		=> 'lib/Log/Dispatch/Email/VWFMail.pm',
	((defined($ExtUtils::MakeMaker::VERSION) &&
	 ($ExtUtils::MakeMaker::VERSION >= 6.3002))
	  ? ('LICENSE' => 'GPL')
	  : ()),
	PL_FILES			=> {},
	PREREQ_PM => {
		'File::Basename' => 0,
		'File::Spec' => 0,
		'Log::Dispatch' => 0,
		'Web::VWF' => '0.003',
	},
	TEST_REQUIRES => {
		'Test::More' => 0,
	},
	dist				=> { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean				=> { FILES => 'Log-Dispatch-Email-VWFMail-*' },
	META_MERGE => {	# https://perldoc.perl.org/CPAN::Meta::Spec
		'meta-spec' => { version => 2 },
		prereqs => {
			runtime => {
				# Optional: without it Web::VWF::Mail sends unsigned
				recommends => {
					'Mail::DKIM' => 0,
				},
			},
		},
		resources => {
			repository => {
				type => 'git',
				url => 'git://github.com/nigelhorne/Log-Dispatch-Email-VWFMail.git',
				web => 'https://github.com/nigelhorne/Log-Dispatch-Email-VWFMail',
			}, bugtracker => {
				web => 'https://github.com/nigelhorne/Log-Dispatch-Email-VWFMail/issues',
				url => 'https://github.com/nigelhorne/Log-Dispatch-Email-VWFMail/issues',
				mailto => 'bug-Log-Dispatch-Email-VWFMail@rt.cpan.org'
			}
		},
	},
	MIN_PERL_VERSION	=> '5.6.2'	# Probably would work, but never tested on earlier versions than this
);
