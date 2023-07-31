use base 'app_test';
use strict;
use warnings;
use testapi;
use gnomeutils;

sub run {
    start_app('snapshot');
    assert_and_click('app_snapshot_camera_permission', timeout => 10, button => 'left');
    assert_screen('app_snapshot_home', 10);
    close_app;
}

1;
