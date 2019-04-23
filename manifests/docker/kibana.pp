#
# Copyright 2018-2019 (c) Andrey Galkin
#

define cfwebapp::docker::kibana (
    Array[String[1]] $ifaces = ['local'],

    CfWeb::DBAccess $app_dbaccess = { cluster => 'logsink' },

    String[1] $server_name = $title,

    Hash[String[1],Any] $auto_cert = {},
    CfWeb::SharedCert $shared_cert = [],

    Boolean $is_backend = false,
    Boolean $robots_noindex = true,

    Integer[1] $memory_weight = 100,
    Integer[128] $memory_min = 512,
    Optional[Integer[128]] $memory_max = 512,

    Hash[String[1], Any] $kibana_tune = {},

    Hash[String[1], Any] $site_params = {},
    CfWeb::DockerImage $image = {
        image => 'docker.elastic.co/kibana/kibana-oss',
        image_tag => '6.7.1',
    },
    Cfnetwork::Port $target_port = 5601,
) {
    include cfweb::nginx

    $user = "app_${title}"
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    $kibana_tune_all = {
        'elasticsearch.pingTimeout' => 3000,
        'elasticsearch.preserveHost' => false,
        'elasticsearch.requestHeadersWhitelist' => [],
        'elasticsearch.requestTimeout' => 30000,
        'kibana.defaultAppId' => 'discover',
    } + $kibana_tune + {
        'server.name' => $server_name,
        'server.host' => '0.0.0.0',
        'server.port' => $target_port,
        'logging.json' => false,
    }

    # ---
    ensure_resource('package', 'kibana', { ensure => absent })

    # ---
    $config_file = "${site_dir}/persistent/kibana.yml"

    ensure_resource('cfweb::site', $title, $site_params + {
        server_name        => $server_name,
        ifaces             => $ifaces,
        auto_cert          => $auto_cert,
        shared_cert        => $shared_cert,
        is_backend         => $is_backend,
        robots_noindex     => $robots_noindex,
        dbaccess           => {
            app => $app_dbaccess + {
                config_prefix   => 'DB_',
                use_unix_socket => false,
                local_iface     => 'docker',
            },
        },
        apps               => {
            docker => {
                memory_weight => $memory_weight,
                memory_min    => $memory_min,
                memory_max    => $memory_max,
            },
        },
        deploy             => {
            target_port   => $target_port,
            image         => $image,
            binds         => {
                'kibana.yml' => '/usr/share/kibana/config/kibana.yml',
            },
            custom_script => @("EOT"/$)
                #!/bin/bash
                set -e
                source .env

                CONF_FILE=${config_file}

                # DB
                #----
                cat >\$CONF_FILE.tmp <<EOF
                ${to_yaml($kibana_tune_all)}
                elasticsearch.hosts: http://\${DB_HOST}:\${DB_PORT}
                EOF
                mv -f \$CONF_FILE.tmp \$CONF_FILE
                chmod 644 \$CONF_FILE
                | EOT
                ,
            config_files  => [$config_file],
        },
    })
}
