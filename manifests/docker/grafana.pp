#
# Copyright 2019 (c) Andrey Galkin
#

define cfwebapp::docker::grafana (
    Array[String[1]] $ifaces = ['local'],

    String[1] $server_name = $title,

    Hash[String[1],Any] $auto_cert = {},
    CfWeb::SharedCert $shared_cert = [],

    Boolean $is_backend = false,
    Boolean $robots_noindex = true,

    Integer[1] $memory_weight = 100,
    Integer[128] $memory_min = 512,
    Optional[Integer[128]] $memory_max = 512,

    Hash[String[1], Any] $site_params = {},
    CfWeb::DockerImage $image = {
        image => 'monitoringartist/grafana-xxl',
        image_tag => 'latest',
    },
    Cfnetwork::Port $target_port = 3000,
    String[1] $docker_network = 'prometheus',
    Hash $grafana_tune = {},
) {
    include cfweb::nginx

    $user = "app_${title}"
    $site_dir = "${cfweb::nginx::web_dir}/${user}"

    # ---
    file { "${site_dir}/persistent/data":
        ensure => directory,
        mode   => '0777',
    }

    $config_file = "${site_dir}/persistent/grafana.ini"

    $grafana_tune_all = deep_merge(
        {
            security => {
                disable_gravatar => true,
            },
            session => {
                provider => memory,
            },
            log => {
                mode => console,
                level => warn,
            },
            # Authentication is assumed on reverse-proxy level by default
            'auth.anonymous' => {
                enabled  => true,
                org_role => 'Admin',
            },
        },
        $grafana_tune
    ).map() |$sn, $sv| {
        (
            ["[${sn}]"] +
            $sv.map() |$k, $v| {
                "${k}=${v}"
            }
        )
    }.flatten().join("\n")

    file { $config_file:
        mode    => '0555',
        content => $grafana_tune_all
    }

    ensure_resource('cfweb::site', $title, $site_params + {
        server_name        => $server_name,
        ifaces             => $ifaces,
        auto_cert          => $auto_cert,
        shared_cert        => $shared_cert,
        is_backend         => $is_backend,
        robots_noindex     => $robots_noindex,
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
                'data'        => '/var/lib/grafana',
                'grafana.ini' => '/etc/grafana/grafana.ini',
            },
            network       => $docker_network,
            config_files  => [$config_file],
        },
    })
}
