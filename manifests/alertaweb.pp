#
# Copyright 2018 (c) Andrey Galkin
#

define cfwebapp::alertaweb (
    Array[String[1]] $ifaces = ['main'],

    String[1] $server_name = $title,

    Hash[String[1],Any] $auto_cert = {},
    CfWeb::SharedCert $shared_cert = [],

    Boolean $is_backend = false,
    Boolean $robots_noindex = true,

    String[1] $deploy_type = 'vcstag',
    String[1] $deploy_tool = 'git',
    String[1] $deploy_url = 'https://github.com/alerta/angular-alerta-webui.git',
    String[1] $deploy_match = 'v5*',

    String[1] $api_endpoint = 'http://localhost.localdomain',

    Hash[String[1], Any] $tune = {},

    Hash[String[1], Any] $site_params = {},
) {
    include cfweb::nginx

    $user = "app_${title}"
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    # ---
    $web_tune_all = {
        'provider' => 'basic',
    } + $tune + {
        'endpoint' => $api_endpoint,
    }

    # ---
    ensure_resource('cfweb::site', $title, $site_params + {
        server_name        => $server_name,
        ifaces             => $ifaces,
        auto_cert          => $auto_cert,
        shared_cert        => $shared_cert,
        is_backend         => $is_backend,
        robots_noindex     => $robots_noindex,
        apps               => {
            futoin => {
                memory_min => 0,
                memory_max => 0,
            },
        },
        deploy             => {
            type          => $deploy_type,
            tool          => $deploy_tool,
            url           => $deploy_url,
            match         => $deploy_match,
            custom_script => @("EOT"/$)
                #!/bin/bash
                set -e
                umask 027

                CONF_DIR=.runtime
                mkdir -p \$CONF_DIR

                # Web UI config
                cat >\$CONF_DIR/web_config.js <<EOF
                'use strict';
                angular.module('config', [])
                    .constant('config', ${web_tune_all.to_json()});
                EOF

                | EOT
                ,
            deploy_set    => [
                [
                    'action prepare',
                    "'cp -f ../.runtime/web_config.js app/config.js'",
                ].join(' '),
                'tools nginx',
                "webmount / '{\"static\":true}'",
            ],
        },
    })

}
