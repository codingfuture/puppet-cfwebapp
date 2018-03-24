#
# Copyright 2018 (c) Andrey Galkin
#

define cfwebapp::kibana (
    Array[String[1]] $ifaces = ['local'],

    CfWeb::DBAccess $app_dbaccess = { cluster => 'logsink' },

    String[1] $server_name = $title,

    Hash[String[1],Any] $auto_cert = {},
    CfWeb::SharedCert $shared_cert = [],

    Boolean $is_backend = false,
    Boolean $robots_noindex = true,

    Integer[1] $memory_weight = 100,
    Integer[128] $memory_min = 128,
    Optional[Integer[128]] $memory_max = 128,

    Array[String[1]] $plugins = [],
    Hash[String[1], Any] $kibana_tune = {},

    Hash[String[1], Any] $site_params = {},
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
        'logging.json' => false,
    }

    include cfdb::elasticsearch

    # ---
    ensure_resource('package', 'kibana', { ensure => latest })
    ensure_resource('service', 'kibana', {
        ensure  => false,
        enable  => false,
        require => Package['kibana'],
    })

    if empty($plugins) {
        $migrate = []
    } else {
        $migrate = (
            ['action migrate'] +
            $plugins.map |$p| { "'@cid tool exec node -- --no-warnings src/cli_plugin ${p}'" }
        ).join(' ')
    }

    # ---
    $app_tune = {
        scalable   => false,
        socketType => "tcp",
        socketPort => cfsystem::gen_port($user)
    }

    ensure_resource('cfweb::site', $title, $site_params + {
        server_name        => $server_name,
        ifaces             => $ifaces,
        auto_cert          => $auto_cert,
        shared_cert        => $shared_cert,
        is_backend         => $is_backend,
        robots_noindex     => $robots_noindex,
        dbaccess           => {
            app => $app_dbaccess + {
                config_prefix => 'DB_'
            },
        },
        apps               => {
            futoin => {
                memory_weight => $memory_weight,
                memory_min    => $memory_min,
                memory_max    => $memory_max,
            },
        },
        deploy             => {
            type          => 'rms',
            tool          => 'scp',
            url           => $site_dir,
            match         => 'kibana-*.tar',
            custom_script => @("EOT"/$)
                #!/bin/bash
                set -e
                source .env
                umask 027

                CONF_DIR=.runtime
                mkdir -p \$CONF_DIR

                # Create fake RMS package from source
                #---
                ver=$(/usr/bin/dpkg-query -f '\${Version}' -W kibana)
                pkg=kibana-\${ver}.tar
                [ -e \$pkg ] || (\
                    /bin/tar -cJf \${pkg}.tmp -C /usr/share/kibana . && \
                    /bin/mv -f \${pkg}.tmp \${pkg} )

                # Node.js
                #---
                cat >\$CONF_DIR/node_wrapper <<EOF
                #!/bin/dash
                app=\\\$1
                shift
                exec ../current/node/bin/node \\
                    "\\\$@" \\
                    \\\$app \\
                    -c ../.runtime/kibana.yml \\
                    -H \\\$HOST \\
                    -p \\\$PORT
                EOF
                chmod +x \$CONF_DIR/node_wrapper
                
                # DB
                #----
                cat >\$CONF_DIR/kibana.yml.tmp <<EOF
                ${to_yaml($kibana_tune_all)}
                elasticsearch.url: http://\${DB_HOST}:\${DB_PORT}
                EOF
                mv -f \$CONF_DIR/kibana.yml.tmp \$CONF_DIR/kibana.yml
                
                | EOT
                ,
            deploy_set    => [
                'env nodeVer 6',
                "env nodeBin ${site_dir}/.runtime/node_wrapper",
                'env CONFIG_PATH ../.runtime/kibana.yml',
                'persistent data',
                'writable optimize',
                "entrypoint kibana node src/cli \'${to_json($app_tune)}\'",
                'webcfg main kibana',
            ] + $migrate,
        },
        require => Package['kibana'],
    })
}
