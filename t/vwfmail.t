#!perl -w

# The POD is the specification: the key is found rather than configured, the
# domain comes from From: and the selector from the key's file name, each can
# be overridden through the environment, and a missing key warns but still
# sends.

use strict;
use warnings;
use Test::More;
use File::Path qw(make_path);
use File::Spec;
use File::Temp qw(tempdir);

BEGIN {
	use_ok('Log::Dispatch::Email::VWFMail');
}

# Mail::DKIM is a prerequisite, but say so plainly: without it Web::VWF::Mail
# falls back to sending unsigned and the signature tests below fail obscurely
ok(eval { require Mail::DKIM; 1 }, 'Mail::DKIM, which does the signing, is installed');

my $fixture = File::Spec->catfile('t', 'dkim', '202611.private');
ok(-r $fixture, "test key $fixture is readable") or BAIL_OUT('no test key');

my $pem = do {
	open(my $fh, '<', $fixture) or die "Cannot read $fixture: $!";
	local $/;
	<$fh>;
};

# Put the test key in $dir under each selector name
sub keys_in {
	my ($dir, @selectors) = @_;
	make_path($dir);

	foreach my $selector(@selectors) {
		my $keyfile = File::Spec->catfile($dir, "$selector.private");
		open(my $fh, '>', $keyfile) or die "Cannot write $keyfile: $!";
		print $fh $pem;
		close($fh) or die "Cannot write $keyfile: $!";
	}

	return $dir;
}

# A sendmail(1) stand-in, so nothing leaves the machine: what it is handed on
# stdin lands in $ENV{CAPFILE}
my $sendmail = File::Spec->catfile(tempdir(CLEANUP => 1), 'sendmail');
{
	open(my $fh, '>', $sendmail) or die "Cannot write $sendmail: $!";
	print $fh "#!/bin/sh\nexec cat > \"\$CAPFILE\"\n";
	close($fh) or die "Cannot write $sendmail: $!";
	chmod(0700, $sendmail) or die "Cannot chmod $sendmail: $!";
}

my $settings = {
	'name' => 'VF',
	'min_level' => 'debug',
	'from' => 'webmaster@bandsman.co.uk',
	'to' => ['njh@bandsman.co.uk'],
	'subject' => 'Error in shop/index.fcgi',
};

# The POD describes the environment as the way to point a test at a capture
# script, so leave nothing of the caller's behind to decide what is signed
delete @ENV{qw(VWF_MAIL_DOMAIN VWF_MAIL_SELECTOR VWF_MAIL_KEYFILE VWF_MAIL_KEYDIR)};
$ENV{'VWF_MAIL_SENDMAIL'} = $sendmail;

# Log one message and return what sendmail was handed, empty if nothing was
# sent, together with the warnings raised on the way
sub log_message {
	my ($message, $environment) = @_;

	local @ENV{keys %{$environment}} = values %{$environment};

	my $capfile = File::Spec->catfile(tempdir(CLEANUP => 1), 'message');
	$ENV{'CAPFILE'} = $capfile;

	my @warnings;
	{
		local $SIG{'__WARN__'} = sub { push(@warnings, @_) };

		my $log = Log::Dispatch::Email::VWFMail->new(%{$settings});
		$log->log(level => 'error', message => $message);
	}

	return ('', \@warnings) unless(-r $capfile);

	open(my $fh, '<', $capfile) or die "Cannot read $capfile: $!";
	my $sent = do { local $/; <$fh> };
	close($fh);

	return ($sent, \@warnings);
}

subtest 'signs with the highest key in ~/dkim' => sub {
	my $home = tempdir(CLEANUP => 1);

	# The 202701 key is written first, so only the file name can explain
	# the selector that comes back
	keys_in(File::Spec->catdir($home, 'dkim'), qw(202701 202611));

	my ($sent, $warnings) = log_message("Something went wrong\n", { 'HOME' => $home });

	ok($sent, 'sendmail was given a message');
	like($sent, qr/^DKIM-Signature:\s.*\bd=bandsman\.co\.uk;/m, 'signed for the domain in From:');
	like($sent, qr/^DKIM-Signature:\s.*\bs=202701;/m, 'selector taken from the highest key file name');
	like($sent, qr/^To: njh\@bandsman\.co\.uk\r?$/m, 'To: header');
	like($sent, qr/^From: webmaster\@bandsman\.co\.uk\r?$/m, 'From: header');
	like($sent, qr/^Subject: Error in shop\/index\.fcgi\r?$/m, 'Subject: header');
	like($sent, qr/Something went wrong/, 'body');
	is(scalar(grep { /no DKIM key/ } @{$warnings}), 0, 'no warning when a key is found');
};

subtest 'VWF_MAIL_KEYDIR chooses where to look' => sub {
	my ($sent, $warnings) = log_message("Something went wrong\n",
		{ 'VWF_MAIL_KEYDIR' => keys_in(tempdir(CLEANUP => 1), '999') });

	like($sent, qr/^DKIM-Signature:\s.*\bs=999;/m, 'selector from the key in VWF_MAIL_KEYDIR');
	is(scalar(grep { /no DKIM key/ } @{$warnings}), 0, 'no warning when a key is found');
};

subtest 'VWF_MAIL_KEYFILE, VWF_MAIL_SELECTOR and VWF_MAIL_DOMAIN override the defaults' => sub {
	my ($sent) = log_message("Something went wrong\n",
		{
			'VWF_MAIL_KEYFILE' => File::Spec->catfile(keys_in(tempdir(CLEANUP => 1), '111'), '111.private'),
			'VWF_MAIL_SELECTOR' => 'custom',
			'VWF_MAIL_DOMAIN' => 'example.com',
		});

	like($sent, qr/^DKIM-Signature:\s.*\bd=example\.com;/m, 'VWF_MAIL_DOMAIN is signed for');
	like($sent, qr/^DKIM-Signature:\s.*\bs=custom;/m, 'VWF_MAIL_SELECTOR is used');
};

subtest 'a missing key warns and still sends, unsigned' => sub {
	my $empty = File::Spec->catdir(tempdir(CLEANUP => 1), 'empty');
	make_path($empty);

	my ($sent, $warnings) = log_message("Something went wrong\n", { 'VWF_MAIL_KEYDIR' => $empty });

	like((join '', @{$warnings}), qr/no DKIM key for bandsman\.co\.uk; sending unsigned/, 'warns that the message is unsigned');
	ok($sent, 'the message is still sent');
	unlike($sent, qr/^DKIM-Signature:/m, 'no signature');
	like($sent, qr/^To: njh\@bandsman\.co\.uk\r?$/m, 'the message is the one that was logged');
};

done_testing();
