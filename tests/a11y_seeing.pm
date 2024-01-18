use base 'app_test';
use strict;
use warnings;
use testapi;
use gnomeutils;

sub run {
    start_app('gnome-control-center');
    assert_screen('app_settings_startup', 10);
    
    # ///////// TESTS RELATED TO ACCESSIBILITY ///////////
    
    type_string('acc');
    # Go to accessibility Section
    assert_and_click('a11y_button', timeout => 15, button => 'left');
    # Go to Seeing Section
    assert_and_click('a11y_seeing', timeout => 15, button => 'left');
    # Switch on contrast
    assert_and_click('a11y_contrast', timeout => 15, button => 'left');
    # Switch off contrast
    assert_and_click('a11y_no_contrast', timeout => 15, button => 'left');
    # Switch on Large Text
    assert_and_click('a11y_largetext', timeout => 15, button => 'left');
    # Switch on Large Text
    assert_and_click('a11y_no_largetext', timeout => 15, button => 'left');
    #Go to overlay scrollbars-toggle on
    assert_and_click('a11y_always_show_scrollbar_on', timeout => 15, button => 'left');
    # Go to overlay scrollbars-toggle off
    assert_and_click('a11y_always_show_scrollbar_off', timeout => 15, button => 'left');
       
   close_app;
}

sub test_flags {
    return { fatal => 0 };
}

1;
