#
# Copyright 2017 (c) Andrey Galkin
#


define cfwebapp::redmine::redmine_telegram_common (
    String[1] $target_dir,
    String[1] $plugin_name = 'ignored',
    String[1] $plugin_version = '0.1.3',

    String[1] $source = 'https://github.com/centosadmin/redmine_telegram_common/archive/<ver>.zip',
) {
    cfwebapp::redmine::generic { $title:
        target_dir     => $target_dir,
        plugin_name    => 'redmine_telegram_common',
        plugin_version => $plugin_version,
        source         => $source,
    }
}
