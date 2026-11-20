#!perl -w

# The POD is the specification: these tests check the behaviour it documents -
# the key is found rather than configured, the domain comes from From: and the
# selector from the key's file name, each can be overridden through the
# environment, and a missing key warns but still sends.

use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);

BEGIN {
	use_ok('Log::Dispatch::Email::VWFMail');
}

my $fixture = File::Spec->catfile('t', 'dkim', '202611.private');
ok(-r $fixture, "test key $fixture is readable") or BAIL_OUT('no test key');

# A key directory holding a copy of the test key under each given name
sub key_dir {
	my @selectors = @_;
	my $dir = tempdir(CLEANUP => 1);

	foreach my $selector(@selectors) {
		make_path($dir);
		open(my $in, '<', $fixture) or die "Cannot read $fixture: $!";
		my $pem = do { local $/; <$in> };
		close($in);

		my $keyfile = File::Spec->catfile($dir, "$selector.private");
		open(my $out, '>', $keyfile) or die "Cannot write $keyfile: $!";
		print $out $pem;
		close($out) or die "Cannot write $keyfile: $!";
	}

	return $dir;
}

# A sendmail(1) stand-in: what it is given on stdin lands in $ENV{CAPFILE}
sub capture_sendmail {
	my $script = File::Spec->catfile(tempdir(CLEANUP => 1), 'sendmail');

	open(my $fh, '>', $script) or die "Cannot write $script: $!";
	print $fh "#!/bin/sh\nexec cat > \"\$CAPFILE\"\n";
	close($fh) or die "Cannot write $script: $!";
	chmod(0700, $script) or die "Cannot chmod $script: $!";

	return $script;
}

my $sendmail = capture_sendmail();

# Log one message through the appender and return the message that sendmail
# was handed, plus any warnings produced on the way.  An empty string means
# nothing was sent.
sub log_message {
	my ($arguments, $environment, $message) = @_;

	local %ENV = %ENV;
	delete @ENV{qw(VWF_MAIL_DOMAIN VWF_MAIL_SELECTOR VWF_MAIL_KEYFILE VWF_MAIL_KEYDIR VWF_MAIL_SENDMAIL)};
	foreach my $name(keys %{$environment}) {
		$ENV{$name} = $environment->{$name} if(defined($environment->{$name}));
	}

	$ENV{'CAPFILE'} = File::Spec->catfile(tempdir(CLEANUP => 1), 'message');

	my @warnings;
	{
		local $SIG{'__WARN__'} = sub { push(@warnings, @_) };

		my $appender = Log::Dispatch::Email::VWFMail->new(%{$arguments});
		$appender->log(level => 'error', message => $message);
	}

	my $captured = '';
	if(-r $ENV{'CAPFILE'}) {
		open(my $fh, '<', $ENV{'CAPFILE'}) or die "Cannot read $ENV{'CAPFILE'}: $!";
		$captured = do { local $/; <$fh> };
		close($fh);
	}

	return ($captured, \@warnings);
}

my $arguments = {
	'name' => 'VF',
	'min_level' => 'debug',
	'from' => 'webmaster@bandsman.co.uk',
	'to' => ['njh@bandsman.co.uk'],
	'subject' => 'Error in shop/index.fcgi',
};

subtest 'signs with the newest key in ~/dkim by default' => sub {
	my $home = tempdir(CLEANUP => 1);
	my $dkim = File::Spec->catdir($home, 'dkim');
	make_path($dkim);

	# The higher name must win, whichever order they were created in
	foreach my $selector(qw(202701 202611)) {
		open(my $in, '<', $fixture) or die "Cannot read $fixture: $!";
		my $pem = do { local $/; <$in> };
		close($in);

		my $keyfile = File::Spec->catfile($dkim, "$selector.private");
		open(my $out, '>', $keyfile) or die "Cannot write $keyfile: $!";
		print $out $pem;
		close($out) or die "Cannot write $keyfile: $!";
	}

	my ($message, $warnings) = log_message($arguments,
		{ 'HOME' => $home, 'VWF_MAIL_SENDMAIL' => $sendmail },
		"Something went wrong\n");

	ok($message, 'sendmail was given a message');
	like($message, qr/^DKIM-Signature:\s.*\bd=bandsman\.co\.uk;/m, 'signed for the domain in From:');
	like($message, qr/^DKIM-Signature:\s.*\bs=202701;/m, 'selector taken from the highest key file name');
	like($message, qr/^To: njh\@bandsman\.co\.uk\r?$/m, 'To: header');
	like($message, qr/^From: webmaster\@bandsman\.co\.uk\r?$/m, 'From: header');
	like($message, qr/^Subject: Error in shop\/index\.fcgi\r?$/m, 'Subject: header');
	like($message, qr/Something went wrong/, 'body');
	is(scalar(grep { /no DKIM key/ } @{$warnings}), 0, 'no warning when a key was found');
};

subtest 'VWF_MAIL_KEYDIR chooses where to look' => sub {
	my ($message, $warnings) = log_message($arguments,
		{ 'VWF_MAIL_KEYDIR' => key_dir('999'), 'VWF_MAIL_SENDMAIL' => $sendmail },
		"Something went wrong\n");

	like($message, qr/^DKIM-Signature:\s.*\bs=999;/m, 'selector from the key found in VWF_MAIL_KEYDIR');
	is(scalar(grep { /no DKIM key/ } @{$warnings}), 0, 'no warning when a key was found');
};

subtest 'VWF_MAIL_KEYFILE, VWF_MAIL_SELECTOR and VWF_MAIL_DOMAIN override the defaults' => sub {
	my $keyfile = File::Spec->catfile(key_dir('111'), '111.private');

	my ($message) = log_message($arguments,
		{
			'VWF_MAIL_KEYFILE' => $keyfile,
			'VWF_MAIL_SELECTOR' => 'custom',
			'VWF_MAIL_DOMAIN' => 'example.com',
			'VWF_MAIL_SENDMAIL' => $sendmail,
		},
		"Something went wrong\n");

	like($message, qr/^DKIM-Signature:\s.*\bd=example\.com;/m, 'VWF_MAIL_DOMAIN is signed for');
	like($message, qr/^DKIM-Signature:\s.*\bs=custom;/m, 'VWF_MAIL_SELECTOR is used');
};

subtest 'a missing key warns and still sends, unsigned' => sub {
	my $empty = File::Spec->catdir(tempdir(CLEANUP => 1), 'empty');
	make_path($empty);

	my ($message, $warnings) = log_message($arguments,
		{ 'VWF_MAIL_KEYDIR' => $empty, 'VWF_MAIL_SENDMAIL' => $sendmail },
		"Something went wrong\n");

	like((join '', @{$warnings}), qr/no DKIM key for bandsman\.co\.uk; sending unsigned/, 'warns that the message is unsigned');
	ok($message, 'the message is still sent');
	unlike($message, qr/^DKIM-Signature:/m, 'no signature');
	like($message, qr/^To: njh\@bandsman\.co\.uk\r?$/m, 'the message is the one that was logged');
};

subtest 'no recipient means no message' => sub {
	my $stderr = File::Spec->catfile(tempdir(CLEANUP => 1), 'stderr');

	local %ENV = %ENV;
	$ENV{'VWF_MAIL_KEYDIR'} = key_dir('202611');
	$ENV{'VWF_MAIL_SENDMAIL'} = $sendmail;
	$ENV{'CAPFILE'} = File::Spec->catfile(tempdir(CLEANUP => 1), 'message');

	{
		open(my $err, '>', $stderr) or die "Cannot write $stderr: $!";
		local *STDERR;
		open(STDERR, '>&', $err) or die "Cannot reopen STDERR: $!";

		# Log::Dispatch::Email::new insists on a recipient, so the guard in
		# send_email is reached by building the object the way an appender
		# whose to= was never set would look.
		my $appender = bless({ %{$arguments}, 'buffer' => [] }, 'Log::Dispatch::Email::VWFMail');
		delete $appender->{'to'};
		$appender->send_email(message => "Something went wrong\n");
	}

	ok(!-e $ENV{'CAPFILE'}, 'sendmail was not run');
	ok(-r $stderr, 'something was written to stderr');
	if(-r $stderr) {
		open(my $fh, '<', $stderr) or die "Cannot read $stderr: $!";
		my $text = do { local $/; <$fh> };
		close($fh);
		like($text, qr/To whom should I be sending this e-mail\?/, 'says why nothing was sent');
	}
};

done_testing();
