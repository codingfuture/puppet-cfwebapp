#
# Copyright 2017-2019 (c) Andrey Galkin
#


define cfwebapp::redmine::redmine_2fa (
    String[1] $target_dir,
    String[1] $plugin_name = 'ignored',
    String[1] $plugin_version = '1.7.0',

    String[1] $source = 'https://github.com/centosadmin/redmine_2fa/archive/v<ver>.zip',
) {
    cfwebapp::redmine::generic { $title:
        target_dir     => $target_dir,
        plugin_name    => 'redmine_2fa',
        plugin_version => $plugin_version,
        source         => $source,
    }
}
