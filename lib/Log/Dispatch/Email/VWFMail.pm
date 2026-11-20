package Log::Dispatch::Email::VWFMail;

use warnings;
use strict;

use base 'Log::Dispatch::Email';

=head1 NAME

Log::Dispatch::Email::VWFMail - Log::Dispatch appender that DKIM-signs its mail

=head1 VERSION

Version 0.01

=cut

our $VERSION = '0.01';

use File::Basename qw(basename);
use File::Spec;

use constant DEFAULT_SENDMAIL => '/usr/sbin/sendmail';

=head1 SYNOPSIS

    log4perl.appender.A2=Log::Dispatch::Email::VWFMail
    log4perl.appender.A2.from=webmaster@bandsman.co.uk
    log4perl.appender.A2.to=njh@bandsman.co.uk
    log4perl.appender.A2.subject=Error in shop/index.fcgi

=head1 DESCRIPTION

Sends a log message the way L<Log::Dispatch::Email::Sendmail> does, but signs
it with L<Web::VWF::Mail> first, so the message carries a C<DKIM-Signature>
for the domain it claims to come from.  An unsigned C<webmaster@> message and
a forgery are indistinguishable in a DMARC report; signing is what tells them
apart, and what lets the copy a mailing list forwards still authenticate.

The signing key is found rather than configured.  C<Log::Dispatch> validates
each appender's arguments and passes on only C<name>, C<min_level>,
C<max_level>, C<callbacks> and C<newline>, so a C<keyfile=> line in the
log4perl configuration never reaches this object.  Instead the domain is taken
from the C<from> address and the selector from the key's file name.

=head1 CONFIGURATION

The defaults suit this host: the key in C<~/dkim/*.private> with the highest
name is used, and its name is the selector.  Each can be overridden in the
environment, which is also how a test points it at a capture script:

=over 4

=item C<VWF_MAIL_DOMAIN> - the signing domain, instead of the one in C<from>

=item C<VWF_MAIL_SELECTOR> - the DKIM selector, instead of the key's file name

=item C<VWF_MAIL_KEYFILE> - the private key to sign with

=item C<VWF_MAIL_KEYDIR> - where to look for C<*.private> (default C<~/dkim>)

=item C<VWF_MAIL_SENDMAIL> - the sendmail to hand the message to

=back

=head1 METHODS

=head2 send_email

Builds the message, signs it and hands it to sendmail(1).  A missing or
unreadable key is not an error: it warns and sends the message unsigned, which
is what C<Web::VWF::Mail> does for a signing problem of any kind.

=cut

sub _signing_key
{
	my $self = shift;

	# The domain is the one the From header claims: signing as anything else
	# would be a signature nobody can align with the message.
	my ($domain) = ($self->{'from'} || '') =~ /\@([^>\s,]+)/;
	$domain = $ENV{'VWF_MAIL_DOMAIN'} if($ENV{'VWF_MAIL_DOMAIN'});

	my $keyfile = $ENV{'VWF_MAIL_KEYFILE'};
	if(!$keyfile) {
		my $dir = $ENV{'VWF_MAIL_KEYDIR'} || File::Spec->catdir(($ENV{'HOME'} || ''), 'dkim');
		my @keys = sort glob(File::Spec->catfile($dir, '*.private'));
		$keyfile = $keys[-1] if(@keys);
	}

	my $selector = $ENV{'VWF_MAIL_SELECTOR'};
	if(!$selector && defined($keyfile) && (basename($keyfile) =~ /\A(.+)\.private\z/)) {
		$selector = $1;
	}

	return ($domain, $selector, $keyfile);
}

sub send_email
{
	my $self = shift;
	my %p = @_;

	unless(defined($self->{'to'})) {
		# Don't warn - it could send a message back through here
		print STDERR "To whom should I be sending this e-mail?\n";
		return;
	}

	my $to = join(',', @{$self->{'to'}});
	my ($domain, $selector, $keyfile) = $self->_signing_key();

	unless(defined($domain) && defined($selector) && defined($keyfile) && -r $keyfile) {
		warn 'VWFMail: no DKIM key for ', ($domain || 'unknown domain'), '; sending unsigned', "\n";
	}

	require Web::VWF::Mail;

	my $mail = Web::VWF::Mail->new(
		'from' => $self->{'from'},
		'domain' => $domain,
		'selector' => $selector,
		'keyfile' => $keyfile,
		'sendmail' => $ENV{'VWF_MAIL_SENDMAIL'} || DEFAULT_SENDMAIL,
	);

	$mail->print("To: $to\n");
	$mail->print("From: $self->{'from'}\n") if($self->{'from'});
	$mail->print("Subject: $self->{'subject'}\n\n", $p{'message'});

	# DreamHost's sendmail writes an IPv6 warning to stderr that breaks the
	# CGI output, so its stderr is discarded while the message is handed over,
	# as Log::Dispatch::Email::Sendmail does.
	my $sent;
	{
		local *STDERR;
		open(STDERR, '>', '/dev/null');
		$sent = $mail->close();
	}

	warn 'VWFMail: sendmail failed for ', ($self->{'from'} || 'unknown sender'), "\n" unless($sent);

	delete $p{'buffer'};
	$self->{'buffer'} = [];

	return;
}

=head1 AUTHOR

Nigel Horne, C<< <njh at bandsman.co.uk> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2026 Nigel Horne.

This program is released under the following licence: GPL

=cut

1; # End of Log-Dispatch-Email-VWFMail
