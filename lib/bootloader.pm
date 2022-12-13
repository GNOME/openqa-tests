package bootloader;

use base Exporter;
use Exporter;

use strict;
use warnings;

use testapi;

our @EXPORT = qw(
    bootloader_enable_journald_to_serial
);

sub bootloader_enable_journald_to_serial {
    assert_screen('gnome_iso_bootloader', timeout => 30);

    wait_screen_change { send_key('e') };

    send_key('end');
    type_string(' console=ttyS0');
    type_string(' systemd.journald.forward_to_console=1');

    save_screenshot;

    send_key('ret');
}
