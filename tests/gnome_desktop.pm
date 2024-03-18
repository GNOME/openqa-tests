use base 'basetest';
use strict;
use testapi;

sub run {
    my $self = shift;
		select_console('debug-shell');
		assert_script_run('ls');
		select_console('x11');

    assert_and_click('gnome_desktop_tour', timeout => 60, button => 'left');
    assert_screen('gnome_desktop_desktop', 60);
}

sub test_flags {
    return { fatal => 1 };
}

1;
