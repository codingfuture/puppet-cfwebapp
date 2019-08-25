#
# Copyright 2019 (c) Andrey Galkin
#

define cfwebapp::docker::metabase (
    CfWeb::DBAccess $app_dbaccess = { cluster => 'metabase', role => 'metabase' },
    Hash[String[1], CfWeb::DBAccess] $extra_dbaccess = {},

    String[1] $server_name = $title,

    Hash[String[1],Any] $auto_cert = {},
    CfWeb::SharedCert $shared_cert = [],

    Boolean $is_backend = false,
    Boolean $robots_noindex = true,

    Integer[1] $memory_weight = 100,
    Integer[128] $memory_min = 1024,
    Optional[Integer[128]] $memory_max = 2048,

    Hash[String[1], Hash] $fw_ports = {},

    Hash[String[1], Any] $site_params = {},
    CfWeb::DockerImage $image = {
        image => 'metabase/metabase',
        image_tag => 'latest',
    },
    Cfnetwork::Port $target_port = 3000,
) {
    include cfweb::nginx

    $user = "app_${title}"
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    $env_file = "${site_dir}/.metabase.env"
    $extra_env_file = "${site_dir}/.env"

    #---
    $extra_dba = $extra_dbaccess.reduce({}) |$m, $v| {
        $k = $v[0]
        $m + {
            $k => ($v[1] + {
                config_prefix => "DBEXT_${k.upcase()}_",
                use_unix_socket => false,
                local_iface     => 'docker',
                iface           => 'docker',
            })
        }
    }

    # ---
    ensure_resource('cfweb::site', $title, $site_params + {
        server_name        => $server_name,
        auto_cert          => $auto_cert,
        shared_cert        => $shared_cert,
        is_backend         => $is_backend,
        robots_noindex     => $robots_noindex,
        dbaccess           => ($extra_dba + {
            app => $app_dbaccess + {
                config_prefix   => 'DB_',
                use_unix_socket => false,
                local_iface     => 'docker',
                iface           => 'docker',
            },
        }),
        apps               => {
            docker => {
                memory_weight => $memory_weight,
                memory_min    => $memory_min,
                memory_max    => $memory_max,
                fw_ports      => $fw_ports,
            },
        },
        deploy             => {
            target_port   => $target_port,
            image         => $image,
            env_file      => $env_file,
            custom_script => @("EOT"/$)
                #!/bin/bash
                set -e
                source .env

                ENV_FILE=${env_file}

                case "\${DB_TYPE}" in
                postgresql) DB_TYPE=postgres ;;
                esac

                # DB
                #----
                cat >\$ENV_FILE.tmp <<EOF
                MB_DB_TYPE=\${DB_TYPE}
                MB_DB_DBNAME=\${DB_DB}
                MB_DB_HOST=\${DB_HOST}
                MB_DB_PORT=\${DB_PORT}
                MB_DB_USER=\${DB_USER}
                MB_DB_PASS=\${DB_PASS}
                EOF
                mv -f \$ENV_FILE.tmp \$ENV_FILE
                chmod 640 \$ENV_FILE
                | EOT
                ,
            config_files  => [$env_file],
        },
    })

    #---
}
