#
# Copyright 2017 (c) Andrey Galkin
#


define cfwebapp::redmine::generic(
    String[1] $target_dir,
    String[1] $plugin_name,
    String[1] $plugin_version,
    String[1] $source,
) {
    $source_act = ($source
        .regsubst('<ver>', $plugin_version, 'IG')
        .regsubst('<name>', $plugin_name, 'IG'))
    $dst = "${target_dir}/${plugin_name}-${plugin_version}.zip"

    if $source_act =~ /^https?:/ {
        wget::fetch { $title:
            source      => $source_act,
            destination => $dst,
        }
        -> file { $dst:
            mode    => '0644',
            replace => no,
            content => '',
        }
    } else {
        file { $dst:
            source => $source_act,
            mode   => '0644',
        }
    }
}
