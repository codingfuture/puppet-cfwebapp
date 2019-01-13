#
# Copyright 2019 (c) Andrey Galkin
#


define cfwebapp::redmine::redmine_bots (
    String[1] $target_dir,
    String[1] $plugin_name = 'ignored',
    String[1] $plugin_version = '0.2.0',

    String[1] $source = 'https://github.com/centosadmin/redmine_bots/archive/v<ver>.zip',
) {
    cfwebapp::redmine::generic { $title:
        target_dir     => $target_dir,
        plugin_name    => 'redmine_bots',
        plugin_version => $plugin_version,
        source         => $source,
    }
}
