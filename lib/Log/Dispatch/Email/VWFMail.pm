package Log::Dispatch::Email::VWFMail;

use strict;
use warnings;
use autodie qw(:all);

use base 'Log::Dispatch::Email';

use Carp qw(carp croak);
use Email::Address::XS;
use File::Basename qw(basename);
use File::HomeDir;
use File::Spec;
use Params::Get qw(get_params);
use Params::Validate::Strict qw(validate_strict);
use Readonly;

# Private helpers are really private (a call from outside this package croaks,
# which also works for $self->_helper() dispatch); the one protected method,
# i18n(), may be called by a subclass that wants to reword the messages.
use Sub::Private { 'mode' => 'enforce' };
use Sub::Protected;

=encoding utf8

=head1 NAME

Log::Dispatch::Email::VWFMail - Log::Dispatch appender that DKIM-signs its mail

=head1 VERSION

Version 0.001.0

=cut

use version; our $VERSION = version->declare('0.001.0');

# Everything that was once a literal in the code lives here, so that it is
# named once and can be changed (or, for the messages, translated) in one place.
Readonly my $DEFAULT_SENDMAIL => '/usr/sbin/sendmail';
Readonly my $KEY_FILE_SUFFIX => '.private';
Readonly my $KEY_DIR_NAME => 'dkim';
Readonly my $KEY_FILE_RE => qr/\A(.+)\Q$KEY_FILE_SUFFIX\E\z/;
Readonly my $LINE_BREAKS_RE => qr/[\r\n]+/;

# The environment variable that overrides each setting
Readonly my %ENV_VAR => (
	'domain' => 'VWF_MAIL_DOMAIN',
	'selector' => 'VWF_MAIL_SELECTOR',
	'keyfile' => 'VWF_MAIL_KEYFILE',
	'keydir' => 'VWF_MAIL_KEYDIR',
	'sendmail' => 'VWF_MAIL_SENDMAIL',
);

# Input schema for send_email().  Log::Dispatch hands over more than the
# message (level, name and so on) when the appender is unbuffered, so unknown
# parameters are ignored rather than rejected.
Readonly my $SEND_EMAIL_SCHEMA => {
	'message' => { 'type' => 'string', 'min' => 0 },
};

# The message catalogue.  An entry is [ $sprintf_format, @names_of_arguments ],
# or a hash of such entries for the variants of a message: 'one' and 'other'
# are chosen by the 'count' argument, and any other key by the 'gender'
# argument (see i18n()).  It is a package variable, not a Readonly, so that a
# site can translate it with local() or by assigning to a key.
our %MESSAGES = (
	'no_recipient' => ['To whom should I be sending this e-mail?'],
	'no_sender' => ['VWFMail: no valid From address to send as; message not sent'],
	'no_key' => ['VWFMail: no DKIM key for %s; sending unsigned', 'domain'],
	'unknown_domain' => ['unknown domain'],
	'send_failed' => ['VWFMail: sendmail failed for %s', 'sender'],
	'no_message' => ['message is required'],
	'bad_arguments' => ['VWFMail: invalid arguments to %s: %s', 'routine', 'reason'],
);

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
environment, which is also how a test points it at a capture script.  An
empty variable counts as unset.

=over 4

=item C<VWF_MAIL_DOMAIN> - the signing domain, instead of the one in C<from>

=item C<VWF_MAIL_SELECTOR> - the DKIM selector, instead of the key's file name

=item C<VWF_MAIL_KEYFILE> - the private key to sign with

=item C<VWF_MAIL_KEYDIR> - where to look for C<*.private> (default C<~/dkim>)

=item C<VWF_MAIL_SENDMAIL> - the sendmail to hand the message to

=back

The home directory comes from L<File::HomeDir>, so it is found even when the
process (a CGI script, say) has no C<HOME> in its environment.

=head1 METHODS

=head2 send_email

=head3 Purpose

Builds the message, signs it and hands it to sendmail(1).  Log::Dispatch
calls this itself, once per message when unbuffered and once per flush when
buffered, so applications do not normally call it.

=head3 Args

A hash or hash reference with C<message>, the text of the message body.  Any
other key (C<level>, C<name>, ...) is ignored.

=head3 Returns

C<$self>, so calls can be chained.  The outcome of the delivery is reported
by warning, not by the return value, because Log::Dispatch ignores it.

=head3 Side Effects

Runs sendmail(1).  While it runs, STDERR is pointed at the null device
because DreamHost's sendmail writes an IPv6 warning there that would corrupt
CGI output.

A missing or unreadable key is not an error: it warns and sends the message
unsigned, which is what C<Web::VWF::Mail> does for a signing problem of any
kind.  A line break in the subject, From or To is replaced by a space, so a
logged value cannot add a header of its own.

When there is no recipient, or the C<from> address cannot be parsed, nothing
is sent and the problem is written straight to STDERR, not warned: a warning
could be routed back into this appender and loop.  C<from> may carry a
display name (C<"Web Master" E<lt>webmaster@example.comE<gt>>); the bare
address is used as the sendmail envelope sender and as the signing domain.

=head3 Usage

    $appender->send_email(message => "Something went wrong\n");

=head3 EXAMPLE

    use Log::Dispatch;

    my $log = Log::Dispatch->new(
        outputs => [ [
            'Email::VWFMail',
            'min_level' => 'error',
            'from' => 'webmaster@bandsman.co.uk',
            'to' => ['njh@bandsman.co.uk'],
            'subject' => 'Error in shop/index.fcgi',
        ] ],
    );

    # Sent, signed with the highest ~/dkim/*.private, when $log goes away
    $log->error("Something went wrong\n");

    # Test a different key and a capture script instead of sendmail
    local $ENV{'VWF_MAIL_KEYFILE'} = '/tmp/keys/202611.private';
    local $ENV{'VWF_MAIL_SENDMAIL'} = '/tmp/capture';

=head3 API SPECIFICATION

=head4 INPUT

    {
        message => { type => 'string', min => 0 },
    }

Unknown keys are ignored.

=head4 OUTPUT

    { type => 'object', isa => 'Log::Dispatch::Email::VWFMail' }

=head3 MESSAGES

=over 4

=item C<VWFMail: no DKIM key for DOMAIN; sending unsigned> (warning)

No readable key, domain or selector could be found.  The message is sent
without a signature.  Put a C<SELECTOR.private> key in C<~/dkim>, or set
C<VWF_MAIL_KEYFILE> or C<VWF_MAIL_KEYDIR>.

=item C<VWFMail: sendmail failed for SENDER> (warning)

sendmail(1) could not be run or exited with a failure.  Check
C<VWF_MAIL_SENDMAIL> and the mail queue.

=item C<To whom should I be sending this e-mail?> (STDERR)

The appender has no recipient, so nothing was sent.  Give it a C<to>.

=item C<VWFMail: no valid From address to send as; message not sent> (STDERR)

C<from> is missing or is not an address.  Give it a C<from> such as
C<webmaster@example.com>.

=item C<VWFMail: invalid arguments to send_email: REASON> (fatal)

The arguments were not a message.  Pass C<< message => $text >>; REASON is the validator's complaint, or
C<message is required>.

=back

=head3 FORMAL SPECIFICATION

    ┌─ SendEmail ──────────────────────────────────────────────
    │ Ξ Config
    │ message? : STRING
    │ sent!    : 𝔹
    │ signed!  : 𝔹
    ├──────────────────────────────────────────────────────────
    │ sent!   = (to ≠ ∅ ∧ sender ∈ ADDRESS ∧ sendmail succeeds)
    │ signed! = (sent! ∧ domain ≠ ⊥ ∧ selector ≠ ⊥ ∧ readable(keyfile))
    │ ¬ signed! ⇒ a warning is raised (sent! is unaffected)
    └──────────────────────────────────────────────────────────

=head3 PSEUDOCODE

    validate the arguments (croak if there is no message)
    parse From into an address (undef if it is not one)
    if there is no recipient or no address
        write the reason to STDERR and stop
    find domain, selector and keyfile (environment, then From, then ~/dkim)
    warn if any is missing or the keyfile is unreadable
    build the message with a sanitised To, From and Subject
    run sendmail with STDERR on the null device
    warn if it failed
    return self

=cut

sub send_email
{
	my $self = shift;

	my $args = $self->_validated_arguments('send_email', \@_);
	my $sender = $self->_parse_address($self->{'from'});

	# Neither case can be reported with carp: it could come back here
	if(!defined($self->{'to'})) {
		$self->_say_to_stderr('no_recipient');
	} elsif(!$sender) {
		$self->_say_to_stderr('no_sender');
	} else {
		$self->_deliver($sender, $args->{'message'});
	}

	return $self;
}

=head2 i18n

=head3 Purpose

Turns a message key into text for the user, so that every warning and error
this class raises can be translated or reworded by a subclass or by assigning
to C<%Log::Dispatch::Email::VWFMail::MESSAGES>.  Protected: callable from
this class and its subclasses only.

=head3 Args

The message key, then an optional hash reference of arguments.  C<count>
selects the C<one> or C<other> variant of a message, and C<gender> selects the
variant of that name, with C<other> as the fallback.

=head3 Returns

The message text.  An unknown key returns the key itself, so a missing
translation is visible rather than fatal.

=head3 Side Effects

None.

=head3 Usage

    my $text = $self->i18n('no_key', { 'domain' => 'example.com' });

=head3 EXAMPLE

    # A catalogue entry is [ $sprintf_format, @argument_names ], or a hash
    # of variants of one
    local $Log::Dispatch::Email::VWFMail::MESSAGES{'files'} = {
        'one' => ['%s file', 'count'],
        'other' => ['%s files', 'count'],
    };
    $self->i18n('files', { 'count' => 2 });	# "2 files"

=head3 API SPECIFICATION

=head4 INPUT

    {
        key => { type => 'string', min => 1 },
        args => { type => 'hashref', optional => 1 },
    }

=head4 OUTPUT

    { type => 'string' }

=head3 MESSAGES

None of its own.  An unknown key is returned as the text.

=head3 FORMAL SPECIFICATION

    ┌─ I18n ───────────────────────────────────────────────────
    │ catalogue : KEY ⇸ (ENTRY ∪ (VARIANT ⇸ ENTRY))
    │ key? : KEY
    │ args? : NAME ⇸ VALUE
    │ text! : STRING
    ├──────────────────────────────────────────────────────────
    │ key? ∉ dom catalogue ⇒ text! = key?
    │ key? ∈ dom catalogue ⇒
    │     text! = sprintf(format(entry), args?(names(entry)))
    └──────────────────────────────────────────────────────────

=head3 PSEUDOCODE

    look the key up; if absent, return the key
    if the entry is a hash of variants, choose one by gender, then count
    format the entry with its named arguments

=cut

sub i18n :Protected
{
	my ($self, $key, $args) = @_;

	my $entry = $MESSAGES{$key};
	if(defined($entry)) {
		$entry = $self->_choose_variant($entry, $args || {});
		my ($format, @names) = @{$entry};
		$entry = sprintf($format, map { $args->{$_} // q{} } @names);
	} else {
		$entry = $key;
	}

	return $entry;
}

# Purpose: pick the wording for a message that has variants.
# Entry: $entry is an array reference (returned as it is) or a hash reference
#	of variants; $args is a hash reference.
# Exit: an array reference [ $format, @names ].  The variant named by
#	$args->{gender} wins, then 'one' when $args->{count} is 1, then 'other'.
# Side effects: none.
sub _choose_variant :Private
{
	my ($self, $entry, $args) = @_;

	if(ref($entry) eq 'HASH') {
		my @wanted = grep { defined } (
			$args->{'gender'},
			(defined($args->{'count'}) && $args->{'count'} == 1) ? 'one' : undef,
			'other',
		);
		my ($found) = grep { exists $entry->{$_} } @wanted;
		$entry = $entry->{$found};
	}

	return $entry;
}

# Purpose: raise a warning in the user's words.
# Entry: $key and $args as for i18n().
# Exit: $self, for chaining.
# Side effects: a carp(), reported from the caller's point of view.
sub _warn_user :Private
{
	my ($self, $key, $args) = @_;

	carp($self->i18n($key, $args));

	return $self;
}

# Purpose: report a problem that must not go through the warn() machinery.
# Entry: $key and $args as for i18n().
# Exit: $self, for chaining.
# Side effects: a line on STDERR.  Not a warning, because a warn handler may
#	log it, which would send it back through this appender.
sub _say_to_stderr :Private
{
	my ($self, $key, $args) = @_;

	print STDERR $self->i18n($key, $args), "\n";

	return $self;
}

# Purpose: normalise and check the arguments of a public routine.
# Entry: $routine is its name (for the message); $arguments is an array
#	reference to its @_, in any form Params::Get understands.
# Exit: a hash reference of the validated arguments.  Croaks, in the user's
#	words, if they do not match $SEND_EMAIL_SCHEMA.
# Side effects: none.
sub _validated_arguments :Private
{
	my ($self, $routine, $arguments) = @_;

	my $validated = eval {
		validate_strict(
			'schema' => $SEND_EMAIL_SCHEMA,
			'input' => get_params(undef, $arguments),
			'unknown_parameter_handler' => 'ignore',
		);
	};

	# validate_strict() lets an undef through a required parameter, by design,
	# so a missing message is checked for as well
	my $reason = $@ || (defined($validated->{'message'}) ? q{} : $self->i18n('no_message'));
	croak($self->i18n('bad_arguments', { 'routine' => $routine, 'reason' => $reason })) if(length($reason));

	return $validated;
}

# Purpose: read an address into its parts.
# Entry: $text is a From-style address, with or without a display name.
# Exit: an Email::Address::XS object, or undef if $text holds no valid
#	address.  Email::Address::XS, not a regex, because a display name may
#	itself contain an '@'.
# Side effects: none.
sub _parse_address :Private
{
	my ($self, $text) = @_;

	# Warnings are silenced here (Email::Address::XS carps about junk), for the
	# same reason _say_to_stderr() avoids warn(): one could loop back to us
	local $SIG{'__WARN__'} = sub { };
	my ($address) = (defined($text) && length($text)) ? Email::Address::XS->parse($text) : ();

	return ($address && $address->is_valid()) ? $address : undef;
}

# Purpose: make a value safe to use as the text of one header line.
# Entry: $value is a string.
# Exit: the string with each run of line breaks replaced by one space, so it
#	cannot end its own header and begin another (header injection).
# Side effects: none.
sub _one_line :Private
{
	my ($self, $value) = @_;

	$value =~ s/$LINE_BREAKS_RE/ /g;

	return $value;
}

# Purpose: read an override from the environment.
# Entry: $setting is a key of %ENV_VAR.
# Exit: the variable's value, or undef if it is unset or empty.
# Side effects: none.
sub _from_environment :Private
{
	my ($self, $setting) = @_;

	my $value = $ENV{$ENV_VAR{$setting}};

	return (defined($value) && length($value)) ? $value : undef;
}

# Purpose: find the private key to sign with.
# Entry: none; consults VWF_MAIL_KEYFILE, VWF_MAIL_KEYDIR and the home
#	directory.
# Exit: the path of VWF_MAIL_KEYFILE, or else of the highest-named
#	*.private in the key directory, or undef if there is none.
# Side effects: reads a directory.  A directory listing is used instead of
#	glob() because glob() splits on spaces and expands '[' and '*'.
sub _find_key_file :Private
{
	my $self = shift;

	my $keyfile = $self->_from_environment('keyfile');
	return $keyfile if(defined($keyfile));

	my $dir = $self->_from_environment('keydir');
	if(!defined($dir)) {
		my $home = File::HomeDir->my_home();
		$dir = File::Spec->catdir($home, $KEY_DIR_NAME) if(defined($home));
	}

	if(defined($dir) && -d $dir) {
		opendir(my $handle, $dir);
		my @names = sort grep { /\Q$KEY_FILE_SUFFIX\E\z/ } readdir($handle);
		closedir($handle);
		$keyfile = File::Spec->catfile($dir, $names[-1]) if(@names);
	}

	return $keyfile;
}

# Purpose: work out how to sign this message.
# Entry: $sender is the Email::Address::XS of the From address.
# Exit: a hash reference { domain, selector, keyfile }; any may be undef.
#	The domain is the one From: claims, because a signature for any other
#	domain would not align with the message; the selector is the key's file
#	name.  The environment overrides each.
# Side effects: reads a directory (see _find_key_file).
sub _signing_key :Private
{
	my ($self, $sender) = @_;

	my $keyfile = $self->_find_key_file();
	my $selector = $self->_from_environment('selector');

	if(!defined($selector) && defined($keyfile) && basename($keyfile) =~ $KEY_FILE_RE) {
		$selector = $1;
	}

	return {
		'domain' => $self->_from_environment('domain') // $sender->host(),
		'selector' => $selector,
		'keyfile' => $keyfile,
	};
}

# Purpose: run a piece of code with STDERR discarded.
# Entry: $code is a code reference.
# Exit: whatever $code returns (in scalar context).
# Side effects: DreamHost's sendmail writes an IPv6 warning to STDERR that
#	breaks CGI output, so STDERR is the null device while $code runs and is
#	restored after, as Log::Dispatch::Email::Sendmail does.  If the null
#	device cannot be opened $code runs anyway: a noisy message beats a lost one.
sub _without_stderr :Private
{
	my ($self, $code) = @_;

	my $result;
	{
		local *STDERR;
		eval { open(STDERR, '>', File::Spec->devnull()); 1 };
		$result = $code->();
	}

	return $result;
}

# Purpose: sign and send one message.
# Entry: $sender is an Email::Address::XS; $message is the body text;
#	$self->{to} is a non-empty array reference.
# Exit: $self, for chaining.
# Side effects: runs sendmail(1); warns if the message is unsigned or the
#	send failed.
sub _deliver :Private
{
	my ($self, $sender, $message) = @_;

	my $key = $self->_signing_key($sender);

	# Unsigned mail is still sent, but whoever reads the log should hear of it
	if(!(defined($key->{'domain'}) && defined($key->{'selector'}) && defined($key->{'keyfile'}) && -r $key->{'keyfile'})) {
		$self->_warn_user('no_key', { 'domain' => $key->{'domain'} // $self->i18n('unknown_domain') });
	}

	require Web::VWF::Mail;

	my $mail = Web::VWF::Mail->new(
		# The envelope sender is the bare address: a display name would be
		# refused as an invalid sendmail -f argument
		'from' => $sender->address(),
		%{$key},
		'sendmail' => $self->_from_environment('sendmail') // $DEFAULT_SENDMAIL,
	);

	my $headers = join("\n",
		'To: ' . $self->_one_line(join(',', @{$self->{'to'}})),
		'From: ' . $self->_one_line($self->{'from'}),
		'Subject: ' . $self->_one_line($self->{'subject'}),
	);
	$mail->print($headers, "\n\n", $message);

	my $sent = $self->_without_stderr(sub { $mail->close() });
	$self->_warn_user('send_failed', { 'sender' => $sender->address() }) unless($sent);

	return $self;
}

=head1 LIMITATIONS

=over 4

=item *

The message catalogue is a package variable and C<i18n> is protected, because
C<Log::Dispatch> constructs the appender and does not pass on extra
arguments, so there is no object configuration to carry a locale.
L<Object::Configure> is therefore not used: there is nowhere for it to hook
in.  A site changes the wording by assigning to
C<%Log::Dispatch::Email::VWFMail::MESSAGES>, which is global to the process.

=item *

The key is found by convention (C<~/dkim/*.private>, highest name wins) and
the environment, not configured per appender, for the same reason.  Two
appenders in one process cannot sign with different keys.

=item *

The key with the highest I<name> is used, not the newest or the one that
matches the published DNS record.  Leave a retired key in the directory and,
if it sorts last, it is the one that signs.

=item *

The message goes out only once: if sendmail(1) fails the message is lost, not
queued for retry, and the only record is the warning.

=item *

A C<from> with no valid address, or a missing recipient, loses the message.
This used to be a fatal error from L<Web::VWF::Mail>, which a logger should
not raise.

=item *

Redirecting STDERR is process-wide for the duration of the send, so output
written by another thread meanwhile is lost.

=item *

The plural and gender support in C<i18n> selects a variant by key; it does
not know the plural rules of any language beyond one against other.  Use
L<Locale::Maketext> if you need more.

=back

=head1 AUTHOR

Nigel Horne, C<< <njh at bandsman.co.uk> >>

=head1 LICENSE AND COPYRIGHT

Copyright 2026 Nigel Horne.

This program is released under the following licence: GPL

=cut

1; # End of Log-Dispatch-Email-VWFMail
