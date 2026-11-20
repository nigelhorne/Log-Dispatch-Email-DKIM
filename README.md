## Name

Log::Dispatch::Email::VWFMail - Log::Dispatch appender that DKIM-signs its mail

## Version

Version 0.01

## Synopsis

```
log4perl.appender.A2=Log::Dispatch::Email::VWFMail
log4perl.appender.A2.from=webmaster@bandsman.co.uk
log4perl.appender.A2.to=njh@bandsman.co.uk
log4perl.appender.A2.subject=Error in shop/index.fcgi
```

## Description

Sends a log message the way [Log::Dispatch::Email::Sendmail](https://metacpan.org/pod/Log%3A%3ADispatch%3A%3AEmail%3A%3ASendmail) does, but signs
it with [Web::VWF::Mail](https://metacpan.org/pod/Web%3A%3AVWF%3A%3AMail) first, so the message carries a `DKIM-Signature`
for the domain it claims to come from.  An unsigned `webmaster@` message and
a forgery are indistinguishable in a DMARC report; signing is what tells them
apart, and what lets the copy a mailing list forwards still authenticate.

The signing key is found rather than configured.  `Log::Dispatch` validates
each appender's arguments and passes on only `name`, `min_level`,
`max_level`, `callbacks` and `newline`, so a `keyfile=` line in the
log4perl configuration never reaches this object.  Instead the domain is taken
from the `from` address and the selector from the key's file name.

## Configuration

The defaults suit this host: the key in `~/dkim/*.private` with the highest
name is used, and its name is the selector.  Each can be overridden in the
environment, which is also how a test points it at a capture script:

- `VWF_MAIL_DOMAIN` - the signing domain, instead of the one in `from`
- `VWF_MAIL_SELECTOR` - the DKIM selector, instead of the key's file name
- `VWF_MAIL_KEYFILE` - the private key to sign with
- `VWF_MAIL_KEYDIR` - where to look for `*.private` (default `~/dkim`)
- `VWF_MAIL_SENDMAIL` - the sendmail to hand the message to

## Methods

### Send\_Email

Builds the message, signs it and hands it to sendmail(1).  A missing or
unreadable key is not an error: it warns and sends the message unsigned, which
is what `Web::VWF::Mail` does for a signing problem of any kind.

## Author

Nigel Horne, `<njh at bandsman.co.uk>`

## License and Copyright

Copyright 2026 Nigel Horne.

This program is released under the following licence: GPL
