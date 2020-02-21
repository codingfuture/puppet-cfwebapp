#
# Copyright 2019-2020 (c) Andrey Galkin
#


define cfwebapp::wikijs2 (
    CfWeb::DBAccess $app_dbaccess,

    String[1] $server_name = $title,

    Hash[String[1],Any] $auto_cert = {},
    CfWeb::SharedCert $shared_cert = [],

    Boolean $is_backend = false,
    Boolean $robots_noindex = true,

    Integer[1] $memory_weight = 100,
    Integer[1024] $memory_min = 1024,
    Integer[1024] $memory_max = 1024,

    String[1] $deploy_type = 'vcstag',
    String[1] $deploy_tool = 'git',
    String[1] $deploy_url = 'https://github.com/Requarks/wiki.git',
    String[1] $deploy_match = '2.1.*',

    Hash $tune = {},

    Hash[String[1], Any] $site_params = {},
    Hash[String[1], Hash] $fw_ports = {},
) {
    include cfweb::nginx

    $user = "app_${title}"
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    # Actual config
    # ---
    $act_config = deep_merge({
        ha       => true,
        offline  => false,
        uploads  => {
            maxFileSize => 1024*1024,
            maxFiles    => 10,
        },
        logLevel => 'info',
    }, $tune, {
        #host => "https://${server_name}",
        # NOTE: not future-compatible assumption
        bindIP   => '127.0.0.1',
        port     => "${site_dir}/.runtime/app.0.sock",
        dataPath => "${site_dir}/persistent/data",
        db       => {
            type => postgres,
            host => 'DB_HOST',
            port => 'DB_PORT',
            user => 'DB_USER',
            pass => 'DB_PASS',
            db   => 'DB_DB',
            ssl  => false,
        },
        pool     => {
            min => 'DB_MAXCONN',
            max => 'DB_MAXCONN',
        },
    })

    # ---
    ensure_resource('cfweb::site', $title, $site_params + {
        server_name        => $server_name,
        auto_cert          => $auto_cert,
        shared_cert        => $shared_cert,
        is_backend         => $is_backend,
        robots_noindex     => $robots_noindex,
        dbaccess           => {
            app => $app_dbaccess,
        },
        apps               => {
            futoin => {
                memory_weight => $memory_weight,
                memory_min    => $memory_min,
                memory_max    => $memory_max,
                fw_ports      => $fw_ports + { cfhttp => {} },
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
                source .env
                umask 027

                CONF_DIR=.wikijs_conf
                mkdir -p \$CONF_DIR

                sed \
                    -e "s,DB_HOST,\${DB_APP_HOST}," \
                    -e "s,DB_PORT,\${DB_APP_PORT}," \
                    -e "s,DB_DB,\${DB_APP_DB}," \
                    -e "s,DB_USER,\${DB_APP_USER}," \
                    -e "s,DB_PASS,\${DB_APP_PASS}," \
                    -e "s,DB_MAXCONN,\${DB_APP_MAXCONN}," \
                    >\$CONF_DIR/config.yml <<EOF
                ${act_config.to_yaml}
                EOF
                | EOT
                ,
            deploy_set    => [
                'env nodeVer 10',
                [
                    'action prepare',
                    '@default',
                    "'ln -sfn ../.wikijs_conf/config.yml ./config.yml'",
                ].join(' '),
                [
                    'action build',
                    "'sed -i /..dev...true/d package.json'",
                    "'@cte webpack --profile --config dev/webpack/webpack.prod.js'",
                ].join(' '),
                "entrypoint app node server/index.js '{\"minMemory\":\"768M\",\"maxInstances\":1}'",
                'webcfg main app',
                #'entrypoint web nginx assets socketType=unix',
                #'webcfg root assets',
                #"webmount / '{\"static\":true}'",
                'persistent logs data',
            ],
        }
    })
}
