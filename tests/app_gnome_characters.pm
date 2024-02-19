use base 'app_test';
use strict;
use warnings;
use testapi;
use gnomeutils;

my $form_factor_postfix = $testapi::form_factor_postfix;

sub run {
    start_app('gnome-characters');
    if ($form_factor_postfix == '_mobile') {
        resize_app_to_mobile;
    }
    assert_screen('app_gnome_characters_home'.$form_factor_postfix, 10);
    close_app;
}

1;
