#
# Copyright 2019 (c) Andrey Galkin
#


define cfwebapp::wikijs (
    CfWeb::DBAccess $app_dbaccess,

    String[1] $server_name = $title,

    Hash[String[1],Any] $auto_cert = {},
    CfWeb::SharedCert $shared_cert = [],

    Boolean $is_backend = false,
    Boolean $robots_noindex = true,

    Integer[1] $memory_weight = 100,
    Integer[350] $memory_min = 350,
    Integer[350] $memory_max = 400,

    String[1] $deploy_type = 'vcstag',
    String[1] $deploy_tool = 'git',
    String[1] $deploy_url = 'https://github.com/Requarks/wiki-v1.git',
    String[1] $deploy_match = 'v1*',

    Optional[String[1]] $session_secret = undef,
    Hash $tune = {},

    Hash[String[1], Any] $site_params = {},
    Hash[String[1], Hash] $fw_ports = {},

    Optional[String[1]] $sync_key = undef,
) {
    include cfweb::nginx

    $user = "app_${title}"
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    # Secret
    # ---
    # TODO: shared secret in cluster

    if !$session_secret and $cfweb::is_secondary {
        fail('There must be shared session_secret set in cluster')
    }

    $secret = cfsystem::gen_pass("session:${title}", 32, $session_secret)

    # Actual config
    # ---
    $act_config = ({
        title => 'Sample Wiki',
        uploads => {
            maxImageFileSize => 3,
            maxOtherFileSize => 100,
        },
        lang => en,
        langRtl => false,
        public => !$robots_noindex,
        auth => {
            defaultReadAccess => !$robots_noindex,
            local => {
                enabled => true,
            },
        },
        git => false,
        features => {
            linebreaks => true,
            mathjax => true,
        },
        theme => {
            primary => indigo,
            alt => 'blue-grey',
            viewSource => all,
            footer => 'blue-grey',
            code => {
                dark => true,
                colorize => true,
            },
        }
    } + $tune + {
        host => "https://${server_name}",
        # NOTE: not future-compatible assumption
        port => "${site_dir}/.runtime/app.0.sock",
        paths => {
            repo => "${site_dir}/persistent/repo",
            data => "${site_dir}/persistent/data",
        },
        sessionSecret => $secret,
        db => 'mongodb://DB_USER:DB_PASS@DB_HOST:DB_PORT/DB_DB',
        externalLogging => {},
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
                fw_ports      => $fw_ports,
            },
        },
        deploy             => {
            type          => $deploy_type,
            tool          => $deploy_tool,
            url           => $deploy_url,
            match         => $deploy_match,
            key_name      => $sync_key,
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
                    >\$CONF_DIR/config.yml <<EOF
                ${act_config.to_yaml}
                EOF
                | EOT
                ,
            deploy_set    => [
                'env nodeVer 8',
                [
                    'action prepare',
                    '@default',
                    "'ln -sfn ../.wikijs_conf/config.yml ./config.yml'",
                ].join(' '),
                [
                    'action build',
                    '@default',
                    "'@cid tool exec npm -- run-script build'",
                ].join(' '),
                'entrypoint app node server/index.js \'{"minMemory":"320M","maxInstances":1}\'',
                'webcfg main app',
                'entrypoint web nginx assets socketType=unix',
                'webcfg root assets',
                "webmount / '{\"static\":true}'",
            ],
        }
    })
}
