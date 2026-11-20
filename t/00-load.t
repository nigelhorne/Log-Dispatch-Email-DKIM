#!perl -T

use strict;

use Test::More tests => 2;

BEGIN {
	use_ok('Log::Dispatch::Email::VWFMail') || print 'Bail out!';
}

require_ok('Log::Dispatch::Email::VWFMail') || print 'Bail out!';

diag("Log::Dispatch::Email::VWFMail $Log::Dispatch::Email::VWFMail::VERSION, Perl $], $^X");
