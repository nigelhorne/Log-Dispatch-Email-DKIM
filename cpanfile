# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.6.2';

requires 'Log::Dispatch';
requires 'Mail::DKIM';
requires 'Web::VWF', '0.003';

on 'test' => sub {
	requires 'Test::More';
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
