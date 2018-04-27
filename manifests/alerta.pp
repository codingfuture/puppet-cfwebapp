#
# Copyright 2018 (c) Andrey Galkin
#

define cfwebapp::alerta (
    Array[String[1]] $ifaces = ['local'],

    CfWeb::DBAccess $app_dbaccess = {
        cluster => 'cfmonitor',
        role    => 'alerta',
    },

    String[1] $server_name = $title,

    Hash[String[1],Any] $auto_cert = {},
    CfWeb::SharedCert $shared_cert = [],

    Boolean $is_backend = false,
    Boolean $robots_noindex = true,

    Integer[1] $memory_weight = 100,
    Integer[192] $memory_min = 192,
    Optional[Integer[192]] $memory_max = undef,

    String[1] $deploy_type = 'vcstag',
    String[1] $deploy_tool = 'git',
    String[1] $deploy_url = 'https://github.com/alerta/alerta.git',
    String[1] $deploy_match = 'v5*',

    CfWeb::SMTP $smtp = {},
    Optional[String[1]] $api_secret = undef,

    Array[String[1]] $admin_users = ["admin@${::facts['domain']}"],
    Array[String[1]] $email_domains = [$::facts['domain']],
    Array[String[1]] $cors_origins = [$server_name],
    Array[String[1]] $plugins = [],
    Hash[String[1], Any] $tune = {},

    Hash[String[1], Any] $site_params = {},
) {
    include cfweb::nginx

    $user = "app_${title}"
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    # ---
    if !$api_secret and $cfweb::is_secondary {
        fail('There must be shared api_secret set in cluster')
    }

    $secret_key = cfsystem::gen_pass("api:${title}", 32, $api_secret)

    # ---
    $api_tune_all = {
        'DEFAULT_PAGE_SIZE' => 1000,
        'HISTORY_LIMIT' => 100,
        'API_KEY_EXPIRE_DAYS' => 3650,

        'AUTH_REQUIRED' => true,
        'CUSTOMER_VIEWS' => false,

        'EMAIL_VERIFICATION' => true,
        'SMTP_USE_SSL' => false,
        'MAIL_LOCALHOST' => $::facts['fqdn'],
        'GITLAB_URL' => undef,
    } + $tune + {
        'BASE_URL' => "https://${server_name}",
        'CORS_ORIGINS' => $cors_origins,
        'LOGGER_NAME' => 'alerta',

        'ADMIN_USERS' => $admin_users,
        'ALLOWED_EMAIL_DOMAINS' => $email_domains,
        'SECRET_KEY' => $secret_key,

        'PLUGINS' => $plugins,

        'SMTP_HOST' => pick($smtp['host'], 'localhost'),
        'SMTP_PORT' => Integer.new(pick($smtp['port'], 25)),
        'SMTP_STARTTLS' => Boolean.new(pick_default($smtp['start_tls'], true)),
        'SMTP_USERNAME' => pick_default($smtp['user'], ''),
        'SMTP_PASSWORD' => pick_default($smtp['password'], ''),
        'MAIL_FROM' => pick_default($smtp['from'], ''),
    }

    $api_cfg = ($api_tune_all.map |$k, $v| {
        if $v =~ Boolean {
            $vb = $v ? {
                true    => 'True',
                default => 'False'
            }
            "${k} = ${vb}"
        } elsif $v =~ Integer {
            "${k} = ${v}"
        } elsif $v =~ Undef {
            "${k} = None"
        } elsif $v =~ Array {
            $vl = $v.map | $iv | {
                $ivs = regsubst($iv,"'", "\\'", 'G')
                "'${ivs}'"
            }
            "${k} = [${vl.join(',')}]"
        } else {
            $vs = regsubst($v,"'", "\\'", 'G')
            "${k} = '${vs}'"
        }
    }).join("\n")

    # ---
    $uwsgi_tune = {
        uwsgi => {
            callable => 'app',
            env      => "ALERTA_SVR_CONF_FILE=${site_dir}/.alertad.conf",
            harakiri => 120,
        }
    }

    # ---
    $smtp_port = $api_tune_all['SMTP_PORT']

    ensure_resource('cfnetwork::describe_service', "smtp_${smtp_port}", {
        server => "tcp/${smtp_port}",
    })
    cfnetwork::client_port { "any:smtp_${smtp_port}:${user}":
        user => $user,
    }

    # ---
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
            type          => $deploy_type,
            tool          => $deploy_tool,
            url           => $deploy_url,
            match         => $deploy_match,
            custom_script => @("EOT"/$)
                #!/bin/bash
                set -e
                source .env
                umask 027

                # API config
                cat >.alertad.conf <<EOF
                ${api_cfg}

                DATABASE_URL = '\$DB_CONNINFO'
                DATABASE_NAME = '\$DB_DB'
                EOF

                | EOT
                ,
            deploy_set    => [
                "action prepare '@default'",
                'tools uwsgi pip python=3',
                "tooltune uwsgi '${uwsgi_tune.to_json()}'",
                'entrypoint api uwsgi alerta/app.wsgi internal=1 minMemory=64M connMemory=128M',
                'webcfg main api',
            ],
        },
    })
}
