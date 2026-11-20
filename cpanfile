# Generated from Makefile.PL using makefilepl2cpanfile

requires 'perl', '5.6.2';

requires 'File::Basename';
requires 'File::Spec';
requires 'Log::Dispatch';
requires 'Web::VWF', '0.003';
recommends 'Mail::DKIM';

on 'test' => sub {
	requires 'Test::More';
};

on 'develop' => sub {
	requires 'Devel::Cover';
	requires 'Perl::Critic';
	requires 'Test::Pod';
	requires 'Test::Pod::Coverage';
};
