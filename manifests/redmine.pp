#
# Copyright 2017 (c) Andrey Galkin
#


define cfwebapp::redmine (
    Hash[String[1],Variant[String,Integer]] $app_dbaccess,
    CfWeb::SMTP $smtp = {},

    String[1] $server_name = $title,
    Array[String[1]] $alt_names = [],
    Boolean $redirect_alt_names = true,

    Array[String[1]] $ifaces = ['main'],
    Array[Cfnetwork::Port] $plain_ports = [80],
    Array[Cfnetwork::Port] $tls_ports = [443],
    Boolean $redirect_plain = true,

    Boolean $is_backend = false,

    Hash[String[1],Hash] $auto_cert = {},
    Array[String[1]] $shared_certs = [],

    Optional[String[1]] $custom_conf = undef,

    Integer[1] $memory_weight = 100,
    Optional[Integer[1]] $memory_max = undef,
    Cfsystem::CpuWeight $cpu_weight = 100,
    Cfsystem::IoWeight $io_weight = 100,

    Hash[String[1], Struct[{
        type       => Enum['conn', 'req'],
        var        => String[1],
        count      => Optional[Integer[1]],
        entry_size => Optional[Integer[1]],
        rate       => Optional[String[1]],
        burst      => Optional[Integer[0]],
        nodelay    => Optional[Boolean],
        newname    => Optional[String[1]],
    }]] $limits = {},

    String[1] $deploy_type = 'vcstag',
    String[1] $deploy_tool = 'svn',
    String[1] $deploy_url = 'http://svn.redmine.org/redmine',
    String[1] $deploy_match = '3.4.*',
    String[1] $ruby_ver = '2.3',
    Optional[String[1]] $rake_secret = undef,
) {
    # ---
    # TODO: shared secret in cluster

    if !$rake_secret and $cfweb::is_secondary {
        fail('There must be shared rake_secret set in cluster')
    }

    $secret = cfsystem::gen_pass("rake:${title}", 32, $rake_secret)

    # ---
    $user = "app_${title}"
    $smtp_host = pick_default($smtp.dig('host'), 'localhost')
    $smtp_port = pick_default($smtp.dig('port'), 25)
    ensure_resource('cfnetwork::describe_service', "smtp_${smtp_port}", {
        server => "tcp/${smtp_port}",
    })
    cfnetwork::client_port { "any:smtp_${smtp_port}:${user}":
        dst  => $smtp_host,
        user => $user,
    }

    # ---
    cfweb::site { $title:
        server_name        => $server_name,
        alt_names          => $alt_names,
        redirect_alt_names => $redirect_alt_names,
        ifaces             => $ifaces,
        plain_ports        => $plain_ports,
        tls_ports          => $tls_ports,
        redirect_plain     => $redirect_plain,
        is_backend         => $is_backend,
        auto_cert          => $auto_cert,
        shared_certs       => $shared_certs,
        dbaccess           => {
            app => $app_dbaccess,
        },
        apps               => {
            futoin => {
                memory_weight => $memory_weight,
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
                
                # DB
                #----
                case \${DB_APP_TYPE} in
                    mysql)
                        adapter=mysql2
                        ;;
                    *)
                        adapter=\${DB_APP_TYPE}
                        ;;
                esac

                cat >.database.yml.tmp <<EOF
                ---
                production:
                    adapter: \$adapter
                    database: \${DB_APP_DB}
                    host: \${DB_APP_HOST}
                    port: \${DB_APP_PORT}
                    username: \${DB_APP_USER}
                    password: \${DB_APP_PASS}
                    encoding: utf8
                    socket: \${DB_APP_SOCKET}
                    connect_timeout: 3
                EOF
                mv -f .database.yml.tmp .database.yml
                
                # Secret
                #----
                cat >.secrets.yml.tmp <<EOF
                ---
                production:
                    secret_key_base: ${secret}
                    secret_token: ${secret}
                EOF
                mv -f .secrets.yml.tmp .secrets.yml
                
                # Main config
                #----
                c_from=${pick_default($smtp.dig('from'), '')}
                if [ -n "\$c_from" ]; then l_from="from: \$c_from"; fi
                    
                c_reply_to=${pick_default($smtp.dig('reply_to'), '')}
                if [ -n "\$c_reply_to" ]; then l_reply_to="reply_to: \$c_reply_to"; fi

                c_user=${pick_default($smtp.dig('user'), '')}
                if [ -n "\$c_user" ]; then
                    l_user="user_name: \$c_user"
                    l_pass="password: ${pick_default($smtp.dig('password'), '')}"
                    l_auth="authentication: ${pick_default($smtp.dig('auth_mode'), 'plain')}"
                fi
                
                which_ignore() {
                    which ${1} || true
                }

                cat >.configuration.yml.tmp <<EOF
                ---
                production:
                    email_delivery:
                        delivery_method: :smtp
                        raise_delivery_errors: false
                        default_options:
                            \$l_from
                            \$l_reply_to
                        smtp_settings:
                            address: ${smtp_host}
                            port: ${smtp_port}
                            enable_starttls_auto: ${pick_default($smtp.dig('start_tls'), false)}
                            \$l_auth
                            \$l_user
                            \$l_pass
                
                default:
                    attachments_storage_path:
                    autologin_cookie_name:
                    autologin_cookie_path:
                    autologin_cookie_secure:
                    
                    scm_subversion_command: \$(which_ignore svn)
                    scm_mercurial_command: \$(which_ignore hg)
                    scm_git_command: \$(which_ignore git)
                    scm_cvs_command:
                    scm_bazaar_command:
                    scm_darcs_command:
                    
                    scm_stderr_log_file:
                    
                    database_cipher_key:
                    
                    rmagick_font_path:
                EOF
                mv -f .configuration.yml.tmp .configuration.yml
                | EOT
                ,
            deploy_set    => [
                "env rubyVer ${ruby_ver}",
                'action prepare app-config database-config app-install',
                [
                    'action app-config',
                    "'ln -sfn ../../.configuration.yml config/configuration.yml'",
                    "'rm -f config/initializers/secret_token.rb'",
                    "'ln -sfn ../../.secrets.yml config/secrets.yml'",
                    "'rm -rf tmp && ln -s ../.tmp tmp'",
                ].join(' '),
                [
                    'action database-config',
                    "'ln -s ../../.database.yml config/database.yml'",
                ].join(' '),
                [
                    'action app-install',
                    "'@cid build-dep ruby mysql-client imagemagick tzdata libxml2'",
                    "'@cid tool exec bundler -- install --without \"development test rmagick\"'",
                ].join(' '),
                [
                    'action migrate',
                    "'@cid tool exec bundler -- exec rake db:migrate RAILS_ENV=production'",
                    "'@cid tool exec bundler -- exec rake redmine:load_default_data RAILS_ENV=production REDMINE_LANG=en'",
                ].join(' '),
                'persistent files log public/plugin_assets',
                'entrypoint web nginx public socketType=unix',
                'entrypoint app puma config.ru internal=1',
                'webcfg root public',
                'webcfg main app',
                "webmount / '{\"static\":true}'",
            ]
        }
    }
}
