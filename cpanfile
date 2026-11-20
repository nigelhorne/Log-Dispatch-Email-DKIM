# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.10.1';

requires 'Carp';
requires 'Email::Address::XS';
requires 'File::Basename';
requires 'File::HomeDir';
requires 'File::Spec';
requires 'Log::Dispatch';
requires 'Params::Get';
requires 'Params::Validate::Strict';
requires 'Readonly';
requires 'Sub::Private', '0.09';
requires 'Sub::Protected';
requires 'Mail::DKIM';
requires 'Web::VWF', '0.003';

on 'test' => sub {
	requires 'File::Temp';
	requires 'Test::More';
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
