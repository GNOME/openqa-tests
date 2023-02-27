use base 'app_test';
use strict;
use warnings;
use testapi;
use gnomeutils;

sub run {
    my $homedir = "/home/" . $testapi::username;

    # Import content
    my $content_url = data_url("ASSET_1");
    select_console('user-virtio-terminal');
    assert_script_run("curl --fail --verbose --location " . $content_url . " -o $homedir/content.tar.xz");
    assert_script_run("tar --extract --file $homedir/content.tar.xz --directory $homedir --verbose --quoting-style=shell > /tmp/content-files");

    script_run("echo 'Content files:' && cat /tmp/content-files");
    # Note: the 'Stephen J Sweeney' book fails to index with tracker3, not sure why.
    # Files with special chars are removed due to https://gitlab.gnome.org/GNOME/tracker/-/issues/408
    assert_script_run("cat /tmp/content-files | grep -v 'Stephen J Sweeney' | grep -v \"03 Justin\" | grep -v '(' | grep -v '!' | grep -v \"28 Justin and Tanya\" | xargs realpath --zero | xargs --null /usr/lib/x86_64-linux-gnu/tracker-3.0/trackertestutils/tracker-await-file --timeout 30");
    script_run("tracker3 status | cat");

    select_console('x11');
    start_app('gnome-music');
    assert_screen('app_gnome_music_home', 10);
    close_app;
    close_app;
}

1;
