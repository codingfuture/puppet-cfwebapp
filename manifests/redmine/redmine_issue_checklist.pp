#
# Copyright 2017-2019 (c) Andrey Galkin
#


define cfwebapp::redmine::redmine_issue_checklist (
    String[1] $target_dir,
    String[1] $plugin_name = 'ignored',
    String[1] $plugin_version = '2.1.0',

    String[1] $source = 'https://github.com/Restream/redmine_issue_checklist/archive/<ver>.zip',
) {
    cfwebapp::redmine::generic { $title:
        target_dir     => $target_dir,
        plugin_name    => 'redmine_issue_checklist',
        plugin_version => $plugin_version,
        source         => $source,
    }
}
