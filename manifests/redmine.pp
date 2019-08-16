#
# Copyright 2017-2019 (c) Andrey Galkin
#


define cfwebapp::redmine (
    CfWeb::DBAccess $app_dbaccess,
    CfWeb::SMTP $smtp = {},
    Optional[CfWeb::IMAP] $imap = undef,

    String[1] $server_name = $title,

    Hash[String[1],Any] $auto_cert = {},
    CfWeb::SharedCert $shared_cert = [],

    Boolean $is_backend = false,
    Boolean $robots_noindex = true,

    Integer[1] $memory_weight = 100,
    Integer[256] $memory_min = 404,
    Optional[Integer[404]] $memory_max = undef,

    String[1] $deploy_type = 'vcstag',
    String[1] $deploy_tool = 'svn',
    String[1] $deploy_url = 'https://svn.redmine.org/redmine',
    String[1] $deploy_match = '4.*',
    String[1] $ruby_ver = '2.6',
    Optional[String[1]] $rake_secret = undef,

    Hash[String[1], Hash] $fw_ports = {},

    Hash[String[1], Hash] $plugins = {
        #'redmine_bots' => {
        #    'impl' => 'cfwebapp::redmine::redmine_bots',
        #},
        #'redmine_2fa' => {
        #    'impl' => 'cfwebapp::redmine::redmine_2fa',
        #},
        #'redmine_issue_checklist' => {
        #    'impl' => 'cfwebapp::redmine::redmine_issue_checklist',
        #},
    },

    Hash[String[1], Any] $site_params = {},
) {
    require cfwebapp::redmine::gandi
    include cfweb::nginx

    $user = "app_${title}"
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    # Where to put plugins for installation
    # ---
    $plugins_zip_dir  = "${site_dir}/.redmine_plugins"

    file { $plugins_zip_dir:
        ensure  => directory,
        purge   => true,
        force   => true,
        recurse => true,
        owner   => $user,
        group   => $user,
        mode    => '0700',
    }
    file { "${site_dir}/.unpack-plugins.sh":
        owner   => $user,
        group   => $user,
        mode    => '0700',
        content => @(EOT)
        #!/bin/bash
        
        for p in $(find ../.redmine_plugins/ -type f); do
            case $p in
                *.zip)
                    /usr/bin/unzip -q -d ./plugins $p
                    ;;
                *.tgz|*.tar.gz)
                    /usr/bin/tar xzf -C ./plugins $p
                    ;;
                *.tar|*.tar)
                    /usr/bin/tar xf -C ./plugins $p
                    ;;
                *)
                    echo "Unsupported $p"
                    exit 1
                    ;;
            esac
            
            p=$(basename $p)
            p=${p%.*}
            pn=$(echo $p | cut -d- -f1)
            test -d ./plugins/$pn || mv ./plugins/$p ./plugins/$pn
        done
        |EOT
    }

    # Secret
    # ---
    # TODO: shared secret in cluster

    if !$rake_secret and $cfweb::is_secondary {
        fail('There must be shared rake_secret set in cluster')
    }

    $secret = cfsystem::gen_pass("rake:${title}", 32, $rake_secret)

    # SMTP
    # ---
    $smtp_host = pick_default($smtp['host'], 'localhost')
    $smtp_port = pick_default($smtp['port'], 25)
    ensure_resource('cfnetwork::describe_service', "smtp_${smtp_port}", {
        server => "tcp/${smtp_port}",
    })
    cfnetwork::client_port { "any:smtp_${smtp_port}:${user}":
        user => $user,
    }

    # IMAP
    # ---
    if $imap and !$cfweb::is_secondary {
        if $imap['ssl'] {
            $imap_port = pick($imap['port'], 993)
            $imap_ssl_arg = '--ssl'
        } else {
            $imap_port = pick($imap['port'], 143)
            $imap_ssl_arg = ''
        }

        package { 'fetchmail': }
        -> file { "${site_dir}/.fetchmail.sh":
            owner   => $user,
            group   => $user,
            mode    => '0700',
            content => @("EOT"/$)
            #!/bin/dash
            
            cat >\${HOME}/.netrc <<EOC
            machine ${imap['host']}
            login ${imap['user']}
            password ${imap['password']}
            EOC
            
            exec /usr/bin/fetchmail \
                --timeout 15 \
                --silent \
                --all \
                --nokeep \
                -p IMAP --idle \
                --service ${imap_port} \
                --folder INBOX \
                ${imap_ssl_arg} \
                --mda 'cid tool exec bundler -- exec rake redmine:email:read RAILS_ENV="production"' \
                --limit 5242880 \
                --user '${imap['user']}' \
                '${imap['host']}'
            |EOT
        }
        -> Cfweb::App::Futoin[$title]

        $imap_ep_tune = [
            '"internal":1',
            '"minMemory":"128M"',
            '"maxMemory":"128M"',
            '"maxInstances":1',
        ].join(',')

        $imap_deploy_set = [
            "entrypoint fetchmail exe ../.fetchmail.sh '{${imap_ep_tune}}'",
        ]

        ensure_resource('cfnetwork::describe_service', "imap_${imap_port}", {
            server => "tcp/${imap_port}",
        })
        cfnetwork::client_port { "any:imap_${imap_port}:${user}":
            user => $user,
        }
    } else {
        $imap_deploy_set = []
    }

    # RMagick
    # ---
    ensure_resource('package', 'libmagickwand-dev')

    Package['libmagickwand-dev']
    -> Cfweb::Site[$title]

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
                
                CONF_DIR=.redmine_conf
                mkdir -p \$CONF_DIR

                cat >\$CONF_DIR/database.yml.tmp <<EOF
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
                mv -f \$CONF_DIR/database.yml.tmp \$CONF_DIR/database.yml
                
                # Secret
                #----
                cat >\$CONF_DIR/secrets.yml.tmp <<EOF
                ---
                production:
                    secret_key_base: ${secret}
                    secret_token: ${secret}
                EOF
                mv -f \$CONF_DIR/secrets.yml.tmp \$CONF_DIR/secrets.yml
                
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
                    which ${1} 2>/dev/null || true
                }

                #---
                cat >\$CONF_DIR/configuration.yml.tmp <<EOF
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
                mv -f \$CONF_DIR/configuration.yml.tmp \$CONF_DIR/configuration.yml
                
                #---
                cat >\$CONF_DIR/additional_environment.rb.tmp <<EOF
                require 'syslog/logger'
                
                config.logger = Syslog::Logger.new '${user}'
                config.log_level = :fatal
                EOF
                mv -f \$CONF_DIR/additional_environment.rb.tmp \$CONF_DIR/additional_environment.rb
                
                # Trigger re-deploy on change
                #---
                cid deploy set env redminePlugins "$(ls .redmine_plugins)"
                | EOT
                ,
            deploy_set    => [
                "env rubyVer ${ruby_ver}",
                'action prepare app-config database-config unpack-plugins app-install',
                [
                    'action app-config',
                    "'ln -sfn ../../.redmine_conf/configuration.yml config/'",
                    "'ln -sfn ../../.redmine_conf/additional_environment.rb config/'",
                    "'rm -f config/initializers/secret_token.rb'",
                    "'ln -sfn ../../.redmine_conf/secrets.yml config/'",
                    "'rm -rf tmp && ln -s ../.tmp tmp'",
                    "'@cid tool exec bundler -- remove puma'",
                ].join(' '),
                [
                    'action database-config',
                    "'ln -sfn ../../.redmine_conf/database.yml config/'",
                ].join(' '),
                [
                    'action app-install',
                    "'@cid build-dep ruby mysql-client imagemagick tzdata libxml2'",
                    "'@cid tool exec bundler -- install --without \"development test\"'",
                    "'@cid tool exec gem -- install puma'",
                ].join(' '),
                [
                    'action unpack-plugins',
                    '../.unpack-plugins.sh',
                ].join(' '),
                [
                    'action migrate',
                    "'@cid tool exec bundler -- exec rake db:migrate RAILS_ENV=production'",
                    "'@cid tool exec bundler -- exec rake redmine:load_default_data RAILS_ENV=production REDMINE_LANG=en'",
                    "'@cid tool exec bundler -- exec rake redmine:plugins:migrate RAILS_ENV=production'",
                ].join(' '),
                'persistent files log public/plugin_assets',
                'entrypoint web nginx public socketType=unix',
                'entrypoint app puma config.ru internal=1 connMemory=32M minMemory=256M',
                'webcfg root public',
                'webcfg main app',
                "webmount / '{\"static\":true}'",
            ] + $imap_deploy_set,
        }
    })

    # ---
    $plugins.each |$name, $params| {
        $impl = pick($params['impl'], 'cfwebapp::redmine::generic')
        $rsc_name = "${title}:${name}"

        create_resources(
            $impl,
            {
                $rsc_name => merge($params - 'impl', {
                    target_dir  => $plugins_zip_dir,
                    plugin_name => $name,
                })
            }
        )

        File[$plugins_zip_dir]
        -> Cfwebapp::Redmine::Generic[$rsc_name]
        -> Cfweb::Deploy[$title]
    }
}
