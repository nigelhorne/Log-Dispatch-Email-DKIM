#!perl -T

use strict;

use Test::More tests => 2;

BEGIN {
	use_ok('Log::Dispatch::Email::DKIM') || print 'Bail out!';
}

require_ok('Log::Dispatch::Email::DKIM') || print 'Bail out!';

diag("Log::Dispatch::Email::DKIM $Log::Dispatch::Email::DKIM::VERSION, Perl $], $^X");
